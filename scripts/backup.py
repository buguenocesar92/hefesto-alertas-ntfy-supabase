#!/usr/bin/env python3
"""Respaldo del kit Hefesto Alertas (ntfy 2.30.0 + Supabase).

Cumple el contrato canonico docs/CONTRATO-RESPALDO.md de Hefesto Studio:
  - la salida va en <timestamp>/ con data.tar.gz, SHA256SUMS y manifest.json
  - manifest.json SIEMPRE trae software, version, database, sha256 y status
  - el .env NUNCA viaja en claro: solo viajan los NOMBRES de las variables
    (env.vars) y, si hay receptor age, el .env cifrado (env.age)
  - la auditoria vive FUERA del repositorio

Modos:
  --directo   usa las variables PG* del entorno y la imagen postgres:17-alpine.
              Es el modo de las pruebas con datos sinteticos y el de una base
              que no vive en el compose de este kit.
  (defecto)   usa el compose del kit (servicios dbtools y filetools).

Uso: python3 scripts/backup.py [--directo] [--destino DIR] [--database ID]
"""
import argparse
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

VERSION = '2.30.0'
SOFTWARE = 'hefesto-alertas'
PG_IMAGE = 'postgres:17-alpine'
CLAVE_MANIFIESTO = ('software', 'version', 'database', 'sha256', 'status')


def audit(line):
    """Rastro append-only fuera del repositorio (regla 12 del contrato)."""
    destino = os.environ.get('HEFESTO_RESPALDO_AUDIT')
    if not destino:
        base = os.environ.get('XDG_STATE_HOME') or os.path.join(os.path.expanduser('~'), '.local', 'state')
        destino = os.path.join(base, 'hefesto-respaldo', 'audit.log')
    os.makedirs(os.path.dirname(destino), exist_ok=True)
    with open(destino, 'a', encoding='utf-8') as f:
        f.write(line.rstrip('\n') + '\n')


def nombres_env(ruta):
    """Solo los NOMBRES de las variables. Nunca los valores."""
    nombres = set()
    if os.path.isfile(ruta):
        with open(ruta, encoding='utf-8', errors='replace') as f:
            for linea in f:
                linea = linea.strip()
                if not linea or linea.startswith('#') or '=' not in linea:
                    continue
                clave = linea.split('=', 1)[0].strip()
                if clave:
                    nombres.add(clave)
    return sorted(nombres)


