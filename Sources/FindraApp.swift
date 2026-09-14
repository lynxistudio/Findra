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

enum ViewMode: String, Codable, CaseIterable {
    case list = "list"
    case grid = "grid"
}

struct IndexedFile: Identifiable, Equatable, Hashable {
    var id: Int64 = 0
    var fileName: String
    var fullPath: String
    var parentPath: String = ""
    var size: Int64 = 0
    var modDate: Double = 0
    var creationDate: Double = 0
    var dirId: Int64 = 0
    var isDirectory: Bool = false

    var stableId: Int64 {
        if id != 0 { return id }
        return abs(Int64(bitPattern: UInt64(truncatingIfNeeded: fullPath.hashValue)))
    }

    var url: URL {
        URL(fileURLWithPath: fullPath)
    }

    var fileExtension: String {
        url.pathExtension.lowercased()
    }

    var isMediaFile: Bool {
        isImageFile || isVideoFile
    }

    var isImageFile: Bool {
        let imageExtensions: Set<String> = [
            "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "bmp", "raw", "cr2", "nef", "arw", "svg", "avif", "ico"
        ]
        return imageExtensions.contains(fileExtension)
    }

    var isVideoFile: Bool {
        let videoExtensions: Set<String> = [
            "mp4", "mov", "m4v", "avi", "mkv", "webm", "flv", "wmv"
        ]
        return videoExtensions.contains(fileExtension)
    }

    var isAudioFile: Bool {
        let audioExtensions: Set<String> = [
            "mp3", "wav", "m4a", "aac", "flac", "aiff", "ogg", "wma"
        ]
        return audioExtensions.contains(fileExtension)
    }

    var sizeFormatted: String {
        if isDirectory { return "—" }
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

    var creationDateFormatted: String {
        let timestamp = creationDate > 0 ? creationDate : modDate
        let date = Date(timeIntervalSince1970: timestamp)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        return fmt.string(from: date)
    }
}

// MARK: - Sort Field Options

enum SortField: String, CaseIterable, Identifiable {
    case modDate = "modDate"
    case creationDate = "creationDate"
    case size = "size"
    case duration = "duration"
    case fileName = "fileName"

    var id: String { rawValue }
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

    // Navigation & Folder Browsing
    @Published var currentDirectoryPath: String? = nil
    @Published var browsedFiles: [IndexedFile] = []
    @Published var backStack: [String] = []
    @Published var forwardStack: [String] = []
    @Published var viewMode: ViewMode = .list
    @Published var thumbnailSize: CGFloat = 110

    // Sorting State
    @Published var sortField: SortField = .modDate
    @Published var isSortAscending: Bool = false

    // Clipboard & Operations
    @Published var cutFilePaths: Set<String> = []
    @Published var copiedFilePaths: Set<String> = []

    let dbManager = DatabaseManager()
    let scanManager = ScanManager()
    lazy var searchManager = SearchManager(dbManager: dbManager)
    var locale: LocaleManager? = nil

    func setSortField(_ field: SortField) {
        if sortField == field {
            isSortAscending.toggle()
        } else {
            sortField = field
            switch field {
            case .modDate, .creationDate, .size, .duration:
                isSortAscending = false
            case .fileName:
                isSortAscending = true
            }
        }
        applyCurrentSort()
    }

    func toggleSortAscending() {
        isSortAscending.toggle()
        applyCurrentSort()
    }

    func sortFieldDisplayName(locale: LocaleManager) -> String {
        switch sortField {
        case .modDate: return locale.sortByModDate
        case .creationDate: return locale.sortByCreationDate
        case .size: return locale.sortBySize
        case .duration: return locale.sortByDuration
        case .fileName: return locale.sortByName
        }
    }

    func applyCurrentSort() {
        sortFilesList(&browsedFiles)
        sortFilesList(&searchResults)
    }

