# Validación de entrega
Hecho en entorno local: parseo YAML y Python; shell syntax; generación de .env0600 sin sobrescritura; publicador en modo seco y rechazo de HTTP/topic inválido; integridad ZIP.

Pendiente en servidor:
- docker compose config --quiet con variables reales.
- Preflight y migraciones contra Supabase16/17 con verify-full, sin superusuario en app.
- Crear admin, lector y emisor; comprobar deny-all anónimo y aislamiento de canales.
- Lector no publica; emisor no lee; cliente1 no accede a cliente2.
- API raíz publica JSON, lectura autenticada recibe el mismo mensaje.
- Adjuntos5MB y limpieza3h; mensajes expiran24h; persistencia tras reinicio.
- Proxy y WebSocket/streaming sin buffering indebido; límites por IP comprobados.
- Push probado por dispositivo después de configurar VAPID; no asumir recepción universal.
- Token vencido/revocado rechazado, rotación documentada.
- Backup y restauración en destino nuevo, con Web Push desactivado durante ensayo.
- Monitoreo externo de /v1/health, espacio, fallos de publicación y costo DB.
