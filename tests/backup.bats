#!/usr/bin/env bats
# Ciclo de respaldo con DATOS SINTETICOS y en aislamiento.
#
# Ningun contenedor de produccion, ningun volumen real, ninguna base real: un
# PostgreSQL efimero con una tabla de prueba, en un puerto local efimero.

load helper

setup() {
  setup_repo
  CONT="ntfy_pg_backup_$$"
  PG_PORT="$(arrancar_pg "$CONT" $(( 21000 + RANDOM % 20000 )))"
  export PG_HOST=127.0.0.1 PG_PORT
  esperar_pg "$CONT"
  docker exec "$CONT" psql -U postgres -q -c \
    "CREATE TABLE aviso_sintetico(id serial primary key, canal text, cuerpo text)" >/dev/null
  docker exec "$CONT" psql -U postgres -q -c \
    "INSERT INTO aviso_sintetico(canal,cuerpo) VALUES ('respaldo','demo')" >/dev/null
}

teardown() {
  docker rm -f "$CONT" >/dev/null 2>&1 || true
  teardown_repo
}

@test "el respaldo genera dump, manifiesto, SHA256SUMS y data.tar.gz" {
  run env PGHOST="$PG_HOST" PGPORT="$PG_PORT" PGUSER=postgres PGPASSWORD=clave-ficticia PGDATABASE=postgres \
    python3 "$REPO_ROOT/scripts/backup.py" --directo --destino "$TMP_ENV/backups"
  [ "$status" -eq 0 ]
  run_dir="$(ls -d "$TMP_ENV"/backups/*/ | head -n1)"
  [ -f "$run_dir/public.dump" ]
  [ -f "$run_dir/SHA256SUMS" ]
  [ -f "$run_dir/manifest.json" ]
  [ -f "$run_dir/data.tar.gz" ]
}

@test "el manifiesto trae las cinco claves obligatorias del contrato" {
  run env PGHOST="$PG_HOST" PGPORT="$PG_PORT" PGUSER=postgres PGPASSWORD=clave-ficticia PGDATABASE=postgres \
    python3 "$REPO_ROOT/scripts/backup.py" --directo --destino "$TMP_ENV/backups"
  [ "$status" -eq 0 ]
  run_dir="$(ls -d "$TMP_ENV"/backups/*/ | head -n1)"
  run python3 -c "import json,sys;m=json.load(open(sys.argv[1]));assert all(k in m for k in ('software','version','database','sha256','status'));assert m['status']=='completed'" "$run_dir/manifest.json"
  [ "$status" -eq 0 ]
}

@test "el .env no queda en claro dentro del respaldo" {
  run env PGHOST="$PG_HOST" PGPORT="$PG_PORT" PGUSER=postgres PGPASSWORD=clave-ficticia PGDATABASE=postgres \
    python3 "$REPO_ROOT/scripts/backup.py" --directo --destino "$TMP_ENV/backups"
  [ "$status" -eq 0 ]
  run_dir="$(ls -d "$TMP_ENV"/backups/*/ | head -n1)"
  [ ! -f "$run_dir/.env" ]
  run bash -c "tar -xzOf '$run_dir/data.tar.gz' 2>/dev/null | grep -q 'clave-ficticia'"
  [ "$status" -ne 0 ]
  run grep -q "DB_PASSWORD" "$run_dir/env.vars"
  [ "$status" -eq 0 ]
}

@test "el dump contiene la tabla sintetica" {
  run env PGHOST="$PG_HOST" PGPORT="$PG_PORT" PGUSER=postgres PGPASSWORD=clave-ficticia PGDATABASE=postgres \
    python3 "$REPO_ROOT/scripts/backup.py" --directo --destino "$TMP_ENV/backups"
  [ "$status" -eq 0 ]
  run_dir="$(ls -d "$TMP_ENV"/backups/*/ | head -n1)"
  run docker run --rm -i --network host -e PGPASSWORD=clave-ficticia postgres:17-alpine \
    pg_restore --list < "$run_dir/public.dump"
  [ "$status" -eq 0 ]
  [[ "$output" == *"aviso_sintetico"* ]]
}
