# Building and installing

Use macOS 15+ on Intel or Apple Silicon with Swift 6 Command Line Tools. No Xcode project, downloaded package or Apple Developer Program membership is required.

```sh
swift test --disable-xctest
sh Scripts/build-release.sh arm64
sh Scripts/build-release.sh x86_64
```

The outputs are `dist/Apple-Silicon/VideoLoggerFCP.app` (arm64) and `dist/Intel/VideoLoggerFCP.app` (x86_64). Each bundle includes its icon, license, Polish and English resources, and a verified ad-hoc signature. Running the script without an argument retains the Intel output at `dist/VideoLoggerFCP.app` for the legacy build and ZIP scripts.

The entire bundle for the chosen architecture is standalone. Copy it with Finder to `/Applications` and launch by double-click. Do not copy only its executable. No installation is performed automatically. Quit older prototypes before switching versions; their in-memory sessions are not transferred. No Terminal is needed for daily use.

This release is not notarized and is not Developer ID signed. A downloaded copy may require Apple's supported **Open Anyway** flow after you verify its provenance. Do not disable Gatekeeper globally. See [Apple's opening guidance](https://support.apple.com/en-gb/102445).

## Icon regeneration

```sh
swift Scripts/generate-icon.swift
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
```

The Swift drawing script is the authoritative renderer for original artwork; the SVG is an editable vector reference. PNG sizes cover standard 16–512 point iconset entries at 1x/2x, including 1024×1024. The build uses the checked-in ICNS, so regeneration is optional.

## CLI

```sh
swift build --configuration release --product videologger
swift run videologger --help
```

`Package.resolved` and shared SwiftPM configuration should be tracked if introduced. User-specific caches, build output, private projects/media, local logs and agent files are ignored. No commits or publishing are part of the build process.

## Localized resources

The build includes English and Polish root lproj directories and the VideoLoggerLocalization resource bundle. Info.plist declares English development language and both supported localizations. Per-app language preferences belong to macOS; no custom switch is required.

For a reproducible synthetic demonstration (no user media):

```sh
swift Scripts/prepare-demo.swift
open -n dist/Apple-Silicon/VideoLoggerFCP.app --args -AppleLanguages '(en)' --open "$PWD/.local/README-demo"
```

The generator refuses to overwrite an existing demo folder. Generated movies/LLC remain ignored in .local/. The launch override is for testing/capture and does not persist a system setting.