    func sortFilesList(_ files: inout [IndexedFile]) {
        files.sort { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }
            let isAsc = isSortAscending
            switch sortField {
            case .modDate:
                return isAsc ? a.modDate < b.modDate : a.modDate > b.modDate
            case .creationDate:
                let aDate = a.creationDate > 0 ? a.creationDate : a.modDate
                let bDate = b.creationDate > 0 ? b.creationDate : b.modDate
                return isAsc ? aDate < bDate : aDate > bDate
            case .size:
                return isAsc ? a.size < b.size : a.size > b.size
            case .duration:
                let aDur = MediaMetadataManager.shared.cachedMetadata(for: a.fullPath)?.duration ?? 0
                let bDur = MediaMetadataManager.shared.cachedMetadata(for: b.fullPath)?.duration ?? 0
                return isAsc ? aDur < bDur : aDur > bDur
            case .fileName:
                let order = a.fileName.localizedStandardCompare(b.fileName)
                return isAsc ? (order == .orderedAscending) : (order == .orderedDescending)
            }
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private var scanTimer: Timer?
    private var incrementalTimer: Timer?
    private var isInitialized = false

    var isSearchActive: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var visibleFiles: [IndexedFile] {
        if isSearchActive {
            return searchResults
        }
        return browsedFiles
    }

    var canNavigateBack: Bool {
        !backStack.isEmpty
    }

    var canNavigateForward: Bool {
        !forwardStack.isEmpty
    }

    var canNavigateUp: Bool {
        guard let current = currentDirectoryPath, current != "/", !current.isEmpty else { return false }
        return true
    }

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

        // Set initial browsing folder to the first indexed directory
        if currentDirectoryPath == nil, let firstDir = directories.first {
            navigateTo(path: firstDir.path, recordHistory: false)
        }
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
        var results = searchManager.search(query: q, limit: 10000)
        sortFilesList(&results)
        searchResults = results
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

    // MARK: - Navigation & Directory Browsing

    func navigateTo(path: String, recordHistory: Bool = true) {
        var cleanPath = path
        if cleanPath.count > 1 && cleanPath.hasSuffix("/") {
            cleanPath = String(cleanPath.dropLast())
        }
        guard FileManager.default.fileExists(atPath: cleanPath) else {
            statusText = locale?.unavailableFiles(1) ?? "Path unavailable: \(cleanPath)"
            return
        }

        if recordHistory, let current = currentDirectoryPath, current != cleanPath {
            backStack.append(current)
            forwardStack.removeAll()
        }

        currentDirectoryPath = cleanPath
        selectedFiles.removeAll()
        cancelEditing()
        loadCurrentDirectory()
    }

    func navigateBack() {
        guard let prev = backStack.popLast() else { return }
        if let current = currentDirectoryPath {
            forwardStack.append(current)
        }
        navigateTo(path: prev, recordHistory: false)
    }

    func navigateForward() {
        guard let next = forwardStack.popLast() else { return }
        if let current = currentDirectoryPath {
            backStack.append(current)
        }
        navigateTo(path: next, recordHistory: false)
    }

    func navigateUp() {
        guard let current = currentDirectoryPath, current != "/", !current.isEmpty else { return }
        let parent = URL(fileURLWithPath: current).deletingLastPathComponent().path
        if !parent.isEmpty && parent != current {
            navigateTo(path: parent)
        }
    }

    func refreshCurrentDirectory() {
        guard let current = currentDirectoryPath else { return }
        var liveItems = dbManager.getFileSystemItems(at: current)
        sortFilesList(&liveItems)
        browsedFiles = liveItems
        statusText = locale?.directoryRefreshed(count: liveItems.count) ?? "Refreshed \(liveItems.count) items"
    }

    func loadCurrentDirectory() {
        guard let current = currentDirectoryPath else {
            browsedFiles = []
            return
        }

        // 1. Fast cache path: load from indexed SQLite database in < 2ms
        var dbItems = dbManager.getFilesInDirectory(parentPath: current)
        if !dbItems.isEmpty {
            sortFilesList(&dbItems)
            browsedFiles = dbItems
            statusText = locale?.resultCount(dbItems.count) ?? "\(dbItems.count) items"
        }

        // 2. Direct filesystem read ensures real-time accuracy and covers unindexed folders
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var liveItems = self.dbManager.getFileSystemItems(at: current)
            self.sortFilesList(&liveItems)
            DispatchQueue.main.async {
                if self.currentDirectoryPath == current {
                    self.browsedFiles = liveItems
                    self.statusText = self.locale?.resultCount(liveItems.count) ?? "\(liveItems.count) items"
                }
            }
        }
    }

