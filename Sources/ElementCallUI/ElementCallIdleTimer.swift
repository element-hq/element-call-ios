//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

/// Keeps the screen awake while any call screen is up.
///
/// Tracked per screen rather than set by each one: a host with a controller per account can put up
/// one account's call screen before another's has gone, and the old screen's `onDisappear` then let
/// the device sleep under the new call. A set, so a screen appearing twice still counts once.
final class ElementCallIdleTimer {
    static let shared = ElementCallIdleTimer { UIApplication.shared.isIdleTimerDisabled = $0 }
    
    private let setIdleTimerDisabled: (Bool) -> Void
    private var screens: Set<UUID> = []
    
    init(setIdleTimerDisabled: @escaping (Bool) -> Void) {
        self.setIdleTimerDisabled = setIdleTimerDisabled
    }
    
    func screenAppeared(_ screen: UUID) {
        screens.insert(screen)
        setIdleTimerDisabled(true)
    }
    
    func screenDisappeared(_ screen: UUID) {
        guard screens.remove(screen) != nil, screens.isEmpty else { return }
        setIdleTimerDisabled(false)
    }
}
