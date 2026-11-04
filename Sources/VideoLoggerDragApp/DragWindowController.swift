import VideoLoggerLocalization
import AppKit
import UniformTypeIdentifiers
import VideoLoggerCore
import VideoLoggerDragDrop

@MainActor
final class DragWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let recordingsTable = RecordingTableView()
    private let segmentsTable = NSTableView()
    private let filterButton = NSPopUpButton()
    private let searchField = NSSearchField()
    private let removeButton = NSButton(title: L("Remove from List"), target: nil, action: nil)
    private let clearButton = NSButton(title: L("Clear List"), target: nil, action: nil)
    private var visibleRecordings: [Recording] = []
    private var pendingAdditions: [String: URL] = [:]
    private var updatingTables = false
    private let summaryLabel = NSTextField(labelWithString: L("Add files or a folder. Scanning does not inspect video parameters."))
    private let statusLabel = NSTextField(wrappingLabelWithString: L("Drop LLC, MP4, MOV files or folders from Finder into this window."))
    private let selectionLabel = NSTextField(labelWithString: L("Selected: 0"))
    private let mediaButton = NSButton(title: L("Locate Missing Media…"), target: nil, action: nil)
    private let issuesButton = NSButton(title: L("Scan Issues"), target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private let dragView = SelectionDragView(frame: .zero)
    private var library = RecordingLibrary()
    private var roots: [String: URL] = [:]
    private var rows: [LibrarySegmentRow] = []
    private let preparer = LibraryPreparer()
    private var prepared: PreparedLibraryDrag?
    private var scanTask: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?
    private var scanRevision = UUID(), selectionRevision = UUID()
    private var scanning = false

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 740),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = L("VideoLoggerFCP — Recordings and Segments")
        window.minSize = NSSize(width: 1100, height: 720)
        super.init(window: window); window.center(); buildInterface()
    }
    required init?(coder: NSCoder) { nil }

    private func buildInterface() {
        guard let content = window?.contentView else { return }
        let drop = ImportDropView(frame: content.bounds)
        drop.autoresizingMask = [.width, .height]; content.addSubview(drop)
        drop.importURLs = { [weak self] in self?.open($0) }
        let title = NSTextField(labelWithString: L("LosslessCut Recordings and Selections"))
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let subtitle = NSTextField(labelWithString: L("Files and folders → recordings → segments → drag the blue panel to Final Cut Pro"))
        subtitle.textColor = .secondaryLabelColor
        let add = NSButton(title: L("Add Files or Folders…"), target: self, action: #selector(openSource(_:)))
        add.setAccessibilityIdentifier("open-source")
        let refresh = NSButton(title: L("Refresh Sources"), target: self, action: #selector(refreshSources(_:)))
        mediaButton.target = self; mediaButton.action = #selector(chooseMedia(_:)); mediaButton.isEnabled = false
        issuesButton.target = self; issuesButton.action = #selector(showIssues(_:)); issuesButton.isEnabled = false
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        let toolbar = NSStackView(views: [add, refresh, mediaButton, issuesButton, spinner]); toolbar.orientation = .horizontal
        filterButton.addItems(withTitles: RecordingFilter.allCases.map(\.title))
        filterButton.target = self; filterButton.action = #selector(filterChanged(_:))
        filterButton.setAccessibilityIdentifier("recording-filter")
        searchField.placeholderString = L("Search filenames"); searchField.delegate = self
        searchField.setAccessibilityIdentifier("recording-search")
        removeButton.target = self; removeButton.action = #selector(removeSelected(_:)); removeButton.isEnabled = false
        clearButton.target = self; clearButton.action = #selector(clearList(_:)); clearButton.isEnabled = false
        recordingsTable.removeSelection = { [weak self] in self?.removeSelected(nil) }
        let management = NSStackView(views: [filterButton, searchField, removeButton, clearButton])
        management.orientation = .horizontal
        searchField.widthAnchor.constraint(equalToConstant: 240).isActive = true
        let recordScroll = makeTable(recordingsTable, columns: [("media", L("Original File"), 205), ("status", L("Status"), 120), ("count", L("Segments"), 65)])
        let segmentScroll = makeTable(segmentsTable, columns: [("source", L("Source File"), 220), ("name", L("Segment"), 260),
                    ("start", L("Start [s]"), 90), ("end", L("End [s]"), 90), ("duration", L("Duration [s]"), 95)])
        recordingsTable.setAccessibilityIdentifier("recordings-table"); segmentsTable.setAccessibilityIdentifier("segments-table")
        let panels = NSStackView(views: [recordScroll, segmentScroll]); panels.orientation = .horizontal; panels.alignment = .height
        let allRecordings = NSButton(title: L("All Recordings"), target: self, action: #selector(selectAllRecordings(_:)))
        let all = NSButton(title: L("All Segments"), target: self, action: #selector(selectAllSegments(_:)))
        let none = NSButton(title: L("Deselect Segments"), target: self, action: #selector(deselectSegments(_:)))
        let selection = NSStackView(views: [allRecordings, all, none, selectionLabel]); selection.orientation = .horizontal
        let hint = NSTextField(labelWithString: L("⌘/⇧-click to select multiple recordings and segments. LLC times are checked against exact frames before dragging."))
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.maximumNumberOfLines = 3; statusLabel.font = .systemFont(ofSize: 12); statusLabel.setAccessibilityIdentifier("status")
        dragView.makePayload = { [weak self] in
            guard let ready = self?.prepared else { throw ConversionError(L("Wait for the selected segments to finish preparing.")) }
            try ready.validateInputs(); return ready.payload
        }
        dragView.report = { [weak self] in self?.statusLabel.stringValue = $0 }
        let stack = NSStackView(views: [title, subtitle, toolbar, management, summaryLabel, panels, selection, hint, dragView, statusLabel])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false; drop.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: drop.leadingAnchor, constant: 22), stack.trailingAnchor.constraint(equalTo: drop.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: drop.topAnchor, constant: 20), stack.bottomAnchor.constraint(equalTo: drop.bottomAnchor, constant: -18),
            panels.widthAnchor.constraint(equalTo: stack.widthAnchor), panels.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
            recordScroll.widthAnchor.constraint(equalToConstant: 400), segmentScroll.heightAnchor.constraint(equalTo: recordScroll.heightAnchor),
            dragView.widthAnchor.constraint(equalTo: stack.widthAnchor), dragView.heightAnchor.constraint(equalToConstant: 62),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor), summaryLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func makeTable(_ table: NSTableView, columns: [(String, String, Double)]) -> NSScrollView {
        for (id, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); column.title = title; column.width = width
            table.addTableColumn(column)
        }
        table.dataSource = self; table.delegate = self; table.allowsMultipleSelection = true
        table.allowsEmptySelection = true; table.usesAlternatingRowBackgroundColors = true; table.rowHeight = 30
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder; scroll.documentView = table
        return scroll
    }

    @objc func openSource(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = true; panel.canChooseFiles = true
        panel.message = L("Add LLC, MP4, MOV, FCPXML files or folders. Subfolders are scanned without copying files.")
        panel.beginSheetModal(for: window) { [weak self] response in if response == .OK { self?.open(panel.urls) } }
    }
    func open(_ url: URL) { open([url]) }
    func open(_ urls: [URL]) {
        for url in urls { roots[libraryFileID(url)] = url; pendingAdditions[libraryFileID(url)] = url }
        scan()
    }
    @objc private func refreshSources(_ sender: Any?) { scan() }

    private func scan() {
        guard !roots.isEmpty else { return }
        scanTask?.cancel(); invalidatePreparation()
        scanning = true; spinner.startAnimation(nil)
        let revision = UUID(); scanRevision = revision
        let inputs = Array(roots.values)
        let additions = Array(pendingAdditions.values)
        statusLabel.stringValue = L("Scanning files and LLC projects…")
        scanTask = Task { [weak self] in
            do {
                let result = try await LibraryScanner().scan(inputs) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.scanRevision == revision, self.scanning else { return }
                        self.statusLabel.stringValue = LF("Scanning: %1$@ items · %2$@ LLC · %3$@ media files", String(describing: progress.visited), String(describing: progress.projects), String(describing: progress.media))
                    }
                }
                try Task.checkCancellation()
                guard let self, self.scanRevision == revision else { return }
                self.library.merge(result, restoringFrom: additions); self.scanning = false
                self.pendingAdditions = [:]
                self.reloadRecordings(selectAll: true)
                self.spinner.stopAnimation(nil); self.issuesButton.isEnabled = !self.library.issues.isEmpty
                self.statusLabel.stringValue = L("Scan complete. Select segments on the right. No LLC means the recording has no prepared selection.")
            } catch {
                guard !Task.isCancelled, let self, self.scanRevision == revision else { return }
                self.scanning = false; self.spinner.stopAnimation(nil); self.statusLabel.stringValue = error.localizedDescription
            }
        }
    }

    @objc private func chooseMedia(_ sender: Any?) {
        guard let window, recordingsTable.selectedRowIndexes.count == 1,
              let index = recordingsTable.selectedRowIndexes.first, visibleRecordings.indices.contains(index) else { return }
        let id = visibleRecordings[index].id
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]; panel.allowsMultipleSelection = false
        panel.message = L("Locate the original MP4 or MOV for this recording. This association is stored only in memory.")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                self.invalidatePreparation(); try self.library.locateMedia(for: id, at: url)
                self.reloadRecordings(selecting: [id])
                self.statusLabel.stringValue = L("Media linked. Select segments; their parameters will be checked before dragging.")
            } catch { self.statusLabel.stringValue = error.localizedDescription }
        }
    }
    @objc private func showIssues(_ sender: Any?) {
        let alert = NSAlert(); alert.messageText = LF("Scan Issues (%1$@)", String(describing: library.issues.count))
        alert.informativeText = library.issues.prefix(12).map { $0.url.path + "\n" + $0.message }.joined(separator: "\n\n")
            + (library.issues.count > 12 ? LF("\n… More issues: %1$@", String(describing: library.issues.count - 12)) : "")
        if let window { alert.beginSheetModal(for: window) }
    }
    @objc private func selectAllRecordings(_ sender: Any?) { recordingsTable.selectAll(nil) }
    @objc private func selectAllSegments(_ sender: Any?) { segmentsTable.selectAll(nil) }
    @objc private func deselectSegments(_ sender: Any?) { segmentsTable.deselectAll(nil) }

    private var selectedRecordingIDs: Set<String> {
        Set(recordingsTable.selectedRowIndexes.compactMap { visibleRecordings.indices.contains($0) ? visibleRecordings[$0].id : nil })
    }
    private func reloadRecordings(selecting ids: Set<String> = [], selectAll: Bool = false) {
        invalidatePreparation()
        let filter = RecordingFilter(rawValue: filterButton.indexOfSelectedItem) ?? .all
        visibleRecordings = library.visibleRecordings(filter: filter, search: searchField.stringValue)
        updatingTables = true
        recordingsTable.reloadData()
        let indexes = IndexSet(visibleRecordings.indices.filter { selectAll || ids.contains(visibleRecordings[$0].id) })
        recordingsTable.selectRowIndexes(indexes, byExtendingSelection: false)
        updatingTables = false
        refreshRows()
        clearButton.isEnabled = !library.recordings.isEmpty
        let missing = library.recordings.filter { !$0.mediaAvailable }.count
        summaryLabel.stringValue = LF("Visible: %1$@/%2$@ · segments: %3$@ · missing media: %4$@ · issues: %5$@", String(describing: visibleRecordings.count), String(describing: library.recordings.count), String(describing: library.recordings.reduce(0) { $0 + $1.segmentCount }), String(describing: missing), String(describing: library.issues.count))
    }
    @objc private func filterChanged(_ sender: Any?) {
        let ids = selectedRecordingIDs
        reloadRecordings(selecting: ids)
        statusLabel.stringValue = L("Filter changed. Select segments again; hidden recordings are not included in a drag.")
    }
    func controlTextDidChange(_ notification: Notification) { filterChanged(searchField) }
    private func cancelScan() {
        scanTask?.cancel(); scanRevision = UUID(); scanning = false; pendingAdditions = [:]
        spinner.stopAnimation(nil); invalidatePreparation()
    }
    @objc private func removeSelected(_ sender: Any?) {
        let ids = selectedRecordingIDs
        guard !ids.isEmpty else { return }
        cancelScan(); library.remove(ids: ids)
        reloadRecordings()
        statusLabel.stringValue = LF("Removed from list: %1$@. Files on disk are unchanged. Explicitly add the file or folder to restore the entry.", String(describing: ids.count))
    }
    @objc private func clearList(_ sender: Any?) {
        cancelScan(); library.clear(); roots = [:]
        reloadRecordings(); issuesButton.isEnabled = false
        statusLabel.stringValue = L("List cleared. Files on disk are unchanged.")
    }

    private func refreshRows() {
        invalidatePreparation()
        let ids = selectedRecordingIDs
        rows = library.segmentRows(for: ids)
        segmentsTable.reloadData(); segmentsTable.deselectAll(nil)
        mediaButton.isEnabled = recordingsTable.selectedRowIndexes.count == 1 && !scanning
        removeButton.isEnabled = !selectedRecordingIDs.isEmpty
    }
    private func invalidatePreparation() {
        prepareTask?.cancel(); selectionRevision = UUID(); prepared = nil; dragView.count = 0
        selectionLabel.stringValue = L("Selected: 0")
        if !scanning { spinner.stopAnimation(nil) }
    }
    private func prepareSelection() {
        invalidatePreparation()
        let selected = segmentsTable.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0] : nil }
        selectionLabel.stringValue = LF("Selected: %1$@", String(describing: selected.count))
        guard !scanning, !selected.isEmpty else { return }
        let revision = selectionRevision
        spinner.startAnimation(nil); statusLabel.stringValue = L("Preparing selected recordings for Drag & Drop…")
        prepareTask = Task { [weak self, preparer] in
            do {
                let result = try await preparer.prepare(selected) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.selectionRevision == revision, self.prepared == nil else { return }
                        self.statusLabel.stringValue = LF("Preparing %1$@/%2$@: %3$@", String(describing: progress.completed), String(describing: progress.total), String(describing: progress.name))
                    }
                }
                try Task.checkCancellation()
                guard let self, self.selectionRevision == revision else { return }
                self.prepared = result; self.dragView.count = result.payload.count; self.spinner.stopAnimation(nil)
                self.statusLabel.stringValue = LF("Ready — segments: %1$@. Drag the blue panel to an Event or Final Cut Pro timeline.", String(describing: result.payload.count))
            } catch {
                guard !Task.isCancelled, let self, self.selectionRevision == revision else { return }
                self.spinner.stopAnimation(nil); self.statusLabel.stringValue = error.localizedDescription
            }
        }
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updatingTables else { return }
        if notification.object as? NSTableView === recordingsTable { refreshRows() }
        else { prepareSelection() }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { tableView === recordingsTable ? visibleRecordings.count : rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let key = tableColumn?.identifier.rawValue ?? ""
        let text: String
        var tooltip: String?
        if tableView === recordingsTable {
            guard visibleRecordings.indices.contains(row) else { return nil }
            let record = visibleRecordings[row]
            switch key { case "status": text = record.status; case "count": text = "\(record.segmentCount)"; default: text = record.name }
            tooltip = record.mediaURL?.path ?? LF("Missing media: %1$@", String(describing: record.expectedMediaURL.path))
        } else {
            guard rows.indices.contains(row) else { return nil }
            let entry = rows[row]
            switch key {
            case "source": text = entry.recording.name
            case "start": text = String(format: "%.6f", entry.segment.start)
            case "end": text = String(format: "%.6f", entry.segment.end)
            case "duration": text = String(format: "%.6f", entry.segment.end - entry.segment.start)
            default: text = entry.segment.name
            }
            tooltip = "\(entry.source.url.lastPathComponent) · \(entry.recording.status)"
        }
        let cell = NSTextField(labelWithString: text); cell.lineBreakMode = .byTruncatingMiddle; cell.toolTip = tooltip
        return cell
    }
}
