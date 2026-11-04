import VideoLoggerLocalization
import Foundation
import CoreMedia
import VideoLoggerCore

public func libraryFileID(_ url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping
}

public struct PreviewSegment: Sendable {
    public let name: String
    public let start: Double
    public let end: Double
    public let sourceIndex: Int
}

public struct LibrarySource: Sendable {
    public let url: URL
    public let contents: Data
    public let segments: [PreviewSegment]
    public var id: String { libraryFileID(url) }
}

public struct Recording: Sendable {
    public let id: String
    public let expectedMediaURL: URL
    public var mediaURL: URL?
    public var sources: [LibrarySource]
    public var manuallyLocated = false
    public var name: String { expectedMediaURL.lastPathComponent }
    public var segmentCount: Int { sources.reduce(0) { $0 + $1.segments.count } }
    public var mediaAvailable: Bool { mediaURL.map(LibraryScanner.isReadableMedia) ?? false }
    public var hasLLC: Bool { sources.contains { $0.url.pathExtension.lowercased() == "llc" } }
    public var status: String { !mediaAvailable ? L("Missing Media") : hasLLC ? L("Analyzed") : L("No LLC") }
}

public struct LibrarySegmentRow: Sendable, Identifiable {
    public let recording: Recording
    public let source: LibrarySource
    public let segment: PreviewSegment
    public var id: String { recording.id + "|" + source.id + "|\(segment.sourceIndex)" }
}

public struct ScanIssue: Sendable {
    public let url: URL
    public let message: String
}
public struct ScanProgress: Sendable {
    public let visited: Int
    public let projects: Int
    public let media: Int
}
public struct LibraryScanResult: Sendable {
    public let recordings: [Recording]
    public let issues: [ScanIssue]
    public let checkedSources: Set<String>
}

public struct RecordingLibrary: Sendable {
    public private(set) var recordings: [Recording] = []
    public private(set) var issues: [ScanIssue] = []
    private var excludedMedia = Set<String>()
    private var excludedSources = Set<String>()
    public init() {}

    /// Removes session data only. No filesystem mutation is performed here.
    public mutating func remove(ids: Set<String>) {
        for record in recordings where ids.contains(record.id) {
            excludedMedia.formUnion(Self.mediaIDs(record))
            excludedSources.formUnion(record.sources.map(\.id))
        }
        recordings.removeAll { ids.contains($0.id) }
    }

    public mutating func clear() {
        remove(ids: Set(recordings.map(\.id)))
        issues = []
    }

    public func visibleRecordings(filter: RecordingFilter = .all, search: String = "") -> [Recording] {
        recordings.filter { filter.matches($0) && (search.isEmpty || $0.name.precomposedStringWithCanonicalMapping
            .localizedStandardContains(search.precomposedStringWithCanonicalMapping)) }
    }

    private static func mediaIDs(_ record: Recording) -> Set<String> {
        Set([record.id, libraryFileID(record.expectedMediaURL)] + (record.mediaURL.map { [libraryFileID($0)] } ?? []))
    }

    private static func explicitlyIncludes(_ record: Recording, inputs: [URL]) -> Bool {
        let ids = mediaIDs(record).union(record.sources.map(\.id))
        return inputs.contains { input in
            let key = libraryFileID(input)
            if ids.contains(key) { return true }
            guard (try? input.standardizedFileURL.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return false }
            let prefix = key.hasSuffix("/") ? key : key + "/"
            return ids.contains { $0.hasPrefix(prefix) }
        }
    }

    /// Explicit additions restore only their own scope, never every previously scanned root.
    public mutating func merge(_ result: LibraryScanResult, restoringFrom inputs: [URL] = []) {
        for index in recordings.indices { recordings[index].sources.removeAll { result.checkedSources.contains($0.id) } }
        for incoming in result.recordings {
            let ids = Self.mediaIDs(incoming), sources = Set(incoming.sources.map(\.id))
            if Self.explicitlyIncludes(incoming, inputs: inputs) {
                excludedMedia.subtract(ids); excludedSources.subtract(sources)
            }
            guard excludedMedia.isDisjoint(with: ids), excludedSources.isDisjoint(with: sources) else { continue }
            if let index = recordings.firstIndex(where: {
                $0.id == incoming.id || ($0.manuallyLocated && $0.mediaURL.map(libraryFileID) == incoming.mediaURL.map(libraryFileID) && incoming.mediaURL != nil)
            }) {
                var current = recordings[index]
                if !current.manuallyLocated { current.mediaURL = incoming.mediaURL }
                for source in incoming.sources {
                    current.sources.removeAll { $0.id == source.id }; current.sources.append(source)
                }
                recordings[index] = current
            } else { recordings.append(incoming) }
        }
        for index in recordings.indices {
            if !recordings[index].manuallyLocated, let media = recordings[index].mediaURL, !LibraryScanner.isReadableMedia(media) { recordings[index].mediaURL = nil }
        }
        issues = []
        for issue in result.issues where !issues.contains(where: { $0.url == issue.url && $0.message == issue.message }) { issues.append(issue) }
        sort()
    }

