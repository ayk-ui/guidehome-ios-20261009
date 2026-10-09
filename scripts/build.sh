#!/bin/bash
set -euo pipefail
TASK_PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_BUILD_DIR="${GUIDE_BUILD_DIR:-${TASK_PROJECT_ROOT}/build}"
TASK_MODE="${1:-unsigned}"
TASK_BUNDLE_ID="${GUIDE_BUNDLE_ID:-com.example.guidehome}"
command -v xcodebuild >/dev/null || { printf '%s\n' '需要在 macOS 安装并选择 Xcode。' >&2; exit 1; }
mkdir -p "$TASK_BUILD_DIR"
TASK_BUILD_DIR="$(cd "$TASK_BUILD_DIR" && pwd)"
TASK_COMMON=(-project "$TASK_PROJECT_ROOT/GuideHome.xcodeproj" -scheme GuideHome -configuration Release -destination 'generic/platform=iOS' -derivedDataPath "$TASK_BUILD_DIR/DerivedData" "PRODUCT_BUNDLE_IDENTIFIER=$TASK_BUNDLE_ID")
case "$TASK_MODE" in
  unsigned)
    xcodebuild "${TASK_COMMON[@]}" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= build
    TASK_APP="$TASK_BUILD_DIR/DerivedData/Build/Products/Release-iphoneos/GuideHome.app"
    test -f "$TASK_APP/GuideHome"
    /usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$TASK_APP/Info.plist" | /usr/bin/grep -qx APPL
    TASK_STAGE="$(mktemp -d "$TASK_BUILD_DIR/unsigned-payload.XXXXXX")"
    mkdir -p "$TASK_STAGE/Payload" "$TASK_BUILD_DIR/unsigned"
    ditto "$TASK_APP" "$TASK_STAGE/Payload/GuideHome.app"
    TASK_IPA="$TASK_BUILD_DIR/unsigned/GuideHome-unsigned.ipa"
    (cd "$TASK_STAGE" && /usr/bin/zip -q -r "$TASK_STAGE/GuideHome-unsigned.ipa" Payload)
    cp "$TASK_STAGE/GuideHome-unsigned.ipa" "$TASK_IPA"
    shasum -a 256 "$TASK_IPA" > "$TASK_IPA.sha256"
    printf '%s\n' '生成的是未签名 IPA，不能直接安装到 iPhone。' > "$TASK_BUILD_DIR/unsigned/未签名说明.txt"
    printf '%s\n' "$TASK_IPA"
    ;;
  archive)
    : "${GUIDE_DEVELOPMENT_TEAM:?请设置自己的 Apple Team ID；不要填写密码或证书内容。}"
    xcodebuild "${TASK_COMMON[@]}" "DEVELOPMENT_TEAM=$GUIDE_DEVELOPMENT_TEAM" CODE_SIGN_STYLE=Automatic -archivePath "$TASK_BUILD_DIR/GuideHome.xcarchive" archive
    printf '%s\n' "$TASK_BUILD_DIR/GuideHome.xcarchive"
    ;;
  export)
    : "${GUIDE_EXPORT_OPTIONS:?请指定你自己的合法签名导出配置 plist 文件。}"
    test -d "$TASK_BUILD_DIR/GuideHome.xcarchive"
    test -f "$GUIDE_EXPORT_OPTIONS"
    xcodebuild -exportArchive -archivePath "$TASK_BUILD_DIR/GuideHome.xcarchive" -exportOptionsPlist "$GUIDE_EXPORT_OPTIONS" -exportPath "$TASK_BUILD_DIR/signed-export"
    ;;
  *) printf '%s\n' '用法：bash scripts/build.sh unsigned|archive|export' >&2; exit 2 ;;
esac
