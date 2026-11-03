#!/bin/sh
set -eu
umask 077
reolink-cli config init >/dev/null
exec "$@"
