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

Coverage includes JSON5/validation, exact timing/source TC, Keyword Ranges/stringout, filenames/Unicode, safe output, folder recursion, multiple sources, 17 movies with two sidecars, symlinks, missing media/relink, caching, list removal/clear/refresh/restore, filters/search, unique resource references, native pasteboard promises and version negotiation. Color-policy tests cover synthetic Rec.2020 HLG/PQ and incomplete metadata. Export/pasteboard tests verify the original media URL and absence of an asset color override in both XML versions.

## Optional checks

`VIDEOLOGGER_TEST_MEDIA` can point to an existing compatible recording for two optional probe/round-trip tests. They generate their own temporary project/XML and never require the old development inputs. Without that variable, those tests are explicitly skipped.

Apple DTD files are not redistributed. Core export tests accept `FCPXML_DTD` for version 1.9; drag tests use local DTD 1.9/1.14 when available under the installed FCP Creator Studio resources path. Missing DTD tests are skipped, while basic XML/behavior checks still run.

```sh
FCPXML_DTD=/path/to/FCPXMLv1_9.dtd swift test --disable-xctest
sh Scripts/validate-fcpxml.sh /path/to/FCPXMLv1_9.dtd /path/to/export.fcpxml
```

## Limits of evidence

Real Final Cut Pro import and iPhone HDR/VFR/HEVC playback are manual checks. Follow [USAGE.md](USAGE.md). Unit, policy, schema, process-start and screenshot checks must not be reported as a successful FCP import. External disks, Gatekeeper on another Mac and notarization are outside these tests.

See [RELEASE_REPORT.md](RELEASE_REPORT.md) for actual finalization results.

## Localization verification

LocalizationTests checks ordered native PL/EN/fallback selection, 168 key/placeholder pairs, English per-key fallback, Unicode and preservation of user data. Native launch overrides and app-bundle resource lookup were additionally verified in separate processes, without writing preferences. Real English and Polish windows were observed; the public English screenshot is authentic.

See [LOCALIZATION.md](LOCALIZATION.md) for evidence limits, including the unchanged System Settings picker and unperformed FCP receiving-app test. Packaging verification checks the entire extracted ZIP, signature, architecture, icon, both languages and SHA-256; see [RELEASING.md](RELEASING.md).

## Segment sorting and HDR reference checks

Build 102 was tested on Apple Silicon with macOS 26.7.3. The full suite passed all 86 tests, including both optional integration cases with a locally generated 10-bit HEVC MOV carrying HLG and a Dolby Vision configuration atom. Tests validated the XML against Final Cut Pro 12.4's DTDs for versions 1.9 and 1.14. Both CLI export modes referenced the synthetic original and declared the HLG source color space. The source MOV and LLC hashes matched after both exports.

A local AppKit smoke test changed the Segment table's sort descriptor in both directions while holding a two-segment selection from the synthetic Dolby Vision MOV. It verified the displayed order, both selected segments and the prepared drag state.

The arm64 app launched. Both Release bundles passed architecture, macOS 15.0 deployment target, signature, icon and PL/EN resource checks. The Intel executable could not run on this Apple Silicon host without Rosetta. It still needs a startup test on an Intel Mac.

For Final Cut Pro acceptance, open a test project and use **Leave files in place**. Add one original from each phone and its LLC to VideoLoggerFCP. Check the sort in both directions, wait for the selected segments to become ready, then drag them into Final Cut Pro. Verify the source paths, frame ranges, orientation, audio and image. Compare the imported color interpretation with an ordinary import of the same original in the same project. Final Cut Pro may apply its own [Color Conform](https://support.apple.com/guide/final-cut-pro/ver808063493/mac). The two reported iPhone originals and their receiving-app behavior have not been tested.

## Bounded frame-duration variations

Build 103 accepts small sample-duration differences on a continuous presentation timeline. Automated tests cover exact CFR, tolerated variations (including an uneven first frame), gaps, larger VFR variations and end-of-file rounding. All 89 tests passed with the optional real-media cases enabled. The real SSD folder produced one drag payload with 30 ranges from 19 LLC projects. Both FCPXML 1.9 and 1.14 payloads passed Apple's DTD validation. Native placement in Final Cut Pro still needs user acceptance, including checking start/end frames.
