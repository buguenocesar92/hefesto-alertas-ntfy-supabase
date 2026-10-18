# Hefesto Alertas · ntfy 2.30.0 + Supabase

Kit nativo para centralizar avisos de respaldos, caídas y procesos. Entrega configuración Docker/Coolify, permisos por canal, publicador HTTPS, respaldo y restauración. No es un servicio ya desplegado.

## Stack elegido
ntfy admite PostgreSQL nativo desde 2.18 y dejó de considerarlo experimental en 2.27. Este kit usa 2.30.0 fijado por digest, con Supabase PostgreSQL para usuarios, permisos, tokens, caché de mensajes y suscripciones web push. Los adjuntos se guardan en volumen local exclusivo. No utiliza Supabase Auth, Storage ni Data API. Una instancia, sin clustering experimental.

## Puesta en marcha
Requiere Docker + Compose v2, Python3.11+, proyecto Supabase exclusivo PostgreSQL16/17, acceso a puerto5432 y proxy HTTPS. Comenzar con 1CPU/1GB para app y medir consumo según conexiones y mensajes; Supabase se dimensiona aparte.

1. `python3 scripts/configure.py`. Editar .env y conservar su permiso0600. DB_PASSWORD se genera hexadecimal para formar una URL sin problemas de escape.
2. Ejecutar sql/01-supabase-app.sql como postgres en SQL Editor. Asignar DB_PASSWORD al rol ntfy_app mediante `\password ntfy_app` en psql administrativo.
3. Desactivar Data API del proyecto. Usar DB_HOST directo5432 o Session Pooler5432 (DB_USER=ntfy_app.REFERENCIA si usa pooler). No usar Transaction Pooler6543. Descargar CA oficial a certs/ca.crt. Confirmar variables SUPABASE_* solo después de hacerlo.
4. `docker compose -f compose.yaml -f compose.bootstrap.yaml up -d`. Preflight valida versión y permisos; ntfy crea/migra sus tablas automáticamente.
5. Crear administrador interactivo: `docker compose exec app ntfy user add --role=admin hefesto-admin`. No hay contraseña inicial compartida. No pasar claves como argumento de shell.
6. Abrir http://localhost:8102. En servidor remoto: `ssh -L 8102:127.0.0.1:8102 usuario@servidor`. Crear las cuentas y ACL según docs/ACCESS.md. Registro público cerrado; accesos a canales denegados por defecto.
7. Detener bootstrap con `docker compose -f compose.yaml -f compose.bootstrap.yaml down` (sin -v). Establecer PUBLIC_URL=https://alertas.sudominio y ejecutar `docker compose up -d`.
8. En Coolify importar compose.yaml, config.yml, ops, certs y variables. Asignar dominio HTTPS al servicio app, puerto8080. No añadir override bootstrap al despliegue público. Al actualizar desde una instalación previa, el volumen ya no se llama `hefesto-alertas-files` sino `<proyecto>_files`; si reutiliza datos, copie el contenido del volumen antiguo al nuevo antes del primer arranque.
9. Verificar login, publicación/lectura con roles distintos, acceso anónimo rechazado y reinicio con persistencia. Revisar docs/ACCEPTANCE.md antes de vender el servicio.

## Límites de operación
Mensajes retenidos24h, adjuntos3h y máximo5MB cada uno (total1GB). Esto es una bandeja temporal de avisos, no un archivo histórico ni un sistema de tickets. Supabase guarda mensajes en texto accesible al servidor; no se ofrece cifrado extremo a extremo. Evitar contraseñas, documentos privados y datos innecesarios en alertas.

No están configurados SMTP, SMS, Firebase, relay iOS, servicios de pago ni conexiones a sistemas reales. El navegador abierto puede recibir mensajes; notificaciones en segundo plano necesitan Web Push (docs/PUSH.md). Las condiciones de red y ahorro de batería afectan entrega móvil. No prometer entrega garantizada para emergencias.

`behind-proxy: false` conserva una configuración inicial conservadora: visitantes tras el proxy comparten límites de IP. Antes de tráfico real configurar proxy-trusted-hosts con la IP/CIDR exacta del proxy y behind-proxy=true, sanear cabeceras en ese proxy y mantener app8080 sin publicación directa. Verificar límites con dos clientes. No usar redes confiables globales 0.0.0.0/0.

## Respaldo
`python3 scripts/backup.py` pausa app, copia public.dump, volumen de adjuntos, .env, compose.yaml y config.yml, genera hashes y reinicia si estaba funcionando. Ejecutar solo sobre despliegue base, fuera de bootstrap. Los mensajes publicados durante la pausa pueden fallar: acordar reintentos en cada emisor. Cifrar respaldo, copiar fuera del VPS y definir retención. Restaurar siguiendo docs/RESTORE.md.

Estado: validación estática del kit y pruebas locales del publicador sin envíos. No se ejecutó Docker, migraciones, push ni restauración en infraestructura real.

## Despliegue en Coolify (MVP Hefesto)

Coolify importa `compose.yaml` desde la rama `coolify` con build pack Docker
Compose. El contrato exige que el compose no fuerce nombres y que la BD y el
modo SSL de Supabase sean parametrizables. Para verificarlo antes de desplegar:

```
bash scripts/coolify-check.sh
```

Variables nuevas respecto al uso local sin Coolify:

| Variable | Defecto | Propósito |
|---|---|---|
| `DB_NAME` | `postgres` | Nombre de la base dentro del Postgres compartido. Coolify asigna una BD por app con prefijo `mvp_<slug>`; usar ese valor. |
| `DB_SSLMODE` | `verify-full` | Modo SSL de Postgres. Para redes internas donde no se disponga de la CA de Supabase, usar `disable` (o cualquier valor distinto de `verify-full`) y dejar la CA vacía. |
| `PGSSLROOTCERT` | `/certs/ca.crt` | Ruta a la CA. Dejar vacía (`PGSSLROOTCERT=`) cuando `DB_SSLMODE != verify-full` para no exigir el archivo. Si la variable no se define, se usa el valor por defecto. |
| `NTFY_BEHIND_PROXY` | `false` | Pasar `true` cuando hay proxy reverso (Traefik en Coolify) para que el rate limit aplique por IP real y no por la IP del proxy. |
| `NTFY_PROXY_TRUSTED_HOSTS` | (vacío) | Lista exacta de hosts/IP/CIDR del proxy de confianza. Obligatoria cuando `NTFY_BEHIND_PROXY=true`. Nunca usar `0.0.0.0/0`. |

Notas operativas:

- Coolify pone el nombre de proyecto, la red y el volumen; el compose no
  declara `name:`. El volumen toma el nombre `<proyecto>_files`; al
  actualizar desde una instalación previa con `VOLUME_PREFIX` fijo hay
  que copiar los adjuntos al volumen nuevo antes del primer arranque.
- El servicio `app` expone 8080 internamente; Coolify/Traefik enrutan el
  dominio HTTPS. No añadir `ports:` al compose.
- `config.yml` mantiene `behind-proxy: false` por compatibilidad con el
  uso local sin proxy. En Coolify se controla desde `NTFY_BEHIND_PROXY` y
  `NTFY_PROXY_TRUSTED_HOSTS`, que el contenedor reenvía a ntfy. Con
  `NTFY_BEHIND_PROXY=true` revisar que `NTFY_PROXY_TRUSTED_HOSTS` incluya
  solo los hosts/IP exactos del proxy.
