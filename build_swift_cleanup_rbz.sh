#!/usr/bin/env bash
# Build an installable SketchUp extension package (.rbz) for Swift Cleanup.
#
# An .rbz is just a .zip of the extension files with a different extension.
# SketchUp installs it via Window > Extension Manager > Install Extension.
#
# Usage: ./build_swift_cleanup_rbz.sh
# Output: dist/SwiftCleanup-<version>.rbz
set -euo pipefail

cd "$(dirname "$0")"

STUB="sketchup_swift_cleanup.rb"
FOLDER="swift_cleanup"

# Pull the version straight from the registration stub so the filename tracks it.
VERSION="$(grep -oE 'ex\.version[[:space:]]*=[[:space:]]*"[^"]+"' "$STUB" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo 0.0.0)"

mkdir -p dist
OUT="dist/SwiftCleanup-${VERSION}.rbz"
rm -f "$OUT"

# Zip only what belongs in the Plugins folder: the stub + the extension folder.
# Exclude editor cruft and OS junk.
zip -r -q "$OUT" "$STUB" "$FOLDER" \
  -x '*.DS_Store' -x '*/.*' -x '__MACOSX/*'

echo "Built $OUT"
unzip -l "$OUT"
