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
    /// Whether a minimized call may open a Picture in Picture window. A host without the
    /// background mode entitlement should answer false, and calls minimize to the bar instead.
    var isPictureInPictureEnabled: Bool { get }
    /// How membership is published. Pinned by the host because it has to match the other clients in
    /// the room, and it cannot change once a session has joined.
    var elementCallCompatibility: MatrixRtcElementCallCompat { get }
    /// Whether the developer stats overlay can be toggled on a tile.
    var areTileStatsAvailable: Bool { get }
    /// Whether *leaving the app* during an audio-only call may open the window by itself. A video
    /// call always may.
    ///
    /// Separate from ``isPictureInPictureEnabled``, which governs minimizing on purpose. The
    /// default is false because CallKit's island already represents a backgrounded audio call, and
    /// a window appearing on every app switch is intrusive when there is only an avatar to show.
    var isAutomaticPictureInPictureForAudioCallsEnabled: Bool { get }
}

public nonisolated extension ElementCallOptions {
    /// Defaulted so that adding this did not break every host's existing conformance.
    var isAutomaticPictureInPictureForAudioCallsEnabled: Bool {
        false
    }
}

/// Defaults for a host that has no opinion.
public nonisolated struct ElementCallDefaultOptions: ElementCallOptions {
    public var isPictureInPictureEnabled: Bool
    public var elementCallCompatibility: MatrixRtcElementCallCompat
    public var areTileStatsAvailable: Bool
    public var isAutomaticPictureInPictureForAudioCallsEnabled: Bool
    
    public init(isPictureInPictureEnabled: Bool = true,
                elementCallCompatibility: MatrixRtcElementCallCompat = .stateEvents,
                areTileStatsAvailable: Bool = false,
                isAutomaticPictureInPictureForAudioCallsEnabled: Bool = false) {
        self.isPictureInPictureEnabled = isPictureInPictureEnabled
        self.elementCallCompatibility = elementCallCompatibility
        self.areTileStatsAvailable = areTileStatsAvailable
        self.isAutomaticPictureInPictureForAudioCallsEnabled = isAutomaticPictureInPictureForAudioCallsEnabled
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
/// One of our own log lines, with the position it came from.
public nonisolated struct ElementCallLogRecord: Sendable {
    public let level: ElementCallLogLevel
    public let message: String
    /// `#fileID` of the call site, e.g. `ElementCall/ElementCallController.swift`.
    public let file: String
    public let line: Int
    
    public init(level: ElementCallLogLevel, message: String, file: String, line: Int) {
        self.level = level
        self.message = message
        self.file = file
        self.line = line
    }
}

public nonisolated protocol ElementCallLogging: Sendable {
    /// The one method a host implements.
    ///
    /// Takes a record rather than `(level, message, file, line)` because the convenience below
    /// needs `#fileID` and `#line` defaults, and Swift does not allow default arguments on a
    /// protocol requirement — an extension with the same signature would become the requirement's
    /// own default implementation and recurse forever on a host that did not override it.
    func log(_ record: ElementCallLogRecord)
}

public nonisolated extension ElementCallLogging {
    /// What everything in this package calls. The defaults make the call site attribute itself,
    /// so a host formatting a line with a position gets our source rather than its own bridge.
    func log(_ level: ElementCallLogLevel, _ message: String, file: String = #fileID, line: Int = #line) {
        log(ElementCallLogRecord(level: level, message: message, file: file, line: line))
    }
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
