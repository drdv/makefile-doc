# A base image with a version of goawk compiled from source (the `build` of [goawk] in
# test/containers.toml, which gives VERSION and SHA256).

FROM golang:1 AS build
ARG VERSION
ARG SHA256

ADD https://github.com/benhoyt/goawk/archive/refs/tags/${VERSION}.tar.gz /tmp/src.tar.gz
RUN echo "${SHA256}  /tmp/src.tar.gz" | sha256sum --check && \
    mkdir /tmp/src && tar -xzf /tmp/src.tar.gz -C /tmp/src --strip-components=1 && \
    cd /tmp/src && CGO_ENABLED=0 go build -o goawk goawk.go

FROM debian:12
COPY --from=build /tmp/src/goawk /usr/local/bin/goawk
