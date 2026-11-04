import VideoLoggerLocalization
import Foundation
import VideoLoggerCore

public struct DragClipSelection: Sendable {
    public let document: DragDocument
    public let indices: [Int]
    public init(document: DragDocument, indices: [Int]) { self.document = document; self.indices = indices }
}

public struct FCPXMLDragPayload: Sendable {
    public static let currentType = "com.apple.finalcutpro.xml.v1-14"
    public static let legacyType = "com.apple.finalcutpro.xml.v1-9"
    public static let genericType = "com.apple.finalcutpro.xml"
    public static let types = [currentType, legacyType, genericType]
    private struct ClipTemplate {
        let contents: Data
        let source: XMLElement
        let mapping: [String: String]
        let keywords: [XMLElement]
        let note: XMLElement?
        let metadata: XMLElement?
    }
    private let current: Data
    private let legacy: Data
    public let count: Int

    init(document: DragDocument, selection: IndexSet) throws {
        try self.init(selections: [DragClipSelection(document: document, indices: Array(selection))])
    }

    public init(selections: [DragClipSelection]) throws {
        guard !selections.isEmpty, selections.allSatisfy({ group in !group.indices.isEmpty && group.indices.allSatisfy { group.document.segments.indices.contains($0) } }) else {
            throw ConversionError(L("Select available segments to drag."))
        }
        let root = XMLElement(name: "fcpxml")
        let options = XMLElement(name: "import-options")
        let link = XMLElement(name: "option")
        link.addAttribute(XMLNode.attribute(withName: "key", stringValue: "copy assets") as! XMLNode)
        link.addAttribute(XMLNode.attribute(withName: "value", stringValue: "0") as! XMLNode)
        options.addChild(link); root.addChild(options)
        let combinedResources = XMLElement(name: "resources")
        root.addChild(combinedResources)
        var mappings: [Data: [String: String]] = [:]
        var nextID = 1
        var templates: [String: ClipTemplate] = [:]
        for group in selections {
            let document = group.document
            try Task.checkCancellation()
            let key = document.sourceURL.absoluteString + "|" + document.media.url.absoluteString
            let template: ClipTemplate
            if let cached = templates[key] {
                guard cached.contents == document.sourceXML else { throw ConversionError(L("Two versions of the same source are present in one selection.")) }
                template = cached
            } else {
                let original = try DragDocumentReader.parse(document.sourceXML)
                let resources = try DragDocumentReader.uniqueElement(original, "/fcpxml/resources")
                let source = try DragDocumentReader.uniqueElement(original, "/fcpxml/asset-clip | /fcpxml/event/asset-clip | /fcpxml/library/event/asset-clip")
                let signature = Data(resources.xmlString(options: [.nodeCompactEmptyElement]).utf8)
                let mapping: [String: String]
                if let existing = mappings[signature] { mapping = existing }
                else {
                    var allocated: [String: String] = [:]
                    for resource in (resources.children ?? []).compactMap({ $0 as? XMLElement }) {
                        let id = try DragDocumentReader.attribute(resource, "id")
                        guard allocated[id] == nil else { throw ConversionError(L("Duplicate XML resource identifier.")) }
                        allocated[id] = "r\(nextID)"; nextID += 1
                    }
                    mapping = allocated; mappings[signature] = mapping
                    for resource in (resources.children ?? []).compactMap({ $0 as? XMLElement }) {
                        let copy = resource.copy() as! XMLElement
                        Self.remap(copy, mapping: mapping); combinedResources.addChild(copy)
                    }
                }
                template = ClipTemplate(contents: document.sourceXML, source: source, mapping: mapping,
                    keywords: source.elements(forName: "keyword"), note: source.elements(forName: "note").first,
                    metadata: source.elements(forName: "metadata").first)
                templates[key] = template
            }
            let source = template.source, mapping = template.mapping
            // Preserve the explicitly supplied order (recording list, then source time).
            for index in group.indices {
                try Task.checkCancellation()
                let segment = document.segments[index]
                let clip = XMLElement(name: "asset-clip")
                for key in ["ref", "format", "tcFormat", "audioRole", "videoRole", "srcEnable"] {
                    if let value = source.attribute(forName: key)?.stringValue {
                        let mapped = (key == "ref" || key == "format") ? (mapping[value] ?? value) : value
                        clip.addAttribute(XMLNode.attribute(withName: key, stringValue: mapped) as! XMLNode)
                    }
                }
                for (key, value) in [("name", segment.name),
                    ("start", try document.media.clock.time(frames: document.media.sourceStartFrame + segment.startFrame)),
                    ("duration", try document.media.clock.time(frames: segment.durationFrames))] {
                    clip.addAttribute(XMLNode.attribute(withName: key, stringValue: value) as! XMLNode)
                }
                if let note = template.note { clip.addChild(note.copy() as! XMLElement) }
                clip.addChild(template.keywords[index].copy() as! XMLElement)
                if let metadata = template.metadata { clip.addChild(metadata.copy() as! XMLElement) }
                root.addChild(clip)
            }
        }
        let xml = XMLDocument(rootElement: root)
        xml.version = "1.0"
        xml.characterEncoding = "UTF-8"
        let dtd = XMLDTD(); dtd.name = "fcpxml"; xml.dtd = dtd
        root.addAttribute(XMLNode.attribute(withName: "version", stringValue: "1.14") as! XMLNode)
        current = xml.xmlData(options: [.nodePrettyPrint, .nodeCompactEmptyElement])
        root.attribute(forName: "version")?.stringValue = "1.9"
        legacy = xml.xmlData(options: [.nodePrettyPrint, .nodeCompactEmptyElement])
        count = selections.reduce(0) { $0 + $1.indices.count }
    }

    private static func remap(_ node: XMLElement, mapping: [String: String]) {
        for attribute in node.attributes ?? [] where ["id", "ref", "format", "projectRef"].contains(attribute.name ?? "") {
            if let value = attribute.stringValue, let replacement = mapping[value] { attribute.stringValue = replacement }
        }
        for child in (node.children ?? []).compactMap({ $0 as? XMLElement }) { remap(child, mapping: mapping) }
    }

    public func data(for type: String) -> Data? {
        switch type {
        case Self.currentType, Self.genericType: current
        case Self.legacyType: legacy
        default: nil
        }
    }
}
