# Requirements and supported scope

## Platform

- macOS 15+, validated on Sequoia 15.7.9 Intel x86_64.
- Swift 6, AppKit, Foundation, AVFoundation and CoreMedia; no external dependencies.
- Local processing only, no account/server, no copying or transcoding original media.

## Inputs and library

LLC v2 JSON5, MP4/MOV, multiple files and recursive folder import. Pairing uses `mediaFileName`, preserving original names. Missing media retains offline segment previews and supports manual relink. Recordings without LLC are normal entries. Hidden files, packages and nested symbolic links are skipped. Still images are not source inputs.

The two-pane interface supports recording/segment multiselection, deterministic source-time ordering, four filters and filename search. Removing/clearing affects memory only. Refresh respects exclusions; explicitly adding files/folders restores them. Filter changes invalidate all segment selection and prepared drag data. Sessions and relinks do not persist across restarts.

## Media contract

- H.264 or HEVC/H.265 in MP4/MOV, decodable by AVFoundation on the current computer.
- One progressive CFR video track, square pixels, video timeline starting at zero, standard 0/90/180/270° rotation without reflection/scaling.
- Zero or one supported mono/stereo audio track starting at zero, integral sample rate.
- Zero or one continuous supported 32/64-bit timecode track matching video fps; supported DF/NDF source TC.
- Exact duration/PTS validation; reject VFR, gaps, format changes, retiming and unsupported edit lists.
- SDR Rec.709 declared only for complete matching tags. Missing tags remain unspecified. HDR/Dolby Vision, Log and unsupported/incomplete color tags are blocked without color conversion.

No full compatibility claim is made for iPhone HDR/VFR, spatial media, slow motion or untagged/mistagged video. Real-media and FCP verification remains necessary.

## Outputs

Native multi-clip drag to Final Cut Pro Events or existing timelines, with original references and no target aspect ratio/resolution. XML 1.9/1.14 pasteboard representations; no intermediary XML file required. The optional CLI writes FCPXML 1.9 Keyword Ranges or selected stringout, beside LLC by default, without overwriting files.

CFR endpoints are rounded to the nearest source frame. Invalid, empty or out-of-bounds ranges are not silently trimmed. LLC markers without end and comma-containing keyword labels are rejected explicitly. Event naming/UID does not guarantee merge or deduplication in FCP. Repeated drops/imports may create duplicate clips/collections. Use Leave files in place and verify the receiving application's behavior.

## Outside 1.0

SwiftUI, a video player/database, persistent bookmarks, batch XML-file export, Event grouping/profiles, automatic FCP library modification, VFR remapping/HDR conversion, Apple Silicon release validation and notarization.

## Localization and release assets

English base/fallback and Polish localizations, selected through native ordered macOS language preferences and per-app language settings. All owned UI/diagnostic messages are localized; source names and data stay unchanged. Matching catalogs and placeholder tests guard coverage. The Release app contains both languages and the original orange icon.

The Intel release ZIP and SHA-256 are generated under ignored dist/, verified after extraction, and uploaded later as release assets rather than committed. No repository URL is invented before the user creates it. No publication, commit, push, remote setup or Applications installation is automatic.
