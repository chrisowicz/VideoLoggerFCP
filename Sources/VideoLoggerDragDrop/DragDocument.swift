import VideoLoggerLocalization
import Foundation
import CoreMedia
import VideoLoggerCore

public struct DragSegment: Sendable {
    public let name: String
    public let startFrame: Int64
    public let durationFrames: Int64
    public let initiallySelected: Bool
}

/// Immutable source snapshot. Each drag makes a fresh pasteboard item from this data.
public struct DragDocument: Sendable {
    public let sourceURL: URL
    public let media: MediaMetadata
    public let mediaName: String
    public let segments: [DragSegment]
    public let warnings: [String]
    let sourceXML: Data

    public var initialSelection: IndexSet {
        IndexSet(segments.indices.filter { segments[$0].initiallySelected })
    }

    public func payload(for selection: IndexSet) throws -> FCPXMLDragPayload {
        guard !selection.isEmpty, selection.allSatisfy({ segments.indices.contains($0) }) else {
            throw ConversionError(L("Select at least one available segment."))
        }
        return try FCPXMLDragPayload(document: self, selection: selection)
    }
}

public struct DragSourceLoader: Sendable {
    private let probe: any MediaProbing
    public init(probe: any MediaProbing = AVFoundationMediaProbe()) { self.probe = probe }

    public func load(_ source: URL, mediaOverride: URL? = nil) async throws -> DragDocument {
        try FileAccess.requireReadableFile(source)
        if source.pathExtension.lowercased() == "llc" {
            let result = try await ConversionService(probe: probe).convert(source: source, mediaOverride: mediaOverride)
            return try DragDocumentReader.read(result.document, source: source, media: result.plan.media,
                selected: result.plan.ranges.map(\.selected), warnings: result.warnings)
        }
        guard source.pathExtension.lowercased() == "fcpxml" else {
            throw ConversionError(L("Choose one .llc file or VideoLoggerFCP FCPXML 1.9 export."))
        }
        let data = try Data(contentsOf: source)
        let declaredURL = try DragDocumentReader.mediaURL(in: data)
        let actualURL = (mediaOverride ?? declaredURL).standardizedFileURL
        let media = try await probe.inspect(actualURL)
        let warnings = mediaOverride == nil ? [] : [L("The media location was selected manually. It must be the same recording.")]
        return try DragDocumentReader.read(data, source: source, media: media, warnings: warnings)
    }
}

/// Deliberately supports our simple exported source clips, not arbitrary FCP timelines/effects.
public enum DragDocumentReader {
    public static func mediaURL(in data: Data) throws -> URL {
        let xml = try parse(data)
        let asset = try uniqueElement(xml, "/fcpxml/resources/asset")
        guard let representation = asset.elements(forName: "media-rep").first(where: { $0.attribute(forName: "kind")?.stringValue == "original-media" }),
              let value = representation.attribute(forName: "src")?.stringValue,
              let url = URL(string: value), url.isFileURL, url.path.hasPrefix("/"),
              url.host == nil || url.host == "" || url.host == "localhost" else {
            throw ConversionError(L("FCPXML must reference one local original video through an absolute file: URL."))
        }
        return url
    }

