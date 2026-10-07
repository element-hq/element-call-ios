//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallKit

/// The remote people of the call in the order this device first saw them: what the small-call
/// layout places its tiles by (019 R7).
///
/// **Not the ranking.** The ranking includes speaking, so laying it out would swap two tiles every
/// time someone new talked, which is exactly what R7 and R13 forbid. Re-sorting `tiles` instead is
/// ruled out too: the grid reads that order. This is a second order beside it that only the
/// small-call layout reads.
///
/// **First sight, not join time.** R7 asks for the join time so that every device agrees, and the
/// core does not expose one (019 core feedback, 2026-10-07). People already in the call when we join
/// arrive together in our first roster, and are seeded in its rank order, which is the closest thing
/// to join time we are given. So two devices that joined at different times can order those people
/// differently; everything after that is in true arrival order on both.
///
/// Kept by the view model for the whole call, the grid included, because the stage unmounts while
/// minimized and entering the small layout from the grid has to find the order already there (R32).
nonisolated struct ElementCallArrivalOrder: Equatable, Sendable {
    private(set) var ids: [MatrixRTCTileID] = []
    
    /// Takes the current tiles, in the order the view model composes them. Remote person tiles only:
    /// ourselves are placed apart, and a screen share sends the call to the grid rather than being
    /// placed (R8). Departed tiles are dropped so everyone after them moves up one; a member who
    /// rejoins comes back with a fresh member ID, so a rejoin is a new arrival and goes last.
    mutating func observe(_ tiles: [ElementCallTile]) {
        let present = tiles.filter { !$0.isLocal && !$0.isScreenShare }.map(\.id)
        let presentSet = Set(present)
        ids.removeAll { !presentSet.contains($0) }
        let known = Set(ids)
        ids.append(contentsOf: present.filter { !known.contains($0) })
    }
}
