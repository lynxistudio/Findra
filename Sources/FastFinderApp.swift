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

// MARK: - App Delegate (for menu bar and lifecycle)

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarItem: NSStatusItem?
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMenuBar()
        setupGlobalHotkey()
    }

    private func setupMenuBar() {
        menuBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = menuBarItem?.button {
            button.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "FastFinder")
            button.action = #selector(toggleWindow)
            button.target = self
        }
    }

    private func setupGlobalHotkey() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
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
        if window == nil {
            let contentView = NSHostingView(rootView: ContentView())
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window?.title = "FastFinder"
            window?.contentView = contentView
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - App Entry

@main
struct FastFinderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var localeManager = LocaleManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(localeManager)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
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

    func initialize(locale: LocaleManager) {
        self.locale = locale
        dbManager.setupDatabase()
        loadDirectories()
        loadExcludedPatterns()
        addDefaultExcludedPatterns()
        updateStats()
        setupSearch()
        startScheduledScans()
        startIncrementalScans()
        startFSEventWatchers()
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
        let dir = IndexDirectory(path: path, type: type, enabled: true)
        dbManager.addDirectory(dir)
        loadDirectories()
        scanDirectory(dir)
        updateStats()
        startFSEventWatcher(for: path)
    }

    func removeDirectory(_ dir: IndexDirectory) {
        stopWatchingForDirectory(dir)
        dbManager.removeDirectory(dir)
        loadDirectories()
        updateStats()
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
            guard let self = self else { return }
            let count = self.scanManager.scanDirectory(dir, dbManager: self.dbManager)
            DispatchQueue.main.async {
                self.isScanning = false
                self.scanProgress = ""
                let loc = self.locale
                self.statusText = loc?.scanComplete(path: dir.path, count: count) ?? "Scan complete: \(dir.path) (\(count) files)"
                self.updateStats()
                self.loadDirectories()
                if !self.searchQuery.isEmpty {
                    self.performSearch()
                }
            }
        }
    }

    func scanAllDirectories() {
        for dir in directories where dir.enabled {
            scanDirectory(dir)
        }
    }

    func rescanDirectory(_ dir: IndexDirectory) {
        dbManager.clearDirectoryFiles(dir)
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
        searchResults = searchManager.search(query: q, limit: 500)
        totalFileCount = dbManager.getTotalFileCount()
    }

    func updateStats() {
        totalFileCount = dbManager.getTotalFileCount()
    }

    private func startScheduledScans() {
        // Full scan for non-local directories every 5 minutes
        scanTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            for dir in self.directories where dir.enabled && dir.type != .local {
                self.scanDirectory(dir)
            }
        }
    }

    private func startIncrementalScans() {
        // Incremental scan for local directories every 1 minute
        incrementalTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            for dir in self.directories where dir.enabled && dir.type == .local {
                DispatchQueue.global(qos: .background).async {
                    _ = self.scanManager.scanDirectoryIncremental(dir, dbManager: self.dbManager)
                }
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
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.fullPath)])
    }

    func quickLookSelected() {
        let files = dbManager.getFilesByIds(selectedFiles)
        let urls = files.map { URL(fileURLWithPath: $0.fullPath) }
        QuickLookCoordinator.shared.previewURLs = urls
        if let panel = QLPreviewPanel.shared() {
            panel.dataSource = QuickLookCoordinator.shared
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func openSelectedFiles() {
        let files = dbManager.getFilesByIds(selectedFiles)
        for file in files {
            NSWorkspace.shared.open(URL(fileURLWithPath: file.fullPath))
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