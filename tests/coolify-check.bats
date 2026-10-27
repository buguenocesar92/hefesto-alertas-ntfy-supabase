#!/usr/bin/env bats
# Contrato de scripts/coolify-check.sh.
# El script real no recibe argumentos: monta su propio .env ficticio. Los tests
# se ajustan al script, no al revés.

load helper

setup() { setup_repo; }

teardown() { teardown_repo; }

@test "coolify-check acepta el compose del repositorio" {
  run bash "$REPO_ROOT/scripts/coolify-check.sh"
  [ "$status" -eq 0 ]
}

@test "coolify-check falla con 1 si un servicio expone ports" {
  copia="$(repo_copy)"
  python3 - "$copia/compose.yaml" <<'PY'
import sys
p=sys.argv[1];t=open(p).read()
t=t.replace('    expose: ["8080"]','    expose: ["8080"]\n    ports: ["127.0.0.1:18080:8080"]')
open(p,'w').write(t)
PY
  run bash "$copia/scripts/coolify-check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ports"* ]]
  rm -rf "$copia"
}

@test "coolify-check falla con 1 si el compose declara name: en una red" {
  copia="$(repo_copy)"
  python3 - "$copia/compose.yaml" <<'PY'
import sys
p=sys.argv[1];t=open(p).read()
t=t.replace('networks:\n  alertas: {}\n  egreso: {}','networks:\n  alertas:\n    name: red-fija\n  egreso: {}')
open(p,'w').write(t)
PY
  run bash "$copia/scripts/coolify-check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"name:"* ]]
  rm -rf "$copia"
}

@test "coolify-check sale con 2 si no puede renderizar el compose" {
  copia="$(repo_copy)"
  printf 'services:\n  app:\n    image: [no-cerrado\n' > "$copia/compose.yaml"
  run bash "$copia/scripts/coolify-check.sh"
  [ "$status" -eq 2 ]
  rm -rf "$copia"
}
