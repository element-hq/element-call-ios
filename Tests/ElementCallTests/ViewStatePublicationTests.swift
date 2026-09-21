//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallHost
@testable import ElementCallUI
import Foundation
import Synchronization
import Testing

/// That the call screen stops republishing when nothing it draws has changed.
///
/// The regression is a screen whose overflow `Menu` flickered and swallowed taps: the projection read
/// an audio level the media layer rewrites ten times a second, nothing drew the number, and
/// `@Observable` granularity is per stored property -- so every wake invalidated every view reading
/// `viewState`, which is all of them. Half the fix is that the read is gone, which only the compiler
/// can check. This pins the other half: a wake producing an identical projection publishes nothing.
///
/// It drives the real `observe()` loop over a fake controller. `controller.call` is nil there, so the
/// tile-producing half of `refresh()` is out of reach -- what is in reach is the property that caused
/// the trouble, `viewState` being one coarse observable thing.
@Suite("View state publication")
@MainActor
struct ViewStatePublicationTests {
    /// `withObservationTracking` is single-shot, so this re-arms after each notification. That
    /// undercounts a burst, which is the safe direction: the assertion that matters is a zero.
    private final nonisolated class Counter: Sendable {
        /// Written from `onChange`, which is `@Sendable` and arrives on whichever thread mutated.
        private let count = Mutex(0)
        
        @MainActor
        init(_ context: ElementCallScreenContext) {
            arm(context)
        }
        
        var value: Int {
            count.withLock { $0 }
        }
        
        @MainActor
        private func arm(_ context: ElementCallScreenContext) {
            withObservationTracking {
                _ = context.viewState
            } onChange: { [self] in
                count.withLock { $0 += 1 }
                Task { @MainActor in arm(context) }
            }
        }
    }
    
    /// The loop is a `Task` over a continuation, so a bare `Task.yield()` is not reliably enough.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(50))
    }
    
    @Test
    func aWakeThatChangesNothingPublishesNothing() async throws {
        let controller = ElementCallController.fake(connection: .connected)
        let viewModel = ElementCallScreenViewModel(controller: controller)
        try await settle()
        let counter = Counter(viewModel.context)
        
        // Already nil, and Observation notifies on every set regardless of the value. This is
        // exactly the shape of the wake that used to arrive ten times a second from the audio meter.
        for _ in 0..<10 {
            controller.errorMessage = nil
            try await settle()
        }
        
        #expect(counter.value == 0)
    }
    
    /// The control. Without it the test above would pass just as well on a screen that had stopped
    /// publishing altogether.
    @Test
    func aWakeThatChangesSomethingPublishesOnce() async throws {
        let controller = ElementCallController.fake(connection: .connected)
        let viewModel = ElementCallScreenViewModel(controller: controller)
        try await settle()
        let counter = Counter(viewModel.context)
        
        // Developer mode is on in the fake, so this is not silently refused.
        controller.toggleTileStats()
        try await settle()
        
        #expect(viewModel.context.viewState.isTileStatsVisible)
        #expect(counter.value == 1)
    }
}
