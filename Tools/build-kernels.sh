#!/bin/sh
# Compile the Core Image Metal kernels for macOS (tests), iPhone and simulator. The film process
# (Emulsion.ci.metal) and the digicam process (Digicam.ci.metal) compile to separate .air files,
# merged with metal-link (metallib -cikernel takes exactly one input) into one metallib per platform.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
kernels="$root/Packages/EmulsionCore/Kernels"
out="$root/Packages/EmulsionCore/Sources/EmulsionCore/Resources/Kernels"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for platform in macosx iphoneos iphonesimulator; do
  case "$platform" in
    macosx) target=air64-apple-macos26.0 ;;
    iphoneos) target=air64-apple-ios26.0 ;;
    iphonesimulator) target=air64-apple-ios26.0-simulator ;;
  esac
  for source in Emulsion Digicam; do
    xcrun -sdk "$platform" metal -target "$target" -fcikernel -c "$kernels/$source.ci.metal" -o "$tmp/$platform-$source.air"
  done
  xcrun -sdk "$platform" metal-link "$tmp/$platform-Emulsion.air" "$tmp/$platform-Digicam.air" -o "$tmp/$platform.air"
  xcrun -sdk "$platform" metallib -cikernel "$tmp/$platform.air" -o "$out/Emulsion-$platform.metallib"
done
echo "Built Emulsion kernels."
