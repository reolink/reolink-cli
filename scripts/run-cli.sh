#!/bin/sh
set -eu

if [ -n "${REOLINK_CLI_BIN:-}" ]; then
  exec "${REOLINK_CLI_BIN}" "$@"
fi

if [ -n "${REOLINK_CONTAINER:-}" ]; then
  tty_flag=-i
  if [ -t 0 ] && [ -t 1 ]; then tty_flag=-it; fi
  for arg do
    if [ "$arg" = mcp-server ]; then tty_flag=-i; fi
  done
  set -- exec "$tty_flag" "$REOLINK_CONTAINER" reolink-cli "$@"
  if [ -n "${REOLINK_DOCKER_CONTEXT:-}" ]; then
    exec docker --context "$REOLINK_DOCKER_CONTEXT" "$@"
  fi
  exec docker "$@"
fi

if command -v reolink-cli >/dev/null 2>&1; then
  exec reolink-cli "$@"
fi

printf '%s\n' 'reolink-cli is not installed. Install the CLI and gateway from https://github.com/reolink/reolink-cli and add them to PATH, or set REOLINK_CONTAINER to a running container.' >&2
exit 127
