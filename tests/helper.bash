# Ayudas comunes de las pruebas bats del kit Hefesto Alertas.
# Ninguna prueba toca la base real, un volumen real ni un contenedor de
# produccion: todo se hace en un directorio temporal.

setup_repo() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export REPO_ROOT
  TMP_ENV="$(mktemp -d)"
  export TMP_ENV
  cp "$REPO_ROOT/.env.example" "$TMP_ENV/.env"
  # .env de pruebas: valores ficticios, jamas secretos reales.
  sed -i 's|^DB_PASSWORD=.*|DB_PASSWORD=clave-ficticia-de-prueba|' "$TMP_ENV/.env"
  sed -i 's|^PUBLIC_URL=.*|PUBLIC_URL=https://alertas.example.invalid|' "$TMP_ENV/.env"
  export BATS_TEST_TMPDIR_REAL="${TMP_ENV}"
}

teardown_repo() {
  if [[ -n "${TMP_ENV:-}" && -d "${TMP_ENV}" ]]; then rm -rf "${TMP_ENV}"; fi
  return 0
}

# Copia el repositorio a un directorio temporal para poder romper el compose
# sin tocar el original.
repo_copy() {
  COPIED="$(mktemp -d)"
  cp -a "$REPO_ROOT/." "$COPIED/"
  echo "$COPIED"
}

# Arranque de un PostgreSQL efimero para las pruebas con datos sinteticos.
# Ningun contenedor real, ningun volumen real, ningun puerto al exterior.
arrancar_pg() { # <contenedor> <puerto_inicial>; imprime el puerto elegido
  local c="$1" p="$2"
  for _ in 1 2 3 4 5 6 7 8; do
    if docker run -d --name "$c" \
      -e POSTGRES_PASSWORD=clave-ficticia \
      -e POSTGRES_DB=postgres \
      -p "127.0.0.1:${p}:5432" \
      postgres:17-alpine >/dev/null 2>&1; then
      echo "$p"
      return 0
    fi
    p=$(( p + 1 ))
  done
  return 1
}

esperar_pg() { # <contenedor>
  local c="$1"
  for _ in $(seq 1 80); do
    if docker exec "$c" psql -U postgres -tAc "SELECT 1" >/dev/null 2>&1; then return 0; fi
    sleep 0.5
  done
  return 1
}
