// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation
import CryptoKit

extension Integrations {

    // MARK: Steam — Web API key + SteamID

    static let steam = Integration(
        platform: .steam,
        summary: String(localized: "Importe toute la bibliothèque Steam (même les jeux jamais téléchargés sur ce Mac) avec le temps de jeu."),
        steps: [String(localized: "Crée une clé Web API (domaine : « localhost »)."),
                String(localized: "Indique ton SteamID64, ton pseudo personnalisé ou l'URL de ton profil."),
                String(localized: "Dans les paramètres de confidentialité Steam, « Détails des jeux » doit être Public.")],
        links: [(String(localized: "Obtenir une clé API"), "https://steamcommunity.com/dev/apikey"),
                (String(localized: "Confidentialité du profil"), "https://steamcommunity.com/my/edit/settings")],
        fields: [IntegrationField(key: "apiKey", label: String(localized: "Clé Web API"), placeholder: String(localized: "32 caractères hexadécimaux")),
                 IntegrationField(key: "steamId", label: String(localized: "SteamID / profil"), placeholder: String(localized: "7656119… ou pseudo"), secret: false,
                                  prefill: steamLocalUser)],
        connectedKeys: ["apiKey"]
    ) { c in
        guard let key = c["apiKey"], var id = c["steamId"] else { throw SyncError(String(localized: "Clé API et SteamID requis")) }
        if UInt64(id) == nil {
            let vanity = id.split(separator: "/").last.map(String.init) ?? id
            let r = try await HTTP.json("https://api.steampowered.com/ISteamUser/ResolveVanityURL/v1/?key=\(key)&vanityurl=\(vanity.urlQueryEscaped)")
            guard let sid = (r["response"] as? [String: Any])?["steamid"] as? String else { throw SyncError(String(localized: "Profil Steam « \(vanity) » introuvable")) }
            id = sid
            c["steamId"] = sid
        }
        let r = try await HTTP.json("https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?key=\(key)&steamid=\(id)&include_appinfo=1&include_played_free_games=1&format=json")
        guard let list = (r["response"] as? [String: Any])?["games"] as? [[String: Any]] else {
            throw SyncError(String(localized: "Aucun jeu renvoyé — « Détails des jeux » est-il public sur ton profil ?"))
        }
        return list.compactMap { e in
            guard let appid = string(e["appid"]) else { return nil }
            var g = Game(id: "steam_\(appid)", platform: .steam, externalId: appid, title: e["name"] as? String ?? "")
            g.playtimeMinutes = (e["playtime_forever"] as? Int).flatMap { $0 > 0 ? $0 : nil }
            if let t = e["rtime_last_played"] as? Int, t > 0 { g.lastPlayed = Date(timeIntervalSince1970: TimeInterval(t)) }
            return g
        }
    }

    static func steamLocalUser() -> String? {
        let f = SteamScanner.root.appendingPathComponent("config/loginusers.vdf")
        guard let users = VDF.parse(file: f)?["users"]?.dict else { return nil }
        return users.first { $0.value["MostRecent"]?.string == "1" }?.key ?? users.keys.first
    }

    // MARK: GOG — OAuth (same client as GOG Galaxy)

    static let gogClientId = "46899977096215655"
    static let gogSecret = "9d85c43b1482497dbbce61f6e4aa173a433796eeae2ca8c5f6129f2dc4de46d9"
    static let gogRedirect = "https://embed.gog.com/on_login_success?origin=client"

