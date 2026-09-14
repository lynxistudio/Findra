import SwiftUI
import AppKit
import Quartz

// MARK: - PreferenceKey for Tracking Card Frames in Marquee Drag

struct FileItemFrameKey: PreferenceKey {
    static var defaultValue: [Int64: CGRect] = [:]
    static func reduce(value: inout [Int64: CGRect], nextValue: () -> [Int64: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - File Grid View (High-Performance Streaming Thumbnail Grid)

struct FileGridView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var locale: LocaleManager
    let files: [IndexedFile]
    @Binding var selectedIds: Set<Int64>
    @FocusState.Binding var isRenameFocused: Bool
    var onDoubleClick: ((IndexedFile) -> Void)? = nil

    @State private var dragStartPoint: CGPoint? = nil
    @State private var dragCurrentPoint: CGPoint? = nil
    @State private var itemFrames: [Int64: CGRect] = [:]
    @State private var selectionBeforeDrag: Set<Int64> = []
    @State private var isCmdDrag: Bool = false
    @State private var lastClickedKey: Int64? = nil

    private var cardSize: CGFloat {
        max(80, appState.thumbnailSize)
    }

    private var itemWidth: CGFloat {
        cardSize + 24
    }

    private var itemHeight: CGFloat {
        cardSize + 56
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: itemWidth, maximum: itemWidth), spacing: 14)]
    }

    private var marqueeRect: CGRect? {
        guard let start = dragStartPoint, let current = dragCurrentPoint else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                // Background surface to catch taps and clear selection / blur search field
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedIds.removeAll()
                        lastClickedKey = nil
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }

                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(files) { file in
                        let fileKey = file.id != 0 ? file.id : file.stableId
                        let isSelected = selectedIds.contains(fileKey)

                        ThumbnailCardView(
                            file: file,
                            isSelected: isSelected,
                            isCut: appState.cutFilePaths.contains(file.fullPath),
                            isEditing: appState.editingFileId == file.id || (file.id == 0 && appState.editingFileId == file.stableId),
                            editingText: $appState.editingFileName,
                            cardSize: cardSize,
                            itemWidth: itemWidth,
                            itemHeight: itemHeight,
                            isRenameFocused: $isRenameFocused,
                            onCommitRename: { appState.commitEditing() }
                        )
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: FileItemFrameKey.self,
                                    value: [fileKey: geo.frame(in: .named("FileGridCanvas"))]
                                )
                            }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            if let onDoubleClick = onDoubleClick {
                                onDoubleClick(file)
                            } else if file.isDirectory {
                                appState.navigateTo(path: file.fullPath)
                            } else {
                                NSWorkspace.shared.open(URL(fileURLWithPath: file.fullPath))
                            }
                        }
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                handleSelection(for: file)
                            }
                        )
                        .contextMenu {
                            let currentSelection = selectedIds.isEmpty ? [fileKey] : selectedIds
                            cardContextMenu(for: currentSelection)
                        }
                    }
                }
                .padding(14)

                // Marquee Rubber-band Selection Box Overlay
                if let rect = marqueeRect, rect.width > 2 || rect.height > 2 {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.18))
                        .overlay(
                            Rectangle()
                                .stroke(Color.accentColor.opacity(0.85), lineWidth: 1)
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .coordinateSpace(name: "FileGridCanvas")
            .onPreferenceChange(FileItemFrameKey.self) { frames in
                self.itemFrames = frames
            }
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named("FileGridCanvas"))
                    .onChanged { value in
                        handleDragChange(value)
                    }
                    .onEnded { value in
                        handleDragEnd(value)
                    }
            )
        }
    }

    private func handleSelection(for file: IndexedFile) {
        let fileKey = file.id != 0 ? file.id : file.stableId
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Resign search field focus so keyboard shortcuts (Space, Arrow keys, Cmd+C) target file operations
        NSApp.keyWindow?.makeFirstResponder(nil)

        if modifiers.contains(.command) {
            // Cmd-click: Toggle item selection
            if selectedIds.contains(fileKey) {
                selectedIds.remove(fileKey)
            } else {
                selectedIds.insert(fileKey)
            }
            lastClickedKey = fileKey
        } else if modifiers.contains(.shift), let lastKey = lastClickedKey {
            // Shift-click: Range selection like Finder / Windows Explorer
            let fileKeys = files.map { $0.id != 0 ? $0.id : $0.stableId }
            if let lastIndex = fileKeys.firstIndex(of: lastKey),
               let currentIndex = fileKeys.firstIndex(of: fileKey) {
                let start = min(lastIndex, currentIndex)
                let end = max(lastIndex, currentIndex)
                let rangeKeys = Set(fileKeys[start...end])
                selectedIds.formUnion(rangeKeys)
            } else {
                selectedIds.insert(fileKey)
                lastClickedKey = fileKey
            }
        } else {
            // Single normal click: Select only this item
            selectedIds = [fileKey]
            lastClickedKey = fileKey
        }
    }

    private func handleDragChange(_ value: DragGesture.Value) {
        NSApp.keyWindow?.makeFirstResponder(nil)

        if dragStartPoint == nil {
            dragStartPoint = value.startLocation
            let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            isCmdDrag = modifiers.contains(.command)
            selectionBeforeDrag = isCmdDrag ? selectedIds : []
        }
        dragCurrentPoint = value.location

        guard let rect = marqueeRect else { return }

        var hitKeys: Set<Int64> = []
        for (key, frame) in itemFrames {
            if rect.intersects(frame) {
                hitKeys.insert(key)
            }
        }

        if isCmdDrag {
            selectedIds = selectionBeforeDrag.symmetricDifference(hitKeys)
        } else {
            selectedIds = hitKeys
        }
    }

    private func handleDragEnd(_ value: DragGesture.Value) {
        dragStartPoint = nil
        dragCurrentPoint = nil
        selectionBeforeDrag = []
        isCmdDrag = false
    }

    @ViewBuilder
    private func cardContextMenu(for selectedIds: Set<Int64>) -> some View {
        let selectedFiles = files.filter { selectedIds.contains($0.id) || selectedIds.contains($0.stableId) }
        let targetFiles = selectedFiles.isEmpty ? [] : selectedFiles

        if targetFiles.count == 1 {
            let single = targetFiles[0]
            if single.isDirectory {
                Button(locale.open) { appState.navigateTo(path: single.fullPath) }
            } else {
                Button(locale.open) { NSWorkspace.shared.open(URL(fileURLWithPath: single.fullPath)) }
                Button(locale.quickLook) { QuickLookCoordinator.shared.showPreview(urls: [URL(fileURLWithPath: single.fullPath)]) }
            }
            Divider()
            Button(locale.rename) { appState.startEditingFile(single) }
            Button(locale.copy) { appState.copyFiles(selectedIds) }
            Button(locale.cut) { appState.cutFiles(selectedIds) }
            Divider()
            Button(locale.copyPath) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(single.fullPath, forType: .string)
            }
            Button(locale.showInFinder) { appState.revealInFinder(single) }
            Divider()
            Button(locale.moveToTrash, role: .destructive) { appState.deleteFiles(selectedIds) }
        } else if !targetFiles.isEmpty {
            Button(locale.quickLook) {
                let urls = targetFiles.map { URL(fileURLWithPath: $0.fullPath) }
                QuickLookCoordinator.shared.showPreview(urls: urls)
            }
            Divider()
            Button(locale.copy) { appState.copyFiles(selectedIds) }
            Button(locale.cut) { appState.cutFiles(selectedIds) }
            Divider()
            Button(locale.moveToTrash, role: .destructive) { appState.deleteFiles(selectedIds) }
        }
    }
}

