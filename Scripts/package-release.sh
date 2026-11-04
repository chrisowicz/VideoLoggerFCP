#!/bin/sh
set -eu
project_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_directory"
sh Scripts/build-release.sh
app_directory="$project_directory/dist/VideoLoggerFCP.app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_directory/Contents/Info.plist")
architecture=$(/usr/bin/lipo -archs "$app_directory/Contents/MacOS/VideoLoggerFCP")
[ "$architecture" = 'x86_64' ] || { echo 'Expected an Intel-only executable.' >&2; exit 1; }
archive_name="VideoLoggerFCP-$version-macOS-Intel.zip"
archive_path="$project_directory/dist/$archive_name"
checksum_path="$archive_path.sha256"
[ ! -L "$archive_path" ] && [ ! -L "$checksum_path" ] || { echo 'Refusing symbolic-link release outputs.' >&2; exit 1; }
verification_directory=$(mktemp -d "$project_directory/.build/release-archive.XXXXXX")
trap 'rm -rf "$verification_directory"' EXIT HUP INT TERM
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_directory" "$verification_directory/$archive_name"
/usr/bin/unzip -tq "$verification_directory/$archive_name"
/usr/bin/ditto -x -k "$verification_directory/$archive_name" "$verification_directory/extracted"
extracted_app="$verification_directory/extracted/VideoLoggerFCP.app"
/usr/bin/codesign --verify --deep --strict "$extracted_app"
/usr/bin/plutil -lint "$extracted_app/Contents/Info.plist"
[ "$(/usr/bin/lipo -archs "$extracted_app/Contents/MacOS/VideoLoggerFCP")" = 'x86_64' ]
for language in en pl; do
    [ -s "$extracted_app/Contents/Resources/$language.lproj/Localizable.strings" ]
    [ -s "$extracted_app/Contents/Resources/VideoLoggerFCP_VideoLoggerLocalization.bundle/$language.lproj/Localizable.strings" ]
done
/usr/bin/diff -qr "$app_directory" "$extracted_app"
mv "$verification_directory/$archive_name" "$archive_path"
(cd "$project_directory/dist" && /usr/bin/shasum -a 256 "$archive_name" > "$archive_name.sha256" && /usr/bin/shasum -a 256 -c "$archive_name.sha256")
printf '%s\n' "$archive_path" "$checksum_path"
