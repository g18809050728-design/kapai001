#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
output=${1:-dist/web}
mkdir -p "$output"
"${GODOT_BIN:-godot}" --headless --path . --export-release Web "$output/index.html"
cp web/game-shell.css web/game-shell.js web/game-shell.woff2 assets/fonts/OFL.txt "$output/"
gzip -kf "$output/index.wasm"
