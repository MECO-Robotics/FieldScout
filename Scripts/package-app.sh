#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
OUTPUT_BUNDLE="$PROJECT_ROOT/outputs/FieldScout.app"

cd "$PROJECT_ROOT"
swift build -c release --product FieldScout
RELEASE_BIN_DIR="$(swift build -c release --show-bin-path)"

mkdir -p "$OUTPUT_BUNDLE/Contents/MacOS" "$OUTPUT_BUNDLE/Contents/Resources"
cp "$RELEASE_BIN_DIR/FieldScout" "$OUTPUT_BUNDLE/Contents/MacOS/FieldScout"
cp "$PROJECT_ROOT/Resources/Info.plist" "$OUTPUT_BUNDLE/Contents/Info.plist"
cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$OUTPUT_BUNDLE/Contents/Resources/AppIcon.icns"
chmod +x "$OUTPUT_BUNDLE/Contents/MacOS/FieldScout"
codesign --force --deep --sign - "$OUTPUT_BUNDLE"

echo "$OUTPUT_BUNDLE"
