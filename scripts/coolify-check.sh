#!/usr/bin/env bash
# scripts/coolify-check.sh
# Verifica que compose.yaml cumpla el contrato de despliegue en Coolify
# para este repo (bd: supabase-pg).
#
# Salida: 0 si pasa; distinto de 0 si falla. Cada motivo se imprime en
# una línea con el prefijo "servicio: motivo".
#
# No requiere Docker daemon: usa `docker compose config`, que solo parsea.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE="$REPO_ROOT/compose.yaml"
TMP_ENV="$(mktemp)"
TMP_ENV_DEFAULT="$(mktemp)"
trap 'rm -f "$TMP_ENV" "$TMP_ENV_DEFAULT"' EXIT

if [[ ! -f "$COMPOSE" ]]; then
  echo "compose.yaml no existe en $REPO_ROOT" >&2
  exit 2
fi

# Variables ${VAR} y ${VAR:[-+?!]valor} que aparecen en el compose
mapfile -t VARS < <(
  grep -oE '\$\{[A-Z_][A-Z_0-9]*(:[+\?\!\-][^}]*)?\}' "$COMPOSE" \
    | sed -E 's/^\$\{([A-Z_][A-Z_0-9]*).*/\1/' \
    | sort -u
)

# .env ficticio, sin secretos y sin caracteres que rompan el parseo
: > "$TMP_ENV"
for V in "${VARS[@]}"; do
  case "$V" in
    PUBLIC_URL|DB_HOST)
      echo "$V=https://ejemplo.invalid" >> "$TMP_ENV"
      ;;
    *)
      echo "$V=x123ficticio" >> "$TMP_ENV"
      ;;
  esac
done

# Parametrización específica para supabase-pg (el test fuerza estos valores)
echo "DB_SSLMODE=disable" >> "$TMP_ENV"
echo "DB_NAME=mvp_prueba" >> "$TMP_ENV"

# Renderizar sin profiles primero (para P2/P3 y como base de P1).
if ! RENDER=$(docker compose --project-directory "$REPO_ROOT" \
  -f "$COMPOSE" --env-file "$TMP_ENV" config --format json 2>/dev/null); then
  echo "ERROR: docker compose config no pudo renderizar:" >&2
  docker compose --project-directory "$REPO_ROOT" \
    -f "$COMPOSE" --env-file "$TMP_ENV" config --format json >&2 || true
  exit 2
fi

# Para P1 queremos ver TODOS los servicios, también los profile-gated.
# `docker compose config` no acepta --profile, así que enumeramos profiles
# y unimos los renders.
mapfile -t ALL_PROFILES < <(
  docker compose --project-directory "$REPO_ROOT" \
    -f "$COMPOSE" --env-file "$TMP_ENV" config --profiles 2>/dev/null \
    | grep -v '^$' || true
)

