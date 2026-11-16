# A static goawk for the host platform (the `build` of [host-goawk] in test/containers.toml,
# which gives VERSION and SHA256). The binary is copied out of the image to test/bin/; built
# without cgo, it is statically linked and runs on any Linux.

FROM golang:1 AS build
ARG VERSION
ARG SHA256

ADD https://github.com/benhoyt/goawk/archive/refs/tags/${VERSION}.tar.gz /tmp/src.tar.gz

WORKDIR /tmp/src
RUN echo "${SHA256}  /tmp/src.tar.gz" | sha256sum --check && \
    tar -xzf /tmp/src.tar.gz --strip-components=1 && CGO_ENABLED=0 go build -o goawk goawk.go

# only the binary, at /awk (test/platforms.py copies it to the awk of the platform)
FROM scratch
COPY --from=build /tmp/src/goawk /awk
