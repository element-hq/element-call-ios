//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallKit

/// The layout for calls of up to five people (spec 019), as pure arithmetic beside the grid's.
///
/// Static and caseless, as `ElementCallSpotlight` is, so every rule is a unit test with no view.
enum ElementCallSmallCallLayout {
    /// Who counts as speaking for the small layout: the tile on top of the overlap (R6, R9) and the
    /// one Picture in Picture continues (R15). One choice for both, so the window never shows
    /// someone other than the tile the stage is raising.
    ///
    /// - Parameters:
    ///   - tiles: the composed tiles, ourselves included; we are never the speaker (R15).
    ///   - arrivalOrder: breaks a tie between two people starting to speak at once.
    ///   - held: the previous answer. Kept while it is still speaking, so two people talking over
    ///     each other do not swap on every word, and kept through silence, so the last speaker
    ///     stays rather than the slot emptying (R9). Dropped once they leave.
    static func speaker(tiles: [ElementCallTile],
                        arrivalOrder: ElementCallArrivalOrder,
                        held: MatrixRTCTileID?) -> MatrixRTCTileID? {
        let remote = tiles.filter { !$0.isLocal && !$0.isScreenShare }
        let speaking = Set(remote.filter(\.isSpeaking).map(\.id))
        if let held, speaking.contains(held) {
            return held
        }
        if let first = arrivalOrder.ids.first(where: speaking.contains) {
            return first
        }
        if let held, remote.contains(where: { $0.id == held }) {
            return held
        }
        return nil
    }
    
    /// The tile the Picture in Picture window continues while the small layout is up (R15): the
    /// speaker, else whoever arrived first, else ourselves when we are alone.
    static func pictureInPictureTile(tiles: [ElementCallTile],
                                     arrivalOrder: ElementCallArrivalOrder,
                                     speakerID: MatrixRTCTileID?) -> MatrixRTCTileID? {
        speakerID ?? arrivalOrder.ids.first ?? tiles.first(where: \.isLocal)?.id
    }
}
