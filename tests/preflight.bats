#!/usr/bin/env bats
# Preflight que corre DENTRO del contenedor (ops/preflight.sh).
# Se ejecuta con un psql simulado: lo que se prueba son las guardas, no la BD.

load helper

setup() {
  setup_repo
  FAKE_BIN="$TMP_ENV/bin"
  mkdir -p "$FAKE_BIN"
  printf '#!/bin/sh\nexit 0\n' > "$FAKE_BIN/psql"
  chmod +x "$FAKE_BIN/psql"
  PATH="$FAKE_BIN:$PATH"
  export PATH
}

teardown() { teardown_repo; }

@test "ops/preflight.sh aborta si el proyecto Supabase no se ha confirmado" {
  run env SUPABASE_DEDICATED_CONFIRMED=false SUPABASE_DATA_API_DISABLED=true \
    PGSSLMODE=disable sh "$REPO_ROOT/ops/preflight.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Confirme proyecto Supabase exclusivo"* ]]
}

@test "ops/preflight.sh aborta si la Data API sigue habilitada" {
  run env SUPABASE_DEDICATED_CONFIRMED=true SUPABASE_DATA_API_DISABLED=false \
    PGSSLMODE=disable sh "$REPO_ROOT/ops/preflight.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Desactive Data API"* ]]
}

@test "ops/preflight.sh exige la CA cuando sslmode es verify-full" {
  run env SUPABASE_DEDICATED_CONFIRMED=true SUPABASE_DATA_API_DISABLED=true \
    PGSSLMODE=verify-full PGSSLROOTCERT="$TMP_ENV/inexistente.crt" sh "$REPO_ROOT/ops/preflight.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Falta certificado CA"* ]]
}

@test "ops/preflight.sh no exige la CA cuando sslmode es disable" {
  run env SUPABASE_DEDICATED_CONFIRMED=true SUPABASE_DATA_API_DISABLED=true \
    PGSSLMODE=disable sh "$REPO_ROOT/ops/preflight.sh"
  [ "$status" -eq 0 ]
}
