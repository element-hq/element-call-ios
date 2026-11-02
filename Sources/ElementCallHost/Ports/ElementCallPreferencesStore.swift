//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallKit
import Foundation

/// What the call does with the reactions it receives, as the user chose it (037 R13).
public nonisolated enum ElementCallReactionsPreference: String, Sendable, CaseIterable {
    /// Nothing shown, nothing played.
    case off
    /// Bubbles, no sound.
    case withoutSound
    /// Bubbles and sounds: Element Call web's default too.
    case withSound
    
    var mode: MatrixRTCReactionsMode {
        switch self {
        case .off: .off
        case .withoutSound: .withoutSound
        case .withSound: .withSound
        }
    }
}

/// Where the user's in-call preferences are kept, which the call reads when it starts and writes
/// when the user changes one.
///
/// A port rather than an ``ElementCallOptions`` member: options are the host's, stated once, while
/// these are the user's, changed mid-call and expected back next week (037 R14, R15). A host that
/// supplies nothing gets ``ElementCallUserDefaultsPreferencesStore``; one that wants them in its own
/// settings implements this.
public protocol ElementCallPreferencesStoreProtocol: AnyObject {
    var reactions: ElementCallReactionsPreference { get set }
}

/// The preferences in `UserDefaults`: kept on this device, surviving a restart, shared with nothing
/// (037 R14).
public final class ElementCallUserDefaultsPreferencesStore: ElementCallPreferencesStoreProtocol {
    static let reactionsKey = "io.element.call.preferences.reactions"
    
    private let defaults: UserDefaults
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    public var reactions: ElementCallReactionsPreference {
        get {
            defaults.string(forKey: Self.reactionsKey).flatMap(ElementCallReactionsPreference.init(rawValue:)) ?? .withSound
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.reactionsKey)
        }
    }
}
