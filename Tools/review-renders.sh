#!/bin/sh
# Full-resolution before/after renders of the local CC0 samples, for look reviews (MOV-146).
#   Tools/review-renders.sh [base-ref] [output-folder]
# "before" is base-ref (default origin/main), built in a temporary worktree; "after" is this
# checkout as it is, uncommitted changes included. Each sample gives
# <sample>.<neutral|default>.<before|after>.jpg in the output folder (default
# ~/Documents/Emulsion Review/renders/<base>-vs-<head>), so Quick Look can flip between a pair.
# Samples: EMULSION_REVIEW_SAMPLES, else ~/Documents/Emulsion Research/samples/proraw-misc;
# only *_CC0.dng files are rendered. Nothing here goes into git.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
base=${1:-origin/main}
base_sha=$(git -C "$root" rev-parse --short "$base^{commit}")
head_sha=$(git -C "$root" rev-parse --short HEAD)
if ! git -C "$root" diff --quiet HEAD; then head_sha="$head_sha-dirty"; fi
out=${2:-"$HOME/Documents/Emulsion Review/renders/$base_sha-vs-$head_sha"}
mkdir -p "$out"
out=$(CDPATH= cd -- "$out" && pwd)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
export EMULSION_REVIEW_DIR="$out"
test_file=Packages/EmulsionCore/Tests/EmulsionCoreTests/ReviewRenders.swift

tmp=$(mktemp -d)
cleanup() { git -C "$root" worktree remove --force "$tmp/base" 2>/dev/null || true; rm -rf "$tmp"; }
trap cleanup EXIT
git -C "$root" worktree add --quiet --detach "$tmp/base" "$base_sha"
# An older base has no ReviewRenders: give it this checkout's copy (it uses only the public render API).
[ -f "$tmp/base/$test_file" ] || cp "$root/$test_file" "$tmp/base/$test_file"

echo "Rendering before ($base_sha)..."
(cd "$tmp/base/Packages/EmulsionCore" && EMULSION_REVIEW_LABEL=before swift test --filter ReviewRenders)
echo "Rendering after ($head_sha)..."
(cd "$root/Packages/EmulsionCore" && EMULSION_REVIEW_LABEL=after swift test --filter ReviewRenders)
echo "Review renders: $out"
