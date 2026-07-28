#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT="$SCRIPT_DIR/MouserNative.xcodeproj"
SCHEME="MouserNative"
VERSION="${MOUSER_VERSION:-3.8.2}"
BUILD_NUMBER="${MOUSER_BUILD_NUMBER:-1}"
SIGN_IDENTITY="${MOUSER_SIGN_IDENTITY:-Developer ID Application}"
DEVELOPMENT_TEAM="${MOUSER_DEVELOPMENT_TEAM:-99M5SZBF38}"
NOTARY_PROFILE="${MOUSER_NOTARY_PROFILE:-Mouser-Notary}"
OUTPUT_DIR="${MOUSER_OUTPUT_DIR:-$SCRIPT_DIR/release-$VERSION}"
NOTARIZE=1

if [[ "${1:-}" == "--skip-notarization" ]]; then
  NOTARIZE=0
fi

OUTPUT_DIR="${OUTPUT_DIR:A}"
if [[ "$OUTPUT_DIR" == "/" || "$OUTPUT_DIR" == "$SCRIPT_DIR" ]]; then
  print -u2 "拒绝使用不安全的输出目录：$OUTPUT_DIR"
  exit 1
fi

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    print -u2 "缺少构建工具：$1"
    exit 1
  }
}

require_command xcodegen
require_command xcodebuild
require_command codesign
require_command diskutil
require_command xcrun

if ! security find-identity -v -p codesigning | grep -F "$SIGN_IDENTITY" >/dev/null; then
  print -u2 "未找到 Developer ID 签名：$SIGN_IDENTITY"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
cd "$SCRIPT_DIR"
xcodegen generate

build_configuration() {
  local configuration="$1"
  local suffix="$2"
  local archive="$OUTPUT_DIR/Mouser-$configuration.xcarchive"
  local app_dir="$OUTPUT_DIR/$configuration"
  local app="$app_dir/Mouser.app"
  local dmg="$OUTPUT_DIR/Mouser-$VERSION$suffix.dmg"
  local image_root="$OUTPUT_DIR/.dmg-$configuration"

  rm -rf "$archive" "$app_dir" "$image_root" "$dmg"
  xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$configuration" \
    -archivePath "$archive" \
    -destination 'generic/platform=macOS' \
    ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    OTHER_CODE_SIGN_FLAGS='--timestamp'

  mkdir -p "$app_dir" "$image_root"
  ditto "$archive/Products/Applications/Mouser.app" "$app"
  codesign --verify --deep --strict --verbose=2 "$app"

  if (( NOTARIZE )); then
    ditto -c -k --keepParent "$app" "$OUTPUT_DIR/Mouser-$configuration.app.zip"
    xcrun notarytool submit \
      "$OUTPUT_DIR/Mouser-$configuration.app.zip" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
  fi

  ditto "$app" "$image_root/Mouser.app"
  ln -s /Applications "$image_root/Applications"
  diskutil image create from \
    --format UDZO \
    --volumeName "Mouser $VERSION" \
    "$image_root" \
    "$dmg"
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$dmg"
  codesign --verify --verbose=2 "$dmg"

  if (( NOTARIZE )); then
    xcrun notarytool submit \
      "$dmg" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait
    xcrun stapler staple "$dmg"
    xcrun stapler validate "$dmg"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
  fi

  rm -rf "$image_root"
  shasum -a 256 "$dmg"
}

build_configuration Release ""
build_configuration Debug "-debug"

print "原生发行包已生成：$OUTPUT_DIR"
