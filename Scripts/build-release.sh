#!/bin/sh
set -eu
project_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_directory"
if [ -L "$project_directory/dist" ] || [ -L "$project_directory/.build" ]; then
    echo 'Refusing symbolic links for build/output directories.' >&2; exit 1
fi
swift build --configuration release --arch x86_64 --product videologger-drag
binary_directory=$(swift build --configuration release --arch x86_64 --show-bin-path)
staging_directory=$(mktemp -d "$project_directory/.build/release-bundle.XXXXXX")
trap 'rm -rf "$staging_directory"' EXIT HUP INT TERM
app_directory="$staging_directory/VideoLoggerFCP.app"
mkdir -p "$app_directory/Contents/MacOS" "$app_directory/Contents/Resources" "$project_directory/dist"
/usr/bin/install -m 755 "$binary_directory/videologger-drag" "$app_directory/Contents/MacOS/VideoLoggerFCP"
/usr/bin/strip -S "$app_directory/Contents/MacOS/VideoLoggerFCP"
/usr/bin/install -m 644 Resources/Info.plist "$app_directory/Contents/Info.plist"
/usr/bin/install -m 644 Resources/AppIcon.icns "$app_directory/Contents/Resources/AppIcon.icns"
/usr/bin/install -m 644 LICENSE "$app_directory/Contents/Resources/LICENSE"
localization_bundle="$binary_directory/VideoLoggerFCP_VideoLoggerLocalization.bundle"
[ -d "$localization_bundle" ] || { echo 'Missing localization resource bundle.' >&2; exit 1; }
cp -R "$localization_bundle" "$app_directory/Contents/Resources/"
for language in en pl; do
    cp -R "$localization_bundle/$language.lproj" "$app_directory/Contents/Resources/"
    /usr/bin/plutil -lint "$app_directory/Contents/Resources/$language.lproj/Localizable.strings"
done
/usr/bin/plutil -lint "$app_directory/Contents/Info.plist"
/usr/bin/codesign --force --sign - --timestamp=none "$app_directory"
/usr/bin/codesign --verify --deep --strict "$app_directory"
target_directory="$project_directory/dist/VideoLoggerFCP.app"
if [ -L "$target_directory" ]; then
    echo 'Refusing to replace a symbolic link at the output path.' >&2; exit 1
fi
if [ -e "$target_directory" ]; then
    existing_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$target_directory/Contents/Info.plist")
    [ "$existing_id" = 'com.wandachowicz.VideoLoggerFCP' ] || { echo 'Unexpected application at output path.' >&2; exit 1; }
    rm -rf "$target_directory"
fi
mv "$app_directory" "$target_directory"
printf '%s\n' "$target_directory"
