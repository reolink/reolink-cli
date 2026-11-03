# syntax=docker/dockerfile:1
ARG REOLINK_VERSION=0.21.0
FROM --platform=$BUILDPLATFORM alpine:3.23 AS release
RUN apk add --no-cache curl binutils
ARG REOLINK_VERSION
ARG TARGETARCH
WORKDIR /release
RUN set -eu; \
    case "$TARGETARCH" in amd64) arch=x86_64 ;; arm64) arch=arm64 ;; *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; esac; \
    asset="reolink-cli-${REOLINK_VERSION}-external-linux-${arch}-musl.tar.gz"; \
    curl --fail --location --retry 3 --proto '=https' "https://github.com/reolink/reolink-cli/releases/download/v${REOLINK_VERSION}/${asset}" -o "$asset"; \
    curl --fail --location --retry 3 --proto '=https' "https://raw.githubusercontent.com/reolink/reolink-cli/main/checksums/v${REOLINK_VERSION}.sha256" -o checksums; \
    awk -v asset="$asset" '$2 == asset { print }' checksums > selected.sha256; \
    test "$(wc -l < selected.sha256)" -eq 1; \
    sha256sum -c selected.sha256; \
    mkdir unpacked /out; \
    tar -xzf "$asset" --strip-components=1 -C unpacked; \
    cp unpacked/bin/reolink-cli unpacked/bin/reolink-gateway /out/; \
    cp unpacked/EULA.txt unpacked/THIRD-PARTY-LICENSES.txt /out/; \
    test -s /out/EULA.txt; test -s /out/THIRD-PARTY-LICENSES.txt; \
    strings /out/reolink-cli /out/reolink-gateway > fingerprints; \
    if grep -Eq 'song/Desktop|p2p_make_c2d_try_relay|p2p_conn_get_relaymod' fingerprints; then echo 'Refusing to package Song P2P' >&2; exit 1; fi

FROM alpine:3.23
ARG REOLINK_VERSION
ARG REOLINK_UID=10001
ARG REOLINK_GID=10001
ARG REOLINK_SKILL_DIR=skills/reolink-cli
LABEL org.opencontainers.image.source="https://github.com/reolink/reolink-cli" \
      org.opencontainers.image.version="$REOLINK_VERSION"
RUN apk add --no-cache ca-certificates \
    && test "$REOLINK_UID" -gt 0 && test "$REOLINK_GID" -gt 0 \
    && addgroup -g "$REOLINK_GID" reolink \
    && adduser -D -u "$REOLINK_UID" -G reolink reolink \
    && mkdir -p /data/config /data/state /data/cache /usr/share/licenses/reolink-cli \
    && chown -R "$REOLINK_UID:$REOLINK_GID" /data
COPY --from=release /out/reolink-cli /out/reolink-gateway /usr/local/bin/
COPY --from=release /out/EULA.txt /out/THIRD-PARTY-LICENSES.txt /usr/share/licenses/reolink-cli/
COPY --chmod=755 container/entrypoint.sh /usr/local/bin/reolink-entrypoint
COPY --chmod=755 container/agent-cli.sh /usr/share/reolink-cli/agent-cli
COPY ${REOLINK_SKILL_DIR}/SKILL.md /usr/share/reolink-cli/skills/reolink-cli/SKILL.md
COPY ${REOLINK_SKILL_DIR}/references/ /usr/share/reolink-cli/skills/reolink-cli/references/
ENV XDG_CONFIG_HOME=/data/config XDG_STATE_HOME=/data/state XDG_CACHE_HOME=/data/cache REOLINK_LOG_FILE=off
RUN reolink-cli --version | grep -F '(external' \
    && REOLINK_LOG_FILE=off reolink-gateway --version | grep -F '(external'
USER ${REOLINK_UID}:${REOLINK_GID}
WORKDIR /data
VOLUME ["/data"]
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:9000/api/health || exit 1
ENTRYPOINT ["reolink-entrypoint"]
CMD ["reolink-gateway", "--addr", "0.0.0.0:9000"]
