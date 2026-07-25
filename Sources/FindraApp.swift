import SwiftUI
import Combine
import Quartz

// MARK: - Data Models

enum DirectoryType: String, Codable, CaseIterable {
    case local = "local"
    case nfs = "nfs"
    case smb = "smb"

    func displayName(_ locale: LocaleManager) -> String {
        switch self {
        case .local: return locale.localDrive
        case .nfs: return locale.nfsDrive
        case .smb: return locale.smbDrive
        }
    }
}

struct IndexDirectory: Identifiable, Codable, Equatable {
    var id: Int64 = 0
    var path: String
    var type: DirectoryType = .local
    var lastScanTime: Double = 0
    var enabled: Bool = true
}

struct IndexedFile: Identifiable, Equatable {
    var id: Int64 = 0
    var fileName: String
    var fullPath: String
    var size: Int64 = 0
    var modDate: Double = 0
    var dirId: Int64 = 0
    var isDirectory: Bool = false

    var sizeFormatted: String {
        if size < 1024 { return "\(size) B" }
        let kb = Double(size) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1024.0
        return String(format: "%.2f GB", gb)
    }

    var modDateFormatted: String {
        let date = Date(timeIntervalSince1970: modDate)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        return fmt.string(from: date)
    }
}

struct DirectoryIndexStats {
    var fileCount: Int = 0
    var folderCount: Int = 0
}

// MARK: - App Delegate (for menu bar and lifecycle)

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var menuBarItem: NSStatusItem?
    private var window: NSWindow?
    private var hotKeyMonitor: Any?
    private weak var appState: AppState?
    private weak var localeManager: LocaleManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMenuBar()
        setupGlobalHotkey()
    }

    private func setupMenuBar() {
        menuBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = menuBarItem?.button {
            button.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Findra")
            button.action = #selector(toggleWindow)
            button.target = self
        }
    }

    func configure(appState: AppState, localeManager: LocaleManager, window: NSWindow? = nil) {
        self.appState = appState
        self.localeManager = localeManager
        if let window {
            adoptMainWindow(window)
        }
    }

    private func setupGlobalHotkey() {
        hotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 49 { // space key
                self.toggleWindow()
            }
        }
    }

    @objc private func toggleWindow() {
        if let window = window, window.isVisible {
            window.orderOut(nil)
        } else {
            showWindow()
        }
    }

    private func showWindow() {
        guard let appState, let localeManager else { return }

        if window == nil {
            adoptExistingWindowIfAvailable()
        }

        if window == nil {
            let contentView = NSHostingView(
                rootView: ContentView()
                    .environmentObject(appState)
                    .environmentObject(localeManager)
            )
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window?.title = "Findra"
            window?.contentView = contentView
            window?.center()
            if let window {
                adoptMainWindow(window)
            }
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func adoptExistingWindowIfAvailable() {
        if let window = NSApp.windows.first(where: { $0.title == "Findra" && !($0 is NSPanel) }) {
            adoptMainWindow(window)
        }
    }

    private func adoptMainWindow(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        window.title = "Findra"
        window.identifier = NSUserInterfaceItemIdentifier("FindraMainWindow")
        window.isReleasedWhenClosed = false
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onResolve(window)
            }
        }
    }
}

// MARK: - App Entry