    public mutating func locateMedia(for id: String, at url: URL) throws {
        try FileAccess.requireReadableFile(url)
        guard ["mp4", "mov"].contains(url.pathExtension.lowercased()), let index = recordings.firstIndex(where: { $0.id == id }) else {
            throw ConversionError(L("Locate the original MP4 or MOV for one recording."))
        }
        var recording = recordings[index]
        let duplicates = recordings.filter { $0.id != id && $0.mediaURL.map(libraryFileID) == libraryFileID(url) }
        for duplicate in duplicates {
            for source in duplicate.sources where !recording.sources.contains(where: { $0.id == source.id }) { recording.sources.append(source) }
        }
        recording.mediaURL = url.standardizedFileURL.resolvingSymlinksInPath()
        recording.manuallyLocated = true
        recordings.removeAll { $0.id == id || duplicates.map(\.id).contains($0.id) }
        recordings.append(recording); sort()
    }

    public func segmentRows(for ids: Set<String>) -> [LibrarySegmentRow] {
        recordings.filter { ids.contains($0.id) }.flatMap { recording in
            recording.sources.flatMap { source in source.segments.map { LibrarySegmentRow(recording: recording, source: source, segment: $0) } }
                .sorted {
                    if $0.segment.start != $1.segment.start { return $0.segment.start < $1.segment.start }
                    if $0.source.id != $1.source.id { return $0.source.id < $1.source.id }
                    return $0.segment.sourceIndex < $1.segment.sourceIndex
                }
        }
    }

