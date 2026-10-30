#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun -sdk macosx metal -c BottleFlip/App/Shaders/BottleGlass.metal -o build/BottleGlass-macos.air
xcrun -sdk macosx metallib build/BottleGlass-macos.air -o BottleFlip/App/Shaders/BottleGlass-macos.metallib
