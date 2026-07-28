#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/Agent Pulse.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLUGINS_DIR="$CONTENTS_DIR/PlugIns"
WIDGET_DIR="$PLUGINS_DIR/AgentPulseWidget.appex"
WIDGET_CONTENTS_DIR="$WIDGET_DIR/Contents"
WIDGET_MACOS_DIR="$WIDGET_CONTENTS_DIR/MacOS"
MODULE_CACHE_DIR="$BUILD_DIR/ModuleCache"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICON_SOURCE="$BUILD_DIR/AppIcon-1024.png"

/bin/rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE_DIR" "$ICONSET_DIR" "$WIDGET_MACOS_DIR"

swiftc \
  -O \
  -target arm64-apple-macos13.0 \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -framework AppKit \
  -framework WidgetKit \
  "$ROOT_DIR"/Sources/*.swift \
  -o "$MACOS_DIR/AgentPulse"

swiftc \
  -O \
  -parse-as-library \
  -application-extension \
  -target arm64-apple-macos14.0 \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -framework SwiftUI \
  -framework WidgetKit \
  "$ROOT_DIR"/WidgetExtension/AgentPulseWidget.swift \
  -o "$WIDGET_MACOS_DIR/AgentPulseWidget"

cp "$ROOT_DIR/WidgetExtension/Info.plist" "$WIDGET_CONTENTS_DIR/Info.plist"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT_DIR/Resources/Info.plist")"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$WIDGET_CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD" "$WIDGET_CONTENTS_DIR/Info.plist"
chmod +x "$WIDGET_MACOS_DIR/AgentPulseWidget"

swiftc \
  -O \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -framework AppKit \
  "$ROOT_DIR/Tools/IconGenerator.swift" \
  -o "$BUILD_DIR/IconGenerator"

"$BUILD_DIR/IconGenerator" "$ICON_SOURCE"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"
swiftc \
  -O \
  -module-cache-path "$MODULE_CACHE_DIR" \
  "$ROOT_DIR/Tools/IconPackager.swift" \
  -o "$BUILD_DIR/IconPackager"
"$BUILD_DIR/IconPackager" "$ICONSET_DIR" "$RESOURCES_DIR/AppIcon.icns"

cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/BasketballMascot.png" "$RESOURCES_DIR/BasketballMascot.png"
cp "$ROOT_DIR/Resources/TrumpMascot.png" "$RESOURCES_DIR/TrumpMascot.png"
chmod +x "$MACOS_DIR/AgentPulse"
codesign --force --sign - --entitlements "$ROOT_DIR/WidgetExtension/AgentPulseWidget.entitlements" "$WIDGET_DIR"
codesign --force --sign - --entitlements "$ROOT_DIR/Resources/AgentPulse.entitlements" "$APP_DIR"

echo "$APP_DIR"
