//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallKit
@testable import ElementCallUI
import Testing

/// The small-call layout's rules (spec 019), as arithmetic with no view.
@MainActor
struct ElementCallSmallCallLayoutTests {
    private typealias Fixtures = ElementCallPreviewFixtures
    private typealias Layout = ElementCallSmallCallLayout
    
    private let me = Fixtures.tile("Me", isLocal: true)
    
    private func arrival(_ tiles: [ElementCallTile]) -> ElementCallArrivalOrder {
        var order = ElementCallArrivalOrder()
        order.observe(tiles)
        return order
    }
    
    // MARK: - Speaker (R9, R15)
    
    /// Two people starting together: the first to have arrived, whatever the ranking says.
    @Test
    func theFirstSpeakerByArrivalIsChosen() {
        let bob = Fixtures.tile("Bob", isSpeaking: true)
        let carol = Fixtures.tile("Carol", isSpeaking: true)
        let order = arrival([me, bob, carol])
        #expect(Layout.speaker(tiles: [me, carol, bob], arrivalOrder: order, held: nil) == bob.id)
    }
    
    /// Talking over each other does not swap the tile on top on every word.
    @Test
    func theHeldSpeakerKeepsTheSlotWhileStillSpeaking() {
        let bob = Fixtures.tile("Bob", isSpeaking: true)
        let carol = Fixtures.tile("Carol", isSpeaking: true)
        let tiles = [me, bob, carol]
        #expect(Layout.speaker(tiles: tiles, arrivalOrder: arrival(tiles), held: carol.id) == carol.id)
    }
    
    /// R9: when nobody is speaking the last speaker stays, until they leave.
    @Test
    func theLastSpeakerIsHeldThroughSilenceUntilTheyLeave() {
        let bob = Fixtures.tile("Bob")
        let carol = Fixtures.tile("Carol")
        let tiles = [me, bob, carol]
        #expect(Layout.speaker(tiles: tiles, arrivalOrder: arrival(tiles), held: carol.id) == carol.id)
        let gone = [me, bob]
        #expect(Layout.speaker(tiles: gone, arrivalOrder: arrival(gone), held: carol.id) == nil)
    }
    
    /// R15: we never count as the speaker, however loud.
    @Test
    func weAreNeverTheSpeaker() {
        let loudMe = Fixtures.tile("Me", isLocal: true, isSpeaking: true)
        let tiles = [loudMe, Fixtures.tile("Bob")]
        #expect(Layout.speaker(tiles: tiles, arrivalOrder: arrival(tiles), held: nil) == nil)
    }
    
    // MARK: - Picture in Picture (R15)
    
    @Test
    func pictureInPictureFollowsTheSpeakerThenTheFirstArrivalThenUs() {
        let bob = Fixtures.tile("Bob")
        let carol = Fixtures.tile("Carol")
        let tiles = [me, carol, bob]
        let order = arrival([me, bob, carol])
        #expect(Layout.pictureInPictureTile(tiles: tiles, arrivalOrder: order, speakerID: carol.id) == carol.id)
        #expect(Layout.pictureInPictureTile(tiles: tiles, arrivalOrder: order, speakerID: nil) == bob.id)
        #expect(Layout.pictureInPictureTile(tiles: [me], arrivalOrder: arrival([me]), speakerID: nil) == me.id)
    }
}
