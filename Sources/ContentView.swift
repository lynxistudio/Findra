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
                navigationToolbar
                searchBar
                resultsArea
                statusBar
            }
            .frame(minWidth: 500)
        }
        .onAppear {
            isSearchFocused = false
            installResultsKeyMonitor()
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { !($0 is NSPanel) }) {
                    window.center()
                    window.makeKeyAndOrderFront(nil)
                }
            }
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
        .onChange(of: appState.visibleFiles) { _, files in
            let visibleIds = Set(files.map { $0.id != 0 ? $0.id : $0.stableId })
            appState.selectedFiles.formIntersection(visibleIds)
        }
        .onChange(of: appState.selectedFiles) { _, newSelection in
            guard QuickLookCoordinator.shared.isPreviewVisible else { return }
            if newSelection.isEmpty {
                QuickLookCoordinator.shared.closePreview()
                return
            }
            let files = appState.visibleFiles.filter { newSelection.contains($0.id) || newSelection.contains($0.stableId) }
            let available = files.filter { FileManager.default.fileExists(atPath: $0.fullPath) }
            if !available.isEmpty {
                QuickLookCoordinator.shared.updatePreview(urls: available.map { URL(fileURLWithPath: $0.fullPath) })
            }
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
                    let isSelected = appState.currentDirectoryPath == dir.path
                    HStack(spacing: 4) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(URL(fileURLWithPath: dir.path).lastPathComponent)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                .foregroundColor(isSelected ? .accentColor : .primary)
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
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.navigateTo(path: dir.path)
                    }
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

    // MARK: - Navigation Toolbar

    var navigationToolbar: some View {
        HStack(spacing: 8) {
            // Navigation Back / Forward / Up
            HStack(spacing: 4) {
                Button {
                    appState.navigateBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(!appState.canNavigateBack)
                .opacity(appState.canNavigateBack ? 1.0 : 0.35)
                .help(locale.back + " (Cmd+[)")

                Button {
                    appState.navigateForward()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(!appState.canNavigateForward)
                .opacity(appState.canNavigateForward ? 1.0 : 0.35)
                .help(locale.forward + " (Cmd+])")

                Button {
                    appState.navigateUp()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(!appState.canNavigateUp)
                .opacity(appState.canNavigateUp ? 1.0 : 0.35)
                .help(locale.parentDirectory + " (Cmd+Up)")
            }

            Divider().frame(height: 16)

            // Interactive Breadcrumb Path Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    if let currentPath = appState.currentDirectoryPath {
                        let segments = pathSegments(for: currentPath)
                        ForEach(segments.indices, id: \.self) { idx in
                            let seg = segments[idx]
                            Button {
                                appState.navigateTo(path: seg.path)
                            } label: {
                                HStack(spacing: 3) {
                                    if idx == 0 {
                                        Image(systemName: "internaldrive")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    Text(seg.name)
                                        .font(.system(size: 11, weight: idx == segments.count - 1 ? .semibold : .regular))
                                        .foregroundColor(idx == segments.count - 1 ? .primary : .secondary)
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.secondary.opacity(0.08))
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(locale.copyPath) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(seg.path, forType: .string)
                                }
                                Button(locale.showInFinder) {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: seg.path)])
                                }
                            }

                            if idx < segments.count - 1 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundColor(.secondary.opacity(0.4))
                            }
                        }
                    } else {
                        Text(locale.emptyPrompt)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            // Force Refresh Button (F5 / Cmd+R)
            Button {
                appState.refreshCurrentDirectory()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(locale.refresh + " (Cmd+R / F5)")

            Divider().frame(height: 14)

            // Sort Menu Button (Placed neatly right next to view mode switcher)
            Menu {
                Button {
                    appState.setSortField(.modDate)
                } label: {
                    HStack {
                        Text(locale.sortByModDate)
                        if appState.sortField == .modDate { Image(systemName: "checkmark") }
                    }
                }
                Button {
                    appState.setSortField(.creationDate)
                } label: {
                    HStack {
                        Text(locale.sortByCreationDate)
                        if appState.sortField == .creationDate { Image(systemName: "checkmark") }
                    }
                }
                Button {
                    appState.setSortField(.size)
                } label: {
                    HStack {
                        Text(locale.sortBySize)
                        if appState.sortField == .size { Image(systemName: "checkmark") }
                    }
                }
                Button {
                    appState.setSortField(.duration)
                } label: {
                    HStack {
                        Text(locale.sortByDuration)
                        if appState.sortField == .duration { Image(systemName: "checkmark") }
                    }
                }
                Button {
                    appState.setSortField(.fileName)
                } label: {
                    HStack {
                        Text(locale.sortByName)
                        if appState.sortField == .fileName { Image(systemName: "checkmark") }
                    }
                }

                Divider()

                Button {
                    appState.toggleSortAscending()
                } label: {
                    HStack {
                        Text(appState.isSortAscending ? locale.sortAscending : locale.sortDescending)
                        Image(systemName: appState.isSortAscending ? "arrow.up" : "arrow.down")
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 10))
                    Text(appState.sortFieldDisplayName(locale: locale))
                        .font(.system(size: 11))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.08)))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(locale.sortOrderHelp)

            // View Mode Switcher
            HStack(spacing: 2) {
                Button {
                    appState.viewMode = .list
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 11))
                        .padding(4)
                        .background(appState.viewMode == .list ? Color.accentColor.opacity(0.18) : Color.clear)
                        .cornerRadius(4)
                        .foregroundColor(appState.viewMode == .list ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(locale.listView)

                Button {
                    appState.viewMode = .grid
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 11))
                        .padding(4)
                        .background(appState.viewMode == .grid ? Color.accentColor.opacity(0.18) : Color.clear)
                        .cornerRadius(4)
                        .foregroundColor(appState.viewMode == .grid ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(locale.gridView)
            }

            // Thumbnail Zoom Slider
            if appState.viewMode == .grid {
                Slider(value: $appState.thumbnailSize, in: 80...200)
                    .frame(width: 65)
                    .help(locale.thumbnailSize)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
    }

    struct PathSegment: Identifiable {
        var id: String { path }
        let name: String
        let path: String
    }

    func pathSegments(for fullPath: String) -> [PathSegment] {
        let components = fullPath.split(separator: "/").map(String.init)
        guard !components.isEmpty else {
            return [PathSegment(name: "/", path: "/")]
        }

        var result: [PathSegment] = []
        var currentAccum = ""
        for comp in components {
            currentAccum += "/" + comp
            result.append(PathSegment(name: comp, path: currentAccum))
        }
        return result
    }

    // MARK: - Search Bar

    var searchBar: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary).padding(.leading, 10)
            TextField(locale.searchPlaceholder, text: $appState.searchQuery)
                .textFieldStyle(.plain).font(.system(size: 13))
                .focused($isSearchFocused)
                .padding(.vertical, 6).padding(.horizontal, 6)
            if !appState.searchQuery.isEmpty {
                Button {
                    appState.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }.buttonStyle(.plain).padding(.trailing, 8)
            }
        }
        .background(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    // MARK: - Results Area

    var resultsArea: some View {
        Group {
            if appState.isSearchActive {
                if appState.searchResults.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28)).foregroundColor(.secondary.opacity(0.4))
                        Text(locale.noResults).font(.body).foregroundColor(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    fileContainerView(for: appState.searchResults)
                }
            } else {
                if appState.browsedFiles.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 32)).foregroundColor(.secondary.opacity(0.4))
                        Text(locale.emptyFolder).font(.body).foregroundColor(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    fileContainerView(for: appState.browsedFiles)
                }
            }
        }
    }

    @ViewBuilder
    func fileContainerView(for files: [IndexedFile]) -> some View {
        if appState.viewMode == .grid {
            FileGridView(
                files: files,
                selectedIds: $appState.selectedFiles,
                isRenameFocused: $isRenameFocused,
                onDoubleClick: { file in
                    if file.isDirectory {
                        appState.navigateTo(path: file.fullPath)
                    } else {
                        NSWorkspace.shared.open(URL(fileURLWithPath: file.fullPath))
                    }
                }
            )
        } else {
            resultsTable(for: files)
        }
    }

    @ViewBuilder
    private func tableDragOverlay(for file: IndexedFile, visibleFiles: [IndexedFile]) -> some View {
        FileDragSourceOverlay(
            file: file,
            selectedIds: $appState.selectedFiles,
            visibleFiles: visibleFiles,
            onDoubleClick: {
                if file.isDirectory {
                    appState.navigateTo(path: file.fullPath)
                } else {
                    NSWorkspace.shared.open(file.url)
                }
            }
        )
    }

    func resultsTable(for files: [IndexedFile]) -> some View {
        Table(files, selection: $appState.selectedFiles, sortOrder: $sortOrder) {
            TableColumn(locale.tableFileName, value: \.fileName) { file in
                let fileKey = file.id != 0 ? file.id : file.stableId
                let isEditingThis = appState.editingFileId == fileKey
                HStack(spacing: 6) {
                    FileIconView(filePath: file.fullPath, fileName: file.fileName, isDirectory: file.isDirectory)
                        .frame(width: 18, height: 18)

                    if isEditingThis {
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
                .opacity(appState.cutFilePaths.contains(file.fullPath) ? 0.45 : 1.0)
                .overlay {
                    if !isEditingThis {
                        tableDragOverlay(for: file, visibleFiles: files)
                    }
                }
            }
            .width(ideal: 300)

            TableColumn(locale.resolution) { file in
                ResolutionTableCell(file: file)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay { tableDragOverlay(for: file, visibleFiles: files) }
            }.width(min: 80, ideal: 95)

            TableColumn(locale.duration) { file in
                DurationTableCell(file: file)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay { tableDragOverlay(for: file, visibleFiles: files) }
            }.width(min: 55, ideal: 70)

            TableColumn(locale.tableSize, value: \.size) { file in
                Text(file.sizeFormatted)
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .overlay { tableDragOverlay(for: file, visibleFiles: files) }
            }.width(min: 75, ideal: 90)

            TableColumn(locale.tableModDate, value: \.modDate) { file in
                Text(file.modDateFormatted)
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay { tableDragOverlay(for: file, visibleFiles: files) }
            }.width(min: 110, ideal: 130)

            TableColumn(locale.tableCreationDate, value: \.creationDate) { file in
                Text(file.creationDateFormatted)
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay { tableDragOverlay(for: file, visibleFiles: files) }
            }.width(min: 110, ideal: 130)

            TableColumn(locale.tablePath) { file in
                Text(file.fullPath)
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay { tableDragOverlay(for: file, visibleFiles: files) }
            }.width(ideal: 300)
        }
        .onChange(of: sortOrder) { _, newValue in
            if appState.isSearchActive {
                appState.searchResults.sort(using: newValue)
            } else {
                appState.browsedFiles.sort(using: newValue)
            }
            if let first = newValue.first {
                saveSortOrder(first.keyPath, order: first.order)
            }
        }
        .contextMenu(forSelectionType: Int64.self) { selectedIds in
            contextMenu(for: selectedIds, in: files)
        }
        .onKeyPress(.return) {
            if appState.editingFileId != nil {
                appState.commitEditing()
                return .handled
            }
            // Enter on selected folder navigates into it; on selected file enters rename
            if appState.selectedFiles.count == 1,
               let id = appState.selectedFiles.first,
               let file = files.first(where: { $0.id == id || $0.stableId == id }) {
                if file.isDirectory {
                    appState.navigateTo(path: file.fullPath)
                    return .handled
                } else {
                    appState.startEditingFile(file)
                    return .handled
                }
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
    func contextMenu(for selectedIds: Set<Int64>, in files: [IndexedFile]) -> some View {
        let ids = selectedIds.isEmpty ? appState.selectedFiles : selectedIds
        let targetFiles = files.filter { ids.contains($0.id) || ids.contains($0.stableId) }

        if targetFiles.count == 1 {
            let single = targetFiles[0]
            if single.isDirectory {
                Button(locale.open) { appState.navigateTo(path: single.fullPath) }
            } else {
                Button(locale.open) { openFiles([single]) }
                Button(locale.quickLook) { quickLookFiles([single]) }
            }
            Divider()
            Button(locale.rename) { appState.startEditingFile(single) }
            Button(locale.copy) { appState.copyFiles(ids) }
            Button(locale.cut) { appState.cutFiles(ids) }
            Button(locale.paste) { appState.pasteFiles() }
            Divider()
            Button(locale.copyPath) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(single.fullPath, forType: .string)
            }
            Button(locale.showInFinder) { appState.revealInFinder(single) }
            Divider()
            Button(locale.moveToTrash, role: .destructive) { appState.deleteFiles(ids, immediately: false) }
            Button(locale.deleteImmediately, role: .destructive) { appState.deleteFiles(ids, immediately: true) }
        } else if !ids.isEmpty {
            Button(locale.copy) { appState.copyFiles(ids) }
            Button(locale.cut) { appState.cutFiles(ids) }
            Button(locale.quickLook) { quickLookFiles(targetFiles) }
            Button(locale.open) { openFiles(targetFiles) }
            Divider()
            Button(locale.moveToTrash, role: .destructive) { appState.deleteFiles(ids, immediately: false) }
            Button(locale.deleteImmediately, role: .destructive) { appState.deleteFiles(ids, immediately: true) }
        } else {
            Button(locale.paste) { appState.pasteFiles() }
            Button(locale.refresh) { appState.refreshCurrentDirectory() }
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
            Text(locale.resultCount(appState.visibleFiles.count))
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
        let files = availableFiles(from: appState.visibleFiles.filter { appState.selectedFiles.contains($0.id) || appState.selectedFiles.contains($0.stableId) })
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
        let files = appState.visibleFiles.filter { appState.selectedFiles.contains($0.id) || appState.selectedFiles.contains($0.stableId) }
        openFiles(files)
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

            let isTextActive: Bool = {
                if let responder = event.window?.firstResponder {
                    if responder is NSTextView || responder is NSTextField {
                        return true
                    }
                }
                return self.isSearchFocused || self.appState.editingFileId != nil
            }()

            // When editing text (Search field, Inline rename, Sheets, etc.):
            // Never hijack text editing shortcuts (Cmd+V, Cmd+C, Cmd+X, Cmd+A, Cmd+Z, plain typing)
            if isTextActive {
                if appState.editingFileId != nil {
                    return event
                }
                // Spacebar with selected files triggers Quick Look only when search query is empty
                if event.keyCode == 49, modifiers.isEmpty, !appState.selectedFiles.isEmpty, appState.searchQuery.isEmpty {
                    event.window?.makeFirstResponder(nil)
                    self.isSearchFocused = false
                    self.quickLookSelected()
                    return nil
                }
                // Down arrow from search field focuses results / selects first file
                if event.keyCode == 125, modifiers.isEmpty { // Down Arrow
                    event.window?.makeFirstResponder(nil)
                    self.isSearchFocused = false
                    if appState.selectedFiles.isEmpty, let first = appState.visibleFiles.first {
                        appState.selectedFiles = [first.id != 0 ? first.id : first.stableId]
                    }
                    return nil
                }
                // Cmd+R or F5 (Refresh)
                if (modifiers == [.command] && event.charactersIgnoringModifiers?.lowercased() == "r") || event.keyCode == 96 {
                    appState.refreshCurrentDirectory()
                    return nil
                }
                // Escape clears search field focus
                if event.keyCode == 53 { // Escape
                    event.window?.makeFirstResponder(nil)
                    self.isSearchFocused = false
                    return nil
                }

                // Forward all other events (Cmd+V paste, Cmd+C copy, Cmd+X cut, Cmd+A select all, Cmd+Z undo, typing, etc.) directly to the text field!
                return event
            }

            // MARK: - File Browser Shortcuts (Only active when NOT editing text)

            // Cmd+A (Select All Files)
            if modifiers == [.command], event.charactersIgnoringModifiers?.lowercased() == "a" {
                let allIds = appState.visibleFiles.map { $0.id != 0 ? $0.id : $0.stableId }
                appState.selectedFiles = Set(allIds)
                return nil
            }

            // Cmd+X (Cut Files)
            if modifiers == [.command], event.charactersIgnoringModifiers?.lowercased() == "x" {
                guard !appState.selectedFiles.isEmpty else { return event }
                appState.cutFiles(appState.selectedFiles)
                return nil
            }

            // Cmd+C (Copy Files)
            if modifiers == [.command], event.charactersIgnoringModifiers?.lowercased() == "c" {
                guard !appState.selectedFiles.isEmpty else { return event }
                appState.copyFiles(appState.selectedFiles)
                return nil
            }

            // Cmd+V (Paste Files)
            if modifiers == [.command], event.charactersIgnoringModifiers?.lowercased() == "v" {
                appState.pasteFiles()
                return nil
            }

            // Cmd+R or F5 (Refresh) - F5 keycode is 96
            if (modifiers == [.command] && event.charactersIgnoringModifiers?.lowercased() == "r") || event.keyCode == 96 {
                appState.refreshCurrentDirectory()
                return nil
            }

            // Cmd+[ (Navigate Back)
            if modifiers == [.command], event.charactersIgnoringModifiers == "[" {
                appState.navigateBack()
                return nil
            }

            // Cmd+] (Navigate Forward)
            if modifiers == [.command], event.charactersIgnoringModifiers == "]" {
                appState.navigateForward()
                return nil
            }

            // Cmd+Up (Navigate Up) - KeyCode 126
            if modifiers == [.command], event.keyCode == 126 {
                appState.navigateUp()
                return nil
            }

            // Cmd+Option+Delete (Delete Immediately) - KeyCode 51
            if modifiers.contains(.command), modifiers.contains(.option), event.keyCode == 51 {
                guard !appState.selectedFiles.isEmpty else { return event }
                appState.deleteFiles(appState.selectedFiles, immediately: true)
                return nil
            }

            // Cmd+Delete (Move to Trash) - KeyCode 51
            if modifiers == [.command], event.keyCode == 51 {
                guard !appState.selectedFiles.isEmpty else { return event }
                appState.deleteFiles(appState.selectedFiles, immediately: false)
                return nil
            }

            // Spacebar (Quick Look) - KeyCode 49
            if event.keyCode == 49 {
                guard !modifiers.contains(.command),
                      !modifiers.contains(.control),
                      !modifiers.contains(.option) else { return event }

                if QuickLookCoordinator.shared.isPreviewVisible {
                    QuickLookCoordinator.shared.closePreview()
                    return nil
                }

                guard !appState.selectedFiles.isEmpty else { return event }
                quickLookSelected()
                return nil
            }

            // Quick Look following selection with Arrow keys (123 Left, 124 Right, 125 Down, 126 Up)
            if QuickLookCoordinator.shared.isPreviewVisible, [123, 124, 125, 126].contains(event.keyCode) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    let files = appState.visibleFiles.filter { appState.selectedFiles.contains($0.id) || appState.selectedFiles.contains($0.stableId) }
                    let available = files.filter { FileManager.default.fileExists(atPath: $0.fullPath) }
                    if !available.isEmpty {
                        QuickLookCoordinator.shared.showPreview(urls: available.map { URL(fileURLWithPath: $0.fullPath) })
                    }
                }
            }

            return event
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
        let wasVisible = isPreviewVisible
        if !wasVisible && NSApp.keyWindow !== panel {
            previousKeyWindow = NSApp.keyWindow
        }
        self.panel = panel
        previewURLs = urls
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        if !wasVisible {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func updatePreview(urls: [URL]) {
        guard isPreviewVisible, !urls.isEmpty, let panel = panel ?? QLPreviewPanel.shared() else { return }
        self.panel = panel
        previewURLs = urls
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
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

// MARK: - Resolution and Duration Table Cells

struct ResolutionTableCell: View {
    let file: IndexedFile
    @State private var resolution: String? = nil

    var body: some View {
        Text(resolution ?? "—")
            .font(.system(size: 11))
            .foregroundColor(resolution != nil ? .cyan : .secondary.opacity(0.4))
            .onAppear {
                guard file.isMediaFile else { return }
                if let cached = MediaMetadataManager.shared.cachedMetadata(for: file.fullPath)?.resolutionFormatted {
                    self.resolution = cached
                    return
                }
                MediaMetadataManager.shared.loadMetadata(for: file) { meta in
                    self.resolution = meta?.resolutionFormatted
                }
            }
    }
}

struct DurationTableCell: View {
    let file: IndexedFile
    @State private var duration: String? = nil

    var body: some View {
        Text(duration ?? "—")
            .font(.system(size: 11))
            .foregroundColor(duration != nil ? .primary : .secondary.opacity(0.4))
            .onAppear {
                guard file.isVideoFile || file.isAudioFile else { return }
                if let cached = MediaMetadataManager.shared.cachedMetadata(for: file.fullPath)?.durationFormatted {
                    self.duration = cached
                    return
                }
                MediaMetadataManager.shared.loadMetadata(for: file) { meta in
                    self.duration = meta?.durationFormatted
                }
            }
    }
}