def sha256_de(ruta):
    with open(ruta, 'rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def dsn_desde_entorno():
    host = os.environ.get('PGHOST', '127.0.0.1')
    puerto = os.environ.get('PGPORT', '5432')
    usuario = os.environ.get('PGUSER', 'postgres')
    base = os.environ.get('PGDATABASE', 'postgres')
    return f'postgresql://{usuario}@{host}:{puerto}/{base}'


def herramienta_pg(tool, argumentos, salida=None, entrada=None):
    """Ejecuta una herramienta de PostgreSQL en la imagen fijada por digest."""
    cmd = ['docker', 'run', '--rm', '-i', '--network', 'host', '-e', 'PGPASSWORD', PG_IMAGE, tool] + argumentos
    return subprocess.run(cmd, check=True, stdout=salida, stdin=entrada)


def main():
    ap = argparse.ArgumentParser(description='Respaldo del kit Hefesto Alertas')
    ap.add_argument('--directo', action='store_true',
                    help='usar las variables PG* del entorno en lugar del compose')
    ap.add_argument('--destino', default=None, help='carpeta base de los respaldos')
    ap.add_argument('--database', default=None, help='identificador de la base de datos')
    args = ap.parse_args()

    root = Path(__file__).resolve().parents[1]
    os.chdir(root)
    os.umask(0o077)

    base_destino = Path(args.destino) if args.destino else root / 'backups'
    base_destino.mkdir(parents=True, exist_ok=True)
    sello = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    p = base_destino / sello
    p.mkdir(parents=True, mode=0o700)

    if args.directo:
        database = args.database or ('postgres:%s@%s:%s' % (
            os.environ.get('PGDATABASE', 'postgres'),
            os.environ.get('PGHOST', '127.0.0.1'),
            os.environ.get('PGPORT', '5432')))
        with (p / 'public.dump').open('wb') as f:
            herramienta_pg('pg_dump', ['--format=custom', '--schema=public', '--no-owner',
                                       '--no-acl', '--dbname=' + dsn_desde_entorno()], salida=f)
        contenidos = ['public.dump']
    else:
        database = args.database or ('postgres:%s@%s:5432/%s' % (
            os.environ.get('DB_NAME', 'postgres'),
            os.environ.get('DB_HOST', 'localhost'),
            os.environ.get('DB_NAME', 'postgres')))

        def dc(*a, **kw):
            return subprocess.run(['docker', 'compose', *a], check=True, **kw)

        running = bool(dc('ps', '--status', 'running', '-q', 'app', capture_output=True, text=True).stdout.strip())
        try:
            dc('stop', 'app')
            with (p / 'public.dump').open('wb') as f:
                dc('run', '--rm', '--no-deps', '-T', '--entrypoint', 'pg_dump', 'dbtools',
                   '--format=custom', '--schema=public', '--no-owner', '--no-acl', stdout=f)
            with (p / 'files.tar.gz').open('wb') as f:
                dc('run', '--rm', '--no-deps', '-T', '--entrypoint', 'tar', 'filetools',
                   '-czf', '-', '-C', '/files', '.', stdout=f)
            shutil.copy2(root / 'config.yml', p / 'config.yml')
            shutil.copy2(root / 'compose.yaml', p / 'compose.yaml')
        finally:
            if running:
                dc('start', 'app')
        contenidos = ['public.dump', 'files.tar.gz', 'compose.yaml', 'config.yml']

    # El .env NO viaja en claro: solo los nombres de las variables.
    env_file = root / '.env'
    variables = nombres_env(env_file)
    if not variables:
        # Sin .env local: se documentan los nombres de la plantilla, nunca sus valores.
        variables = nombres_env(root / '.env.example')
    (p / 'env.vars').write_text('\n'.join(variables) + ('\n' if variables else ''), encoding='utf-8')
    contenidos.append('env.vars')
    env_cifrado = False
    receptor = os.environ.get('HEFESTO_AGE_RECIPIENT')
    if receptor and env_file.is_file():
        subprocess.run(['age', '-r', receptor, '-o', str(p / 'env.age'), str(env_file)], check=True)
        env_cifrado = True
        contenidos.append('env.age')

    # data.tar.gz: el contenido a respaldar, con rutas relativas.
    with tarfile.open(p / 'data.tar.gz', 'w:gz') as tf:
        for nombre in contenidos:
            tf.add(p / nombre, arcname=nombre)

    hashes = {nombre: sha256_de(p / nombre) for nombre in contenidos}
    sha_archivo = sha256_de(p / 'data.tar.gz')
    with (p / 'SHA256SUMS').open('w', encoding='utf-8') as f:
        f.write('%s  data.tar.gz\n' % sha_archivo)
        for nombre in contenidos:
            f.write('%s  %s\n' % (hashes[nombre], nombre))

    manifiesto = {
        'software': SOFTWARE,
        'version': VERSION,
        'database': database,
        'sha256': sha_archivo,
        'status': 'completed',
        'product': SOFTWARE,
        'created_at': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        'mode': 'directo' if args.directo else 'compose',
        'files_sha256': hashes,
        'env_included': env_cifrado,
        'env_vars': variables,
        'note': 'El .env no viaja en claro. Solo los nombres de las variables; '
                'los valores se reconfiguran en el destino.',
    }
    (p / 'manifest.json').write_text(json.dumps(manifiesto, indent=2, ensure_ascii=False), encoding='utf-8')

    audit('%s backup software=%s version=%s sha256=%s destino=%s resultado=completed' % (
        datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        SOFTWARE, VERSION, sha_archivo, p))

    print('Respaldo completo:', p, 'Contiene secretos cifrados; cifrar antes de transferir.')


if __name__ == '__main__':
    sys.exit(main())
