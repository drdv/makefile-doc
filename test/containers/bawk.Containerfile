# The prebuilt busybox awk of busybox.net for the host platform (the `build` of [host-bawk]
# in test/containers.toml, which gives VERSION and SHA256). The binary, for x86_64, is
# statically linked (musl): it is copied out of the image to test/bin/ and runs on any Linux.

FROM alpine:3.22 AS build
ARG VERSION
ARG SHA256

ADD https://busybox.net/downloads/binaries/${VERSION}-x86_64-linux-musl/busybox_AWK /tmp/bawk
RUN echo "${SHA256}  /tmp/bawk" | sha256sum -c && chmod 755 /tmp/bawk

# only the binary, at /awk (test/platforms.py copies it to the awk of the platform)
FROM scratch
COPY --from=build /tmp/bawk /awk
