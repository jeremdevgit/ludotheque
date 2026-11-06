// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI
import GameController

/// Couch / TV mode (Playnite "Fullscreen mode"): big covers, gamepad or
/// keyboard navigation. Arrows/D-pad move, A/Return play, B/Esc quit,
/// LB/RB or Q/E switch tab, Y/F favourite, X/R random.
@MainActor
final class TVModel: ObservableObject {
    @Published var index = 0
    @Published var tab = 0
    let tabs: [(String, Scope)] = [(String(localized: "Installés"), .installed), (String(localized: "Jouables"), .playable), (String(localized: "Récents"), .recent),
                                   (String(localized: "Favoris"), .favorites), (String(localized: "Cloud"), .cloud), (String(localized: "Tous"), .all)]
    weak var lib: Library?
    weak var window: NSWindow?
    var close: (() -> Void)?
    private var keyMonitor: Any?
    private var repeatTask: Task<Void, Never>?
    private var lastStickDir = 0

    func items() -> [GameGroup] {
        guard let lib else { return [] }
        let scope = tabs[tab].1
        return lib.groups.filter { $0.games.contains { lib.matches($0, scope) } }
            .sorted { (lib.lastPlayed($0) ?? .distantPast, lib.title($1)) > (lib.lastPlayed($1) ?? .distantPast, lib.title($0)) }
    }

    func start() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window != nil, e.window === self.window else { return e }
            switch e.keyCode {
            case 123: self.move(-1)
            case 124: self.move(1)
            case 125: self.move(5)
            case 126: self.move(-5)
            case 36, 49: self.play()
            case 53: self.close?()
            default:
                switch e.charactersIgnoringModifiers?.lowercased() {
                case "q": self.switchTab(-1)
                case "e": self.switchTab(1)
                case "f": self.favorite()
                case "r": self.random()
                default: return e
                }
            }
            return nil
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.bindControllers() }
        }
        GCController.startWirelessControllerDiscovery {}
        bindControllers()
    }

    func stop() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        GCController.stopWirelessControllerDiscovery()
        for c in GCController.controllers() { c.extendedGamepad?.valueChangedHandler = nil }
    }

    private func bindControllers() {
        for c in GCController.controllers() {
            guard let pad = c.extendedGamepad else { continue }
            pad.buttonA.pressedChangedHandler = { [weak self] _, _, p in if p { Task { @MainActor in self?.play() } } }
            pad.buttonB.pressedChangedHandler = { [weak self] _, _, p in if p { Task { @MainActor in self?.close?() } } }
            pad.buttonY.pressedChangedHandler = { [weak self] _, _, p in if p { Task { @MainActor in self?.favorite() } } }
            pad.buttonX.pressedChangedHandler = { [weak self] _, _, p in if p { Task { @MainActor in self?.random() } } }
            pad.leftShoulder.pressedChangedHandler = { [weak self] _, _, p in if p { Task { @MainActor in self?.switchTab(-1) } } }
            pad.rightShoulder.pressedChangedHandler = { [weak self] _, _, p in if p { Task { @MainActor in self?.switchTab(1) } } }
            pad.dpad.valueChangedHandler = { [weak self] _, x, y in Task { @MainActor in self?.stick(x, y) } }
            pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in Task { @MainActor in self?.stick(x, y) } }
        }
    }

    /// Direction with auto-repeat while held.
    private func stick(_ x: Float, _ y: Float) {
        let dir = x > 0.5 ? 1 : x < -0.5 ? -1 : y > 0.5 ? -5 : y < -0.5 ? 5 : 0
        guard dir != lastStickDir else { return }
        lastStickDir = dir
        repeatTask?.cancel()
        guard dir != 0 else { return }
        move(dir)
        repeatTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            while !Task.isCancelled { move(dir); try? await Task.sleep(for: .milliseconds(110)) }
        }
    }

    func move(_ d: Int) {
        let n = items().count
        guard n > 0 else { return }
        index = min(max(0, index + d), n - 1)
    }

    func switchTab(_ d: Int) {
        tab = (tab + d + tabs.count) % tabs.count
        index = 0
    }

    func play() {
        let list = items()
        guard list.indices.contains(index), let lib else { return }
        let g = list[index].primary
        if g.launchKind != .none { lib.launch(g) }
    }

    func favorite() {
        let list = items()
        guard list.indices.contains(index) else { return }
        lib?.toggleFavorite(list[index])
        objectWillChange.send()
    }

    func random() {
        let n = items().count
        if n > 0 { index = Int.random(in: 0..<n) }
    }
}

