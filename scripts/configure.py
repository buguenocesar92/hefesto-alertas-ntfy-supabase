#!/usr/bin/env python3
import os,secrets
from pathlib import Path
root=Path(__file__).resolve().parents[1]
s=(root/'.env.example').read_text().replace('DB_PASSWORD=GENERAR','DB_PASSWORD='+secrets.token_hex(32))
fd=os.open(root/'.env',os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'w') as f:f.write(s)
print('.env creado. Editar conexión y dominio sin publicar secretos.')
