//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import MatrixRtc

/// What a received reaction looks and sounds like: Element Call web's answer, so a mixed call shows
/// and plays the same thing on every client (037 R9).
///
/// The core's catalogue is the source, corrected where it disagrees with web. Each correction is
/// asked of the core (feature-hq `plans/037…/core-rs-feedback.md`, 2026-11-02) and goes when the
/// core gives the same answer.
nonisolated enum MatrixRTCReactionCatalogue {
    /// Web's sound for a reaction whose name it does not know, and for a known one with no sound.
    static let genericSound = "generic"
    
    /// Every sound a reaction can name, which is every file under `Sounds/reactions`.
    static let sounds = [genericSound, "party", "clap", "dog", "cat", "lightbulb", "crickets", "deer", "rock", "wave", "baduntss", "bell"]
    
    /// A known name shows the catalogue's emoji, whatever was sent with it; an unknown one shows what
    /// was sent, already cut to its first character by the core.
    static func resolve(name: String, emoji: String) -> (emoji: String, sound: String) {
        guard let kind = catalogue[name] else {
            return (emoji, genericSound)
        }
        // The core calls a known name without a sound silent, where web falls back to its generic
        // sound: a 👍 from web is heard there.
        return (kind.emoji, kind.sound ?? genericSound)
    }
    
    private static let catalogue: [String: (emoji: String, sound: String?)] = {
        var catalogue = Dictionary(reactionCatalog().map { ($0.name, (emoji: $0.emoji, sound: $0.sound)) },
                                   uniquingKeysWith: { first, _ in first })
        // Web has a bell; the core's catalogue stops before it.
        if catalogue["bell"] == nil {
            catalogue["bell"] = ("🛎️", "bell")
        }
        return catalogue
    }()
}
