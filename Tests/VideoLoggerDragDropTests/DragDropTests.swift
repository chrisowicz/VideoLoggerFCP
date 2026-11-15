import Testing
import Foundation
import AppKit
import VideoLoggerTestSupport
import VideoLoggerCore
@testable import VideoLoggerDragDrop

private let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let dtdDirectory = URL(fileURLWithPath: "/Applications/Final Cut Pro Creator Studio.app/Contents/Frameworks/Interchange.framework/Versions/A/Resources")

struct DragDropTests {
    @Test(arguments: [false, true])
    func readsBothExistingExportVariants(stringout: Bool) throws {
        let (data, media) = try base(stringout: stringout)
        let document = try DragDocumentReader.read(data, source: repository.appendingPathComponent("test.fcpxml"), media: media)
        #expect(document.mediaName == "Sample_A.MP4")
        #expect(document.segments.map(\.startFrame) == [37, 210, 607, 1049])
        #expect(document.segments.map(\.durationFrames) == [98, 150, 217, 210])
        #expect(document.initialSelection == IndexSet(0..<4))
    }

    @Test
    func payloadPreservesOrderTimecodeAudioAndOriginalMedia() throws {
        let (data, media) = try base()
        let document = try DragDocumentReader.read(data, source: repository.appendingPathComponent("test.fcpxml"), media: media)
        let payload = try document.payload(for: IndexSet([3, 0, 2]))
        let xml = try XMLDocument(data: #require(payload.data(for: FCPXMLDragPayload.currentType)))
        #expect(try xml.nodes(forXPath: "/fcpxml/asset-clip/@name").map(\.stringValue) == [
            "Opening", "Wide shot", "Closing"
        ])
        #expect(try xml.nodes(forXPath: "/fcpxml/asset-clip[1]/@start").first?.stringValue == "2460193736/30000s")
        #expect(try xml.nodes(forXPath: "/fcpxml/asset-clip[1]/@duration").first?.stringValue == "98098/30000s")
        #expect(try xml.nodes(forXPath: "/fcpxml/asset-clip/keyword").count == 3)
        #expect(try xml.nodes(forXPath: "//event | //library | //project | //sequence | //spine | //adjust-conform | //adjust-transform").isEmpty)
        #expect(try xml.nodes(forXPath: "//asset-clip/@offset").isEmpty)
        #expect(try xml.nodes(forXPath: "//resources/asset/@name").first?.stringValue == document.mediaName)
        #expect(try xml.nodes(forXPath: "//resources/asset/@hasAudio").first?.stringValue == "1")
        #expect(try xml.nodes(forXPath: "//media-rep/@src").first?.stringValue == media.url.absoluteString)
        #expect(try xml.nodes(forXPath: "//option[@key='copy assets']/@value").first?.stringValue == "0")
        #expect(try xml.nodes(forXPath: "//format/@frameDuration").first?.stringValue == "1001/30000s")
    }

    @Test
    func selectionFlagsAndRepeatedSnapshotsAreIndependent() throws {
        let (data, media) = try base()
        let document = try DragDocumentReader.read(data, source: repository, media: media, selected: [false, true, false, true])
        #expect(document.initialSelection == IndexSet([1, 3]))
        let one = try document.payload(for: IndexSet(integer: 1))
        let four = try document.payload(for: IndexSet(0..<4))
        let again = try document.payload(for: IndexSet(integer: 1))
        #expect(one.count == 1 && four.count == 4)
        #expect(one.data(for: FCPXMLDragPayload.currentType) == again.data(for: FCPXMLDragPayload.currentType))
        #expect(document.initialSelection == IndexSet([1, 3]))
        #expect(throws: (any Error).self) { try document.payload(for: []) }
        #expect(throws: (any Error).self) { try document.payload(for: IndexSet(integer: 4)) }
    }

    @Test
    func versionNegotiationMatchesActualDocuments() throws {
        let (data, media) = try base()
        let document = try DragDocumentReader.read(data, source: repository, media: media)
        let payload = try document.payload(for: IndexSet(0..<4))
        for (type, version) in [(FCPXMLDragPayload.currentType, "1.14"), (FCPXMLDragPayload.legacyType, "1.9"), (FCPXMLDragPayload.genericType, "1.14")] {
            let xml = try XMLDocument(data: #require(payload.data(for: type)))
            #expect(xml.rootElement()?.attribute(forName: "version")?.stringValue == version)
            #expect(try xml.nodes(forXPath: "/fcpxml/asset-clip").count == 4)
        }
        #expect(payload.data(for: "public.file-url") == nil)
        #expect(payload.data(for: "public.utf8-plain-text") == nil)
    }

    @MainActor @Test
    func nativePasteboardPromisesReturnXMLAndCanBeRepeated() throws {
        let (data, media) = try base()
        let document = try DragDocumentReader.read(data, source: repository, media: media)
        let payload = try document.payload(for: IndexSet(0..<4))
        let board = NSPasteboard(name: NSPasteboard.Name("pl.videologgerfcp.test." + UUID().uuidString))
        defer { board.clearContents() }
        for _ in 0..<2 {
            let provider = FCPXMLPasteboardProvider(payload: payload)
            let item = try provider.makeItem()
            #expect(Set(item.types.map(\.rawValue)) == Set(FCPXMLDragPayload.types))
            board.clearContents()
            #expect(board.writeObjects([item]))
            for type in FCPXMLDragPayload.types {
                #expect(board.data(forType: NSPasteboard.PasteboardType(type)) == payload.data(for: type))
            }
            #expect(board.data(forType: .fileURL) == nil)
            #expect(board.data(forType: .string) == nil)
            withExtendedLifetime(provider) {}
        }
    }

    @Test
    func preservesUnicodeEscapingAndMetadata() throws {
        let (data, media) = try base()
        let xml = try XMLDocument(data: data)
        let keyword = try #require(xml.nodes(forXPath: "//event/asset-clip/keyword[1]").first as? XMLElement)
        let name = "Zażółć <&> \"' 🎬"
        keyword.attribute(forName: "value")?.stringValue = name
        let source = try #require(xml.nodes(forXPath: "//event/asset-clip").first as? XMLElement)
        let metadata = XMLElement(name: "metadata")
        let md = XMLElement(name: "md")
        md.addAttribute(XMLNode.attribute(withName: "key", stringValue: "test.key") as! XMLNode)
        md.addAttribute(XMLNode.attribute(withName: "value", stringValue: "Żółć & metadata") as! XMLNode)
        metadata.addChild(md); source.addChild(metadata)
        let document = try DragDocumentReader.read(xml.xmlData(), source: repository, media: media)
        let result = try XMLDocument(data: #require(document.payload(for: IndexSet(integer: 0)).data(for: FCPXMLDragPayload.currentType)))
        #expect(try result.nodes(forXPath: "/fcpxml/asset-clip/@name").first?.stringValue == name)
        #expect(try result.nodes(forXPath: "/fcpxml/asset-clip/keyword/@value").first?.stringValue == name)
        #expect(try result.nodes(forXPath: "//md/@value").first?.stringValue == "Żółć & metadata")
    }

    @Test
    func rejectsMalformedUnsupportedOrMismatchedXML() throws {
        let (data, media) = try base()
        for (xpath, attribute, value) in [
            ("/fcpxml", "version", "1.14"),
            ("//format", "frameDuration", "1/25s"),
            ("//event/asset-clip", "ref", "missing"),
            ("//event/asset-clip/keyword[1]", "start", "2460688231/30000s"),
            ("//event/asset-clip/keyword[1]", "duration", "999999999/30000s"),
            ("//asset", "audioRate", "44100"),
            ("//media-rep", "src", "https://example.com/film.MP4"),
        ] {
            let xml = try XMLDocument(data: data)
            let node = try #require(xml.nodes(forXPath: xpath).first as? XMLElement)
            node.attribute(forName: attribute)?.stringValue = value
            #expect(throws: (any Error).self) { try DragDocumentReader.read(xml.xmlData(), source: repository, media: media) }
        }
        #expect(throws: (any Error).self) { try DragDocumentReader.read(Data("not XML".utf8), source: repository, media: media) }
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: dtdDirectory.appendingPathComponent("FCPXMLv1_14.dtd").path), "Brak lokalnych DTD Apple."))
    func validatesBothAdvertisedVersionsForSingleAndMultipleClips() throws {
        let (data, media) = try base()
        let document = try DragDocumentReader.read(data, source: repository, media: media)
        for indices in [IndexSet(integer: 0), IndexSet([0, 2]), IndexSet(0..<4)] {
            let payload = try document.payload(for: indices)
            try validate(#require(payload.data(for: FCPXMLDragPayload.currentType)), version: "1_14")
            try validate(#require(payload.data(for: FCPXMLDragPayload.legacyType)), version: "1_9")
        }
    }

    @Test(arguments: ["9-18-9 (Rec. 2020 HLG)", "9-16-9 (Rec. 2020 PQ)", nil] as [String?])
    func sourceColorReachesExportAndDragWithoutAnAssetOverride(colorSpace: String?) throws {
        let (data, media) = try base(stringout: true, colorSpace: colorSpace)
        let document = try DragDocumentReader.read(data, source: repository, media: media)
        let payload = try document.payload(for: [0])
        for representation in [data, try #require(payload.data(for: FCPXMLDragPayload.currentType)),
                               try #require(payload.data(for: FCPXMLDragPayload.legacyType))] {
            let xml = try XMLDocument(data: representation)
            #expect(try xml.nodes(forXPath: "//format/@colorSpace").map(\.stringValue) == (colorSpace.map { [$0] } ?? []))
            #expect(try xml.nodes(forXPath: "//asset/@colorSpaceOverride").isEmpty)
            #expect(try xml.nodes(forXPath: "//media-rep/@src").first?.stringValue == media.url.absoluteString)
        }
        if FileManager.default.fileExists(atPath: dtdDirectory.appendingPathComponent("FCPXMLv1_14.dtd").path) {
            try validate(data, version: "1_9")
            try validate(#require(payload.data(for: FCPXMLDragPayload.currentType)), version: "1_14")
            try validate(#require(payload.data(for: FCPXMLDragPayload.legacyType)), version: "1_9")
        }
    }

    @Test
    func loaderReusesEngineForLLCAndReadsExistingFCPXML() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let llc = folder.appendingPathComponent("sample.llc")
        let xml = folder.appendingPathComponent("sample.fcpxml")
        let mediaURL = folder.appendingPathComponent("Sample_A.MP4")
        let input = try Data(contentsOf: FixtureResources.project("four-segments"))
        try input.write(to: llc); try Data("not real video; stub probe".utf8).write(to: mediaURL)
        let probe = StubProbe()
        let result = try await ConversionService(probe: probe).convert(source: llc)
        try result.document.write(to: xml)
        let fromLLC = try await DragSourceLoader(probe: probe).load(llc)
        let fromXML = try await DragSourceLoader(probe: probe).load(xml)
        #expect(fromLLC.segments.map(\.startFrame) == fromXML.segments.map(\.startFrame))
        #expect(fromLLC.media.url == mediaURL)
        #expect(try Data(contentsOf: llc) == input)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIDEOLOGGER_TEST_MEDIA"].map { FileManager.default.fileExists(atPath: $0) } ?? false, "Ustaw VIDEOLOGGER_TEST_MEDIA dla integracji z rzeczywistym MP4."))
    func realMediaRoundTripAndOptionalFixtures() async throws {
        let mediaURL = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["VIDEOLOGGER_TEST_MEDIA"]))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let media = try await AVFoundationMediaProbe().inspect(mediaURL)
        let source = folder.appendingPathComponent("optional.llc")
        let input = ["version": 2, "mediaFileName": mediaURL.lastPathComponent,
            "cutSegments": [["start": 0.0, "end": media.durationSeconds, "name": "Whole source"]]] as [String: Any]
        try JSONSerialization.data(withJSONObject: input).write(to: source)
        let result = try await ConversionService().convert(source: source, mediaOverride: mediaURL)
        let xmlURL = folder.appendingPathComponent("optional.fcpxml")
        try result.document.write(to: xmlURL)
        let llc = try await DragSourceLoader().load(source, mediaOverride: mediaURL)
        let xml = try await DragSourceLoader().load(xmlURL, mediaOverride: mediaURL)
        #expect(llc.media.clock == xml.media.clock)
        #expect(try llc.payload(for: [0]).data(for: FCPXMLDragPayload.currentType)
            == xml.payload(for: [0]).data(for: FCPXMLDragPayload.currentType))
    }

    private func base(stringout: Bool = false, colorSpace: String? = "1-1-1 (Rec. 709)") throws -> (Data, MediaMetadata) {
        let source = try FixtureResources.project("four-segments")
        let project = try LosslessCutImporter().parse(Data(contentsOf: source), sourceURL: source)
        let media = try testMedia(url: URL(fileURLWithPath: "/originals/Zażółć & film #1.MP4"), colorSpace: colorSpace)
        let plan = try ConversionPlanner().plan(project: project, media: media, options: ExportOptions(includeStringout: stringout))
        return (try FCPXMLExporter().export(plan), media)
    }

    private func validate(_ data: Data, version: String) throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".fcpxml")
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/xmllint")
        process.arguments = ["--nonet", "--noout", "--dtdvalid", dtdDirectory.appendingPathComponent("FCPXMLv\(version).dtd").absoluteString, file.path]
        let errors = Pipe(); process.standardError = errors
        try process.run()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "DTD: \(message)")
    }
}

private struct StubProbe: MediaProbing {
    func inspect(_ url: URL) async throws -> MediaMetadata {
        try FileAccess.requireReadableFile(url)
        return try testMedia(url: url)
    }
}
private func testMedia(url: URL, colorSpace: String? = "1-1-1 (Rec. 709)") throws -> MediaMetadata {
    MediaMetadata(url: url, width: 3840, height: 3840, clock: try FrameClock(numerator: 1001, denominator: 30000), frameCount: 26361,
                  audio: AudioMetadata(channels: 2, sampleRate: 48000), colorSpace: colorSpace,
                  sourceStartFrame: 2457699, timecodeFormat: "DF", rotationDegrees: 90)
}
