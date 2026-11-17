//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementCallUI
import Foundation
import Testing

/// The screen stays awake while any call screen is up, whichever order screens come and go in.
@Suite("Idle timer")
@MainActor
struct IdleTimerTests {
    @Test("A call screen keeps the screen awake until it goes")
    func oneScreen() {
        let fixture = Fixture()
        let screen = UUID()
        
        fixture.timer.screenAppeared(screen)
        #expect(fixture.isIdleTimerDisabled == true)
        
        fixture.timer.screenDisappeared(screen)
        #expect(fixture.isIdleTimerDisabled == false)
    }
    
    /// A host swapping one account's call screen for another's can show the new one first.
    @Test("The old screen going after the new one appeared keeps the screen awake")
    func newScreenBeforeOldGoes() {
        let fixture = Fixture()
        let old = UUID()
        let new = UUID()
        
        fixture.timer.screenAppeared(old)
        fixture.timer.screenAppeared(new)
        fixture.timer.screenDisappeared(old)
        #expect(fixture.isIdleTimerDisabled == true)
        
        fixture.timer.screenDisappeared(new)
        #expect(fixture.isIdleTimerDisabled == false)
    }
    
    @Test("A screen appearing twice goes in one disappearance, and an unknown one changes nothing")
    func repeatedAndUnknownScreens() {
        let fixture = Fixture()
        let screen = UUID()
        
        fixture.timer.screenAppeared(screen)
        fixture.timer.screenAppeared(screen)
        fixture.timer.screenDisappeared(UUID())
        #expect(fixture.isIdleTimerDisabled == true)
        
        fixture.timer.screenDisappeared(screen)
        #expect(fixture.isIdleTimerDisabled == false)
    }
    
    // MARK: - Helpers
    
    private final class Fixture {
        var isIdleTimerDisabled: Bool?
        private(set) lazy var timer = ElementCallIdleTimer { [unowned self] in isIdleTimerDisabled = $0 }
    }
}
