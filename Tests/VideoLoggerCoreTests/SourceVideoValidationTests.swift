import Testing
import Foundation
import CoreMedia
import CoreGraphics
@testable import VideoLoggerCore

struct SourceVideoValidationTests {
    private var rec709: [String: Any] { [kCMFormatDescriptionExtension_ColorPrimaries as String: "ITU_R_709_2",
        kCMFormatDescriptionExtension_TransferFunction as String: "ITU_R_709_2",
        kCMFormatDescriptionExtension_YCbCrMatrix as String: "ITU_R_709_2"] }

    @Test(arguments: [kCMVideoCodecType_H264, kCMVideoCodecType_HEVC, FourCharCode(0x68657631)])
    func supportedCodecsKeepSDRTags(codec: FourCharCode) throws {
        #expect(try SourceVideoValidation.colorSpace(codec: codec, extensions: rec709 as NSDictionary, containsHDR: false) == "1-1-1 (Rec. 709)")
        #expect(try SourceVideoValidation.colorSpace(codec: codec, extensions: [:], containsHDR: false) == nil)
    }
    @Test
    func hdrDolbyVisionLogAndAmbiguousColorAreBlocked() throws {
        var cases: [[String: Any]] = []
        for transfer in [kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG, kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ] {
            var tags = rec709; tags[kCMFormatDescriptionExtension_TransferFunction as String] = transfer; cases.append(tags)
        }
        for key in [kCMFormatDescriptionExtension_MasteringDisplayColorVolume, kCMFormatDescriptionExtension_ContentLightLevelInfo,
                    kCMFormatDescriptionExtension_AlternativeTransferCharacteristics, kCMFormatDescriptionExtension_LogTransferFunction] {
            var tags = rec709; tags[key as String] = Data([0]); cases.append(tags)
        }
        for atom in ["dvcC", "dvvC"] {
            var tags = rec709; tags[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String] = [atom: Data([1])]; cases.append(tags)
        }
        cases.append([kCMFormatDescriptionExtension_ColorPrimaries as String: "ITU_R_2020"])
        for tags in cases {
            #expect(throws: ConversionError.self) { try SourceVideoValidation.colorSpace(codec: kCMVideoCodecType_HEVC, extensions: tags as NSDictionary, containsHDR: false) }
        }
        for codec in [kCMVideoCodecType_DolbyVisionHEVC, FourCharCode(0x64766865)] {
            #expect(throws: ConversionError.self) { try SourceVideoValidation.colorSpace(codec: codec, extensions: rec709 as NSDictionary, containsHDR: false) }
        }
        #expect(throws: ConversionError.self) { try SourceVideoValidation.colorSpace(codec: kCMVideoCodecType_HEVC, extensions: rec709 as NSDictionary, containsHDR: true) }
        #expect(throws: ConversionError.self) { try SourceVideoValidation.colorSpace(codec: kCMVideoCodecType_AppleProRes422, extensions: rec709 as NSDictionary, containsHDR: false) }
    }
    @Test(arguments: [24, 25, 30, 50, 60, 120])
    func cfrRequiresEveryExactPTSAndDuration(fps: Int32) throws {
        let duration = CMTime(value: 1, timescale: fps)
        var timing = try CFRSampleValidator(frameDuration: duration)
        for frame in 0..<5 { try timing.append(presentationTime: CMTime(value: Int64(frame), timescale: fps), duration: duration) }
        try timing.finish(trackDuration: CMTime(value: 5, timescale: fps))
        #expect(timing.count == 5)
        #expect(throws: ConversionError.self) { try timing.append(presentationTime: CMTime(value: 5, timescale: fps), duration: CMTime(value: 2, timescale: fps)) }
        #expect(throws: ConversionError.self) { try timing.append(presentationTime: CMTime(value: 6, timescale: fps), duration: duration) }
    }
    @Test
    func fractionalCFRAndMalformedTimesAreCheckedExactly() throws {
        let duration = CMTime(value: 1001, timescale: 30000)
        var timing = try CFRSampleValidator(frameDuration: duration)
        try timing.append(presentationTime: .zero, duration: duration)
        try timing.finish(trackDuration: duration)
        #expect(throws: ConversionError.self) { try timing.append(presentationTime: CMTime(value: 1, timescale: 30), duration: duration) }
        #expect(throws: ConversionError.self) { try timing.finish(trackDuration: CMTime(value: 1, timescale: 30)) }
        #expect(throws: ConversionError.self) { try timing.append(presentationTime: .invalid, duration: duration) }
        #expect(throws: ConversionError.self) { try CFRSampleValidator(frameDuration: .zero) }
    }
    @Test(arguments: [0, 90, 180, 270])
    func allStandardRotationsAreRecognized(rotation: Int) throws {
        let transforms = [0: CGAffineTransform.identity, 90: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 48, ty: 0),
                          180: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 64, ty: 48),
                          270: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 64)]
        #expect(try AVFoundationMediaProbe.rotationDegrees(#require(transforms[rotation])) == rotation)
    }
}
