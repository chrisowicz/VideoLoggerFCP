import Testing
import Foundation
@testable import VideoLoggerCore

struct ExporterTests {
    @Test
    func testSourceClipKeywordsCollectionsAndNames() throws {
        let plan = try ConversionPlanner().plan(project: fixtureProject(), media: testMedia(), options: ExportOptions())
        let xml = try document(plan)
        #expect(try nodes(xml, "/fcpxml[@version='1.9']/resources/format").count == 1)
        #expect(try nodes(xml, "/fcpxml/resources/asset/media-rep[@kind='original-media']").count == 1)
        #expect(try value(xml, "/fcpxml/resources/asset/@name") == plan.project.mediaFileName)
        #expect(try value(xml, "/fcpxml/event/asset-clip/@name") == plan.project.mediaFileName)
        #expect(try nodes(xml, "/fcpxml/event/asset-clip/keyword").count == 4)
        #expect(try nodes(xml, "/fcpxml/event/keyword-collection").count == 4)
        #expect(try value(xml, "/fcpxml/event/asset-clip/keyword[4]/@value") == "Closing")
        #expect(try value(xml, "/fcpxml/event/asset-clip/keyword[1]/@start") == "37037/30000s")
        #expect(try value(xml, "/fcpxml/event/asset-clip/keyword[1]/@duration") == "98098/30000s")
        #expect(try nodes(xml, "/fcpxml/event/project").isEmpty)
    }
    @Test
    func testStringoutSelectionOrderAndContinuousOffsets() throws {
        let project = testProject([
            LogSegment(start: 5, end: 7, name: "Later"),
            LogSegment(start: 2, end: 3, name: "Unselected", selected: false),
            LogSegment(start: 0, end: 1, name: "Earlier"),
        ])
        let plan = try ConversionPlanner().plan(project: project,
            media: testMedia(clock: FrameClock(numerator: 1, denominator: 25)), options: ExportOptions(includeStringout: true))
        let xml = try document(plan)
        #expect(try nodes(xml, "/fcpxml/event/asset-clip/keyword").count == 3)
        #expect(try nodes(xml, "//spine/asset-clip").count == 2)
        #expect(try value(xml, "//spine/asset-clip[1]/@name") == "Later")
        #expect(try value(xml, "//spine/asset-clip[2]/@name") == "Earlier")
        #expect(try value(xml, "//spine/asset-clip[1]/@offset") == "0/25s")
        #expect(try value(xml, "//spine/asset-clip[2]/@offset") == "50/25s")
        #expect(try value(xml, "//sequence/@duration") == "75/25s")
    }
    @Test
    func testSourceTimecodeIsAddedToKeywordsAndStringoutButNotOffsets() throws {
        let plan = try ConversionPlanner().plan(project: testProject([LogSegment(start: 1, end: 2, name: "TC")]),
            media: testMedia(sourceStartFrame: 2457699), options: ExportOptions(includeStringout: true))
        let xml = try document(plan)
        #expect(try value(xml, "//resources/asset/@start") == "2460156699/30000s")
        #expect(try value(xml, "/fcpxml/event/asset-clip/@start") == "2460156699/30000s")
        #expect(try value(xml, "//keyword/@start") == "2460186729/30000s")
        #expect(try value(xml, "//spine/asset-clip/@start") == "2460186729/30000s")
        #expect(try value(xml, "//spine/asset-clip/@offset") == "0/30000s")
        #expect(try value(xml, "/fcpxml/event/asset-clip/@tcFormat") == "DF")
    }
    @Test
    func testEscapingAndPercentEncodedFileURL() throws {
        let label = "Zażółć <&> \"apostrof'\" 🎬"
        let plan = try ConversionPlanner().plan(project: testProject([LogSegment(start: 0, end: 1, name: label)]),
            media: testMedia(), options: ExportOptions(eventName: "Event <&>"))
        let xml = try document(plan)
        #expect(try value(xml, "//keyword/@value") == label)
        #expect(try value(xml, "/fcpxml/event/@name") == "Event <&>")
        let mediaURL = try value(xml, "//media-rep/@src")
        #expect(URL(string: mediaURL) == plan.media.url)
        #expect(mediaURL.contains("%23"))
        #expect(!(mediaURL.contains(" ")))
        #expect(try value(xml, "/fcpxml/event/asset-clip/@name") == "Film & Łódź.MP4")
    }
    @Test
    func testDuplicateKeywordNamesCreateOneCollection() throws {
        let plan = try ConversionPlanner().plan(project: testProject([
            LogSegment(start: 0, end: 1, name: "Same"), LogSegment(start: 1, end: 2, name: "Same")
        ]), media: testMedia(audio: nil), options: ExportOptions())
        let xml = try document(plan)
        #expect(try nodes(xml, "//keyword").count == 2)
        #expect(try nodes(xml, "//keyword-collection").count == 1)
        #expect(try nodes(xml, "//resources/asset/@hasAudio").isEmpty)
    }
    @Test(.enabled(if: FileManager.default.fileExists(atPath: appleDTDURL.path), "Brak DTD Apple 1.9; ustaw FCPXML_DTD."))
    func testDocumentsValidateAgainstOfficialAppleDTDWhenAvailable() throws {
        let dtdURL = appleDTDURL
        for (stringout, name) in [(false, nil), (true, nil),
                                  (false, "  Example — Łódź & <dzień> \"1\" 'żółć', 🎬  "),
                                  (true, "  Example — Łódź & <dzień> \"1\" 'żółć', 🎬  ")] as [(Bool, String?)] {
            let plan = try ConversionPlanner().plan(project: fixtureProject(), media: testMedia(sourceStartFrame: 2457699),
                                                    options: ExportOptions(eventName: name, includeStringout: stringout))
            let xmlURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".fcpxml")
            defer { try? FileManager.default.removeItem(at: xmlURL) }
            try FCPXMLExporter().export(plan).write(to: xmlURL)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xmllint")
            // libxml requires a percent-encoded URL for DTD paths containing spaces.
            process.arguments = ["--nonet", "--noout", "--dtdvalid", dtdURL.absoluteString, xmlURL.path]
            let diagnostics = Pipe()
            process.standardError = diagnostics
            try process.run()
            let errorData = diagnostics.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let message = String(decoding: errorData, as: UTF8.self)
            #expect(process.terminationStatus == 0, "DTD validation: \(message)")
        }
    }
    private func document(_ plan: ConversionPlan) throws -> XMLDocument {
        try XMLDocument(data: FCPXMLExporter().export(plan), options: [.nodeLoadExternalEntitiesNever])
    }
    private func nodes(_ xml: XMLDocument, _ path: String) throws -> [XMLNode] { try xml.nodes(forXPath: path) }
    private func value(_ xml: XMLDocument, _ path: String) throws -> String {
        try #require(nodes(xml, path).first?.stringValue)
    }
}

private var appleDTDURL: URL {
    ProcessInfo.processInfo.environment["FCPXML_DTD"].map { URL(fileURLWithPath: $0) }
        ?? URL(fileURLWithPath: "/Applications/Final Cut Pro Creator Studio.app/Contents/Frameworks/Interchange.framework/Versions/A/Resources/FCPXMLv1_9.dtd")
}
