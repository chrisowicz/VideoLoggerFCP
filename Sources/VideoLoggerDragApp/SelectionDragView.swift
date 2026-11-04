import VideoLoggerLocalization
import AppKit
import VideoLoggerDragDrop

@MainActor
final class SelectionDragView: NSView, NSDraggingSource {
    var makePayload: (() throws -> FCPXMLDragPayload)?
    var report: ((String) -> Void)?
    var count = 0 { didSet { needsDisplay = true; setAccessibilityLabel(LF("Drag selected segments: %1$@", String(describing: count))) } }
    private var anchor: NSPoint?
    private var provider: FCPXMLPasteboardProvider?
    private var session: NSDraggingSession?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("drag-selection")
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        (count > 0 ? NSColor.controlAccentColor : NSColor.disabledControlTextColor).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let text = count > 0 ? LF("Drag selected segments to Final Cut Pro (%1$@)", String(describing: count)) : L("Select segments in the list")
        (text as NSString).draw(in: NSRect(x: 12, y: bounds.midY - 10, width: bounds.width - 24, height: 25),
            withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white, .paragraphStyle: style])
    }

    override func mouseDown(with event: NSEvent) { anchor = convert(event.locationInWindow, from: nil) }
    override func mouseUp(with event: NSEvent) { anchor = nil }
    override func mouseDragged(with event: NSEvent) {
        guard session == nil, count > 0, let anchor, let makePayload else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - anchor.x, point.y - anchor.y) >= 4 else { return }
        do {
            let payload = try makePayload()
            let provider = FCPXMLPasteboardProvider(payload: payload) { [weak self] type in
                Task { @MainActor [weak self] in self?.report?(LF("The receiver requested native payload: %1$@.", String(describing: type))) }
            }
            self.provider = provider // Keep immutable snapshot alive after the drag until the next interaction.
            let item = NSDraggingItem(pasteboardWriter: try provider.makeItem())
            let image = NSImage(size: NSSize(width: 260, height: 42), flipped: false) { rect in
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
                (LF("VideoLoggerFCP · %1$@ segments", String(describing: payload.count)) as NSString).draw(at: NSPoint(x: 14, y: 13),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white])
                return true
            }
            item.setDraggingFrame(NSRect(x: point.x - 20, y: point.y - 20, width: 260, height: 42), contents: image)
            report?(LF("Dragging %1$@ segments. Drop on an Event or open Final Cut Pro timeline.", String(describing: payload.count)))
            session = beginDraggingSession(with: [item], event: event, source: self)
            self.anchor = nil
        } catch { report?(error.localizedDescription) }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        self.session = nil
        anchor = nil
        report?(operation.isEmpty ? L("Drag canceled or rejected. The selection remains available.")
            : L("The receiver finished the drag. Verify ranges and the result in Final Cut Pro; the gesture alone does not confirm import."))
    }
}
