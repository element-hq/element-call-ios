//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallHost
import ElementCallKit
import Foundation

/// One tile of the call: a member's camera or a member's screen, as the model ranked it.
public nonisolated struct ElementCallTile: Identifiable, Equatable, Sendable {
    /// The member *and* the stream. A member publishing a camera and a screen share is two tiles,
    /// drawn at once, so the member alone names a person rather than a tile — and this is the
    /// `ForEach` identity, so two tiles sharing one would collapse into a single view.
    public let id: MatrixRTCTileID
    public let userID: String
    public let displayName: String
    public let avatarURL: URL?
    public let isLocal: Bool
    /// Cannot be heard: muted, or no microphone stream reached us at all. The badge collapses the
    /// two on purpose; the stats overlay keeps them apart, where the question is why.
    public let isMicrophoneMuted: Bool
    /// This tile's own stream is present and unmuted. On a share tile it is the share.
    public let hasVideo: Bool
    /// Loud enough to count as talking. A threshold crossing, not a level: nothing continuous
    /// belongs in a tile, which the whole screen is rebuilt to redraw.
    public let isSpeaking: Bool
    public let hasHandRaised: Bool
    /// The model marks the tile worth the largest slot — a screen share today, a pin later. It does
    /// not choose a spotlight; `ElementCallSpotlight` is where that is decided.
    public let isHero: Bool
    public let stats: String?
    
    public var memberID: String {
        id.memberID
    }
    
    public var kind: MatrixRTCTileKind {
        id.kind
    }
    
    public var isScreenShare: Bool {
        id.kind == .screenShare
    }
}

/// A message the screen shows once and then forgets. Replaces the host's alert type so the package
/// does not depend on it.
public nonisolated struct ElementCallAlert: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let title: String
    public let message: String
    
    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

/// `Equatable` so ``ElementCallScreenViewModel`` can decline to republish an unchanged projection.
/// Never hand-write `==` here: synthesis picks up a new member for free, and a hand-written one
/// silently stops covering the member somebody adds next -- which is the same failure as the bug
/// the conformance exists to fix.
public nonisolated struct ElementCallScreenViewState: Equatable, Sendable {
    public var roomName: String
    /// Whether the room is a direct chat. False until the room has been read.
    public var isDirect = false
    public var connection: ElementCallConnection = .idle
    public var connectedAt: Date?
    public var memberCount = 0
    /// Ourselves first, then the model's ranking untouched. See ``ElementCallScreenViewModel``.
    public var tiles: [ElementCallTile] = []
    public var isMicrophoneMuted = false
    public var isCameraEnabled = false
    public var isFrontCamera = true
    public var isScreenSharing = false
    public var isLoudspeaker = false
    public var isMediaDegraded = false
    public var isTileStatsVisible = false
    public var isDeveloperModeEnabled = false
    public var isScreenSharingEnabled = false
    /// False while minimized, in the bar or the system window: the tiles unmount so only the window decodes.
    public var isMaximized = true
    
    /// Which tile gets the largest slot, or nil when every tile is the same size.
    ///
    /// Stored rather than computed, because the answer has memory: which hero the user swiped to,
    /// and who spoke last while nobody is speaking. `ElementCallSpotlight` decides it in `refresh()`
    /// and this is the one copy the stage, the Picture in Picture window and the tests all read.
    /// Never ourselves, and never the head of the ranking just for being the head of it.
    public var spotlightID: MatrixRTCTileID?
    /// The remote people in the order they arrived, which the small-call layout places them by
    /// instead of the ranking (019 R7). Kept in the grid too, so entering the small layout finds it.
    var arrivalOrder = ElementCallArrivalOrder()
    /// Who the small-call layout raises and Picture in Picture follows (019 R9, R15). Stored for the
    /// reason `spotlightID` is: it holds the last speaker through silence.
    public var smallCallSpeakerID: MatrixRTCTileID?
    /// Whether the device has a camera on each side, so the flip button means something (019 R24).
    public var canSwitchCamera = false
    
    /// The tile the Picture in Picture window continues, and whether it must be that one. In a
    /// small call it is the speaker, else the first to arrive, else ourselves, and exactly that
    /// tile (019 R15); otherwise the spotlight, with the window's own fallbacks (003 R68).
    public var pictureInPictureTile: (id: MatrixRTCTileID?, isExact: Bool) {
        guard ElementCallSmallCallLayout.applies(to: tiles) else { return (spotlightID, false) }
        return (ElementCallSmallCallLayout.pictureInPictureTile(tiles: tiles, arrivalOrder: arrivalOrder, speakerID: smallCallSpeakerID), true)
    }
    
    public var isVideoCall: Bool {
        isCameraEnabled || tiles.contains { $0.hasVideo || $0.isScreenShare }
    }
}

extension ElementCallTile {
    /// A copy with a different stats string. The overlay draws when a tile carries one, so turning
    /// it on means rewriting the tiles rather than setting a flag; a live screen rebuilds them from
    /// receive statistics on every refresh, and the harness has to do the same by hand.
    func withStats(_ stats: String?) -> ElementCallTile {
        ElementCallTile(id: id,
                        userID: userID,
                        displayName: displayName,
                        avatarURL: avatarURL,
                        isLocal: isLocal,
                        isMicrophoneMuted: isMicrophoneMuted,
                        hasVideo: hasVideo,
                        isSpeaking: isSpeaking,
                        hasHandRaised: hasHandRaised,
                        isHero: isHero,
                        stats: stats)
    }
    
    /// Our own mute and camera, taken from the controls rather than from the tile; anyone else's
    /// tile comes back unchanged. The reason is latency rather than preference: a mute tap has to
    /// reach the badge before the transport round-trips. The model publishes per-tile state
    /// immediately, but that is a promise about its own coalescing window, not about the round trip.
    /// The live composition and the harness both go through here, so a harness tap changes our
    /// tile exactly as a real one does.
    func withLocalMedia(isMicrophoneMuted: Bool, hasVideo: Bool) -> ElementCallTile {
        guard isLocal else { return self }
        return ElementCallTile(id: id,
                               userID: userID,
                               displayName: displayName,
                               avatarURL: avatarURL,
                               isLocal: isLocal,
                               isMicrophoneMuted: isMicrophoneMuted,
                               hasVideo: hasVideo,
                               isSpeaking: isSpeaking,
                               hasHandRaised: hasHandRaised,
                               isHero: isHero,
                               stats: stats)
    }
}

public nonisolated enum ElementCallScreenViewAction: Sendable {
    case toggleMicrophone
    case toggleCamera
    case switchCamera
    case toggleScreenShare
    case toggleLoudspeaker
    case toggleTileStats
    case minimize
    case hangUp
    case dismiss
}
