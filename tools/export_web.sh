#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
output=${1:-dist/web}
if [ -e "$output/game-assets" ]; then
    echo "Choose a new Web export directory. Published asset paths are immutable." >&2
    exit 1
fi
mkdir -p "$output"
kapai_web_python=${PYTHON_BIN:-python3.11}
"$kapai_web_python" -c 'import PIL, zstandard'
"${GODOT_BIN:-godot}" --headless --path . --export-release Web "$output/index.html"
cp web/game-shell.css web/game-shell.js web/game-shell.woff2 web/account-campus.webp assets/fonts/OFL.txt "$output/"
build_version=${KAPAI_BUILD_VERSION:-$(git rev-parse --short HEAD 2>/dev/null || echo local)}
case "$build_version" in
    *[!a-zA-Z0-9_.:-]*) echo "Invalid KAPAI_BUILD_VERSION" >&2; exit 1 ;;
esac
sed "s/__KAPAI_BUILD_VERSION__/$build_version/g" web/accounts.js > "$output/accounts.js"
gzip -kf "$output/index.wasm"
"$kapai_web_python" tools/slim_web_pack.py "$output/index.pck"
"$kapai_web_python" tools/prepare_web_assets.py "$output"
