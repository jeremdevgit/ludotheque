// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI
import AppKit
import ImageIO
import CryptoKit

/// Covers are downsampled, decoded and shaped once, off the main thread, then kept as small
/// JPEGs on disk plus an in-memory cache: scrolling never decodes or blurs anything.
/// Shared, thread-safe memory cache: views read it synchronously, the actor fills it.
/// Bounded by decoded size (≈ 0.5 Mo per cover): 128 Mo ≈ 250 covers, several screens of grid.
/// Older covers are evicted and decoded again from the disk cache (off the main thread) if needed.
let coverMemory: NSCache<NSString, NSImage> = {
    let c = NSCache<NSString, NSImage>()
    c.totalCostLimit = 128 * 1_048_576
    c.countLimit = 600
    return c
}()

/// Memory cost of a cached cover (decoded RGBA bytes).
func coverCost(_ img: NSImage) -> Int { max(1, Int(img.size.width * img.size.height * 4)) }

actor CoverStore {
    static let shared = CoverStore()
    private var memory: NSCache<NSString, NSImage> { coverMemory }

    static func key(_ game: Game, poster: Bool) -> String { "\(game.id)|\(game.coverURL ?? "")|\(poster)" }
    private var inflight: [String: Task<NSImage?, Never>] = [:]
    private static let maxPixel = 420

    /// `poster`: landscape artwork is composed into a portrait poster (blurred backdrop + whole image).
    func image(for game: Game, poster: Bool = false) async -> NSImage? {
        let key = Self.key(game, poster: poster)
        if let img = memory.object(forKey: key as NSString) { return img }
        let t: Task<NSImage?, Never>
        if let existing = inflight[key] { t = existing } else {
            t = Task { [weak self] in
                // Already processed on disk: immediate, no queue slot needed.
                if let img = await Task.detached(priority: .userInitiated, operation: { Self.cached(game, poster: poster) }).value { return img }
                // Network loads: at most `maxConcurrent` at once, most recent request first.
                guard let self, await self.acquire() else { return nil }
                let img = await Task.detached(priority: .utility) { await Self.load(game, poster: poster) }.value
                await self.release()
                return img
            }
            inflight[key] = t
        }
        // A tile scrolled off screen cancels its request: queued loads are dropped.
        let img = await withTaskCancellationHandler { await t.value } onCancel: { t.cancel() }
        inflight[key] = nil
        if let img { memory.setObject(img, forKey: key as NSString, cost: coverCost(img)) }
        return img
    }

    // MARK: Load queue (bounded, LIFO, cancellable)

    private static let maxConcurrent = 8
    private final class RedirectPolicy: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            guard let origin = task.originalRequest?.url, GOGImageURL.isAllowed(origin) else {
                completionHandler(request)
                return
            }
            guard let destination = request.url, GOGImageURL.isAllowed(destination) else {
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }
    }
    private static let redirectPolicy = RedirectPolicy()
    /// Short timeouts: a slow or dead image host must never hold a slot for a minute.
    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 12
        c.timeoutIntervalForResource = 20
        c.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: c, delegate: redirectPolicy, delegateQueue: nil)
    }()

    /// Disk-cached cover, if any (no network).
    nonisolated static func cached(_ g: Game, poster: Bool) -> NSImage? {
        for s in [g.coverURL, g.altCoverURL].compactMap({ $0 }) {
            if let cg = decodeDisk(s, poster: poster) { return decoded(cg) }
        }
        return nil
    }
    private var active = 0
    private var waiters: [(id: UUID, cont: CheckedContinuation<Bool, Never>)] = []

    private func acquire() async -> Bool {
        if Task.isCancelled { return false }
        if active < Self.maxConcurrent { active += 1; return true }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in waiters.append((id, c)) }
        } onCancel: {
            Task { await self.dropWaiter(id) }
        }
    }

    private func dropWaiter(_ id: UUID) {
        if let i = waiters.firstIndex(where: { $0.id == id }) { waiters.remove(at: i).cont.resume(returning: false) }
    }

    private func release() {
        if let w = waiters.popLast() { w.cont.resume(returning: true) }   // slot handed over directly
        else { active -= 1 }
    }

    /// New covers are stored as HEIC (about half the size of JPEG at the same quality);
    /// JPEGs from older versions are still read, so nothing is downloaded again.
    nonisolated private static func diskURL(_ s: String, poster: Bool, ext: String = "heic") -> URL {
        let h = SHA256.hash(data: Data(s.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return Paths.caches.appendingPathComponent(h + (poster ? "-p" : "") + "-v2." + ext)
    }

    nonisolated private static func decodeDisk(_ s: String, poster: Bool) -> CGImage? {
        decodeFile(diskURL(s, poster: poster)) ?? decodeFile(diskURL(s, poster: poster, ext: "jpg"))
    }

    /// HEIC when the system encoder is available, JPEG otherwise.
    nonisolated private static func writeCover(_ cg: CGImage, _ s: String, poster: Bool) {
        let url = diskURL(s, poster: poster)
        if let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.heic" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
            if CGImageDestinationFinalize(dest) { return }
            try? FileManager.default.removeItem(at: url)
        }
        if let jpg = NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
            try? jpg.write(to: diskURL(s, poster: poster, ext: "jpg"), options: .atomic)
        }
    }

    /// Fully decoded image (no lazy decode at draw time on the main thread).
    nonisolated private static func decoded(_ cg: CGImage) -> NSImage {
        let img = rasterized(cg) ?? cg
        return NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
    }

    /// Copies the image into a plain BGRA bitmap (the format the screen uses). An image straight
    /// from ImageIO is still tied to its JPEG/HEIC file: Core Animation decoded it again on the
    /// main thread the first time each tile appeared, which made fast scrolling stutter.
    /// The screen's own colour space: Core Animation can then show the bitmap as is, without making
    /// a colour-converted copy of every cover.
    nonisolated static let displaySpace: CGColorSpace = CGDisplayCopyColorSpace(CGMainDisplayID())
    nonisolated static func rasterized(_ cg: CGImage) -> CGImage? {
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(cg.alphaInfo)
        let info = (opaque ? CGImageAlphaInfo.noneSkipFirst : .premultipliedFirst).rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: displaySpace, bitmapInfo: info) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return ctx.makeImage()
    }

    nonisolated private static func decodeFile(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    private static func load(_ g: Game, poster: Bool) async -> NSImage? {
        for s in [g.coverURL, g.altCoverURL].compactMap({ $0 }) {
            if let cg = decodeDisk(s, poster: poster) { return decoded(cg) }
            var data: Data?
            if s.hasPrefix("file://"), let u = URL(string: s) { data = try? Data(contentsOf: u) }
            else if let u = URL(string: s), ["https", "http"].contains(u.scheme ?? ""),
                    let (d, r) = try? await session.data(from: u),
                    (r as? HTTPURLResponse)?.statusCode == 200, d.count < 20_000_000 { data = d }
            guard let data, var cg = downsample(data) else { continue }
            if poster, cg.width > Int(Double(cg.height) * 1.15), let p = posterize(cg) { cg = p }
            writeCover(cg, s, poster: poster)
            return decoded(cg)
        }
        if let p = g.appPath {
            return await MainActor.run { NSWorkspace.shared.icon(forFile: p) }
        }
        return nil
    }

    private static func downsample(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    }

    /// Landscape art → 2:3 poster: the image scaled up from a tiny copy (a free, smooth blur)
    /// as backdrop, the whole image centred on top. Rendered once, then cached.
    private static func posterize(_ img: CGImage) -> CGImage? {
        let w = 300, h = 450
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.setFillColor(CGColor(gray: 0.08, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // Tiny copy (≈10 px wide) drawn over the whole poster = blurred backdrop.
        if let tiny = CGContext(data: nil, width: 10, height: max(1, 10 * img.height / img.width), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
            tiny.interpolationQuality = .medium
            tiny.draw(img, in: CGRect(x: 0, y: 0, width: tiny.width, height: tiny.height))
            if let small = tiny.makeImage() {
                ctx.setAlpha(0.65)
                let bh = Double(h), bw = bh * Double(img.width) / Double(img.height)
                ctx.draw(small, in: CGRect(x: (Double(w) - bw) / 2, y: 0, width: bw, height: bh))
                ctx.setAlpha(1)
            }
        }
        let fw = Double(w), fh = fw * Double(img.height) / Double(img.width)
        ctx.draw(img, in: CGRect(x: 0, y: (Double(h) - fh) / 2, width: fw, height: fh))
        return ctx.makeImage()
    }
}

@MainActor
final class CoverModel: ObservableObject {
    @Published var image: NSImage?
}

struct CoverImage: View {
    let game: Game
    var poster = false
    @StateObject private var model = CoverModel()

    var body: some View {
        // The frame comes from Color.clear (flexible); the image is an overlay clipped to it,
        // so a "fill" image can never report its own size and overflow onto neighbours.
        Color.clear
            .overlay { content }
            .background(Color(game.platform.color).opacity(0.18))
            .clipped()
            .task(id: game.coverURL ?? game.id) {
                if coverMemory.object(forKey: CoverStore.key(game, poster: poster) as NSString) != nil { return }
                model.image = await CoverStore.shared.image(for: game, poster: poster)
            }
    }

    @ViewBuilder private var content: some View {
        if let image = model.image ?? coverMemory.object(forKey: CoverStore.key(game, poster: poster) as NSString) {
            let isIcon = game.coverURL == nil && game.altCoverURL == nil
            if isIcon {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(24)
            } else {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: game.platform.symbol).font(.system(size: 26)).foregroundStyle(.secondary)
            Text(game.title).font(.caption.weight(.semibold)).multilineTextAlignment(.center).lineLimit(3).padding(.horizontal, 8)
        }
    }
}
