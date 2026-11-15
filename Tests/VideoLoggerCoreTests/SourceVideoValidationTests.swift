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
    @Test(arguments: [
        ("ITU_R_2100_HLG", "9-18-9 (Rec. 2020 HLG)"),
        ("SMPTE_ST_2084_PQ", "9-16-9 (Rec. 2020 PQ)"),
        ("ITU_R_709_2", "9-1-9 (Rec. 2020)")
    ])
    func recognizedRec2020ProfilesKeepTheirTags(transfer: String, expected: String) throws {
        let tags = [kCMFormatDescriptionExtension_ColorPrimaries as String: "ITU_R_2020",
                    kCMFormatDescriptionExtension_TransferFunction as String: transfer,
                    kCMFormatDescriptionExtension_YCbCrMatrix as String: "ITU_R_2020"]
        #expect(try SourceVideoValidation.colorSpace(codec: kCMVideoCodecType_HEVC, extensions: tags as NSDictionary,
                                                    containsHDR: transfer != "ITU_R_709_2") == expected)
    }

    @Test
    func dolbyVisionHLGKeepsTheBaseSpaceAndAmbiguousTagsDeferToTheOriginal() throws {
        var hlg: [String: Any] = [kCMFormatDescriptionExtension_ColorPrimaries as String: "ITU_R_2020",
                    kCMFormatDescriptionExtension_TransferFunction as String: "ITU_R_2100_HLG",
                    kCMFormatDescriptionExtension_YCbCrMatrix as String: "ITU_R_2020"]
        hlg[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String] = ["dvvC": Data([1])]
        for codec in [kCMVideoCodecType_HEVC, kCMVideoCodecType_DolbyVisionHEVC, FourCharCode(0x64766865)] {
            #expect(try SourceVideoValidation.colorSpace(codec: codec, extensions: hlg as NSDictionary,
                                                        containsHDR: true) == "9-18-9 (Rec. 2020 HLG)")
        }
        let incomplete = [kCMFormatDescriptionExtension_ColorPrimaries as String: "ITU_R_2020"]
        var p3 = rec709
        p3[kCMFormatDescriptionExtension_ColorPrimaries as String] = "P3_D65"
        for tags in [incomplete, p3] {
            #expect(try SourceVideoValidation.colorSpace(codec: kCMVideoCodecType_HEVC, extensions: tags as NSDictionary,
                                                        containsHDR: false) == nil)
        }
        #expect(try SourceVideoValidation.colorSpace(codec: kCMVideoCodecType_HEVC, extensions: rec709 as NSDictionary,
                                                    containsHDR: true) == nil)
        #expect(try SourceVideoValidation.colorSpace(codec: kCMVideoCodecType_DolbyVisionHEVC, extensions: rec709 as NSDictionary,
                                                    containsHDR: false) == nil)
    }

    @Test
    func logAndUnsupportedCodecsRemainBlocked() {
        var log = rec709
        log[kCMFormatDescriptionExtension_LogTransferFunction as String] = "AppleLog"
        #expect(throws: ConversionError.self) {
            try SourceVideoValidation.colorSpace(codec: kCMVideoCodecType_HEVC, extensions: log as NSDictionary, containsHDR: false)
        }
        #expect(throws: ConversionError.self) {
            try SourceVideoValidation.colorSpace(codec: kCMVideoCodecType_AppleProRes422, extensions: rec709 as NSDictionary, containsHDR: false)
        }
    }

    @Test(arguments: [24, 25, 30, 50, 60, 120])
    func constantRatesRemainExact(fps: Int32) throws {
        var timing = VideoSampleTiming()
        let duration = CMTime(value: 1, timescale: fps)
        for frame in 0..<5 { try timing.append(presentationTime: CMTime(value: Int64(frame), timescale: fps), duration: duration) }
        #expect(try timing.finish(trackDuration: CMTime(value: 5, timescale: fps)) == FrameClock(numerator: 1, denominator: fps))
        #expect(!timing.isVariable)
        #expect(throws: ConversionError.self) { try timing.append(presentationTime: CMTime(value: 6, timescale: fps), duration: duration) }
    }

    @Test
    func fractionalCFRAndMalformedTimesAreCheckedExactly() throws {
        let duration = CMTime(value: 1001, timescale: 30000)
        var timing = VideoSampleTiming()
        try timing.append(presentationTime: .zero, duration: duration)
        #expect(try timing.finish(trackDuration: duration) == FrameClock(numerator: 1001, denominator: 30000))
        #expect(throws: ConversionError.self) { try timing.finish(trackDuration: CMTime(value: 1, timescale: 30)) }
        #expect(throws: ConversionError.self) { try timing.append(presentationTime: .invalid, duration: duration) }
        #expect(throws: ConversionError.self) { try timing.append(presentationTime: duration, duration: .zero) }
    }

    @Test
    func minorUnevenDurationsUseDominantCadenceWithoutFirstSampleBias() throws {
        var timing = VideoSampleTiming()
        for ticks in [11, 9] + Array(repeating: 10, count: 18) {
            try timing.append(presentationTime: timing.endPTS, duration: CMTime(value: Int64(ticks), timescale: 600))
        }
        #expect(try timing.finish(trackDuration: CMTime(value: 200, timescale: 600)) == FrameClock(numerator: 1, denominator: 60))
        #expect(timing.isVariable)
    }

    @Test
    func mixedRatesAndLongSamplesStayBlocked() throws {
        for values in [[25] + Array(repeating: 20, count: 99), [21, 21] + Array(repeating: 20, count: 8)] {
            var timing = VideoSampleTiming()
            for ticks in values {
                try timing.append(presentationTime: timing.endPTS, duration: CMTime(value: Int64(ticks), timescale: 600))
            }
            #expect(throws: ConversionError.self) { try timing.finish(trackDuration: timing.endPTS) }
        }
    }

    @Test(arguments: [0, 90, 180, 270])
    func allStandardRotationsAreRecognized(rotation: Int) throws {
        let transforms = [0: CGAffineTransform.identity, 90: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 48, ty: 0),
                          180: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 64, ty: 48),
                          270: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 64)]
        #expect(try AVFoundationMediaProbe.rotationDegrees(#require(transforms[rotation])) == rotation)
    }
}
