// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI
import AppKit

/// Library grid backed by NSCollectionView: tiles are recycled and drawn with plain layers,
/// so scrolling keeps up with the display refresh rate (60 Hz, 120 Hz ProMotion, 144 Hz…).
struct GameCollectionView: NSViewRepresentable {
    @Environment(Library.self) var lib
    @ObservedObject private var style = TileStyleStore.shared
    @ObservedObject private var logos = LogoCache.shared
    let sections: [(String, [GameGroup])]
    let tileWidth: Double
    /// Passed explicitly (read by the parent view), so external changes always reach the grid.
    let selected: String?
    let scrollTarget: String?
    let dataVersion: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 18
        layout.minimumLineSpacing = 22
        layout.sectionInset = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        let cv = NSCollectionView()
        cv.collectionViewLayout = layout
        cv.isSelectable = true
        cv.allowsMultipleSelection = false
        cv.backgroundColors = [.clear]
        cv.register(TileItem.self, forItemWithIdentifier: TileItem.id)
        cv.register(SectionHeader.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader, withIdentifier: SectionHeader.id)
        cv.dataSource = context.coordinator
        cv.delegate = context.coordinator
        let scroll = NSScrollView()
        scroll.documentView = cv
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        // The AppKit view extends under the fixed progress bar (28 pt): inset the content by that much.
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 28, left: 0, bottom: 0, right: 0)
        scroll.scrollerInsets = NSEdgeInsets(top: 28, left: 0, bottom: 0, right: 0)
        context.coordinator.collection = cv
        context.coordinator.scroll = scroll
        #if DEBUG
        // `-debugAutoScroll YES`: smooth continuous scroll (≈2400 pt/s) for performance measurements.
        if UserDefaults.standard.bool(forKey: "debugAutoScroll") {
            Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak scroll] t in
                guard let scroll, let doc = scroll.documentView else { t.invalidate(); return }
                let clip = scroll.contentView
                var y = clip.bounds.origin.y + 40
                if y > doc.bounds.height - clip.bounds.height { y = 0 }
                clip.scroll(to: NSPoint(x: 0, y: y))
                scroll.reflectScrolledClipView(clip)
            }
        }
        #endif
        // NSCollectionView creates the tiles that scroll into view from the clip view's bounds-change
        // notifications: they must stay on (turning them off left only the first row displayed).
        scroll.contentView.postsBoundsChangedNotifications = true
        cv.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.frameChanged),
                                               name: NSView.frameDidChangeNotification, object: cv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(lib: lib, sections: sections, tileWidth: tileWidth, style: style.style, logosCount: logos.images.count,
                                   selected: selected, scrollTarget: scrollTarget, dataVersion: dataVersion)
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
        weak var collection: NSCollectionView?
        weak var scroll: NSScrollView?
        var lib: Library?
        var sections: [(String, [GameGroup])] = []
        var tileWidth: Double = 150
        var style = TileStyle()
        private var ids: [[String]] = []
        private var lastWidth: CGFloat = 0
        private var lastScrollTarget: String?
        private var lastSelected: String?
        private var logosCount = 0
        private var dataVersion = -1

        func update(lib: Library, sections: [(String, [GameGroup])], tileWidth: Double, style: TileStyle, logosCount: Int,
                    selected: String?, scrollTarget: String?, dataVersion: Int) {
            self.lib = lib
            let newIds = sections.map { $0.1.map(\.id) }
            let structureChanged = newIds != ids || sections.map(\.0) != self.sections.map(\.0)
            let sizeChanged = tileWidth != self.tileWidth || style != self.style
            // Visible tiles are reconfigured only when what they show may have changed
            // (not on a mere selection change).
            let contentChanged = sizeChanged || dataVersion != self.dataVersion || logosCount != self.logosCount
            self.sections = sections
            self.tileWidth = tileWidth
            self.style = style
            self.dataVersion = dataVersion
            guard let cv = collection else { return }
            if structureChanged {
                ids = newIds
                cv.reloadData()
            } else if contentChanged {
                if sizeChanged { cv.collectionViewLayout?.invalidateLayout() }
                // Same items: refresh only what is on screen (favourites, status, covers…).
                for ip in cv.indexPathsForVisibleItems() {
                    (cv.item(at: ip) as? TileItem)?.configure(group(ip), lib: lib, style: style)
                }
            }
            self.logosCount = logosCount
            syncSelection(selected)
            if let t = scrollTarget, t != lastScrollTarget, let ip = indexPath(of: t) {
                lastScrollTarget = t
                cv.scrollToItems(at: [ip], scrollPosition: .centeredVertically)
            }
        }

        private func group(_ ip: IndexPath) -> GameGroup { sections[ip.section].1[ip.item] }

        private func indexPath(of id: String) -> IndexPath? {
            for (s, list) in ids.enumerated() { if let i = list.firstIndex(of: id) { return IndexPath(item: i, section: s) } }
            return nil
        }

        private func syncSelection(_ id: String?) {
            guard let cv = collection, id != lastSelected else { return }
            lastSelected = id
            if let id, let ip = indexPath(of: id) { cv.selectionIndexPaths = [ip] } else { cv.selectionIndexPaths = [] }
        }

        @objc func frameChanged() {
            guard let cv = collection, abs(cv.bounds.width - lastWidth) > 0.5 else { return }
            lastWidth = cv.bounds.width
            cv.collectionViewLayout?.invalidateLayout()
        }

        // Data source
        func numberOfSections(in collectionView: NSCollectionView) -> Int { sections.count }
        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { sections[section].1.count }

        func collectionView(_ cv: NSCollectionView, itemForRepresentedObjectAt ip: IndexPath) -> NSCollectionViewItem {
            let item = cv.makeItem(withIdentifier: TileItem.id, for: ip) as! TileItem
            if let lib { item.configure(group(ip), lib: lib, style: style) }
            return item
        }

        func collectionView(_ cv: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                            at ip: IndexPath) -> NSView {
            let v = cv.makeSupplementaryView(ofKind: kind, withIdentifier: SectionHeader.id, for: ip) as! SectionHeader
            v.set(sections[ip.section].0, count: sections[ip.section].1.count)
            return v
        }

        // Layout: fixed column count from the width → items fill the row exactly.
        func collectionView(_ cv: NSCollectionView, layout: NSCollectionViewLayout, sizeForItemAt ip: IndexPath) -> NSSize {
            let width = cv.bounds.width - 40
            let spacing: CGFloat = 18
            let n = max(1, Int((width + spacing) / (CGFloat(tileWidth) + spacing)))
            let w = min(CGFloat(tileWidth) * 1.25, floor((width - spacing * CGFloat(n - 1)) / CGFloat(n)))
            var h = w / tileAspectRatio(style.aspect)
            if style.title { h += style.font == "large" ? 24 : style.font == "small" ? 18 : 21 }
            if style.logos || style.subtitle { h += 22 }
            return NSSize(width: w, height: ceil(h) + 6)
        }

        func collectionView(_ cv: NSCollectionView, layout: NSCollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> NSSize {
            sections[section].0.isEmpty ? .zero : NSSize(width: cv.bounds.width, height: 36)
        }

        // Selection → details panel
        func collectionView(_ cv: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            guard let ip = indexPaths.first else { return }
            let id = group(ip).id
            lastSelected = id
            if lib?.selected != id { lib?.selected = id }
        }
    }
}

