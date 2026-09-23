//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallHost
import ElementCallKit
@testable import ElementCallUI
import Foundation
import Testing

/// What the screen makes of the model's ranking: which tiles exist, in what order, and what the two
/// questions derived from that list answer.
///
/// None of this had a test before, because the only path to it went through `refresh()`, which needs
/// a live call. The composition is a pure function now for exactly this reason: it is where an
/// index-versus-identity mistake would produce the wrong person's mute state rather than a crash.
@MainActor
struct ElementCallTileCompositionTests {
    private let me = MatrixRTCTileID(memberID: "@alice:example.com:ME")
    
    private func tile(_ name: String, kind: MatrixRTCTileKind = .person, isLocal: Bool = false, isHero: Bool = false, isSpeaking: Bool = false) -> MatrixRTCTile {
        MatrixRTCTile(id: MatrixRTCTileID(memberID: isLocal ? me.memberID : "@\(name):example.com:DEVICE", kind: kind),
                      userID: "@\(name):example.com",
                      isLocal: isLocal,
                      isHero: isHero,
                      hasVideo: kind == .screenShare,
                      isSpeaking: isSpeaking)
    }
    
    private func compose(ranked: [MatrixRTCTile], own: MatrixRTCTile?) -> [ElementCallTile] {
        ElementCallScreenViewModel.tiles(ranked: ranked,
                                         own: own,
                                         profiles: [:],
                                         youLabel: "You",
                                         isLocalMicrophoneMuted: false,
                                         localHasVideo: false)
    }
    
    // MARK: - Composition
    
    /// The model never ranks us, so where we go is the app's decision rather than an accident of
    /// whatever the transport happened to return. First, which is where the roster always put us.
    @Test
    func theOwnTileIsFirstAndTheModelsOrderIsKeptAfterIt() {
        let ranked = [tile("carol"), tile("bob"), tile("dan")]
        let composed = compose(ranked: ranked, own: tile("alice", isLocal: true))
        #expect(composed.first?.isLocal == true)
        #expect(composed.dropFirst().map(\.id) == ranked.map(\.id))
    }
    
    /// A member publishing both is two tiles sharing one member ID — which is the case every
    /// member-keyed assumption in the app used to get wrong.
    @Test
    func aSharerBecomesTwoTilesSharingOneMemberID() {
        let composed = compose(ranked: [tile("frank", kind: .screenShare, isHero: true), tile("frank")],
                               own: tile("alice", isLocal: true))
        let franks = composed.filter { $0.memberID == "@frank:example.com:DEVICE" }
        #expect(franks.count == 2)
        #expect(Set(franks.map(\.id)).count == 2)
        #expect(franks.filter(\.isScreenShare).count == 1)
    }
    
    /// Our own tile cannot be ranked, so nothing can mark it a hero. Asserted rather than assumed
    /// because it arrives on a different surface from the list and carries the same fields.
    @Test
    func weAreNeverHeroEvenIfSomethingUpstreamSaysSo() {
        let composed = compose(ranked: [], own: tile("alice", isLocal: true, isHero: true))
        #expect(composed.first?.isHero == false)
    }
    
    /// The model publishes our mute and camera too, but ours are overridden locally: a mute tap has
    /// to reach the badge before the transport round-trips.
    @Test
    func ourOwnMuteAndCameraComeFromTheCallRatherThanTheModel() {
        let own = MatrixRTCTile(id: me, userID: "@alice:example.com", isLocal: true, hasVideo: false, isMicrophoneMuted: false)
        let composed = ElementCallScreenViewModel.tiles(ranked: [],
                                                        own: own,
                                                        profiles: [:],
                                                        youLabel: "You",
                                                        isLocalMicrophoneMuted: true,
                                                        localHasVideo: true)
        #expect(composed.first?.isMicrophoneMuted == true)
        #expect(composed.first?.hasVideo == true)
    }
    
    // MARK: - The spotlight
    
    @Test
    func theHeroTakesTheSpotlightAndWeNeverDo() {
        var state = ElementCallScreenViewState(roomName: "Room")
        state.tiles = compose(ranked: [tile("carol", isSpeaking: true), tile("frank", kind: .screenShare, isHero: true)],
                              own: tile("alice", isLocal: true))
        #expect(state.spotlightID?.kind == .screenShare)
        
        state.tiles = compose(ranked: [tile("carol", isSpeaking: true), tile("bob")],
                              own: tile("alice", isLocal: true))
        #expect(state.spotlightID == MatrixRTCTileID(memberID: "@carol:example.com:DEVICE"))
    }
    
    /// Alone, there is nobody to spotlight — and the stage gives our tile the large slot anyway.
    @Test
    func thereIsNoSpotlightWhenWeAreTheOnlyPersonInTheCall() {
        var state = ElementCallScreenViewState(roomName: "Room")
        state.tiles = compose(ranked: [], own: tile("alice", isLocal: true))
        #expect(state.spotlightID == nil)
        #expect(state.tiles.count == 1)
    }
    
    // MARK: - One to one
    
    @Test
    func aDirectCallIsOneToOneUntilSomethingElseIsOnTheStage() {
        var state = ElementCallScreenViewState(roomName: "Room")
        state.isDirect = true
        
        state.tiles = compose(ranked: [], own: tile("alice", isLocal: true))
        #expect(state.layout == .oneToOne, "alone while they are still ringing")
        
        state.tiles = compose(ranked: [tile("bob")], own: tile("alice", isLocal: true))
        #expect(state.layout == .oneToOne)
        
        // Their share is a tile of its own, so a direct call in which they share is three tiles and
        // has nowhere to put our thumbnail.
        state.tiles = compose(ranked: [tile("bob", kind: .screenShare, isHero: true), tile("bob")],
                              own: tile("alice", isLocal: true))
        #expect(state.layout == .group)
        
        state.isDirect = false
        state.tiles = compose(ranked: [tile("bob")], own: tile("alice", isLocal: true))
        #expect(state.layout == .group)
    }
    
    /// A tile outside the detail window has no record, only a reference — and the reference has to
    /// be enough to draw an avatar with a name, which both resolve through the user ID. Without it
    /// an out-of-window tile is not a degraded tile but an empty one.
    @Test
    func aReferenceOutsideTheWindowStillNamesItsUser() {
        let bob = tile("bob")
        let windowed = MatrixRTCTileRoster(order: MatrixRTCTileRoster([bob, tile("carol")]).order,
                                           detail: [bob.id: bob])
        #expect(windowed.detail.count == 1)
        let outside = windowed.order.last
        #expect(outside?.id == tile("carol").id)
        #expect(outside?.userID == "@carol:example.com")
    }
    
    /// Our own share still makes no tile at all, so it cannot turn a direct call into a group one —
    /// which is what the one-to-one rule has always claimed and now depends on the model for.
    @Test
    func ourOwnShareDoesNotTurnADirectCallIntoAGroupOne() {
        var state = ElementCallScreenViewState(roomName: "Room")
        state.isDirect = true
        state.isScreenSharing = true
        state.tiles = compose(ranked: [tile("bob")], own: tile("alice", isLocal: true))
        #expect(state.layout == .oneToOne)
    }
}
