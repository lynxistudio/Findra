import SwiftUI
import AppKit
import Quartz
import UniformTypeIdentifiers

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
    @State private var renameValue: String = ""
    @State private var isExcludedExpanded = false
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isRenameFocused: Bool

    init() {
        if let savedSort = UserDefaults.standard.string(forKey: "FastFinderSortOrder") {
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
        .onAppear { isSearchFocused = true }
        .onChange(of: appState.editingFileId) { _, newId in
            if let id = newId {
                if let file = appState.searchResults.first(where: { $0.id == id }) {
                    renameValue = file.fileName
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isRenameFocused = true
                }
            }
        }
        .onChange(of: isRenameFocused) { _, focused in
            if !focused { appState.cancelEditing() }
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
                    // Icon — draggable (small target, won't block row selection)
                    FileIconView(filePath: file.fullPath, fileName: file.fileName, isDirectory: file.isDirectory)
                        .frame(width: 18, height: 18)
                        .onDrag {
                            let url = URL(fileURLWithPath: file.fullPath)
                            return NSItemProvider(object: url as NSURL)
                        }

                    if appState.editingFileId == file.id {
                        TextField("", text: $renameValue)
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
            Button(locale.showInFinder) { appState.revealInFinder(files[0]) }
            Button(locale.quickLook) { quickLookSingle(files[0]) }
            Divider()
            Button(locale.open) {
                NSWorkspace.shared.open(URL(fileURLWithPath: files[0].fullPath))
            }
            Divider()
            Button(locale.moveToTrash, role: .destructive) { appState.deleteFiles(ids) }
        } else if !ids.isEmpty {
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
        QuickLookCoordinator.shared.previewURLs = [URL(fileURLWithPath: file.fullPath)]
        if let panel = QLPreviewPanel.shared() {
            panel.dataSource = QuickLookCoordinator.shared
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func quickLookSelected() {
        let files = appState.dbManager.getFilesByIds(appState.selectedFiles)
        QuickLookCoordinator.shared.previewURLs = files.map { URL(fileURLWithPath: $0.fullPath) }
        if let panel = QLPreviewPanel.shared() {
            panel.dataSource = QuickLookCoordinator.shared
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func openSelectedFiles() {
        let files = appState.dbManager.getFilesByIds(appState.selectedFiles)
        for f in files {
            NSWorkspace.shared.open(URL(fileURLWithPath: f.fullPath))
        }
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
        UserDefaults.standard.set("\(sortName):\(orderStr)", forKey: "FastFinderSortOrder")
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

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURLs[index] as QLPreviewItem
    }
}