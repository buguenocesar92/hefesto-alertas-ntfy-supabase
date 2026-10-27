# Contrato de variables del kit Hefesto Alertas

Este documento es **normativo**: el preflight (`scripts/preflight.sh`) y el
preflight del contenedor (`ops/preflight.sh`) fallan de forma cerrada cuando
una variable obligatoria no esta.

Las redes y el volumen **no** declaran `name:` a proposito: el contrato P2 de
`scripts/coolify-check.sh` lo prohibe, para que Docker derive los nombres del
nombre del proyecto y no se puedan colar dos despliegues con el mismo nombre.

| Variable | Obligatoria | Efecto si falta | Donde se usa |
| --- | --- | --- | --- |
| `DB_HOST` | si | el compose no renderiza (`${DB_HOST:?...}`) | `compose.yaml:3` (ancla `x-pg`) |
| `DB_PORT` | no | usa `5432` | `compose.yaml:4` |
| `DB_NAME` | no | usa `postgres` | `compose.yaml:5` |
| `DB_USER` | no | usa `ntfy_app` | `compose.yaml:6` |
| `DB_PASSWORD` | si | el compose no renderiza (`${DB_PASSWORD:?...}`) | `compose.yaml:7` |
| `DB_SSLMODE` | no | usa `verify-full` (exige CA) | `compose.yaml:8` |
| `PGSSLROOTCERT` | no | usa `/certs/ca.crt` | `compose.yaml:9` |
| `PUBLIC_URL` | si | el compose no renderiza (`${PUBLIC_URL:?...}`) | `compose.yaml:41` |
| `VOLUME_PREFIX` | no | prefijo del proyecto en Coolify; el compose no lo declara | `docs/CONTRATO.md`, `.env.example` |
| `SUPABASE_DEDICATED_CONFIRMED` | si | `ops/preflight.sh` aborta | `compose.yaml:21` |
| `SUPABASE_DATA_API_DISABLED` | si | `ops/preflight.sh` aborta | `compose.yaml:22` |
| `WEB_PUSH_PUBLIC_KEY` | no | ntfy arranca sin Web Push | `compose.yaml:45` |
| `WEB_PUSH_PRIVATE_KEY` | no | ntfy arranca sin Web Push | `compose.yaml:46` |
| `WEB_PUSH_EMAIL_ADDRESS` | no | ntfy arranca sin Web Push | `compose.yaml:47` |
| `NTFY_BEHIND_PROXY` | no | `false` | `compose.yaml:48` |
| `NTFY_PROXY_TRUSTED_HOSTS` | no | vacio | `compose.yaml:49` |
| `SMTP_ADDRESS` | no | este kit no usa SMTP todavia | `.env.example` |
| `SMTP_USERNAME` | no | este kit no usa SMTP todavia | `.env.example` |
| `SMTP_PASSWORD` | no | este kit no usa SMTP todavia | `.env.example` |

## Redes

| Red | Servicios | Para que sirve |
| --- | --- | --- |
| `alertas` | `preflight`, `permissions`, `app`, `dbtools`, `filetools` | comunicacion interna entre servicios del kit |
| `egreso` | `preflight`, `app`, `dbtools` | salida a internet: Supabase, Web Push y SMTP |

## Volumen

`files` guarda los adjuntos de ntfy. Su nombre lo deriva Docker del nombre del
proyecto (`<proyecto>_files`); el compose no lo fija para no violar el contrato
P2. En Coolify el nombre del proyecto es el `VOLUME_PREFIX` del `.env`.
