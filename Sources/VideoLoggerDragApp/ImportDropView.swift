import AppKit
import VideoLoggerDragDrop

@MainActor
final class ImportDropView: NSView {
    var importURLs: (([URL]) -> Void)?
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { nil }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        !FinderDropReader.urls(from: sender.draggingPasteboard).isEmpty && sender.draggingSourceOperationMask.contains(.copy) ? .copy : []
    }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { !FinderDropReader.urls(from: sender.draggingPasteboard).isEmpty }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = FinderDropReader.urls(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }; importURLs?(urls); return true
    }
}