    static let gog = Integration(
        platform: .gog,
        summary: String(localized: "Importe tous les jeux de ton compte GOG, avec la compatibilité Mac."),
        steps: [String(localized: "Clique sur « Se connecter à GOG » et identifie-toi."),
                String(localized: "Tu arrives sur une page blanche : copie son adresse complète (elle contient « code= »)."),
                String(localized: "Colle-la ci-dessous puis synchronise. La connexion est ensuite renouvelée automatiquement.")],
        links: [(String(localized: "Se connecter à GOG"), "https://auth.gog.com/auth?client_id=\(gogClientId)&redirect_uri=\(gogRedirect.urlQueryEscaped)&response_type=code&layout=client2")],
        fields: [IntegrationField(key: "code", label: String(localized: "Adresse ou code"), placeholder: "https://embed.gog.com/on_login_success?…code=…")],
        connectedKeys: ["refresh", "code"]
    ) { c in
        let base = "https://auth.gog.com/token?client_id=\(gogClientId)&client_secret=\(gogSecret)"
        let tok: [String: Any]
        if let code = c["code"] {
            tok = try await HTTP.json("\(base)&grant_type=authorization_code&code=\(extractCode(code).urlQueryEscaped)&redirect_uri=\(gogRedirect.urlQueryEscaped)")
            c["code"] = nil
        } else if let rt = c["refresh"] {
            tok = try await HTTP.json("\(base)&grant_type=refresh_token&refresh_token=\(rt.urlQueryEscaped)")
        } else { throw SyncError(String(localized: "Connecte-toi d'abord à GOG")) }
        guard let access = tok["access_token"] as? String else { throw SyncError(String(localized: "Connexion GOG refusée — recommence la connexion")) }
        c["refresh"] = tok["refresh_token"] as? String
        let galaxy = Launchers.installed(.gog)

        var games = [Game](), page = 1, pages = 1
        repeat {
            let r = try await HTTP.json("https://embed.gog.com/account/getFilteredProducts?mediaType=1&sortBy=title&page=\(page)",
                                        headers: ["Authorization": "Bearer \(access)"])
            pages = r["totalPages"] as? Int ?? 1
            for p in r["products"] as? [[String: Any]] ?? [] {
                guard let id = string(p["id"]), let title = p["title"] as? String else { continue }
                var g = Game(id: "gog_\(id)", platform: .gog, externalId: id, title: title)
                g.macNative = (p["worksOn"] as? [String: Any])?["Mac"] as? Bool
                g.storeURL = (p["url"] as? String).map { "https://www.gog.com\($0)" }
                if let img = p["image"] as? String { g.altCoverURL = "https:\(img)_196.jpg" }
                g.launchURL = galaxy ? "goggalaxy://openGameView/gog_\(id)" : g.storeURL
                games.append(g)
            }
            page += 1
        } while page <= pages
        return games
    }

    // MARK: Epic — OAuth (Legendary / Heroic client)

    static let epicBasic = "MzRhMDJjZjhmNDQxNGUyOWIxNTkyMTg3NmRhMzZmOWE6ZGFhZmJjY2M3Mzc3NDUwMzlkZmZlNTNkOTRmYzc2Y2Y="

