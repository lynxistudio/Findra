#!/bin/bash
set -e

# FastFinder Build Script
# Compiles SwiftUI app and packages as .app bundle

APP_NAME="FastFinder"
BUILD_DIR=$(dirname "$0")
SRC_DIR="$BUILD_DIR/Sources"
OUTPUT_APP="$HOME/Desktop/FastFinder.app"
ICNS_PATH="$BUILD_DIR/AppIcon.icns"

echo "=== FastFinder Build ==="
echo "SDK: $(xcrun --show-sdk-path)"
echo ""

# Clean previous build
rm -rf "$OUTPUT_APP"

# Compile Swift sources into a single Mach-O binary
echo "--- Compiling Swift sources ---"
SDK=$(xcrun --show-sdk-path)
FRAMEWORKS="SwiftUI AppKit Quartz"
FW_FLAGS=""
for fw in $FRAMEWORKS; do
    FW_FLAGS="$FW_FLAGS -F $SDK/System/Library/Frameworks -framework $fw"
done

cd "$SRC_DIR"
swiftc \
    -sdk "$SDK" \
    -target arm64-apple-macos14.0 \
    $FW_FLAGS \
    -lsqlite3 \
    -O \
    *.swift \
    -o "$BUILD_DIR/FastFinder"

echo "Compilation successful!"

# Create .app bundle structure
echo "--- Creating .app bundle ---"
mkdir -p "$OUTPUT_APP/Contents/MacOS"
mkdir -p "$OUTPUT_APP/Contents/Resources"

# Move binary into bundle
mv "$BUILD_DIR/FastFinder" "$OUTPUT_APP/Contents/MacOS/FastFinder"

# Copy icon
if [ -f "$ICNS_PATH" ]; then
    cp "$ICNS_PATH" "$OUTPUT_APP/Contents/Resources/AppIcon.icns"
    echo "Icon copied"
else
    echo "WARNING: Icon not found at $ICNS_PATH"
fi

# Create Info.plist
cat > "$OUTPUT_APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>FastFinder</string>
    <key>CFBundleExecutable</key>
    <string>FastFinder</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.fastfinder.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>FastFinder</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>200</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
PLIST

echo "Info.plist created"

# Ad-hoc code signing
echo "--- Signing ---"
codesign --force --deep --sign - "$OUTPUT_APP" 2>/dev/null || true

echo ""
echo "=== Build Complete ==="
echo "App: $OUTPUT_APP"
echo "Size: $(du -sh "$OUTPUT_APP" | cut -f1)"
echo ""
echo "To run: open $OUTPUT_APP"