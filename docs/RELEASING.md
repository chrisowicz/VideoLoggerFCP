# Preparing GitHub Releases v1.0.0

The target repository is [chrisowicz/VideoLoggerFCP](https://github.com/chrisowicz/VideoLoggerFCP), supplied by the owner. Its [Releases page](https://github.com/chrisowicz/VideoLoggerFCP/releases) is the download destination. Do not create a remote, tag or release automatically.

## Build the assets locally

```sh
sh Scripts/package-release.sh
```

This builds the complete Intel Release app, creates a macOS-compatible ZIP with `ditto`, checks ZIP CRCs, extracts a temporary copy, verifies its ad-hoc signature/Info.plist/architecture, compares the complete extracted app tree, checks both localization tables and writes/verifies SHA-256.

Outputs under ignored `dist/`:

- `VideoLoggerFCP.app`
- `VideoLoggerFCP-1.0.0-macOS-Intel.zip`
- `VideoLoggerFCP-1.0.0-macOS-Intel.zip.sha256`

The ZIP contains the whole application bundle, including its executable, orange icon, license, English/Polish resources and resource bundle. No source project, demo media or agent files belong in the archive. Build artifacts are not committed.

## Later publication — user action

1. Review the source and repository configuration before committing/publishing; the Releases link is already set to the supplied repository.
2. Create tag/release `v1.0.0` using the intended source revision, following your own approval process.
3. Attach the ZIP and its `.sha256` file as Release assets. Do not add them to the Git index.
4. Review the draft notes below and complete real FCP/manual acceptance before making distribution claims.

No tag, commit, remote, GitHub Release or publication is created by the scripts.

## Draft release notes

VideoLoggerFCP 1.0.0 for macOS Intel brings LosslessCut selections to existing Final Cut Pro Events and timelines using native Drag & Drop. It supports multiple recordings/folders, MP4/MOV, original-media references, filters/search and memory-only session cleanup.

The interface now supports English and Polish through macOS language preferences, including per-app language selection. English is the base/fallback. Filenames and LLC segment labels are preserved.

Download `VideoLoggerFCP-1.0.0-macOS-Intel.zip` and its SHA-256 file. Extract the app and copy it to Applications using Finder. The app is ad-hoc signed and not notarized, so Gatekeeper may warn on downloaded copies; use Apple's supported per-app opening procedure only after verifying the source. Do not disable Gatekeeper globally.

Requirements: macOS 15+, Intel x86_64; validated development environment macOS 15.7.9. Final Cut Pro is needed to receive clips. CFR/SDR H.264/HEVC validation applies; VFR, HDR/Dolby Vision and unsupported color metadata are blocked without approximation/transcoding. There is no full iPhone compatibility claim and no new claim of a completed FCP receiving-app test.

## Verifying a download

With both assets in the same directory:

```sh
shasum -a 256 -c VideoLoggerFCP-1.0.0-macOS-Intel.zip.sha256
```

Expected: `VideoLoggerFCP-1.0.0-macOS-Intel.zip: OK`. The checksum checks file integrity; verify that the assets came from the correct repository as well.
