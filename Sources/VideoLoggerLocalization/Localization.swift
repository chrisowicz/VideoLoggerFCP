import Foundation

/// Native bundle language negotiation with a per-key English fallback.
/// No app preference is written here; macOS owns the ordered language preferences.
public struct LocalizedStrings: Sendable {
    public let language: String
    private let selected: Bundle
    private let english: Bundle

    public init(bundle: Bundle, preferences: [String]? = nil) {
        let available = ["en", "pl"].filter { bundle.localizations.contains($0) }
        language = Bundle.preferredLocalizations(from: available, forPreferences: preferences).first ?? "en"
        english = bundle.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)) ?? bundle
        selected = bundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? english
    }

    public func text(_ key: String) -> String {
        let fallback = english.localizedString(forKey: key, value: key, table: "Localizable")
        return selected.localizedString(forKey: key, value: fallback, table: "Localizable")
    }

    public func format(_ key: String, _ arguments: [String]) -> String {
        String(format: text(key), locale: Locale(identifier: language), arguments: arguments.map { $0 as CVarArg })
    }
}

private final class LocalizationResourceLocator: NSObject {}

public enum AppLocalization {
    public static let resourceBundle: Bundle = {
        // Resolve relative to the running app/tool; never embed a private build-directory fallback.
        let owner = Bundle(for: LocalizationResourceLocator.self)
        let roots = [Bundle.main.resourceURL, Bundle.main.bundleURL,
                     Bundle.main.executableURL?.deletingLastPathComponent(), owner.resourceURL,
                     owner.bundleURL, owner.bundleURL.deletingLastPathComponent()].compactMap { $0 }
        for root in roots {
            if let bundle = Bundle(url: root.appendingPathComponent("VideoLoggerFCP_VideoLoggerLocalization.bundle")) {
                return bundle
            }
        }
        fatalError("Missing VideoLoggerFCP localization resources. Rebuild or reinstall the complete application.")
    }()
    public static let strings = LocalizedStrings(bundle: resourceBundle)
}

public func L(_ key: String) -> String { AppLocalization.strings.text(key) }
public func LF(_ key: String, _ arguments: String...) -> String { AppLocalization.strings.format(key, arguments) }
