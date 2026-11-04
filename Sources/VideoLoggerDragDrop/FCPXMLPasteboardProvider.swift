import VideoLoggerLocalization
import AppKit

/// No file promises or file URLs: the receiver requests native FCPXML bytes.
public final class FCPXMLPasteboardProvider: NSObject, NSPasteboardItemDataProvider {
    private let payload: FCPXMLDragPayload
    private let onRequest: (@Sendable (String) -> Void)?

    public init(payload: FCPXMLDragPayload, onRequest: (@Sendable (String) -> Void)? = nil) {
        self.payload = payload
        self.onRequest = onRequest
    }

    public func makeItem() throws -> NSPasteboardItem {
        let item = NSPasteboardItem()
        guard item.setDataProvider(self, forTypes: FCPXMLDragPayload.types.map { NSPasteboard.PasteboardType($0) }) else {
            throw NSError(domain: "VideoLoggerDragDrop", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: L("Cannot prepare the native FCPXML payload.")])
        }
        return item
    }

    public func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                           provideDataForType type: NSPasteboard.PasteboardType) {
        guard let data = payload.data(for: type.rawValue) else { return }
        if item.setData(data, forType: type) { onRequest?(type.rawValue) }
    }
}
