//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCall
import ElementCallKit
import Foundation

/// Shared fixtures for previews, so every snapshot is built from the same people and the diffs
/// between them mean something.
///
/// Public because the example harness is built from them too, the way the port fakes are: a UI test
/// and a snapshot then describe the same Alice, Bob and Carol, and `ElementCallTile`'s memberwise
/// initialiser is internal, so there is no other way to make one from outside.
public enum ElementCallPreviewFixtures {
    public static func tile(_ name: String,
                            isLocal: Bool = false,
                            isMuted: Bool = false,
                            hasMicrophone: Bool = true,
                            hasVideo: Bool = false,
                            isScreenSharing: Bool = false,
                            isSpeaking: Bool = false,
                            hasHandRaised: Bool = false,
                            stats: String? = nil) -> ElementCallTile {
        let user = "@\(name.lowercased()):example.com"
        return ElementCallTile(memberID: "\(user):DEVICE",
                               userID: user,
                               displayName: isLocal ? "You" : name,
                               avatarURL: nil,
                               isLocal: isLocal,
                               isMicrophoneMuted: isMuted,
                               hasMicrophone: hasMicrophone,
                               hasVideo: hasVideo,
                               isScreenSharing: isScreenSharing,
                               isSpeaking: isSpeaking,
                               hasHandRaised: hasHandRaised,
                               isFrontCamera: isLocal,
                               audioLevel: isSpeaking ? 0.6 : 0,
                               stats: stats)
    }
    
    public static let alice = tile("Alice", isLocal: true)
    public static let bob = tile("Bob", isMuted: true)
    public static let carol = tile("Carol", isSpeaking: true)
    
    public static let group = [alice, bob, carol, tile("Dan"), tile("Erin"), tile("Frank"), tile("Grace"), tile("Heidi")]
    
    /// No call object exists in a preview, so `hasVideo` here only changes the badges, not the
    /// picture: a tile with nothing to draw falls back to its avatar.
    public static func connected(tiles: [ElementCallTile],
                                 spotlight: String? = nil,
                                 isDirect: Bool = false,
                                 isMicrophoneMuted: Bool = false,
                                 isScreenSharing: Bool = false,
                                 isTileStatsVisible: Bool = false) -> ElementCallScreenViewState {
        var state = ElementCallScreenViewState(roomName: "Product | Lobby")
        state.isDirect = isDirect
        state.connection = .connected
        // Deliberately nil: the status line renders this as a live counting timer, so even a
        // fixed date produces a different image on every run. The duration is not what these
        // snapshots are for.
        state.connectedAt = nil
        state.memberCount = tiles.count
        state.tiles = tiles
        state.spotlightMemberID = spotlight
        state.isMicrophoneMuted = isMicrophoneMuted
        state.isScreenSharing = isScreenSharing
        state.isTileStatsVisible = isTileStatsVisible
        state.areTileStatsAvailable = true
        return state
    }
    
    public static func noCall() -> MatrixRTCCall? {
        nil
    }
}