// MARK: - Pre-rendered layer images

/// SF Symbols and logos rendered once into bitmaps, then shared by every tile and row. Handing a
/// symbol NSImage to a layer or an image view re-rendered it for each tile shown while scrolling.
@MainActor
enum LayerImages {
    private static var cache: [String: CGImage] = [:]
    static var scale: CGFloat { NSScreen.main?.backingScaleFactor ?? 2 }

    static func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular, colors: [NSColor]) -> CGImage? {
        let appearance = NSApp.effectiveAppearance
        let key = "\(name)|\(size)|\(weight.rawValue)|\(colors.map(\.description).joined(separator: ","))|\(appearance.name.rawValue)|\(scale)"
        if let c = cache[key] { return c }
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: weight).applying(.init(paletteColors: colors))) else { return nil }
        let c = render(img, appearance: appearance)
        cache[key] = c
        return c
    }

    /// The platform's real logo once downloaded, its SF Symbol meanwhile.
    static func logo(_ p: Platform) -> CGImage? {
        if let img = LogoCache.shared.images[p] {
            let key = "logo|\(p.rawValue)"
            if let c = cache[key] { return c }
            var r = NSRect(x: 0, y: 0, width: 32, height: 32)
            let c = img.cgImage(forProposedRect: &r, context: nil, hints: nil).flatMap { CoverStore.rasterized($0) }
            cache[key] = c
            return c
        }
        return symbol(p.symbol, size: 13, colors: [.secondaryLabelColor])
    }

    private static func render(_ img: NSImage, appearance: NSAppearance) -> CGImage? {
        let size = img.size, sc = scale
        let w = Int(ceil(size.width * sc)), h = Int(ceil(size.height * sc))
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.scaleBy(x: sc, y: sc)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        appearance.performAsCurrentDrawingAppearance { img.draw(in: NSRect(origin: .zero, size: size)) }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}

