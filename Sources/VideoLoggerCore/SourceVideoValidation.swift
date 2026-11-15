import VideoLoggerLocalization
import Foundation
import CoreMedia

/// Safety gate shared by MOV and MP4. It never changes source metadata or pixels.
enum SourceVideoValidation {
    static func colorSpace(codec: FourCharCode, extensions: NSDictionary, containsHDR: Bool) throws -> String? {
        let atoms = extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] as? NSDictionary
        let dolbyCodec = codec == kCMVideoCodecType_DolbyVisionHEVC || codec == 0x64766865 // dvhe
        let dolbyVision = dolbyCodec || atoms?["dvcC"] != nil || atoms?["dvvC"] != nil
        guard dolbyCodec || [kCMVideoCodecType_H264, kCMVideoCodecType_HEVC, 0x68657631].contains(codec) else { // hev1
            throw ConversionError(L("Unsupported video codec. H.264 and HEVC/H.265 in MP4 or MOV are supported (CFR)."))
        }
        if extensions[kCMFormatDescriptionExtension_LogTransferFunction] != nil {
            throw ConversionError(L("Log transfer characteristics are not supported. Export and Drag & Drop are blocked without changing the original colors."))
        }
        let primaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries] as? String
        let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction] as? String
        let matrix = extensions[kCMFormatDescriptionExtension_YCbCrMatrix] as? String
        let hdr = dolbyVision || containsHDR
            || extensions[kCMFormatDescriptionExtension_MasteringDisplayColorVolume] != nil
            || extensions[kCMFormatDescriptionExtension_ContentLightLevelInfo] != nil
            || extensions[kCMFormatDescriptionExtension_AlternativeTransferCharacteristics] != nil

        // FCPXML references the original bitstream, including Dolby Vision dynamic metadata.
        // Describe recognized base color spaces without setting an asset color override.
        switch (primaries, transfer, matrix) {
        case ("ITU_R_2020", "ITU_R_2100_HLG", "ITU_R_2020"): return "9-18-9 (Rec. 2020 HLG)"
        case ("ITU_R_2020", "SMPTE_ST_2084_PQ", "ITU_R_2020"): return "9-16-9 (Rec. 2020 PQ)"
        case ("ITU_R_709_2", "ITU_R_709_2", "ITU_R_709_2") where !hdr: return "1-1-1 (Rec. 709)"
        case ("ITU_R_2020", "ITU_R_709_2", "ITU_R_2020") where !hdr: return "9-1-9 (Rec. 2020)"
        default: return nil // FCP can inspect the original; never fill in missing or unfamiliar tags.
        }
    }
}

/// Inspect the actual presentation timeline. Minor clock variations can share an FCP grid.
struct VideoSampleTiming {
    private var counts: [FrameClock: Int64] = [:]
    private var shortest: CMTime?
    private var longest: CMTime?
    private(set) var endPTS = CMTime.zero
    private(set) var count: Int64 = 0
    var isVariable: Bool { counts.count > 1 }

    mutating func append(presentationTime: CMTime, duration: CMTime) throws {
        guard presentationTime.isNumeric, duration.isNumeric, presentationTime.epoch == 0, duration.epoch == 0,
              duration.value > 0, CMTimeCompare(presentationTime, endPTS) == 0 else {
            throw ConversionError(L("Invalid video timestamps or a gap in the presentation timeline. Export and Drag & Drop are blocked."))
        }
        let clock = try FrameClock(numerator: duration.value, denominator: duration.timescale)
        counts[clock, default: 0] += 1
        if shortest.map({ CMTimeCompare(duration, $0) < 0 }) ?? true { shortest = duration }
        if longest.map({ CMTimeCompare(duration, $0) > 0 }) ?? true { longest = duration }
        count += 1
        endPTS = CMTimeAdd(presentationTime, duration)
    }

    func finish(trackDuration: CMTime) throws -> FrameClock {
        guard trackDuration.isNumeric, trackDuration.epoch == 0, CMTimeCompare(endPTS, trackDuration) == 0,
              let shortest, let longest, let (clock, frequency) = counts.max(by: { $0.value < $1.value }) else {
            throw ConversionError(L("The track duration does not match complete frames; unsupported edit list or corrupt video."))
        }
        // Require a dominant cadence and limit each frame to ±10% of its duration.
        let step = CMTime(value: clock.numerator, timescale: clock.denominator)
        guard frequency >= count - count / 10,
              CMTimeCompare(CMTimeMultiply(shortest, multiplier: 10), CMTimeMultiply(step, multiplier: 9)) >= 0,
              CMTimeCompare(CMTimeMultiply(longest, multiplier: 10), CMTimeMultiply(step, multiplier: 11)) <= 0 else {
            throw ConversionError(L("VFR exceeds the timing tolerance. Export and Drag & Drop are blocked."))
        }
        return clock
    }
}
