//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCall
import SwiftUI

/// Everything the harness can show, and the catalogue's rows.
///
/// The connected ones are shapes of the *layout* rather than features: what a test or a person
/// poking at it needs is a stage with a strip that pages, a one-to-one call, and a screen share,
/// because those are the three arrangements a tile can be full screen *from*.
///
/// The connecting ones are the states the stage never reaches. No fixture can express them —
/// `ElementCallPreviewFixtures.connected(...)` only ever builds a connected call — so they come from
/// a real view model over a fake controller instead. That difference is not cosmetic: a view model
/// routes minimize and hang up through ``ElementCallController``, so those rows exercise the genuine
/// host contract while the connected rows can only report the tap. See ``ElementCallExampleHost``.
enum ElementCallExampleFixture: String, CaseIterable {
    case group
    case pagedStrip
    case oneToOne
    case screenShare
    case sharerOnAPagedStrip
    case video
    case joining
    case connectingMedia
    case failed
    case ended
    
    /// Still spelled `-arrangement` although the list now holds more than arrangements: it is what
    /// the UI tests pass and what the recipe in AGENTS.md documents, and renaming it would buy
    /// nothing but a broken recipe.
    static let launchArgument = "-arrangement"
    
    /// Named `Category` rather than `Section` so it does not collide with SwiftUI's `Section` at
    /// the catalogue's use site, where both would be in scope.
    enum Category: String, CaseIterable {
        case connected = "Connected"
        case connecting = "Connecting"
    }
    
    var category: Category {
        switch self {
        case .group, .pagedStrip, .oneToOne, .screenShare, .sharerOnAPagedStrip, .video: .connected
        case .joining, .connectingMedia, .failed, .ended: .connecting
        }
    }
    
    static func fixtures(in category: Category) -> [ElementCallExampleFixture] {
        allCases.filter { $0.category == category }
    }
    
    var title: String {
        switch self {
        case .group: "Group"
        case .pagedStrip: "Paged strip"
        case .oneToOne: "One to one"
        case .screenShare: "Screen share"
        case .sharerOnAPagedStrip: "Sharer on a paged strip"
        case .video: "Moving video"
        case .joining: "Joining"
        case .connectingMedia: "Connecting media"
        case .failed: "Failed"
        case .ended: "Ended"
        }
    }
    
    /// What this row is *for*. The knowledge was already in the comments on each case below; a
    /// catalogue is where it stops being invisible to anyone who is not reading this file.
    var detail: String {
        switch self {
        case .group: "Eight people, one spotlit."
        case .pagedStrip: "Enough people that the strip runs to more than one page."
        case .oneToOne: "A direct call, our camera on, so the tile draws its flip button."
        case .screenShare: "A remote share holding the spotlight, the sharer's camera in the strip."
        case .sharerOnAPagedStrip: "A sharer's camera pages away from their screen."
        case .video: "The only row fed real frames, some portrait and some landscape."
        case .joining: "Before there is a call to render."
        case .connectingMedia: "Joined, waiting on media."
        case .failed: "The error the screen shows once and clears."
        case .ended: "After hanging up, before the screen goes away."
        }
    }
    
    /// Whether the tiles should be fed generated frames. Only the video row asks for it, so every
    /// other one stays a pure layout harness with no timer running behind it.
    var wantsVideo: Bool {
        self == .video
    }
    
    /// A connected row is a view state written by hand; a connecting row is a connection for a fake
    /// controller to sit in. Modelled as a sum rather than branched on at each use site, because the
    /// two need different objects behind them all the way up to the root view.
    enum Kind {
        case connected(ElementCallScreenViewState)
        case connecting(ElementCallConnection)
    }
    
    /// Built from the same fixtures the snapshots use, so a failure here and a failure there are
    /// talking about the same people.
    @MainActor
    var kind: Kind {
        typealias Fixtures = ElementCallPreviewFixtures
        switch self {
        case .group:
            return .connected(Fixtures.connected(tiles: Fixtures.group))
        case .pagedStrip:
            // Enough people that the strip runs to more than one page: going full screen from page
            // two and coming back to page two is the thing worth checking.
            let extras = (1...16).map { Fixtures.tile("Member\($0)") }
            return .connected(Fixtures.connected(tiles: Fixtures.group + extras))
        case .oneToOne:
            // Our camera on, so the tile draws its flip button: the one control inside a tile, and
            // so the one thing that can prove a tap still reaches a button rather than the gesture
            // wrapped around it.
            return .connected(Fixtures.connected(tiles: [Fixtures.tile("Alice", isLocal: true, hasVideo: true), Fixtures.bob],
                                                 isDirect: true))
        case .screenShare:
            // Frank on **two** tiles: his screen is the hero and takes the spotlight, and his camera
            // is still in the strip beside everyone else's. That pairing is the whole of what
            // changed, and it is the one arrangement in which a member-keyed accessibility
            // identifier, released set or `ForEach` identity is wrong rather than merely redundant.
            return .connected(Fixtures.connected(tiles: [Fixtures.alice, Fixtures.share("Frank"),
                                                         Fixtures.tile("Frank", hasVideo: true), Fixtures.bob]))
        case .sharerOnAPagedStrip:
            // The sharer's own camera pushed several pages away from their screen. Releasing by
            // member took the hero down with it a few seconds after a swipe, and only a running app
            // shows that: the spotlight simply goes black.
            let extras = (1...16).map { Fixtures.tile("Member\($0)") }
            return .connected(Fixtures.connected(tiles: [Fixtures.alice, Fixtures.share("Frank")] + extras
                                                     + [Fixtures.tile("Frank", hasVideo: true)]))
        case .video:
            // Bob and Erin are the portrait cameras, the rest landscape: see `TestPatternVideo`.
            // Dan has his camera off, because a stage where every tile is a picture is not the one
            // anybody is in: an avatar is a plain SwiftUI view that resizes on its own, and it is
            // worth being able to see the two side by side through the same move.
            // Dan comes second so he lands on the first page of the strip: a small phone fits only
            // two tiles to a page, and an avatar you have to swipe to reach is one you will forget
            // to look at.
            let tiles = ["Alice", "Dan", "Carol", "Bob", "Erin", "Frank"].enumerated().map { index, name in
                Fixtures.tile(name, isLocal: index == 0, hasVideo: name != "Dan")
            }
            return .connected(Fixtures.connected(tiles: tiles))
        case .joining:
            return .connecting(.joining)
        case .connectingMedia:
            return .connecting(.connectingMedia)
        case .failed:
            return .connecting(.failed("The call could not be joined."))
        case .ended:
            return .connecting(.ended)
        }
    }
}

/// What the app was asked to open on.
enum ElementCallExampleLaunchTarget {
    case catalogue
    case fixture(ElementCallExampleFixture)
    /// The flag was passed with something that is not a fixture. Deliberately not folded into
    /// ``catalogue``: the old behaviour was to quietly substitute `.group`, so `-arrangement
    /// pagedStrp` ran the strip tests against an eight-person stage and failed with "this tile is
    /// not hittable" — true, and about nothing. Named, it goes on screen, which means it goes into
    /// the failure screenshot.
    case unknown(String)
    
    static func fromLaunchArguments() -> ElementCallExampleLaunchTarget {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: ElementCallExampleFixture.launchArgument) else { return .catalogue }
        guard let name = arguments[safe: index + 1] else { return .unknown("") }
        guard let fixture = ElementCallExampleFixture(rawValue: name) else { return .unknown(name) }
        return .fixture(fixture)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
