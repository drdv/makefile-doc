# A base image with mawk 1.3.4 20240123 compiled from source (the `build` of [mawk2024] in
# test/containers.toml). To test another version, change VERSION and SHA256.

FROM debian:12 AS build
ARG VERSION=t20240123
ARG SHA256=38577cd9b459532ee4ee0a04db13ada71f76a2b0fd15fc562afa5c7ec11722ad

RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
        gcc libc6-dev make
ADD https://github.com/ThomasDickey/mawk-snapshots/archive/refs/tags/${VERSION}.tar.gz /tmp/mawk.tar.gz
RUN echo "${SHA256}  /tmp/mawk.tar.gz" | sha256sum --check && \
    mkdir /tmp/mawk && tar -xzf /tmp/mawk.tar.gz -C /tmp/mawk --strip-components=1 && \
    cd /tmp/mawk && ./configure && make

# /usr/local/bin is before /usr/bin in PATH: this mawk is used, not the one of Debian
FROM debian:12
COPY --from=build /tmp/mawk/mawk /usr/local/bin/mawk