# Unimos los .services de cada profile sobre el render base.
RENDER_ALL="$RENDER"
for P in "${ALL_PROFILES[@]}"; do
  RENDER_P=$(docker compose --project-directory "$REPO_ROOT" \
    -f "$COMPOSE" --env-file "$TMP_ENV" --profile "$P" \
    config --format json 2>/dev/null) || continue
  RENDER_ALL=$(printf '%s\n%s\n' "$RENDER_ALL" "$RENDER_P" | jq -s '
    reduce .[] as $r ({}; .services = (.services + $r.services))
  ')
done

EXIT=0
fail() { echo "$1"; EXIT=1; }

# Servicio P1: iterar sobre TODOS los servicios (perfil-gated incluidos)
mapfile -t SERVICES < <(printf '%s' "$RENDER_ALL" | jq -r '.services | keys[]')

for SVC in "${SERVICES[@]}"; do
  SJSON=$(printf '%s' "$RENDER_ALL" | jq --arg s "$SVC" '.services[$s]')

  # Contrato punto 1: nada que salte Traefik ni dé poder sobre el host

  if [[ "$(printf '%s' "$SJSON" | jq -r '.ports // [] | length')" != "0" ]]; then
    fail "$SVC: expone 'ports' (contrato P1)"
  fi

  CNAME=$(printf '%s' "$SJSON" | jq -r '.container_name // empty')
  [[ -n "$CNAME" ]] && fail "$SVC: container_name fijo '$CNAME' (contrato P1)"

  PRIV=$(printf '%s' "$SJSON" | jq -r '.privileged // false')
  [[ "$PRIV" == "true" ]] && fail "$SVC: privileged habilitado (contrato P1)"

  CAPS=$(printf '%s' "$SJSON" | jq -r '.cap_add // [] | length')
  [[ "$CAPS" != "0" ]] && fail "$SVC: cap_add definido (contrato P1)"

  DEVS=$(printf '%s' "$SJSON" | jq -r '.devices // [] | length')
  [[ "$DEVS" != "0" ]] && fail "$SVC: devices definido (contrato P1)"

  NM=$(printf '%s' "$SJSON" | jq -r '.network_mode // empty')
  [[ -n "$NM" ]] && fail "$SVC: network_mode='$NM' comparte netns (contrato P1)"

  PIDV=$(printf '%s' "$SJSON" | jq -r '.pid // empty')
  [[ "$PIDV" == "host" ]] && fail "$SVC: pid=host (contrato P1)"

  IPCV=$(printf '%s' "$SJSON" | jq -r '.ipc // empty')
  [[ "$IPCV" == "host" ]] && fail "$SVC: ipc=host (contrato P1)"

  UNS=$(printf '%s' "$SJSON" | jq -r '.userns_mode // empty')
  [[ -n "$UNS" ]] && fail "$SVC: userns_mode='$UNS' (contrato P1)"

  UNCONF=$(printf '%s' "$SJSON" | jq -r \
    '.security_opt // [] | map(select(test("unconfined"))) | length')
  [[ "$UNCONF" != "0" ]] && fail "$SVC: security_opt unconfined (contrato P1)"

  DSOCK=$(printf '%s' "$SJSON" | jq -r \
    '[.volumes // [] | .[] | select(.source != null) | select(.source | test("docker\\.sock"))] | length')
  [[ "$DSOCK" != "0" ]] && fail "$SVC: bind a docker.sock (contrato P1)"

  # Binds absolutos: solo cuentan los que NO están bajo REPO_ROOT/.
  ABS=$(printf '%s' "$SJSON" | jq -r --arg repo "$REPO_ROOT" \
    '[.volumes // [] | .[] | select(.source != null) | select(.source | startswith("/")) | select(.source != $repo and (.source | startswith($repo + "/")) | not)] | length')
  [[ "$ABS" != "0" ]] && fail "$SVC: bind absoluto fuera del repo (contrato P1)"

  # env_file per-service: rechaza cualquier ruta definida a nivel de servicio
  ENVFILES=$(printf '%s' "$SJSON" | jq -r '.env_file // [] | length')
  if [[ "$ENVFILES" != "0" ]] && ! printf '%s' "$SJSON" | jq -e '.env_file == []' >/dev/null; then
    fail "$SVC: env_file a nivel de servicio (contrato P1)"
  fi
done

# Contrato punto 2: nombres estables sin forzar.
# El contrato prohíbe DECLARAR 'name:' en el compose. Docker pone el
# nombre del directorio como project name por defecto y Coolify usa el
# del proyecto; no podemos distinguirlos del render JSON, así que
# inspeccionamos el YAML fuente con un parser real (PyYAML).
P2_RESULT=$(python3 - "$COMPOSE" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    doc = yaml.safe_load(f) or {}
errs = []
if isinstance(doc, dict) and 'name' in doc:
    errs.append("'name:' declarado a nivel raíz")
volumes = doc.get('volumes') or {}
if isinstance(volumes, dict):
    for k, v in volumes.items():
        if isinstance(v, dict) and 'name' in v:
            errs.append(f"volumen '{k}' declara 'name:'")
networks = doc.get('networks') or {}
if isinstance(networks, dict):
    for k, v in networks.items():
        if isinstance(v, dict) and 'name' in v:
            errs.append(f"red '{k}' declara 'name:'")
print("\n".join(errs))
PY
)
if [[ -n "$P2_RESULT" ]]; then
  while IFS= read -r line; do
    fail "compose: $line (contrato P2)"
  done <<<"$P2_RESULT"
fi

# Contrato punto 3: para supabase-pg, DB_NAME= y DB_SSLMODE= parametrizables.
# Inspeccionamos los valores renderizados de las claves específicas.
DBN=$(printf '%s' "$RENDER" | jq -r '
  [.. | objects | select(has("PGDATABASE")) | .PGDATABASE] | first // empty')
if [[ "$DBN" != "mvp_prueba" ]]; then
  fail "compose: PGDATABASE renderizado es '$DBN', esperaba mvp_prueba (BD no parametrizable)"
fi

DSS=$(printf '%s' "$RENDER" | jq -r '
  [.. | objects | select(has("PGSSLMODE")) | .PGSSLMODE] | first // empty')
if [[ "$DSS" != "disable" ]]; then
  fail "compose: PGSSLMODE renderizado es '$DSS', esperaba disable (sslmode no parametrizable)"
fi

# Además exigimos que el compose fuente USE las variables (no valor hardcodeado)
grep -q '\${DB_NAME' "$COMPOSE" || fail "compose: no usa \${DB_NAME} (BD no parametrizable)"
grep -q '\${DB_SSLMODE' "$COMPOSE" || fail "compose: no usa \${DB_SSLMODE} (sslmode no parametrizable)"

# (a) El DSN de la app lleva /mvp_prueba? y sslmode=disable con el .env de prueba.
APP_DSN=$(printf '%s' "$RENDER" | jq -r '.services.app.environment.NTFY_DATABASE_URL // empty')
if [[ "$APP_DSN" != *"/mvp_prueba?"* ]]; then
  fail "app: NTFY_DATABASE_URL no contiene '/mvp_prueba?' (BD no llega al DSN)"
fi
if [[ "$APP_DSN" != *"sslmode=disable"* ]]; then
  fail "app: NTFY_DATABASE_URL no contiene 'sslmode=disable' (sslmode no llega al DSN)"
fi

# (b) El servicio preflight recibe PGSSLMODE=disable (es la variable que
# debe leer preflight.sh; anclar este contrato evita regresiones).
PRE_SSL=$(printf '%s' "$RENDER" | jq -r '.services.preflight.environment.PGSSLMODE // empty')
if [[ "$PRE_SSL" != "disable" ]]; then
  fail "preflight: PGSSLMODE es '$PRE_SSL', esperaba 'disable' (preflight.sh debe leer PGSSLMODE)"
fi

# (c) Segundo render SIN DB_SSLMODE, DB_NAME ni PGSSLROOTCERT en el .env.
# Garantiza que el uso original (sslmode=verify-full, CA por defecto, BD
# postgres) sigue intacto y no se rompió al parametrizar.
: > "$TMP_ENV_DEFAULT"
for V in "${VARS[@]}"; do
  case "$V" in
    PUBLIC_URL|DB_HOST)
      echo "$V=https://ejemplo.invalid" >> "$TMP_ENV_DEFAULT"
      ;;
    DB_SSLMODE|DB_NAME|PGSSLROOTCERT)
      # Sin definir: el render debe respetar los defaults del compose.
      ;;
    *)
      echo "$V=x123ficticio" >> "$TMP_ENV_DEFAULT"
      ;;
  esac
done

if RENDER_DEFAULT=$(docker compose --project-directory "$REPO_ROOT" \
  -f "$COMPOSE" --env-file "$TMP_ENV_DEFAULT" config --format json 2>/dev/null); then
  APP_DSN_DEF=$(printf '%s' "$RENDER_DEFAULT" | jq -r '.services.app.environment.NTFY_DATABASE_URL // empty')
  EXPECTED="/postgres?sslmode=verify-full&sslrootcert=/certs/ca.crt"
  if [[ "$APP_DSN_DEF" != *"$EXPECTED"* ]]; then
    fail "app: NTFY_DATABASE_URL (defaults) no contiene '$EXPECTED' (uso original roto): '$APP_DSN_DEF'"
  fi
else
  echo "ERROR: docker compose config (defaults) no pudo renderizar" >&2
  EXIT=2
fi

# (d) El servicio app tiene healthcheck definido (contrato punto 6).
APP_HC=$(printf '%s' "$RENDER" | jq -r '.services.app.healthcheck.test // empty')
if [[ -z "$APP_HC" ]]; then
  fail "app: healthcheck.test ausente (contrato P6)"
fi

exit "$EXIT"