import SwiftUI

// MARK: - Locale Manager (auto-detects system language)

final class LocaleManager: ObservableObject {
    let isChinese: Bool

    init() {
        let lang = Locale.preferredLanguages.first ?? "en"
        isChinese = lang.hasPrefix("zh")
    }

    // MARK: - Sidebar

    var indexedDirectories: String {
        isChinese ? "索引目录" : "Indexed Directories"
    }
    var exclusionRules: String {
        isChinese ? "排除规则" : "Exclusion Rules"
    }
    var addDirectory: String {
        isChinese ? "添加索引目录" : "Add Directory"
    }
    var add: String {
        isChinese ? "添加" : "Add"
    }
    var cancel: String {
        isChinese ? "取消" : "Cancel"
    }
    var remove: String {
        isChinese ? "移除" : "Remove"
    }
    var rescan: String {
        isChinese ? "重新扫描" : "Rescan"
    }
    var stopWatching: String {
        isChinese ? "取消监听" : "Stop Watching"
    }
    var confirmRemoveTitle: String {
        isChinese ? "移除目录" : "Remove Directory"
    }
    func confirmRemoveMsg(path: String) -> String {
        isChinese
            ? "确认移除 \(path)？这将同时删除索引数据。"
            : "Remove \(path)? This will also delete index data."
    }
    var pathLabel: String {
        isChinese ? "路径:" : "Path:"
    }
    var typeLabel: String {
        isChinese ? "类型:" : "Type:"
    }
    var browse: String {
        isChinese ? "浏览" : "Browse"
    }
    var selectFolderPrompt: String {
        isChinese ? "选择要索引的文件夹" : "Select folder to index"
    }
    var selectPrompt: String {
        isChinese ? "选择" : "Select"
    }
    var localDrive: String {
        isChinese ? "本地" : "Local"
    }
    var nfsDrive: String {
        isChinese ? "NFS 网络" : "NFS"
    }
    var smbDrive: String {
        isChinese ? "SMB 网络" : "SMB"
    }
    var indexed: String {
        isChinese ? "已索引" : "Indexed"
    }
    var addExclusionRule: String {
        isChinese ? "添加排除规则" : "Add Exclusion Rule"
    }
    var exclusionHint: String {
        isChinese
            ? "匹配该名称的目录将被跳过（如 node_modules、.git）"
            : "Directories matching this name will be skipped (e.g. node_modules, .git)"
    }
    var patternPlaceholder: String {
        isChinese ? "目录名或通配符" : "Directory name or wildcard"
    }

    // MARK: - Search

    var searchPlaceholder: String {
        isChinese ? "搜索文件名..." : "Search file names..."
    }
    var noResults: String {
        isChinese ? "未找到匹配的文件" : "No matching files found"
    }
    var emptyPrompt: String {
        isChinese ? "输入文件名关键词开始搜索" : "Enter keywords to search"
    }
    func totalFiles(_ count: Int) -> String {
        isChinese ? "共索引 \(count) 个文件" : "\(count) files indexed"
    }
    var tableFileName: String {
        isChinese ? "文件名" : "Name"
    }
    var tableSize: String {
        isChinese ? "大小" : "Size"
    }
    var tableModDate: String {
        isChinese ? "修改时间" : "Modified"
    }
    var tablePath: String {
        isChinese ? "路径" : "Path"
    }
    func resultCount(_ count: Int) -> String {
        isChinese ? "\(count) 个结果" : "\(count) results"
    }
    func unavailableFiles(_ count: Int) -> String {
        isChinese
            ? "\(count) 个文件当前不可用，可能已移动、删除或所在磁盘未挂载"
            : "\(count) file(s) unavailable; they may have moved, been deleted, or be on an unmounted volume"
    }
    func copiedFiles(_ count: Int) -> String {
        isChinese ? "已复制 \(count) 个文件" : "Copied \(count) file(s)"
    }
    var copyFailed: String {
        isChinese ? "无法复制文件" : "Could not copy files"
    }

    // MARK: - Context Menu

    var rename: String {
        isChinese ? "重命名" : "Rename"
    }
    var showInFinder: String {
        isChinese ? "在 Finder 中显示" : "Show in Finder"
    }
    var quickLook: String {
        isChinese ? "快速查看" : "Quick Look"
    }
    var copy: String {
        isChinese ? "复制" : "Copy"
    }
    var open: String {
        isChinese ? "打开" : "Open"
    }
    var moveToTrash: String {
        isChinese ? "移到废纸篓" : "Move to Trash"
    }

    // MARK: - Scan Status

