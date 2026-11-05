// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import AppKit
import SwiftUI

/// What one cell shows (plain values: cells are AppKit views, recycled while scrolling).
struct GameCell {
    var text = ""
    var secondary: String?
    var color: NSColor = .labelColor
    var symbol: String?
    var symbolColor: NSColor?
    var star = false                       // small yellow star after the text (favourites)
    var cover: Game?                       // 22×33 cover before the text
    var logos: [(Platform, Bool)] = []     // platform, dimmed
    var tooltip: String?
    var monospaced = false
}

struct GameTableColumn {
    let id: String
    let title: String
    var width: CGFloat = 120
    var minWidth: CGFloat = 50
    var maxWidth: CGFloat = 2000
    let cell: @MainActor (GameGroup) -> GameCell
}

/// Game table backed by NSTableView with a fixed row height. SwiftUI's `Table` measured every row
/// through a hosting view (automatic row heights): opening or leaving a table of 1 500 games
/// blocked the window for up to a second. Here only the visible rows exist, built with plain
/// AppKit views and layers; the context menu is built on right click only.
struct NativeGameTable: NSViewRepresentable {
    let lib: Library
    let groups: [GameGroup]
    let columns: [GameTableColumn]
    /// Column widths are remembered under this name.
    let autosaveName: String
    var extraMenu: (@MainActor (GameGroup) -> [NSMenuItem])?
    let onOpen: @MainActor (GameGroup) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let table = GameNSTableView()
        table.style = .inset
        table.usesAlternatingRowBackgroundColors = true
        table.usesAutomaticRowHeights = false
        table.allowsMultipleSelection = false
        table.allowsColumnReordering = true
        table.columnAutoresizingStyle = .reverseSequentialColumnAutoresizingStyle
        table.intercellSpacing = NSSize(width: 8, height: 2)
        for c in columns {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(c.id))
            col.title = c.title
            col.width = c.width
            col.minWidth = c.minWidth
            col.maxWidth = c.maxWidth
            table.addTableColumn(col)
        }
        table.rowHeight = columns.contains { $0.id == "title" } ? 38 : 24
        table.autosaveName = autosaveName
        table.autosaveTableColumns = true
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        table.onReturn = { [weak coordinator = context.coordinator] in coordinator?.openSelected() }
        let menu = NSMenu()
        menu.delegate = context.coordinator
        table.menu = menu
        context.coordinator.table = table
        context.coordinator.parent = self
        context.coordinator.observeSelection()

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(self)
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        weak var table: NSTableView?
        var parent: NativeGameTable?
        private var ids: [String] = []
        private var syncing = false

        func update(_ p: NativeGameTable) {
            parent = p
            // Column titles can change (performance targets in the headers).
            for c in p.columns { table?.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(c.id))?.title = c.title }
            guard let table else { return }
            let newIds = p.groups.map(\.id)
            syncing = true
            defer { syncing = false }
            if newIds != ids {
                ids = newIds
                table.reloadData()
            } else {
                // Same rows: refresh what is visible only (status, verdicts, covers…).
                let visible = table.rows(in: table.visibleRect)
                if visible.length > 0 {
                    table.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<(visible.location + visible.length)),
                                     columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
                }
            }
            syncSelection()
        }

        /// The selection is followed here, outside SwiftUI: clicking a row never re-evaluates the page.
        func observeSelection() {
            withObservationTracking { _ = parent?.lib.selected } onChange: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.table != nil else { return }
                    self.syncSelection()
                    self.observeSelection()
                }
            }
        }

        private func syncSelection() {
            guard let table else { return }
            syncing = true
            defer { syncing = false }
            let row = parent?.lib.selected.flatMap { ids.firstIndex(of: $0) }
            if let row {
                if table.selectedRow != row {
                    table.selectRowIndexes([row], byExtendingSelection: false)
                    table.scrollRowToVisible(row)
                }
            } else if table.selectedRow >= 0 {
                table.deselectAll(nil)
            }
        }

        func openSelected() {
            guard let table, let g = group(table.selectedRow) else { return }
            parent?.onOpen(g)
        }

        // Typing letters jumps to a game (first column's text).
        func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
            guard let p = parent, let g = group(row), tableColumn?.identifier.rawValue == p.columns.first?.id else { return nil }
            return p.columns.first?.cell(g).text
        }

        private func group(_ row: Int) -> GameGroup? {
            guard let p = parent, row >= 0, row < p.groups.count else { return nil }
            return p.groups[row]
        }

        func numberOfRows(in tableView: NSTableView) -> Int { parent?.groups.count ?? 0 }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let p = parent, let tableColumn, let g = group(row),
                  let col = p.columns.first(where: { $0.id == tableColumn.identifier.rawValue }) else { return nil }
            let id = NSUserInterfaceItemIdentifier("cell")
            let v = (tableView.makeView(withIdentifier: id, owner: nil) as? GameCellView) ?? {
                let c = GameCellView(); c.identifier = id; return c
            }()
            v.configure(col.cell(g))
            return v
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !syncing, let table, let lib = parent?.lib else { return }
            let id = group(table.selectedRow)?.id
            if lib.selected != id { lib.selected = id }
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            guard let g = group(sender.clickedRow) else { return }
            parent?.onOpen(g)
        }

        // Context menu, built when it opens.
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table, let p = parent, let g = group(table.clickedRow) else { return }
            let built = TileMenu.build(g, lib: p.lib)
            let items = built.items
            built.removeAllItems()
            items.forEach(menu.addItem)
            if let extra = p.extraMenu?(g), !extra.isEmpty {
                menu.addItem(.separator())
                extra.forEach(menu.addItem)
            }
        }
    }
}

