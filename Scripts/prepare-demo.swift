#!/usr/bin/env swift
import Foundation
import AVFoundation
import CoreVideo

// Synthetic demonstration files only. Never read, copy or transcode user media.
let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = project.appendingPathComponent(".local/README-demo", isDirectory: true)
guard !FileManager.default.fileExists(atPath: output.path) else {
    throw NSError(domain: "VideoLoggerDemo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Demo folder already exists; choose a fresh checkout or remove only the previously generated demo folder manually."])
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func makeMovie(at url: URL) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: url.pathExtension.lowercased() == "mov" ? .mov : .mp4)
    writer.movieTimeScale = 25
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 90,
        AVVideoCompressionPropertiesKey: [AVVideoAllowFrameReorderingKey: false, AVVideoExpectedSourceFrameRateKey: 25],
        AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]])
    input.mediaTimeScale = 25; input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 90])
    guard writer.canAdd(input) else { throw CocoaError(.fileWriteUnknown) }
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<750 {
        var attempts = 0
        while !input.isReadyForMoreMediaData {
            guard writer.status != .failed, attempts < 10000 else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            try await Task.sleep(for: .milliseconds(1)); attempts += 1
        }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 160, 90, kCVPixelFormatType_32ARGB, nil, &buffer) == kCVReturnSuccess,
              let buffer else { throw CocoaError(.coderInvalidValue) }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) { memset(base, 0, CVPixelBufferGetDataSize(buffer)) }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 25)) else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
    }
    writer.endSession(atSourceTime: CMTime(value: 750, timescale: 25)); input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
}

let examples: [(String, [(Double, Double, String)])] = [
    ("Mountain_Road_001.MP4", [(1, 7.5, "Mountain switchbacks"), (12, 20, "Mountain panorama")]),
    ("Coastal_Ride_002.MOV", [(2, 8, "Scenic coastal road"), (10, 18.5, "Rider conversation")]),
    ("City_Exploration_003.MP4", [(1.5, 11.25, "City streets")]),
    ("Sunset_Ride_004.MOV", [(4, 14, "Sunset viewpoint")])
]
for (filename, segments) in examples {
    try await makeMovie(at: output.appendingPathComponent(filename))
    let object: [String: Any] = ["version": 2, "mediaFileName": filename,
        "cutSegments": segments.map { ["start": $0.0, "end": $0.1, "name": $0.2, "selected": true] as [String: Any] }]
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        .write(to: output.appendingPathComponent(filename + "-proj.llc"), options: [.withoutOverwriting])
}
print("Created four tiny synthetic CFR/SDR movies and six named ranges in .local/README-demo.")
