// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation

/// Image endpoints published by GOG's GamesDB. Keep remote metadata on GOG's HTTPS image hosts.
enum GOGImageURL {
    static func make(_ template: String?, formatter: String, fileExtension: String) -> String? {
        guard let template else { return nil }
        let value = template
            .replacingOccurrences(of: "{formatter}", with: formatter)
            .replacingOccurrences(of: "{ext}", with: fileExtension)
        guard let url = URL(string: value), isAllowed(url) else { return nil }
        return url.absoluteString
    }

    static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        return isAllowedHost(host)
    }

    static func isAllowedHost(_ host: String) -> Bool {
        let host = host.lowercased()
        if host == "images.gog.com" { return true }
        for suffix in ["gog.com", "gog-statics.com"] {
            for number in 1...4 where host == "images-\(number).\(suffix)" { return true }
        }
        return false
    }
}
