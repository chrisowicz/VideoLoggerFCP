import Testing
import Foundation
import VideoLoggerCore
@testable import VideoLoggerDragDrop

struct ListManagementTests {
    @Test
    func removeOneAndManyOnlyChangesSessionAndRefreshDoesNotRestore() async throws {
        let fixture = try ListFixture(); defer { fixture.cleanup() }
        try fixture.populate()
        let snapshot = try fixture.snapshot()
        let scan = try await LibraryScanner().scan([fixture.root])
        var library = RecordingLibrary(); library.merge(scan)
        let ids = library.recordings.map(\.id)
        library.remove(ids: [ids[0]])
        #expect(library.recordings.count == 2)
        #expect(library.segmentRows(for: [ids[0]]).isEmpty)
        library.merge(try await LibraryScanner().scan([fixture.root]))
        #expect(library.recordings.count == 2)
        library.remove(ids: Set(ids.dropFirst()))
        library.merge(scan)
        #expect(library.recordings.isEmpty)
        #expect(try fixture.snapshot() == snapshot)
    }

    @Test
    func clearKeepsFilesAndExplicitFileRestoresOnlyThatRecording() async throws {
        let fixture = try ListFixture(); defer { fixture.cleanup() }
        try fixture.populate(); let snapshot = try fixture.snapshot()
        let scan = try await LibraryScanner().scan([fixture.root])
        var library = RecordingLibrary(); library.merge(scan); library.clear(); library.merge(scan)
        #expect(library.recordings.isEmpty && library.issues.isEmpty)
        library.merge(scan, restoringFrom: [fixture.root.appendingPathComponent("A.MOV")])
        #expect(library.recordings.map(\.name) == ["A.MOV"])
        library.merge(scan)
        #expect(library.recordings.count == 1)
        library.merge(scan, restoringFrom: [fixture.root.appendingPathComponent("B.llc")])
        #expect(library.recordings.map(\.name) == ["A.MOV", "B.MP4"])
        library.merge(scan, restoringFrom: [fixture.root])
        #expect(library.recordings.count == 3)
        #expect(try fixture.snapshot() == snapshot)
    }

    @Test
    func unrelatedExplicitFolderDoesNotRestoreExcludedRecordings() async throws {
        let fixture = try ListFixture(), other = try ListFixture(); defer { fixture.cleanup(); other.cleanup() }
        try fixture.populate()
        var library = RecordingLibrary(); library.merge(try await LibraryScanner().scan([fixture.root])); library.clear()
        let scan = try await LibraryScanner().scan([fixture.root, other.root])
        library.merge(scan, restoringFrom: [other.root])
        #expect(library.recordings.isEmpty)
    }

    @Test
    func removedRelinkDoesNotReturnThroughOriginalOrLocatedPaths() async throws {
        let fixture = try ListFixture(); defer { fixture.cleanup() }
        let llc = try fixture.llc("selection.llc", media: "Missing.MOV")
        let located = try fixture.file("Original.MOV")
        var library = RecordingLibrary(); library.merge(try await LibraryScanner().scan([llc, located]))
        let id = try #require(library.recordings.first { $0.hasLLC }?.id)
        try library.locateMedia(for: id, at: located)
        library.remove(ids: [id])
        library.merge(try await LibraryScanner().scan([llc, located]))
        #expect(library.recordings.isEmpty)
        library.merge(try await LibraryScanner().scan([llc, located]), restoringFrom: [located])
        #expect(library.recordings.count == 1)
    }

