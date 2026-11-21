#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
output=${1:-dist/web}
mkdir -p "$output"
"${GODOT_BIN:-godot}" --headless --path . --export-release Web "$output/index.html"
cp web/game-shell.css web/game-shell.js web/game-shell.woff2 web/account-campus.webp assets/fonts/OFL.txt "$output/"
build_version=${KAPAI_BUILD_VERSION:-$(git rev-parse --short HEAD 2>/dev/null || echo local)}
case "$build_version" in
    *[!a-zA-Z0-9_.:-]*) echo "Invalid KAPAI_BUILD_VERSION" >&2; exit 1 ;;
esac
sed "s/__KAPAI_BUILD_VERSION__/$build_version/g" web/accounts.js > "$output/accounts.js"
gzip -kf "$output/index.wasm"
