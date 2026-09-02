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
# Restore dependencies first for better layer caching.
COPY moon.mod ./
COPY .mooncakes ./.mooncakes
COPY moon.pkg auth ceph k8s proof server kunloria.mbt cmd ./
RUN moon build --release --target native cmd/main \
 && cp _build/native/release/build/cmd/main/main.exe /out-kunloria

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
