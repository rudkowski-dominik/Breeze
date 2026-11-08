#!/bin/zsh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$ROOT_DIR/Breeze.app"

echo "=== Building Breeze for Apple Silicon (Mac mini M5 Pro) ==="

# 1. Process user icons if needed
if [ ! -f "$ROOT_DIR/AppIcon.icns" ] || [ ! -f "$ROOT_DIR/assets/AppIcon-Light.png" ]; then
    echo "Processing Liquid Glass user icons..."
    swift "$SCRIPT_DIR/process_user_icons.swift"
    iconutil -c icns "$ROOT_DIR/AppIcon.iconset" -o "$ROOT_DIR/AppIcon.icns"
    iconutil -c icns "$ROOT_DIR/AppIcon-Dark.iconset" -o "$ROOT_DIR/assets/AppIcon-Dark.icns"
    iconutil -c icns "$ROOT_DIR/AppIcon-Light.iconset" -o "$ROOT_DIR/assets/AppIcon-Light.icns"
    rm -rf "$ROOT_DIR"/*.iconset
fi

# 2. Compile Privileged Helper
echo "Compiling breeze-helper..."
swiftc -O -framework IOKit -framework Foundation \
    -o "$ROOT_DIR/breeze-helper" \
    "$ROOT_DIR/Sources/Helper/main.swift"

# 3. Compile Main App
echo "Compiling Breeze main application..."
swiftc -O -framework Cocoa -framework SwiftUI -framework IOKit \
    -o "$ROOT_DIR/Breeze" \
    "$ROOT_DIR/Sources/Breeze/SMC/SMCEngine.swift" \
    "$ROOT_DIR/Sources/Breeze/Models/FanProfile.swift" \
    "$ROOT_DIR/Sources/Breeze/Services/LocalizationManager.swift" \
    "$ROOT_DIR/Sources/Breeze/Services/HelperClient.swift" \
    "$ROOT_DIR/Sources/Breeze/Services/FanManager.swift" \
    "$ROOT_DIR/Sources/Breeze/UI/GaugeMenuItemView.swift" \
    "$ROOT_DIR/Sources/Breeze/UI/MenuBarController.swift" \
    "$ROOT_DIR/Sources/Breeze/UI/Views/ProfileEditorView.swift" \
    "$ROOT_DIR/Sources/Breeze/UI/Views/SettingsView.swift" \
    "$ROOT_DIR/Sources/Breeze/UI/SettingsWindowController.swift" \
    "$ROOT_DIR/Sources/Breeze/AppDelegate.swift" \
    "$ROOT_DIR/Sources/Breeze/main.swift"

# 4. Create macOS .app Bundle
echo "Assembling Breeze.app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Library/LaunchServices"

cp "$ROOT_DIR/Breeze" "$APP_DIR/Contents/MacOS/Breeze"
cp "$ROOT_DIR/breeze-helper" "$APP_DIR/Contents/Library/LaunchServices/breeze-helper"
cp "$ROOT_DIR/breeze-helper" "$APP_DIR/Contents/MacOS/breeze-helper"
cp "$ROOT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/assets/AppIcon-Light.png" "$APP_DIR/Contents/Resources/AppIcon-Light.png"
cp "$ROOT_DIR/assets/AppIcon-Dark.png" "$APP_DIR/Contents/Resources/AppIcon-Dark.png"

# 5. Generate Info.plist
cat << 'PLIST' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Breeze</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.breeze.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Breeze</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "=== Build Complete! Application created at: $APP_DIR ==="