    // MARK: - File Operations & Clipboard

    func cutFiles(_ fileIds: Set<Int64>) {
        let files = visibleFiles.filter { fileIds.contains($0.id) || fileIds.contains($0.stableId) }
        let availableFiles = files.filter { FileManager.default.fileExists(atPath: $0.fullPath) }
        guard !availableFiles.isEmpty else { return }

        cutFilePaths = Set(availableFiles.map(\.fullPath))
        copiedFilePaths.removeAll()

        let urls = availableFiles.map { URL(fileURLWithPath: $0.fullPath) as NSURL }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls)
        pb.setString("cut", forType: NSPasteboard.PasteboardType("com.lynxistudio.findra.cut"))

        statusText = locale?.cutFiles(availableFiles.count) ?? "Cut \(availableFiles.count) file(s)"
    }

    func copyFiles(_ fileIds: Set<Int64>) {
        let files = visibleFiles.filter { fileIds.contains($0.id) || fileIds.contains($0.stableId) }
        let availableFiles = files.filter { FileManager.default.fileExists(atPath: $0.fullPath) }
        guard !availableFiles.isEmpty else {
            statusText = locale?.unavailableFiles(fileIds.count) ?? "Files unavailable"
            return
        }

        copiedFilePaths = Set(availableFiles.map(\.fullPath))
        cutFilePaths.removeAll()

        let urls = availableFiles.map { URL(fileURLWithPath: $0.fullPath) as NSURL }
        let pb = NSPasteboard.general
        pb.clearContents()
        guard pb.writeObjects(urls) else {
            statusText = locale?.copyFailed ?? "Could not copy files"
            return
        }

        statusText = locale?.copiedFiles(availableFiles.count) ?? "Copied \(availableFiles.count) file(s)"
        if availableFiles.count != files.count {
            statusText += " - " + (locale?.unavailableFiles(files.count - availableFiles.count) ?? "Some files unavailable")
        }
    }

    func pasteFiles(into targetPath: String? = nil) {
        let destPath = targetPath ?? currentDirectoryPath
        guard let dest = destPath, FileManager.default.fileExists(atPath: dest) else {
            statusText = "Cannot paste: destination folder unavailable"
            return
        }

        let pb = NSPasteboard.general
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else {
            return
        }

        let isCut = pb.string(forType: NSPasteboard.PasteboardType("com.lynxistudio.findra.cut")) == "cut" || !cutFilePaths.isEmpty
        let fm = FileManager.default
        var processedCount = 0

        for sourceURL in urls {
            let sourcePath = sourceURL.path
            let fileName = sourceURL.lastPathComponent
            let targetURL = uniqueDestinationURL(for: fileName, in: dest)

            do {
                if isCut {
                    try fm.moveItem(at: sourceURL, to: targetURL)
                    if let file = dbManager.getFileByPath(sourcePath) {
                        _ = dbManager.renameFile(fileId: file.id, newName: targetURL.lastPathComponent, newPath: targetURL.path)
                    }
                    processedCount += 1
                } else {
                    try fm.copyItem(at: sourceURL, to: targetURL)
                    processedCount += 1
                }
            } catch {
                print("Paste error: \(error.localizedDescription)")
            }
        }

        if isCut {
            cutFilePaths.removeAll()
            pb.setString("", forType: NSPasteboard.PasteboardType("com.lynxistudio.findra.cut"))
        }

        statusText = locale?.pastedFiles(processedCount) ?? "Pasted \(processedCount) item(s)"
        refreshCurrentDirectory()
        updateStats()
        refreshDirectoryIndexStats()
    }