    static let epic = Integration(
        platform: .epic,
        summary: String(localized: "Importe toute ta bibliothèque Epic Games (y compris les jeux gratuits récupérés)."),
        steps: [String(localized: "Clique sur « Se connecter à Epic » et identifie-toi."),
                String(localized: "La page affiche un texte JSON : copie la valeur « authorizationCode » (ou tout le texte)."),
                String(localized: "Colle-la ci-dessous puis synchronise. Le code n'est valable que quelques minutes.")],
        links: [(String(localized: "Se connecter à Epic"), "https://www.epicgames.com/id/login?redirectUrl=https%3A%2F%2Fwww.epicgames.com%2Fid%2Fapi%2Fredirect%3FclientId%3D34a02cf8f4414e29b15921876da36f9a%26responseType%3Dcode")],
        fields: [IntegrationField(key: "code", label: "authorizationCode", placeholder: String(localized: "32 caractères"))],
        connectedKeys: ["refresh", "code"]
    ) { c in
        let tokURL = "https://account-public-service-prod03.ol.epicgames.com/account/api/oauth/token"
        let auth = ["Authorization": "basic \(epicBasic)"]
        let tok: [String: Any]
        if let code = c["code"] {
            tok = try await HTTP.json(tokURL, method: "POST", headers: auth,
                                      form: ["grant_type": "authorization_code", "code": extractCode(code), "token_type": "eg1"])
            c["code"] = nil
        } else if let rt = c["refresh"] {
            tok = try await HTTP.json(tokURL, method: "POST", headers: auth,
                                      form: ["grant_type": "refresh_token", "refresh_token": rt, "token_type": "eg1"])
        } else { throw SyncError(String(localized: "Connecte-toi d'abord à Epic")) }
        guard let access = tok["access_token"] as? String else { throw SyncError(String(localized: "Connexion Epic refusée — recommence la connexion")) }
        c["refresh"] = tok["refresh_token"] as? String
        let bearer = ["Authorization": "bearer \(access)"]

        struct Rec { let ns, cid, app: String }
        var recs = [Rec](), cursor: String?
        repeat {
            var url = "https://library-service.live.use1a.on.epicgames.com/library/api/public/items?includeMetadata=true"
            if let cursor { url += "&cursor=\(cursor.urlQueryEscaped)" }
            let r = try await HTTP.json(url, headers: bearer)
            for e in r["records"] as? [[String: Any]] ?? [] {
                guard let ns = e["namespace"] as? String, ns != "ue", let cid = e["catalogItemId"] as? String,
                      let app = e["appName"] as? String else { continue }
                recs.append(Rec(ns: ns, cid: cid, app: app))
            }
            cursor = (r["responseMetadata"] as? [String: Any])?["nextCursor"] as? String
        } while cursor != nil

        // Titles / covers / Mac support from the catalog (local cache first).
        let local = EpicScanner.catalog()
        return await withTaskGroup(of: Game?.self) { group in
            var it = recs.makeIterator()
            func next() {
                guard let rec = it.next() else { return }
                group.addTask {
                    var g = Game(id: "epic_\(rec.app)", platform: .epic, externalId: rec.app, title: "")
                    g.launchURL = "com.epicgames.launcher://apps/\(rec.ns)%3A\(rec.cid)%3A\(rec.app)?action=launch&silent=true"
                    if let e = local[rec.app] {
                        if !e.isGame { return nil }
                        g.title = e.title; g.coverURL = e.cover; g.macNative = e.mac
                        return g
                    }
                    let u = "https://catalog-public-service-prod06.ol.epicgames.com/catalog/api/shared/namespace/\(rec.ns)/bulk/items?id=\(rec.cid)&includeDLCDetails=true&includeMainGameDetails=true&country=FR&locale=fr"
                    guard let r = try? await HTTP.json(u, headers: bearer), let item = r[rec.cid] as? [String: Any] else { return g }
                    let cats = (item["categories"] as? [[String: Any]])?.compactMap { $0["path"] as? String } ?? []
                    if item["mainGameItem"] != nil || (!cats.isEmpty && !cats.contains("games")) { return nil }
                    g.title = item["title"] as? String ?? ""
                    let imgs = item["keyImages"] as? [[String: Any]] ?? []
                    g.coverURL = (imgs.first { $0["type"] as? String == "DieselGameBoxTall" } ?? imgs.first)?["url"] as? String
                    g.macNative = (item["releaseInfo"] as? [[String: Any]])?.contains { ($0["platform"] as? [String])?.contains("Mac") == true }
                    return g
                }
            }
            for _ in 0..<8 { next() }
            var out = [Game]()
            for await g in group { if let g { out.append(g) }; next() }
            return out
        }
    }

    // MARK: Xbox — OpenXBL

    static let xbox = Integration(
        platform: .xbox,
        summary: String(localized: "Importe ton historique de jeux Xbox (console, PC, Game Pass) via le service gratuit OpenXBL."),
        steps: [String(localized: "Connecte-toi sur xbl.io avec ton compte Microsoft."),
                String(localized: "Dans ton profil OpenXBL, crée une clé API (« API Keys »)."),
                String(localized: "Colle-la ci-dessous. Les jeux se lancent ensuite via Xbox Cloud Gaming.")],
        links: [(String(localized: "Ouvrir OpenXBL"), "https://xbl.io")],
        fields: [IntegrationField(key: "apiKey", label: String(localized: "Clé API OpenXBL"))],
        connectedKeys: ["apiKey"]
    ) { c in
        guard let key = c["apiKey"] else { throw SyncError(String(localized: "Clé API requise")) }
        let r = try await HTTP.json("https://xbl.io/api/v2/player/titleHistory",
                                    headers: ["X-Authorization": key, "Accept": "application/json", "Accept-Language": Langue.bcp47])
        let titles = (r["titles"] ?? (r["content"] as? [String: Any])?["titles"]) as? [[String: Any]] ?? []
        return titles.compactMap { t in
            guard let id = string(t["titleId"]), let name = t["name"] as? String else { return nil }
            if let type = t["type"] as? String, type != "Game" { return nil }
            var g = Game(id: "xbox_\(id)", platform: .xbox, externalId: id, title: name)
            Links.fill(&g)
            g.altCoverURL = t["displayImage"] as? String
            g.lastPlayed = date((t["titleHistory"] as? [String: Any])?["lastTimePlayed"])
            return g
        }
    }

