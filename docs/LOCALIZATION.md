# English and Polish localization

Date: 2026-11-04. VideoLoggerFCP 1.0.0, build 101, macOS Sequoia 15.7.9 / Intel.

## Implementation

The Foundation-only VideoLoggerLocalization module contains 168 unique localized UI/diagnostic keys in native en.lproj/pl.lproj Localizable.strings files. English is the development language and fallback. All owned application menus, controls, filters, statuses, progress, drag messages, dialogs and conversion/library diagnostics use these resources. Technical identifiers and user filenames, segment names and paths remain data and are not translated.

Foundation negotiates the full ordered macOS preference array. Examples: `[pl,en] → pl`, `[en,pl] → en`, `[de] → en`, `[de,pl,en] → pl`, `[de,en,pl] → en`. Standard per-app AppleLanguages overrides are honored; no custom language selector or persistent preference is written by the application. Missing Polish values use the English table for that key.

Info.plist declares English CFBundleDevelopmentRegion and en/pl CFBundleLocalizations. The SwiftPM package also declares English defaultLocalization. Release packaging includes native root lproj directories and the localization resource bundle in Contents/Resources. Runtime lookup checks relative app/executable resource paths without a private development-path fallback. Release debug symbols are stripped before signing.

After installing the updated bundle, users can choose System Settings → General → Language & Region → Applications → VideoLoggerFCP, select English or Polish and relaunch.

## Verification

| Check | Result |
| --- | --- |
| Full automatic regression | 83 definitions: 81 PASS, 2 optional real-media tests skipped |
| Ordered native language resolution | PASS for Polish, English, German-only fallback and secondary supported preferences |
| Missing Polish key | PASS: English fallback in an intentionally incomplete temporary test bundle |
| Catalog coverage | PASS: 168 matching keys, matching positional format placeholders, no Polish text in English values |
| Unicode/user data | PASS: Polish characters and literal filename/segment/Event values preserved |
| Separate-process launch overrides | PASS: five native AppleLanguages launch cases, no settings persisted |
| Packaged helper/resource lookup | PASS: app-bundle language override and lookup inside Contents/Resources, without using build-path resources; relative test-bundle lookup is also covered |
| Native English UI | Confirmed: four synthetic MP4/MOV movies, six segments, English controls/statuses and Ready selection |
| Native Polish UI | Confirmed on automatic system-language startup, including Polish controls and accented text |
| Public screenshot | Real English window capture saved and embedded in README; decoded pixels unchanged by PNG conversion |
| Native drag / XML regression | Existing payload, promises, ordering, resource references and DTD 1.9/1.14 checks pass |

A new FCP receiving-app import was not performed. The System Settings language picker itself was not changed during testing; its effective per-app language override was exercised through native launch preferences. Real iPhone HDR/VFR acceptance remains outside this localization verification. Unsupported variants remain blocked.

The final binary privacy check found and removed old generated build-path/debug information. Release packaging strips debug symbols before signing, and the final executable contains no detected /Users or /Volumes path strings.

## Reproducibility

Run `swift test --disable-xctest`, `sh Scripts/build-release.sh` and, for release assets, `sh Scripts/package-release.sh`. The image provenance and regeneration procedure is documented in images/README.md. Generated demo media, process-probe binaries and local logs are ignored.

Apple references: [ordered Bundle language negotiation](https://developer.apple.com/documentation/foundation/bundle/1409418-preferredlocalizations), [CFBundleDevelopmentRegion](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundledevelopmentregion). Native selection is used directly; the application does not inspect only the first system language.
