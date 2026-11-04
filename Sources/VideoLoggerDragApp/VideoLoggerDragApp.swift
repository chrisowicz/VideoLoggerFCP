import VideoLoggerLocalization
import AppKit

@main
@MainActor
struct VideoLoggerDragApp {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let delegate = DragApplicationDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class DragApplicationDelegate: NSObject, NSApplicationDelegate {
    private var controller: DragWindowController?
    private var pendingSources: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = DragWindowController()
        self.controller = controller
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("Quit VideoLoggerFCP"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: L("File"))
        let openItem = fileMenu.addItem(withTitle: L("Add Files or Folders…"), action: #selector(DragWindowController.openSource(_:)), keyEquivalent: "o")
        openItem.target = controller
        fileItem.submenu = fileMenu
        menu.addItem(fileItem)
        NSApp.mainMenu = menu
        controller.showWindow(nil)
        NSApp.activate()
        if !pendingSources.isEmpty { controller.open(pendingSources); pendingSources = [] }
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--open"), arguments.indices.contains(index + 1) {
            controller.open(arguments[(index + 1)...].map { URL(fileURLWithPath: $0).standardizedFileURL })
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let controller { controller.open(urls) } else { pendingSources.append(contentsOf: urls) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
