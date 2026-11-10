# basa-render: the import's page renderer (native/render) with headless
# Chromium. BASA starts it per run with `docker run -i` (Basa.Import.Browser);
# requests and replies go over stdin/stdout.
#
#   docker compose build render

FROM rust:1-slim-trixie AS build
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
# dependencies first, in their own layer: code changes rebuild only basa-render
RUN mkdir src && echo 'fn main() {}' > src/main.rs && cargo build --release --locked && rm -rf src
COPY src ./src
RUN touch src/main.rs && cargo build --release --locked

FROM debian:trixie-slim
# chromium-headless-shell gets Debian's security updates; fonts so text lays out
RUN apt-get update \
 && apt-get install -y --no-install-recommends chromium-headless-shell fonts-dejavu-core ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --create-home --uid 10001 render
COPY --from=build /src/target/release/basa-render /usr/local/bin/basa-render
USER render
ENV CHROME_PATH=/usr/bin/chromium-headless-shell
# the container is the isolation, so Chromium's own sandbox is off inside it
ENTRYPOINT ["/usr/local/bin/basa-render", "--no-sandbox"]
