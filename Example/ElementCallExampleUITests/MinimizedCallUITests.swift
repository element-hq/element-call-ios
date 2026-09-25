//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import XCTest

/// Minimizing a call to the bar and coming back, through real touches.
///
/// This earns a UI test on three counts, none of which the package's own target can reach. The
/// minimize button's accessibility identifier reached no view until this feature needed it — the
/// same omission that had already happened once for the overflow button, and which a unit test on
/// `ElementCallAccessibilityIdentifiers` cannot see, because the constant was always there and it
/// was the modifier that was missing. The button then has to actually take the touch, sitting as it
/// does in a top bar inside the same `ZStack` as the floating controls. And the bar has to be
/// hittable where a host puts it, above a list, which is a hit-testing question rather than a
/// drawing one.
///
/// XCTest rather than swift-testing, for the reason given in `TileFullscreenUITests`.
final class MinimizedCallUITests: XCTestCase {
    private var app: XCUIApplication!
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // No `-arrangement`, so the app opens on the catalogue and the fixture is chosen by tapping,
        // which is the path a person takes.
        app.launch()
    }
    
    private func openGroupFixture() {
        let row = app.buttons["example.fixture.group"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The catalogue should list the group fixture.")
        row.tap()
        XCTAssertTrue(carol.waitForExistence(timeout: 10), "Picking a fixture should open the call screen.")
    }
    
    private var carol: XCUIElement {
        app.otherElements["elementCall.tile.@carol:example.com:DEVICE"]
    }
    
    /// Any tile actually in view. Asked rather than worked out: how many fit is the layout's
    /// business, and all this needs to know is whether the stage is there at all.
    private func hasVisibleTiles() -> Bool {
        let tiles = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "elementCall.tile."))
        return tiles.allElementsBoundByAccessibilityElement.contains { $0.isHittable }
    }
    
    func testMinimizingCollapsesTheCallToTheBarAndTheBarComesBack() {
        openGroupFixture()
        
        app.buttons["elementCall.minimize"].tap()
        
        let bar = app.buttons["elementCall.minimizedBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "Minimizing should leave the call in the bar.")
        XCTAssertFalse(hasVisibleTiles(), "The stage should be gone while the call is minimized.")
        XCTAssertTrue(app.buttons["example.fixture.oneToOne"].isHittable,
                      "The catalogue should be reachable behind a minimized call, not merely visible.")
        
        bar.tap()
        
        XCTAssertTrue(carol.waitForExistence(timeout: 5), "Tapping the bar should restore the call.")
        XCTAssertFalse(bar.exists, "The bar belongs to a minimized call only.")
    }
    
    /// Both kinds of fixture in one launch, because they hang up through entirely different code
    /// and a second twenty-second launch to say so would be twenty seconds badly spent. A connected
    /// fixture only *reports* the tap, through the harness context's `onHostAction`; a connecting
    /// one runs a real view model, so the tap goes to `ElementCallController.hangUp()` and comes
    /// back as an `ended` action over Combine — including a teardown that happens inside that
    /// subscription's own delivery.
    func testHangingUpReturnsToTheCatalogue() {
        openGroupFixture()
        
        app.buttons["elementCall.hangUp"].tap()
        
        let row = app.buttons["example.fixture.group"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Hanging up should come back to the catalogue.")
        XCTAssertFalse(app.buttons["elementCall.minimizedBar"].exists,
                       "A call that ended is not a call that was minimized.")
        
        // Below the fold on a small phone now that the catalogue has a scenarios section too, and
        // a tap does not scroll to its target.
        let joining = app.buttons["example.fixture.joining"]
        for _ in 0..<4 where !joining.isHittable {
            app.swipeUp()
        }
        joining.tap()
        XCTAssertTrue(app.buttons["elementCall.hangUp"].waitForExistence(timeout: 10),
                      "A connecting fixture should open its screen too.")
        
        app.buttons["elementCall.hangUp"].tap()
        
        XCTAssertTrue(row.waitForExistence(timeout: 5),
                      "A controller-driven call should come back to the catalogue as well.")
    }
}
