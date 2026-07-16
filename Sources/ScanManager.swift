import Foundation
import Combine

struct DirectoryScanResult {
    let count: Int
    let errorMessage: String?
    let isAlreadyRunning: Bool

    var isSuccess: Bool {
        errorMessage == nil && !isAlreadyRunning
    }
}

final class ScanManager {
    private var watchers: [String: FSEventWatcher] = [:]
    private let scanLock = NSLock()
    private var activeScanPaths = Set<String>()

    // Only patterns the user explicitly adds are excluded. Index roots are otherwise exhaustive.
    static let defaultExcludedPatterns: [String] = []

    // MARK: - Directory Scanning (Full)

    func scanDirectory(_ dir: IndexDirectory, dbManager: DatabaseManager) -> DirectoryScanResult {
        guard reserveScan(for: dir.path) else {
            return DirectoryScanResult(count: 0, errorMessage: nil, isAlreadyRunning: true)
        }
        defer { finishScan(for: dir.path) }

        guard let indexedDirectory = dbManager.getAllDirectories().first(where: { $0.path == dir.path }) else {
            return DirectoryScanResult(count: 0, errorMessage: "Indexed directory was removed", isAlreadyRunning: false)
        }

        let rootURL = URL(fileURLWithPath: dir.path, isDirectory: true)
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return DirectoryScanResult(count: 0, errorMessage: "Indexed directory is unavailable", isAlreadyRunning: false)
        }

        let scanId = UUID().uuidString
        guard dbManager.beginDirectoryScan(scanId) else {
            return DirectoryScanResult(count: 0, errorMessage: "Could not prepare scan staging", isAlreadyRunning: false)
        }

        let excludedPatterns = dbManager.getAllExcludedPatterns()
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        let fileManager = FileManager.default
        var scanErrors: [String] = []
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [],
            errorHandler: { url, error in
                scanErrors.append("\(url.path): \(error.localizedDescription)")
                return true
            }
        ) else {
            dbManager.discardDirectoryScan(scanId)
            return DirectoryScanResult(count: 0, errorMessage: "Could not enumerate indexed directory", isAlreadyRunning: false)
        }

        var batch: [(fileName: String, fullPath: String, size: Int64, modDate: Double, isDirectory: Bool)] = []
        var entryCount = 0
        var stagingFailed = false

        func flushBatch() {
            guard !batch.isEmpty else { return }
            if dbManager.appendDirectoryScanEntries(scanId, entries: batch) {
                entryCount += batch.count
                batch.removeAll(keepingCapacity: true)
            } else {
                stagingFailed = true
            }
        }

        for case let url as URL in enumerator {
            if isPathExcluded(url.path, relativeTo: rootURL.path, excludedPatterns: excludedPatterns) {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            do {
                let values = try url.resourceValues(forKeys: resourceKeys)
                let isDirectory = values.isDirectory == true
                let isRegularFile = values.isRegularFile == true
                guard isDirectory || isRegularFile else { continue }

                batch.append((
                    fileName: url.lastPathComponent,
                    fullPath: url.path,
                    size: isDirectory ? 0 : Int64(values.fileSize ?? 0),
                    modDate: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
                    isDirectory: isDirectory
                ))
                if batch.count >= 1_000 {
                    flushBatch()
                    if stagingFailed { break }
                }
            } catch {
                scanErrors.append("\(url.path): \(error.localizedDescription)")
            }
        }

        if !stagingFailed { flushBatch() }

        guard !stagingFailed else {
            dbManager.discardDirectoryScan(scanId)
            return DirectoryScanResult(count: 0, errorMessage: "Could not write scan results", isAlreadyRunning: false)
        }
        guard scanErrors.isEmpty else {
            dbManager.discardDirectoryScan(scanId)
            return DirectoryScanResult(count: 0, errorMessage: "Scan incomplete: \(scanErrors.count) path(s) could not be read", isAlreadyRunning: false)
        }
        guard dbManager.commitDirectoryScan(scanId, dirId: indexedDirectory.id) else {
            dbManager.discardDirectoryScan(scanId)
            return DirectoryScanResult(count: 0, errorMessage: "Could not update index", isAlreadyRunning: false)
        }

        dbManager.updateLastScanTime(indexedDirectory)
        print("扫描完成: \(entryCount) 个条目 (完整同步)")
        return DirectoryScanResult(count: entryCount, errorMessage: nil, isAlreadyRunning: false)
    }

    // MARK: - Exclusion Checking

    private func isPathExcluded(_ path: String, relativeTo rootPath: String? = nil, excludedPatterns: [String]) -> Bool {
        let allPatterns = ScanManager.defaultExcludedPatterns + excludedPatterns
        let relativePath: String
        if let rootPath, path.hasPrefix(rootPath + "/") {
            relativePath = String(path.dropFirst(rootPath.count + 1))
        } else {
            relativePath = path
        }
        let components = relativePath.split(separator: "/").map(String.init)
        for pattern in allPatterns {
            if components.contains(pattern) { return true }
        }
        return false
    }

    private func reserveScan(for path: String) -> Bool {
        scanLock.lock()
        defer { scanLock.unlock() }
        guard !activeScanPaths.contains(path) else { return false }
        activeScanPaths.insert(path)
        return true
    }

    private func finishScan(for path: String) {
        scanLock.lock()
        activeScanPaths.remove(path)
        scanLock.unlock()
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
        guard let dir = dirs
            .filter({ path == $0.path || path.hasPrefix($0.path + "/") })
            .max(by: { $0.path.count < $1.path.count }) else { return }

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
            if !isPathExcluded(path, relativeTo: dir.path, excludedPatterns: excludedPatterns) {
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
    private let queue = DispatchQueue(label: "com.lynxistudio.findra.fsevents", qos: .utility)

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
