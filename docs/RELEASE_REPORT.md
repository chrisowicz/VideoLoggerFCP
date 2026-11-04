> Updated 2026-11-04: build 101 adds native PL/EN localization (168 keys), a real English demonstration screenshot and verified v1.0.0 Intel ZIP/SHA-256 assets. Current regression: 81 PASS, 2 optional real-media SKIP (83 definitions). See LOCALIZATION.md and RELEASING.md. Historical 1.0 preparation results below remain scoped to the initial build.

# VideoLoggerFCP 1.0 release preparation

Date: 2026-11-03. Local preparation only; no commit, remote, push, GitHub Release, visibility change or installation into Applications was performed.

## Current localized release assets — 2026-11-04

- Version 1.0.0 (101), Release x86_64, with the original orange icon and English/Polish resources.
- `dist/VideoLoggerFCP-1.0.0-macOS-Intel.zip`: 1,150,253 bytes.
- SHA-256: `7123eef06a3f1e0f7b89cc34570ca4d816859e77ca6bdc8dd1c880f064c59de1`.
- ZIP CRC, extraction, complete extracted-tree comparison, strict ad-hoc signature, Info.plist and Intel architecture: PASS.
- Five native language-launch cases using resources inside the packaged application: PASS. No private build-path strings detected in the final executable or extracted archive files.
- Final source candidate audit: 73 files, including the genuine English screenshot; local Markdown links valid; no detected private paths/credential patterns or files over 5 MB. dist/, demo media and agent checkpoints remain ignored.
- Git index empty, no commits and no remotes. The owner-supplied download destination is [GitHub Releases](https://github.com/chrisowicz/VideoLoggerFCP/releases); nothing was published.

The checksum applies to this prepared archive. Rebuilding can change archive bytes and generates a new checksum. The matching `.sha256` asset is generated beside the ZIP. Per-app launch overrides were tested; changing the System Settings language picker and a new FCP receiving-app import remain manual checks.

## Delivered

- Standalone `dist/VideoLoggerFCP.app`, Release x86_64, version 1.0.0 (100), macOS 15+.
- Original orange film-frame icon: editable SVG reference, authoritative Swift renderer, ten standard PNG iconset entries, 1024×1024 PNG and ICNS. Icon and license are included in the app bundle.
- Repeatable `Scripts/build-release.sh`; compatibility build entry point retained.
- MIT license with the owner's approved attribution.
- English README, architecture, requirements, building, usage and testing documentation.
- Shared synthetic project resources under Tests/Fixtures. Private development inputs are no longer required by tests.
- Scoped ignore rules and a local empty Git repository prepared for later publication.

No production conversion or native pasteboard behavior was redesigned for finalization. The application retains folder/multi-source import, filters/search, memory-only list removal, MP4/MOV validation and native drag.

## Cleanup

Removed the two root development LLC files, two root experimental FCPXML files, the Event FCPXMLD package, Diagnostics/ and Exports/ with their contents, the retired Event-UID preparation helper, six superseded reports/instructions, old test logs, the private fixture copy and stale build/cache entries. Public documentation replaces historical experiments with current supported behavior and limitations.

The exact local deletion manifest is intentionally excluded from Git because it contains former private filenames. No external directories or original external recordings were removed or modified. Cleanup did not follow symbolic links outside the project.

An ignored legacy prototype app bundle was intentionally left in the build directory because it may still serve the user's open in-memory session. It is not part of the public source candidate or the new standalone Release app. Newly recreated build cache supports current validation; no private diagnostics are needed to build or test.

## Validation performed

| Check | Result |
| --- | --- |
| Full suite after cleanup / fresh build cache | 77 test definitions: 75 PASS, 2 optional real-media tests skipped |
| Synthetic AVFoundation integrations | PASS: generated H.264 MOV, standard rotations, fractional timing, both XML export modes and VFR rejection |
| Existing native drag regression | PASS: payload content/order/resources, pasteboard promises, repeated snapshots, XML version negotiation |
| Folder/multiple LLC, offline/relink, list/filter/file protection | PASS |
| Apple DTD 1.9 and 1.14 on this machine | PASS; DTD files are not redistributed |
| Release x86_64 build, repeated after clearing old cache | PASS |
| Bundle structure / Info.plist / ad-hoc signature | PASS |
| Original icon sizes and copied ICNS/LICENSE | PASS |
| Runtime dependencies | System frameworks/libraries only; no build-directory dependency |
| Standalone Release startup | PASS: real AppKit window with two synthetic recordings and seven offline ranges |
| Candidate files / ignore rules | PASS (62 candidate files): user media, agent files, logs and build artifacts excluded; synthetic fixtures included |
| Pattern/privacy and large-file audit | No private user paths, tested credential patterns or files over 5 MB found in candidate files |
| Git history / remotes | Empty history, no remotes; nothing committed or published |

The pattern audit is a bounded check, not a forensic security guarantee. Approved copyright attribution and project links are intentionally public.

## Manual checks and distribution limits

A new 1.0 import into Final Cut Pro was not performed. Previous native integration was reported successful by the user; automated regression does not replace receiving-app testing. Real iPhone HEVC/HDR/VFR, external-disk performance, image/audio playback, Gatekeeper on another Mac and Apple Silicon distribution remain unverified. HDR/VFR are rejected rather than silently approximated or converted.

The current interface supports English and Polish through macOS preferences. An authentic English screenshot with synthetic examples is now included in docs/images/videologgerfcp-english.png; provenance is documented in docs/images/README.md.

The package is ad-hoc signed, not notarized or Developer ID signed. This does not require a paid Apple Developer Program account, but downloaded copies can encounter Gatekeeper. Installation is a manual Finder copy to Applications; no automatic installation was performed.

## Readiness

The source tree is prepared for a future public repository: source, test resources, build scripts, original artwork, MIT license and current documentation are the publication candidates. Local agent checkpoints, deletion/audit manifests, media, old outputs and app bundles are excluded. Publication itself requires a separate user action/authorization. Real receiving-app acceptance is documented in USAGE.md.
