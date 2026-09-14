import SwiftUI
import AppKit

// MARK: - File Drag Source Overlay (SwiftUI Representable)

struct FileDragSourceOverlay: NSViewRepresentable {
    let file: IndexedFile
    @Binding var selectedIds: Set<Int64>
    let visibleFiles: [IndexedFile]
    var onDoubleClick: (() -> Void)? = nil
    var onSelection: (() -> Void)? = nil

    func makeNSView(context: Context) -> FileDragSourceView {
        let view = FileDragSourceView()
        view.file = file
        view.selectedIds = $selectedIds
        view.visibleFiles = visibleFiles
        view.onDoubleClick = onDoubleClick
        view.onSelection = onSelection
        return view
    }

    func updateNSView(_ nsView: FileDragSourceView, context: Context) {
        nsView.file = file
        nsView.selectedIds = $selectedIds
        nsView.visibleFiles = visibleFiles
        nsView.onDoubleClick = onDoubleClick
        nsView.onSelection = onSelection
    }
}

// MARK: - Native AppKit NSDraggingSource View

final class FileDragSourceView: NSView, NSDraggingSource {
    var file: IndexedFile?
    var selectedIds: Binding<Set<Int64>> = .constant([])
    var visibleFiles: [IndexedFile] = []
    var onDoubleClick: (() -> Void)? = nil
    var onSelection: (() -> Void)? = nil

    static var lastClickedKey: Int64? = nil

    private var mouseDownLocation: NSPoint?
    private var isDragging = false
    private var shouldSelectOnMouseUp = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

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
        guard let file = file else {
            super.mouseDown(with: event)
            return
        }

        // Resign search field focus so keyboard shortcuts (Space, Delete, etc.) target file selection
        window?.makeFirstResponder(nil)

        mouseDownLocation = convert(event.locationInWindow, from: nil)
        isDragging = false
        shouldSelectOnMouseUp = false

        let fileKey = file.id != 0 ? file.id : file.stableId
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if modifiers.contains(.command) {
            // Cmd-click: Toggle item selection
            if selectedIds.wrappedValue.contains(fileKey) {
                selectedIds.wrappedValue.remove(fileKey)
            } else {
                selectedIds.wrappedValue.insert(fileKey)
            }
            FileDragSourceView.lastClickedKey = fileKey
            onSelection?()
        } else if modifiers.contains(.shift), let lastKey = FileDragSourceView.lastClickedKey {
            // Shift-click: Range selection like Finder
            let fileKeys = visibleFiles.map { $0.id != 0 ? $0.id : $0.stableId }
            if let lastIndex = fileKeys.firstIndex(of: lastKey),
               let currentIndex = fileKeys.firstIndex(of: fileKey) {
                let start = min(lastIndex, currentIndex)
                let end = max(lastIndex, currentIndex)
                let rangeKeys = Set(fileKeys[start...end])
                selectedIds.wrappedValue.formUnion(rangeKeys)
            } else {
                selectedIds.wrappedValue.insert(fileKey)
                FileDragSourceView.lastClickedKey = fileKey
            }
            onSelection?()
        } else {
            // Normal click without modifiers
            if selectedIds.wrappedValue.contains(fileKey) {
                // Already part of selection. Delay collapsing until mouseUp so we can drag the multi-selection.
                shouldSelectOnMouseUp = selectedIds.wrappedValue.count > 1
            } else {
                selectedIds.wrappedValue = [fileKey]
                FileDragSourceView.lastClickedKey = fileKey
                onSelection?()
            }
        }

        focusEnclosingTable()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let file = file, let start = mouseDownLocation else {
            super.mouseDragged(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        let distance = hypot(location.x - start.x, location.y - start.y)
        guard distance >= 3 else { return }

        isDragging = true
        shouldSelectOnMouseUp = false

        beginFinderDrag(for: file, with: event)
        mouseDownLocation = nil
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownLocation = nil
            isDragging = false
            shouldSelectOnMouseUp = false
        }

        guard !isDragging, let file = file else { return }

        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }

        let fileKey = file.id != 0 ? file.id : file.stableId
        if shouldSelectOnMouseUp {
            selectedIds.wrappedValue = [fileKey]
            FileDragSourceView.lastClickedKey = fileKey
            onSelection?()
        }
    }

    private func beginFinderDrag(for file: IndexedFile, with event: NSEvent) {
        let fileKey = file.id != 0 ? file.id : file.stableId
        let currentSelected = selectedIds.wrappedValue

        let filesToDrag: [IndexedFile]
        if currentSelected.contains(fileKey) {
            filesToDrag = visibleFiles.filter { currentSelected.contains($0.id != 0 ? $0.id : $0.stableId) }
        } else {
            filesToDrag = [file]
            selectedIds.wrappedValue = [fileKey]
            FileDragSourceView.lastClickedKey = fileKey
        }

        let urls = filesToDrag
            .filter { FileManager.default.fileExists(atPath: $0.fullPath) }
            .map { URL(fileURLWithPath: $0.fullPath) }
        guard !urls.isEmpty else { return }

        let dragPoint = convert(event.locationInWindow, from: nil)
        let items: [NSDraggingItem] = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 48, height: 48)
            let offset = CGFloat(min(index, 4)) * 3
            let frame = NSRect(
                x: dragPoint.x - 24 + offset,
                y: dragPoint.y - 24 - offset,
                width: 48,
                height: 48
            )
            item.setDraggingFrame(frame, contents: icon)
            return item
        }

        let session = beginDraggingSession(with: items, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .stack
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

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .generic, .move]
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        false
    }
}
