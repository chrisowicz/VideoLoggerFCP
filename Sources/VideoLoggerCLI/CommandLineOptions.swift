import VideoLoggerLocalization
import Foundation
import VideoLoggerCore

struct CommandLineOptions {
    let source: URL
    var media: URL?
    var output: URL?
    var options = ExportOptions()

    var outputURL: URL {
        output ?? SafeOutputWriter.defaultOutput(for: source, includeStringout: options.includeStringout)
    }

    init(_ arguments: [String]) throws {
        guard let first = arguments.first, !first.hasPrefix("-") else {
            throw ConversionError(L("Provide one source .llc file."))
        }
        source = URL(fileURLWithPath: first).standardizedFileURL
        var index = 1
        var seen = Set<String>()
        while index < arguments.count {
            let flag = arguments[index]
            // Both spellings represent the same option: reject conflicting/duplicate names.
            let key = flag == "--event" ? "--event-name" : flag
            guard seen.insert(key).inserted else { throw ConversionError(LF("Duplicate option: %1$@", String(describing: flag))) }
            if flag == "--stringout" { options.includeStringout = true; index += 1; continue }
            guard ["--media", "--output", "--event", "--event-name"].contains(flag), index + 1 < arguments.count,
                  !arguments[index + 1].hasPrefix("--") else {
                throw ConversionError(LF("Unknown option or missing value: %1$@", String(describing: flag)))
            }
            let value = arguments[index + 1]
            switch flag {
            case "--media": media = URL(fileURLWithPath: value).standardizedFileURL
            case "--output": output = URL(fileURLWithPath: value).standardizedFileURL
            default: options.eventName = value
            }
            index += 2
        }
    }
}
