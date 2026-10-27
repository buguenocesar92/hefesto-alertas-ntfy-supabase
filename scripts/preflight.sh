#!/usr/bin/env bash
# Validacion estatica del kit Hefesto Alertas.
# No abre red, no arranca servicios y no toca la base de datos: solo mira
# ficheros. Es el preflight que puede correr el operador antes de desplegar.
#
# Uso: scripts/preflight.sh [--env FICHERO]
#   --env FICHERO   fichero de variables a validar (por defecto .env)
#
# Salida: 0 -> correcto; 1 -> problemas; 2 -> error de uso.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env"
err=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_FILE="${2:-}"; shift 2;;
    -h|--help) sed -n '2,12p' "$0"; exit 0;;
    *) echo "argumento desconocido: $1" >&2; exit 2;;
  esac
done

[[ -f "$ENV_FILE" ]] || {
  if [[ "$ENV_FILE" == "$ROOT/.env" && -f "$ROOT/.env.example" ]]; then
    # Sin .env local se valida la PLANTILLA: el despliegue real se comprueba
    # con --env /etc/hefesto/<kit>.env.
    echo "Aviso: no hay .env en el repositorio; se valida la plantilla .env.example"
    ENV_FILE="$ROOT/.env.example"
  else
    echo "no existe el fichero de variables: $ENV_FILE" >&2
    exit 2
  fi
}

# Con .env.example se valida la PLANTILLA; con un .env real se valida el
# despliegue, y ahi si se exige la CA y los permisos 600.
es_ejemplo=0
if [[ "$(basename "$ENV_FILE")" == ".env.example" ]]; then es_ejemplo=1; fi
[[ "$ENV_FILE" == "$ROOT/.env" ]] && es_ejemplo=0

valor() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -n1 | cut -d= -f2- || true; }
req() {
  local v="$1" got
  got="$(valor "$v")"
  [[ -n "$got" ]] || { echo "Falta $v en $(basename "$ENV_FILE")"; err=1; }
}

for v in PUBLIC_URL DB_HOST DB_USER DB_PASSWORD; do req "$v"; done

url="$(valor PUBLIC_URL)"
case "$url" in
  https://*) ;;
  *) echo "PUBLIC_URL debe ser https"; err=1;;
esac

if [[ "$es_ejemplo" -eq 0 ]]; then
  permisos="$(stat -c '%a' "$ENV_FILE" 2>/dev/null || echo "")"
  if [[ -n "$permisos" && "$permisos" != "600" ]]; then
    echo "$(basename "$ENV_FILE") debe tener permisos 600 (actual: $permisos)"; err=1
  fi
  modo="$(valor DB_SSLMODE)"; modo="${modo:-verify-full}"
  if [[ "$modo" = "verify-full" && ! -s "$ROOT/certs/ca.crt" ]]; then
    echo "Falta certs/ca.crt para DB_SSLMODE=verify-full (ver docs/SECRETS.md)"; err=1
  fi
  if [[ "$modo" != "verify-full" && "$modo" != "require" && "$modo" != "disable" ]]; then
    echo "DB_SSLMODE debe ser verify-full, require o disable (actual: $modo)"; err=1
  fi
  for v in SUPABASE_DEDICATED_CONFIRMED SUPABASE_DATA_API_DISABLED; do
    if [[ "$(valor "$v")" != "true" ]]; then
      echo "$v debe ser true: el preflight del contenedor aborta si no"; err=1
    fi
  done
else
  modo="$(valor DB_SSLMODE)"; modo="${modo:-verify-full}"
  if [[ "$modo" = "verify-full" && ! -s "$ROOT/certs/ca.crt" ]]; then
    echo "Aviso: certs/ca.crt no esta todavia (la aporta el operador desde el panel de Supabase)"
  fi
fi

if [[ "$err" -eq 0 ]]; then echo "preflight estatico OK ($(basename "$ENV_FILE"))"; fi
exit "$err"