    @Test
    func everyFilterAndUnicodeSearchArePureProjections() async throws {
        let fixture = try ListFixture(); defer { fixture.cleanup() }
        try fixture.populate(); let snapshot = try fixture.snapshot()
        var library = RecordingLibrary(); library.merge(try await LibraryScanner().scan([fixture.root]))
        #expect(library.visibleRecordings().count == 3)
        #expect(library.visibleRecordings(filter: .analyzed).map(\.name) == ["A.MOV", "B.MP4"])
        #expect(library.visibleRecordings(filter: .withoutLLC).map(\.name) == ["Łódź & dzień.MOV"])
        #expect(library.visibleRecordings(filter: .missingMedia).map(\.name) == ["B.MP4"])
        #expect(library.visibleRecordings(search: "łódź").map(\.name) == ["Łódź & dzień.MOV"])
        #expect(library.visibleRecordings(filter: .analyzed, search: "mov").map(\.name) == ["A.MOV"])
        #expect(library.visibleRecordings(filter: .missingMedia, search: "A").isEmpty)
        #expect(library.recordings.count == 3 && library.segmentRows(for: Set(library.recordings.map(\.id))).count == 2)
        #expect(try fixture.snapshot() == snapshot)
    }

    @Test
    func movAndMP4WithSameBasenameRemainSeparateAndFindTheirSidecars() async throws {
        let fixture = try ListFixture(); defer { fixture.cleanup() }
        let mov = try fixture.file("IMG_0001.MOV"), mp4 = try fixture.file("IMG_0001.MP4")
        _ = try fixture.llc("phone selection.llc", media: mov.lastPathComponent)
        _ = try fixture.llc("camera selection.llc", media: mp4.lastPathComponent)
        _ = try fixture.file("unsupported.png")
        let scan = try await LibraryScanner().scan([mov, mp4])
        #expect(scan.recordings.count == 2 && scan.recordings.allSatisfy { $0.hasLLC })
        let recursive = try await LibraryScanner().scan([fixture.root])
        #expect(recursive.recordings.count == 2 && recursive.issues.isEmpty)
    }

    @Test
    func movSourceKeepsOriginalURIInBothPayloadVersions() async throws {
        let fixture = try ListFixture(); defer { fixture.cleanup() }
        let mov = try fixture.file("iPhone — Łódź & 01.MOV")
        _ = try fixture.llc("phone.llc", media: mov.lastPathComponent)
        let snapshot = try fixture.snapshot()
        var library = RecordingLibrary(); library.merge(try await LibraryScanner().scan([fixture.root]))
        let rows = library.segmentRows(for: Set(library.recordings.map(\.id)))
        let ready = try await LibraryPreparer(probe: PhoneProbe()).prepare(rows)
        for type in [FCPXMLDragPayload.currentType, FCPXMLDragPayload.legacyType] {
            let xml = try XMLDocument(data: #require(ready.payload.data(for: type)))
            #expect(try xml.nodes(forXPath: "//media-rep/@src").first?.stringValue == mov.absoluteString)
            #expect(try xml.nodes(forXPath: "/fcpxml/asset-clip/@name").first?.stringValue == "Phone selection")
            #expect(try xml.nodes(forXPath: "/fcpxml/resources/format/@frameDuration").first?.stringValue == "1001/60000s")
            #expect(try xml.nodes(forXPath: "//project | //sequence").isEmpty)
        }
        #expect(try fixture.snapshot() == snapshot)
    }
}

private struct PhoneProbe: MediaProbing {
    func inspect(_ url: URL) async throws -> MediaMetadata {
        MediaMetadata(url: url, width: 1080, height: 1920, clock: try FrameClock(numerator: 1001, denominator: 60000),
                      frameCount: 600, audio: AudioMetadata(channels: 2, sampleRate: 48000), rotationDegrees: 90)
    }
}
private struct ListFixture {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
    @discardableResult func file(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data("Test placeholder, not a real video".utf8).write(to: url); return url
    }
    @discardableResult func llc(_ name: String, media: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try JSONSerialization.data(withJSONObject: ["version": 2, "mediaFileName": media,
            "cutSegments": [["start": 1, "end": 2, "name": "Phone selection"]]]).write(to: url)
        return url
    }
    func populate() throws {
        try file("A.MOV"); try llc("A.llc", media: "A.MOV")
        try llc("B.llc", media: "B.MP4")
        try file("Łódź & dzień.MOV")
    }
    func snapshot() throws -> [String: Data] {
        let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        return try Dictionary(uniqueKeysWithValues: urls.map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }
}
