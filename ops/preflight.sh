#!/bin/sh
set -eu
[ "$SUPABASE_DEDICATED_CONFIRMED" = true ] || { echo 'Confirme proyecto Supabase exclusivo'; exit 1; }
[ "$SUPABASE_DATA_API_DISABLED" = true ] || { echo 'Desactive Data API y confirme variable'; exit 1; }
# La CA solo es obligatoria cuando sslmode=verify-full.
# En cualquier otro modo (incluido disable) la conexión no exige certificado.
if [ "${DB_SSLMODE:-verify-full}" = "verify-full" ]; then
  [ -s "${PGSSLROOTCERT:-/certs/ca.crt}" ] || { echo 'Falta certificado CA'; exit 1; }
fi
# Por defecto exigimos host *.supabase.co. Para hosts internos
# (BD propia, pruebas locales) usar DB_SSLMODE=disable o
# DB_ALLOW_INTERNAL_HOST=true.
if [ "${DB_ALLOW_INTERNAL_HOST:-false}" != "true" ] && [ "${DB_SSLMODE:-verify-full}" != "disable" ]; then
  case "$PGHOST" in
    *.supabase.co) ;;
    *) echo "Host no es Supabase (DB_HOST=$PGHOST). Use DB_SSLMODE=disable o DB_ALLOW_INTERNAL_HOST=true"; exit 1 ;;
  esac
fi
export PGCONNECT_TIMEOUT=15
psql --no-psqlrc -v ON_ERROR_STOP=1 -f /opt/hefesto/preflight.sql
