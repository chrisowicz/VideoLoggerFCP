# English interface screenshot

`videologgerfcp-english.png` is an authentic app-window capture of the running English VideoLoggerFCP Release interface. It shows four synthetic recordings, six named ranges and a prepared selection. No desktop, private media, private filenames or private paths are visible.

The capture API returned JPEG data. The original capture bytes were verified before conversion to PNG with macOS `sips`. The PNG was checked against the original capture in a common sRGB pixel context: all decoded pixels are identical. There was no UI reconstruction, retouching or generated illustration. The saved PNG is 2560×1536 and uses lossless PNG encoding.

## Reproduce the view

```sh
sh Scripts/build-release.sh
swift Scripts/prepare-demo.swift
open -n dist/VideoLoggerFCP.app --args -AppleLanguages '(en)' --open "$PWD/.local/README-demo"
```

The generator creates four tiny black-frame CFR/SDR movies and their LLC ranges in ignored `.local/README-demo`. These filenames are demonstration labels, not real travel footage. The generator refuses to overwrite a previous demo folder. No user media is read or downloaded.

Select **All Segments** and wait for **Ready**. Capture only the actual application window using macOS Screenshot or a native window-capture tool. Save PNG to this directory; keep the title, tables and controls readable and review for privacy before publishing. Do not add the generated movies/LLC to Git.