struct TVModeView: View {
    @Environment(Library.self) var lib
    @Environment(\.dismissWindow) private var dismissWindow
    @StateObject private var model = TVModel()

    var body: some View {
        let items = model.items()
        let current = items.indices.contains(model.index) ? items[model.index] : nil
        ZStack {
            Color.black.ignoresSafeArea()
            if let current {
                CoverImage(game: lib.coverGame(current))
                    .blur(radius: 40).opacity(0.45).ignoresSafeArea()
                    .id(current.id).transition(.opacity)
            }
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 26) {
                    Text("LB").tvHint()
                    ForEach(Array(model.tabs.enumerated()), id: \.offset) { i, t in
                        Text(t.0).font(.system(size: 26, weight: i == model.tab ? .bold : .regular))
                            .foregroundStyle(i == model.tab ? .white : .white.opacity(0.45))
                            .onTapGesture { model.tab = i; model.index = 0 }
                    }
                    Text("RB").tvHint()
                    Spacer()
                    Text(Date.now, style: .time).font(.system(size: 24, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 60).padding(.top, 40)

                Spacer()

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 28) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, g in
                                CoverImage(game: lib.coverGame(g))
                                    .frame(width: i == model.index ? 260 : 200, height: i == model.index ? 390 : 300)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(.white, lineWidth: i == model.index ? 4 : 0))
                                    .shadow(color: .black.opacity(0.6), radius: i == model.index ? 24 : 8)
                                    .opacity(g.primary.launchKind == .none ? 0.5 : 1)
                                    .onTapGesture(count: 2) { model.index = i; model.play() }
                                    .onTapGesture { model.index = i }
                                    .id(g.id)
                            }
                        }
                        .padding(.horizontal, 60).frame(height: 420)
                    }
                    .onChange(of: model.index) { _, i in
                        if items.indices.contains(i) { withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(items[i].id, anchor: .center) } }
                    }
                }

                if let current {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Text(lib.title(current)).font(.system(size: 40, weight: .bold)).foregroundStyle(.white)
                            if lib.isFavorite(current) { Image(systemName: "star.fill").font(.title).foregroundStyle(.yellow) }
                        }
                        HStack(spacing: 14) {
                            ForEach(current.bestPerPlatform) { PlatformLogo(platform: $0.platform, size: 26) }
                            Label(current.primary.launchKind.label, systemImage: current.primary.launchKind.symbol)
                            let m = lib.playtime(current)
                            if m > 0 { Label("\(m / 60) h \(m % 60) min", systemImage: "clock") }
                            let s = lib.statusOf(current)
                            if s != .none { Label(s.label, systemImage: s.symbol) }
                        }
                        .font(.title3).foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 60)
                } else {
                    Text("Aucun jeu dans cet onglet").font(.title).foregroundStyle(.white.opacity(0.6)).padding(.horizontal, 60)
                }

                Spacer()

                HStack(spacing: 30) {
                    hint("A", String(localized: "Jouer")); hint("B", String(localized: "Quitter")); hint("X", String(localized: "Au hasard")); hint("Y", String(localized: "Favori"))
                    Spacer()
                    Text("Clavier : flèches · Entrée · Échap · Q/E · R · F").foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 60).padding(.bottom, 36)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.index)
        .background(WindowAccessor { w in
            model.window = w
            if !w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) }
        })
        .onAppear {
            model.lib = lib
            model.close = { dismissWindow(id: "tv") }
            model.start()
        }
        .onDisappear { model.stop() }
    }

    private func hint(_ b: String, _ t: String) -> some View {
        HStack(spacing: 8) { Text(b).tvHint(); Text(t).foregroundStyle(.white.opacity(0.8)) }.font(.title3)
    }
}

private extension Text {
    func tvHint() -> some View {
        font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Hands the hosting NSWindow to SwiftUI code once it exists.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { onWindow(w) } }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
