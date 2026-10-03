###########
# CRYSTAL #
###########

# mcpctl has no HTTP client (mcp-remote does the network), so no libxml2. It
# still needs two libraries beyond the Crystal runtime:
#   zlib     linked into the binary: baked_file_system stores the baked files
#            gzipped (compress/gzip).
#   OpenSSL  build time only: baked_file_system's loader, run as a macro at
#            compile time, hashes the files (digest/sha256) and is linked with
#            the same --static flags. The shipped binary does not link it.
FROM alpine:3.24 AS crystal

RUN apk add --update --no-cache \
  bash \
  make \
  crystal=~1.20 \
  shards \
  gc-dev \
  gc-static \
  git \
  openssl-dev \
  openssl-libs-static \
  pcre2-dev \
  pcre2-static \
  yaml-dev \
  yaml-static \
  zlib-dev \
  zlib-static

FROM crystal AS build-binary-file

ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

ENV \
  TARGETPLATFORM=${TARGETPLATFORM} \
  TARGETOS=${TARGETOS} \
  TARGETARCH=${TARGETARCH} \
  TARGETVARIANT=${TARGETVARIANT}

WORKDIR /build
COPY .git/ /build/.git/
COPY shard.yml shard.lock /build/
COPY LICENSE licenses.manifest /build/
COPY licenses-spdx/ /build/licenses-spdx/
COPY scripts/ /build/scripts/
COPY Makefile.release /build/Makefile
COPY src/ /build/src/
RUN mkdir /build/bin

RUN make release

FROM scratch AS binary-file
ARG TARGETOS
ARG TARGETARCH
COPY --from=build-binary-file /build/bin/mcpctl-${TARGETOS}-${TARGETARCH} /

FROM gcr.io/distroless/static-debian12 AS docker-image

ARG TARGETOS
ARG TARGETARCH

COPY --from=build-binary-file /build/bin/mcpctl-${TARGETOS}-${TARGETARCH} /usr/bin/mcpctl

USER nonroot
ENV USER=nonroot
ENV HOME=/home/nonroot
WORKDIR /home/nonroot
ENTRYPOINT ["mcpctl"]
