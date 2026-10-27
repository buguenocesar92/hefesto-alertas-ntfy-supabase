#!/usr/bin/env python3
"""Restaura los adjuntos de ntfy desde un respaldo sobre un volumen vacio.

Cumple la regla 6 del contrato canonico docs/CONTRATO-RESPALDO.md: valida el
manifiesto, el checksum y las rutas del tar antes de tocar nada, y exige que el
volumen destino este vacio. Nunca vacia ni sobrescribe datos existentes.

Uso: python3 scripts/restore_files.py /ruta/respaldo
"""
import datetime
import hashlib
import json
import os
import subprocess
import sys
import tarfile
from pathlib import Path, PurePosixPath

VERSION = '2.30.0'
SOFTWARE = 'hefesto-alertas'
CLAVE_MANIFIESTO = ('software', 'version', 'database', 'sha256', 'status')


def audit(line):
    destino = os.environ.get('HEFESTO_RESPALDO_AUDIT')
    if not destino:
        base = os.environ.get('XDG_STATE_HOME') or os.path.join(os.path.expanduser('~'), '.local', 'state')
        destino = os.path.join(base, 'hefesto-respaldo', 'audit.log')
    os.makedirs(os.path.dirname(destino), exist_ok=True)
    with open(destino, 'a', encoding='utf-8') as f:
        f.write(line.rstrip('\n') + '\n')


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Uso: python3 scripts/restore_files.py /ruta/respaldo')
    p = Path(sys.argv[1]).resolve()
    root = Path(__file__).resolve().parents[1]
    os.chdir(root)

    if not (p / 'manifest.json').is_file():
        raise SystemExit('Falta manifest.json en el respaldo')
    m = json.loads((p / 'manifest.json').read_text(encoding='utf-8'))
    faltan = [k for k in CLAVE_MANIFIESTO if k not in m]
    if faltan:
        raise SystemExit('Manifiesto incompleto, faltan: ' + ', '.join(faltan))
    if m.get('software') != SOFTWARE:
        raise SystemExit('Producto incorrecto')
    if m.get('status') != 'completed' or m.get('version') != VERSION:
        raise SystemExit('Manifiesto invalido')

    a = p / 'files.tar.gz'
    if not a.is_file():
        raise SystemExit('Falta files.tar.gz en el respaldo')
    esperado = m.get('files_sha256', {}).get('files.tar.gz')
    with a.open('rb') as f:
        real = hashlib.file_digest(f, 'sha256').hexdigest()
    if esperado and real != esperado:
        raise SystemExit('Hash incorrecto')

    with tarfile.open(a) as tf:
        seen = set()
        for member in tf:
            name = PurePosixPath(member.name)
            if name.is_absolute() or '..' in name.parts or not (member.isfile() or member.isdir()) or str(name) in seen:
                raise SystemExit('Ruta/tipo no admitido')
            seen.add(str(name))

    def dc(*a, **kw):
        return subprocess.run(['docker', 'compose', *a], check=True, **kw)

    if dc('ps', '--status', 'running', '-q', 'app', capture_output=True, text=True).stdout.strip():
        raise SystemExit('Detener app')
    found = dc('run', '--rm', '--no-deps', '-T', '--entrypoint', 'find', 'filetools', '/files',
               '-mindepth', '1', '-maxdepth', '1', capture_output=True, text=True).stdout.strip()
    if found:
        raise SystemExit('Volumen no vacio; no se sobrescribe')
    with a.open('rb') as f:
        dc('run', '--rm', '--no-deps', '-T', '--user', '0', '--entrypoint', 'tar', 'filetools',
           '-xzf', '-', '-C', '/files', stdin=f)
    dc('run', '--rm', '--no-deps', 'permissions')
    audit('%s restore origen=%s sha256=%s destino=volumen-files resultado=ok' % (
        datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        p, m.get('sha256', 'desconocido')))
    print('Archivos restaurados y propietario ajustado.')


if __name__ == '__main__':
    sys.exit(main())
