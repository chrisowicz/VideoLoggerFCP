import VideoLoggerLocalization
import Foundation
import AVFoundation
import CoreMedia

public struct AVFoundationMediaProbe: MediaProbing {
    public init() {}
    public func inspect(_ url: URL) async throws -> MediaMetadata {
        try FileAccess.requireReadableFile(url)
        guard ["mp4", "mov"].contains(url.pathExtension.lowercased()) else {
            throw ConversionError(L("Choose original MP4 or MOV media; other file types are not supported."))
        }
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard try await asset.load(.isReadable), !(try await asset.load(.hasProtectedContent)) else {
            throw ConversionError(L("The media cannot be read or is protected by DRM."))
        }
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard videoTracks.count == 1, let video = videoTracks.first else {
            throw ConversionError(L("Exactly one video track is required."))
        }
        let formats = try await video.load(.formatDescriptions)
        guard formats.count == 1, let format = formats.first else {
            throw ConversionError(L("No unambiguous video format."))
        }
        let extensions = (CMFormatDescriptionGetExtensions(format) as NSDictionary?) ?? NSDictionary()
        let characteristics = try await video.load(.mediaCharacteristics)
        let colorSpace = try SourceVideoValidation.colorSpace(codec: CMFormatDescriptionGetMediaSubType(format),
            extensions: extensions, containsHDR: characteristics.contains(.containsHDRVideo))
        guard try await video.load(.isDecodable) else {
            throw ConversionError(L("The media codec cannot be decoded by AVFoundation on this computer."))
        }
        if let fieldCount = extensions[kCMFormatDescriptionExtension_FieldCount] as? NSNumber,
           fieldCount.intValue != 1 { throw ConversionError(L("Interlaced video is not supported.")) }
        if let aspect = extensions[kCMFormatDescriptionExtension_PixelAspectRatio] as? NSDictionary {
            let h = aspect[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing] as? NSNumber
            let v = aspect[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing] as? NSNumber
            guard let h, let v, h.doubleValue == v.doubleValue, h.doubleValue > 0 else {
                throw ConversionError(L("Square pixels are required."))
            }
        }
        let transform = try await video.load(.preferredTransform)
        let rotation = try Self.rotationDegrees(transform)
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        let swapsAxes = rotation == 90 || rotation == 270
        let width = Int(swapsAxes ? dimensions.height : dimensions.width)
        let height = Int(swapsAxes ? dimensions.width : dimensions.height)
        let timeRange = try await video.load(.timeRange)
        guard CMTimeCompare(timeRange.start, .zero) == 0,
              try await video.load(.canProvideSampleCursors),
              let cursor = video.makeSampleCursor(presentationTimeStamp: .negativeInfinity) else {
            throw ConversionError(L("A video timeline starting at zero and AVFoundation sample access are required."))
        }
        let firstDuration = cursor.currentSampleDuration
        var timing = try CFRSampleValidator(frameDuration: firstDuration)
        let clock = try FrameClock(numerator: firstDuration.value, denominator: firstDuration.timescale)
        repeat {
            try Task.checkCancellation()
            try timing.append(presentationTime: cursor.presentationTimeStamp, duration: cursor.currentSampleDuration)
            guard CMFormatDescriptionEqual(cursor.copyCurrentSampleFormatDescription(), otherFormatDescription: format) else {
                throw ConversionError(L("The video format changes within the recording."))
            }
        } while cursor.stepInPresentationOrder(byCount: 1) == 1
        try timing.finish(trackDuration: timeRange.duration)
        let sampleCount = timing.count, expectedPTS = timing.expectedPTS
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard audioTracks.count <= 1 else { throw ConversionError(L("At most one audio track is supported.")) }
        var audio: AudioMetadata?
        if let track = audioTracks.first {
            let audioFormats = try await track.load(.formatDescriptions)
            guard audioFormats.count == 1, let audioFormat = audioFormats.first,
                  let description = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormat) else {
                throw ConversionError(L("The audio parameters could not be determined."))
            }
            let rate = description.pointee.mSampleRate
            let channels = Int(description.pointee.mChannelsPerFrame)
            guard rate.isFinite, rate > 0, rate < Double(Int32.max), rate.rounded() == rate,
                  (1...2).contains(channels), CMTimeCompare(try await track.load(.timeRange).start, .zero) == 0 else {
                throw ConversionError(L("Mono/stereo audio starting at zero and an integral sample rate are required."))
            }
            audio = AudioMetadata(channels: channels, sampleRate: Int(rate))
        }
        let timecodeTracks = try await asset.loadTracks(withMediaType: .timecode)
        guard timecodeTracks.count <= 1 else { throw ConversionError(L("Ambiguous timecode tracks.")) }
        var sourceStart: Int64 = 0
        var timecodeFormat = "NDF"
        if let track = timecodeTracks.first {
            guard try await track.load(.canProvideSampleCursors),
                  let tc = track.makeSampleCursor(presentationTimeStamp: .negativeInfinity),
                  CMTimeCompare(tc.presentationTimeStamp, .zero) == 0,
                  CMTimeCompare(tc.currentSampleDuration, expectedPTS) == 0 else {
                throw ConversionError(L("One continuous timecode sample covering the entire video is required."))
            }
            let tcDescription = tc.copyCurrentSampleFormatDescription()
            guard CMTimeCompare(CMTimeCodeFormatDescriptionGetFrameDuration(tcDescription), firstDuration) == 0 else {
                throw ConversionError(L("The timecode frame rate differs from the video frame rate."))
            }
            guard Double(CMTimeCodeFormatDescriptionGetFrameQuanta(tcDescription)) == clock.framesPerSecond.rounded() else {
                throw ConversionError(L("The timecode frame count is inconsistent."))
            }
            let subtype = CMFormatDescriptionGetMediaSubType(tcDescription)
            let size: Int
            switch subtype {
            case kCMTimeCodeFormatType_TimeCode32: size = 4
            case kCMTimeCodeFormatType_TimeCode64: size = 8
            default: throw ConversionError(L("Unsupported timecode format."))
            }
            let storage = tc.currentSampleStorageRange
            guard storage.offset >= 0, storage.length == size,
                  let storageURL = tc.currentChunkStorageURL,
                  storageURL.standardizedFileURL.resolvingSymlinksInPath() == url.standardizedFileURL.resolvingSymlinksInPath() else {
                throw ConversionError(L("External or discontinuous timecode data is not supported."))
            }
            let handle = try FileHandle(forReadingFrom: storageURL)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(storage.offset))
            let data = try handle.read(upToCount: size) ?? Data()
            sourceStart = try Self.decodeTimecode(data, size: size)
            guard tc.stepInPresentationOrder(byCount: 1) == 0 else {
                throw ConversionError(L("Discontinuous timecode is not supported."))
            }
            let flags = CMTimeCodeFormatDescriptionGetTimeCodeFlags(tcDescription)
            timecodeFormat = flags & kCMTimeCodeFlag_DropFrame != 0 ? "DF" : "NDF"
            if timecodeFormat == "DF" {
                guard clock.numerator == 1001, [30000, 60000].contains(clock.denominator) else {
                    throw ConversionError(L("Unsupported drop-frame timecode rate."))
                }
            }
        }
        return MediaMetadata(url: url, width: width, height: height, clock: clock, frameCount: sampleCount,
                             audio: audio, colorSpace: colorSpace, sourceStartFrame: sourceStart,
                             timecodeFormat: timecodeFormat, rotationDegrees: rotation)
    }

    static func decodeTimecode(_ data: Data, size: Int) throws -> Int64 {
        guard data.count == size, size == 4 || size == 8 else { throw ConversionError(L("Corrupt timecode sample.")) }
        let value = data.withUnsafeBytes { bytes -> Int64 in
            if size == 4 { return Int64(Int32(bigEndian: bytes.loadUnaligned(as: Int32.self))) }
            return Int64(bigEndian: bytes.loadUnaligned(as: Int64.self))
        }
        guard value >= 0 else { throw ConversionError(L("Negative timecode is not supported.")) }
        return value
    }

    static func rotationDegrees(_ transform: CGAffineTransform) throws -> Int {
        let rotations: [(Int, [CGFloat])] = [(0, [1, 0, 0, 1]), (90, [0, 1, -1, 0]),
                                           (180, [-1, 0, 0, -1]), (270, [0, -1, 1, 0])]
        let matrix = [transform.a, transform.b, transform.c, transform.d]
        guard transform.tx.isFinite, transform.ty.isFinite,
              let rotation = rotations.first(where: { pair in
                  zip(matrix, pair.1).allSatisfy { abs($0 - $1) < 1e-6 }
              }) else { throw ConversionError(L("Only standard 0/90/180/270° rotation is supported, without scaling or reflection.")) }
        return rotation.0
    }

}
