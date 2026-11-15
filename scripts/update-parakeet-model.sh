#!/usr/bin/env bash
# Pin the Parakeet TDT 0.6B v2 int8 model to Hugging Face's latest revision.
#
# Usage:
#   scripts/update-parakeet-model.sh           # bump the pin and hashes in place
#   scripts/update-parakeet-model.sh --check   # exit 1 when the pin is stale
#
# The revision and every file hash live in a marked block in
# modules/home-manager/services/dictated/default.nix. The URL pins a commit, not
# `resolve/main`, so a rebuild can never silently swap model weights; this
# script is how the pin moves forward.
#
# Hashes come from the Hugging Face tree API (`lfs.oid` is the SHA-256 of the
# stored bytes), so checking for and applying an update costs a few kilobytes.
# Files not stored in LFS (tokens.txt) are downloaded to be hashed; that one is
# 9 KB.

set -euo pipefail

REPO="csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8"
TARGET="modules/home-manager/services/dictated/default.nix"
FILES=(encoder.int8.onnx decoder.int8.onnx joiner.int8.onnx tokens.txt)
API="https://huggingface.co/api/models/${REPO}"

mode="update"
case "${1:-}" in
  "") ;;
  --check) mode="check" ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

for dep in curl jq sha256sum nix; do
  command -v "$dep" >/dev/null || { echo "error: $dep is required" >&2; exit 1; }
done

root=$(git rev-parse --show-toplevel)
file="$root/$TARGET"
[[ -f "$file" ]] || { echo "error: $TARGET not found" >&2; exit 1; }

hex_to_sri() { nix hash convert --hash-algo sha256 --to sri "$1"; }

latest=$(curl -fsSL "$API/commits/main?limit=1" | jq -er '.[0].id')
pinned=$(sed -n 's/^ *modelRev = "\([^"]*\)";$/\1/p' "$file")
[[ -n "$pinned" ]] || { echo "error: no modelRev pin in $TARGET" >&2; exit 1; }

tree=$(curl -fsSL "$API/tree/$latest")

declare -A hashes
for name in "${FILES[@]}"; do
  oid=$(jq -er --arg p "$name" '.[] | select(.path == $p) | .lfs.oid // empty' <<<"$tree" 2>/dev/null || true)
  if [[ -z "${oid:-}" ]]; then
    # Not an LFS object: the tree only carries a git blob id, so hash the bytes.
    oid=$(curl -fsSL "https://huggingface.co/$REPO/resolve/$latest/$name" | sha256sum | cut -d' ' -f1)
  fi
  hashes[$name]=$(hex_to_sri "$oid")
done

current_hash() {
  sed -n "s|^ *\"$1\" = \"\(sha256-[^\"]*\)\";$|\1|p" "$file"
}

stale=0
[[ "$latest" != "$pinned" ]] && stale=1
for name in "${FILES[@]}"; do
  [[ "$(current_hash "$name")" == "${hashes[$name]}" ]] || stale=1
done

if ((!stale)); then
  echo "parakeet model pin is current ($pinned)"
  exit 0
fi

echo "pinned: $pinned"
echo "latest: $latest"
for name in "${FILES[@]}"; do
  printf '  %-18s %s -> %s\n' "$name" "$(current_hash "$name")" "${hashes[$name]}"
done

if [[ "$mode" == "check" ]]; then
  echo "stale: run scripts/update-parakeet-model.sh" >&2
  exit 1
fi

sed -i -E "s|^ *modelRev = \"[^\"]*\";$|  modelRev = \"$latest\";|" "$file"
for name in "${FILES[@]}"; do
  sed -i -E "s|^ *\"$name\" = \"sha256-[^\"]*\";$|    \"$name\" = \"${hashes[$name]}\";|" "$file"
done

echo "updated $TARGET"
echo "verify with: nix build .#homeConfigurations.\"minttea@desktop\".activationPackage"
