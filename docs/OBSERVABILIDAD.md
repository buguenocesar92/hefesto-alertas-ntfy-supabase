# Observabilidad del kit Hefesto Alertas

## 1. Sonda HTTP

El servicio `app` expone `8080` **internamente** (`expose`, no `ports`). La
sonda va por el proxy externo, contra la URL publica:

```bash
curl -fsS https://alertas.example.com/v1/health | jq -e '.healthy == true'
```

Frecuencia: cada 30 s. El `healthcheck` interno del contenedor ya existe
(`compose.yaml`) y cubre el arranque; la sonda externa cubre el camino completo
(proxy, TLS, DNS).

## 2. Alertas

| Sintoma | Umbral | Actuacion |
| --- | --- | --- |
| Reinicios del contenedor `app` | mas de 3 por hora | revisar `docker compose logs app` y OOM |
| Sonda HTTP | 3 fallos seguidos | el proxy no llega a ntfy |
| Disco del host | mas del 85 % | los adjuntos viven en el volumen `files` |
| Respaldos | sin uno nuevo en 26 h | reejecutar `scripts/backup.py` |
| Preflight | el servicio `preflight` sale con codigo distinto de 0 | el despliegue no arranco: revisar `ops/preflight.sh` |

## 3. Rotacion de logs

```yaml
services:
  app:
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

Con `max-size: 10m` y `max-file: 3` el contenedor mantiene 30 MB de logs y no
llena el disco.

## 4. Logs de `publish.py`

`scripts/publish.py` escribe en la salida estandar. El destino lo decide el
servicio que lo invoca:

- En Coolify: el log del servicio, con la rotacion de arriba.
- En cron: `>> /var/log/hefesto-alertas-publish.log 2>&1` con `logrotate`.
- En el contenedor: `docker compose logs -f app`.

Los mensajes de error **no** incluyen tokens ni URLs firmadas.

## 5. Respaldos

| Que | Como | Frecuencia | Prueba de restauracion |
| --- | --- | --- | --- |
| Base de datos de Supabase | `scripts/backup.py` (pg_dump del esquema `public`) | diaria | `scripts/restore_db.py` contra una base efimera + conteo de filas de una tabla sintetica (`tests/backup.bats`) |
| Volumen `files` (adjuntos) | `scripts/backup.py` (export del volumen) | diaria | `scripts/restore_files.py` sobre volumen vacio + comparacion de hashes (`tests/restore.bats`) |

El ciclo completo se prueba con **datos sinteticos** en `tests/backup.bats` y
`tests/restore.bats`: ningun contenedor de produccion, ningun volumen real.

## 6. Verificacion de restauracion

Trimestral, contra una base de destino **nueva y vacia**:

```bash
python3 scripts/restore_db.py /ruta/respaldo
python3 scripts/restore_files.py /ruta/respaldo
```

Ninguno de los dos vacia ni sobrescribe: `restore_db.py` exige que `public`
este vacio y `restore_files.py` exige que el volumen este vacio.
