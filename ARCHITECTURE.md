# Architecture

VideoLoggerFCP is a Swift Package Manager project with no external packages. The production application uses AppKit; the conversion engine remains independent of UI and command-line adapters.

## Modules

| Module | Responsibility |
| --- | --- |
| VideoLoggerLocalization | Foundation-only native en/pl strings, ordered bundle negotiation and English per-key fallback |
| VideoLoggerCore | JSON5 import, media validation, exact frame planning, FCPXML export and safe file output |
| VideoLoggerCLI | Single-project argument parsing and optional file export |
| VideoLoggerDragDrop | Library scanning/model, selection preparation, native FCPXML payload and pasteboard provider |
| VideoLoggerDragApp | AppKit file/folder input, tables, filters, session controls and native drag gestures |
| VideoLoggerTestSupport | Synthetic project resources under Tests/Fixtures; test-only dependency |

## Conversion and timing

`LosslessCutImporter → LoggingProject → MediaProbing → MediaMetadata → ConversionPlanner → ConversionPlan → FCPXMLExporter`.

Foundation's JSON5 decoder reads LLC version 2. Filenames and labels are validated, with explicit rejection of markers without an end and keyword labels containing commas. The latter cannot be preserved as one FCPXML keyword because commas are separators.

AVFoundation reads actual sample duration/PTS, format descriptions, source timecode and orientation without transcoding. `VideoSampleTiming` checks continuous sample PTS using CMTime and calculates the dominant exact sample duration. A uniform source keeps its native clock. A source with uneven timing is eligible when at least 90% of samples share one duration and all durations are within ±10% of it. The planner aligns elapsed LLC times to that duration, with the asset capped at the last complete grid frame within the source. The app identifies this case in its readiness message. Larger variations and discontinuities fail validation.

Source timecode is added to asset, clip and keyword starts. Stringout offsets remain relative to zero. Standard orientation is read from the original; no image rotation or second transform is inserted. The original media remains authoritative for pixels and audio.

`SourceVideoValidation` checks the codec and recognizes complete Rec.709 and Rec.2020 SDR/HLG/PQ descriptions. Dolby Vision is represented through the compatible base color space and a reference to the untouched original, where dynamic metadata resides. If the tags do not describe a recognized space, the FCPXML format leaves color unspecified. No asset color override is written. AVFoundation decodability checks, detected Log rejection and exact timing validation still apply.

`ConversionService` returns data and a plan; it never writes video or LLC. `SafeOutputWriter` writes only a new export, defaults beside LLC and refuses existing output/source/symlink overwrites.

## Library and session state

`LibraryScanner` performs asynchronous filesystem/JSON work only. It discovers MP4/MOV and LLC recursively, pairs by `mediaFileName`, and keeps media without projects. It skips hidden files/packages and nested symlinks, reporting symlink skips; an explicitly chosen link resolves to its target. No original video bytes are read during scanning. FCPXML is previewed only when explicitly added, avoiding duplicate folder selections.

`RecordingLibrary` holds recordings, project bytes and preview ranges in memory. Identity uses standardized, resolved full paths normalized to NFC. Display names are preserved. Duplicate basenames in different folders remain different recordings. Drag preparation orders segments by recording list, then source time, sidecar path and source index. The Source File and Segment columns can sort the visible rows by localized name in either direction. Rows with the same sort value keep their source order. The controller restores selected row IDs after sorting.

Removing entries stores excluded media/source IDs in memory. Refresh respects exclusions; explicit file/folder additions restore only their own scope. Clear cancels pending work and clears refresh roots. These operations do not mutate files. Relink associations are also session-only.

Filters/search project the library without discarding data. The controller maps table rows through visible recording IDs. Filter changes retain only still-visible selected recording IDs, clear all selected segments and invalidate the prepared payload. No hidden selection can be dragged. The recording table handles Delete/Backspace only while it has focus.

## Drag preparation and transport

`LibraryPreparer` is an actor. It checks the entire selection, invokes the existing source loader/conversion service only for selected sources, and builds one immutable payload. Missing or unsupported media blocks the complete selection; no silent subset is exported.

Probe cache keys include resolved path, file size and modification date. Document cache also includes source contents. Fresh file attributes and source bytes are checked before preparation completes and again when dragging. Size/date cache is not a content fingerprint; choosing the correct relocated original remains the user's responsibility.

`FCPXMLDragPayload` combines resources with unique IDs and remapped references. It preserves source ranges, keyword/note/metadata and explicit selection order. The result contains resources and asset-clips, with no target Event/library/project/sequence. Source format resources do not prescribe the target project format.

The existing `NSPasteboardItemDataProvider` promises XML 1.14 for `com.apple.finalcutpro.xml.v1-14` and the generic type, and XML 1.9 for `com.apple.finalcutpro.xml.v1-9`. A fresh item/session is created for each gesture. Finder file-URL input and native XML output are separate paths. There are no private FCP formats, AppleScript automation or direct library edits.

AppKit stays on MainActor. Scan/preparation jobs support cancellation and revision checks against stale callbacks. UI changes invalidate preparation. Payloads remain in memory; the primary workflow does not call the file writer.

## Packaging

`Resources/Info.plist`, the original icon and LICENSE are copied into standalone arm64 or x86_64 Release apps by `Scripts/build-release.sh`. Runtime code depends only on system frameworks/libraries. Signing is ad-hoc, with no notarization. No App Sandbox/bookmarks, database, player, SwiftUI or persisted session is included.

## Localization

`VideoLoggerLocalization` owns matching en.lproj/pl.lproj Localizable.strings catalogs (168 unique UI/diagnostic keys). UI, Core diagnostics, library statuses and CLI text call `L`/`LF`; resource keys are English and format arguments preserve user strings. Original names, technical XML identifiers and export data are not used as localization keys.

Foundation `Bundle.preferredLocalizations(from:forPreferences:)` negotiates the complete system preference list. No custom language preference is written. Standard per-app AppleLanguages overrides are honored. Missing Polish values use an explicitly loaded English table; unknown keys remain unchanged. Formatting uses positional string arguments and is checked for placeholder parity.

Package.swift declares defaultLocalization=en. The app declares CFBundleDevelopmentRegion=en and CFBundleLocalizations=en/pl. Release packaging includes the SwiftPM resource bundle inside Contents/Resources and copies root en.lproj/pl.lproj resources for native AppKit localization. Runtime lookup checks Contents/Resources and the running executable directory using relative bundle paths; it does not embed a private build-directory fallback. Release debug symbols are stripped before signing.
