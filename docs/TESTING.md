# Testing

```sh
swift test --disable-xctest
sh Scripts/build-release.sh
codesign --verify --deep --strict dist/VideoLoggerFCP.app
plutil -lint dist/VideoLoggerFCP.app/Contents/Info.plist
file dist/VideoLoggerFCP.app/Contents/MacOS/VideoLoggerFCP
```

`--disable-xctest` supports Command Line Tools environments without XCTest. Tests use Swift Testing. No private project/media is required.

Synthetic LLC resources live in `Tests/Fixtures/Projects`, shared by the test-only `VideoLoggerTestSupport` target. Test placeholders are tiny temporary files with explicit metadata stubs. AVFoundation integration tests create small H.264 MOV movies from new black frames with AVAssetWriter, exercising real sample inspection, orientation, 30000/1001 timing and VFR rejection. They do not transcode user recordings.

Coverage includes JSON5/validation, exact timing/source TC, Keyword Ranges/stringout, filenames/Unicode, safe output, folder recursion, multiple sources, 17 movies with two sidecars, symlinks, missing media/relink, caching, list removal/clear/refresh/restore, filters/search, unique resource references, native pasteboard promises and version negotiation. HDR/HEVC policy tests use explicit synthetic metadata; they are not proof of real iPhone support.

## Optional checks

`VIDEOLOGGER_TEST_MEDIA` can point to an existing compatible recording for two optional probe/round-trip tests. They generate their own temporary project/XML and never require the old development inputs. Without that variable, those tests are explicitly skipped.

Apple DTD files are not redistributed. Core export tests accept `FCPXML_DTD` for version 1.9; drag tests use local DTD 1.9/1.14 when available under the installed FCP Creator Studio resources path. Missing DTD tests are skipped, while basic XML/behavior checks still run.

```sh
FCPXML_DTD=/path/to/FCPXMLv1_9.dtd swift test --disable-xctest
sh Scripts/validate-fcpxml.sh /path/to/FCPXMLv1_9.dtd /path/to/export.fcpxml
```

## Limits of evidence

Real Final Cut Pro import and iPhone HDR/VFR/HEVC playback are manual checks. Follow [USAGE.md](USAGE.md). Unit, policy, schema, process-start and screenshot checks must not be reported as a successful FCP import. External disks, Gatekeeper on another Mac, Apple Silicon and notarization are not validated by these tests.

See [RELEASE_REPORT.md](RELEASE_REPORT.md) for actual finalization results.

## Localization verification

The current full suite has 83 test definitions: 81 passed and two optional real-media tests were skipped. LocalizationTests checks ordered native PL/EN/fallback selection, all 168 key/placeholder pairs, English per-key fallback, Unicode and preservation of user data. Native launch overrides and app-bundle resource lookup were additionally verified in separate processes, without writing preferences. Real English and Polish windows were observed; the public English screenshot is authentic.

See [LOCALIZATION.md](LOCALIZATION.md) for evidence limits, including the unchanged System Settings picker and unperformed FCP receiving-app test. Packaging verification checks the entire extracted ZIP, signature, architecture, icon, both languages and SHA-256; see [RELEASING.md](RELEASING.md).
