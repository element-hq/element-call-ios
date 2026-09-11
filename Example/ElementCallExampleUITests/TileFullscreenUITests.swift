//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import XCTest

/// The gestures on a call tile, driven by real touches.
///
/// This is the one thing the package's own test target cannot do. `ElementCallStageLayoutTests`
/// proves the arrangement is right and the snapshots prove it is drawn right, but neither can tell a
/// double tap that reaches the tile from one that a gesture higher up claimed first, and that is the
/// failure this feature is prone to: the strip's paging drag and the tile's pan are attached to the
/// same view tree, and there is a `Button` inside the tile.
///
/// XCTest rather than swift-testing, because UI testing never moved: XCUIApplication drives a
/// separate process, which is exactly what swift-testing's in-process model cannot do.
final class TileFullscreenUITests: XCTestCase {
    private var app: XCUIApplication!
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }
    
    private func launch(_ arrangement: String) {
        app.launchArguments = ["-arrangement", arrangement]
        app.launch()
    }
    
    private func tile(_ user: String) -> XCUIElement {
        app.otherElements["elementCall.tile.@\(user):example.com:DEVICE"]
    }
    
    /// A tile on another page of the strip is still in the hierarchy, just parked a screen's width
    /// away, so `exists` says nothing about which page is in view and a tap on one cannot land.
    /// Hittable is the question worth asking of anything on the strip.
    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let hittable = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: element)
        return XCTWaiter().wait(for: [hittable], timeout: timeout) == .completed
    }
    
    /// Which tiles are actually on screen. Asked rather than worked out: how many fit on a page is
    /// the layout's business and it changes with the device, so a test that names the members it
    /// expects on page two is a test that breaks for reasons that have nothing to do with it.
    private func tilesOnScreen() -> Set<String> {
        let tiles = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "elementCall.tile."))
        return Set(tiles.allElementsBoundByAccessibilityElement.filter(\.isHittable).map(\.identifier))
    }
    
    /// How many tiles a strip page holds is the layout's arithmetic and it is smaller than you would
    /// guess: an iPhone SE in portrait fits two. So wait for a page rather than for a named member.
    private func waitForAPage(timeout: TimeInterval = 10) -> Set<String> {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let onScreen = tilesOnScreen()
            if !onScreen.isEmpty {
                return onScreen
            }
        }
        return []
    }
    
    /// Swipes the strip and waits for the page to actually change, returning what is on screen after.
    private func pageStrip(from before: Set<String>) -> Set<String> {
        app.swipeLeft()
        let deadline = Date().addingTimeInterval(5)
        var onScreen = before
        while Date() < deadline {
            onScreen = tilesOnScreen()
            if onScreen != before, !onScreen.isEmpty {
                return onScreen
            }
        }
        return onScreen
    }
    
    private var exitButton: XCUIElement {
        app.buttons["elementCall.exitFullscreen"]
    }
    
    private var hangUpButton: XCUIElement {
        app.buttons["elementCall.hangUp"]
    }
    
    // MARK: - Going full screen and back
    
    func testDoubleTappingATileFillsTheScreenWithIt() {
        launch("group")
        let bob = tile("bob")
        XCTAssertTrue(bob.waitForExistence(timeout: 10))
        XCTAssertTrue(tile("dan").exists, "the others are on the stage to begin with")
        
        bob.doubleTap()
        
        XCTAssertTrue(bob.waitForExistence(timeout: 2))
        XCTAssertFalse(tile("dan").exists, "full screen is one tile, not one tile on top of the rest")
    }
    
    func testDoubleTappingAgainComesBackToTheStage() {
        launch("group")
        let bob = tile("bob")
        XCTAssertTrue(bob.waitForExistence(timeout: 10))
        
        bob.doubleTap()
        XCTAssertFalse(tile("dan").exists)
        
        bob.doubleTap()
        XCTAssertTrue(tile("dan").waitForExistence(timeout: 2), "the stage came back")
        XCTAssertFalse(exitButton.exists)
    }
    
    /// The stage clamps `currentPage` whenever the page count changes, and full screen is one page.
    /// Without a guard on that, going full screen from page two silently rewinds the strip to page
    /// one, and that is where you land coming back.
    func testTheStripKeepsItsPageAcrossFullScreen() throws {
        launch("pagedStrip")
        let firstPage = waitForAPage()
        XCTAssertFalse(firstPage.isEmpty)
        
        let secondPage = pageStrip(from: firstPage)
        XCTAssertNotEqual(firstPage, secondPage, "the strip paged")
        let left = try app.otherElements[XCTUnwrap(firstPage.subtracting(secondPage).sorted().first)]
        let chosen = try app.otherElements[XCTUnwrap(secondPage.subtracting(firstPage).sorted().first)]
        
        chosen.doubleTap()
        XCTAssertTrue(waitForDisappearance(of: left), "went full screen from the second page")
        
        chosen.doubleTap()
        XCTAssertTrue(waitUntilHittable(chosen), "back on the stage")
        XCTAssertEqual(tilesOnScreen(), secondPage, "on the page we left, not rewound to the first one")
    }
    
    // MARK: - Chrome
    
    func testASingleTapRaisesAndLowersTheChrome() {
        launch("group")
        let bob = tile("bob")
        XCTAssertTrue(bob.waitForExistence(timeout: 10))
        
        bob.doubleTap()
        XCTAssertFalse(exitButton.exists, "full screen starts with the picture and nothing else")
        
        bob.tap()
        XCTAssertTrue(exitButtonAppears(), "a tap brought the chrome up")
        XCTAssertTrue(hangUpButton.exists, "and the controls with it")
        
        bob.tap()
        XCTAssertTrue(waitForDisappearance(of: exitButton), "and another put it away")
    }
    
    func testTheExitButtonLeavesFullScreen() {
        launch("group")
        let bob = tile("bob")
        XCTAssertTrue(bob.waitForExistence(timeout: 10))
        
        bob.doubleTap()
        bob.tap()
        XCTAssertTrue(exitButtonAppears())
        
        exitButton.tap()
        XCTAssertTrue(tile("dan").waitForExistence(timeout: 2), "back on the stage")
    }
    
    // MARK: - Gestures that must not collide
    
    /// A pinch is two fingers moving apart; the strip's paging drag is one finger moving sideways.
    /// They share a view tree, and the arrangement relies on full screen reporting a single page to
    /// keep the paging gesture out of the way.
    func testPinchingInFullScreenNeitherExitsNorPages() {
        launch("pagedStrip")
        let bob = tile("bob")
        XCTAssertTrue(bob.waitForExistence(timeout: 10))
        
        bob.doubleTap()
        XCTAssertTrue(waitForDisappearance(of: tile("dan")))
        
        bob.pinch(withScale: 3, velocity: 1)
        XCTAssertTrue(bob.exists, "still full screen")
        XCTAssertFalse(tile("dan").exists, "and still the only tile")
        
        bob.pinch(withScale: 0.2, velocity: -1)
        XCTAssertTrue(bob.exists, "pinching back out springs to the fitted size rather than leaving")
        XCTAssertFalse(tile("dan").exists)
    }
    
    /// The other half of the same arrangement: outside full screen the tile's own gestures must not
    /// have eaten the drag the strip pages with.
    func testTheStripStillPagesWhenNotFullScreen() {
        launch("pagedStrip")
        let firstPage = waitForAPage()
        XCTAssertFalse(firstPage.isEmpty)
        
        let secondPage = pageStrip(from: firstPage)
        
        XCTAssertNotEqual(firstPage, secondPage, "the tile's own gestures have not eaten the paging drag")
        XCTAssertFalse(secondPage.subtracting(firstPage).isEmpty, "and the new page brought tiles with it")
    }
    
    /// A `Button` inside the tile has to keep its taps: child gestures beat the parent's, which is
    /// why the tile uses `.gesture` and not `.highPriorityGesture`.
    func testTappingTheFlipButtonDoesNotGoFullScreen() {
        launch("oneToOne")
        let alice = tile("alice")
        XCTAssertTrue(alice.waitForExistence(timeout: 10))
        let flip = app.buttons["Switch camera"].firstMatch
        XCTAssertTrue(flip.waitForExistence(timeout: 2))
        
        flip.doubleTap()
        
        // Both halves matter and only the second one has ever been wrong: the chrome is layered over
        // the gesture surface rather than inside it, so a tap that lands on the button is the
        // button's alone. Full screen shows the picture and nothing else, so the other person's tile
        // going away is what tells you the tile took the taps.
        XCTAssertTrue(flip.exists, "the button is still there to be tapped")
        XCTAssertTrue(tile("bob").exists, "still the one-to-one arrangement, not full screen")
    }
    
    // MARK: - Screen share
    
    func testFullScreenOnASharerKeepsTheirScreen() {
        launch("screenShare")
        let frank = tile("frank")
        XCTAssertTrue(frank.waitForExistence(timeout: 10))
        
        frank.doubleTap()
        frank.tap()
        
        XCTAssertTrue(exitButtonAppears())
        // The chrome names what you are looking at, and a share says so rather than naming them:
        // the stream kind followed the spotlight alone until full screen taught it to follow size.
        XCTAssertTrue(app.staticTexts["(Screen share)"].waitForExistence(timeout: 2))
    }
    
    // MARK: - Helpers
    
    private func exitButtonAppears() -> Bool {
        exitButton.waitForExistence(timeout: 2)
    }
    
    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }
}
