#!/bin/zsh
# Packages a ready-to-install bundle for another Mac (no Swift toolchain needed there):
#   macos/dist/BambooDriver.zip  ->  BambooDriver/{BambooDriver.app, install.sh}
set -euo pipefail
cd "${0:A:h}"

./build.sh
OUT=dist/BambooDriver
rm -rf dist
mkdir -p "$OUT"
cp -R build/BambooDriver.app "$OUT/"
cp install.sh "$OUT/"

(cd dist && ditto -c -k --norsrc --noextattr --keepParent BambooDriver BambooDriver.zip)
echo "Created macos/dist/BambooDriver.zip"
