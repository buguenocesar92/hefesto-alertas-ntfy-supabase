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
trap 'rm -f "$TMP_ENV"' EXIT

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

# Contrato punto 2: nombres estables sin forzar
RNAME=$(printf '%s' "$RENDER" | jq -r '.name // empty')
[[ -n "$RNAME" ]] && fail "compose: name raíz fijo '$RNAME' (contrato P2)"

NETNAMES=$(printf '%s' "$RENDER" | jq -r \
  '[.networks // {} | to_entries[]? | select(.value.name != null) | .key + ":" + .value.name] | join(",")')
[[ -n "$NETNAMES" ]] && fail "compose: redes con name fijo '$NETNAMES' (contrato P2)"

VOLNAMES=$(printf '%s' "$RENDER" | jq -r \
  '[.volumes // {} | to_entries[]? | select(.value.name != null) | .key + ":" + .value.name] | join(",")')
[[ -n "$VOLNAMES" ]] && fail "compose: volúmenes con name fijo '$VOLNAMES' (contrato P2)"

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

exit "$EXIT"