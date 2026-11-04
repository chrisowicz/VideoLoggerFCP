import VideoLoggerLocalization
import Foundation

public struct ConversionError: LocalizedError, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct LogSegment: Equatable, Sendable {
    public let start: Double
    public let end: Double
    public let name: String
    public let selected: Bool
    public init(start: Double, end: Double, name: String, selected: Bool = true) {
        self.start = start; self.end = end; self.name = name; self.selected = selected
    }
}

public struct LoggingProject: Sendable {
    public let sourceURL: URL
    public let mediaFileName: String
    public let segments: [LogSegment]
    public init(sourceURL: URL, mediaFileName: String, segments: [LogSegment]) {
        self.sourceURL = sourceURL; self.mediaFileName = mediaFileName; self.segments = segments
    }
}

/// Exact seconds per frame, never an approximation of nominalFrameRate.
public struct FrameClock: Equatable, Sendable {
    public let numerator: Int64
    public let denominator: Int32
    public init(numerator: Int64, denominator: Int32) throws {
        guard numerator > 0, denominator > 0 else {
            throw ConversionError(L("Invalid rational frame duration."))
        }
        var a = numerator, b = Int64(denominator)
        while b != 0 { (a, b) = (b, a % b) }
        self.numerator = numerator / a
        self.denominator = Int32(Int64(denominator) / a)
    }
    public var secondsPerFrame: Double { Double(numerator) / Double(denominator) }
    public var framesPerSecond: Double { 1 / secondsPerFrame }
    public func nearestFrame(seconds: Double) throws -> Int64 {
        let frames = seconds * Double(denominator) / Double(numerator)
        guard seconds.isFinite, seconds >= 0, frames.isFinite, frames.rounded() < Double(Int64.max) else {
            throw ConversionError(L("The time is invalid or too large."))
        }
        return Int64(frames.rounded(.toNearestOrAwayFromZero))
    }
    public func time(frames: Int64) throws -> String {
        let product = frames.multipliedReportingOverflow(by: numerator)
        guard frames >= 0, !product.overflow else {
            throw ConversionError(L("The FCPXML time range was exceeded."))
        }
        return "\(product.partialValue)/\(denominator)s"
    }
}

public struct AudioMetadata: Equatable, Sendable {
    public let channels: Int
    public let sampleRate: Int
    public init(channels: Int, sampleRate: Int) { self.channels = channels; self.sampleRate = sampleRate }
}

public struct MediaMetadata: Sendable {
    public let url: URL
    public let width: Int
    public let height: Int
    public let clock: FrameClock
    public let frameCount: Int64
    public let audio: AudioMetadata?
    public let colorSpace: String?
    public let sourceStartFrame: Int64
    public let timecodeFormat: String
    public let rotationDegrees: Int
    public init(url: URL, width: Int, height: Int, clock: FrameClock, frameCount: Int64,
                audio: AudioMetadata? = nil, colorSpace: String? = nil,
                sourceStartFrame: Int64 = 0, timecodeFormat: String = "NDF", rotationDegrees: Int = 0) {
        self.url = url; self.width = width; self.height = height; self.clock = clock
        self.frameCount = frameCount; self.audio = audio; self.colorSpace = colorSpace
        self.sourceStartFrame = sourceStartFrame; self.timecodeFormat = timecodeFormat
        self.rotationDegrees = rotationDegrees
    }
    public var durationSeconds: Double { Double(frameCount) * clock.secondsPerFrame }
}

public struct ExportOptions: Sendable {
    public var eventName: String?
    public var includeStringout: Bool
    public init(eventName: String? = nil, includeStringout: Bool = false) {
        self.eventName = eventName; self.includeStringout = includeStringout
    }
}

public struct FrameRange: Equatable, Sendable {
    public let start: Int64
    public let end: Int64
    public let name: String
    public let selected: Bool
    public var duration: Int64 { end - start }
}

public struct ConversionPlan: Sendable {
    public let project: LoggingProject
    public let media: MediaMetadata
    public let ranges: [FrameRange]
    public let eventName: String
    public let projectName: String
    public let includeStringout: Bool
    public var selectedRanges: [FrameRange] { ranges.filter(\.selected) }
}

public protocol ProjectImporting: Sendable {
    func parse(_ data: Data, sourceURL: URL) throws -> LoggingProject
}
public protocol MediaProbing: Sendable {
    func inspect(_ url: URL) async throws -> MediaMetadata
}
public protocol ProjectExporting: Sendable {
    func export(_ plan: ConversionPlan) throws -> Data
}

// Reject invalid XML scalars and attribute whitespace that XML parsers normalize.
func validateLabel(_ value: String, field: String) throws {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          value.unicodeScalars.allSatisfy({ scalar in
              let v = scalar.value
              return (0x20...0xD7FF).contains(v) || (0xE000...0xFFFD).contains(v)
                  || (0x10000...0x10FFFF).contains(v)
          }) else {
        throw ConversionError(LF("%1$@: the name is empty or contains characters that cannot be used in an XML attribute.", String(describing: field)))
    }
}

func validateMediaFileName(_ name: String) throws {
    try validateLabel(name, field: "mediaFileName")
    guard name != ".", name != "..", !name.contains("/"), !name.contains("\\") else {
        throw ConversionError(L("mediaFileName must contain only a filename; use --media for another location."))
    }
}
