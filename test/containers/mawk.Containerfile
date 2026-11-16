# A static mawk for the host platform (the `build` of [host-mawk], [host-mawk2020] and
# [host-mawk2024] in test/containers.toml, which give VERSION and SHA256). The binary is
# copied out of the image to test/bin/; statically linked, it runs on any Linux.

FROM alpine:3.22 AS build
ARG VERSION
ARG SHA256

RUN apk add --no-cache -q build-base
# the author's git export of mawk (invisible-island.net blocks scripted downloads at times)
ADD https://github.com/ThomasDickey/mawk-snapshots/archive/refs/tags/${VERSION}.tar.gz /tmp/src.tar.gz

WORKDIR /tmp/src
RUN echo "${SHA256}  /tmp/src.tar.gz" | sha256sum -c && \
    tar -xzf /tmp/src.tar.gz --strip-components=1 && ./configure LDFLAGS=-static && make

# only the binary, at /awk (test/platforms.py copies it to the awk of the platform)
FROM scratch
COPY --from=build /tmp/src/mawk /awk
