# A base image with a version of mawk compiled from source (the `build` of [mawk],
# [mawk2020] and [mawk2024] in test/containers.toml, which give VERSION and SHA256).

FROM debian:12 AS build
ARG VERSION
ARG SHA256

RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
        gcc libc6-dev make
# the author's git export of mawk (invisible-island.net blocks scripted downloads at times)
ADD https://github.com/ThomasDickey/mawk-snapshots/archive/refs/tags/${VERSION}.tar.gz /tmp/src.tar.gz
RUN echo "${SHA256}  /tmp/src.tar.gz" | sha256sum --check && \
    mkdir /tmp/src && tar -xzf /tmp/src.tar.gz -C /tmp/src --strip-components=1 && \
    cd /tmp/src && ./configure && make

# /usr/local/bin is before /usr/bin in PATH: this mawk is used, not the one of Debian
FROM debian:12
COPY --from=build /tmp/src/mawk /usr/local/bin/mawk
