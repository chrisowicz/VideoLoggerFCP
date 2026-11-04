import VideoLoggerLocalization
import Foundation
import Darwin
import VideoLoggerCore

@main
struct VideoLoggerCommand {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments == ["--help"] || arguments == ["-h"] { print(usage); return }
            let command = try CommandLineOptions(arguments)
            print(L("Reading the project and checking metadata and every frame timestamp…"))
            let result = try await ConversionService().convert(source: command.source, mediaOverride: command.media,
                                                              options: command.options)
            let output = command.outputURL
            for warning in result.warnings { print(LF("Warning: %1$@", String(describing: warning))) }
            try SafeOutputWriter.write(result.document, to: output, protecting: [command.source, result.plan.media.url])
            let media = result.plan.media
            print(LF("Saved: %1$@", String(describing: output.path)))
            print(LF("Video: %1$@×%2$@, %3$@ fps, frame duration %4$@, %5$@ frames", String(describing: media.width), String(describing: media.height), String(describing: media.clock.framesPerSecond), String(describing: try media.clock.time(frames: 1)), String(describing: media.frameCount)))
            print(LF("Source timecode: %1$@ (%2$@); metadata rotation: %3$@°", String(describing: try media.clock.time(frames: media.sourceStartFrame)), String(describing: media.timecodeFormat), String(describing: media.rotationDegrees)))
            if media.colorSpace == nil { print(L("Warning: no recognized color space; no colorSpace declaration was added. Check colors in Final Cut Pro.")) }
            for (index, range) in result.plan.ranges.enumerated() {
                print(LF("%1$@. %2$@: frames [%3$@, %4$@), %5$@ + %6$@", String(describing: index + 1), String(describing: range.name), String(describing: range.start), String(describing: range.end), String(describing: try media.clock.time(frames: range.start)), String(describing: try media.clock.time(frames: range.duration))))
            }
            print(LF("Keyword Ranges: %1$@; stringout: %2$@", String(describing: result.plan.ranges.count), String(describing: result.plan.includeStringout ? LF("%1$@ clips", String(result.plan.selectedRanges.count)) : L("off"))))
            print(L("Final Cut Pro import requires separate verification; see docs/USAGE.md."))
        } catch {
            FileHandle.standardError.write(Data(LF("Error: %1$@\n\n%2$@\n", String(describing: error.localizedDescription), String(describing: usage)).utf8))
            exit(1)
        }
    }
    static let usage = L("cli.usage")
}

