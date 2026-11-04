import Testing
import Foundation
import VideoLoggerTestSupport
@testable import VideoLoggerCore

struct ParserTests {
    @Test
    func testSyntheticFixturePreservesNamesAndTimes() throws {
        let project = try fixtureProject()
        #expect(project.mediaFileName == "Sample_A.MP4")
        #expect(project.segments == [
            LogSegment(start: 1.25, end: 4.5, name: "Opening"),
            LogSegment(start: 7, end: 12, name: "Interview"),
            LogSegment(start: 20.25, end: 27.5, name: "Wide shot"),
            LogSegment(start: 35, end: 42, name: "Closing"),
        ])
    }
    @Test
    func testJSON5AndOptionalFields() throws {
        let project = try parse("""
        { // comment
          version: 0x2, mediaFileName: 'film.MP4',
          cutSegments: [ /* comment */
            { start: +.5, end: 1., name: 'Zażółć <&> "test"', selected: false, },
            { start: 2, end: 3, tags: { unknown: 'ignored' }, },
          ],
        }
        """)
        #expect(project.segments[0].name == "Zażółć <&> \"test\"")
        #expect(!(project.segments[0].selected))
        #expect(project.segments[1].name == "Segment 2")
        #expect(project.segments[1].selected)
    }
    @Test
    func testRejectsInvalidSchemasAndUnsupportedVersions() {
        for text in ["not JSON", "{}", "{version:1,mediaFileName:'a.MP4',cutSegments:[]}",
                     "{version:2,mediaFileName:'a.MP4',cutSegments:[]}",
                     "{version:2,mediaFileName:7,cutSegments:[]}"] {
            #expect(throws: (any Error).self) { try parse(text) }
        }
    }
    @Test
    func testRejectsInvalidOrNonFiniteTimes() {
        for segment in ["{start:-1,end:2}", "{start:2,end:2}", "{start:3,end:2}",
                        "{start:NaN,end:2}", "{start:0,end:Infinity}", "{end:2}",
                        "{start:'1',end:2}", "{start:0,end:2,selected:'true'}"] {
            #expect(throws: (any Error).self) { try parse(projectText(segment)) }
        }
    }
    @Test
    func testMarkerIsNotSilentlyExtendedToEndOfMedia() {
        do {
            _ = try parse(projectText("{start:1,name:'Marker'}"))
            Issue.record("Marker should fail")
        } catch { #expect(error.localizedDescription.contains("marker")) }
    }
    @Test
    func testRejectsUnsafeMediaPaths() {
        for name in ["../a.MP4", "/a.MP4", "folder/a.MP4", "C:\\\\a.MP4", "..", ""] {
            #expect(throws: (any Error).self) { try parse("{version:2,mediaFileName:'\(name)',cutSegments:[{start:0,end:1}]}") }
        }
    }
    @Test
    func testRejectsLabelsThatCannotBePreservedAsSingleKeywords() {
        for name in ["", " ", "a,b", "line\\nnext", "bad\\u0001name"] {
            #expect(throws: (any Error).self) { try parse(projectText("{start:0,end:1,name:'\(name)'}")) }
        }
    }
    private func projectText(_ segment: String) -> String {
        "{version:2,mediaFileName:'a.MP4',cutSegments:[\(segment)]}"
    }
    private func parse(_ text: String) throws -> LoggingProject {
        try LosslessCutImporter().parse(Data(text.utf8), sourceURL: URL(fileURLWithPath: "/fixture/test.llc"))
    }
}

func fixtureProject() throws -> LoggingProject {
    let url = try FixtureResources.project("four-segments")
    return try LosslessCutImporter().parse(Data(contentsOf: url), sourceURL: url)
}
func testMedia(clock: FrameClock? = nil, frameCount: Int64 = 30000,
               sourceStartFrame: Int64 = 0, audio: AudioMetadata? = AudioMetadata(channels: 2, sampleRate: 48000)) throws -> MediaMetadata {
    MediaMetadata(url: URL(fileURLWithPath: "/media/Zażółć & film #1.MP4"), width: 3840, height: 3840,
                  clock: try clock ?? FrameClock(numerator: 1001, denominator: 30000), frameCount: frameCount,
                  audio: audio, colorSpace: "1-1-1 (Rec. 709)", sourceStartFrame: sourceStartFrame,
                  timecodeFormat: sourceStartFrame == 0 ? "NDF" : "DF")
}
func testProject(_ segments: [LogSegment]) -> LoggingProject {
    LoggingProject(sourceURL: URL(fileURLWithPath: "/fixture/project.llc"), mediaFileName: "Film & Łódź.MP4", segments: segments)
}
