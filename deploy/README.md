# Deployment

BASA runs on one server under Docker Compose (`--profile prod`): the
application, PostgreSQL, RustFS, RabbitMQ, Meilisearch, Stalwart, the
signature checker, the page renderer, the photo checker and Caddy (HTTPS).

## First time, on the server

```sh
git clone https://github.com/abitcipher/basa.git /srv/basa
cd /srv/basa
cp .env.example .env    # BASA_HOST, PHX_HOST, SECRET_KEY_BASE, TOKEN_SIGNING_SECRET, passwords, keys
deploy/deploy.sh --no-pull
```

Point the domain's DNS at the server before starting, so Caddy can get a
certificate.

## Updates

On the server: `deploy/deploy.sh`.

From GitHub: run the **Deploy** workflow (Actions → Deploy → Run workflow).
It connects over SSH and runs the same script. Repository secrets it needs:

| Secret | Value |
|---|---|
| `DEPLOY_HOST` | server address |
| `DEPLOY_USER` | SSH user that owns the checkout |
| `DEPLOY_SSH_KEY` | private key of a deploy key pair (the public half in the user's `authorized_keys`) |
| `DEPLOY_PATH` | path of the checkout, for example `/srv/basa` |

Use a dedicated user and key for deployment, never a password.

## Backups

Volumes to back up: `postgres_data`, `rustfs_data`, `stalwart_data`.
City reference: `bin/basa eval 'Basa.Release.geo_export()'`.
