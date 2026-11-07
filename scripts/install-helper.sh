#!/bin/zsh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
HELPER_BIN="$ROOT_DIR/breeze-helper"

if [ ! -f "$HELPER_BIN" ]; then
    echo "breeze-helper not found. Compiling first..."
    "$SCRIPT_DIR/build.sh"
fi

echo "=== Installing Breeze Privileged Helper Daemon ==="
echo "This requires administrator privileges to place the helper in /Library/PrivilegedHelperTools."

sudo mkdir -p /Library/PrivilegedHelperTools
sudo cp "$HELPER_BIN" /Library/PrivilegedHelperTools/com.breeze.helper
sudo chown root:wheel /Library/PrivilegedHelperTools/com.breeze.helper
sudo chmod 755 /Library/PrivilegedHelperTools/com.breeze.helper

# Create launchd plist daemon
PLIST_PATH="/Library/LaunchDaemons/com.breeze.helper.plist"
sudo cat << 'EOF' > /tmp/com.breeze.helper.plist
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
EOF

sudo mv /tmp/com.breeze.helper.plist "$PLIST_PATH"
sudo chown root:wheel "$PLIST_PATH"
sudo chmod 644 "$PLIST_PATH"

sudo launchctl unload "$PLIST_PATH" 2>/dev/null || true
sudo launchctl load -w "$PLIST_PATH"

echo "=== Helper daemon successfully installed and started! ==="
echo "Socket: /var/run/breeze.sock"
