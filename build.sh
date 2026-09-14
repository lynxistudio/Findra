#!/bin/bash
set -e

# Findra Build Script
# Compiles SwiftUI app and packages as .app bundle

APP_NAME="Findra"
BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$BUILD_DIR/Sources"
OUTPUT_APP="${OUTPUT_APP:-/Applications/Findra.app}"
ICNS_PATH="$BUILD_DIR/AppIcon.icns"

echo "=== Findra Build ==="
echo "SDK: $(xcrun --show-sdk-path)"
echo ""

# Clean previous build
rm -rf "$OUTPUT_APP"

# Compile Swift sources into a single Mach-O binary
echo "--- Compiling Swift sources ---"
SDK=$(xcrun --show-sdk-path)
FRAMEWORKS="SwiftUI AppKit Quartz QuickLookThumbnailing AVFoundation ImageIO"
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
    -o "$BUILD_DIR/Findra"

echo "Compilation successful!"

# Create .app bundle structure
echo "--- Creating .app bundle ---"
mkdir -p "$OUTPUT_APP/Contents/MacOS"
mkdir -p "$OUTPUT_APP/Contents/Resources"

# Move binary into bundle
mv "$BUILD_DIR/Findra" "$OUTPUT_APP/Contents/MacOS/Findra"

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
    <string>Findra</string>
    <key>CFBundleExecutable</key>
    <string>Findra</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.lynxistudio.findra</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Findra</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.2.0</string>
    <key>CFBundleVersion</key>
    <string>220</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Findra needs access to your Documents folder to index and browse your files.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Findra needs access to your Downloads folder to index and browse your files.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>Findra needs access to external and removable volumes to index and manage your files.</string>
    <key>NSNetworkVolumesUsageDescription</key>
    <string>Findra needs access to network volumes (SMB/NFS) to index and manage your remote files.</string>
</dict>
</plist>
PLIST

echo "Info.plist created"

# Classic app bundle marker for LaunchServices compatibility
printf 'APPL????' > "$OUTPUT_APP/Contents/PkgInfo"

# Ad-hoc code signing with stable identifier to preserve macOS TCC permissions across builds
echo "--- Signing ---"
codesign --force --deep -s - -i "com.lynxistudio.findra" -r='designated => identifier "com.lynxistudio.findra"' "$OUTPUT_APP" 2>/dev/null || true

# Remove quarantine/provenance flags so macOS doesn't treat it as an unverified download
xattr -cr "$OUTPUT_APP" 2>/dev/null || true

echo ""
echo "=== Build Complete ==="
echo "App: $OUTPUT_APP"
echo "Size: $(du -sh "$OUTPUT_APP" | cut -f1)"
echo ""
echo "To run: open $OUTPUT_APP"
