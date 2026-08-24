#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="PasteMemo"
EXECUTABLE_NAME="PasteMemo"
DEFAULT_BUNDLE_ID="com.lifedever.pastememo"
MIN_SYSTEM_VERSION="14.0"

ARCH="${ARCH:-$(uname -m)}"
CONFIGURATION="${CONFIGURATION:-release}"
BUNDLE_ID="${BUNDLE_ID:-$DEFAULT_BUNDLE_ID}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
BUILD_DIR="$ROOT_DIR/.build/${ARCH}-apple-macosx/${CONFIGURATION}"
PRODUCT_BINARY="$BUILD_DIR/$EXECUTABLE_NAME"
ICON_FILE="$ROOT_DIR/Sources/Resources/AppIcon.icns"

resolve_version() {
  if [[ -n "${VERSION:-}" ]]; then
    printf '%s\n' "$VERSION"
    return 0
  fi

  if git -C "$ROOT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    local tag
    tag="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null || true)"
    tag="${tag#v}"
    if [[ -n "$tag" ]]; then
      printf '%s\n' "$tag"
      return 0
    fi
  fi

  echo "VERSION is not set, and no git tag was found." >&2
  echo "Use: make package VERSION=1.2.3" >&2
  exit 1
}

VERSION="$(resolve_version)"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}-${ARCH}.dmg"
STAGING_DIR="$DIST_DIR/.dmg-staging-${ARCH}"

printf '[package] building %s %s (%s)\n' "$APP_NAME" "$VERSION" "$ARCH"

# 根据不同架构构建 SwiftPM 项目
swift build -c "$CONFIGURATION" --arch "$ARCH"

# 动态获取当前架构输出目录
BUILD_DIR="$(swift build -c "$CONFIGURATION" --arch "$ARCH" --show-bin-path)"
PRODUCT_BINARY="$BUILD_DIR/$EXECUTABLE_NAME"

if [[ ! -x "$PRODUCT_BINARY" ]]; then
  echo "Built binary not found: $PRODUCT_BINARY" >&2
  exit 1
fi

if [[ ! -f "$ICON_FILE" ]]; then
  echo "App icon not found: $ICON_FILE" >&2
  exit 1
fi

rm -rf "$APP_DIR" "$STAGING_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$DIST_DIR"

cp "$PRODUCT_BINARY" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"

# 构建并复制 MCP Proxy 命令行工具（如果存在）
swift build -c "$CONFIGURATION" --arch "$ARCH" --product pastememo-mcp 2>/dev/null || true
if [[ -f "$BUILD_DIR/pastememo-mcp" ]]; then
  cp "$BUILD_DIR/pastememo-mcp" "$APP_DIR/Contents/MacOS/pastememo-mcp"
  chmod +x "$APP_DIR/Contents/MacOS/pastememo-mcp"
fi

cp "$ICON_FILE" "$APP_DIR/Contents/Resources/AppIcon.icns"

# 复制 Localization 语言包标记目录
for lproj in "$ROOT_DIR"/Sources/Localization/*.lproj; do
  if [[ -d "$lproj" ]]; then
    mkdir -p "$APP_DIR/Contents/Resources/$(basename "$lproj")"
  fi
done

# 复制 SwiftPM 生成的所有资源 bundle（如 PermissionFlow 与本地化 bundle）
for bundle in "$BUILD_DIR"/*.bundle; do
  if [[ -d "$bundle" ]]; then
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
    cp -R "$bundle" "$APP_DIR/" 2>/dev/null || true
  fi
done

CURRENT_YEAR="$(date +%Y)"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>${MIN_SYSTEM_VERSION}</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © ${CURRENT_YEAR} lifedever. All rights reserved.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>PasteMemo needs to communicate with Finder to save images to folders.</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
  </dict>
</dict>
</plist>
EOF

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  printf '[package] codesigning app bundle with %s\n' "$CODESIGN_IDENTITY"
  codesign --force --deep --options runtime --sign "$CODESIGN_IDENTITY" "$APP_DIR"
else
  printf '[package] ad-hoc codesigning app bundle\n'
  codesign --force --deep --sign - "$APP_DIR" || true
fi

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"

printf '[package] creating dmg %s\n' "$(basename "$DMG_PATH")"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGING_DIR"

printf '[package] app: %s\n' "$APP_DIR"
printf '[package] dmg: %s\n' "$DMG_PATH"
