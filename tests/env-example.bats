#!/usr/bin/env bats
# .env.example debe cubrir todas las variables que el compose exige.

load helper

setup() { setup_repo; }

teardown() { teardown_repo; }

@test "todo placeholder del compose aparece en .env.example" {
  for v in $(grep -oE '\$\{[A-Z_]+' "$REPO_ROOT/compose.yaml" | sed 's/\${//' | sort -u); do
    run grep -qE "^${v}=" "$REPO_ROOT/.env.example"
    [ "$status" -eq 0 ] || { echo "Falta $v en .env.example"; return 1; }
  done
}

@test ".env.example no contiene secretos: las sensibles son placeholders" {
  run python3 - "$REPO_ROOT/.env.example" <<'PY'
import re,sys
permitidos=re.compile(r'^(REEMPLAZAR|GENERAR[A-Z0-9_]*|)\S*$')
prohibido=re.compile(r'(PASSWORD|SECRET|PRIVATE_KEY|TOKEN)')
malas=[]
for linea in open(sys.argv[1]):
    linea=linea.strip()
    if not linea or linea.startswith('#') or '=' not in linea:
        continue
    clave,valor=linea.split('=',1)
    if not prohibido.search(clave):
        continue
    if valor and not permitidos.match(valor):
        malas.append(clave)
if malas:
    print("valores que parecen secretos reales: "+", ".join(malas))
    raise SystemExit(1)
PY
  [ "$status" -eq 0 ]
}

@test ".env.example documenta las variables del contrato" {
  for v in DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD DB_SSLMODE PGSSLROOTCERT \
           PUBLIC_URL VOLUME_PREFIX SUPABASE_DEDICATED_CONFIRMED SUPABASE_DATA_API_DISABLED \
           WEB_PUSH_PUBLIC_KEY WEB_PUSH_PRIVATE_KEY WEB_PUSH_EMAIL_ADDRESS \
           SMTP_ADDRESS SMTP_USERNAME SMTP_PASSWORD; do
    run grep -qE "^${v}=" "$REPO_ROOT/.env.example"
    [ "$status" -eq 0 ] || { echo "Falta $v en .env.example"; return 1; }
  done
}
