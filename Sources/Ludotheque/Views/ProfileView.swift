// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI

struct ProfileView: View {
    @Environment(Library.self) var lib
    @ObservedObject private var store = ProfileStore.shared
    @ObservedObject private var share = ShareModel.shared

    var body: some View {
        let stats = ProfileStats(lib)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                banner(stats)
                if store.editing { customization }
                ForEach(store.profile.panels) { panel in
                    if store.editing || !store.profile.hiddenPanels.contains(panel) {
                        panelView(panel, stats)
                    }
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $share.presented) { ShareSheet().environment(lib) }
    }

    // MARK: Header

    private func banner(_ stats: ProfileStats) -> some View {
        let p = store.profile
        return ZStack(alignment: .bottomLeading) {
            ZStack {
                store.theme.gradient
                if let path = p.bannerPath, let img = NSImage(contentsOfFile: path) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).opacity(0.55)
                }
            }
            .frame(height: 220).clipped()
            HStack(alignment: .bottom, spacing: 18) {
                avatar.frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.6), lineWidth: 3))
                    .shadow(radius: 10)
                    .onTapGesture { if store.editing { store.pickImage(banner: false) } }
                VStack(alignment: .leading, spacing: 6) {
                    if store.editing {
                        TextField("Ton nom de joueur", text: $store.profile.displayName).font(.title.bold()).textFieldStyle(.plain)
                        TextField("Devise / statut (ex. « Main support depuis 2014 »)", text: $store.profile.tagline).textFieldStyle(.plain)
                    } else {
                        Text(p.displayName.isEmpty ? "Ton profil" : p.displayName).font(.system(size: 34, weight: .heavy))
                        if !p.tagline.isEmpty { Text(p.tagline).font(.title3).opacity(0.9) }
                    }
                    HStack(spacing: 8) {
                        levelBadge(stats)
                        if let fav = stats.favoritePlatform {
                            HStack(spacing: 4) { PlatformLogo(platform: fav, size: 16); Text(fav.name) }
                                .font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.18), in: Capsule())
                        }
                        Text("Membre depuis \(p.memberSince.formatted(.dateTime.month(.wide).year()))").font(.caption).opacity(0.8)
                    }
                }
                .foregroundStyle(.white)
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Button { store.editing.toggle() } label: {
                        Label(store.editing ? "Terminer" : "Modifier le profil", systemImage: store.editing ? "checkmark" : "pencil")
                    }
                    .buttonStyle(.borderedProminent).tint(store.editing ? .green : .white.opacity(0.25))
                    Button { share.presented = true } label: { Label("Partager", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered).tint(.white)
                }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder private var avatar: some View {
        if let path = store.profile.avatarPath, let img = NSImage(contentsOfFile: path) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color.white.opacity(0.2)
                if store.profile.displayName.isEmpty { Image(systemName: "person.fill").font(.system(size: 50)) }
                else { Text(String(store.profile.displayName.prefix(1)).uppercased()).font(.system(size: 54, weight: .bold)) }
                if store.editing { Image(systemName: "camera.fill").padding(6).background(.black.opacity(0.5), in: Circle()).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(6) }
            }
            .foregroundStyle(.white)
        }
    }

    private func levelBadge(_ s: ProfileStats) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().stroke(.white.opacity(0.3), lineWidth: 3)
                Circle().trim(from: 0, to: CGFloat(s.xp - s.level * s.level * 100) / CGFloat(max(1, s.nextLevelXP - s.level * s.level * 100)))
                    .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                Text("\(s.level)").font(.system(size: 12, weight: .bold))
            }
            .frame(width: 30, height: 30)
            Text("Niveau \(s.level)").font(.caption.weight(.semibold))
        }
        .help("\(s.xp) XP — prochain niveau à \(s.nextLevelXP) XP (jeux, heures, jeux terminés, plateformes)")
    }

    // MARK: Customization (edit mode)

    private var customization: some View {
        GroupBox("Personnalisation") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Thème").frame(width: 110, alignment: .leading)
                    ForEach(Array(ProfileTheme.all.enumerated()), id: \.offset) { i, t in
                        Circle().fill(t.gradient).frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Color.primary, lineWidth: store.profile.theme == i ? 2.5 : 0))
                            .help(t.name)
                            .onTapGesture { store.profile.theme = i }
                    }
                }
                HStack {
                    Text("Images").frame(width: 110, alignment: .leading)
                    Button("Avatar…") { store.pickImage(banner: false) }
                    Button("Bannière…") { store.pickImage(banner: true) }
                    if store.profile.bannerPath != nil { Button("Retirer la bannière") { store.profile.bannerPath = nil } }
                }
                HStack {
                    Text("Pays / région").frame(width: 110, alignment: .leading)
                    TextField("🇫🇷 France", text: $store.profile.country).frame(width: 200)
                }
                VStack(alignment: .leading) {
                    Text("Bio")
                    TextEditor(text: $store.profile.bio).frame(height: 60).overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Panneaux (ordre et visibilité)")
                    ForEach(Array(store.profile.panels.enumerated()), id: \.element) { i, p in
                        HStack {
                            Toggle(isOn: Binding(get: { !store.profile.hiddenPanels.contains(p) },
                                                 set: { if $0 { store.profile.hiddenPanels.remove(p) } else { store.profile.hiddenPanels.insert(p) } })) {
                                Label(p.title, systemImage: p.symbol)
                            }
                            Spacer()
                            Button { move(i, -1) } label: { Image(systemName: "chevron.up") }.disabled(i == 0).buttonStyle(.borderless)
                            Button { move(i, 1) } label: { Image(systemName: "chevron.down") }.disabled(i == store.profile.panels.count - 1).buttonStyle(.borderless)
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private func move(_ i: Int, _ d: Int) {
        let j = i + d
        guard store.profile.panels.indices.contains(j) else { return }
        store.profile.panels.swapAt(i, j)
    }

    // MARK: Panels

    @ViewBuilder private func panelView(_ panel: ProfilePanel, _ stats: ProfileStats) -> some View {
        let hidden = store.profile.hiddenPanels.contains(panel)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(panel.title, systemImage: panel.symbol).font(.title3.bold())
                if hidden { Text("masqué").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if store.editing { addButton(panel) }
            }
            switch panel {
            case .tags: tagsPanel
            case .stats: statsPanel(stats)
            case .ranked: rankedPanel
            case .mastery: masteryPanel
            case .favorites: showcasePanel
            case .recent: recentPanel
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(hidden ? 0.5 : 1)
    }

    @ViewBuilder private func addButton(_ panel: ProfilePanel) -> some View {
        switch panel {
        case .tags: Button { store.profile.tags.append(GamerTag()) } label: { Label("Ajouter un pseudo", systemImage: "plus") }
        case .ranked: Button { store.profile.ranked.append(RankedEntry()) } label: { Label("Ajouter un jeu classé", systemImage: "plus") }
        case .mastery: Button { store.profile.mastery.append(MasteryEntry()) } label: { Label("Ajouter un jeu maîtrisé", systemImage: "plus") }
        default: EmptyView()
        }
    }

    private var tagsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.profile.tags.isEmpty { empty("Ajoute tes pseudos Steam, Xbox, PSN, Nintendo, Riot, Battle.net, Discord…") }
            ForEach($store.profile.tags) { $t in
                HStack(spacing: 10) {
                    PlatformLogo(platform: t.platform, size: 22)
                    if store.editing {
                        Picker("", selection: $t.platform) {
                            ForEach(Platform.allCases.filter { $0 != .other }) { Text($0.name).tag($0) }
                        }.labelsHidden().frame(width: 170)
                        TextField("Pseudo", text: $t.name).frame(width: 200)
                        TextField("Lien du profil (facultatif)", text: $t.url)
                        Button(role: .destructive) { store.profile.tags.removeAll { $0.id == t.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    } else {
                        Text(t.name).font(.headline).textSelection(.enabled)
                        Text(t.platform.name).foregroundStyle(.secondary)
                        Spacer()
                        Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t.name, forType: .string); lib.flash("Pseudo copié") } label: {
                            Image(systemName: "doc.on.doc")
                        }.buttonStyle(.borderless).help("Copier le pseudo")
                        if let u = URL(string: t.url), !t.url.isEmpty { Link(destination: u) { Image(systemName: "arrow.up.right.square") } }
                    }
                }
            }
        }
    }

    private func statsPanel(_ s: ProfileStats) -> some View {
        HStack(spacing: 12) {
            tile("\(s.games)", "jeux"); tile("\(s.installed)", "installés"); tile("\(s.hours) h", "de jeu")
            tile("\(s.completed)", "terminés"); tile("\(s.platforms)", "plateformes"); tile("\(SessionLog.shared.thisWeekMinutes / 60) h", "cette semaine")
        }
    }

    private var rankedPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.profile.ranked.isEmpty { empty("Indique tes rangs : League of Legends, Valorant, Rocket League, Overwatch, CS2…") }
            ForEach($store.profile.ranked) { $r in
                HStack(spacing: 12) {
                    gameThumb(r.game)
                    if store.editing {
                        VStack(alignment: .leading) {
                            HStack {
                                gameField($r.game)
                                TextField("Rang (ex. Diamant II)", text: $r.rank).frame(width: 160)
                                Menu("Paliers") {
                                    ForEach(["Fer", "Bronze", "Argent", "Or", "Platine", "Émeraude", "Diamant", "Maître", "Grand Maître", "Challenger"], id: \.self) { t in
                                        Button(t) { r.rank = t }
                                    }
                                }.frame(width: 90)
                            }
                            HStack {
                                TextField("Mode (Solo/Duo, 3v3…)", text: $r.mode)
                                TextField("Saison", text: $r.season)
                                TextField("Meilleur rang", text: $r.peak)
                            }
                        }
                        Button(role: .destructive) { store.profile.ranked.removeAll { $0.id == r.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.game).font(.headline)
                            Text([r.mode, r.season].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: "shield.fill").foregroundStyle(r.color)
                                Text(r.rank).font(.headline).foregroundStyle(r.color)
                            }
                            if !r.peak.isEmpty { Text("Meilleur : \(r.peak)").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
    }

    private var masteryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.profile.mastery.isEmpty { empty("Les jeux que tu maîtrises, ton main, ton niveau…") }
            ForEach($store.profile.mastery) { $m in
                HStack(spacing: 12) {
                    gameThumb(m.game)
                    if store.editing {
                        VStack(alignment: .leading) {
                            HStack {
                                gameField($m.game)
                                Picker("Niveau", selection: $m.level) {
                                    ForEach(1...5, id: \.self) { Text(MasteryEntry.levels[$0]).tag($0) }
                                }.frame(width: 190)
                            }
                            HStack {
                                TextField("Main / rôle / perso / deck", text: $m.main)
                                TextField("Note (ex. 1 200 h, top 500…)", text: $m.note)
                            }
                        }
                        Button(role: .destructive) { store.profile.mastery.removeAll { $0.id == m.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.game).font(.headline)
                            Text([m.main, m.note].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 1) {
                                ForEach(1...5, id: \.self) { i in Image(systemName: i <= m.level ? "star.fill" : "star").foregroundStyle(.yellow) }
                            }
                            Text(m.levelName).font(.caption.weight(.semibold))
                        }
                    }
                }
            }
        }
    }

    private var showcasePanel: some View {
        let games = store.profile.showcase.compactMap { k in lib.groups.first { $0.key == k } }
        return VStack(alignment: .leading, spacing: 8) {
            if games.isEmpty { empty("Clic droit sur un jeu → « Ajouter à la vitrine du profil ».") }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(games) { g in
                        VStack {
                            CoverImage(game: lib.coverGame(g)).frame(width: 120, height: 180).clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(alignment: .topTrailing) {
                                    if store.editing {
                                        Button { store.toggleShowcase(g.key) } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                                            .buttonStyle(.plain).padding(4)
                                    }
                                }
                            Text(lib.title(g)).font(.caption).lineLimit(1).frame(width: 120)
                        }
                        .onTapGesture(count: 2) { lib.launch(g.primary) }
                    }
                }
            }
        }
    }

    private var recentPanel: some View {
        let recent = lib.groups.filter { lib.lastPlayed($0) != nil }.sorted { lib.lastPlayed($0)! > lib.lastPlayed($1)! }.prefix(5)
        return VStack(spacing: 6) {
            ForEach(Array(recent)) { g in
                HStack {
                    CoverImage(game: lib.coverGame(g)).frame(width: 26, height: 39).clipShape(RoundedRectangle(cornerRadius: 3))
                    Text(lib.title(g))
                    Spacer()
                    Text("\(lib.playtime(g) / 60) h").foregroundStyle(.secondary).monospacedDigit()
                    Text(lib.lastPlayed(g)!.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .trailing)
                }
            }
        }
    }

    // MARK: Helpers

    private func gameField(_ b: Binding<String>) -> some View {
        HStack(spacing: 2) {
            TextField("Jeu", text: b).frame(width: 220)
            Menu {
                let q = Integrations.norm(b.wrappedValue)
                let hits = lib.groups.filter { q.isEmpty ? lib.playtime($0) > 0 : Integrations.norm(lib.title($0)).contains(q) }
                    .sorted { lib.playtime($0) > lib.playtime($1) }.prefix(15)
                ForEach(Array(hits)) { g in Button(lib.title(g)) { b.wrappedValue = lib.title(g) } }
            } label: { Image(systemName: "magnifyingglass") }
            .menuStyle(.borderlessButton).frame(width: 28).help("Choisir dans ta bibliothèque")
        }
    }

    @ViewBuilder private func gameThumb(_ title: String) -> some View {
        if let g = lib.groups.first(where: { Integrations.norm(lib.title($0)) == Integrations.norm(title) }) {
            CoverImage(game: lib.coverGame(g)).frame(width: 36, height: 54).clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            RoundedRectangle(cornerRadius: 5).fill(.quaternary).frame(width: 36, height: 54)
                .overlay(Image(systemName: "gamecontroller").foregroundStyle(.secondary))
        }
    }

    private func tile(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.title2.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            Text(l).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func empty(_ t: String) -> some View {
        Text(store.editing ? t : t + " (bouton « Modifier le profil »)").font(.callout).foregroundStyle(.secondary)
    }
}

// MARK: - Share sheet

@MainActor
final class ShareModel: ObservableObject {
    static let shared = ShareModel()
    @Published var presented = false
    @Published var options = ShareOptions()
    @Published var format: ShareFormat = .png
    @Published var preview: ProfileExport.Content?
    @Published var working = false
}

struct ShareSheet: View {
    @Environment(Library.self) var lib
    @ObservedObject private var model = ShareModel.shared
    @ObservedObject private var store = ProfileStore.shared

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Form {
                Section("Informations à partager") {
                    Toggle("Nom, devise et avatar", isOn: $model.options.identity)
                    Toggle("Bio", isOn: $model.options.bio)
                    Toggle("Pseudos", isOn: $model.options.tags)
                    Toggle("Statistiques et niveau", isOn: $model.options.stats)
                    Toggle("Jeux classés", isOn: $model.options.ranked)
                    Toggle("Jeux maîtrisés", isOn: $model.options.mastery)
                    Toggle("Vitrine de jeux", isOn: $model.options.showcase)
                    Toggle("Joués récemment", isOn: $model.options.recent)
                }
                Section("Format") {
                    Picker("Format", selection: $model.format) {
                        ForEach(ShareFormat.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                    Text(model.format.isImage ? "Carte de profil illustrée, prête à poster." : "Données structurées, pour un tableur, un site ou un message.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    HStack {
                        Button("Exporter…") { Task { await export() } }.buttonStyle(.borderedProminent).disabled(model.working)
                        Button("Copier") { Task { await copy() } }.disabled(model.working)
                        ShareLinkButton()
                    }
                    Button("Fermer") { model.presented = false }.keyboardShortcut(.cancelAction)
                }
            }
            .formStyle(.grouped)
            .frame(width: 320)
            Divider()
            ScrollView {
                if let c = model.preview {
                    if model.format.isImage {
                        ProfileCard(content: c, theme: store.theme, options: model.options)
                            .frame(width: 900).scaleEffect(0.5, anchor: .topLeading).frame(width: 450, alignment: .topLeading)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Text(String(data: ProfileExport.export(c, theme: store.theme, options: model.options, format: model.format) ?? Data(), encoding: .utf8) ?? "")
                            .font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else { SkeletonBlock(width: 450, height: 300, radius: 10).skeletonPulse() }
            }
            .padding(16)
            .frame(width: 500)
        }
        .frame(height: 620)
        .task { model.preview = await ProfileExport.gather(lib, store, ShareOptions(identity: true, tags: true, stats: true, ranked: true, mastery: true, showcase: true, recent: true, bio: true)) }
    }

    private func data() async -> Data? {
        guard let c = model.preview else { return nil }
        return ProfileExport.export(c, theme: store.theme, options: model.options, format: model.format)
    }

    private func export() async {
        model.working = true
        defer { model.working = false }
        guard let d = await data() else { lib.flash("Export impossible"); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [model.format.type]
        panel.nameFieldStringValue = "Profil \(store.profile.displayName.isEmpty ? "Ludothèque" : store.profile.displayName)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? d.write(to: url)
        lib.flash("Profil exporté en \(model.format.rawValue)")
    }

    private func copy() async {
        guard let d = await data() else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        switch model.format {
        case .png, .jpeg: if let img = NSImage(data: d) { pb.writeObjects([img]) }
        case .pdf: pb.setData(d, forType: .pdf)
        default: pb.setString(String(data: d, encoding: .utf8) ?? "", forType: .string)
        }
        lib.flash("Copié dans le presse-papiers")
    }
}

/// macOS share menu (Messages, Mail, AirDrop…) for the current export.
private struct ShareLinkButton: View {
    @ObservedObject private var model = ShareModel.shared
    @ObservedObject private var store = ProfileStore.shared

    var body: some View {
        Button {
            guard let c = model.preview, let d = ProfileExport.export(c, theme: store.theme, options: model.options, format: model.format) else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Profil.\(model.format.type.preferredFilenameExtension ?? "dat")")
            try? d.write(to: url)
            let picker = NSSharingServicePicker(items: [url])
            if let v = NSApp.keyWindow?.contentView { picker.show(relativeTo: .zero, of: v, preferredEdge: .minY) }
        } label: { Label("Partager…", systemImage: "square.and.arrow.up") }
    }
}
