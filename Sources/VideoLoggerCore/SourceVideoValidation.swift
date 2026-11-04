import VideoLoggerLocalization
import Foundation
import CoreMedia

/// Safety gate shared by MOV and MP4. It never changes source metadata or pixels.
enum SourceVideoValidation {
    static func colorSpace(codec: FourCharCode, extensions: NSDictionary, containsHDR: Bool) throws -> String? {
        let atoms = extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] as? NSDictionary
        let dolbyVision = codec == kCMVideoCodecType_DolbyVisionHEVC || codec == 0x64766865 // dvhe
            || atoms?["dvcC"] != nil || atoms?["dvvC"] != nil
        let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction] as? String
        let hdrTransfers = [kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String,
                            kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String]
        if dolbyVision || containsHDR || transfer.map(hdrTransfers.contains) == true
            || extensions[kCMFormatDescriptionExtension_MasteringDisplayColorVolume] != nil
            || extensions[kCMFormatDescriptionExtension_ContentLightLevelInfo] != nil
            || extensions[kCMFormatDescriptionExtension_AlternativeTransferCharacteristics] != nil {
            throw ConversionError(L("HDR / Dolby Vision: this variant cannot be mapped safely. Export and Drag & Drop are blocked; the original remains unchanged, without SDR conversion."))
        }
        guard [kCMVideoCodecType_H264, kCMVideoCodecType_HEVC, 0x68657631].contains(codec) else { // hev1
            throw ConversionError(L("Unsupported video codec. H.264 and HEVC/H.265 in MP4 or MOV are supported (SDR, CFR)."))
        }
        if extensions[kCMFormatDescriptionExtension_LogTransferFunction] != nil {
            throw ConversionError(L("Log transfer characteristics are not supported. Export and Drag & Drop are blocked without changing the original colors."))
        }
        let primaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries] as? String
        let matrix = extensions[kCMFormatDescriptionExtension_YCbCrMatrix] as? String
        if primaries == nil, transfer == nil, matrix == nil { return nil } // No invented Rec.709 tag.
        guard primaries == "ITU_R_709_2", transfer == "ITU_R_709_2", matrix == "ITU_R_709_2" else {
            throw ConversionError(L("Unsupported or incomplete color metadata (SDR Rec.709 or no tags required). Export and Drag & Drop are blocked; colors are not converted."))
        }
        return "1-1-1 (Rec. 709)"
    }
}

/// Exact comparison of every presentation timestamp and duration; no nominal-fps tolerance.
struct CFRSampleValidator {
    let frameDuration: CMTime
    private(set) var expectedPTS = CMTime.zero
    private(set) var count: Int64 = 0
    init(frameDuration: CMTime) throws {
        guard frameDuration.isNumeric, frameDuration.epoch == 0, frameDuration.value > 0,
              frameDuration.timescale > 0 else { throw ConversionError(L("Invalid video frame duration.")) }
        self.frameDuration = frameDuration
    }
    mutating func append(presentationTime: CMTime, duration: CMTime) throws {
        guard presentationTime.isNumeric, duration.isNumeric, presentationTime.epoch == 0, duration.epoch == 0,
              CMTimeCompare(duration, frameDuration) == 0, CMTimeCompare(presentationTime, expectedPTS) == 0 else {
            throw ConversionError(L("The video has a variable frame rate (VFR), gaps or irregular PTS. Segments cannot be mapped exactly by the CFR engine. Export and Drag & Drop are blocked without approximating timing."))
        }
        count += 1; expectedPTS = CMTimeAdd(expectedPTS, frameDuration)
    }
    func finish(trackDuration: CMTime) throws {
        guard count > 0, trackDuration.isNumeric, trackDuration.epoch == 0,
              CMTimeCompare(expectedPTS, trackDuration) == 0 else {
            throw ConversionError(L("The track duration does not match complete frames; unsupported edit list or corrupt video."))
        }
    }
}
