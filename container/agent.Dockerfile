# Add the verified musl binaries to an existing, version-pinned agent image.
ARG REOLINK_IMAGE=reolink-cli:0.21.0-external
ARG AGENT_IMAGE=ghcr.io/openclaw/openclaw:2026.10.5-slim
FROM ${REOLINK_IMAGE} AS reolink
FROM ${AGENT_IMAGE}
COPY --from=reolink /usr/local/bin/reolink-cli /usr/local/libexec/reolink-cli
COPY --from=reolink /usr/local/bin/reolink-gateway /usr/local/bin/reolink-gateway
COPY --from=reolink /usr/share/reolink-cli/agent-cli /usr/local/bin/reolink-cli
COPY --from=reolink /usr/share/reolink-cli/skills/ /opt/reolink/skills/
COPY --from=reolink /usr/share/licenses/reolink-cli/ /usr/share/licenses/reolink-cli/
