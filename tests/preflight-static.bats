#!/usr/bin/env bats
# Preflight estatico del kit (scripts/preflight.sh): no abre red ni arranca nada.

load helper

setup() { setup_repo; }

teardown() { teardown_repo; }

@test "el preflight estatico acepta la plantilla .env.example" {
  run bash "$REPO_ROOT/scripts/preflight.sh" --env "$REPO_ROOT/.env.example"
  [ "$status" -eq 0 ]
}

@test "el preflight estatico rechaza un .env sin PUBLIC_URL" {
  sed -i '/^PUBLIC_URL=/d' "$TMP_ENV/.env"
  run bash "$REPO_ROOT/scripts/preflight.sh" --env "$TMP_ENV/.env"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PUBLIC_URL"* ]]
}

@test "el preflight estatico rechaza un PUBLIC_URL que no sea https" {
  sed -i 's|^PUBLIC_URL=.*|PUBLIC_URL=http://alertas.example.com|' "$TMP_ENV/.env"
  run bash "$REPO_ROOT/scripts/preflight.sh" --env "$TMP_ENV/.env"
  [ "$status" -eq 1 ]
  [[ "$output" == *"https"* ]]
}

@test "el preflight estatico rechaza un .env real sin la CA en verify-full" {
  chmod 600 "$TMP_ENV/.env"
  run bash "$REPO_ROOT/scripts/preflight.sh" --env "$TMP_ENV/.env"
  [ "$status" -eq 1 ]
  [[ "$output" == *"certs/ca.crt"* ]]
}

@test "el preflight estatico rechaza un .env real con permisos abiertos" {
  chmod 644 "$TMP_ENV/.env"
  run bash "$REPO_ROOT/scripts/preflight.sh" --env "$TMP_ENV/.env"
  [ "$status" -eq 1 ]
  [[ "$output" == *"600"* ]]
}

@test "el preflight estatico sale con 2 si el fichero no existe" {
  run bash "$REPO_ROOT/scripts/preflight.sh" --env "$TMP_ENV/no-existe.env"
  [ "$status" -eq 2 ]
}
