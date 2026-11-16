# A static wak for the host platform (the `build` of [host-wak] in test/containers.toml,
# which gives VERSION and SHA256). The binary is copied out of the image to test/bin/;
# statically linked, it runs on any Linux.

FROM alpine:3.22 AS build
ARG VERSION
ARG SHA256

RUN apk add --no-cache -q build-base
ADD https://github.com/raygard/wak/archive/refs/tags/${VERSION}.tar.gz /tmp/src.tar.gz

WORKDIR /tmp/src
RUN echo "${SHA256}  /tmp/src.tar.gz" | sha256sum -c && \
    tar -xzf /tmp/src.tar.gz --strip-components=1 && make CC="gcc -static"

# only the binary, at /awk (test/platforms.py copies it to the awk of the platform)
FROM scratch
COPY --from=build /tmp/src/wak /awk
