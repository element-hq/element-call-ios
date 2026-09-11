//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCall
@testable import ElementCallUI
import Foundation
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
    
    /// The checkout the tests were built from, the same route `PreviewTests` takes to its record
    /// marker.
    static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // ElementCallTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // the checkout
        .appendingPathComponent("Sources")
    
    /// Nil when the simulator may not read the checkout. macOS refuses it anything under
    /// `~/Documents` or `~/Desktop`, and the read fails with "Operation not permitted" rather than
    /// "not found", so a checkout in either place would fail the test below on where it sits rather
    /// than on what it found.
    static let declarations = try? String(contentsOf: sources.appendingPathComponent("ElementCallUI/ElementCallAccessibilityIdentifiers.swift"),
                                          encoding: .utf8)
    
    /// Spelling is worth nothing if no view carries the identifier. Four of them — the stage, the
    /// room name, the call state and every tile — were declared, asserted above, and applied to
    /// nothing at all: the rig could not find any of them, and this suite stayed green throughout,
    /// because it only ever compared strings to themselves.
    ///
    /// So read the sources and insist each one reaches a view. A control reaches one through
    /// ``ElementCallAccessibilityIdentifiers/control(for:)`` rather than by name, which is why the
    /// switch arm counts.
    ///
    /// Skipped rather than failed where the sources cannot be read, so it lies in neither
    /// direction. CI checks out somewhere unguarded, which is where this has to hold.
    @Test("Every declared identifier is applied to a view",
          .enabled(if: declarations != nil, "the simulator may not read this checkout"))
    func everyIdentifierIsApplied() throws {
        let sources = Self.sources
        let declarations = try #require(Self.declarations)
        
        let declared = declarations.split(separator: "\n").compactMap { line -> String? in
            guard let range = line.range(of: "(?<=static (let|func) )\\w+", options: .regularExpression) else { return nil }
            let name = String(line[range])
            return name == "prefix" ? nil : name
        }
        // The parse itself can rot. If it ever stops finding the declarations this test would pass
        // by checking nothing, which is the failure it exists to prevent.
        #expect(declared.count >= 12, "only parsed \(declared.count) identifiers: \(declared)")
        
        var code = ""
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        for case let url as URL in files ?? .init() where url.pathExtension == "swift" {
            code += try String(contentsOf: url, encoding: .utf8)
        }
        
        for name in declared {
            let isApplied = code.contains("ElementCallAccessibilityIdentifiers.\(name)")
            let isReachedByIcon = declarations.range(of: ": \(name)$", options: [.regularExpression]) != nil
                || declarations.contains(": \(name)\n")
            #expect(isApplied || isReachedByIcon,
                    "\(name) is declared but no view applies it, and no icon resolves to it")
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
