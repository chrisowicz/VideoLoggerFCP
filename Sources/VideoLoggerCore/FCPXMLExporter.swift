import VideoLoggerLocalization
import Foundation

public struct FCPXMLExporter: ProjectExporting {
    public init() {}
    public func export(_ plan: ConversionPlan) throws -> Data {
        let clock = plan.media.clock
        let duration = try clock.time(frames: plan.media.frameCount)
        let sourceStart = try clock.time(frames: plan.media.sourceStartFrame)
        let root = element("fcpxml", [("version", "1.9")])
        let resources = element("resources")
        var formatAttributes = [("id", "r1"), ("frameDuration", try clock.time(frames: 1)),
                                ("width", "\(plan.media.width)"), ("height", "\(plan.media.height)"),
                                ("fieldOrder", "progressive")]
        if let colorSpace = plan.media.colorSpace { formatAttributes.append(("colorSpace", colorSpace)) }
        resources.addChild(element("format", formatAttributes))
        var assetAttributes = [("id", "r2"), ("name", plan.project.mediaFileName), ("start", sourceStart),
                               ("duration", duration), ("hasVideo", "1"), ("format", "r1"), ("videoSources", "1")]
        if let audio = plan.media.audio {
            assetAttributes += [("hasAudio", "1"), ("audioSources", "1"),
                                ("audioChannels", "\(audio.channels)"), ("audioRate", "\(audio.sampleRate)")]
        }
        let asset = element("asset", assetAttributes)
        asset.addChild(element("media-rep", [("kind", "original-media"), ("src", plan.media.url.absoluteString)]))
        resources.addChild(asset)
        root.addChild(resources)
        let event = element("event", [("name", plan.eventName)])
        let source = element("asset-clip", [("ref", "r2"), ("name", plan.project.mediaFileName),
                                            ("format", "r1"), ("start", sourceStart), ("duration", duration),
                                            ("tcFormat", plan.media.timecodeFormat)])
        for range in plan.ranges {
            source.addChild(element("keyword", [("start", try clock.time(frames: plan.media.sourceStartFrame + range.start)),
                                                 ("duration", try clock.time(frames: range.duration)),
                                                 ("value", range.name)]))
        }
        event.addChild(source)
        var names = Set<String>()
        for range in plan.ranges where names.insert(range.name).inserted {
            event.addChild(element("keyword-collection", [("name", range.name)]))
        }
        if plan.includeStringout {
            let project = element("project", [("name", plan.projectName)])
            let spine = element("spine")
            var offset: Int64 = 0
            for range in plan.selectedRanges {
                let clip = element("asset-clip", [("ref", "r2"), ("name", range.name),
                                                  ("offset", try clock.time(frames: offset)),
                                                  ("start", try clock.time(frames: plan.media.sourceStartFrame + range.start)),
                                                  ("duration", try clock.time(frames: range.duration))])
                spine.addChild(clip)
                let sum = offset.addingReportingOverflow(range.duration)
                guard !sum.overflow else { throw ConversionError(L("The stringout exceeds the time range.")) }
                offset = sum.partialValue
            }
            let sequence = element("sequence", [("format", "r1"), ("duration", try clock.time(frames: offset)),
                                                 ("tcStart", "0s"), ("tcFormat", "NDF")])
            sequence.addChild(spine)
            project.addChild(sequence)
            event.addChild(project)
        }
        root.addChild(event)
        let document = XMLDocument(rootElement: root)
        document.version = "1.0"
        document.characterEncoding = "UTF-8"
        let dtd = XMLDTD()
        dtd.name = "fcpxml"
        document.dtd = dtd
        let data = document.xmlData(options: [.nodePrettyPrint])
        // Parsing checks well-formedness. Official DTD validation is a separate check.
        _ = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
        return data
    }
}

private func element(_ name: String, _ attributes: [(String, String)] = []) -> XMLElement {
    let node = XMLElement(name: name)
    for (key, value) in attributes {
        node.addAttribute(XMLNode.attribute(withName: key, stringValue: value) as! XMLNode)
    }
    return node
}
