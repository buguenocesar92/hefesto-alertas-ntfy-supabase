# Integraciones de ejemplo (sin activar)

Publicador Python incluido, requiere NTFY_URL y NTFY_TOKEN desde un gestor de secretos:
```
export NTFY_URL=https://alertas.example.com
printf 'Respaldo terminado: 42 registros' | python3 scripts/publish.py cliente1-backups --title Respaldo
```
Por defecto solo valida. Agregar --send para publicar realmente. No pasar token en argumentos ni imprimirlo. El script valida HTTPS y evita redirecciones con credenciales. Un timeout no permite distinguir entre no entrega y entrega sin respuesta: revisar antes de repetir; no hay garantía exactly-once.

n8n: nodo HTTP Request, POST a URL raíz, credencial Header Auth (Authorization: Bearer TOKEN), body JSON:
```
{"topic":"cliente1-backups","title":"Respaldo","message":"Proceso finalizado","priority":3}
```
Crear credencial propia; no colocar el token en un JSON exportado. Manejar429 con espera y alertar fallos en otro canal.

Laravel (HTTP client, ejecutar en job después de commit):
```php
$response = Http::withToken(config('services.ntfy.token'))
    ->timeout(15)->withoutRedirecting()
    ->post(config('services.ntfy.url'), [
        'topic' => 'cliente1-ventas',
        'title' => 'Nueva operación',
        'message' => 'Revisar el panel comercial',
        'priority' => 3,
    ]);
$response->throw();
```
Definir services.ntfy.url HTTPS y token desde entorno. Evitar enviar RUT, datos de pago o contenido completo de pedidos. El ejemplo no incorpora cambios en tus proyectos existentes.

Uptime Kuma: crear notificación ntfy con servidor propio y token según la interfaz de su versión; usar emisor restringido al canal de incidentes. Probar manualmente. Si Kuma y ntfy están en el mismo VPS, una caída total requiere monitor externo.
