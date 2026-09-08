//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCall
import ElementCallKit
import Foundation

/// One tile of the call: a member as the layout sees it, video or avatar.
public nonisolated struct ElementCallTile: Identifiable, Equatable, Sendable {
    public let memberID: String
    public let userID: String
    public let displayName: String
    public let avatarURL: URL?
    public let isLocal: Bool
    /// Cannot be heard: muted, or no microphone stream reached us at all. The badge collapses the
    /// two on purpose; `hasMicrophone` keeps them apart for the stats overlay, where the question is why.
    public let isMicrophoneMuted: Bool
    /// Whether a microphone stream reaches us at all, muted or not. Absent is a fault worth showing:
    /// a member the SFU relays to everyone else would otherwise read here as having muted themselves.
    public let hasMicrophone: Bool
    public let hasVideo: Bool
    public let isScreenSharing: Bool
    public let isSpeaking: Bool
    public let hasHandRaised: Bool
    public let isFrontCamera: Bool
    public let audioLevel: Float
    public let stats: String?
    
    public var id: String {
        memberID
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

public nonisolated struct ElementCallScreenViewState: Sendable {
    public var roomName: String
    /// Whether the room is a direct chat. False until the room has been read.
    public var isDirect = false
    public var connection: ElementCallConnection = .idle
    public var connectedAt: Date?
    public var memberCount = 0
    public var tiles: [ElementCallTile] = []
    public var spotlightMemberID: String?
    public var isMicrophoneMuted = false
    public var isCameraEnabled = false
    public var isFrontCamera = true
    public var isScreenSharing = false
    public var isLoudspeaker = false
    public var isMediaDegraded = false
    public var isTileStatsVisible = false
    public var areTileStatsAvailable = false
    /// False while minimized, in the bar or the system window: the tiles unmount so only the window decodes.
    public var isMaximized = true
    public var isAudioTestToneEnabled = false
    
    /// One-to-one is a direct chat with at most the two of us in it, each on a camera tile: alone
    /// while the other side is still ringing, our own camera fills the screen and shrinks to the
    /// thumbnail once they arrive. Anyone else joining, or the other side sharing a screen, is a
    /// group call: the spotlight knows what to do with a share, and a third member has nowhere to go
    /// in a two-tile layout. Our own share stays one-to-one because it never makes a tile of its own.
    public var layout: ElementCallLayout {
        let isJustUs = isDirect && tiles.count <= 2 && tiles.filter(\.isLocal).count == 1
        return isJustUs && !tiles.contains { !$0.isLocal && $0.isScreenSharing } ? .oneToOne : .group
    }
    
    public var isVideoCall: Bool {
        isCameraEnabled || tiles.contains { $0.hasVideo || $0.isScreenSharing }
    }
}

public nonisolated enum ElementCallScreenViewAction: Sendable {
    case toggleMicrophone
    case toggleCamera
    case switchCamera
    case toggleScreenShare
    case toggleLoudspeaker
    case toggleTileStats
    case toggleAudioTestTone
    case minimize
    case hangUp
    case dismiss
}
