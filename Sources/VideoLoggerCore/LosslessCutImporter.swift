import VideoLoggerLocalization
import Foundation

public struct LosslessCutImporter: ProjectImporting {
    public init() {}
    public func parse(_ data: Data, sourceURL: URL) throws -> LoggingProject {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        let raw: RawProject
        do { raw = try decoder.decode(RawProject.self, from: data) }
        catch let error as DecodingError {
            let context: DecodingError.Context?
            switch error {
            case .dataCorrupted(let c), .keyNotFound(_, let c), .typeMismatch(_, let c), .valueNotFound(_, let c):
                context = c
            @unknown default: context = nil
            }
            let path = context?.codingPath.map(\.stringValue).joined(separator: ".") ?? ""
            throw ConversionError(LF("Invalid JSON5 project %1$@ [%2$@]: %3$@", String(describing: sourceURL.lastPathComponent), String(describing: path), String(describing: error.localizedDescription)))
        }
        guard raw.version == 2 else {
            throw ConversionError(LF("Unsupported .llc version: %1$@. Version 2 is supported.", String(describing: raw.version)))
        }
        try validateMediaFileName(raw.mediaFileName)
        guard !raw.cutSegments.isEmpty else { throw ConversionError(L("The project contains no segments.")) }
        let segments = try raw.cutSegments.enumerated().map { index, item in
            guard let end = item.end else {
                throw ConversionError(LF("Segment %1$@: missing end denotes an LLC v2 marker; only ranges can be exported.", String(describing: index + 1)))
            }
            guard item.start.isFinite, end.isFinite, item.start >= 0, end > item.start else {
                throw ConversionError(LF("Segment %1$@: finite times 0 ≤ start < end are required.", String(describing: index + 1)))
            }
            let name = item.name ?? LF("Segment %1$@", String(describing: index + 1))
            try validateLabel(name, field: LF("Segment %1$@", String(describing: index + 1)))
            guard !name.contains(",") else {
                throw ConversionError(LF("Segment %1$@: commas separate FCPXML keywords. This label cannot be preserved as a single keyword.", String(describing: index + 1)))
            }
            return LogSegment(start: item.start, end: end, name: name, selected: item.selected ?? true)
        }
        return LoggingProject(sourceURL: sourceURL, mediaFileName: raw.mediaFileName, segments: segments)
    }
}

private struct RawProject: Decodable {
    let version: Int
    let mediaFileName: String
    let cutSegments: [RawSegment]
}
private struct RawSegment: Decodable {
    let start: Double
    let end: Double?
    let name: String?
    let selected: Bool?
}
