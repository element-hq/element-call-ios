//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCall
import Foundation

/// Accessibility identifiers for the call UI.
///
/// **These are public API.** An external interop test rig drives real builds of the host app
/// through them, so a rename is a breaking change for something outside this repository. Add
/// freely, but do not rename or remove without checking who depends on it.
///
/// Every identifier is prefixed so it cannot collide with a host's own.
public nonisolated enum ElementCallAccessibilityIdentifiers {
    private static let prefix = "elementCall"
    
    // MARK: Controls
    
    public static let hangUp = "\(prefix).hangUp"
    public static let microphone = "\(prefix).microphone"
    public static let camera = "\(prefix).camera"
    public static let audioOutput = "\(prefix).audioOutput"
    public static let screenShare = "\(prefix).screenShare"
    public static let minimize = "\(prefix).minimize"
    /// Leaves the full-screen tile. Spelled out rather than derived from its icon: it borrows the
    /// collapse glyph, and `control(for:)` maps that to `minimize`, which would leave two different
    /// buttons answering to one identifier.
    public static let exitFullscreen = "\(prefix).exitFullscreen"
    public static let more = "\(prefix).more"
    
    // MARK: Structure
    
    public static let stage = "\(prefix).stage"
    public static let minimizedBar = "\(prefix).minimizedBar"
    public static let roomName = "\(prefix).roomName"
    public static let callState = "\(prefix).callState"
    
    /// A tile, identified by the member on it, so a test can assert about one participant.
    public static func tile(memberID: String) -> String {
        "\(prefix).tile.\(memberID)"
    }
    
    /// The control that shows a given icon. Derived rather than hand-written at each call site so a
    /// new control cannot quietly ship without one.
    static func control(for icon: ElementCallIcon) -> String {
        switch icon {
        case .endCall: hangUp
        case .micOn, .micOff: microphone
        case .videoCall, .videoCallOff: camera
        case .volumeOn, .volumeOff: audioOutput
        case .shareScreen: screenShare
        case .collapse: minimize
        case .overflow: more
        case .switchCamera: "\(prefix).switchCamera"
        case .raisedHand: "\(prefix).raisedHand"
        case .userProfile: "\(prefix).userProfile"
        }
    }
}
