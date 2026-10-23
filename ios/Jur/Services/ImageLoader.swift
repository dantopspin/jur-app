// Photos: downloaded once, kept on disk (they never change: every upload gets a new name),
// decoded off the main thread at the size they're shown, and held in memory, so going back
// to a screen shows its photos at once. Small places (avatars, grids, lists) ask for the
// 480 px copy saved next to each photo; older photos without one fall back to the original.
import ImageIO
import UIKit

final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()

    enum Size: Sendable {
        case thumb, full
        var maxPixel: CGFloat { self == .thumb ? 480 : 1600 }
    }

    private let memory: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 150 * 1024 * 1024
        return c
    }()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jur-images", isDirectory: true)
        config.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 400 * 1024 * 1024, directory: dir)
        // Photo URLs are immutable, so a stored copy is always right.
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()

    private let lock = NSLock()
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    private var noThumb: Set<String> = []

    private func key(_ url: URL, _ size: Size) -> NSString { "\(Int(size.maxPixel))|\(url.absoluteString)" as NSString }

    /// Already in memory: drawn in the very first frame, no fade.
    func cached(_ url: URL, _ size: Size) -> UIImage? {
        memory.object(forKey: key(url, size)) ?? (size == .thumb ? memory.object(forKey: key(url, .full)) : nil)
    }

    func image(_ url: URL, _ size: Size) async -> UIImage? {
        if let hit = cached(url, size) { return hit }
        let k = key(url, size)
        let task: Task<UIImage?, Never> = lock.withLock {
            if let running = inflight[k as String] { return running }
            let t = Task.detached(priority: .userInitiated) { [self] in await self.fetch(url, size) }
            inflight[k as String] = t
            return t
        }
        let image = await task.value
        lock.withLock { inflight[k as String] = nil }
        if let image { store(image, k) }
        return image
    }

    /// Warm the cache for what's about to be shown (the next cards, a list's avatars).
    func prefetch(_ urls: [URL], _ size: Size) {
        for url in urls where cached(url, size) == nil {
            Task.detached(priority: .utility) { [self] in _ = await self.image(url, size) }
        }
    }

    /// A photo just uploaded from this phone: show it straight away, no download.
    func seed(_ data: Data, for url: URL) {
        for size in [Size.full, .thumb] {
            if let image = Self.decode(data, size.maxPixel) { store(image, key(url, size)) }
        }
    }

    func clearMemory() { memory.removeAllObjects() }

    // MARK: private

    private func store(_ image: UIImage, _ k: NSString) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memory.setObject(image, forKey: k, cost: cost)
    }

    private func fetch(_ url: URL, _ size: Size) async -> UIImage? {
        if size == .thumb, let thumb = Self.thumbURL(url) {
            let known = lock.withLock { noThumb.contains(thumb.absoluteString) }
            if !known {
                if let image = await download(thumb, size.maxPixel) { return image }
                lock.withLock { _ = noThumb.insert(thumb.absoluteString) }
            }
        }
        return await download(url, size.maxPixel)
    }

    private func download(_ url: URL, _ maxPixel: CGFloat) async -> UIImage? {
        guard let (data, response) = try? await session.data(from: url) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        return Self.decode(data, maxPixel)
    }

    /// Decoded and scaled in one step, ready to draw (no work left for the main thread).
    static func decode(_ data: Data, _ maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// ".../photos/<user>/<id>.jpg" → ".../photos/<user>/<id>_t.jpg"
    static func thumbURL(_ url: URL) -> URL? {
        let s = url.absoluteString
        guard s.contains("/storage/v1/object/public/photos/"), s.hasSuffix(".jpg"), !s.hasSuffix("_t.jpg") else { return nil }
        return URL(string: String(s.dropLast(4)) + "_t.jpg")
    }
}
