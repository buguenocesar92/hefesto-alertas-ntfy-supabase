# Recuperación y traspaso
1. Mantener el origen intacto y preparar otro proyecto Supabase16/17 y un VOLUME_PREFIX nuevo. Usar la misma imagen2.30.0.
2. Preparar rol/SQL y CA. Recuperar .env y config.yml del respaldo de confianza: conservar VAPID, cambiar conexión y dominio de destino. Mantener app detenida.
3. `docker compose run --rm preflight`.
4. `python3 scripts/restore_db.py /ruta/respaldo` exige public vacío; no borra datos.
5. `python3 scripts/restore_files.py /ruta/respaldo` exige volumen vacío, valida hashes y rutas, restaura adjuntos y propietario1000.
6. Ensayo privado: vaciar temporalmente las tres variables WEB_PUSH_* antes de arrancar (guardar originales fuera del ensayo). Evita activar Web Push con suscripciones reales recuperadas. No conectar emisores ni relay. Revisar cuentas, ACL, mensajes y archivos. Caché/adjuntos vencidos pueden eliminarse al iniciar; restauración no extiende su caducidad.
7. Detener ensayo. Para corte final: pausar emisores, hacer respaldo final, repetir en destino vacío, conservar dominio original cuando sea posible, restaurar VAPID, cambiar DNS/proxy y reconectar emisores. Verificar permisos y mensajes de prueba autorizados. Retirar origen tras aceptación.

No iniciar dos instancias contra la misma base/archivos ni cambiar versión durante restauración. Si una restauración falla a medias, comenzar en destino vacío. Hashes detectan corrupción, no autentican archivos de terceros. Para adjuntos use siempre directorio exclusivo: ntfy elimina archivos huérfanos compatibles con sus IDs.

Odoo/n8n/Laravel: integración por POST HTTPS desde backend; mantener credencial fuera del navegador. Odoo puede invocar un servicio propio al terminar un proceso; no hay módulo instalado ni sincronización bidireccional en este kit. Entregar URL, usuarios, ACL, rotación de tokens, respaldo y runbook al cliente.
