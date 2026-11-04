import Testing
import Foundation
import VideoLoggerCore
@testable import VideoLoggerLocalization

struct LocalizationTests {
    @Test(arguments: [
        (["pl-PL", "en"], "pl"), (["en-GB", "pl"], "en"),
        (["de-DE"], "en"), (["de", "pl", "en"], "pl"),
        (["de", "en", "pl"], "en"), (["fr", "de"], "en"), ([], "en")
    ])
    func nativeLanguageNegotiation(preferences: [String], expected: String) {
        let strings = LocalizedStrings(bundle: AppLocalization.resourceBundle, preferences: preferences)
        #expect(strings.language == expected)
        #expect(strings.text("Remove from List") == (expected == "pl" ? "Usuń z listy" : "Remove from List"))
    }

    @Test
    func nativePerAppPreferenceUsesCompleteOverrideArray() {
        // This is the same effective ordered array Foundation receives for a per-app override.
        // A real defaults-domain/launch check is run separately; no global test mutation here.
        let overridden = LocalizedStrings(bundle: AppLocalization.resourceBundle, preferences: ["en", "pl"])
        #expect(overridden.language == "en")
        let overriddenPolish = LocalizedStrings(bundle: AppLocalization.resourceBundle, preferences: ["pl", "de"])
        #expect(overriddenPolish.language == "pl")
    }

    @Test
    func missingPolishTranslationFallsBackToEnglish() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        for language in ["en", "pl"] {
            let folder = root.appendingPathComponent(language + ".lproj")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let text = language == "en" ? "\"English only\" = \"English fallback\";\n\"Shared\" = \"Shared\";" : "\"Shared\" = \"Wspólny\";"
            try Data(text.utf8).write(to: folder.appendingPathComponent("Localizable.strings"))
        }
        let bundle = try #require(Bundle(url: root))
        let strings = LocalizedStrings(bundle: bundle, preferences: ["pl"])
        #expect(strings.text("Shared") == "Wspólny")
        #expect(strings.text("English only") == "English fallback")
        #expect(strings.text("Unknown technical key") == "Unknown technical key")
    }

    @Test
    func catalogIsCompleteAndFormatsMatch() throws {
        let english = try table("en"), polish = try table("pl")
        #expect(english.count == 168 && polish.count == english.count)
        #expect(Set(english.keys) == Set(polish.keys))
        let regex = try NSRegularExpression(pattern: "%[0-9]+\\$@")
        func placeholders(_ text: String) -> [String] {
            regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range) }
        }
        for (key, value) in english {
            #expect(placeholders(value) == placeholders(try #require(polish[key])), "Format mismatch: \(key)")
            #expect(!value.isEmpty)
            #expect(value.range(of: "[ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]", options: .regularExpression) == nil, "Polish in English catalog: \(key)")
        }
        #expect(AppLocalization.resourceBundle.developmentLocalization == "en")
        #expect(Set(AppLocalization.resourceBundle.localizations).isSuperset(of: ["en", "pl"]))
    }

    @Test
    func formattingPreservesPolishUnicodeAndUserNames() {
        let name = "Zażółć & <film> 100% — Łódź.MOV"
        for language in ["en", "pl"] {
            let strings = LocalizedStrings(bundle: AppLocalization.resourceBundle, preferences: [language])
            let result = strings.format("Missing media: %1$@", [name])
            #expect(result.hasSuffix(name))
            #expect(!result.contains("%1$@"))
        }
    }

    @Test
    func userContentIsNeverLocalizedOrRenamed() throws {
        let name = "Remove from List.MOV", label = "Select segments in the list — Żółć"
        let data = try JSONSerialization.data(withJSONObject: ["version": 2, "mediaFileName": name,
            "cutSegments": [["start": 1, "end": 2, "name": label]]])
        let project = try LosslessCutImporter().parse(data, sourceURL: URL(fileURLWithPath: "/fixture/test.llc"))
        let media = MediaMetadata(url: URL(fileURLWithPath: "/fixture/" + name), width: 1920, height: 1080,
            clock: try FrameClock(numerator: 1, denominator: 25), frameCount: 100)
        let plan = try ConversionPlanner().plan(project: project, media: media, options: ExportOptions(eventName: "Clear List"))
        let xml = try XMLDocument(data: FCPXMLExporter().export(plan))
        #expect(try xml.nodes(forXPath: "//asset/@name").first?.stringValue == name)
        #expect(try xml.nodes(forXPath: "//keyword/@value").first?.stringValue == label)
        #expect(try xml.nodes(forXPath: "//event/@name").first?.stringValue == "Clear List")
    }

    private func table(_ language: String) throws -> [String: String] {
        let url = try #require(AppLocalization.resourceBundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: language + ".lproj"))
        let data = try Data(contentsOf: url)
        if let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] { return dictionary }
        let wrapped = Data(("{" + String(decoding: data, as: UTF8.self) + "}").utf8)
        return try #require(PropertyListSerialization.propertyList(from: wrapped, format: nil) as? [String: String])
    }
}
