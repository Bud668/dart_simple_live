#!/bin/bash
set -euo pipefail
base="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$base"
exec 9>"$base/.build.lock"
flock -n 9 || { echo 'A Simple Live build is already running.' >&2; exit 2; }
docker run --rm --cpus=6 --memory=8g -v "$base:/workspace" simple-live-build:v3 python3 compile.py
docker run --rm --cpus=6 --memory=8g -v "$base:/workspace" simple-live-build:v3 bash verify.sh
