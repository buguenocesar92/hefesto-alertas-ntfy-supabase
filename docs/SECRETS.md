# Secretos del kit Hefesto Alertas

Ninguna credencial vive en este repositorio. `.env` esta en `.gitignore` y
`secrets/.gitignore` bloquea `*.env` y `*.age` por si alguien deja un fichero
ahi.

## 1. Que hay que guardar

| Secreto | Donde vive | Como se genera |
| --- | --- | --- |
| `DB_PASSWORD` | gestor de secretos del cliente | `openssl rand -base64 32` |
| `WEB_PUSH_PRIVATE_KEY` | gestor de secretos del cliente | `ntfy webpush` en el servidor, una sola vez |
| `WEB_PUSH_PUBLIC_KEY` | `.env` (publico) | junto a la privada |
| `SMTP_PASSWORD` | gestor de secretos del cliente | la entrega el operador |

## 2. Ruta SOPS + age (principal)

La clave **privada** de age vive fuera del repositorio, en el servidor o en el
gestor de secretos. El kit solo necesita la publica.

```bash
# En el servidor, una sola vez: la clave privada nunca sale de ahi.
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
SOPS_AGE_RECIPIENT="$(grep -oP 'public key: \K\S+' ~/.config/sops/age/keys.txt)"

# Cifrar el .env en el servidor (nunca en el repo de trabajo).
sops --encrypt --age "$SOPS_AGE_RECIPIENT" --in-place .env

# Descifrar en el destino, ahi mismo, sin dejar el claro en disco mas de lo necesario.
sops --decrypt .env > /etc/hefesto/alertas.env
chmod 600 /etc/hefesto/alertas.env
```

## 3. Ruta Infisical (alternativa)

Si el cliente usa Infisical como gestor:

```bash
infisical run --env=produccion --path=/hefesto/alertas -- docker compose up -d
```

El `.env` local es opcional en ese caso: Coolify inyecta las variables desde el
gestor y nunca las escribe en el repositorio.

## 4. Reglas

- `.env` con permisos `600`. `scripts/preflight.sh` lo comprueba.
- La clave privada de age, la de Web Push y `DB_PASSWORD` no se versionan, no
  se pegan en un ticket y no se copian al portapapeles.
- Un respaldo **no lleva el `.env` en claro**: `scripts/backup.py` solo escribe
  los NOMBRES de las variables (`env.vars`) y, si hay receptor age, el `.env`
  cifrado (`env.age`). Ver `docs/CONTRATO-RESPALDO.md` de Hefesto Studio.
- Rotar `DB_PASSWORD` obliga a redesplegar: el cambio no se propaga solo.
- `gitleaks` corre en CI sobre el repositorio y sobre el historial.
