import Testing
import Foundation
import CoreGraphics
@testable import VideoLoggerCore

struct TimingTests {
    @Test
    func toleratedTimingUsesWallTimeAndHandlesRoundedEndOfFile() throws {
        let source = URL(fileURLWithPath: "/example/phone.llc")
        let media = MediaMetadata(url: URL(fileURLWithPath: "/example/phone.mov"),
                                  width: 1920, height: 1080, clock: try FrameClock(numerator: 1, denominator: 60),
                                  frameCount: 1366, irregularSourceDuration: 22.781666666666666)
        let project = LoggingProject(sourceURL: source, mediaFileName: "phone.mov",
            segments: [LogSegment(start: 9.581892, end: 22.781667, name: "Selection")])
        let plan = try ConversionPlanner().plan(project: project, media: media, options: ExportOptions())
        #expect(plan.ranges[0].start == 575)
        #expect(plan.ranges[0].end == 1366)
        let bad = LoggingProject(sourceURL: source, mediaFileName: "phone.mov",
            segments: [LogSegment(start: 0, end: 22.782, name: "Beyond media")])
        #expect(throws: ConversionError.self) {
            try ConversionPlanner().plan(project: bad, media: media, options: ExportOptions())
        }
    }

    @Test
    func testIntegerAndFractionalFrameClocks() throws {
        let pal = try FrameClock(numerator: 1, denominator: 25)
        #expect(try pal.nearestFrame(seconds: 1) == 25)
        #expect(try pal.nearestFrame(seconds: 0.02) == 1)
        #expect(try pal.time(frames: 26) == "26/25s")
        let ntsc = try FrameClock(numerator: 1001, denominator: 30000)
        #expect(try ntsc.nearestFrame(seconds: 1) == 30)
        #expect(try ntsc.time(frames: 30) == "30030/30000s")
        let ntsc60 = try FrameClock(numerator: 1001, denominator: 60000)
        #expect(try ntsc60.nearestFrame(seconds: 1) == 60)
        #expect(try FrameClock(numerator: 2002, denominator: 60000) == ntsc)
    }
    @Test
    func testInvalidAndOverflowingTimes() throws {
        #expect(throws: (any Error).self) { try FrameClock(numerator: 0, denominator: 30) }
        #expect(throws: (any Error).self) { try FrameClock(numerator: 1, denominator: -1) }
        let clock = try FrameClock(numerator: 1001, denominator: 30000)
        for seconds in [Double.nan, .infinity, -1, Double.greatestFiniteMagnitude] {
            #expect(throws: (any Error).self) { try clock.nearestFrame(seconds: seconds) }
        }
        #expect(throws: (any Error).self) { try clock.time(frames: Int64.max) }
        #expect(throws: (any Error).self) { try clock.time(frames: -1) }
    }
    @Test
    func testSyntheticRangesAtFractionalFrameRate() throws {
        let plan = try ConversionPlanner().plan(project: fixtureProject(), media: testMedia(), options: ExportOptions())
        #expect(plan.ranges.map(\.start) == [37, 210, 607, 1049])
        #expect(plan.ranges.map(\.end) == [135, 360, 824, 1259])
        #expect(plan.ranges.map(\.duration) == [98, 150, 217, 210])
        for (segment, range) in zip(plan.project.segments, plan.ranges) {
            #expect(abs(segment.start - Double(range.start) * plan.media.clock.secondsPerFrame) <= plan.media.clock.secondsPerFrame / 2)
            #expect(abs(segment.end - Double(range.end) * plan.media.clock.secondsPerFrame) <= plan.media.clock.secondsPerFrame / 2)
        }
    }
    @Test
    func testOutOfBoundsAndCollapsedRangesFail() throws {
        let media = try testMedia(clock: FrameClock(numerator: 1, denominator: 25), frameCount: 250)
        for segment in [LogSegment(start: 0, end: 10.1, name: "Too long"),
                        LogSegment(start: 1.001, end: 1.002, name: "Too short"),
                        LogSegment(start: -1, end: 1, name: "Negative")] {
            #expect(throws: (any Error).self) { try ConversionPlanner().plan(project: testProject([segment]), media: media, options: ExportOptions()) }
        }
    }
    @Test
    func testExactEndAndOverlappingRangesAreAllowed() throws {
        let media = try testMedia(clock: FrameClock(numerator: 1, denominator: 25), frameCount: 250)
        let plan = try ConversionPlanner().plan(project: testProject([
            LogSegment(start: 0, end: 10, name: "All"), LogSegment(start: 1, end: 2, name: "Within")
        ]), media: media, options: ExportOptions())
        #expect(plan.ranges[0].end == 250)
    }
    @Test
    func testNoSelectedSegmentsFailsOnlyWithStringout() throws {
        let project = testProject([LogSegment(start: 0, end: 1, name: "A", selected: false)])
        #expect(throws: Never.self) { try ConversionPlanner().plan(project: project, media: testMedia(), options: ExportOptions()) }
        #expect(throws: (any Error).self) { try ConversionPlanner().plan(project: project, media: testMedia(), options: ExportOptions(includeStringout: true)) }
    }
    @Test
    func testMetadataAndEventValidation() throws {
        let project = testProject([LogSegment(start: 0, end: 1, name: "A")])
        #expect(throws: (any Error).self) { try ConversionPlanner().plan(project: project, media: testMedia(frameCount: 0), options: ExportOptions()) }
        #expect(throws: (any Error).self) { try ConversionPlanner().plan(project: project, media: testMedia(), options: ExportOptions(eventName: "")) }
        #expect(throws: (any Error).self) { try ConversionPlanner().plan(project: project, media: testMedia(sourceStartFrame: Int64.max), options: ExportOptions()) }
    }
    @Test
    func testTimecodeBigEndian32And64() throws {
        #expect(try AVFoundationMediaProbe.decodeTimecode(Data([0, 37, 128, 99]), size: 4) == 2457699)
        #expect(try AVFoundationMediaProbe.decodeTimecode(Data([0, 0, 0, 0, 0, 37, 128, 99]), size: 8) == 2457699)
        #expect(throws: (any Error).self) { try AVFoundationMediaProbe.decodeTimecode(Data([255, 255, 255, 255]), size: 4) }
        #expect(throws: (any Error).self) { try AVFoundationMediaProbe.decodeTimecode(Data([0]), size: 4) }
    }
    @Test
    func testMetadataRotationWithoutImageProcessing() throws {
        #expect(try AVFoundationMediaProbe.rotationDegrees(.identity) == 0)
        #expect(try AVFoundationMediaProbe.rotationDegrees(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 3840, ty: 0)) == 90)
        #expect(throws: (any Error).self) { try AVFoundationMediaProbe.rotationDegrees(CGAffineTransform(scaleX: 2, y: 2)) }
        #expect(throws: (any Error).self) { try AVFoundationMediaProbe.rotationDegrees(CGAffineTransform(scaleX: -1, y: 1)) }
    }
}