    public static func read(_ data: Data, source: URL, media: MediaMetadata,
                            selected: [Bool]? = nil, warnings: [String] = []) throws -> DragDocument {
        _ = try mediaURL(in: data)
        let xml = try parse(data)
        let asset = try uniqueElement(xml, "/fcpxml/resources/asset")
        let format = try uniqueElement(xml, "/fcpxml/resources/format")
        let clip = try uniqueElement(xml, "/fcpxml/asset-clip | /fcpxml/event/asset-clip | /fcpxml/library/event/asset-clip")
        let assetID = try attribute(asset, "id")
        let formatID = try attribute(format, "id")
        let end = media.sourceStartFrame.addingReportingOverflow(media.frameCount)
        guard !end.overflow else { throw ConversionError(L("The source time range was exceeded.")) }
        _ = try media.clock.time(frames: end.partialValue)
        let frameTime = CMTime(value: media.clock.numerator, timescale: media.clock.denominator)
        let origin = try time(media.clock.time(frames: media.sourceStartFrame))
        let duration = try time(media.clock.time(frames: media.frameCount))
        guard !assetID.isEmpty, !formatID.isEmpty, assetID != formatID,
              clip.attribute(forName: "ref")?.stringValue == assetID,
              clip.attribute(forName: "format")?.stringValue == formatID,
              asset.attribute(forName: "format")?.stringValue == formatID,
              asset.attribute(forName: "hasVideo")?.stringValue == "1",
              CMTimeCompare(try time(attribute(format, "frameDuration")), frameTime) == 0,
              CMTimeCompare(try time(attribute(asset, "start")), origin) == 0,
              CMTimeCompare(try time(attribute(asset, "duration")), duration) == 0,
              CMTimeCompare(try time(attribute(clip, "start")), origin) == 0,
              CMTimeCompare(try time(attribute(clip, "duration")), duration) == 0,
              Int(try attribute(format, "width")) == media.width,
              Int(try attribute(format, "height")) == media.height else {
            throw ConversionError(L("FCPXML parameters or references do not match the original media. Choose the correct file or regenerate the XML."))
        }
        guard (clip.children ?? []).compactMap({ $0 as? XMLElement }).allSatisfy({ ["keyword", "note", "metadata"].contains($0.name ?? "") }),
              clip.attribute(forName: "audioStart") == nil, clip.attribute(forName: "audioDuration") == nil else {
            throw ConversionError(L("Effects, retiming and complex FCPXML clips cannot be imported."))
        }
        if let audio = media.audio {
            guard asset.attribute(forName: "hasAudio")?.stringValue == "1",
                  Int(try attribute(asset, "audioChannels")) == audio.channels,
                  Int(try attribute(asset, "audioRate")) == audio.sampleRate else {
                throw ConversionError(L("FCPXML audio parameters differ from the original media."))
            }
        } else if asset.attribute(forName: "hasAudio")?.stringValue == "1" {
            throw ConversionError(L("FCPXML declares audio that is absent from the original media."))
        }
        let keywords = clip.elements(forName: "keyword")
        guard !keywords.isEmpty, selected == nil || selected?.count == keywords.count else {
            throw ConversionError(L("FCPXML contains no keyword ranges matching VideoLoggerFCP segments."))
        }
        let segments = try keywords.enumerated().map { index, keyword in
            let name = try attribute(keyword, "value")
            let start = try frameIndex(CMTimeSubtract(time(attribute(keyword, "start")), origin), clock: media.clock)
            let length = try frameIndex(time(attribute(keyword, "duration")), clock: media.clock)
            guard !name.isEmpty, length > 0, start >= 0, start <= media.frameCount,
                  length <= media.frameCount - start else { throw ConversionError(L("The keyword range is empty or outside the original video.")) }
            return DragSegment(name: name, startFrame: start, durationFrames: length,
                               initiallySelected: selected?[index] ?? true)
        }
        let representations = asset.elements(forName: "media-rep").filter { $0.attribute(forName: "kind")?.stringValue == "original-media" }
        representations.first?.attribute(forName: "src")?.stringValue = media.url.absoluteString
        xml.isStandalone = false
        return DragDocument(sourceURL: source, media: media, mediaName: try attribute(asset, "name"), segments: segments,
                            warnings: warnings, sourceXML: xml.xmlData())
    }

    static func parse(_ data: Data) throws -> XMLDocument {
        let document = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
        guard document.rootElement()?.name == "fcpxml", document.rootElement()?.attribute(forName: "version")?.stringValue == "1.9" else {
            throw ConversionError(L("Only VideoLoggerFCP FCPXML 1.9 is supported as input. A 1.14 Event export is not a segment list."))
        }
        return document
    }

    static func uniqueElement(_ xml: XMLDocument, _ xpath: String) throws -> XMLElement {
        let nodes = try xml.nodes(forXPath: xpath)
        guard nodes.count == 1, let element = nodes.first as? XMLElement else {
            throw ConversionError(L("One media asset, one format and one full source clip are required."))
        }
        return element
    }

    static func attribute(_ element: XMLElement, _ name: String) throws -> String {
        guard let value = element.attribute(forName: name)?.stringValue else { throw ConversionError(LF("FCPXML: missing %1$@.", String(describing: name))) }
        return value
    }

    static func time(_ value: String) throws -> CMTime {
        guard value.hasSuffix("s") else { throw ConversionError(LF("Invalid FCPXML time: %1$@", String(describing: value))) }
        let parts = value.dropLast().split(separator: "/", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let numerator = Int64(parts[0]),
              let denominator = parts.count == 2 ? Int32(parts[1]) : 1, denominator > 0 else {
            throw ConversionError(LF("Invalid rational FCPXML time: %1$@", String(describing: value)))
        }
        return CMTime(value: numerator, timescale: denominator)
    }

    static func frameIndex(_ time: CMTime, clock: FrameClock) throws -> Int64 {
        let frame = try clock.nearestFrame(seconds: time.seconds)
        let exact = try self.time(clock.time(frames: frame))
        guard time.isNumeric, CMTimeCompare(time, exact) == 0 else {
            throw ConversionError(L("The FCPXML range does not lie exactly on frame boundaries."))
        }
        return frame
    }
}
