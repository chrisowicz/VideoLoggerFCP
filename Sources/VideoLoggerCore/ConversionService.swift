import VideoLoggerLocalization
import Foundation

public struct ConversionResult: Sendable {
    public let document: Data
    public let plan: ConversionPlan
    public let warnings: [String]
}

public struct ConversionService: Sendable {
    private let importer: any ProjectImporting
    private let probe: any MediaProbing
    private let exporter: any ProjectExporting
    public init(importer: any ProjectImporting = LosslessCutImporter(),
                probe: any MediaProbing = AVFoundationMediaProbe(),
                exporter: any ProjectExporting = FCPXMLExporter()) {
        self.importer = importer; self.probe = probe; self.exporter = exporter
    }
    public func convert(source: URL, mediaOverride: URL? = nil,
                        options: ExportOptions = ExportOptions()) async throws -> ConversionResult {
        try FileAccess.requireReadableFile(source)
        guard source.pathExtension.lowercased() == "llc" else { throw ConversionError(L("The source must be an .llc file.")) }
        let project = try importer.parse(Data(contentsOf: source), sourceURL: source)
        let mediaURL = (mediaOverride ?? source.deletingLastPathComponent().appendingPathComponent(project.mediaFileName))
            .standardizedFileURL
        try FileAccess.requireReadableFile(mediaURL)
        let metadata = try await probe.inspect(mediaURL)
        let plan = try ConversionPlanner().plan(project: project, media: metadata, options: options)
        let sourceDirectory = source.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        let mediaDirectory = metadata.url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        var warnings: [String] = []
        if sourceDirectory != mediaDirectory {
            warnings.append(LF("LLC and media are in different folders. LLC: %1$@; media: %2$@. The default export location is the LLC folder.", String(describing: sourceDirectory.path), String(describing: mediaDirectory.path)))
        }
        return ConversionResult(document: try exporter.export(plan), plan: plan, warnings: warnings)
    }
}

public enum FileAccess {
    public static func requireReadableFile(_ url: URL) throws {
        guard url.isFileURL else { throw ConversionError(L("Only local files are supported.")) }
        let attributes: URLResourceValues
        do { attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey]) }
        catch { throw ConversionError(LF("Cannot read file: %1$@. %2$@", String(describing: url.path), String(describing: error.localizedDescription))) }
        guard attributes.isRegularFile == true, attributes.isReadable == true else {
            throw ConversionError(LF("The path is not a readable regular file: %1$@", String(describing: url.path)))
        }
    }
}

public enum SafeOutputWriter {
    public static func defaultOutput(for source: URL, includeStringout: Bool = false) -> URL {
        let base = source.deletingPathExtension()
        let name = base.lastPathComponent + (includeStringout ? "-stringout" : "") + ".fcpxml"
        return base.deletingLastPathComponent().appendingPathComponent(name)
    }
    public static func write(_ data: Data, to output: URL, protecting sources: [URL]) throws {
        guard output.isFileURL, output.pathExtension.lowercased() == "fcpxml" else {
            throw ConversionError(L("The output must be a local .fcpxml file."))
        }
        let destination = output.standardizedFileURL.resolvingSymlinksInPath()
        guard !sources.contains(where: { $0.standardizedFileURL.resolvingSymlinksInPath() == destination }) else {
            throw ConversionError(L("The output cannot replace a source file."))
        }
        // O_EXCL semantics: existing files (including symlinks/hard links) are never overwritten.
        do { try data.write(to: output, options: [.withoutOverwriting]) }
        catch { throw ConversionError(LF("Cannot create %1$@. Existing output is never overwritten. %2$@", String(describing: output.path), String(describing: error.localizedDescription))) }
    }
}
