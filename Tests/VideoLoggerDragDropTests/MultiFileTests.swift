import VideoLoggerLocalization
import Testing
import Foundation
import AppKit
import VideoLoggerTestSupport
import VideoLoggerCore
@testable import VideoLoggerDragDrop


struct MultiFileTests {
    @Test
    func twoSyntheticProjectsParseWithoutMedia() async throws {
        let urls = try ["four-segments", "three-segments"].map { try FixtureResources.project($0) }
        let before = try urls.map { try Data(contentsOf: $0) }
        var library = RecordingLibrary(); library.merge(try await LibraryScanner().scan(urls))
        #expect(library.recordings.count == 2)
        #expect(library.recordings.map(\.segmentCount) == [4, 3])
        let rows = library.segmentRows(for: Set(library.recordings.map(\.id)))
        #expect(rows.count == 7)
        #expect(rows.suffix(3).map(\.segment.name) == ["First", "Second", "Third"])
        #expect(try urls.map { try Data(contentsOf: $0) } == before)
        for record in library.recordings where !LibraryScanner.isReadableMedia(record.expectedMediaURL) {
            #expect(record.status == L("Missing Media"))
        }
    }

    @Test
    func singleLLCFindsItsMediaWithoutVideoProbe() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let movie = try fixture.movie("A.MP4")
        let llc = try fixture.llc("arbitrary notes.llc", media: movie.lastPathComponent)
        let result = try await LibraryScanner().scan([llc])
        #expect(result.recordings.count == 1 && result.issues.isEmpty)
        #expect(result.recordings[0].mediaURL == movie)
        #expect(result.recordings[0].status == L("Analyzed"))
    }

    @Test
    func looseMP4FindsNonConventionalSidecarAndIgnoresOtherProjects() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let movie = try fixture.movie("A.MP4")
        _ = try fixture.llc("notes not filename-proj.llc", media: "A.MP4")
        _ = try fixture.llc("other.llc", media: "B.MP4")
        let result = try await LibraryScanner().scan([movie])
        #expect(result.recordings.count == 1)
        #expect(result.recordings[0].sources.count == 1)
        #expect(result.recordings[0].name == "A.MP4")
    }

    @Test
    func mediaWithoutLLCIsNormal() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let movie = try fixture.movie("A.mp4")
        let result = try await LibraryScanner().scan([movie])
        #expect(result.issues.isEmpty)
        #expect(result.recordings[0].status == L("No LLC"))
        #expect(result.recordings[0].segmentCount == 0)
    }

    @Test
    func recursiveFolderHas17MoviesAndOnly2Selections() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let subfolder = try fixture.directory("podfolder/Łódź & dzień")
        for index in 1...17 { _ = try fixture.movie(String(format: "Take %02d.MP4", index), folder: index % 2 == 0 ? subfolder : nil) }
        _ = try fixture.llc("first.llc", media: "Take 01.MP4")
        _ = try fixture.llc("second.llc", media: "Take 02.MP4", folder: subfolder)
        let result = try await LibraryScanner().scan([fixture.root])
        #expect(result.recordings.count == 17)
        #expect(result.recordings.filter { $0.status == L("Analyzed") }.count == 2)
        #expect(result.recordings.filter { $0.status == L("No LLC") }.count == 15)
        #expect(result.issues.isEmpty)
        var library = RecordingLibrary()
        for _ in 0..<3 { library.merge(result) }
        #expect(library.recordings.count == 17)
        #expect(library.recordings.reduce(0) { $0 + $1.sources.count } == 2)
    }

    @Test
    func multipleLLCsDeduplicateAndRetainMissingSegments() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let first = try fixture.llc("first.llc", media: "A.MP4")
        let second = try fixture.llc("second.llc", media: "B.MP4")
        var library = RecordingLibrary()
        library.merge(try await LibraryScanner().scan([first, second, first, fixture.root]))
        #expect(library.recordings.count == 2)
        #expect(library.recordings.allSatisfy { $0.status == L("Missing Media") })
        #expect(library.segmentRows(for: Set(library.recordings.map(\.id))).count == 2)
    }

    @Test
    func invalidLLCIsReportedWithoutLosingValidMediaAndCanBeFixed() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        _ = try fixture.movie("A.MP4")
        let bad = fixture.root.appendingPathComponent("bad.llc")
        try Data("{version:2,cutSegments:'wrong'}".utf8).write(to: bad)
        var library = RecordingLibrary()
        library.merge(try await LibraryScanner().scan([fixture.root]))
        #expect(library.issues.count == 1)
        #expect(library.recordings[0].status == L("No LLC"))
        _ = try fixture.llc("bad.llc", media: "A.MP4")
        library.merge(try await LibraryScanner().scan([fixture.root]))
        #expect(library.issues.isEmpty && library.recordings.count == 1)
        #expect(library.recordings[0].status == L("Analyzed"))
    }

    @Test
    func unicodeSpacesAndNFCPathsDoNotDuplicateEntries() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let movie = try fixture.movie("Łódź & dzień #1.MP4")
        _ = try fixture.llc("opisy 'żółć'.llc", media: movie.lastPathComponent.decomposedStringWithCanonicalMapping,
                                segments: [(1, 2, "Zażółć <&> \"' 🎬")])
        var library = RecordingLibrary()
        library.merge(try await LibraryScanner().scan([fixture.root, movie]))
        library.merge(try await LibraryScanner().scan([URL(fileURLWithPath: movie.path.decomposedStringWithCanonicalMapping)]))
        #expect(library.recordings.count == 1)
        #expect(library.recordings[0].sources.count == 1)
        #expect(library.segmentRows(for: Set(library.recordings.map(\.id)))[0].segment.name == "Zażółć <&> \"' 🎬")
    }

    @Test
    func nestedSymlinksAreSkippedIncludingOutsideTargetsAndCycles() async throws {
        let fixture = try Fixture(), outside = try Fixture(); defer { fixture.cleanup(); outside.cleanup() }
        _ = try outside.movie("Outside.MP4")
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("outside"), withDestinationURL: outside.root)
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("cycle"), withDestinationURL: fixture.root)
        let result = try await LibraryScanner().scan([fixture.root])
        #expect(result.recordings.isEmpty && result.issues.count == 2)
        let explicit = try await LibraryScanner().scan([fixture.root.appendingPathComponent("outside")])
        #expect(explicit.recordings.count == 1)
    }

    @Test
    func scanCanBeCancelled() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        for index in 0..<100 { _ = try fixture.movie("Take\(index).MP4") }
        let task = Task { try await LibraryScanner().scan([fixture.root]) }
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
    }

    @Test
    func missingMediaBlocksWholeSelectionBeforeAnyProbe() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        _ = try fixture.movie("A.MP4"); _ = try fixture.llc("A.llc", media: "A.MP4")
        _ = try fixture.llc("B.llc", media: "B.MP4")
        var library = RecordingLibrary(); library.merge(try await LibraryScanner().scan([fixture.root]))
        let rows = library.segmentRows(for: Set(library.recordings.map(\.id)))
        let probe = CountingProbe(); let preparer = LibraryPreparer(probe: probe)
        do { _ = try await preparer.prepare(rows); Issue.record("Missing MP4 should block drag") }
        catch { #expect(error.localizedDescription.contains("B.MP4")) }
        #expect(await probe.total() == 0)
    }

    @Test
    func relinkMergesAlreadyImportedMovieAndDoesNotEditLLC() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let llc = try fixture.llc("A.llc", media: "Original.MP4")
        let contents = try Data(contentsOf: llc)
        let located = try fixture.movie("Original.MP4", folder: fixture.directory("originals"))
        var library = RecordingLibrary(); library.merge(try await LibraryScanner().scan([llc, located]))
        #expect(library.recordings.count == 2)
        let id = try #require(library.recordings.first(where: { !$0.sources.isEmpty })?.id)
        try library.locateMedia(for: id, at: located)
        #expect(library.recordings.count == 1 && library.recordings[0].sources.count == 1)
        library.merge(try await LibraryScanner().scan([llc, located]))
        #expect(library.recordings.count == 1 && library.recordings[0].mediaURL == located)
        #expect(try Data(contentsOf: llc) == contents)
    }

    @Test
    func preparationIsLazyCachedAndDetectsChangedFiles() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let movie = try fixture.movie("A.MP4"); _ = try fixture.llc("A.llc", media: "A.MP4")
        _ = try fixture.movie("B.MP4"); _ = try fixture.llc("B.llc", media: "B.MP4")
        let probe = CountingProbe(); let preparer = LibraryPreparer(probe: probe)
        var library = RecordingLibrary(); library.merge(try await LibraryScanner().scan([fixture.root]))
        #expect(await probe.total() == 0)
        let first = library.segmentRows(for: [try #require(library.recordings.first?.id)])
        let prepared = try await preparer.prepare(first)
        let again = try await preparer.prepare(first)
        #expect(await probe.total() == 1)
        #expect(prepared.payload.data(for: FCPXMLDragPayload.currentType) == again.payload.data(for: FCPXMLDragPayload.currentType))
        try Data("modified synthetic video".utf8).write(to: movie)
        #expect(throws: (any Error).self) { try prepared.validateInputs() }
        _ = try await preparer.prepare(first)
        #expect(await probe.total() == 2)
        try Data("changed LLC".utf8).write(to: first[0].source.url)
        #expect(throws: (any Error).self) { try again.validateInputs() }
    }

    @Test
    func sortedMultipleMediaPayloadHasUniqueResourceReferencesAndNoProject() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        _ = try fixture.movie("A.MP4"); _ = try fixture.movie("B.MP4")
        _ = try fixture.llc("A.llc", media: "A.MP4", segments: [(9, 12, "A late"), (1, 3, "A early")])
        _ = try fixture.llc("B.llc", media: "B.MP4", segments: [(2, 4, "B middle")])
        var library = RecordingLibrary(); library.merge(try await LibraryScanner().scan([fixture.root]))
        let rows = library.segmentRows(for: Set(library.recordings.map(\.id)))
        #expect(rows.map(\.segment.name) == ["A early", "A late", "B middle"])
        let prepared = try await LibraryPreparer(probe: CountingProbe()).prepare(rows)
        for (type, version) in [(FCPXMLDragPayload.currentType, "1_14"), (FCPXMLDragPayload.legacyType, "1_9")] {
            let data = try #require(prepared.payload.data(for: type)); let xml = try XMLDocument(data: data)
            #expect(try xml.nodes(forXPath: "/fcpxml/asset-clip/@name").map(\.stringValue) == ["A early", "A late", "B middle"])
            let ids = try xml.nodes(forXPath: "/fcpxml/resources/*/@id").compactMap(\.stringValue)
            #expect(ids.count == 4 && Set(ids).count == 4)
            let refs = try xml.nodes(forXPath: "//asset-clip/@ref | //asset-clip/@format | //asset/@format").compactMap(\.stringValue)
            #expect(refs.allSatisfy { ids.contains($0) })
            #expect(try xml.nodes(forXPath: "/fcpxml/asset-clip[1]/@start").first?.stringValue == "125/25s")
            #expect(try xml.nodes(forXPath: "//event | //project | //sequence | //library").isEmpty)
            #expect(try xml.nodes(forXPath: "//media-rep/@src").compactMap(\.stringValue).count == 2)
            #expect(xml.rootElement()?.attribute(forName: "version")?.stringValue == version.replacingOccurrences(of: "_", with: "."))
        }
    }

    @Test
    func interleavedSidecarsShareResourcesAndKeepVisibleOrder() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        _ = try fixture.movie("A.MP4")
        _ = try fixture.llc("one.llc", media: "A.MP4", segments: [(9, 10, "late"), (1, 2, "early")])
        _ = try fixture.llc("two.llc", media: "A.MP4", segments: [(5, 6, "middle")])
        var library = RecordingLibrary(); library.merge(try await LibraryScanner().scan([fixture.root]))
        #expect(library.recordings.count == 1 && library.recordings[0].segmentCount == 3)
        let prepared = try await LibraryPreparer(probe: CountingProbe()).prepare(library.segmentRows(for: Set(library.recordings.map(\.id))))
        let xml = try XMLDocument(data: #require(prepared.payload.data(for: FCPXMLDragPayload.currentType)))
        #expect(try xml.nodes(forXPath: "/fcpxml/asset-clip/@name").map(\.stringValue) == ["early", "middle", "late"])
        #expect(try xml.nodes(forXPath: "//resources/asset").count == 1)
    }

    @MainActor @Test
    func finderPasteboardReadsManyFilesAndRejectsNativeOutput() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("pl.videologgerfcp.finder-test." + UUID().uuidString))
        defer { board.clearContents() }
        let urls = [URL(fileURLWithPath: "/folder/Łódź & 1.llc"), URL(fileURLWithPath: "/folder/2.MP4")]
        #expect(board.writeObjects(urls.map { $0 as NSURL }))
        #expect(FinderDropReader.urls(from: board).map(libraryFileID) == urls.map(libraryFileID))
        board.clearContents()
        let item = NSPasteboardItem(); item.setData(Data("XML".utf8), forType: NSPasteboard.PasteboardType(FCPXMLDragPayload.currentType))
        #expect(board.writeObjects([item]))
        #expect(FinderDropReader.urls(from: board).isEmpty)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/Applications/Final Cut Pro Creator Studio.app/Contents/Frameworks/Interchange.framework/Versions/A/Resources/FCPXMLv1_14.dtd"), "Brak DTD Apple."))
    func multipleMediaDocumentsValidateBothDTDs() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        for name in ["A.MP4", "B.MP4"] { _ = try fixture.movie(name); _ = try fixture.llc(name + ".llc", media: name) }
        var library = RecordingLibrary(); library.merge(try await LibraryScanner().scan([fixture.root]))
        let prepared = try await LibraryPreparer(probe: CountingProbe()).prepare(library.segmentRows(for: Set(library.recordings.map(\.id))))
        try validateDTD(#require(prepared.payload.data(for: FCPXMLDragPayload.currentType)), version: "1_14")
        try validateDTD(#require(prepared.payload.data(for: FCPXMLDragPayload.legacyType)), version: "1_9")
    }

    private func validateDTD(_ data: Data, version: String) throws {
        let dtd = URL(fileURLWithPath: "/Applications/Final Cut Pro Creator Studio.app/Contents/Frameworks/Interchange.framework/Versions/A/Resources/FCPXMLv\(version).dtd")
        guard FileManager.default.fileExists(atPath: dtd.path) else { throw ConversionError("Brak DTD Apple.") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".fcpxml")
        try data.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/xmllint")
        process.arguments = ["--nonet", "--noout", "--dtdvalid", dtd.absoluteString, url.path]
        let errors = Pipe(); process.standardError = errors; try process.run()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit(); #expect(process.terminationStatus == 0, "DTD: \(message)")
    }
}

