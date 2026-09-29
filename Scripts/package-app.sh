#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
OUTPUT_BUNDLE="$PROJECT_ROOT/outputs/FieldScout.app"

cd "$PROJECT_ROOT"
swift build -c release --arch arm64 --arch x86_64 --product FieldScout
RELEASE_BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
SPARKLE_FRAMEWORK="$(find "$PROJECT_ROOT/.build/artifacts" -path '*/Sparkle.framework' -type d | head -1)"

if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
    echo "Sparkle.framework was not found in SwiftPM artifacts." >&2
    exit 1
fi

mkdir -p "$OUTPUT_BUNDLE/Contents/MacOS" "$OUTPUT_BUNDLE/Contents/Resources" "$OUTPUT_BUNDLE/Contents/Frameworks"
cp "$RELEASE_BIN_DIR/FieldScout" "$OUTPUT_BUNDLE/Contents/MacOS/FieldScout"
cp "$PROJECT_ROOT/Resources/Info.plist" "$OUTPUT_BUNDLE/Contents/Info.plist"
cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$OUTPUT_BUNDLE/Contents/Resources/AppIcon.icns"
ditto "$SPARKLE_FRAMEWORK" "$OUTPUT_BUNDLE/Contents/Frameworks/Sparkle.framework"
chmod +x "$OUTPUT_BUNDLE/Contents/MacOS/FieldScout"
codesign --force --deep --sign - "$OUTPUT_BUNDLE/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$OUTPUT_BUNDLE"
codesign --verify --deep --strict "$OUTPUT_BUNDLE"

echo "$OUTPUT_BUNDLE"
