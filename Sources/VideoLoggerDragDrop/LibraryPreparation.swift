import VideoLoggerLocalization
import Foundation
import VideoLoggerCore

struct MediaFileStamp: Hashable, Sendable {
    let size: Int
    let modified: Date
    static func read(_ url: URL) throws -> Self {
        guard url.isFileURL else { throw ConversionError(L("Only local files are supported.")) }
        // URL resource values may be cached on the same NSURL instance after a file changes.
        let values = try FileManager.default.attributesOfItem(atPath: url.path)
        guard values[.type] as? FileAttributeType == .typeRegular,
              FileManager.default.isReadableFile(atPath: url.path),
              let size = values[.size] as? Int, let modified = values[.modificationDate] as? Date else {
            throw ConversionError(LF("Cannot check whether the media is current: %1$@", String(describing: url.lastPathComponent)))
        }
        return Self(size: size, modified: modified)
    }
}

private actor CachedMediaProbe: MediaProbing {
    let base: any MediaProbing
    var cache: [String: (MediaFileStamp, MediaMetadata)] = [:]
    init(base: any MediaProbing) { self.base = base }
    func inspect(_ url: URL) async throws -> MediaMetadata {
        let stamp = try MediaFileStamp.read(url)
        let id = libraryFileID(url)
        if let cached = cache[id], cached.0 == stamp { return cached.1 }
        let metadata = try await base.inspect(url)
        try Task.checkCancellation()
        guard try MediaFileStamp.read(url) == stamp else { throw ConversionError(L("The media changed while reading. Prepare the selection again.")) }
        cache[id] = (stamp, metadata)
        return metadata
    }
}

public struct PreparationProgress: Sendable {
    public let completed: Int
    public let total: Int
    public let name: String
}

public struct PreparedLibraryDrag: Sendable {
    public let payload: FCPXMLDragPayload
    let media: [URL: MediaFileStamp]
    let sources: [URL: Data]
    /// Called again at mouse-down/drag: never offer a stale selection after unmount or edits.
    public func validateInputs() throws {
        for (url, stamp) in media {
            guard try MediaFileStamp.read(url) == stamp else { throw ConversionError(LF("The media changed. Select the segments again: %1$@", String(describing: url.lastPathComponent))) }
        }
        for (url, contents) in sources {
            guard try Data(contentsOf: url) == contents else { throw ConversionError(LF("The selection file changed. Refresh the list: %1$@", String(describing: url.lastPathComponent))) }
        }
    }
}

public actor LibraryPreparer {
    private let probe: CachedMediaProbe
    private struct CachedDocument {
        let contents: Data
        let mediaID: String
        let stamp: MediaFileStamp
        let document: DragDocument
    }
    private var documents: [String: CachedDocument] = [:]
    public init(probe: any MediaProbing = AVFoundationMediaProbe()) { self.probe = CachedMediaProbe(base: probe) }

    public func prepare(_ rows: [LibrarySegmentRow], progress: (@Sendable (PreparationProgress) -> Void)? = nil) async throws -> PreparedLibraryDrag {
        guard !rows.isEmpty else { throw ConversionError(L("Select segments.")) }
        let unavailable = Set(rows.filter { $0.recording.mediaURL == nil || !LibraryScanner.isReadableMedia($0.recording.mediaURL!) }.map { $0.recording.name })
        guard unavailable.isEmpty else { throw ConversionError(L("Missing MP4/MOV media: ") + unavailable.sorted().joined(separator: ", ") + L(". Locate the original or deselect these segments.")) }
        var loaded: [String: DragDocument] = [:], mediaStamps: [URL: MediaFileStamp] = [:], sourceContents: [URL: Data] = [:]
        let total = Set(rows.map { $0.source.id }).count
        for row in rows where loaded[row.source.id] == nil {
            try Task.checkCancellation()
            guard let mediaURL = row.recording.mediaURL else { throw ConversionError(L("Missing media.")) }
            guard try Data(contentsOf: row.source.url) == row.source.contents else {
                throw ConversionError(LF("The selection changed since scanning. Refresh: %1$@", String(describing: row.source.url.lastPathComponent)))
            }
            progress?(PreparationProgress(completed: loaded.count, total: total, name: row.recording.name))
            let stamp = try MediaFileStamp.read(mediaURL)
            let mediaID = libraryFileID(mediaURL)
            let document: DragDocument
            if let cached = documents[row.source.id], cached.contents == row.source.contents, cached.mediaID == mediaID, cached.stamp == stamp {
                document = cached.document
            } else {
                document = try await DragSourceLoader(probe: probe).load(row.source.url, mediaOverride: mediaURL)
                try Task.checkCancellation()
                documents[row.source.id] = CachedDocument(contents: row.source.contents, mediaID: mediaID, stamp: stamp, document: document)
            }
            loaded[row.source.id] = document
            mediaStamps[mediaURL] = stamp; sourceContents[row.source.url] = row.source.contents
        }
        try Task.checkCancellation()
        // Group adjacent rows without reordering them; interleaved sidecars remain separate groups.
        var grouped: [(String, DragDocument, [Int])] = []
        for row in rows {
            guard let document = loaded[row.source.id], document.segments.indices.contains(row.segment.sourceIndex) else {
                throw ConversionError(L("Inconsistent segment list. Refresh the sources."))
            }
            if let last = grouped.indices.last, grouped[last].0 == row.source.id {
                grouped[last].2.append(row.segment.sourceIndex)
            } else { grouped.append((row.source.id, document, [row.segment.sourceIndex])) }
        }
        let groups = grouped.map { DragClipSelection(document: $0.1, indices: $0.2) }
        let prepared = PreparedLibraryDrag(payload: try FCPXMLDragPayload(selections: groups), media: mediaStamps, sources: sourceContents)
        try prepared.validateInputs()
        progress?(PreparationProgress(completed: total, total: total, name: ""))
        return prepared
    }
}
