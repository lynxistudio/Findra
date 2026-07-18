import SwiftUI
import AppKit
import Quartz

private let sortOrderDefaultsKey = "FindraSortOrder"
private let legacySortOrderDefaultsKey = "FastFinderSortOrder"

// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var locale: LocaleManager
    @State private var showAddDirectorySheet = false
    @State private var newDirectoryPath = ""
    @State private var newDirectoryType: DirectoryType = .nfs
    @State private var sortOrder: [KeyPathComparator<IndexedFile>] = [.init(\.modDate, order: .reverse)]
    @State private var directoryToRemove: IndexDirectory?
    @State private var showExcludedSheet = false
    @State private var newExcludedPattern = ""
    @State private var isExcludedExpanded = false
    @State private var resultsKeyMonitor: Any?
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isRenameFocused: Bool

    init() {
        if UserDefaults.standard.string(forKey: sortOrderDefaultsKey) == nil,
           let legacySort = UserDefaults.standard.string(forKey: legacySortOrderDefaultsKey) {
            UserDefaults.standard.set(legacySort, forKey: sortOrderDefaultsKey)
        }

        if let savedSort = UserDefaults.standard.string(forKey: sortOrderDefaultsKey) {
            let parts = savedSort.split(separator: ":")
            if parts.count == 2 {
                let order: SortOrder = parts[1] == "reverse" ? .reverse : .forward
                switch parts[0] {
                case "fileName": sortOrder = [.init(\.fileName, order: order)]
                case "size": sortOrder = [.init(\.size, order: order)]
                case "modDate": sortOrder = [.init(\.modDate, order: order)]
                case "fullPath": sortOrder = [.init(\.fullPath, order: order)]
                default: sortOrder = [.init(\.modDate, order: .reverse)]
                }
            }
        }
    }

    var body: some View {
        HSplitView {
            directorySidebar
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
            VStack(spacing: 0) {
                searchBar
                resultsArea
                statusBar
            }
            .frame(minWidth: 500)
        }
        .onAppear {
            isSearchFocused = true
            installResultsKeyMonitor()
        }
        .onDisappear { removeResultsKeyMonitor() }
        .onChange(of: appState.editingFileId) { _, newId in
            if newId != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isRenameFocused = true
                }
            }
        }
        .onChange(of: isRenameFocused) { _, focused in
            if !focused { appState.cancelEditing() }
        }
        .onChange(of: appState.searchResults) { _, results in
            let visibleIds = Set(results.map(\.id))
            appState.selectedFiles.formIntersection(visibleIds)
        }
    }

    // MARK: - Directory Sidebar

    var directorySidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with + button
            HStack {
                Text(locale.indexedDirectories)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button { showAddDirectorySheet = true } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help(locale.addDirectory)
            }
            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 6)

            // Directory list with per-row delete buttons
            List {
                ForEach(appState.directories) { dir in
                    HStack(spacing: 4) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(URL(fileURLWithPath: dir.path).lastPathComponent)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Text(dir.path)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Image(systemName: dir.type == .local ? "internaldrive" : "network")
                                    .font(.system(size: 8)).foregroundColor(.blue)
                                Text(dir.type.displayName(locale))
                                    .font(.system(size: 8)).foregroundColor(.blue)
                                if dir.enabled {
                                    Circle().fill(Color.green).frame(width: 5, height: 5)
                                    Text(locale.indexed).font(.system(size: 8)).foregroundColor(.green)
                                    let stats = appState.directoryIndexStats[dir.id] ?? DirectoryIndexStats()
                                    Text(locale.directoryIndexStats(folders: stats.folderCount, files: stats.fileCount))
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        Spacer()
                        Button {
                            directoryToRemove = dir
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 3)
                    .contextMenu {
                        Button(locale.rescan) { appState.scanDirectory(dir) }
                        Button(locale.stopWatching) { appState.stopWatchingForDirectory(dir) }
                        Divider()
                        Button(locale.remove, role: .destructive) { appState.removeDirectory(dir) }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider().padding(.horizontal, 8)

            // Excluded patterns — collapsed by default
            DisclosureGroup(isExpanded: $isExcludedExpanded) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(appState.excludedPatterns, id: \.self) { pattern in
                        HStack(spacing: 4) {
                            Circle().fill(Color.orange.opacity(0.6)).frame(width: 5, height: 5)
                            Text(pattern)
                                .font(.system(size: 11))
                                .lineLimit(1)
                            Spacer()
                            Button {
                                appState.removeExcludedPattern(pattern)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 2)
                    }
                }
                .frame(maxHeight: 160)
                .padding(.top, 4)
            } label: {
                HStack {
                    Label(locale.exclusionRules, systemImage: "exclamationmark.shield")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("(\(appState.excludedPatterns.count))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.6))
                    Spacer()
                    Button {
                        showExcludedSheet = true
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
            .padding(.horizontal, 4)

            Spacer()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $showAddDirectorySheet) {
            addDirectorySheet
        }
        .sheet(isPresented: $showExcludedSheet) {
            excludedPatternSheet
        }
        .alert(locale.confirmRemoveTitle, isPresented: Binding(
            get: { directoryToRemove != nil },
            set: { if !$0 { directoryToRemove = nil } }
        )) {
            Button(locale.cancel, role: .cancel) { directoryToRemove = nil }
            Button(locale.remove, role: .destructive) {
                if let dir = directoryToRemove {
                    appState.removeDirectory(dir)
                    directoryToRemove = nil
                }
            }
        } message: {
            if let dir = directoryToRemove {
                Text(locale.confirmRemoveMsg(path: dir.path))
            }
        }
    }

    // MARK: - Sheets

    var addDirectorySheet: some View {
        VStack(spacing: 16) {
            Text(locale.addDirectory).font(.title2).bold()
            HStack {
                Text(locale.pathLabel).font(.headline)
                TextField("/Volumes/...", text: $newDirectoryPath)
                    .textFieldStyle(.roundedBorder).frame(width: 290)
                Button {
                    browseFolder()
                } label: {
                    Label(locale.browse, systemImage: "folder")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            HStack {
                Text(locale.typeLabel).font(.headline)
                Picker("", selection: $newDirectoryType) {
                    ForEach(DirectoryType.allCases, id: \.self) { t in
                        Text(t.displayName(locale)).tag(t)
                    }
                }.pickerStyle(.segmented).frame(width: 200)
            }
            HStack {
                Button(locale.cancel) { showAddDirectorySheet = false }
                Button(locale.add) {
                    let path = newDirectoryPath.trimmingCharacters(in: .whitespaces)
                    if !path.isEmpty {
                        appState.addDirectory(path, type: newDirectoryType)
                    }
                    newDirectoryPath = ""
                    showAddDirectorySheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newDirectoryPath.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(30).frame(width: 500, height: 220)
    }

    var excludedPatternSheet: some View {
        VStack(spacing: 16) {
            Text(locale.addExclusionRule).font(.title3).bold()
            Text(locale.exclusionHint)
                .font(.caption).foregroundColor(.secondary)
            HStack {
                TextField(locale.patternPlaceholder, text: $newExcludedPattern)
                    .textFieldStyle(.roundedBorder).frame(width: 250)
                Button(locale.add) {
                    let p = newExcludedPattern.trimmingCharacters(in: .whitespaces)
                    if !p.isEmpty { appState.addExcludedPattern(p) }
                    newExcludedPattern = ""
                    showExcludedSheet = false
                }.buttonStyle(.borderedProminent)
                    .disabled(newExcludedPattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Button(locale.cancel) { showExcludedSheet = false; newExcludedPattern = "" }
        }.padding(30).frame(width: 400, height: 180)
    }

    // MARK: - Search Bar

    var searchBar: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary).padding(.leading, 10)
            TextField(locale.searchPlaceholder, text: $appState.searchQuery)
                .textFieldStyle(.plain).font(.system(size: 14))
                .focused($isSearchFocused)
                .padding(.vertical, 8).padding(.horizontal, 6)
            if !appState.searchQuery.isEmpty {
                Button { appState.searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }.buttonStyle(.plain).padding(.trailing, 8)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        .padding(.horizontal, 12).padding(.top, 10)
    }

    // MARK: - Results Area

    var resultsArea: some View {
        Group {
            if appState.searchResults.isEmpty && !appState.searchQuery.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28)).foregroundColor(.secondary.opacity(0.4))
                    Text(locale.noResults).font(.body).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.searchResults.isEmpty && appState.searchQuery.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 32)).foregroundColor(.secondary.opacity(0.4))
                    Text(locale.emptyPrompt).font(.body).foregroundColor(.secondary)
                    Text(locale.totalFiles(appState.totalFileCount))
                        .font(.caption).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                resultsTable
            }
        }
    }

    var resultsTable: some View {
        Table(appState.searchResults, selection: $appState.selectedFiles, sortOrder: $sortOrder) {
            TableColumn(locale.tableFileName, value: \.fileName) { file in
                HStack(spacing: 6) {
                    FileIconView(filePath: file.fullPath, fileName: file.fileName, isDirectory: file.isDirectory)
                        .frame(width: 18, height: 18)

                    if appState.editingFileId == file.id {
                        TextField("", text: $appState.editingFileName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .focused($isRenameFocused)
                            .onSubmit { appState.commitEditing() }
                    } else {
                        Text(file.fileName)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    if appState.editingFileId != file.id {
                        FinderDragSourceOverlay(
                            file: file,
                            selectedIds: $appState.selectedFiles,
                            visibleFiles: appState.searchResults
                        )
                    }
                }
            }
            .width(ideal: 300)

            TableColumn(locale.tableSize, value: \.size) { file in
                Text(file.isDirectory ? "—" : file.sizeFormatted)
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }.width(min: 80, ideal: 100)

            TableColumn(locale.tableModDate, value: \.modDate) { file in
                Text(file.modDateFormatted)
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }.width(min: 120, ideal: 140)

            TableColumn(locale.tablePath) { file in
                Text(file.fullPath)
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.head)
            }.width(ideal: 400)
        }
        .onChange(of: sortOrder) { _, newValue in
            appState.searchResults.sort(using: newValue)
            if let first = newValue.first {
                saveSortOrder(first.keyPath, order: first.order)
            }
        }
        .contextMenu(forSelectionType: Int64.self) { selectedIds in
            contextMenu(for: selectedIds)
        }
        .onKeyPress(.return) {
            if appState.editingFileId != nil {
                appState.commitEditing()
                return .handled
            }
            // Enter to rename selected file
            if appState.selectedFiles.count == 1,
               let id = appState.selectedFiles.first,
               let file = appState.searchResults.first(where: { $0.id == id }),
               !file.isDirectory {
                appState.startEditingFile(file)
                return .handled
            }
            openSelectedFiles()
            return .handled
        }
        .onKeyPress(.escape) {
            if appState.editingFileId != nil {
                appState.cancelEditing()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.space) {
            quickLookSelected()
            return .handled
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    func contextMenu(for selectedIds: Set<Int64>) -> some View {
        let ids = selectedIds.isEmpty ? appState.selectedFiles : selectedIds
        let files = appState.dbManager.getFilesByIds(ids)

        if files.count == 1 {
            Button(locale.rename) { appState.startEditingFile(files[0]) }
            Divider()
            Button(locale.copy) { appState.copyFiles(ids) }
            Button(locale.showInFinder) { appState.revealInFinder(files[0]) }
            Button(locale.quickLook) { quickLookFiles(files) }
            Divider()
            Button(locale.open) { openFiles(files) }
            Divider()
            Button(locale.moveToTrash, role: .destructive) { appState.deleteFiles(ids) }
        } else if !ids.isEmpty {
            Button(locale.copy) { appState.copyFiles(ids) }
            Button(locale.quickLook) { quickLookFiles(files) }
            Button(locale.open) { appState.openSelectedFiles() }
            Divider()
            Button(locale.moveToTrash, role: .destructive) { appState.deleteFiles(ids) }
        }
    }

    // MARK: - Status Bar

    var statusBar: some View {
        HStack(spacing: 4) {
            if appState.isScanning {
                ProgressView().scaleEffect(0.7).padding(.trailing, 4)
                Text(appState.scanProgress)
                    .font(.system(size: 11)).foregroundColor(.secondary)
            } else {
                Text(appState.statusText)
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Text(locale.resultCount(appState.searchResults.count))
                .font(.system(size: 11)).foregroundColor(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Actions

    func quickLookSingle(_ file: IndexedFile) {
        quickLookFiles([file])
    }

    func quickLookSelected() {
        let files = availableFiles(from: appState.dbManager.getFilesByIds(appState.selectedFiles))
        guard !files.isEmpty else { return }
        QuickLookCoordinator.shared.togglePreview(
            urls: files.map { URL(fileURLWithPath: $0.fullPath) }
        )
    }

    func quickLookFiles(_ files: [IndexedFile]) {
        let files = availableFiles(from: files)
        guard !files.isEmpty else { return }
        QuickLookCoordinator.shared.showPreview(
            urls: files.map { URL(fileURLWithPath: $0.fullPath) }
        )
    }

    func openSelectedFiles() {
        openFiles(appState.dbManager.getFilesByIds(appState.selectedFiles))
    }

    func openFiles(_ files: [IndexedFile]) {
        for file in availableFiles(from: files) {
            NSWorkspace.shared.open(URL(fileURLWithPath: file.fullPath))
        }
    }

    func availableFiles(from files: [IndexedFile]) -> [IndexedFile] {
        let available = files.filter { FileManager.default.fileExists(atPath: $0.fullPath) }
        let unavailableCount = files.count - available.count
        if unavailableCount > 0 {
            appState.statusText = locale.unavailableFiles(unavailableCount)
        }
        return available
    }

    func installResultsKeyMonitor() {
        guard resultsKeyMonitor == nil else { return }
        resultsKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers == [.command], event.charactersIgnoringModifiers?.lowercased() == "c" {
                guard appState.editingFileId == nil,
                      !appState.selectedFiles.isEmpty,
                      isResultsTableFocused(in: event.window) else { return event }
                appState.copyFiles(appState.selectedFiles)
                return nil
            }

            guard event.keyCode == 49 else { return event }
            guard !modifiers.contains(.command),
                  !modifiers.contains(.control),
                  !modifiers.contains(.option) else { return event }

            if QuickLookCoordinator.shared.isPreviewVisible {
                QuickLookCoordinator.shared.closePreview()
                return nil
            }

            guard !appState.selectedFiles.isEmpty,
                  isResultsTableFocused(in: event.window) else { return event }
            quickLookSelected()
            return nil
        }
    }

    func removeResultsKeyMonitor() {
        if let resultsKeyMonitor {
            NSEvent.removeMonitor(resultsKeyMonitor)
            self.resultsKeyMonitor = nil
        }
    }

    func isResultsTableFocused(in window: NSWindow?) -> Bool {
        guard let window, !(window.firstResponder is NSTextView) else { return false }
        var responder = window.firstResponder
        while let current = responder {
            if current is NSTableView { return true }
            responder = current.nextResponder
        }
        return false
    }

    func browseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = locale.selectFolderPrompt
        panel.prompt = locale.selectPrompt
        if panel.runModal() == .OK, let url = panel.url {
            newDirectoryPath = url.path
        }
    }

    func saveSortOrder(_ keyPath: PartialKeyPath<IndexedFile>, order: SortOrder) {
        let sortName: String
        switch keyPath {
        case \IndexedFile.fileName: sortName = "fileName"
        case \IndexedFile.size: sortName = "size"
        case \IndexedFile.modDate: sortName = "modDate"
        case \IndexedFile.fullPath: sortName = "fullPath"
        default: sortName = "modDate"
        }
        let orderStr = order == .reverse ? "reverse" : "forward"
        UserDefaults.standard.set("\(sortName):\(orderStr)", forKey: sortOrderDefaultsKey)
    }
}

// MARK: - Finder Drag Source

struct FinderDragSourceOverlay: NSViewRepresentable {
    let file: IndexedFile
    @Binding var selectedIds: Set<Int64>
    let visibleFiles: [IndexedFile]

    func makeNSView(context: Context) -> FinderDragSourceView {
        FinderDragSourceView()
    }

    func updateNSView(_ nsView: FinderDragSourceView, context: Context) {
        nsView.file = file
        nsView.selectedIds = $selectedIds
        nsView.visibleFiles = visibleFiles
    }
}

final class FinderDragSourceView: NSView, NSDraggingSource {
    var file: IndexedFile?
    var selectedIds: Binding<Set<Int64>> = .constant([])
    var visibleFiles: [IndexedFile] = []

    private var mouseDownLocation: NSPoint?
    private var armedSelectedIds: Set<Int64> = []
    private var armedVisibleFiles: [IndexedFile] = []

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let event = NSApp.currentEvent {
            let isRightClick = event.type == .rightMouseDown
            let isControlClick = event.type == .leftMouseDown && event.modifierFlags.contains(.control)
            if isRightClick || isControlClick {
                return nil
            }
        }
        return bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let file else { return }
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        updateSelection(for: file, event: event)
        armedSelectedIds = selectedIds.wrappedValue
        armedVisibleFiles = visibleFiles
        focusEnclosingTable()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let file, let start = mouseDownLocation else { return }
        let location = convert(event.locationInWindow, from: nil)
        let distance = hypot(location.x - start.x, location.y - start.y)
        guard distance >= 3 else { return }

        beginFinderDrag(for: file, with: event)
        resetArmedDrag()
    }

    override func mouseUp(with event: NSEvent) {
        resetArmedDrag()
    }

    private func updateSelection(for file: IndexedFile, event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            if selectedIds.wrappedValue.contains(file.id) {
                selectedIds.wrappedValue.remove(file.id)
            } else {
                selectedIds.wrappedValue.insert(file.id)
            }
        } else if !selectedIds.wrappedValue.contains(file.id) {
            selectedIds.wrappedValue = [file.id]
        }
    }

    private func beginFinderDrag(for file: IndexedFile, with event: NSEvent) {
        let files: [IndexedFile]
        let dragSelectedIds = armedSelectedIds
        let dragVisibleFiles = armedVisibleFiles.isEmpty ? visibleFiles : armedVisibleFiles

        if dragSelectedIds.contains(file.id) {
            files = dragVisibleFiles.filter { dragSelectedIds.contains($0.id) }
        } else {
            files = [file]
        }

        let urls = files
            .filter { FileManager.default.fileExists(atPath: $0.fullPath) }
            .map { URL(fileURLWithPath: $0.fullPath) }
        guard !urls.isEmpty else { return }

        let dragPoint = convert(event.locationInWindow, from: nil)
        let items = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32)
            let offset = CGFloat(min(index, 4)) * 2
            let frame = NSRect(x: dragPoint.x - 16 + offset, y: dragPoint.y - 16 - offset, width: 32, height: 32)
            item.setDraggingFrame(frame, contents: icon)
            return item
        }

        let session = beginDraggingSession(with: items, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .stack
    }

    private func resetArmedDrag() {
        mouseDownLocation = nil
        armedSelectedIds = []
        armedVisibleFiles = []
    }

    private func focusEnclosingTable() {
        var view: NSView? = self
        while let current = view {
            if let tableView = current as? NSTableView {
                window?.makeFirstResponder(tableView)
                return
            }
            view = current.superview
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        false
    }
}

// MARK: - File Icon View

struct FileIconView: View {
    let filePath: String
    let fileName: String
    let isDirectory: Bool

    @State private var nsImage: NSImage?

    var body: some View {
        if isDirectory {
            Image(systemName: "folder.fill")
                .foregroundColor(.yellow).font(.system(size: 14))
        } else if let img = nsImage {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: quickLookSymbol)
                .foregroundColor(.secondary).font(.system(size: 12))
                .onAppear { loadIcon() }
        }
    }

    var quickLookSymbol: String {
        switch URL(fileURLWithPath: fileName).pathExtension.lowercased() {
        case "mp4", "mov", "avi", "mkv": return "play.rectangle"
        case "jpg", "jpeg", "png", "gif", "heic": return "photo"
        default: return "doc"
        }
    }

    func loadIcon() {
        DispatchQueue.global(qos: .userInitiated).async {
            let icon = NSWorkspace.shared.icon(forFile: filePath)
            DispatchQueue.main.async { self.nsImage = icon }
        }
    }
}

// MARK: - QuickLook Coordinator

final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookCoordinator()
    var previewURLs: [URL] = []
    private weak var panel: QLPreviewPanel?
    private weak var previousKeyWindow: NSWindow?

    var isPreviewVisible: Bool {
        panel?.isVisible == true
    }

    func showPreview(urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        if NSApp.keyWindow !== panel {
            previousKeyWindow = NSApp.keyWindow
        }
        self.panel = panel
        previewURLs = urls
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
    }

    func togglePreview(urls: [URL]) {
        if isPreviewVisible {
            closePreview()
        } else {
            showPreview(urls: urls)
        }
    }

    func closePreview() {
        panel?.orderOut(nil)
        previousKeyWindow?.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard previewURLs.indices.contains(index) else { return nil }
        return previewURLs[index] as QLPreviewItem
    }
}