@main
struct FindraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var localeManager = LocaleManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(localeManager)
                .frame(minWidth: 900, minHeight: 600)
                .background(
                    WindowAccessor { window in
                        appDelegate.configure(appState: appState, localeManager: localeManager, window: window)
                    }
                )
                .onAppear {
                    appDelegate.configure(appState: appState, localeManager: localeManager)
                    appState.initialize(locale: localeManager)
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

// MARK: - Global App State

final class AppState: ObservableObject {
    @Published var directories: [IndexDirectory] = []
    @Published var excludedPatterns: [String] = []
    @Published var searchResults: [IndexedFile] = []
    @Published var searchQuery: String = ""
    @Published var totalFileCount: Int = 0
    @Published var directoryIndexStats: [Int64: DirectoryIndexStats] = [:]
    @Published var isScanning: Bool = false
    @Published var scanProgress: String = ""
    @Published var statusText: String = "Ready"
    @Published var selectedFiles: Set<Int64> = []
    @Published var editingFileId: Int64? = nil
    @Published var editingFileName: String = ""

    let dbManager = DatabaseManager()
    let scanManager = ScanManager()
    lazy var searchManager = SearchManager(dbManager: dbManager)
    var locale: LocaleManager? = nil

    private var cancellables = Set<AnyCancellable>()
    private var scanTimer: Timer?
    private var incrementalTimer: Timer?
    private var isInitialized = false

    func initialize(locale: LocaleManager) {
        guard !isInitialized else { return }
        isInitialized = true

        self.locale = locale
        dbManager.setupDatabase()
        loadDirectories()
        removeRedundantNestedDirectories()
        loadDirectories()
        loadExcludedPatterns()
        addDefaultExcludedPatterns()
        updateStats()
        refreshDirectoryIndexStats()
        setupSearch()
        startScheduledScans()
        startIncrementalScans()
        startFSEventWatchers()
        // Rebuild every configured root in the background after launch. Search remains database-only.
        scanAllDirectories()
    }

    func loadDirectories() {
        directories = dbManager.getAllDirectories()
    }

    func loadExcludedPatterns() {
        excludedPatterns = dbManager.getAllExcludedPatterns()
    }

    func addDefaultExcludedPatterns() {
        for pattern in ScanManager.defaultExcludedPatterns {
            dbManager.addExcludedPattern(pattern)
        }
        loadExcludedPatterns()
    }

    func addExcludedPattern(_ pattern: String) {
        dbManager.addExcludedPattern(pattern)
        loadExcludedPatterns()
    }

    func removeExcludedPattern(_ pattern: String) {
        dbManager.removeExcludedPattern(pattern)
        loadExcludedPatterns()
    }

    func addDirectory(_ path: String, type: DirectoryType) {
        if directories.contains(where: { path == $0.path || path.hasPrefix($0.path + "/") }) {
            statusText = locale?.directoryAlreadyCovered(path: path) ?? "Directory is already covered by an indexed parent"
            return
        }

        let dir = IndexDirectory(path: path, type: type, enabled: true)
        dbManager.addDirectory(dir)
        dbManager.removeDirectoriesNestedWithin(path)
        loadDirectories()
        if let storedDirectory = directories.first(where: { $0.path == path }) {
            scanDirectory(storedDirectory)
        }
        refreshDirectoryIndexStats()
        updateStats()
        startFSEventWatcher(for: path)
    }

    private func removeRedundantNestedDirectories() {
        let sortedDirectories = directories.sorted { $0.path.count < $1.path.count }
        for directory in sortedDirectories {
            dbManager.removeDirectoriesNestedWithin(directory.path)
        }
    }

    func removeDirectory(_ dir: IndexDirectory) {
        stopWatchingForDirectory(dir)
        dbManager.removeDirectory(dir)
        loadDirectories()
        updateStats()
        refreshDirectoryIndexStats()
    }

    func stopWatchingForDirectory(_ dir: IndexDirectory) {
        scanManager.stopWatching(path: dir.path)
    }

    func scanDirectory(_ dir: IndexDirectory) {
        guard dir.enabled else { return }
        isScanning = true
        let loc = locale
        scanProgress = loc?.scanning(dir.path) ?? "Scanning: \(dir.path)"

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.runDirectoryScan(dir)
        }
    }

    private func runDirectoryScan(_ dir: IndexDirectory) {
        let result = scanManager.scanDirectory(dir, dbManager: dbManager)
        DispatchQueue.main.async { [weak self] in
            self?.finishScan(result, for: dir)
        }
    }

    private func finishScan(_ result: DirectoryScanResult, for dir: IndexDirectory) {
        isScanning = false
        scanProgress = ""
        let loc = locale
        if result.isAlreadyRunning {
            statusText = loc?.scanAlreadyRunning(path: dir.path) ?? "Scan already running: \(dir.path)"
        } else if result.isSuccess {
            statusText = loc?.scanComplete(path: dir.path, count: result.count) ?? "Scan complete: \(dir.path) (\(result.count) files)"
        } else {
            statusText = loc?.scanFailed(path: dir.path, reason: result.errorMessage ?? "Unknown error") ?? "Scan incomplete: \(dir.path)"
        }
        updateStats()
        loadDirectories()
        refreshDirectoryIndexStats()
        if !searchQuery.isEmpty {
            performSearch()
        }
    }

    func scanAllDirectories() {
        for dir in directories where dir.enabled {
            scanDirectory(dir)
        }
    }

    func rescanDirectory(_ dir: IndexDirectory) {
        scanDirectory(dir)
    }

    private func setupSearch() {
        $searchQuery
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.performSearch()
            }
            .store(in: &cancellables)
    }

    func performSearch() {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            searchResults = []
            return
        }
        searchResults = searchManager.search(query: q, limit: 10000)
        totalFileCount = dbManager.getTotalFileCount()
    }

    func updateStats() {
        totalFileCount = dbManager.getTotalFileCount()
    }

    func refreshDirectoryIndexStats() {
        directoryIndexStats = dbManager.getDirectoryIndexStats()
    }

    private func startScheduledScans() {
        // Reconcile network volumes regularly. Queries remain index-only and never wait for this work.
        scanTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            for dir in self.directories where dir.enabled && dir.type != .local {
                self.scanDirectory(dir)
            }
        }
    }

    private func startIncrementalScans() {
        // A complete local reconciliation catches moved or copied folders that FSEvents cannot expand recursively.
        incrementalTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            for dir in self.directories where dir.enabled && dir.type == .local {
                self.scanDirectory(dir)
            }
        }
    }

    func startFSEventWatchers() {
        for dir in directories where dir.enabled && dir.type == .local {
            startFSEventWatcher(for: dir.path)
        }
    }

    func startFSEventWatcher(for path: String) {
        scanManager.startWatching(path: path) { [weak self] changedPath in
            guard let self = self else { return }
            self.scanManager.handleFileSystemEvent(path: changedPath, dbManager: self.dbManager)
            if !self.searchQuery.isEmpty {
                DispatchQueue.main.async {
                    self.performSearch()
                }
            }
        }
    }

    // MARK: - File Operations

    func deleteFiles(_ fileIds: Set<Int64>) {
        let files = dbManager.getFilesByIds(fileIds)
        for file in files {
            do {
                let url = URL(fileURLWithPath: file.fullPath)
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                dbManager.removeFileById(file.id)
            } catch {
                print("删除失败: \(file.fullPath) - \(error)")
            }
        }
        updateStats()
        refreshDirectoryIndexStats()
        performSearch()
    }

    func renameFile(fileId: Int64, oldPath: String, newName: String) -> Bool {
        let fm = FileManager.default
        let oldUrl = URL(fileURLWithPath: oldPath)
        let newUrl = oldUrl.deletingLastPathComponent().appendingPathComponent(newName)
        let newPath = newUrl.path

        do {
            try fm.moveItem(at: oldUrl, to: newUrl)
            let success = dbManager.renameFile(fileId: fileId, newName: newName, newPath: newPath)
            if success {
                performSearch()
                return true
            } else {
                // Rollback
                try? fm.moveItem(at: newUrl, to: oldUrl)
                return false
            }
        } catch {
            print("重命名失败: \(oldPath) -> \(newName) - \(error)")
            return false
        }
    }

    func revealInFinder(_ file: IndexedFile) {
        guard FileManager.default.fileExists(atPath: file.fullPath) else {
            statusText = locale?.unavailableFiles(1) ?? "File unavailable"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.fullPath)])
    }

    func copyFiles(_ fileIds: Set<Int64>) {
        let files = dbManager.getFilesByIds(fileIds)
        let availableFiles = files.filter { FileManager.default.fileExists(atPath: $0.fullPath) }
        guard !availableFiles.isEmpty else {
            statusText = locale?.unavailableFiles(files.count) ?? "Files unavailable"
            return
        }

        let urls = availableFiles.map { URL(fileURLWithPath: $0.fullPath) as NSURL }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects(urls) else {
            statusText = locale?.copyFailed ?? "Could not copy files"
            return
        }

        statusText = locale?.copiedFiles(availableFiles.count) ?? "Copied \(availableFiles.count) file(s)"
        if availableFiles.count != files.count {
            statusText += " - " + (locale?.unavailableFiles(files.count - availableFiles.count) ?? "Some files unavailable")
        }
    }

    func quickLookSelected() {
        let files = dbManager.getFilesByIds(selectedFiles).filter {
            FileManager.default.fileExists(atPath: $0.fullPath)
        }
        guard !files.isEmpty else {
            statusText = locale?.unavailableFiles(selectedFiles.count) ?? "Files unavailable"
            return
        }
        let urls = files.map { URL(fileURLWithPath: $0.fullPath) }
        QuickLookCoordinator.shared.showPreview(urls: urls)
    }

    func openSelectedFiles() {
        let files = dbManager.getFilesByIds(selectedFiles)
        var unavailableCount = 0
        for file in files {
            if FileManager.default.fileExists(atPath: file.fullPath) {
                NSWorkspace.shared.open(URL(fileURLWithPath: file.fullPath))
            } else {
                unavailableCount += 1
            }
        }
        if unavailableCount > 0 {
            statusText = locale?.unavailableFiles(unavailableCount) ?? "Files unavailable"
        }
    }

    func startEditingFile(_ file: IndexedFile) {
        editingFileId = file.id
        editingFileName = file.fileName
    }

    func cancelEditing() {
        editingFileId = nil
        editingFileName = ""
    }

    func commitEditing() {
        guard let fileId = editingFileId, !editingFileName.isEmpty else { return }
        if let file = dbManager.getFilesByIds([fileId]).first {
            let success = renameFile(fileId: fileId, oldPath: file.fullPath, newName: editingFileName)
            if success {
                editingFileId = nil
                editingFileName = ""
            }
        }
    }
}