// MARK: - Tile

final class TileItem: NSCollectionViewItem {
    static let id = NSUserInterfaceItemIdentifier("TileItem")
    private var tile: TileView { view as! TileView }

    override func loadView() { view = TileView() }

    override var isSelected: Bool { didSet { tile.setSelected(isSelected) } }

    @MainActor
    func configure(_ g: GameGroup, lib: Library, style: TileStyle) {
        tile.configure(g, lib: lib, style: style)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        tile.resetForReuse()
    }
}

final class TileView: NSView {
    private let cover = CALayer()
    private let dimLayer = CALayer()
    private let hoverLayer = CALayer()
    private let playIcon = CALayer()
    private let badge = CALayer()
    private let statusDot = CALayer()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private var logoLayers: [CALayer] = []
    private var group: GameGroup?
    private weak var lib: Library?
    private var style = TileStyle()
    private var coverKey = ""
    private var loadTask: Task<Void, Never>?
    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        cover.masksToBounds = true
        cover.contentsGravity = .resizeAspectFill
        cover.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        cover.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]   // no implicit animations
        hoverLayer.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        hoverLayer.isHidden = true
        hoverLayer.actions = ["hidden": NSNull()]
        playIcon.contentsGravity = .center
        hoverLayer.addSublayer(playIcon)
        cover.addSublayer(hoverLayer)
        layer?.addSublayer(cover)
        for l in [badge, statusDot] {
            l.contentsGravity = .resizeAspect
            l.actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]
            layer?.addSublayer(l)
        }
        playIcon.contentsScale = LayerImages.scale
        for t in [title, subtitle] {
            t.lineBreakMode = .byTruncatingTail
            t.maximumNumberOfLines = 1
            t.cell?.truncatesLastVisibleLine = true
            addSubview(t)
        }
        subtitle.textColor = .secondaryLabelColor
        subtitle.font = .systemFont(ofSize: 11)
        for _ in 0..<4 {
            let l = CALayer()
            l.contentsGravity = .resizeAspect
            l.cornerRadius = 3
            l.masksToBounds = true
            l.actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull()]
            layer?.addSublayer(l)
            logoLayers.append(l)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func resetForReuse() {
        loadTask?.cancel()
        loadTask = nil
        cover.contents = nil
        coverKey = ""
        hoverLayer.isHidden = true
    }

    @MainActor
    func configure(_ g: GameGroup, lib: Library, style: TileStyle) {
        self.group = g
        self.lib = lib
        self.style = style
        let game = g.primary
        let kind = game.launchKind
        let coverGame = lib.coverGame(g)
        let poster = style.aspect != "16:9"

        title.stringValue = (lib.isFavorite(g) ? "★ " : "") + lib.title(g)
        title.font = style.font == "small" ? .systemFont(ofSize: 11, weight: .medium) : style.font == "large" ? .systemFont(ofSize: 14, weight: .semibold) : .systemFont(ofSize: 12.5, weight: .medium)
        title.isHidden = !style.title
        subtitle.stringValue = Self.subtitle(g, lib: lib)
        subtitle.isHidden = !style.subtitle
        cover.cornerRadius = style.radius
        hoverLayer.cornerRadius = style.radius
        alphaValue = style.dim && kind == .none ? 0.55 : 1

        // Platform logos (cached images; SF Symbol fallback).
        let platforms = style.logos ? Array(g.bestPerPlatform.prefix(4)) : []
        for (i, l) in logoLayers.enumerated() {
            if i < platforms.count {
                let p = platforms[i].platform
                l.contents = LayerImages.logo(p)
                l.opacity = platforms[i].launchKind == .none ? 0.4 : 1
                l.isHidden = false
                LogoCache.shared.request(p)
            } else { l.isHidden = true; l.contents = nil }
        }

        // Badges
        let badgeInfo: (String, NSColor)? = !style.badge ? nil : {
            switch kind {
            case .installed: ("checkmark.circle.fill", .systemGreen)
            case .installable: ("arrow.down.circle.fill", .systemOrange)
            case .cloud: ("cloud.circle.fill", .systemBlue)
            case .none: nil
            }
        }()
        if let (sym, color) = badgeInfo {
            badge.contents = LayerImages.symbol(sym, size: 17, colors: [.white, color])
            badge.isHidden = false
        } else { badge.isHidden = true; badge.contents = nil }
        let status = lib.statusOf(g)
        if style.status && status != .none {
            statusDot.contents = LayerImages.symbol(status.symbol, size: 16, weight: .bold, colors: [NSColor(status.color)])
            statusDot.isHidden = false
        } else { statusDot.isHidden = true; statusDot.contents = nil }
        playIcon.contents = LayerImages.symbol(kind == .installed ? "play.fill" : kind == .cloud ? "cloud.fill" : "arrow.down.circle.fill",
                                               size: 30, weight: .semibold, colors: [.white])

        // Cover: synchronous memory hit, otherwise loaded off the main thread and applied if still current.
        let key = CoverStore.key(coverGame, poster: poster)
        let isIcon = coverGame.coverURL == nil && coverGame.altCoverURL == nil
        cover.contentsGravity = isIcon ? .resizeAspect : .resizeAspectFill
        cover.backgroundColor = coverGame.platform.color.withAlphaComponent(0.18).cgColor
        if key != coverKey {
            coverKey = key
            loadTask?.cancel()
            if let img = coverMemory.object(forKey: key as NSString) {
                cover.contents = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
            } else {
                cover.contents = nil
                loadTask = Task { @MainActor [weak self] in
                    let img = await CoverStore.shared.image(for: coverGame, poster: poster)
                    guard let self, !Task.isCancelled, self.coverKey == key, let img else { return }
                    self.cover.contents = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
                }
            }
        }
        needsLayout = true
    }

    private static func subtitle(_ g: GameGroup, lib: Library) -> String {
        var parts = [String]()
        switch g.primary.launchKind {
        case .installed: parts.append("Installé")
        case .installable: parts.append("À installer")
        case .cloud: parts.append("Cloud")
        case .none: if g.games.count == 1 && g.primary.macNative == false { parts.append("Pas sur Mac") }
        }
        let m = lib.playtime(g)
        if m > 0 { parts.append(m >= 60 ? "\(m / 60) h" : "\(m) min") }
        return parts.joined(separator: " · ")
    }

    /// Light / dark switch: the pre-rendered symbols and colours are taken again for this appearance.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if let group, let lib { configure(group, lib: lib, style: style) }
    }

    func setSelected(_ s: Bool) {
        cover.borderWidth = s ? 3 : 0
        cover.borderColor = NSColor.controlAccentColor.cgColor
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let w = bounds.width
        let ch = w / tileAspectRatio(style.aspect)
        cover.frame = CGRect(x: 0, y: 0, width: w, height: ch)
        hoverLayer.frame = cover.bounds
        playIcon.frame = hoverLayer.bounds
        badge.frame = CGRect(x: w - 26, y: 6, width: 20, height: 20)
        statusDot.frame = CGRect(x: 6, y: 6, width: 20, height: 20)
        var y = ch + 4
        if style.title {
            let th: CGFloat = style.font == "large" ? 20 : style.font == "small" ? 15 : 17
            title.frame = NSRect(x: 0, y: y, width: w, height: th)
            y += th + 2
        }
        var x: CGFloat = 0
        for l in logoLayers where !l.isHidden {
            l.frame = CGRect(x: x, y: y + 1, width: 16, height: 16)
            x += 21
        }
        subtitle.frame = NSRect(x: x, y: y, width: max(0, w - x), height: 16)
        CATransaction.commit()
    }

    // Hover overlay (no animation).
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }
    override func mouseEntered(with event: NSEvent) {
        if style.hover, group?.primary.launchKind != LaunchKind.none { hoverLayer.isHidden = false }
    }
    override func mouseExited(with event: NSEvent) { hoverLayer.isHidden = true }

    // Double click launches (single click is handled by the collection view selection).
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard event.clickCount == 2, let g = group, let lib else { return }
        if g.primary.launchKind != .none { lib.launch(g.primary) } else { lib.openStore(g.primary) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let g = group, let lib else { return nil }
        return TileMenu.build(g, lib: lib)
    }
}

