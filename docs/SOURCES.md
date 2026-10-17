# Fuentes oficiales consultadas · 2026-10-15
- https://docs.ntfy.sh/config/
- https://docs.ntfy.sh/releases/
- https://docs.ntfy.sh/publish/
- https://github.com/binwiederhier/ntfy/tree/v2.30.0
- https://github.com/binwiederhier/ntfy/blob/v2.30.0/server/server.yml
- https://github.com/binwiederhier/ntfy/blob/v2.30.0/db/pg/pg.go
- https://github.com/binwiederhier/ntfy/blob/v2.30.0/cmd/user.go
- https://github.com/binwiederhier/ntfy/blob/v2.30.0/cmd/access.go
- https://github.com/binwiederhier/ntfy/blob/v2.30.0/cmd/token.go
- https://github.com/binwiederhier/ntfy/blob/v2.30.0/LICENSE
- https://hub.docker.com/v2/repositories/binwiederhier/ntfy/tags/v2.30.0

Imagen app fijada por digest. postgres:17-alpine se usa solo como herramienta; resolver digest en arquitectura del destino antes de congelar release operativo. PostgreSQL probado aquí: ninguno; el soporte se verificó en código/documentación, falta aceptación real.
