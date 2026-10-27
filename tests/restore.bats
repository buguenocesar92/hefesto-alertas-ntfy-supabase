#!/usr/bin/env bats
# Ciclo de restauracion con DATOS SINTETICOS y en aislamiento.
#
# El respaldo se hace contra un PostgreSQL efimero con una tabla de prueba y se
# restaura contra OTRO PostgreSQL efimero, vacio. Ninguna base real, ningun
# volumen real.

load helper

setup() {
  setup_repo
  ORIGEN="ntfy_pg_origen_$$"
  DESTINO="ntfy_pg_destino_$$"
  PUERTO_ORIGEN="$(arrancar_pg "$ORIGEN" $(( 41000 + RANDOM % 10000 )))"
  PUERTO_DESTINO="$(arrancar_pg "$DESTINO" $(( 51000 + RANDOM % 10000 )))"
  esperar_pg "$ORIGEN"
  esperar_pg "$DESTINO"
  docker exec "$ORIGEN" psql -U postgres -q -c \
    "CREATE TABLE aviso_sintetico(id serial primary key, canal text, cuerpo text)" >/dev/null
  docker exec "$ORIGEN" psql -U postgres -q -c \
    "INSERT INTO aviso_sintetico(canal,cuerpo) VALUES ('respaldo','demo')" >/dev/null
  run env PGHOST=127.0.0.1 PGPORT="$PUERTO_ORIGEN" PGUSER=postgres PGPASSWORD=clave-ficticia PGDATABASE=postgres \
    python3 "$REPO_ROOT/scripts/backup.py" --directo --destino "$TMP_ENV/backups"
  [ "$status" -eq 0 ]
  RUN_DIR="$(ls -d "$TMP_ENV"/backups/*/ | head -n1)"
}

teardown() {
  docker rm -f "$ORIGEN" "$DESTINO" >/dev/null 2>&1 || true
  teardown_repo
}

@test "restore_db reconstruye la tabla sintetica en una base vacia" {
  run env PGHOST=127.0.0.1 PGPORT="$PUERTO_DESTINO" PGUSER=postgres PGPASSWORD=clave-ficticia PGDATABASE=postgres \
    python3 "$REPO_ROOT/scripts/restore_db.py" "$RUN_DIR" --directo
  [ "$status" -eq 0 ]
  run docker exec "$DESTINO" psql -U postgres -tAc "SELECT count(*) FROM aviso_sintetico"
  [ "$output" = "1" ]
}

@test "restore_db rechaza un destino que ya tiene tablas" {
  docker exec "$DESTINO" psql -U postgres -q -c "CREATE TABLE ya_existe(id int)" >/dev/null
  run env PGHOST=127.0.0.1 PGPORT="$PUERTO_DESTINO" PGUSER=postgres PGPASSWORD=clave-ficticia PGDATABASE=postgres \
    python3 "$REPO_ROOT/scripts/restore_db.py" "$RUN_DIR" --directo
  [ "$status" -ne 0 ]
  [[ "$output" == *"public no esta vacio"* ]]
}

@test "restore_db rechaza un manifiesto invalido antes de tocar el destino" {
  python3 - "$RUN_DIR/manifest.json" <<'PY'
import json,sys
p=sys.argv[1];m=json.load(open(p));m['status']='failed';json.dump(m,open(p,'w'))
PY
  run env PGHOST=127.0.0.1 PGPORT="$PUERTO_DESTINO" PGUSER=postgres PGPASSWORD=clave-ficticia PGDATABASE=postgres \
    python3 "$REPO_ROOT/scripts/restore_db.py" "$RUN_DIR" --directo
  [ "$status" -ne 0 ]
  run docker exec "$DESTINO" psql -U postgres -tAc "SELECT count(*) FROM pg_tables WHERE schemaname='public'"
  [ "$output" = "0" ]
}

@test "restore_db rechaza un manifiesto al que le faltan claves" {
  python3 - "$RUN_DIR/manifest.json" <<'PY'
import json,sys
p=sys.argv[1];m=json.load(open(p));m.pop('database');json.dump(m,open(p,'w'))
PY
  run env PGHOST=127.0.0.1 PGPORT="$PUERTO_DESTINO" PGUSER=postgres PGPASSWORD=clave-ficticia PGDATABASE=postgres \
    python3 "$REPO_ROOT/scripts/restore_db.py" "$RUN_DIR" --directo
  [ "$status" -ne 0 ]
  [[ "$output" == *"database"* ]]
}
