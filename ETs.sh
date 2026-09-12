#!/bin/sh
printf '\033c\033]0;%s\a' ETs
base_path="$(dirname "$(realpath "$0")")"
"$base_path/ETs.x86_64" "$@"
