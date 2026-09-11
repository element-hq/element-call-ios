//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCall
@testable import ElementCallUI
import Testing

/// The identifiers are consumed by an interop test rig outside this repository, which means they are
/// API and a rename breaks someone else's build.
///
/// The exact strings are asserted on purpose. A rename should fail here and make whoever did it
/// decide deliberately to break the rig, rather than finding out when the rig goes red.
@Suite("Accessibility identifiers")
nonisolated struct AccessibilityIdentifierTests {
    @Test("The published identifiers keep their exact spelling")
    func spelling() {
        #expect(ElementCallAccessibilityIdentifiers.hangUp == "elementCall.hangUp")
        #expect(ElementCallAccessibilityIdentifiers.microphone == "elementCall.microphone")
        #expect(ElementCallAccessibilityIdentifiers.camera == "elementCall.camera")
        #expect(ElementCallAccessibilityIdentifiers.audioOutput == "elementCall.audioOutput")
        #expect(ElementCallAccessibilityIdentifiers.screenShare == "elementCall.screenShare")
        #expect(ElementCallAccessibilityIdentifiers.minimize == "elementCall.minimize")
        #expect(ElementCallAccessibilityIdentifiers.more == "elementCall.more")
        #expect(ElementCallAccessibilityIdentifiers.stage == "elementCall.stage")
        #expect(ElementCallAccessibilityIdentifiers.minimizedBar == "elementCall.minimizedBar")
        #expect(ElementCallAccessibilityIdentifiers.roomName == "elementCall.roomName")
        #expect(ElementCallAccessibilityIdentifiers.callState == "elementCall.callState")
    }
    
    @Test("A tile is addressable by the member on it")
    func tile() {
        #expect(ElementCallAccessibilityIdentifiers.tile(memberID: "@bob:example.com:DEVICE")
            == "elementCall.tile.@bob:example.com:DEVICE")
    }
    
    /// Every control derives its identifier from its icon, so this is what stops a new control from
    /// shipping without one.
    @Test("Every icon resolves to a prefixed, non-empty identifier")
    func everyIconIsAddressable() {
        for icon in ElementCallIcon.allCases {
            let identifier = ElementCallAccessibilityIdentifiers.control(for: icon)
            #expect(identifier.hasPrefix("elementCall."), "\(icon) is not prefixed")
            #expect(identifier.count > "elementCall.".count, "\(icon) has an empty identifier")
        }
    }
    
    /// Two icons may share an identifier when they are two states of one control, mute against
    /// unmute for instance, but a control must never share with an unrelated one.
    @Test("Controls that are not paired states have distinct identifiers")
    func distinctness() {
        let paired: [Set<ElementCallIcon>] = [[.micOn, .micOff],
                                              [.videoCall, .videoCallOff],
                                              [.volumeOn, .volumeOff]]
        var seen = [String: ElementCallIcon]()
        for icon in ElementCallIcon.allCases {
            let identifier = ElementCallAccessibilityIdentifiers.control(for: icon)
            if let other = seen[identifier] {
                let isPair = paired.contains { $0.contains(icon) && $0.contains(other) }
                #expect(isPair, "\(icon) and \(other) share \(identifier) but are not paired states")
            }
            seen[identifier] = icon
        }
    }
}
