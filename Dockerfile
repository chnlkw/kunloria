# syntax=docker/dockerfile:1
# --- build stage ------------------------------------------------------------
# Installs the MoonBit toolchain and compiles the static-ish native binary
# (glibc; only libc + libgcc_s are needed at runtime).
FROM debian:bookworm-slim AS build
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl bzip2 xz-utils \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
ENV PATH="/root/.moon/bin:$PATH"
WORKDIR /src
# Which example (or your own main package) to embed; a deployment embeds
# exactly one policy binary. docker build --build-arg EXAMPLE=rgw-tenant .
ARG EXAMPLE=rgw-tenant
# Restore dependencies first for better layer caching.
RUN moon update
COPY moon.mod ./
COPY .mooncakes ./.mooncakes
COPY moon.pkg kunloria.mbt verdict engine k8s ceph server examples ./
RUN moon build --release --target native "examples/${EXAMPLE}/main" \
 && cp "_build/native/release/build/examples/${EXAMPLE}/main/main.exe" /out-kunloria

# --- runtime stage ----------------------------------------------------------
FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --no-create-home kunloria
COPY --from=build /out-kunloria /usr/local/bin/kunloria
USER kunloria
EXPOSE 8080
ENV KUNLORIA_HOST=0.0.0.0 KUNLORIA_PORT=8080
HEALTHCHECK --interval=30s --timeout=3s CMD curl -fsS http://127.0.0.1:8080/healthz || exit 1
ENTRYPOINT ["/usr/local/bin/kunloria"]
