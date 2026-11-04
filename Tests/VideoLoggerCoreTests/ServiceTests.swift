import Testing
import Foundation
@testable import VideoLoggerCore

struct ServiceTests {
    @Test
    func testServiceResolvesMediaFileNameWithoutRealVideo() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("project.llc")
        let media = directory.appendingPathComponent("film.MP4")
        let input = Data("{version:2,mediaFileName:'film.MP4',cutSegments:[{start:1,end:2,name:'A'}]}".utf8)
        try input.write(to: source)
        try Data("synthetic placeholder, not a video".utf8).write(to: media)
        let service = ConversionService(probe: StubProbe(expectedURL: media))
        let result = try await service.convert(source: source, options: ExportOptions(includeStringout: true))
        #expect(result.plan.media.url == media)
        #expect(result.warnings.isEmpty)
        #expect(result.plan.ranges.count == 1)
        #expect(try Data(contentsOf: source) == input)
        #expect(throws: Never.self) { try XMLDocument(data: result.document) }
    }
    @Test
    func testServiceAllowsExplicitMediaLocation() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("project.llc")
        let relocated = directory.appendingPathComponent("relocated.MP4")
        try Data("{version:2,mediaFileName:'original.MP4',cutSegments:[{start:0,end:1}]}".utf8).write(to: source)
        try Data().write(to: relocated)
        let result = try await ConversionService(probe: StubProbe(expectedURL: relocated)).convert(source: source, mediaOverride: relocated)
        #expect(result.plan.project.mediaFileName == "original.MP4")
        #expect(result.plan.media.url == relocated)
    }
    @Test
    func testMissingMediaIsAnErrorWithoutMetadataGuessing() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("project.llc")
        try Data("{version:2,mediaFileName:'missing.MP4',cutSegments:[{start:0,end:1}]}".utf8).write(to: source)
        do { _ = try await ConversionService().convert(source: source); Issue.record("Expected missing media error") }
        catch { #expect(error.localizedDescription.contains("missing.MP4")) }
    }
    @Test
    func testOutputNamingAndNoOverwrite() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("project-proj.llc")
        let output = SafeOutputWriter.defaultOutput(for: source)
        #expect(output.lastPathComponent == "project-proj.fcpxml")
        let bytes = Data("first".utf8)
        try SafeOutputWriter.write(bytes, to: output, protecting: [source])
        #expect(throws: (any Error).self) { try SafeOutputWriter.write(Data("second".utf8), to: output, protecting: [source]) }
        #expect(try Data(contentsOf: output) == bytes)
        #expect(throws: (any Error).self) { try SafeOutputWriter.write(bytes, to: source, protecting: [source]) }
    }
    @Test
    func testWriterProtectsSourcesAndSymlinks() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("original.fcpxml")
        let alias = directory.appendingPathComponent("alias.fcpxml")
        let bytes = Data("source".utf8)
        try bytes.write(to: source)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        #expect(throws: (any Error).self) { try SafeOutputWriter.write(Data(), to: source, protecting: [source]) }
        #expect(throws: (any Error).self) { try SafeOutputWriter.write(Data(), to: alias, protecting: [source]) }
        #expect(try Data(contentsOf: source) == bytes)
    }
    @Test
    func testFileValidationRejectsDirectoriesAndNetworkURLs() throws {
        #expect(throws: (any Error).self) { try FileAccess.requireReadableFile(URL(fileURLWithPath: NSTemporaryDirectory())) }
        #expect(throws: (any Error).self) { try FileAccess.requireReadableFile(URL(string: "https://example.com/film.MP4")!) }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIDEOLOGGER_TEST_MEDIA"].map { FileManager.default.fileExists(atPath: $0) } ?? false, "Ustaw VIDEOLOGGER_TEST_MEDIA dla opcjonalnego testu rzeczywistego medium."))
    func testOptionalRealMediaProbe() async throws {
        guard let path = ProcessInfo.processInfo.environment["VIDEOLOGGER_TEST_MEDIA"] else {
            return
        }
        let media = try await AVFoundationMediaProbe().inspect(URL(fileURLWithPath: path))
        #expect(media.width > 0 && media.height > 0)
        #expect(media.frameCount > 0 && media.clock.secondsPerFrame > 0)
        #expect(media.sourceStartFrame >= 0)
        #expect([0, 90, 180, 270].contains(media.rotationDegrees))
    }
    @Test(arguments: [false, true], [false, true])
    func testExportBesideLLCAndMediaLocationWarning(stringout: Bool, separateMediaDirectory: Bool) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceDirectory = directory.appendingPathComponent("LLC & żółć", isDirectory: true)
        let mediaDirectory = separateMediaDirectory
            ? directory.appendingPathComponent("Media #original", isDirectory: true) : sourceDirectory
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let source = sourceDirectory.appendingPathComponent("Film.żółć-proj.llc")
        let media = mediaDirectory.appendingPathComponent("Film.żółć.MP4")
        let input = Data("{version:2,mediaFileName:'Film.żółć.MP4',cutSegments:[{start:1,end:2,name:'Oryginalna nazwa & żółć'}]}".utf8)
        let originalMedia = Data("synthetic placeholder, no video copied".utf8)
        try input.write(to: source)
        try originalMedia.write(to: media)
        let name = "Example & <Łódź> \"1\" 'żółć'"
        let result = try await ConversionService(probe: StubProbe(expectedURL: media)).convert(
            source: source, mediaOverride: separateMediaDirectory ? media : nil,
            options: ExportOptions(eventName: name, includeStringout: stringout))
        #expect(result.warnings.count == (separateMediaDirectory ? 1 : 0))
        if separateMediaDirectory {
            let warning = try #require(result.warnings.first)
            #expect(warning.contains(sourceDirectory.standardizedFileURL.resolvingSymlinksInPath().path))
            #expect(warning.contains(mediaDirectory.standardizedFileURL.resolvingSymlinksInPath().path))
        }
        let output = SafeOutputWriter.defaultOutput(for: source, includeStringout: stringout)
        #expect(output.deletingLastPathComponent() == sourceDirectory)
        #expect(output.lastPathComponent == "Film.żółć-proj" + (stringout ? "-stringout" : "") + ".fcpxml")
        try SafeOutputWriter.write(result.document, to: output, protecting: [source, media])
        #expect(throws: (any Error).self) {
            try SafeOutputWriter.write(Data("replacement".utf8), to: output, protecting: [source, media])
        }
        #expect(try Data(contentsOf: output) == result.document)
        #expect(try Data(contentsOf: source) == input)
        #expect(try Data(contentsOf: media) == originalMedia)
        #expect(!FileManager.default.fileExists(atPath: sourceDirectory.appendingPathComponent("Exports").path))
        let xml = try XMLDocument(data: Data(contentsOf: output))
        #expect(try xml.nodes(forXPath: "/fcpxml/event/@name").first?.stringValue == name)
        #expect(try xml.nodes(forXPath: "//media-rep/@src").first?.stringValue == media.absoluteString)
        #expect(try xml.nodes(forXPath: "/fcpxml/event/project").count == (stringout ? 1 : 0))
        #expect(try xml.nodes(forXPath: "/fcpxml/event/asset-clip/keyword/@value").first?.stringValue == "Oryginalna nazwa & żółć")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VideoLoggerTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct StubProbe: MediaProbing {
    let expectedURL: URL
    func inspect(_ url: URL) async throws -> MediaMetadata {
        guard url == expectedURL else { throw ConversionError("Unexpected media URL") }
        return MediaMetadata(url: url, width: 1920, height: 1080,
                             clock: try FrameClock(numerator: 1, denominator: 25), frameCount: 250)
    }
}