    private func uniqueDestinationURL(for fileName: String, in directory: String) -> URL {
        let dirURL = URL(fileURLWithPath: directory, isDirectory: true)
        var targetURL = dirURL.appendingPathComponent(fileName)
        let fm = FileManager.default
        guard fm.fileExists(atPath: targetURL.path) else { return targetURL }

        let nameWithoutExt = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var counter = 2

        while fm.fileExists(atPath: targetURL.path) {
            let newName: String
            if ext.isEmpty {
                newName = "\(nameWithoutExt) \(counter)"
            } else {
                newName = "\(nameWithoutExt) \(counter).\(ext)"
            }
            targetURL = dirURL.appendingPathComponent(newName)
            counter += 1
        }
        return targetURL
    }

    func deleteFiles(_ fileIds: Set<Int64>) {
        let files = visibleFiles.filter { fileIds.contains($0.id) || fileIds.contains($0.stableId) }
        var deletedCount = 0
        for file in files {
            do {
                let url = URL(fileURLWithPath: file.fullPath)
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                if file.id != 0 {
                    dbManager.removeFileById(file.id)
                }
                deletedCount += 1
            } catch {
                print("删除失败: \(file.fullPath) - \(error)")
            }
        }
        statusText = locale?.deletedFiles(deletedCount) ?? "Moved \(deletedCount) item(s) to Trash"
        selectedFiles.removeAll()
        refreshCurrentDirectory()
        updateStats()
        refreshDirectoryIndexStats()
        if isSearchActive {
            performSearch()
        }
    }

    func renameFile(fileId: Int64, oldPath: String, newName: String) -> Bool {
        let fm = FileManager.default
        let oldUrl = URL(fileURLWithPath: oldPath)
        let newUrl = oldUrl.deletingLastPathComponent().appendingPathComponent(newName)
        let newPath = newUrl.path

        do {
            try fm.moveItem(at: oldUrl, to: newUrl)
            if fileId != 0 {
                _ = dbManager.renameFile(fileId: fileId, newName: newName, newPath: newPath)
            }
            refreshCurrentDirectory()
            if isSearchActive {
                performSearch()
            }
            return true
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

    func quickLookSelected() {
        let files = visibleFiles.filter { selectedFiles.contains($0.id) || selectedFiles.contains($0.stableId) }
        let available = files.filter { FileManager.default.fileExists(atPath: $0.fullPath) }
        guard !available.isEmpty else {
            statusText = locale?.unavailableFiles(selectedFiles.count) ?? "Files unavailable"
            return
        }
        let urls = available.map { URL(fileURLWithPath: $0.fullPath) }
        QuickLookCoordinator.shared.togglePreview(urls: urls)
    }

    func openSelectedFiles() {
        let files = visibleFiles.filter { selectedFiles.contains($0.id) || selectedFiles.contains($0.stableId) }
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
        editingFileId = file.id != 0 ? file.id : file.stableId
        editingFileName = file.fileName
    }

    func cancelEditing() {
        editingFileId = nil
        editingFileName = ""
    }

    func commitEditing() {
        guard let fileId = editingFileId, !editingFileName.isEmpty else { return }
        if let file = visibleFiles.first(where: { $0.id == fileId || $0.stableId == fileId }) {
            let success = renameFile(fileId: file.id, oldPath: file.fullPath, newName: editingFileName)
            if success {
                editingFileId = nil
                editingFileName = ""
            }
        }
    }
}