    private mutating func sort() {
        recordings.sort {
            let order = $0.name.precomposedStringWithCanonicalMapping.localizedStandardCompare($1.name.precomposedStringWithCanonicalMapping)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}

/// Filesystem/JSON scan only. No AVFoundation and no video byte reads.
public struct LibraryScanner: Sendable {
    public init() {}
    public static func isReadableMedia(_ url: URL) -> Bool {
        guard url.isFileURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular else { return false }
        return FileManager.default.isReadableFile(atPath: url.path)
    }

    public func scan(_ inputs: [URL], progress: (@Sendable (ScanProgress) -> Void)? = nil) async throws -> LibraryScanResult {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey]
        var media: [String: URL] = [:], projects: [String: URL] = [:], xmlInputs: [String: URL] = [:]
        var explicitMedia: [URL] = [], issues: [ScanIssue] = []
        var visitedDirectories = Set<String>(), count = 0
        for input in inputs {
            guard input.isFileURL else { issues.append(ScanIssue(url: input, message: L("Only local files are supported."))); continue }
            var stack: [(URL, Bool)] = [(input.standardizedFileURL.resolvingSymlinksInPath(), true)]
            while let (url, explicit) = stack.popLast() {
                try Task.checkCancellation(); count += 1
                do {
                    let values = try url.resourceValues(forKeys: keys)
                    if values.isSymbolicLink == true {
                        issues.append(ScanIssue(url: url, message: L("Skipped a symbolic link; explicitly add its target if needed."))); continue
                    }
                    if values.isDirectory == true {
                        if values.isPackage == true { continue }
                        if visitedDirectories.insert(libraryFileID(url)).inserted {
                            let children = try manager.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
                            stack.append(contentsOf: children.map { ($0, false) })
                        }
                    } else if values.isRegularFile == true {
                        switch url.pathExtension.lowercased() {
                        case "mp4", "mov": media[libraryFileID(url)] = url; if explicit { explicitMedia.append(url) }
                        case "llc": projects[libraryFileID(url)] = url
                        case "fcpxml": if explicit { xmlInputs[libraryFileID(url)] = url }
                        default: if explicit { issues.append(ScanIssue(url: url, message: L("Choose LLC, MP4, MOV, FCPXML files or a folder."))) }
                        }
                    }
                } catch { issues.append(ScanIssue(url: url, message: error.localizedDescription)) }
                if count % 64 == 0 { progress?(ScanProgress(visited: count, projects: projects.count, media: media.count)) }
            }
        }
        // A loose MP4/MOV searches only the LLC files next to it, without importing unrelated recordings.
        var siblings: [String: URL] = [:]
        for movie in explicitMedia {
            do {
                for url in try manager.contentsOfDirectory(at: movie.deletingLastPathComponent(), includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) where url.pathExtension.lowercased() == "llc" {
                    if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true { siblings[libraryFileID(url)] = url }
                }
            } catch { issues.append(ScanIssue(url: movie.deletingLastPathComponent(), message: error.localizedDescription)) }
        }
        var records = media.mapValues { Recording(id: libraryFileID($0), expectedMediaURL: $0, mediaURL: $0, sources: []) }
        var checked = Set<String>()
        let allProjects = projects.merging(siblings) { first, _ in first }
        for (id, url) in allProjects.sorted(by: { $0.key < $1.key }) {
            try Task.checkCancellation()
            count += 1
            if count % 16 == 0 { progress?(ScanProgress(visited: count, projects: projects.count, media: media.count)) }
            do {
                let data = try Data(contentsOf: url)
                let project = try LosslessCutImporter().parse(data, sourceURL: url)
                let expected = url.deletingLastPathComponent().appendingPathComponent(project.mediaFileName)
                guard ["mp4", "mov"].contains(expected.pathExtension.lowercased()) else {
                    throw ConversionError(L("LLC references an unsupported media type. MP4 or MOV is required."))
                }
                let key = libraryFileID(expected)
                guard projects[id] != nil || media[key] != nil else { continue }
                checked.insert(id)
                let source = LibrarySource(url: url, contents: data, segments: project.segments.enumerated().map {
                    PreviewSegment(name: $0.element.name, start: $0.element.start, end: $0.element.end, sourceIndex: $0.offset)
                })
                var recording = records[key] ?? Recording(id: key, expectedMediaURL: expected,
                    mediaURL: Self.isReadableMedia(expected) ? expected : nil, sources: [])
                recording.sources.append(source); records[key] = recording
            } catch {
                checked.insert(id); issues.append(ScanIssue(url: url, message: error.localizedDescription))
            }
        }
        for (id, url) in xmlInputs {
            try Task.checkCancellation(); checked.insert(id)
            do {
                let data = try Data(contentsOf: url)
                let mediaURL = try DragDocumentReader.mediaURL(in: data)
                let xml = try DragDocumentReader.parse(data)
                let asset = try DragDocumentReader.uniqueElement(xml, "/fcpxml/resources/asset")
                let clip = try DragDocumentReader.uniqueElement(xml, "/fcpxml/asset-clip | /fcpxml/event/asset-clip | /fcpxml/library/event/asset-clip")
                let origin = try DragDocumentReader.time(DragDocumentReader.attribute(asset, "start"))
                let segments = try clip.elements(forName: "keyword").enumerated().map { index, keyword in
                    let start = try CMTimeSubtract(DragDocumentReader.time(DragDocumentReader.attribute(keyword, "start")), origin).seconds
                    let duration = try DragDocumentReader.time(DragDocumentReader.attribute(keyword, "duration")).seconds
                    guard start.isFinite, duration.isFinite, start >= 0, duration > 0 else { throw ConversionError(L("Invalid FCPXML range.")) }
                    return PreviewSegment(name: try DragDocumentReader.attribute(keyword, "value"), start: start, end: start + duration, sourceIndex: index)
                }
                guard !segments.isEmpty else { throw ConversionError(L("No segments in FCPXML.")) }
                let key = libraryFileID(mediaURL)
                var recording = records[key] ?? Recording(id: key, expectedMediaURL: mediaURL,
                    mediaURL: Self.isReadableMedia(mediaURL) ? mediaURL : nil, sources: [])
                recording.sources.append(LibrarySource(url: url, contents: data, segments: segments)); records[key] = recording
            } catch { issues.append(ScanIssue(url: url, message: error.localizedDescription)) }
        }
        try Task.checkCancellation()
        progress?(ScanProgress(visited: count, projects: projects.count, media: media.count))
        return LibraryScanResult(recordings: Array(records.values), issues: issues, checkedSources: checked)
    }
}

public enum RecordingFilter: Int, CaseIterable, Sendable {
    case all, analyzed, withoutLLC, missingMedia
    public var title: String {
        switch self {
        case .all: L("All Recordings")
        case .analyzed: L("Analyzed (with LLC)")
        case .withoutLLC: L("No LLC")
        case .missingMedia: L("Missing Media")
        }
    }
    func matches(_ recording: Recording) -> Bool {
        switch self {
        case .all: true
        case .analyzed: recording.hasLLC
        case .withoutLLC: !recording.hasLLC
        case .missingMedia: !recording.mediaAvailable
        }
    }
}
