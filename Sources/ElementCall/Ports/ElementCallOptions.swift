//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallKit
import Foundation

/// Host settings the call reads. Named Options rather than Configuration because hosts embedding the
/// Element Call widget already have a configuration type of their own.
///
/// Read every time rather than captured, so a host backing these with live settings sees the change.
public nonisolated protocol ElementCallOptions: Sendable {
    /// Whether a minimized video call may open a Picture in Picture window. A host without the
    /// background mode entitlement should answer false, and calls minimize to the bar instead.
    var isPictureInPictureEnabled: Bool { get }
    /// How membership is published. Pinned by the host because it has to match the other clients in
    /// the room, and it cannot change once a session has joined.
    var elementCallCompatibility: MatrixRtcElementCallCompat { get }
    /// Whether the developer stats overlay can be toggled on a tile.
    var areTileStatsAvailable: Bool { get }
}

/// Defaults for a host that has no opinion.
public nonisolated struct ElementCallDefaultOptions: ElementCallOptions {
    public var isPictureInPictureEnabled: Bool
    public var elementCallCompatibility: MatrixRtcElementCallCompat
    public var areTileStatsAvailable: Bool
    
    public init(isPictureInPictureEnabled: Bool = true,
                elementCallCompatibility: MatrixRtcElementCallCompat = .stateEvents,
                areTileStatsAvailable: Bool = false) {
        self.isPictureInPictureEnabled = isPictureInPictureEnabled
        self.elementCallCompatibility = elementCallCompatibility
        self.areTileStatsAvailable = areTileStatsAvailable
    }
}

public nonisolated enum ElementCallLogLevel: Sendable {
    case debug, info, warning, error
}

/// Where our log lines go. The host owns this so call logs land in the same place, and the same
/// rageshake, as everything else it writes.
///
/// Note this covers only this package's own lines. The media layer's logs, and the Rust core's, go
/// through the core's own subscriber, which the host installs separately.
public nonisolated protocol ElementCallLogging: Sendable {
    func log(_ level: ElementCallLogLevel, _ message: String)
}

/// Text the call screen shows. English defaults, because a host without translations should still
/// get something readable rather than a key.
public nonisolated struct ElementCallStrings: Sendable {
    public var you: String
    public var error: String
    public var stop: String
    public var back: String
    
    public init(you: String = "You", error: String = "Error", stop: String = "Stop", back: String = "Back") {
        self.you = you
        self.error = error
        self.stop = stop
        self.back = back
    }
}
