import Foundation
import Combine

final class ScanManager {
    private var watchers: [String: FSEventWatcher] = [:]

    // Default excluded patterns
    static let defaultExcludedPatterns: [String] = [
        ".git", "node_modules", ".cache", "tmp", "temp",
        "Trash", "Recycle Bin", "@eaDir", "#recycle", ".recycle",
        "System Volume Information", ".DS_Store", "Thumbs.db"
    ]

    // Media file extensions
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp",
        "heic", "heif", "svg", "psd", "ai", "eps", "raw", "cr2",
        "nef", "arw", "dng", "ico", "icns"
    ]
    private static let videoExtensions: Set<String> = [
        "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v",
        "mpg", "mpeg", "3gp", "ts", "rmvb", "divx", "f4v", "mts", "m2ts"
    ]
    private static let mediaExtensions: Set<String> = imageExtensions.union(videoExtensions)

    // MARK: - Directory Scanning (Full)

    func scanDirectory(_ dir: IndexDirectory, dbManager: DatabaseManager) -> Int {
        return scanDirectory(dir, dbManager: dbManager, incremental: false, lastScanTime: 0)
    }

    /// Incremental scan: only files newer than lastScanTime
    func scanDirectoryIncremental(_ dir: IndexDirectory, dbManager: DatabaseManager) -> Int {
        let lastScan = dbManager.getLastScanTime(for: dir.id)
        guard lastScan > 0 else {
            return scanDirectory(dir, dbManager: dbManager, incremental: false, lastScanTime: 0)
        }
        return scanDirectory(dir, dbManager: dbManager, incremental: true, lastScanTime: lastScan)
    }

    private func scanDirectory(_ dir: IndexDirectory, dbManager: DatabaseManager, incremental: Bool, lastScanTime: Double) -> Int {
        let path = dir.path
        guard FileManager.default.fileExists(atPath: path) else {
            print("目录不存在: \(path)")
            return 0
        }

        let scannerCmd: String
        if let fdPath = findExecutable("fd") {
            scannerCmd = fdPath
        } else {
            scannerCmd = "/usr/bin/find"
        }
        let isFd = scannerCmd.hasSuffix("fd")

        let excludedPatterns = dbManager.getAllExcludedPatterns()
        let dirs = dbManager.getAllDirectories()
        guard let currentDir = dirs.first(where: { $0.path == path }) else { return 0 }
        let dirId = currentDir.id

        let fileResults = scanFilesWithCommand(scannerCmd, path: path, isFd: isFd,
                                                excludedPatterns: excludedPatterns,
                                                incremental: incremental, lastScanTime: lastScanTime)
        let dirResults = scanDirsWithCommand(scannerCmd, path: path, isFd: isFd,
                                              excludedPatterns: excludedPatterns,
                                              incremental: incremental, lastScanTime: lastScanTime)

        var allEntries: [(fileName: String, fullPath: String, size: Int64, modDate: Double, isDirectory: Bool)] = []
        for f in fileResults {
            allEntries.append((f.fileName, f.fullPath, f.size, f.modDate, false))
        }
        for d in dirResults {
            allEntries.append((d.fileName, d.fullPath, 0, d.modDate, true))
        }

        if allEntries.isEmpty {
            if !incremental { print("警告: 目录 \(path) 扫描结果为 0") }
            dbManager.updateLastScanTime(dir)
            return 0
        }

        if incremental {
            let entries: [(String, String, Int64, Double, Bool)] = allEntries.map { ($0.0, $0.1, $0.2, $0.3, $0.4) }
            dbManager.insertFilesBatch(entries.map { (fileName: $0.0, fullPath: $0.1, size: $0.2, modDate: $0.3, dirId: dirId, isDirectory: $0.4) })
        } else {
            dbManager.replaceDirectoryEntries(dirId: dirId, entries: allEntries)
        }

        dbManager.updateLastScanTime(dir)
        print("扫描完成: \(fileResults.count) 个文件, \(dirResults.count) 个子文件夹 (\(incremental ? "增量" : "全量"))")
        return allEntries.count
    }

    private func scanFilesWithCommand(_ cmd: String, path: String, isFd: Bool,
                                       excludedPatterns: [String],
                                       incremental: Bool, lastScanTime: Double) -> [(fileName: String, fullPath: String, size: Int64, modDate: Double)] {
        let lines = runFindCommand(cmd, path: path, isFd: isFd, typeFlag: "f",
                                    incremental: incremental, lastScanTime: lastScanTime)
        var results: [(fileName: String, fullPath: String, size: Int64, modDate: Double)] = []
        results.reserveCapacity(lines.count)

        for line in lines {
            let fullPath = String(line)
            if isPathExcluded(fullPath, excludedPatterns: excludedPatterns) { continue }
            let fileName = URL(fileURLWithPath: fullPath).lastPathComponent

            var size: Int64 = 0
            var modDate: Double = 0
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath) {
                size = (attrs[.size] as? Int64) ?? 0
                modDate = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            }
            results.append((fileName: fileName, fullPath: fullPath, size: size, modDate: modDate))
        }

        let totalCount = results.count
        results = results.filter { ScanManager.mediaExtensions.contains(URL(fileURLWithPath: $0.fullPath).pathExtension.lowercased()) }
        print("文件扫描: \(totalCount) 个文件（过滤后保留 \(results.count) 个图片/视频）")
        return results
    }

    private func scanDirsWithCommand(_ cmd: String, path: String, isFd: Bool,
                                      excludedPatterns: [String],
                                      incremental: Bool, lastScanTime: Double) -> [(fileName: String, fullPath: String, modDate: Double)] {
        let lines = runFindCommand(cmd, path: path, isFd: isFd, typeFlag: "d",
                                    incremental: incremental, lastScanTime: lastScanTime)
        var results: [(fileName: String, fullPath: String, modDate: Double)] = []
        results.reserveCapacity(lines.count)

        for line in lines {
            let fullPath = String(line)
            if fullPath == path { continue }
            if isPathExcluded(fullPath, excludedPatterns: excludedPatterns) { continue }
            let fileName = URL(fileURLWithPath: fullPath).lastPathComponent

            var modDate: Double = 0
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath) {
                modDate = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            }
            results.append((fileName: fileName, fullPath: fullPath, modDate: modDate))
        }
        print("目录扫描: \(results.count) 个子文件夹")
        return results
    }

    // MARK: - Exclusion Checking

    private func isPathExcluded(_ path: String, excludedPatterns: [String]) -> Bool {
        let allPatterns = ScanManager.defaultExcludedPatterns + excludedPatterns
        let components = path.split(separator: "/").map(String.init)
        for pattern in allPatterns {
            if components.contains(pattern) { return true }
        }
        return false
    }

    // MARK: - Command Runner

    private func runFindCommand(_ cmd: String, path: String, isFd: Bool, typeFlag: String,
                                 incremental: Bool, lastScanTime: Double) -> [String] {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        if isFd {
            process.executableURL = URL(fileURLWithPath: cmd)
            process.arguments = [".", path, "--type", typeFlag, "--absolute-path"]
        } else {
            process.executableURL = URL(fileURLWithPath: cmd)
            var args = ["-x", path, "-type", typeFlag]
            if incremental && lastScanTime > 0 {
                let refPath = "/tmp/.fastfinder_ref_\(Int(lastScanTime))"
                let refDate = Date(timeIntervalSince1970: lastScanTime)
                if FileManager.default.fileExists(atPath: refPath) {
                    try? FileManager.default.setAttributes([.modificationDate: refDate], ofItemAtPath: refPath)
                } else {
                    FileManager.default.createFile(atPath: refPath, contents: Data())
                    try? FileManager.default.setAttributes([.modificationDate: refDate], ofItemAtPath: refPath)
                }
                args.append("-newer")
                args.append(refPath)
            }
            process.arguments = args
        }

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.qualityOfService = .utility

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env

        var stdoutData = Data()
        let stdoutGroup = DispatchGroup()
        stdoutGroup.enter()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stdoutGroup.leave()
            } else {
                stdoutData.append(data)
            }
        }

        var stderrData = Data()
        let stderrGroup = DispatchGroup()
        stderrGroup.enter()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                stderrGroup.leave()
            } else {
                stderrData.append(data)
            }
        }

        do {
            try process.run()

            let timeoutSeconds: Double = 120
            let timeoutWorkItem = DispatchWorkItem { [weak process] in
                if process?.isRunning == true {
                    process?.terminate()
                    print("扫描超时 (\(Int(timeoutSeconds))秒): \(path)")
                }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWorkItem)

            process.waitUntilExit()
            timeoutWorkItem.cancel()
            _ = stdoutGroup.wait(timeout: .now() + 5)
            _ = stderrGroup.wait(timeout: .now() + 5)

            if process.terminationStatus != 0 {
                let errStr = String(data: stderrData, encoding: .utf8) ?? ""
                let trimmed = errStr.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    print("扫描失败 (退出码 \(process.terminationStatus)): \(trimmed)")
                }
            }

            guard let output = String(data: stdoutData, encoding: .utf8) else { return [] }
            return output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        } catch {
            print("扫描失败: \(error)")
            return []
        }
    }

    private func findExecutable(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let output = output, !output.isEmpty, FileManager.default.fileExists(atPath: output) {
                return output
            }
        } catch {}
        return nil
    }

    // MARK: - FSEvents Watching

    func startWatching(path: String, callback: @escaping (String) -> Void) {
        guard watchers[path] == nil else { return }
        let watcher = FSEventWatcher(path: path, callback: callback)
        watcher.start()
        watchers[path] = watcher
    }

    func stopWatching(path: String) {
        watchers[path]?.stop()
        watchers[path] = nil
    }

    func stopAllWatching() {
        for (_, watcher) in watchers { watcher.stop() }
        watchers.removeAll()
    }

    func handleFileSystemEvent(path: String, dbManager: DatabaseManager) {
        let fm = FileManager.default
        let dirs = dbManager.getAllDirectories()
        guard let dir = dirs.first(where: { path.hasPrefix($0.path) }) else { return }

        if fm.fileExists(atPath: path) {
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            var isDir: ObjCBool = false
            let isDirectory = fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
            var size: Int64 = 0
            var modDate: Double = 0
            if !isDirectory, let attrs = try? fm.attributesOfItem(atPath: path) {
                size = (attrs[.size] as? Int64) ?? 0
                modDate = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            }
            let excludedPatterns = dbManager.getAllExcludedPatterns()
            if !isPathExcluded(path, excludedPatterns: excludedPatterns) {
                dbManager.insertFilesBatch([(fileName: fileName, fullPath: path, size: size, modDate: modDate, dirId: dir.id, isDirectory: isDirectory)])
            }
        } else {
            dbManager.deleteByPath(path)
        }
    }
}

// MARK: - FSEventWatcher

final class FSEventWatcher {
    private let path: String
    private let callback: (String) -> Void
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.fastfinder.fsevents", qos: .utility)

    init(path: String, callback: @escaping (String) -> Void) {
        self.path = path
        self.callback = callback
    }

    func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let paths = [path] as CFArray
        let flags: FSEventStreamCreateFlags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)

        stream = FSEventStreamCreate(kCFAllocatorDefault, { (_, info, numEvents, eventPaths, eventFlags, _) in
            guard let info = info else { return }
            let watcher = Unmanaged<FSEventWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = (Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String])
            for i in 0..<Int(numEvents) {
                let flag = Int(eventFlags[i])
                if flag & (kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemModified |
                          kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed) != 0 {
                    watcher.callback(paths[i])
                }
            }
        }, &context, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2.0, flags)

        if let stream = stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    func stop() {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    deinit { stop() }
}