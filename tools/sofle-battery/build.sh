#!/bin/sh
# Builds SofleBattery.app and installs it into /Applications.
set -e

cd "$(dirname "$0")"
app="/Applications/SofleBattery.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -O main.swift -o "$app/Contents/MacOS/SofleBattery"

iconset="$(mktemp -d)/AppIcon.iconset"
swift make-icon.swift "$iconset"
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.matheusrossi.soflebattery</string>
  <key>CFBundleName</key><string>SofleBattery</string>
  <key>CFBundleExecutable</key><string>SofleBattery</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>Reads the battery level of both Sofle keyboard halves.</string>
</dict>
</plist>
EOF

codesign --force --sign - "$app"
echo "Installed $app"