    func scanning(_ path: String) -> String {
        isChinese ? "正在扫描: \(path)" : "Scanning: \(path)"
    }
    func scanComplete(path: String, count: Int) -> String {
        isChinese
            ? "扫描完成: \(path) (\(count) 个文件)"
            : "Scan complete: \(path) (\(count) files)"
    }
    func scanFailed(path: String, reason: String) -> String {
        isChinese
            ? "扫描未完成，已保留原有索引: \(path) (\(reason))"
            : "Scan incomplete; existing index kept: \(path) (\(reason))"
    }
    func scanAlreadyRunning(path: String) -> String {
        isChinese ? "该目录正在扫描: \(path)" : "Scan already running: \(path)"
    }
    func directoryIndexStats(folders: Int, files: Int) -> String {
        isChinese ? "\(folders) 个文件夹，\(files) 个文件" : "\(folders) folders, \(files) files"
    }
    func directoryAlreadyCovered(path: String) -> String {
        isChinese ? "该目录已被上级索引目录覆盖: \(path)" : "Directory is already covered by an indexed parent: \(path)"
    }

    // MARK: - Navigation & View Modes

    var back: String {
        isChinese ? "后退" : "Back"
    }
    var forward: String {
        isChinese ? "前进" : "Forward"
    }
    var parentDirectory: String {
        isChinese ? "上级目录" : "Parent Folder"
    }
    var refresh: String {
        isChinese ? "刷新" : "Refresh"
    }
    var listView: String {
        isChinese ? "列表视图" : "List View"
    }
    var gridView: String {
        isChinese ? "网格视图" : "Grid View"
    }
    var thumbnailSize: String {
        isChinese ? "缩略图大小" : "Thumbnail Size"
    }
    var copyPath: String {
        isChinese ? "拷贝路径" : "Copy Path"
    }
    var emptyFolder: String {
        isChinese ? "此文件夹为空" : "This folder is empty"
    }

    // MARK: - File Operations & Clipboard

    var cut: String {
        isChinese ? "剪切" : "Cut"
    }
    var paste: String {
        isChinese ? "粘贴" : "Paste"
    }
    func cutFiles(_ count: Int) -> String {
        isChinese ? "已剪切 \(count) 个文件" : "Cut \(count) file(s)"
    }
    func pastedFiles(_ count: Int) -> String {
        isChinese ? "已粘贴 \(count) 个文件" : "Pasted \(count) file(s)"
    }
    var deleteImmediately: String {
        isChinese ? "立即直接删除" : "Delete Immediately"
    }
    func trashingFiles(_ count: Int) -> String {
        isChinese ? "正在移入废纸篓 (\(count) 个项目)..." : "Moving \(count) item(s) to Trash..."
    }
    func deletingFiles(_ count: Int) -> String {
        isChinese ? "正在永久删除 (\(count) 个项目)..." : "Permanently deleting \(count) item(s)..."
    }
    func deletedFiles(_ count: Int) -> String {
        isChinese ? "已移到废纸篓 \(count) 个文件" : "Moved \(count) file(s) to Trash"
    }
    func permanentlyDeletedFiles(_ count: Int) -> String {
        isChinese ? "已永久删除 \(count) 个文件" : "Permanently deleted \(count) file(s)"
    }
    func directoryRefreshed(count: Int) -> String {
        isChinese ? "已刷新，共 \(count) 个项目" : "Refreshed: \(count) item(s)"
    }

    // MARK: - Sorting & Media Metadata

    var resolution: String {
        isChinese ? "分辨率" : "Resolution"
    }
    var duration: String {
        isChinese ? "时长" : "Duration"
    }
    var tableCreationDate: String {
        isChinese ? "创建时间" : "Date Created"
    }
    var sortByModDate: String {
        isChinese ? "修改时间" : "Date Modified"
    }
    var sortByCreationDate: String {
        isChinese ? "创建时间 (下载时间)" : "Date Created"
    }
    var sortBySize: String {
        isChinese ? "文件大小" : "File Size"
    }
    var sortByDuration: String {
        isChinese ? "时长" : "Duration"
    }
    var sortByName: String {
        isChinese ? "文件名" : "File Name"
    }
    var sortAscending: String {
        isChinese ? "升序" : "Ascending"
    }
    var sortDescending: String {
        isChinese ? "降序" : "Descending"
    }
    var sortOrderHelp: String {
        isChinese ? "更改排序方式" : "Change sort order"
    }
    var sortMenuTitle: String {
        isChinese ? "排序" : "Sort"
    }
}
