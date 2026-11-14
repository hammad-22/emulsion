#!/bin/sh
# Full-resolution before/after renders of the local CC0 samples, for look reviews (MOV-146).
#   Tools/review-renders.sh [base-ref] [output-folder]
# "before" is base-ref (default origin/main, fetched first), built in a temporary worktree; "after" is this
# checkout as it is, uncommitted changes included. Each sample gives
# <sample>.<neutral|default|digicam|digicam-strong>.<before|after>.jpg in the output folder (default
# ~/Documents/Emulsion Review/renders/<base>-vs-<head>), so Quick Look can flip between a pair (a base
# without the digicam process renders only the film looks).
# Samples: EMULSION_REVIEW_SAMPLES, else ~/Documents/Emulsion Research/samples/proraw-misc;
# only *_CC0.dng files are rendered, unless EMULSION_REVIEW_INCLUDE_LOCAL=1, which also renders the
# other DNGs into local-only/ (the owner's review only; never share them). Nothing here goes into git.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
base=${1:-origin/main}
case "$base" in origin/*) git -C "$root" fetch --quiet origin ;; esac
base_sha=$(git -C "$root" rev-parse --short "$base^{commit}")
head_sha=$(git -C "$root" rev-parse --short HEAD)
if [ -n "$(git -C "$root" status --porcelain)" ]; then head_sha="$head_sha-dirty"; fi
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

# One test process per look: later full-size renders in one process can come out with corrupt
# tiles (MOV-147). A base whose ReviewRenders predates EMULSION_REVIEW_LOOK renders every look at once.
looks="neutral default digicam digicam-strong"
render() { # <package folder> <label>
  if grep -q EMULSION_REVIEW_LOOK "$1/Tests/EmulsionCoreTests/ReviewRenders.swift"; then
    for look in $looks; do (cd "$1" && EMULSION_REVIEW_LABEL=$2 EMULSION_REVIEW_LOOK=$look swift test --filter ReviewRenders); done
  else
    (cd "$1" && EMULSION_REVIEW_LABEL=$2 swift test --filter ReviewRenders)
  fi
}
echo "Rendering before ($base_sha)..."
render "$tmp/base/Packages/EmulsionCore" before
echo "Rendering after ($head_sha)..."
render "$root/Packages/EmulsionCore" after
echo "Review renders: $out"
