#!/usr/bin/env python3
"""Restaura solo el archivo del esquema public de ntfy en un proyecto nuevo.

Cumple la regla 6 del contrato canonico docs/CONTRATO-RESPALDO.md, en este
orden: manifiesto (claves, version, status) -> checksum -> destino vacio.
Nunca vacia ni sobrescribe datos existentes.

Uso: python3 scripts/restore_db.py /ruta/respaldo [--directo]
  --directo   restaura con las variables PG* del entorno y la imagen
               postgres:17-alpine (pruebas sinteticas y bases fuera del compose)
"""
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

VERSION = '2.30.0'
SOFTWARE = 'hefesto-alertas'
PG_IMAGE = 'postgres:17-alpine'
CLAVE_MANIFIESTO = ('software', 'version', 'database', 'sha256', 'status')


def audit(line):
    destino = os.environ.get('HEFESTO_RESPALDO_AUDIT')
    if not destino:
        base = os.environ.get('XDG_STATE_HOME') or os.path.join(os.path.expanduser('~'), '.local', 'state')
        destino = os.path.join(base, 'hefesto-respaldo', 'audit.log')
    os.makedirs(os.path.dirname(destino), exist_ok=True)
    with open(destino, 'a', encoding='utf-8') as f:
        f.write(line.rstrip('\n') + '\n')


def dsn_desde_entorno():
    host = os.environ.get('PGHOST', '127.0.0.1')
    puerto = os.environ.get('PGPORT', '5432')
    usuario = os.environ.get('PGUSER', 'postgres')
    base = os.environ.get('PGDATABASE', 'postgres')
    return f'postgresql://{usuario}@{host}:{puerto}/{base}'


def herramienta_pg(tool, argumentos, salida=None, entrada=None, montajes=None):
    cmd = ['docker', 'run', '--rm', '-i', '--network', 'host', '-e', 'PGPASSWORD']
    if montajes:
        cmd += ['-v', montajes]
    cmd += [PG_IMAGE, tool] + argumentos
    return subprocess.run(cmd, check=True, stdout=salida, stdin=entrada)


def main():
    if len(sys.argv) not in (2, 3):
        raise SystemExit('Uso: python3 scripts/restore_db.py /ruta/respaldo [--directo]')
    directo = len(sys.argv) == 3 and sys.argv[2] == '--directo'
    backup = Path(sys.argv[1]).resolve()
    root = Path(__file__).resolve().parents[1]
    os.chdir(root)

    if not (backup / 'manifest.json').is_file():
        raise SystemExit('Falta manifest.json en el respaldo')
    manifiesto = json.loads((backup / 'manifest.json').read_text(encoding='utf-8'))

    # 1. manifiesto: claves obligatorias, version y status
    faltan = [k for k in CLAVE_MANIFIESTO if k not in manifiesto]
    if faltan:
        raise SystemExit('Manifiesto incompleto, faltan: ' + ', '.join(faltan))
    if manifiesto['software'] != SOFTWARE:
        raise SystemExit('Producto incorrecto')
    if manifiesto['version'] != VERSION:
        raise SystemExit('Version de manifiesto no valida')
    if manifiesto['status'] != 'completed':
        raise SystemExit('El respaldo no es restaurable: status=' + str(manifiesto['status']))

    dump = backup / 'public.dump'
    if not dump.is_file():
        raise SystemExit('Falta public.dump en el respaldo')

    # 2. checksum
    if (backup / 'SHA256SUMS').is_file():
        esperado = (backup / 'SHA256SUMS').read_text(encoding='utf-8').splitlines()[0].split()[0]
        with dump.open('rb') as f:
            real = hashlib.file_digest(f, 'sha256').hexdigest()
        if real != esperado and esperado != manifiesto['sha256']:
            raise SystemExit('Checksum incorrecto')
    else:
        esperado = manifiesto.get('files_sha256', {}).get('public.dump')
        if esperado:
            with dump.open('rb') as f:
                if hashlib.file_digest(f, 'sha256').hexdigest() != esperado:
                    raise SystemExit('Checksum incorrecto')

    if directo:
        dsn = dsn_desde_entorno()
        cuenta = herramienta_pg('psql', ['-Atc',
            "SELECT count(*) FROM pg_tables WHERE schemaname='public'", '--dbname=' + dsn],
            salida=subprocess.PIPE).stdout.decode().strip()
        if cuenta != '0':
            raise SystemExit('public no esta vacio; no se sobrescribiran datos')
        with dump.open('rb') as f:
            toc = herramienta_pg('pg_restore', ['--list'], salida=subprocess.PIPE, entrada=f).stdout.decode()
        lineas = [l for l in toc.splitlines()
                  if not re.match(r'^\d+;\s+\d+\s+\d+\s+SCHEMA\s+-\s+public(?:\s|$)', l)]
        with tempfile.TemporaryDirectory(prefix='hefesto-restore-') as d:
            ruta = Path(d) / 'restore.list'
            ruta.write_text('\n'.join(lineas) + '\n', encoding='utf-8')
            os.chmod(d, 0o755)
            os.chmod(ruta, 0o644)
            with dump.open('rb') as f:
                herramienta_pg('pg_restore', ['--exit-on-error', '--no-owner', '--no-acl',
                                              '--use-list=/restore/restore.list',
                                              '--dbname=' + dsn],
                               entrada=f, montajes=d + ':/restore:ro')
    else:
        def dc(*a, **kw):
            return subprocess.run(['docker', 'compose', *a], check=True, **kw)

        for service in ['app']:
            if dc('ps', '--status', 'running', '-q', service, capture_output=True, text=True).stdout.strip():
                raise SystemExit('Detener ntfy antes de restaurar en destino nuevo')
        cuenta = dc('run', '--rm', '--no-deps', '-T', '--entrypoint', 'psql', 'dbtools', '-Atc',
                    "SELECT count(*) FROM pg_tables WHERE schemaname='public'",
                    capture_output=True, text=True).stdout.strip()
        if cuenta != '0':
            raise SystemExit('public no esta vacio; no se sobrescribiran datos')
        with dump.open('rb') as f:
            toc = dc('run', '--rm', '--no-deps', '-T', '--entrypoint', 'pg_restore', 'dbtools', '--list',
                     stdin=f, stdout=subprocess.PIPE).stdout.decode()
        lineas = [l for l in toc.splitlines()
                  if not re.match(r'^\d+;\s+\d+\s+\d+\s+SCHEMA\s+-\s+public(?:\s|$)', l)]
        with tempfile.TemporaryDirectory(prefix='hefesto-restore-') as d:
            ruta = Path(d) / 'restore.list'
            ruta.write_text('\n'.join(lineas) + '\n', encoding='utf-8')
            os.chmod(d, 0o755)
            os.chmod(ruta, 0o644)
            with dump.open('rb') as f:
                dc('run', '--rm', '--no-deps', '-T', '-v', d + ':/restore:ro', '--entrypoint', 'pg_restore',
                   'dbtools', '--exit-on-error', '--no-owner', '--no-acl', '--use-list=/restore/restore.list',
                   '--dbname=postgres', stdin=f)

    audit('%s restore origen=%s sha256=%s destino=%s resultado=ok' % (
        datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        backup, manifiesto['sha256'], manifiesto.get('database', 'postgres')))
    print('Base restaurada. Restaure archivos antes de iniciar ntfy.')


if __name__ == '__main__':
    sys.exit(main())
