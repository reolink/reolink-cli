#!/bin/sh
set -eu
umask 077
# Scope XDG overrides to the camera CLI, preserving the agent's own directories.
export XDG_CONFIG_HOME=/data/config
export XDG_CACHE_HOME=/data/cache
export XDG_STATE_HOME=/tmp/reolink-agent-state
export REOLINK_LOG_FILE=off
exec /usr/local/libexec/reolink-cli "$@"
