# Usage and Final Cut Pro verification

The native interface follows macOS language preferences (English/Polish). These instructions use English control names. Import files/folders from Finder or **Add Files or Folders…** (Command-O). Folders recurse without probing all movie samples. MP4/MOV filenames come from the originals; sidecars are matched through LLC `mediaFileName`.

Select recordings on the left, then ranges on the right (Command/Shift-click). **All Recordings / All Segments** selects all visible recordings/segments. Wait for **Ready**, then drag the drag panel to an existing FCP Event or open project timeline. Select sources remain at their original paths. The payload does not prescribe project dimensions; repeat the gesture in 16:9 and 9:16 projects.

Table times are raw LLC seconds. Preparation validates the media and snaps CFR endpoints to actual frames, including source timecode. A missing or unsupported selected source blocks the whole gesture. Locate a moved original with **Locate Missing Media…**, or deselect its ranges. Relink does not save into LLC.

## List management

**Remove from List** and Delete/Backspace with focus in the left table remove selected session entries. **Clear List** clears all entries, including hidden ones, and refresh roots. No source is deleted/moved/overwritten. Refresh does not restore removed entries; explicitly adding their file, sidecar or containing folder does.

Filters cover all, with LLC, without LLC and missing media. Offline recordings with LLC match both relevant filters. Search matches filenames. On a filter/search change, only still-visible selected recording IDs remain selected and every selected segment/prepared payload is cleared. Choose segments again. Clearing filters does not resurrect hidden selections. Session state is discarded on quit.

## Optional file export

```sh
swift run videologger /path/to/selection.llc --event-name "Interview"
swift run videologger /path/to/selection.llc --event-name "Interview" --stringout
swift run videologger /path/to/selection.llc --media /path/to/original.MOV \
  --output /path/to/export.fcpxml
```

Defaults are beside LLC, named after its basename; stringout adds `-stringout`. `--event` remains an alias for `--event-name`. Existing output is never overwritten. All named ranges become keywords; stringout uses selected segments in LLC order. GUI drag uses explicit GUI selection in recording/source-time order.

Same-name Events and a real Event UID did not merge as expected in prior user-reported file import experiments. Import + manual Merge Events worked. Do not assume deduplication of clips or keyword collections after repeated XML imports or native drops.

## Manual receiving-app checks

1. Choose **Leave files in place** in FCP. Open the intended library and an existing Event/project.
2. Drop one range, then multiple ranges from two originals onto an Event and timeline separately.
3. Verify names, order, source references/timecode, first/last frames, duration, image orientation and audio.
4. Repeat in landscape (e.g. 3840×2160) and portrait (1080×1920) projects. Confirm their formats stay unchanged; choose framing in FCP.
5. Verify originals remain at their existing locations and no unwanted Original Media copies appear. Render/proxy/optimized media are separate FCP settings.
6. Repeat a drop and record duplicate clips/collections rather than assuming deduplication.
7. Test removal/filter changes, offline media, relink and disconnecting media after preparation. Stale selections must not be delivered.
8. Test real iPhone SDR H.264/HEVC, rotation, fractional fps, VFR and HDR/Dolby Vision. Unsupported variants must show an error and leave drag disabled.

Record FCP/macOS versions and results. Automated DTD validation does not prove image/audio playback or receiving-app behavior. Native drag was previously confirmed by the user; a new 1.0 FCP import has not been claimed.

Apple documents [native XML drag and drop](https://developer.apple.com/documentation/professional-video-applications/supporting-drag-and-drop-for-data-sent-to-final-cut-pro), including one/multiple clips on an existing timeline. This application uses that public transport, without automating the library.

## Language preferences

English is the base language. The first supported language in the complete ordered macOS preference list is used; unsupported-only preferences fall back to English. Per-app choices in System Settings → General → Language & Region → Applications override the app language after relaunch. Names and paths from your projects remain unchanged. A missing Polish key falls back to its English value.
