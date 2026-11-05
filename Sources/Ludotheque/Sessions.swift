// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import AppKit

/// Playtime counter: after a launch, the next app that starts (that isn't a
/// launcher or a browser) is assumed to be the game and timed until it quits.
@MainActor
final class PlaySessions {
    private var pending: (key: String, at: Date)?
    private var active: [pid_t: (key: String, start: Date)] = [:]
    private let onSession: (String, Int) -> Void
    private static let ignored: Set<String> = Set(Launchers.bundleIds.values).union([
        Launchers.heroic, Launchers.geforceNow, "com.valvesoftware.steam.helper", "com.epicgames.UnrealEngine.CrashReportClient",
        "com.apple.Safari", "com.google.Chrome", "com.brave.Browser", "org.mozilla.firefox", "com.microsoft.edgemac",
        "company.thebrowser.Browser", "com.operasoftware.Opera", "com.hnc.Discord", "com.tinyspeck.slackmacgap",
        "ru.keepcoder.Telegram", "net.whatsapp.WhatsApp", "com.microsoft.teams2", "com.spotify.client",
    ])

    init(onSession: @escaping (String, Int) -> Void) {
        self.onSession = onSession
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.launched(app) }
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.terminated(app) }
        }
    }

    /// The game's process is not known yet (launched through a URL scheme).
    func expect(_ key: String) { pending = (key, Date()) }

    /// The game's process is known (direct .app or emulator launch).
    func track(_ key: String, pid: pid_t) {
        pending = nil
        active[pid] = (key, Date())
    }

    private func launched(_ app: NSRunningApplication?) {
        guard let app, let p = pending, Date().timeIntervalSince(p.at) < 180 else { return }
        let bundle = app.bundleIdentifier ?? ""
        if Self.ignored.contains(bundle) || bundle.hasPrefix("com.apple.") || bundle == Bundle.main.bundleIdentifier { return }
        if app.activationPolicy != .regular { return }
        // Ignore apps that declare a non-game category (chat, browser, utilities…).
        if let url = app.bundleURL, let cat = (Bundle2.info(url)?["LSApplicationCategoryType"] as? String)?.lowercased(),
           !cat.isEmpty, !cat.contains("game") { return }
        track(p.key, pid: app.processIdentifier)
    }

    private func terminated(_ app: NSRunningApplication?) {
        guard let pid = app?.processIdentifier, let s = active.removeValue(forKey: pid) else { return }
        let minutes = Int(Date().timeIntervalSince(s.start) / 60)
        if minutes >= 1 { onSession(s.key, minutes) }
    }
}
