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
    /// not choose a spotlight; ``ElementCallScreenViewState/spotlightID`` is where that is decided.
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

/// How the tiles are arranged.
public nonisolated enum ElementCallLayout: Sendable {
    /// The other person fills the screen, we are a thumbnail over them.
    case oneToOne
    /// Whoever is talking large, everyone else in the strip.
    case group
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
    
    /// Which tile gets the largest slot.
    ///
    /// The model **ranks**; it does not choose a spotlight. It marks a hero — a screen share today,
    /// a pin later — and orders everything after it, and what a UI does with its largest slot stays
    /// the UI's business. So: the hero if there is one, else the head of the ranking, which is who
    /// the model's damping has settled on.
    ///
    /// Never ourselves while anybody else is there, and that now costs nothing: we are not in the
    /// model's list at all, we are spliced in at the front, so reading past ourselves is the whole
    /// of the rule. It used to be three separate guards.
    ///
    /// Reading `isHero` rather than taking `tiles[1]` is not belt and braces. It is the difference
    /// between honouring a fact the model states and assuming a sort order agrees with it; if they
    /// ever disagree, the hero is the answer.
    public var spotlightID: MatrixRTCTileID? {
        (tiles.first(where: \.isHero) ?? tiles.first { !$0.isLocal })?.id
    }
    
    /// One-to-one is a direct chat with at most one other tile on the stage, and that tile a camera:
    /// alone while the other side is still ringing, our own camera fills the screen and shrinks to
    /// the thumbnail once they arrive. Anyone else joining is a group call, because a third member
    /// has nowhere to go in a two-tile layout.
    ///
    /// The `isLocal` count is gone: the own tile is no longer one of the model's, the view model
    /// splices it in unconditionally, so counting it proves nothing. The share test survives for the
    /// sharer whose camera is *off* — two tiles by the count, and a layout that would otherwise put
    /// our thumbnail over somebody's spreadsheet. Our own share still never makes a tile at all, so
    /// it still cannot turn a direct call into a group one.
    public var layout: ElementCallLayout {
        isDirect && tiles.count <= 2 && !tiles.contains(where: \.isScreenShare) ? .oneToOne : .group
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
