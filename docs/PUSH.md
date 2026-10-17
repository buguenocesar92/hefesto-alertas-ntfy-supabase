# Notificaciones y dispositivos
Sin claves VAPID, este kit permite suscripciones activas; no afirma que la PWA despertará cerrada.

Para Web Push, generar claves con:
```
docker compose run --rm --no-deps app webpush keys
```
Copiar las dos claves a WEB_PUSH_PUBLIC_KEY y WEB_PUSH_PRIVATE_KEY, y definir WEB_PUSH_EMAIL_ADDRESS con correo administrativo real. Guardar la privada y respaldar .env. No configurar web-push-file: PostgreSQL guarda las suscripciones. Recrear app, acceder por HTTPS, permitir notificaciones y probar con navegador en segundo plano. Web Push contacta proveedores de push del navegador; no es un canal completamente interno.

Android puede usar la app ntfy con URL propia y conexión persistente; revisar políticas de batería. iOS nativo necesita configuración adicional de upstream para avisos inmediatos cuando la app duerme: no está activada aquí. Activar ntfy.sh como upstream introduce dependencia externa y requiere revisar la documentación/privacidad antes de hacerlo. Alternativa: PWA con Web Push cuando el dispositivo/navegador lo soporte.

Una notificación mostrada no equivale a acuse humano. Para incidentes críticos combinar monitor externo, escalamiento y ticket; no depender únicamente del mismo VPS que se está vigilando.
