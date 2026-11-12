#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
archive="Vendor/Syphon-source-f476167.zip"
expected="7ca4824406ae51aad1f357078f5979c79bb35f74099b6380feb21c400b5cdd60"
actual=$(shasum -a 256 "$archive" | awk '{print $1}')
[[ "$actual" == "$expected" ]] || { echo "Syphon source checksum mismatch." >&2; exit 1; }
work=$(mktemp -d "${TMPDIR:-/tmp}/SubtitleStage-Syphon.XXXXXX")
unzip -q "$archive" -d "$work/source"
source_root="$work/source/Syphon-Syphon-Framework-f476167"
xcodebuild -project "$source_root/Syphon.xcodeproj" -scheme Syphon -configuration Release     -derivedDataPath "$work/build" ARCHS='x86_64 arm64' ONLY_ACTIVE_ARCH=NO     CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=13.0 build
ditto "$work/build/Build/Products/Release/Syphon.framework" Vendor/Syphon.framework
cp "$source_root/License.txt" Vendor/Syphon-LICENSE.txt
lipo -archs Vendor/Syphon.framework/Syphon
echo "Built Syphon from pinned source. Build logs and sources: $work"
