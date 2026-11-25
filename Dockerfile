# Builds redlib from source for linux/amd64 and linux/arm64.
# Cross-compiles with musl so the release image needs no libc at all.
# Based on Nachtalb/redlib's Dockerfile.distroless, trimmed to two targets.
# To support more (i686, arm/v7, riscv64, mips64le) see their Dockerfile.distroless:
# https://github.com/Nachtalb/redlib/blob/main/Dockerfile.distroless

ARG TARGETARCH

########################
## builder images (run on the CI host, cross-compile to the target)
########################
FROM --platform=$BUILDPLATFORM ghcr.io/rust-cross/rust-musl-cross:x86_64-musl AS cross-amd64
FROM --platform=$BUILDPLATFORM ghcr.io/rust-cross/rust-musl-cross:aarch64-musl AS cross-arm64

FROM cross-${TARGETARCH} AS builder

RUN apt-get update \
    && apt-get -y install git cmake perl pkg-config libclang-dev \
    && rm -rf /var/lib/apt/lists/*

# bindgen (btls-sys/BoringSSL) must parse the target's musl headers, not the
# build host's glibc ones — without this the build fails on 'stddef.h' not found.
ENV BINDGEN_EXTRA_CLANG_ARGS="--sysroot=${TARGET_HOME}"

# The rust-cross images ship a rust toolchain; pin one matching Cargo.toml's
# rust-version and add the target triple.
RUN rustup toolchain install 1.99 --profile minimal --no-self-update --target $CARGO_BUILD_TARGET \
    && rustup default 1.99

WORKDIR /redlib
COPY . ./

ARG TARGETARCH
ARG GIT_HASH=
# Set by the CI on a release tag: the binary then reports that version.
ARG REDLIB_RELEASE=

# Cache ids include TARGETARCH: buildx builds both platforms in parallel,
# and a shared cargo registry mount makes concurrent unpacks collide
# (".cargo-ok: File exists").
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=/root/.cargo/registry \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=/root/.cargo/git \
    --mount=type=cache,id=redlib-target-${TARGETARCH},target=/redlib/target \
    cargo build --release --locked --bin redlib \
    && cp target/$CARGO_BUILD_TARGET/release/redlib /usr/local/bin/redlib

########################
## release image
########################
FROM --platform=$BUILDPLATFORM gcr.io/distroless/static:nonroot AS distroless

FROM scratch AS release

COPY --from=distroless / /
COPY --from=builder /usr/local/bin/redlib /usr/local/bin/redlib

USER 65532
WORKDIR /home/nonroot
EXPOSE 8080

# No HEALTHCHECK here: distroless/static has no wget/curl/shell to probe with.
# Do the healthcheck from compose with an external probe if you need one.

LABEL org.opencontainers.image.title="redlib" \
      org.opencontainers.image.description="Private front-end for Reddit" \
      org.opencontainers.image.url="https://github.com/jpjpjunior/redlib" \
      org.opencontainers.image.source="https://github.com/jpjpjunior/redlib" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.base.name="gcr.io/distroless/static:nonroot"

CMD ["redlib"]
