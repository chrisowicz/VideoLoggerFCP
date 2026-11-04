#!/bin/sh
# Compatibility entry point; build the supported standalone Release application.
set -eu
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec sh "$script_directory/build-release.sh" "$@"
