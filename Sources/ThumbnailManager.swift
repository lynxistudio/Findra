import AppKit
import QuickLookThumbnailing
import AVFoundation
import CryptoKit

// MARK: - Thumbnail Cache & Generator Manager

final class ThumbnailManager {
    static let shared = ThumbnailManager()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let diskCacheURL: URL
    private let queue = OperationQueue()
    private let activeRequestsLock = NSLock()
    private var activeRequests: [String: QLThumbnailGenerator.Request] = [:]

    init() {
        // Configure memory cache
        memoryCache.countLimit = 1500
        memoryCache.totalCostLimit = 120 * 1024 * 1024 // 120 MB

        // Configure disk cache directory in Application Support/Findra/Thumbnails
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        diskCacheURL = appSupport.appendingPathComponent("Findra/Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)

        // Bounded concurrency prevents saturating NAS SMB/NFS connections
        queue.name = "com.lynxistudio.findra.thumbnails"
        queue.maxConcurrentOperationCount = 6
        queue.qualityOfService = .userInitiated
    }

    // MARK: - Public API

    /// Retrieves an image synchronously from memory cache if already available.
    func cachedThumbnail(for file: IndexedFile, targetSize: CGSize) -> NSImage? {
        let key = cacheKey(for: file, size: targetSize) as NSString
        return memoryCache.object(forKey: key)
    }

    /// Loads thumbnail asynchronously: checks memory, then disk, then generates via QLThumbnailGenerator/AVFoundation.
    func loadThumbnail(for file: IndexedFile, targetSize: CGSize, completion: @escaping (NSImage?) -> Void) {
        let key = cacheKey(for: file, size: targetSize)

        // 1. Check Memory Cache
        if let memoryImage = memoryCache.object(forKey: key as NSString) {
            completion(memoryImage)
            return
        }

        // 2. Background task for disk check and generation
        queue.addOperation { [weak self] in
            guard let self = self else { return }

            // Check Disk Cache
            let diskURL = self.diskCacheURL.appendingPathComponent("\(key).jpg")
            if let diskData = try? Data(contentsOf: diskURL),
               let diskImage = NSImage(data: diskData) {
                let cost = Int(diskData.count)
                self.memoryCache.setObject(diskImage, forKey: key as NSString, cost: cost)
                DispatchQueue.main.async {
                    completion(diskImage)
                }
                return
            }

            // Fallback for missing file on disk
            guard FileManager.default.fileExists(atPath: file.fullPath) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let fileURL = URL(fileURLWithPath: file.fullPath)

            // Generate via QuickLookThumbnailing
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let request = QLThumbnailGenerator.Request(
                fileAt: fileURL,
                size: targetSize,
                scale: scale,
                representationTypes: .thumbnail
            )

            self.activeRequestsLock.lock()
            self.activeRequests[key] = request
            self.activeRequestsLock.unlock()

            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, error in
                guard let self = self else { return }

                self.activeRequestsLock.lock()
                self.activeRequests.removeValue(forKey: key)
                self.activeRequestsLock.unlock()

                if let rep = representation {
                    let image = rep.nsImage
                    self.saveToCache(image: image, key: key, diskURL: diskURL)
                    DispatchQueue.main.async {
                        completion(image)
                    }
                } else if file.isVideoFile {
                    // Fallback to AVAssetImageGenerator for videos if QL fails
                    self.generateVideoThumbnail(from: fileURL, targetSize: targetSize) { [weak self] videoImage in
                        guard let self = self, let videoImage = videoImage else {
                            DispatchQueue.main.async { completion(nil) }
                            return
                        }
                        self.saveToCache(image: videoImage, key: key, diskURL: diskURL)
                        DispatchQueue.main.async {
                            completion(videoImage)
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                }
            }
        }
    }

    /// Cancel in-flight thumbnail request for cells that scrolled out of view.
    func cancelRequest(for file: IndexedFile, targetSize: CGSize) {
        let key = cacheKey(for: file, size: targetSize)
        activeRequestsLock.lock()
        if let request = activeRequests.removeValue(forKey: key) {
            QLThumbnailGenerator.shared.cancel(request)
        }
        activeRequestsLock.unlock()
    }

    // MARK: - Private Helpers

    private func cacheKey(for file: IndexedFile, size: CGSize) -> String {
        let raw = "\(file.fullPath)_\(file.modDate)_\(file.size)_\(Int(size.width))x\(Int(size.height))"
        let hash = SHA256.hash(data: Data(raw.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func saveToCache(image: NSImage, key: String, diskURL: URL) {
        // Save to memory
        memoryCache.setObject(image, forKey: key as NSString)

        // Save to disk asynchronously
        DispatchQueue.global(qos: .utility).async {
            guard let tiffData = image.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else {
                return
            }
            try? jpegData.write(to: diskURL, options: .atomic)
        }
    }

    private func generateVideoThumbnail(from url: URL, targetSize: CGSize, completion: @escaping (NSImage?) -> Void) {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: targetSize.width * 2, height: targetSize.height * 2)

        let time = CMTime(seconds: 1.0, preferredTimescale: 600)
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, result, _ in
            if result == .succeeded, let cgImage = cgImage {
                let image = NSImage(cgImage: cgImage, size: targetSize)
                completion(image)
            } else {
                // Try time zero
                generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) { _, cgImage2, _, result2, _ in
                    if result2 == .succeeded, let cgImage2 = cgImage2 {
                        let image = NSImage(cgImage: cgImage2, size: targetSize)
                        completion(image)
                    } else {
                        completion(nil)
                    }
                }
            }
        }
    }
}