final class SectionHeader: NSView, NSCollectionViewElement {
    static let id = NSUserInterfaceItemIdentifier("SectionHeader")
    private let label = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .boldSystemFont(ofSize: 15)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    func set(_ name: String, count: Int) { label.stringValue = "\(name)   \(count)" }
    override func layout() { super.layout(); label.frame = NSRect(x: 24, y: 8, width: bounds.width - 48, height: 20) }
}

// MARK: - Context menu (AppKit version of GroupMenu)

@MainActor
enum TileMenu {
    final class Action: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire() { run() }
    }

    static func item(_ title: String, _ run: @escaping () -> Void) -> NSMenuItem {
        let a = Action(run)
        let it = NSMenuItem(title: title, action: #selector(Action.fire), keyEquivalent: "")
        it.target = a
        it.representedObject = a   // keeps the action alive
        return it
    }

    static func gameActions(_ g: Game, lib: Library) -> [NSMenuItem] {
        var items = [NSMenuItem]()
        switch g.launchKind {
        case .installed: items.append(item("Jouer") { lib.launch(g) })
        case .installable: items.append(item("Installer via \(g.platform.name)") { lib.launch(g) })
        case .cloud: items.append(item("Jouer en streaming") { lib.launch(g) })
        case .none: break
        }
        if lib.geforceNowAvailable && g.launchKind != .installed { items.append(item("Chercher dans GeForce NOW") { lib.openInGeForceNow(g) }) }
        if g.storeURL != nil { items.append(item("Page du jeu") { lib.openStore(g) }) }
        if g.appPath != nil || g.launchURL?.hasPrefix("emu:") == true { items.append(item("Afficher dans le Finder") { lib.reveal(g) }) }
        if g.manualId != nil { items.append(item("Modifier…") { lib.edit(g) }) }
        if g.launchKind == .installed { items.append(item("Désinstaller…") { lib.uninstalling = g }) }
        return items
    }

    static func build(_ grp: GameGroup, lib: Library) -> NSMenu {
        let menu = NSMenu()
        if grp.games.count == 1 {
            gameActions(grp.primary, lib: lib).forEach(menu.addItem)
        } else {
            for g in grp.games {
                let sub = NSMenu()
                gameActions(g, lib: lib).forEach(sub.addItem)
                let it = NSMenuItem(title: "\(g.platform.name) — \(g.launchKind.label)", action: nil, keyEquivalent: "")
                it.submenu = sub
                menu.addItem(it)
            }
        }
        menu.addItem(.separator())
        menu.addItem(item("Afficher les détails") { lib.selected = grp.id })
        let statusMenu = NSMenu()
        for c in Completion.allCases {
            let it = item(c.label) { lib.update(grp.key) { $0.status = c } }
            it.state = lib.statusOf(grp) == c ? .on : .off
            statusMenu.addItem(it)
        }
        let st = NSMenuItem(title: "Statut", action: nil, keyEquivalent: "")
        st.submenu = statusMenu
        menu.addItem(st)
        menu.addItem(item(lib.isFavorite(grp) ? "Retirer des favoris" : "Ajouter aux favoris") { lib.toggleFavorite(grp) })
        menu.addItem(item(lib.isHidden(grp) ? "Ne plus masquer" : "Masquer") { lib.toggleHidden(grp) })
        menu.addItem(item(ProfileStore.shared.profile.showcase.contains(grp.key) ? "Retirer de la vitrine du profil" : "Ajouter à la vitrine du profil") {
            ProfileStore.shared.toggleShowcase(grp.key)
        })
        menu.addItem(item("Ajouter une autre version manuellement…") { lib.duplicateAsManual(grp.primary) })
        return menu
    }
}