// MARK: - Thumbnail Card View

struct ThumbnailCardView: View {
    let file: IndexedFile
    let isSelected: Bool
    let isCut: Bool
    let isEditing: Bool
    @Binding var editingText: String
    let cardSize: CGFloat
    let itemWidth: CGFloat
    let itemHeight: CGFloat
    var isRenameFocused: FocusState<Bool>.Binding
    let onCommitRename: () -> Void

    @State private var thumbnail: NSImage? = nil
    @State private var isLoading = false

    private var targetSize: CGSize {
        CGSize(width: cardSize * 1.5, height: cardSize * 1.5)
    }

    var body: some View {
        VStack(spacing: 4) {
            // Thumbnail / Icon Canvas
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                        .frame(width: cardSize, height: cardSize)

                    if file.isDirectory {
                        Image(systemName: "folder.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundColor(.accentColor.opacity(0.85))
                            .frame(width: cardSize * 0.52, height: cardSize * 0.52)
                    } else if let img = thumbnail {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: cardSize - 6, maxHeight: cardSize - 6)
                            .cornerRadius(4)
                    } else {
                        // Lightweight placeholder icon while streaming thumbnail loads
                        FileIconView(filePath: file.fullPath, fileName: file.fileName, isDirectory: false)
                            .frame(width: cardSize * 0.45, height: cardSize * 0.45)
                    }
                }

                // Video Badge
                if file.isVideoFile {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                        .padding(3)
                }
            }
            .frame(width: cardSize, height: cardSize)

            // File Name Label / Inline Rename Field
            if isEditing {
                TextField("", text: $editingText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .focused(isRenameFocused)
                    .onSubmit { onCommitRename() }
                    .frame(width: cardSize + 12)
            } else {
                Text(file.fileName)
                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.middle)
                    .frame(width: cardSize + 12, height: 26, alignment: .top)
            }

            // Size badge (keeps consistent baseline between files and directories)
            Text(file.isDirectory ? " " : file.sizeFormatted)
                .font(.system(size: 9))
                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                .lineLimit(1)
                .frame(height: 12)
        }
        .frame(width: itemWidth, height: itemHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .opacity(isCut ? 0.45 : 1.0)
        .onAppear {
            loadThumbnailIfNeeded()
        }
        .onDisappear {
            ThumbnailManager.shared.cancelRequest(for: file, targetSize: targetSize)
        }
    }

    private func loadThumbnailIfNeeded() {
        guard !file.isDirectory else { return }

        // Fast memory lookup
        if let cached = ThumbnailManager.shared.cachedThumbnail(for: file, targetSize: targetSize) {
            self.thumbnail = cached
            return
        }

        // Asynchronous generation with priority for visible items
        ThumbnailManager.shared.loadThumbnail(for: file, targetSize: targetSize) { image in
            if let image = image {
                withAnimation(.easeOut(duration: 0.15)) {
                    self.thumbnail = image
                }
            }
        }
    }
}
