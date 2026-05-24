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
}