//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import XCTest

/// What is inside the top bar's overflow menu.
///
/// This belongs here rather than in a snapshot for a concrete reason: a SwiftUI `Menu` renders only
/// its label until it is opened, so an image of the call screen says nothing about its contents. A
/// real tap is the only way to see them, which is the same reason the tile gestures live here.
///
/// XCTest rather than swift-testing, for the reason given in `TileFullscreenUITests`.
final class OverflowMenuUITests: XCTestCase {
    private var app: XCUIApplication!
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-arrangement", "group"]
        app.launch()
    }
    
    private func openMenu() {
        let more = app.buttons["elementCall.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "The overflow button should be in the top bar.")
        more.tap()
    }
    
    /// The harness runs over the preview fixtures, which stand in for a host with developer mode on,
    /// so the diagnostics toggle is the one thing expected to be here.
    func testTheMenuOffersTheStatsOverlayInDeveloperMode() {
        openMenu()
        
        XCTAssertTrue(app.buttons["Tile stats"].waitForExistence(timeout: 3)
                          || app.switches["Tile stats"].waitForExistence(timeout: 1),
                      "Developer mode is on in the fixtures, so the stats toggle should be offered.")
    }
    
    /// The version row is what a bug report quotes, and it is also what keeps the menu from being
    /// empty for a host with everything gated off.
    func testTheMenuNamesThePackageVersion() {
        openMenu()
        
        let version = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Element Call '")).firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 3),
                      "The menu should end with the package version.")
    }
    
    /// The tone used to sit between the two, and removing it is the point of the change. Asserting
    /// its absence is cheap and stops it being reintroduced by a revert.
    func testTheAudioTestToneIsGone() {
        openMenu()
        
        XCTAssertFalse(app.descendants(matching: .any)
                           .matching(NSPredicate(format: "label CONTAINS '440'")).firstMatch.exists,
                       "The audio test tone was removed outright.")
    }
}