    // MARK: PlayStation — NPSSO token

    static let psn = Integration(
        platform: .psn,
        summary: String(localized: "Importe les jeux PS4 / PS5 auxquels tu as joué, avec le temps de jeu. Non jouables sur Mac (hors PS Remote Play)."),
        steps: [String(localized: "Connecte-toi sur playstation.com dans ton navigateur."),
                String(localized: "Ouvre ensuite le lien « Obtenir le jeton NPSSO » : copie la valeur « npsso » (64 caractères)."),
                String(localized: "Colle-la ci-dessous. Le jeton expire au bout d'environ 2 mois.")],
        links: [(String(localized: "1. Se connecter à PlayStation"), "https://www.playstation.com/"),
                (String(localized: "2. Obtenir le jeton NPSSO"), "https://ca.account.sony.com/api/v1/ssocookie")],
        fields: [IntegrationField(key: "npsso", label: String(localized: "Jeton NPSSO"))],
        connectedKeys: ["npsso"]
    ) { c in
        guard let raw = c["npsso"] else { throw SyncError(String(localized: "Jeton NPSSO requis")) }
        let access = try await psnAccessToken(raw)

        var games = [Game](), offset = 0
        while true {
            let r = try await HTTP.json("https://m.np.playstation.com/api/gamelist/v2/users/me/titles?categories=ps4_game,ps5_native_game&limit=200&offset=\(offset)",
                                        headers: ["Authorization": "Bearer \(access)"])
            let titles = r["titles"] as? [[String: Any]] ?? []
            for t in titles {
                guard let id = t["titleId"] as? String else { continue }
                var g = Game(id: "psn_\(id)", platform: .psn, externalId: id,
                             title: (t["localizedName"] as? String) ?? (t["name"] as? String) ?? "")
                Links.fill(&g)
                g.altCoverURL = (t["localizedImageUrl"] as? String) ?? (t["imageUrl"] as? String)
                g.playtimeMinutes = isoDurationMinutes(t["playDuration"] as? String)
                g.lastPlayed = date(t["lastPlayedDateTime"])
                games.append(g)
            }
            guard let next = r["nextOffset"] as? Int, next > offset, !titles.isEmpty else { break }
            offset = next
        }
        return games
    }


    /// NPSSO cookie → PSN access token (shared by the library sync and trophies).
    static func psnAccessToken(_ raw: String) async throws -> String {
        let npsso = extractCode(raw, jsonKey: "npsso")
        let authURL = "https://ca.account.sony.com/api/authz/v3/oauth/authorize?access_type=offline&client_id=09515159-7237-4370-9b40-3806e67c0891&redirect_uri=com.scee.psxandroid.scecompcall%3A%2F%2Fredirect&response_type=code&scope=psn%3Amobile.v2.core%20psn%3Aclientapp"
        let (_, resp) = try await HTTP.raw(authURL, headers: ["Cookie": "npsso=\(npsso)"], session: HTTP.noRedirect)
        guard let loc = resp.value(forHTTPHeaderField: "Location"),
              let code = URLComponents(string: loc)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw SyncError(String(localized: "Jeton NPSSO invalide ou expiré"))
        }
        let tok = try await HTTP.json("https://ca.account.sony.com/api/authz/v3/oauth/token", method: "POST",
                                      headers: ["Authorization": "Basic MDk1MTUxNTktNzIzNy00MzcwLTliNDAtMzgwNmU2N2MwODkxOnVjUGprYTV0bnRCMktxc1A="],
                                      form: ["code": code, "redirect_uri": "com.scee.psxandroid.scecompcall://redirect",
                                             "grant_type": "authorization_code", "token_format": "jwt"])
        guard let access = tok["access_token"] as? String else { throw SyncError(String(localized: "Authentification PlayStation refusée")) }

