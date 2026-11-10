# BASA

A booking platform for renting out spaces, equipment and people's time:
a responsive website, a Telegram bot with a Mini App, and an API. A sale is
treated as a long lease, so the same flow covers selling.

First vertical: music (studios, rehearsal rooms, mobile setups).

## Repositories

| Repository | What it is |
|---|---|
| [basa](https://github.com/abitcipher/basa) | This application |
| [basa_tma](https://github.com/abitcipher/basa_tma) | Telegram Mini App toolkit for Phoenix (sign-in, app shell, local emulator) |
| [rules](https://github.com/abitcipher/rules) | GoRules ZEN decision graphs for Elixir, as a NIF |

`basa` uses the other two as dependencies, pinned by tag in `mix.exs`.

## Stack

Elixir · Ash 3 · Phoenix LiveView · PostgreSQL 18 (PostGIS, pgvector,
btree_gist) · Oban · Rust (native code) · React widgets · RustFS (S3) ·
RabbitMQ · Meilisearch · Stalwart · Caddy. All services run under Docker
Compose.

## Run it locally

You need Elixir 1.20, Erlang/OTP 29, Rust (stable), Node 24 and Docker.

```sh
cp .env.example .env            # edit secrets; Telegram and AI keys are optional
docker compose up -d            # Postgres, RustFS, RabbitMQ, Meilisearch, Stalwart, ...
mix setup                       # dependencies, database, migrations, assets
mix run priv/repo/dev_seeds.exs # development accounts
(cd assets/widgets && npm ci)   # once; the dev server then rebuilds the widgets
mix phx.server                  # http://localhost:4000
```

Development accounts (password `password1234`): `lessor@basa.test`,
`lessee@basa.test`, `admin@basa.test`.

Without a Telegram bot token, development runs a local Telegram emulator
at `/dev/telegram`: the real bot, a Telegram-like chat and the Mini App.

## Tests and checks

```sh
mix test                               # needs the postgres container
mix format --check-formatted
(cd assets/widgets && npm run check)   # TypeScript
cargo test --manifest-path native/witness/Cargo.toml
```

## Languages

The interface is in Ukrainian, English, German, French, Spanish, Italian,
Polish, Romanian and Turkish (`priv/gettext/<code>`); every string is
translated in every language, and a test fails otherwise. After adding
strings: `mix gettext.extract --merge`.

Help for users is part of the application (`/help`), written in Ukrainian,
English and Spanish (`priv/help/<language>`).

## Deploy

One server with Docker is enough:

```sh
cp .env.example .env    # set BASA_HOST, secrets, keys
deploy/deploy.sh        # pulls, builds the images, migrates, starts
```

Caddy serves HTTPS for `BASA_HOST`. The `Deploy` workflow in GitHub Actions
runs the same script on the server over SSH (see `deploy/README.md`).

## Data and licences of content

City data: GeoNames (CC BY 4.0) and © OpenStreetMap contributors (ODbL).
