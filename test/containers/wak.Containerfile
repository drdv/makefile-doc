# A base image with a version of wak compiled from source (the `build` of [wak] in
# test/containers.toml, which gives VERSION and SHA256).

FROM debian:12 AS build
ARG VERSION
ARG SHA256

RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
        gcc libc6-dev make
ADD https://github.com/raygard/wak/archive/refs/tags/${VERSION}.tar.gz /tmp/src.tar.gz
RUN echo "${SHA256}  /tmp/src.tar.gz" | sha256sum --check && \
    mkdir /tmp/src && tar -xzf /tmp/src.tar.gz -C /tmp/src --strip-components=1 && \
    cd /tmp/src && make

FROM debian:12
COPY --from=build /tmp/src/wak /usr/local/bin/wak
