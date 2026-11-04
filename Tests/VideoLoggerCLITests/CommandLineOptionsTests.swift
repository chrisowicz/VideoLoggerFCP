import Testing
import Foundation
import VideoLoggerCore
@testable import VideoLoggerCLI

struct CommandLineOptionsTests {
    @Test(arguments: [false, true])
    func testEventNameAndDefaultOutputForBothVariants(stringout: Bool) throws {
        let name = "  Example — Łódź & <dzień> \"1\" 'żółć', 🎬  "
        var args = ["/example/day-01/Camera_0001-proj.llc", "--event-name", name]
        if stringout { args.append("--stringout") }
        let command = try CommandLineOptions(args)
        #expect(command.options.eventName == name)
        let suffix = stringout ? "-stringout" : ""
        #expect(command.outputURL.path == "/example/day-01/Camera_0001-proj\(suffix).fcpxml")
        let project = LoggingProject(sourceURL: command.source, mediaFileName: "Camera_0001.MP4", segments: [
            LogSegment(start: 1, end: 2, name: "Oryginalny segment żółć & <test>")
        ])
        let media = MediaMetadata(url: URL(fileURLWithPath: "/example/day-01/Camera_0001.MP4"),
                                  width: 1920, height: 1080, clock: try FrameClock(numerator: 1, denominator: 25), frameCount: 250)
        let plan = try ConversionPlanner().plan(project: project, media: media, options: command.options)
        let xml = try XMLDocument(data: FCPXMLExporter().export(plan), options: [.nodeLoadExternalEntitiesNever])
        #expect(try xml.nodes(forXPath: "/fcpxml/event/@name").first?.stringValue == name)
        #expect(try xml.nodes(forXPath: "/fcpxml/resources/asset/@name").first?.stringValue == "Camera_0001.MP4")
        #expect(try xml.nodes(forXPath: "/fcpxml/event/asset-clip/keyword/@value").first?.stringValue == project.segments[0].name)
        #expect(try xml.nodes(forXPath: "/fcpxml/event/project").count == (stringout ? 1 : 0))
    }

    @Test
    func testLegacyEventOptionRemainsEquivalent() throws {
        let old = try CommandLineOptions(["/fixture/project.llc", "--event", "Łódź & dzień"])
        let new = try CommandLineOptions(["/fixture/project.llc", "--event-name", "Łódź & dzień"])
        #expect(old.options.eventName == new.options.eventName)
        #expect(old.outputURL == new.outputURL)
    }

    @Test(arguments: [false, true])
    func testWithoutEventNamePreservesDefault(stringout: Bool) throws {
        let command = try CommandLineOptions(["/fixture/Film żółć-proj.llc"] + (stringout ? ["--stringout"] : []))
        #expect(command.options.eventName == nil)
        let project = LoggingProject(sourceURL: command.source, mediaFileName: "Film żółć.MP4",
                                     segments: [LogSegment(start: 0, end: 1, name: "Segment")])
        let media = MediaMetadata(url: URL(fileURLWithPath: "/fixture/Film żółć.MP4"), width: 1920, height: 1080,
                                  clock: try FrameClock(numerator: 1, denominator: 25), frameCount: 250)
        let plan = try ConversionPlanner().plan(project: project, media: media, options: command.options)
        #expect(plan.eventName == "Film żółć-proj")
        let xml = try XMLDocument(data: FCPXMLExporter().export(plan))
        #expect(try xml.nodes(forXPath: "/fcpxml/event/@name").first?.stringValue == "Film żółć-proj")
    }

    @Test(arguments: [false, true])
    func testExplicitOutputRemainsExact(stringout: Bool) throws {
        let command = try CommandLineOptions(["/fixture/source.llc", "--output", "/chosen/Łódź & wynik.fcpxml"]
                                             + (stringout ? ["--stringout"] : []))
        #expect(command.outputURL.path == "/chosen/Łódź & wynik.fcpxml")
        let relative = try CommandLineOptions(["source.llc", "--output", "chosen.fcpxml"])
        #expect(relative.outputURL == URL(fileURLWithPath: "chosen.fcpxml").standardizedFileURL)
    }

    @Test(arguments: [
        ["--event-name"],
        ["--event-name", "--stringout"],
        ["--event-name", "A", "--event-name", "B"],
        ["--event", "A", "--event-name", "B"],
        ["--event-name", "A", "--event", "B"],
        ["another.llc"],
    ])
    func testInvalidOrAmbiguousArgumentsAreRejected(arguments: [String]) {
        #expect(throws: (any Error).self) { try CommandLineOptions(["source.llc"] + arguments) }
    }
}
