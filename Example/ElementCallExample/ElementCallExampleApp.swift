//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallAll
import SwiftUI

/// A call screen with no call behind it, for driving by hand or by a UI test.
///
/// Which arrangement it opens on is read from the launch arguments so a test can start where it
/// means to, rather than tapping its way there through a menu it does not care about.
@main
struct ElementCallExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ElementCallExampleScreen(arrangement: .fromLaunchArguments())
        }
    }
}

/// The states worth having on hand. Each is a shape of the layout rather than a feature: what a test
/// or a person poking at it needs is a stage with a strip that pages, a one-to-one call, and a
/// screen share, because those are the three arrangements a tile can be full screen *from*.
enum ElementCallExampleArrangement: String, CaseIterable {
    case group
    case pagedStrip
    case oneToOne
    case screenShare
    
    static let launchArgument = "-arrangement"
    
    static func fromLaunchArguments() -> ElementCallExampleArrangement {
        guard let index = ProcessInfo.processInfo.arguments.firstIndex(of: launchArgument),
              let name = ProcessInfo.processInfo.arguments[safe: index + 1],
              let arrangement = ElementCallExampleArrangement(rawValue: name) else { return .group }
        return arrangement
    }
    
    var title: String {
        switch self {
        case .group: "Group"
        case .pagedStrip: "Paged strip"
        case .oneToOne: "One to one"
        case .screenShare: "Screen share"
        }
    }
    
    /// Built from the same fixtures the snapshots use, so a failure here and a failure there are
    /// talking about the same people.
    @MainActor
    var state: ElementCallScreenViewState {
        typealias Fixtures = ElementCallPreviewFixtures
        switch self {
        case .group:
            return Fixtures.connected(tiles: Fixtures.group, spotlight: Fixtures.carol.memberID)
        case .pagedStrip:
            // Enough people that the strip runs to more than one page: going full screen from page
            // two and coming back to page two is the thing worth checking.
            let extras = (1...16).map { Fixtures.tile("Member\($0)") }
            return Fixtures.connected(tiles: Fixtures.group + extras, spotlight: Fixtures.carol.memberID)
        case .oneToOne:
            // Our camera on, so the tile draws its flip button: the one control inside a tile, and
            // so the one thing that can prove a tap still reaches a button rather than the gesture
            // wrapped around it.
            return Fixtures.connected(tiles: [Fixtures.tile("Alice", isLocal: true, hasVideo: true), Fixtures.bob],
                                      isDirect: true)
        case .screenShare:
            let sharer = Fixtures.tile("Frank", hasVideo: true, isScreenSharing: true)
            return Fixtures.connected(tiles: [Fixtures.alice, Fixtures.bob, sharer], spotlight: sharer.memberID)
        }
    }
}

struct ElementCallExampleScreen: View {
    let arrangement: ElementCallExampleArrangement
    
    @State private var context: ElementCallScreenContext?
    
    var body: some View {
        ZStack {
            if let context {
                ElementCallHarnessScreen(context: context)
            }
        }
        .onAppear {
            guard context == nil else { return }
            context = .preview(state: arrangement.state)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
