#!/bin/sh
set -eu
[ "$SUPABASE_DEDICATED_CONFIRMED" = true ] || { echo 'Confirme proyecto Supabase exclusivo'; exit 1; }
[ "$SUPABASE_DATA_API_DISABLED" = true ] || { echo 'Desactive Data API y confirme variable'; exit 1; }
# La CA solo es obligatoria cuando sslmode=verify-full.
# En cualquier otro modo (incluido disable) la conexión no exige certificado.
# PGSSLMODE es la variable que el contenedor recibe desde compose (el
# ancla &pg mapea DB_SSLMODE -> PGSSLMODE); leerla aquí mantiene el
# contrato con compose y deja a DB_SSLMODE como variable solo de UI.
if [ "${PGSSLMODE:-verify-full}" = "verify-full" ]; then
  [ -s "${PGSSLROOTCERT:-/certs/ca.crt}" ] || { echo 'Falta certificado CA'; exit 1; }
fi
export PGCONNECT_TIMEOUT=15
psql --no-psqlrc -v ON_ERROR_STOP=1 -f /opt/hefesto/preflight.sql
