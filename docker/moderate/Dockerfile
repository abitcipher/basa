# basa-moderate: BASA's photo checks (native/moderate), open image models on
# ONNX Runtime (built into the binary), CPU only. BASA starts it with
# `docker run -i` (Basa.Moderation) and a volume for the models at /models;
# requests and replies go over stdin/stdout. Models are not in the image:
# the level chosen at /admin/settings is downloaded into the volume once.
#
#   docker compose build moderate

FROM rust:1-slim-trixie AS build
WORKDIR /src
# ort fetches ONNX Runtime while building
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates pkg-config libssl-dev g++ && rm -rf /var/lib/apt/lists/*
COPY Cargo.toml Cargo.lock ./
# dependencies first, in their own layer: code changes rebuild only basa-moderate
RUN mkdir src && echo 'fn main() {}' > src/main.rs && cargo build --release --locked && rm -rf src
COPY src ./src
RUN touch src/main.rs && cargo build --release --locked

FROM debian:trixie-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libstdc++6 \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --no-create-home --uid 10002 moderate \
 && mkdir /models && chown moderate /models
COPY --from=build /src/target/release/basa-moderate /usr/local/bin/basa-moderate
USER moderate
VOLUME /models
ENTRYPOINT ["/usr/local/bin/basa-moderate", "--models", "/models"]
