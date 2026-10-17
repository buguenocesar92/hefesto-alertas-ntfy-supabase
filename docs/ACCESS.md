# Cuentas y canales
El administrador tiene acceso global: nunca usar su token en automatizaciones. Preferir instancia por cliente; los prefijos por sí solos no aíslan datos.

Crear dos usuarios con contraseñas interactivas:
```
docker compose exec app ntfy user add emisor-cliente1
docker compose exec app ntfy user add lector-cliente1
docker compose exec app ntfy access emisor-cliente1 'cliente1-*' write
docker compose exec app ntfy access lector-cliente1 'cliente1-*' read
docker compose exec app ntfy access
```
No conceder permisos a everyone ni comodín global a cuentas de cliente. Ejemplos de canales: cliente1-backups, cliente1-incidentes, cliente1-ventas. Probar que cliente1 no accede a cliente2.

Crear token del emisor:
```
docker compose exec app ntfy token add --expires=720h --label=automatizacion emisor-cliente1
```
Guardar salida en gestor de secretos; no en repositorios, enlaces ni capturas. El token hereda permisos del usuario, no crea aislamiento adicional por sí solo. Usar usuario por integración cuando necesite revocación separada. Rotar antes de vencer, probar el nuevo y retirar el anterior con `ntfy token remove USUARIO TOKEN` por consola protegida (el argumento puede quedar en historial; usar interfaz/operación segura del administrador si procede).

Cliente móvil/web: configurar servidor HTTPS propio y cuenta lectora, suscribirse a los canales permitidos. No utilizar la cuenta administradora en dispositivos compartidos. Eliminar suscripciones y tokens al retirar acceso.