        return access
    }

    // MARK: itch.io — API key

    static let itch = Integration(
        platform: .itch,
        summary: String(localized: "Importe tous les jeux achetés ou réclamés sur itch.io."),
        steps: [String(localized: "Dans les paramètres itch.io, section « API keys », génère une nouvelle clé."), String(localized: "Colle-la ci-dessous.")],
        links: [(String(localized: "Clés API itch.io"), "https://itch.io/user/settings/api-keys")],
        fields: [IntegrationField(key: "apiKey", label: String(localized: "Clé API itch.io"))],
        connectedKeys: ["apiKey"]
    ) { c in
        guard let key = c["apiKey"] else { throw SyncError(String(localized: "Clé API requise")) }
        let app = Launchers.installed(.itch)
        var games = [Game](), page = 1
        while page < 100 {
            let r = try await HTTP.json("https://api.itch.io/profile/owned-keys?page=\(page)", headers: ["Authorization": "Bearer \(key)"])
            let keys = r["owned_keys"] as? [[String: Any]] ?? []
            if keys.isEmpty { break }
            for k in keys {
                guard let game = k["game"] as? [String: Any], let id = string(game["id"]), let title = game["title"] as? String else { continue }
                if let cls = game["classification"] as? String, cls != "game" { continue }
                var g = Game(id: "itch_\(id)", platform: .itch, externalId: id, title: title)
                g.coverURL = game["cover_url"] as? String
                g.storeURL = game["url"] as? String
                g.macNative = (game["p_osx"] as? Bool == true) || (game["type"] as? String == "html")
                g.launchURL = app ? "itch://games/\(id)" : g.storeURL
                games.append(g)
            }
            page += 1
        }
        return games
    }

    // MARK: Humble Bundle — session cookie

    static let humble = Integration(
        platform: .humble,
        summary: String(localized: "Importe les jeux sans DRM de tes achats Humble Bundle / Humble Choice."),
        steps: [String(localized: "Connecte-toi sur humblebundle.com."),
                String(localized: "Ouvre les outils de développement du navigateur → Stockage/Application → Cookies."),
                String(localized: "Copie la valeur du cookie « _simpleauth_sess » et colle-la ci-dessous.")],
        links: [(String(localized: "Ouvrir Humble Bundle"), "https://www.humblebundle.com/home/library")],
        fields: [IntegrationField(key: "cookie", label: "Cookie _simpleauth_sess")],
        connectedKeys: ["cookie"]
    ) { c in
        guard var cookie = c["cookie"] else { throw SyncError(String(localized: "Cookie requis")) }
        if cookie.hasPrefix("_simpleauth_sess=") { cookie = String(cookie.dropFirst("_simpleauth_sess=".count)) }
        let headers = ["Cookie": "_simpleauth_sess=\(cookie)", "Accept": "application/json"]
        let (d, r) = try await HTTP.raw("https://www.humblebundle.com/api/v1/user/order?ajax=true", headers: headers)
        guard r.statusCode == 200, let orders = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else {
            throw SyncError(String(localized: "Cookie invalide ou expiré"))
        }
        let keys = orders.compactMap { $0["gamekey"] as? String }
        var games = [String: Game]()
        for start in stride(from: 0, to: keys.count, by: 40) {
            let batch = keys[start..<min(start + 40, keys.count)].map { "gamekeys=\($0)" }.joined(separator: "&")
            let res = try await HTTP.json("https://www.humblebundle.com/api/v1/orders?all_tpkds=true&\(batch)", headers: headers)
            for (_, order) in res {
                for sp in (order as? [String: Any])?["subproducts"] as? [[String: Any]] ?? [] {
                    guard let mn = sp["machine_name"] as? String, let name = sp["human_name"] as? String else { continue }
                    let dls = (sp["downloads"] as? [[String: Any]] ?? []).compactMap { $0["platform"] as? String }
                    guard dls.contains(where: { ["mac", "windows", "linux"].contains($0) }) else { continue } // games only
                    var g = Game(id: "humble_\(mn)", platform: .humble, externalId: mn, title: name)
                    g.macNative = dls.contains("mac")
                    g.altCoverURL = sp["icon"] as? String
                    g.storeURL = "https://www.humblebundle.com/home/library"
                    g.launchURL = g.storeURL
                    games[g.id] = g
                }
            }
        }
        return Array(games.values)
    }
}

// MARK: - Nintendo — Nintendo Account (Switch play history)

extension Integrations {
    static let nintendoClient = "5c38e31cd085304b"

