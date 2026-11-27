//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import XCTest

/// The call lobby (045) through real touches, on fixtures.md's Lobby fixtures: the real controller,
/// a scripted core. Only what needs a touch to arrive is here; the lobby's behaviour is
/// `LobbyTests`, in process.
///
/// XCTest rather than swift-testing, for the reason given in `TileFullscreenUITests`.
final class LobbyUITests: XCTestCase {
    private var app: XCUIApplication!
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }
    
    private func open(_ fixture: String) {
        app.launchArguments = ["-fixture", fixture]
        app.launch()
    }
    
    private var join: XCUIElement {
        app.buttons["elementCall.lobby.join"]
    }
    
    private var preview: XCUIElement {
        app.otherElements["elementCall.lobby.preview"]
    }
    
    /// R36: a gesture declared off can still take the touch, so the preview is tapped, double tapped
    /// and pinched for real, and the lobby must be exactly where it was.
    func testTapsAndPinchesOnThePreviewDoNothing() {
        open("lobby_join")
        XCTAssertTrue(join.waitForExistence(timeout: 10))
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        let frame = preview.frame
        
        preview.doubleTap()
        preview.pinch(withScale: 2, velocity: 1)
        preview.tap()
        
        XCTAssertTrue(preview.exists, "The preview should still be the lobby's, not a tile gone full screen.")
        XCTAssertEqual(preview.frame, frame, "Nothing on the preview should move it.")
        XCTAssertFalse(app.buttons["elementCall.exitFullscreen"].exists, "A double tap must not take the preview full screen.")
        XCTAssertTrue(join.isHittable, "The chrome is pinned in the lobby: a tap must not hide it.")
    }
    
    /// R20, R33: the leading button reads Close and closes; it never minimizes.
    func testCloseClosesAndNeverMinimizes() {
        open("lobby_empty")
        let close = app.buttons["elementCall.lobby.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertEqual(close.label, "Close")
        XCTAssertFalse(app.buttons["elementCall.minimize"].exists, "The lobby has no minimize button.")
        
        close.tap()
        
        XCTAssertTrue(join.waitForNonExistence(timeout: 5), "Close should close the lobby.")
        XCTAssertFalse(app.buttons["elementCall.minimizedBar"].exists, "A closed lobby leaves no minimized bar.")
    }
    
    /// R23, R24, R49: the tap switches to the call at once, our tile is on the stage throughout, and
    /// the bar grows the call's buttons in place. No spinner is ever in the tree: our tile from the
    /// lobby is the stage until the core reports its own.
    func testJoinMovesThePreviewIntoOurTile() {
        open("lobby_join")
        XCTAssertTrue(join.waitForExistence(timeout: 10))
        XCTAssertTrue(join.isEnabled)
        XCTAssertFalse(app.buttons["elementCall.hangUp"].exists, "The lobby's bar has no hang-up (C3).")
        
        join.tap()
        
        XCTAssertTrue(app.buttons["elementCall.hangUp"].waitForExistence(timeout: 5), "Join should grow the call's buttons in.")
        XCTAssertFalse(join.exists)
        XCTAssertFalse(app.activityIndicators.firstMatch.exists, "No spinner while joining from a lobby.")
        let ownTile = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@",
                                                             "elementCall.tile.", "alice")).firstMatch
        XCTAssertTrue(ownTile.waitForExistence(timeout: 10), "Our tile should be in the call.")
        XCTAssertTrue(app.buttons["elementCall.minimize"].exists, "In the call the leading button minimizes again.")
    }
    
    /// R27: Join looks as always with the microphone refused, and its tap explains rather than joins.
    func testJoinWithTheMicrophoneRefusedExplains() {
        open("lobby_mic_refused")
        XCTAssertTrue(join.waitForExistence(timeout: 10))
        let loaded = NSPredicate(format: "label != %@", "Loading call")
        expectation(for: loaded, evaluatedWith: join)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(join.isEnabled, "Join should look as it always does (R27).")
        
        join.tap()
        
        let alert = app.alerts["Microphone needed"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Join should say the microphone is needed.")
        XCTAssertTrue(alert.buttons["Open settings"].exists)
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(join.exists, "The lobby stays open.")
        XCTAssertFalse(app.buttons["elementCall.hangUp"].exists, "Nothing joined.")
    }
    
    /// A second join in one run of the app: the first call's audio has to be gone before the second
    /// one's starts. On an iPhone the second Join crashed the app.
    func testJoiningTwiceInOneRun() {
        open("lobby_join")
        for attempt in 1...2 {
            if attempt > 1 {
                // Hanging up comes back to the catalogue at the row last opened.
                let row = app.buttons["example.fixture.lobby_join"]
                XCTAssertTrue(row.waitForExistence(timeout: 10), "Attempt \(attempt): the catalogue should show lobby_join.")
                row.tap()
            }
            XCTAssertTrue(join.waitForExistence(timeout: 10))
            let loaded = NSPredicate(format: "label != %@", "Loading call")
            expectation(for: loaded, evaluatedWith: join)
            waitForExpectations(timeout: 10)
            join.tap()
            let hangUp = app.buttons["elementCall.hangUp"]
            XCTAssertTrue(hangUp.waitForExistence(timeout: 10), "Attempt \(attempt): Join should land in the call.")
            // Long enough for the call's audio to start, which is where the second attempt died.
            sleep(3)
            XCTAssertEqual(app.state, .runningForeground, "Attempt \(attempt): the app should still be running.")
            hangUp.tap()
            XCTAssertTrue(hangUp.waitForNonExistence(timeout: 10))
        }
    }
}
