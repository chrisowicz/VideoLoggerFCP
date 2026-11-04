import AppKit

/// Delete only affects the session when the recording table has keyboard focus.
@MainActor
final class RecordingTableView: NSTableView {
    var removeSelection: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if [51, 117].contains(event.keyCode),
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            removeSelection?()
        } else { super.keyDown(with: event) }
    }
}