    /// PKCE verifier kept in the Keychain so the login link stays valid across launches.
    static var nintendoVerifier: String {
        let c = Creds(.nintendo)
        if let v = c["verifier"] { return v }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let v = base64url(Data(bytes))
        c["verifier"] = v
        return v
    }

    static func base64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static var nintendoLoginURL: String {
        let challenge = base64url(Data(SHA256.hash(data: Data(nintendoVerifier.utf8))))
        return "https://accounts.nintendo.com/connect/1.0.0/authorize?state=\(UUID().uuidString)&redirect_uri=npf\(nintendoClient)%3A%2F%2Fauth&client_id=\(nintendoClient)&scope=openid%20user%20user.mii%20user.email%20user.links%5B%5D.id&response_type=session_token_code&session_token_code_challenge=\(challenge)&session_token_code_challenge_method=S256&theme=login_form"
    }

    static let nintendo = Integration(
        platform: .nintendo,
        summary: String(localized: "Importe l'historique de jeu de ta Nintendo Switch (titres et temps de jeu) depuis ton compte Nintendo. Expérimental : API non officielle."),
        steps: [String(localized: "Clique sur « Se connecter à Nintendo » et identifie-toi."),
                String(localized: "Sur la page « Lier un compte », fais un clic droit sur le bouton rouge « Sélectionner ce compte » → « Copier le lien »."),
                String(localized: "Colle le lien (npf…://auth#session_token_code=…) ci-dessous puis synchronise. La connexion reste valable ensuite.")],
        links: [(String(localized: "Se connecter à Nintendo"), "ludotheque:nintendo-login")], // built on click (needs the PKCE verifier)
        fields: [IntegrationField(key: "code", label: String(localized: "Lien copié"), placeholder: "npf5c38e31cd085304b://auth#session_token_code=…")],
        connectedKeys: ["refresh", "code"]
    ) { c in
        let ua = ["User-Agent": "com.nintendo.znej/1.13.0 (Android/7.1.2)", "Accept": "application/json"]
        if let pasted = c["code"] {
            guard let re = try? NSRegularExpression(pattern: "session_token_code=([^&\\s]+)"),
                  let m = re.firstMatch(in: pasted, range: NSRange(pasted.startIndex..., in: pasted)),
                  let r = Range(m.range(at: 1), in: pasted) else { throw SyncError(String(localized: "Lien invalide : il doit contenir « session_token_code= »")) }
            let st = try await HTTP.json("https://accounts.nintendo.com/connect/1.0.0/api/session_token", method: "POST", headers: ua,
                                         form: ["client_id": nintendoClient, "session_token_code": String(pasted[r]),
                                                "session_token_code_verifier": nintendoVerifier])
            guard let session = st["session_token"] as? String else { throw SyncError(String(localized: "Connexion Nintendo refusée — recommence")) }
            c["refresh"] = session
            c["code"] = nil
        }
        guard let session = c["refresh"] else { throw SyncError(String(localized: "Connecte-toi d'abord à Nintendo")) }
        let tok = try await HTTP.json("https://accounts.nintendo.com/connect/1.0.0/api/token", method: "POST", headers: ua,
                                      jsonBody: ["client_id": nintendoClient, "session_token": session,
                                                 "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer-session-token"])
        guard let access = tok["access_token"] as? String else { throw SyncError(String(localized: "Session Nintendo expirée — reconnecte-toi")) }
        var h = ua
        h["Authorization"] = "Bearer \(access)"
        let r = try await HTTP.json("https://mypage-api.entry.nintendo.co.jp/api/v1/users/me/play_histories", headers: h)
        return (r["playHistories"] as? [[String: Any]] ?? []).compactMap { t in
            guard let id = t["titleId"] as? String, let name = t["titleName"] as? String else { return nil }
            var g = Game(id: "nintendo_\(id)", platform: .nintendo, externalId: id, title: name)
            g.macNative = false
            g.altCoverURL = t["imageUrl"] as? String
            g.playtimeMinutes = (t["totalPlayedMinutes"] as? Int).flatMap { $0 > 0 ? $0 : nil }
            g.lastPlayed = date(t["lastPlayedAt"])
            g.storeURL = "https://www.nintendo.com/fr-fr/Rechercher/Rechercher-299117.html?q=\(name.urlQueryEscaped)"
            return g
        }
    }
}
