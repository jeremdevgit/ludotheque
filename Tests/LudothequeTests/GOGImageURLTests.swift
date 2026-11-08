// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation

@main
struct GOGImageURLTests {
    static func main() {
        testAcceptsKnownGOGImageHosts()
        testRejectsUnsafeOrUntrustedImageURLs()
        testRejectsAuthorityInjectionAndUnapprovedRedirectHosts()
        print("3 security URL checks passed")
    }

    private static func testAcceptsKnownGOGImageHosts() {
        for host in ["images.gog.com", "images-1.gog.com", "images-4.gog.com", "images-2.gog-statics.com"] {
            precondition(GOGImageURL.make("https://\(host)/cover{formatter}.{ext}?namespace=gamesdb",
                                          formatter: "_cover", fileExtension: "webp") != nil, host)
        }
    }

    private static func testRejectsUnsafeOrUntrustedImageURLs() {
        for value in ["http://images.gog.com/a.jpg", "file:///tmp/a.jpg", "gopher://images.gog.com/a",
                      "https://127.0.0.1/a.jpg", "https://localhost/a.jpg",
                      "https://images.gog.com.attacker.example/a.jpg",
                      "https://user:pass@images.gog.com/a.jpg", "https://attacker.example/a.jpg"] {
            precondition(GOGImageURL.make(value, formatter: "_cover", fileExtension: "jpg") == nil, value)
        }
    }

    private static func testRejectsAuthorityInjectionAndUnapprovedRedirectHosts() {
        precondition(GOGImageURL.make("https://attacker.example/{formatter}.{ext}", formatter: "@images.gog.com", fileExtension: "jpg") == nil)
        precondition(!GOGImageURL.isAllowed(URL(string: "https://127.0.0.1/a.jpg")!))
        precondition(!GOGImageURL.isAllowed(URL(string: "https://images.gog.com.attacker.example/a.jpg")!))
        precondition(GOGImageURL.isAllowed(URL(string: "https://images-3.gog.com/a.jpg")!))
    }
}
