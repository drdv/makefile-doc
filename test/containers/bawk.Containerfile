# A base image with a prebuilt busybox awk of busybox.net, as `bawk` (the `build` of [bawk]
# in test/containers.toml, which gives VERSION and SHA256). The binary is for x86_64.

FROM debian:12
ARG VERSION
ARG SHA256

ADD https://busybox.net/downloads/binaries/${VERSION}-x86_64-linux-musl/busybox_AWK /usr/local/bin/bawk
RUN echo "${SHA256}  /usr/local/bin/bawk" | sha256sum --check && chmod 755 /usr/local/bin/bawk
