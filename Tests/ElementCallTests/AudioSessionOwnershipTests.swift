//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementCallKit
import Testing

nonisolated struct AudioSessionOwnershipTests {
    /// Thin, and deliberately so: the predicate decides whether a call has any audio at all on the
    /// runtimes with no CallKit, and inverting it is silent — the session simply never activates
    /// and every tile stays mute. The suite runs on the simulator, which is one of those runtimes,
    /// so this pins that branch. The iOS-app-on-Mac branch cannot be reached from here at all,
    /// which is why it is a runtime check rather than something a test could cover.
    @Test
    func theSimulatorOwnsItsOwnAudioSession() {
        #expect(CallAudioSessionConfigurator.isSelfActivating)
    }
}
