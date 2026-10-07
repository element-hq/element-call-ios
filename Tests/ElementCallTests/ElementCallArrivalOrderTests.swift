//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallKit
@testable import ElementCallUI
import Testing

/// The order the small-call layout places people in (spec 019 R7, R32): first sight, never rank.
@MainActor
struct ElementCallArrivalOrderTests {
    private typealias Fixtures = ElementCallPreviewFixtures
    
    private let me = Fixtures.tile("Me", isLocal: true)
    private let bob = Fixtures.tile("Bob")
    private let carol = Fixtures.tile("Carol")
    private let dan = Fixtures.tile("Dan")
    
    private func order(_ rosters: [ElementCallTile]...) -> [MatrixRTCTileID] {
        var order = ElementCallArrivalOrder()
        for roster in rosters {
            order.observe(roster)
        }
        return order.ids
    }
    
    /// The people already there when we join arrive in one roster, seeded in its order.
    @Test
    func theFirstRosterSeedsInTheOrderGiven() {
        #expect(order([me, carol, bob]) == [carol.id, bob.id])
    }
    
    @Test
    func ourselvesAndScreenSharesAreNotPlaced() {
        #expect(order([me, Fixtures.share("Bob"), bob]) == [bob.id])
    }
    
    /// R7, R13: a new ranking moves nothing; only a newcomer changes the order, and goes last.
    @Test
    func aNewRankingMovesNobodyAndANewcomerGoesLast() {
        #expect(order([me, bob, carol], [me, carol, bob]) == [bob.id, carol.id])
        #expect(order([me, bob, carol], [me, dan, carol, bob]) == [bob.id, carol.id, dan.id])
    }
    
    /// R7: a departure moves everyone after it up one place.
    @Test
    func aDepartureMovesLaterArrivalsUp() {
        #expect(order([me, bob, carol, dan], [me, bob, dan]) == [bob.id, dan.id])
    }
    
    /// A member who leaves and comes back has gone, so they arrive again at the end.
    @Test
    func aRejoinIsANewArrival() {
        #expect(order([me, bob, carol], [me, carol], [me, bob, carol]) == [carol.id, bob.id])
    }
}
