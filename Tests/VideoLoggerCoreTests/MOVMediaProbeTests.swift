import Testing
import Foundation
import AVFoundation
import CoreVideo
import CoreMedia
@testable import VideoLoggerCore

/// These tiny synthetic H.264 movies test the real AVFoundation adapter, not iPhone capture.
struct MOVMediaProbeTests {
    @Test(arguments: [0, 90, 180, 270])
    func realMOVProbeReadsOrientationAndPreservesFile(rotation: Int) async throws {
        let fixture = try await SyntheticMovie(rotation: rotation)
        defer { fixture.cleanup() }
        let before = try Data(contentsOf: fixture.url)
        let media = try await AVFoundationMediaProbe().inspect(fixture.url)
        #expect(media.rotationDegrees == rotation)
        #expect(media.width == (rotation == 90 || rotation == 270 ? 48 : 64))
        #expect(media.height == (rotation == 90 || rotation == 270 ? 64 : 48))
        #expect(media.clock == (try FrameClock(numerator: 1, denominator: 25)))
        #expect(media.frameCount == 8 && media.sourceStartFrame == 0)
        #expect(media.colorSpace == "1-1-1 (Rec. 709)")
        #expect(try Data(contentsOf: fixture.url) == before)
    }
    @Test
    func fractionalMOVConvertsBothExportModesWithOriginalURL() async throws {
        let fixture = try await SyntheticMovie(numerator: 1001, denominator: 30000)
        defer { fixture.cleanup() }
        let source = fixture.url.deletingLastPathComponent().appendingPathComponent("phone.llc")
        try JSONSerialization.data(withJSONObject: ["version": 2, "mediaFileName": fixture.url.lastPathComponent,
            "cutSegments": [["start": 1001.0/30000, "end": 6006.0/30000, "name": "Phone range"]]]).write(to: source)
        let before = try Data(contentsOf: fixture.url), llcBefore = try Data(contentsOf: source)
        for stringout in [false, true] {
            let result = try await ConversionService().convert(source: source, options: ExportOptions(includeStringout: stringout))
            #expect(result.plan.media.clock == (try FrameClock(numerator: 1001, denominator: 30000)))
            #expect(result.plan.ranges[0].start == 1 && result.plan.ranges[0].end == 6)
            let xml = try XMLDocument(data: result.document)
            #expect(try xml.nodes(forXPath: "//media-rep/@src").first?.stringValue == fixture.url.absoluteString)
            #expect(try xml.nodes(forXPath: "//project").count == (stringout ? 1 : 0))
        }
        #expect(try Data(contentsOf: fixture.url) == before)
        #expect(try Data(contentsOf: source) == llcBefore)
    }
    @Test
    func realVFRMovieBlocksProbeAndExportWithoutApproximations() async throws {
        let fixture = try await SyntheticMovie(variable: true)
        defer { fixture.cleanup() }
        let before = try Data(contentsOf: fixture.url)
        do {
            _ = try await AVFoundationMediaProbe().inspect(fixture.url)
            Issue.record("VFR should be rejected")
        } catch { #expect(error.localizedDescription.contains("VFR")) }
        let source = fixture.url.deletingLastPathComponent().appendingPathComponent("vfr.llc")
        try JSONSerialization.data(withJSONObject: ["version": 2, "mediaFileName": fixture.url.lastPathComponent,
            "cutSegments": [["start": 0, "end": 0.1, "name": "VFR range"]]]).write(to: source)
        do {
            _ = try await ConversionService().convert(source: source)
            Issue.record("VFR conversion should be rejected")
        } catch { #expect(error.localizedDescription.contains("VFR")) }
        #expect(try Data(contentsOf: fixture.url) == before)
    }
}

private struct SyntheticMovie {
    let url: URL
    init(rotation: Int = 0, numerator: Int64 = 1, denominator: Int32 = 25, variable: Bool = false) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        url = directory.appendingPathComponent("Synthetic — Łódź & SDR.MOV")
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            writer.movieTimeScale = denominator
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 48,
                AVVideoCompressionPropertiesKey: [AVVideoAllowFrameReorderingKey: false,
                    AVVideoMaxKeyFrameIntervalKey: 1, AVVideoExpectedSourceFrameRateKey: Double(denominator)/Double(numerator)],
                AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]])
            input.mediaTimeScale = denominator
            input.expectsMediaDataInRealTime = false
            if rotation == 90 { input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 48, ty: 0) }
            if rotation == 180 { input.transform = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 64, ty: 48) }
            if rotation == 270 { input.transform = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 64) }
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                    kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 48])
            guard writer.canAdd(input) else { throw ConversionError("Synthetic writer cannot add H.264 input") }
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? ConversionError("Synthetic writer failed to start") }
            writer.startSession(atSourceTime: .zero)
            let frames: [Int64] = variable ? [0, 1, 3, 4, 6, 7, 9, 10] : Array(0..<8)
            for frame in frames {
                var attempts = 0
                while !input.isReadyForMoreMediaData {
                    if writer.status == .failed || attempts > 5000 { throw writer.error ?? ConversionError("Synthetic writer timeout") }
                    try await Task.sleep(for: .milliseconds(1)); attempts += 1
                }
                var pixel: CVPixelBuffer?
                guard CVPixelBufferCreate(kCFAllocatorDefault, 64, 48, kCVPixelFormatType_32ARGB, nil, &pixel) == kCVReturnSuccess,
                      let pixel else { throw ConversionError("Synthetic pixel allocation failed") }
                CVPixelBufferLockBaseAddress(pixel, [])
                if let base = CVPixelBufferGetBaseAddress(pixel) { memset(base, 0, CVPixelBufferGetDataSize(pixel)) }
                CVPixelBufferUnlockBaseAddress(pixel, [])
                guard adaptor.append(pixel, withPresentationTime: CMTime(value: frame * numerator, timescale: denominator)) else {
                    throw writer.error ?? ConversionError("Synthetic append failed")
                }
            }
            writer.endSession(atSourceTime: CMTime(value: (frames.last! + 1) * numerator, timescale: denominator))
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? ConversionError("Synthetic movie not completed") }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
    func cleanup() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
}
