FROM alpine:3.19 AS build
WORKDIR /build
RUN apk add --no-cache git cargo \
 && git clone --depth=1 https://github.com/redlib-org/redlib.git \
 && cd redlib \
 && RUSTFLAGS='-C target-feature=+crt-static' cargo build --release --target x86_64-alpine-linux-musl --target-dir dst \
 && mv dst/x86_64-alpine-linux-musl/release/redlib /usr/local/bin/

FROM alpine:3.19
COPY --from=build /usr/local/bin/redlib /usr/local/bin/
RUN adduser --home /nonexistent --no-create-home --disabled-password redlib
USER redlib
EXPOSE 8080
HEALTHCHECK --interval=1m --timeout=3s CMD wget --spider -q http://localhost:8080/settings || exit 1
CMD ["redlib"]
