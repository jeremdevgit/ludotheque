// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI
import AppKit

/// Real platform logos: each site's favicon, fetched once and cached on disk.
@MainActor
final class LogoCache: ObservableObject {
    static let shared = LogoCache()
    @Published private(set) var images: [Platform: NSImage] = [:]
    private var requested = Set<Platform>()

    func request(_ p: Platform) {
        guard let domain = p.domain, requested.insert(p).inserted else { return }
        let file = Paths.logos.appendingPathComponent("\(p.rawValue).png")
        // Disk and network both off the main thread.
        Task.detached(priority: .utility) {
            if let d = try? Data(contentsOf: file), let img = NSImage(data: d) {
                await MainActor.run { LogoCache.shared.images[p] = img }
                return
            }
            guard let u = URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=64"),
                  let (d, r) = try? await URLSession.shared.data(for: URLRequest(url: u, timeoutInterval: 12)), (r as? HTTPURLResponse)?.statusCode == 200,
                  let img = NSImage(data: d) else { return }
            try? d.write(to: file, options: .atomic)
            await MainActor.run { LogoCache.shared.images[p] = img }
        }
    }
}

struct PlatformLogo: View {
    let platform: Platform
    var size: CGFloat = 16
    @ObservedObject private var cache = LogoCache.shared

    var body: some View {
        Group {
            if let img = cache.images[platform] {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            } else {
                Image(systemName: platform.symbol).resizable().aspectRatio(contentMode: .fit)
                    .foregroundStyle(Color(platform.color)).padding(size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .onAppear { cache.request(platform) }
    }
}