private struct Fixture {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
    func directory(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    func movie(_ name: String, folder: URL? = nil) throws -> URL {
        let url = (folder ?? root).appendingPathComponent(name)
        try Data("synthetic metadata-probe fixture".utf8).write(to: url); return url
    }
    func llc(_ name: String, media: String, folder: URL? = nil, segments: [(Double, Double, String)] = [(1, 3, "Fragment")]) throws -> URL {
        let url = (folder ?? root).appendingPathComponent(name)
        let object: [String: Any] = ["version": 2, "mediaFileName": media, "cutSegments": segments.map { ["start": $0.0, "end": $0.1, "name": $0.2, "selected": true] as [String: Any] }]
        try JSONSerialization.data(withJSONObject: object).write(to: url); return url
    }
}
private actor CountingProbe: MediaProbing {
    private var calls = 0
    func total() -> Int { calls }
    func inspect(_ url: URL) async throws -> MediaMetadata {
        try FileAccess.requireReadableFile(url); calls += 1
        let isA = url.lastPathComponent == "A.MP4"
        return MediaMetadata(url: url, width: isA ? 1920 : 3840, height: isA ? 1080 : 3840,
            clock: try FrameClock(numerator: isA ? 1 : 1001, denominator: isA ? 25 : 30000), frameCount: 100000,
            audio: AudioMetadata(channels: 2, sampleRate: 48000), sourceStartFrame: isA ? 100 : 2457699, timecodeFormat: isA ? "NDF" : "DF")
    }
}
