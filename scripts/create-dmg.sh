#!/bin/zsh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DMG_NAME="Breeze-1.0.0.dmg"
DMG_PATH="$ROOT_DIR/$DMG_NAME"
STAGING_DIR="$ROOT_DIR/dmg_staging"

echo "=== Building Distributable DMG: $DMG_NAME ==="

# Ensure app is built
if [ ! -d "$ROOT_DIR/Breeze.app" ]; then
    "$SCRIPT_DIR/build.sh"
fi

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# 1. Copy Breeze.app
echo "Copying Breeze.app to staging..."
cp -R "$ROOT_DIR/Breeze.app" "$STAGING_DIR/"

# 2. Create symlink to /Applications
echo "Creating /Applications link..."
ln -s /Applications "$STAGING_DIR/Applications"

# 3. Add one-click helper installer script directly inside DMG
cat << 'EOF' > "$STAGING_DIR/Install Privileged Helper.command"
#!/bin/zsh
echo "=== Installing Breeze Privileged Helper Daemon ==="
echo "This installs com.breeze.helper to enable seamless fan control."
echo ""
sudo mkdir -p /Library/PrivilegedHelperTools
HELPER_SRC="$(dirname "$0")/Breeze.app/Contents/Library/LaunchServices/breeze-helper"
if [ ! -f "$HELPER_SRC" ]; then
    HELPER_SRC="/Applications/Breeze.app/Contents/Library/LaunchServices/breeze-helper"
fi
sudo cp "$HELPER_SRC" /Library/PrivilegedHelperTools/com.breeze.helper
sudo chown root:wheel /Library/PrivilegedHelperTools/com.breeze.helper
sudo chmod 755 /Library/PrivilegedHelperTools/com.breeze.helper

cat << 'PLIST' | sudo tee /Library/LaunchDaemons/com.breeze.helper.plist > /dev/null
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.breeze.helper</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Library/PrivilegedHelperTools/com.breeze.helper</string>
        <string>daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
PLIST

sudo chown root:wheel /Library/LaunchDaemons/com.breeze.helper.plist
sudo chmod 644 /Library/LaunchDaemons/com.breeze.helper.plist
sudo launchctl unload /Library/LaunchDaemons/com.breeze.helper.plist 2>/dev/null || true
sudo launchctl load -w /Library/LaunchDaemons/com.breeze.helper.plist

echo ""
echo "✅ Privileged Helper successfully installed! You can now close this window."
EOF
chmod +x "$STAGING_DIR/Install Privileged Helper.command"

# 4. Create DMG image
echo "Creating compressed UDZO disk image with hdiutil..."
rm -f "$DMG_PATH"
hdiutil create -volname "Breeze" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "=== DMG Build Complete: $DMG_PATH ==="
ls -lh "$DMG_PATH"
