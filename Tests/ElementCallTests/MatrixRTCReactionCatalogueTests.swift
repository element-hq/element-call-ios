//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementCallKit
import Foundation
import Testing

/// What a reaction shows and plays is Element Call web's answer, not the core's hint where the two
/// differ (037 R9).
nonisolated struct MatrixRTCReactionCatalogueTests {
    @Test
    func aKnownNameWithASoundPlaysIt() {
        let resolved = MatrixRTCReactionCatalogue.resolve(name: "drum", emoji: "🥁")
        #expect(resolved.sound == "baduntss")
        #expect(resolved.emoji == "🥁")
    }
    
    /// The core calls these silent; web plays its generic sound for them.
    @Test(arguments: ["thumbsup", "thumbsdown", "dizzy", "ok", "heart", "laugh"])
    func aKnownNameWithoutASoundPlaysTheGenericOne(name: String) {
        #expect(MatrixRTCReactionCatalogue.resolve(name: name, emoji: "x").sound == "generic")
    }
    
    /// The core's catalogue has no bell; web's does, with a sound of its own.
    @Test
    func theBellRings() {
        let resolved = MatrixRTCReactionCatalogue.resolve(name: "bell", emoji: "🔔")
        #expect(resolved.sound == "bell")
        #expect(resolved.emoji == "🛎️")
    }
    
    @Test
    func aKnownNameShowsTheCataloguesEmojiWhateverWasSent() {
        #expect(MatrixRTCReactionCatalogue.resolve(name: "clapping", emoji: "🦆").emoji == "👏")
    }
    
    @Test
    func anUnknownNameShowsWhatWasSentAndPlaysTheGenericSound() {
        let resolved = MatrixRTCReactionCatalogue.resolve(name: "duck", emoji: "🦆")
        #expect(resolved.emoji == "🦆")
        #expect(resolved.sound == "generic")
    }
    
    /// Every sound the catalogue can name has a file, or it would silently play the generic one.
    @Test
    func everyCatalogueSoundIsBundled() {
        let named = ["party", "clapping", "dog", "cat", "lightbulb", "crickets", "deer", "rock", "wave", "drum", "bell"]
            .map { MatrixRTCReactionCatalogue.resolve(name: $0, emoji: "").sound }
        #expect(Set(named).isSubset(of: Set(MatrixRTCReactionCatalogue.sounds)))
        #expect(!named.contains("generic"))
    }
}
