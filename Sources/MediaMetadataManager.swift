import Foundation
import ImageIO
import AVFoundation
import CoreGraphics

// MARK: - Media Metadata Structure

final class MediaMetadata: NSObject {
    let resolution: CGSize?
    let duration: Double? // in seconds

    init(resolution: CGSize?, duration: Double?) {
        self.resolution = resolution
        self.duration = duration
    }

    var resolutionFormatted: String? {
        guard let resolution, resolution.width > 0, resolution.height > 0 else { return nil }
        return "\(Int(resolution.width)) × \(Int(resolution.height))"
    }

    var durationFormatted: String? {
        guard let duration, duration > 0 else { return nil }
        let totalSeconds = Int(duration.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Media Metadata Manager

final class MediaMetadataManager {
    static let shared = MediaMetadataManager()

    private let cache = NSCache<NSString, MediaMetadata>()

    private init() {
        cache.countLimit = 3000
    }

    func cachedMetadata(for path: String) -> MediaMetadata? {
        cache.object(forKey: path as NSString)
    }

    func loadMetadata(for file: IndexedFile, completion: @escaping (MediaMetadata?) -> Void) {
        let pathKey = file.fullPath as NSString
        if let cached = cache.object(forKey: pathKey) {
            completion(cached)
            return
        }

        guard file.isMediaFile || file.isAudioFile else {
            completion(nil)
            return
        }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let metadata = await self.extractMetadata(for: file)
            if let metadata {
                self.cache.setObject(metadata, forKey: pathKey)
            }
            await MainActor.run {
                completion(metadata)
            }
        }
    }

    private func extractMetadata(for file: IndexedFile) async -> MediaMetadata? {
        let url = URL(fileURLWithPath: file.fullPath)

        if file.isImageFile {
            // High-speed header extraction using ImageIO (reads only first ~1KB, sub-0.1ms)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
            guard let width = props[kCGImagePropertyPixelWidth] as? CGFloat,
                  let height = props[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }

            let orientation = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
            let finalSize: CGSize
            if [5, 6, 7, 8].contains(orientation) {
                finalSize = CGSize(width: height, height: width)
            } else {
                finalSize = CGSize(width: width, height: height)
            }
            return MediaMetadata(resolution: finalSize, duration: nil)
        }

        if file.isVideoFile {
            let asset = AVURLAsset(url: url)
            var resolution: CGSize? = nil
            var durationSec: Double? = nil

            if let tracks = try? await asset.loadTracks(withMediaType: .video), let track = tracks.first {
                if let size = try? await track.load(.naturalSize),
                   let transform = try? await track.load(.preferredTransform) {
                    let transformed = size.applying(transform)
                    resolution = CGSize(width: abs(transformed.width), height: abs(transformed.height))
                }
            }

            if let duration = try? await asset.load(.duration) {
                let sec = duration.seconds
                if sec.isFinite && sec > 0 {
                    durationSec = sec
                }
            }

            return MediaMetadata(resolution: resolution, duration: durationSec)
        }

        if file.isAudioFile {
            let asset = AVURLAsset(url: url)
            if let duration = try? await asset.load(.duration) {
                let sec = duration.seconds
                if sec.isFinite && sec > 0 {
                    return MediaMetadata(resolution: nil, duration: sec)
                }
            }
        }

        return nil
    }
}