/// Return / Enter opens the selected game, like a double click.
final class GameNSTableView: NSTableView {
    var onReturn: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76, selectedRow >= 0, let onReturn { onReturn() } else { super.keyDown(with: event) }
    }
}

/// One cell: optional cover, optional symbol, text (+ secondary line), optional platform logos.
final class GameCellView: NSTableCellView {
    private let cover = CALayer()
    private let symbolView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let secondaryLabel = NSTextField(labelWithString: "")
    private var logoLayers: [CALayer] = []
    private var content = GameCell()
    private var coverKey = ""
    private var loadTask: Task<Void, Never>?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        cover.masksToBounds = true
        cover.cornerRadius = 3
        cover.contentsGravity = .resizeAspectFill
        cover.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(cover)
        symbolView.imageScaling = .scaleProportionallyDown
        addSubview(symbolView)
        for t in [label, secondaryLabel] {
            t.lineBreakMode = .byTruncatingTail
            t.maximumNumberOfLines = 1
            t.cell?.truncatesLastVisibleLine = true
            addSubview(t)
        }
        secondaryLabel.font = .systemFont(ofSize: 10)
        secondaryLabel.textColor = .secondaryLabelColor
        textField = label
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

    private static let bodyFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    private static let monoFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    private static var symbols: [String: NSImage] = [:]
    private static func symbol(_ name: String) -> NSImage? {
        if let i = symbols[name] { return i }
        let i = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        symbols[name] = i
        return i
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
    }

    @MainActor
    func configure(_ c: GameCell) {
        content = c
        let font: NSFont = c.monospaced ? Self.monoFont : Self.bodyFont
        if c.star {
            let a = NSMutableAttributedString(string: c.text, attributes: [.font: font, .foregroundColor: c.color])
            a.append(NSAttributedString(string: "  ★", attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.systemYellow, .baselineOffset: 1]))
            label.attributedStringValue = a
        } else {
            label.font = font
            label.textColor = c.color
            label.stringValue = c.text
        }
        secondaryLabel.stringValue = c.secondary ?? ""
        secondaryLabel.isHidden = c.secondary == nil
        toolTip = c.tooltip
        if let s = c.symbol {
            symbolView.image = Self.symbol(s)
            symbolView.contentTintColor = c.symbolColor ?? c.color
            symbolView.isHidden = false
        } else { symbolView.isHidden = true; symbolView.image = nil }
        for (i, l) in logoLayers.enumerated() {
            if i < c.logos.count {
                let (p, dim) = c.logos[i]
                l.contents = LayerImages.logo(p)
                l.opacity = dim ? 0.4 : 1
                l.isHidden = false
                LogoCache.shared.request(p)
            } else { l.isHidden = true; l.contents = nil }
        }
        if let g = c.cover {
            cover.isHidden = false
            cover.backgroundColor = g.platform.color.withAlphaComponent(0.18).cgColor
            let key = CoverStore.key(g, poster: true)
            if key != coverKey {
                coverKey = key
                loadTask?.cancel()
                if let img = coverMemory.object(forKey: key as NSString) {
                    cover.contents = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
                } else {
                    cover.contents = nil
                    loadTask = Task { @MainActor [weak self] in
                        let img = await CoverStore.shared.image(for: g, poster: true)
                        guard let self, !Task.isCancelled, self.coverKey == key, let img else { return }
                        self.cover.contents = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    }
                }
            }
        } else {
            cover.isHidden = true
            cover.contents = nil
            coverKey = ""
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let h = bounds.height
        var x: CGFloat = 2
        if !cover.isHidden {
            cover.frame = CGRect(x: x, y: (h - 33) / 2, width: 22, height: 33)
            x += 30
        }
        if !symbolView.isHidden {
            symbolView.frame = NSRect(x: x, y: (h - 15) / 2, width: 15, height: 15)
            x += 20
        }
        var lx = x
        for l in logoLayers where !l.isHidden {
            l.frame = CGRect(x: lx, y: (h - 15) / 2, width: 15, height: 15)
            lx += 19
        }
        let textX = content.logos.isEmpty ? x : lx
        let w = max(0, bounds.width - textX - 2)
        if secondaryLabel.isHidden {
            label.frame = NSRect(x: textX, y: (h - 17) / 2, width: w, height: 17)
        } else {
            label.frame = NSRect(x: textX, y: h / 2 - 1, width: w, height: 17)
            secondaryLabel.frame = NSRect(x: textX, y: h / 2 - 15, width: w, height: 14)
        }
        CATransaction.commit()
    }
}
