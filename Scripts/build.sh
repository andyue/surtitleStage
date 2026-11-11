#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
build_arch() {
    local arch="$1"
    swift build --disable-sandbox --cache-path ".build/cache-$arch" --config-path ".build/config-$arch" --security-path ".build/security-$arch" --manifest-cache local --configuration release --triple "$arch-apple-macosx14.0"
}
bin_path() {
    local arch="$1"
    swift build --disable-sandbox --cache-path ".build/cache-$arch" --config-path ".build/config-$arch" --security-path ".build/security-$arch" --manifest-cache local --configuration release --triple "$arch-apple-macosx14.0" --show-bin-path
}
build_arch x86_64
build_arch arm64
x86_bin="$(bin_path x86_64)/SubtitleStage"
arm_bin="$(bin_path arm64)/SubtitleStage"
bundle_root=$(mktemp -d "${TMPDIR:-/tmp}/SubtitleStage.XXXXXX")
app="$bundle_root/SubtitleStage.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create "$x86_bin" "$arm_bin" -output "$app/Contents/MacOS/SubtitleStage"
mkdir -p "$app/Contents/Frameworks"
ditto --norsrc Vendor/Syphon.framework "$app/Contents/Frameworks/Syphon.framework"
cp Vendor/Syphon-LICENSE.txt "$app/Contents/Resources/Syphon-LICENSE.txt"
cp Vendor/Syphon-Metal-LICENSE.txt "$app/Contents/Resources/Syphon-Metal-LICENSE.txt"
cp Vendor/NDI-Headers-LICENSE.txt "$app/Contents/Resources/NDI-Headers-LICENSE.txt"
cp Scripts/Credits.rtf "$app/Contents/Resources/Credits.rtf"
cp Scripts/Info.plist "$app/Contents/Info.plist"
iconset="$bundle_root/SubtitleStage.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" Scripts/AppIcon.svg --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -s format png -z "$retina" "$retina" Scripts/AppIcon.svg --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
# iCloud/Finder may attach metadata that codesign rejects on generated bundles.
xattr -cr "$app"
codesign --force --sign - "$app/Contents/Frameworks/Syphon.framework"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
package_root=$(mktemp -d "${TMPDIR:-/tmp}/SubtitleStage-Release.XXXXXX")
release_folder="$package_root/SubtitleStage Release"
mkdir -p "$release_folder"
ditto --norsrc "$app" "$release_folder/SubtitleStage.app"
cp Scripts/INSTALL.txt "$release_folder/INSTALL.txt"
archive_temp="$package_root/SubtitleStage.zip"
ditto -c -k --keepParent --norsrc "$release_folder" "$archive_temp"
mv "$archive_temp" "$PWD/.build/SubtitleStage.zip"
hdiutil create -quiet -volname "SubtitleStage" -srcfolder "$release_folder" -format UDZO -ov "$package_root/SubtitleStage.dmg"
mv "$package_root/SubtitleStage.dmg" "$PWD/.build/SubtitleStage.dmg"
printf '%s\n' "$app" > .build/app-path.txt
echo "Built $app"
echo "Archive: $PWD/.build/SubtitleStage.zip"
echo "Disk image: $PWD/.build/SubtitleStage.dmg"

# Keep deliverables visible in Finder; compilation caches remain in .build.
app_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
app_build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$app/Contents/Info.plist")
mkdir -p "$PWD/dist"
cp "$PWD/.build/SubtitleStage.dmg" "$PWD/dist/SubtitleStage-$app_version-build$app_build.dmg"
echo "Visible disk image: $PWD/dist/SubtitleStage-$app_version-build$app_build.dmg"
