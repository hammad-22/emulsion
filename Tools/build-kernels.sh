#!/bin/sh
# Compile the Core Image Metal kernels for macOS (tests), iPhone and simulator.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
src="$root/Packages/EmulsionCore/Kernels/Emulsion.ci.metal"
out="$root/Packages/EmulsionCore/Sources/EmulsionCore/Resources/Kernels"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for platform in macosx iphoneos iphonesimulator; do
  case "$platform" in
    macosx) target=air64-apple-macos26.0 ;;
    iphoneos) target=air64-apple-ios26.0 ;;
    iphonesimulator) target=air64-apple-ios26.0-simulator ;;
  esac
  xcrun -sdk "$platform" metal -target "$target" -fcikernel -c "$src" -o "$tmp/$platform.air"
  xcrun -sdk "$platform" metallib -cikernel "$tmp/$platform.air" -o "$out/Emulsion-$platform.metallib"
done
echo "Built Emulsion kernels."
