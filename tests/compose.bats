#!/usr/bin/env bats
# Contrato del compose: imagenes fijadas por digest y redes explicitas.

load helper

setup() { setup_repo; }

teardown() { teardown_repo; }

@test "ninguna imagen auxiliar queda sin digest" {
  run grep -nE 'image:[[:space:]]*postgres:17-alpine[[:space:]]*$' "$REPO_ROOT/compose.yaml"
  [ -z "$output" ]
}

@test "todas las imágenes del compose están fijadas por digest" {
  run bash -c "grep -oE 'image: .*' '$REPO_ROOT/compose.yaml' | grep -vc '@sha256:'"
  [ "$output" = "0" ]
}

@test "el compose declara redes explicitas" {
  run grep -c '^networks:' "$REPO_ROOT/compose.yaml"
  [ "$output" -ge 1 ]
  run grep -c 'networks: \[alertas' "$REPO_ROOT/compose.yaml"
  [ "$output" -ge 1 ]
}

@test "el compose renderiza con las variables del contrato" {
  run env DB_HOST=ejemplo.invalid DB_PASSWORD=x123 PUBLIC_URL=https://ejemplo.invalid \
    docker compose -f "$REPO_ROOT/compose.yaml" config --quiet
  [ "$status" -eq 0 ]
}

@test "el compose no renderiza sin DB_PASSWORD" {
  run env -u DB_PASSWORD DB_HOST=ejemplo.invalid PUBLIC_URL=https://ejemplo.invalid \
    docker compose -f "$REPO_ROOT/compose.yaml" config --quiet
  [ "$status" -ne 0 ]
  [[ "$output" == *"DB_PASSWORD"* ]]
}

@test "el compose declara la red egreso para la app" {
  run python3 -c "import yaml,sys;d=yaml.safe_load(open(sys.argv[1]));assert 'egreso' in d['services']['app']['networks'];assert 'alertas' in d['services']['app']['networks']" "$REPO_ROOT/compose.yaml"
  [ "$status" -eq 0 ]
}
