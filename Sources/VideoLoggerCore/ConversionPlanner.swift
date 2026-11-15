import VideoLoggerLocalization
import Foundation

public struct ConversionPlanner: Sendable {
    public init() {}
    public func plan(project: LoggingProject, media: MediaMetadata, options: ExportOptions) throws -> ConversionPlan {
        try validateMediaFileName(project.mediaFileName)
        guard media.url.isFileURL, media.width > 0, media.height > 0, media.frameCount > 0,
              media.sourceStartFrame >= 0, ["DF", "NDF"].contains(media.timecodeFormat) else {
            throw ConversionError(L("Invalid video metadata or nonlocal URL."))
        }
        if let audio = media.audio {
            guard audio.channels > 0, audio.sampleRate > 0 else { throw ConversionError(L("Invalid audio parameters.")) }
        }
        let sourceEnd = media.sourceStartFrame.addingReportingOverflow(media.frameCount)
        guard !sourceEnd.overflow else { throw ConversionError(L("The source timecode range was exceeded.")) }
        _ = try media.clock.time(frames: sourceEnd.partialValue)
        let eventName = options.eventName ?? project.sourceURL.deletingPathExtension().lastPathComponent
        try validateLabel(eventName, field: L("Event name"))
        guard !project.segments.isEmpty else { throw ConversionError(L("The project contains no segments.")) }
        // LosslessCut sidecars can round the final time to six decimal places.
        let endTolerance = media.usesTimingTolerance ? 0.000_000_501 : 1e-9
        let ranges = try project.segments.enumerated().map { index, segment in
            try validateLabel(segment.name, field: LF("Segment %1$@", String(describing: index + 1)))
            guard !segment.name.contains(","), segment.start.isFinite, segment.end.isFinite,
                  segment.start >= 0, segment.end > segment.start,
                  segment.end <= media.durationSeconds + endTolerance else {
                throw ConversionError(LF("Segment %1$@ (%2$@): invalid range/name or end beyond the video (%3$@ s).", String(describing: index + 1), String(describing: segment.name), String(describing: media.durationSeconds)))
            }
            let start = try media.clock.nearestFrame(seconds: segment.start)
            let alignedEnd = try media.clock.nearestFrame(seconds: segment.end)
            let end = media.usesTimingTolerance ? min(alignedEnd, media.frameCount) : alignedEnd
            guard start < end, end <= media.frameCount else {
                throw ConversionError(LF("Segment %1$@: the frame-aligned range is empty or outside the media.", String(describing: index + 1)))
            }
            return FrameRange(start: start, end: end, name: segment.name, selected: segment.selected)
        }
        if options.includeStringout && !ranges.contains(where: \.selected) {
            throw ConversionError(L("Stringout requires at least one segment with selected=true."))
        }
        return ConversionPlan(project: project, media: media, ranges: ranges, eventName: eventName,
                              projectName: project.sourceURL.deletingPathExtension().lastPathComponent + " — Stringout",
                              includeStringout: options.includeStringout)
    }
}
