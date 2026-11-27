//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import CallKit
import Foundation

/// Whether another call holds the phone, for the lobby's camera (045 R48). A seam so a test can ring
/// the phone; ``ElementCallSystemPhoneCallsMonitor`` everywhere else.
@MainActor
protocol ElementCallPhoneCallsMonitorProtocol: AnyObject {
    var isAnotherCallActive: Bool { get }
    /// `onChange` is called on the main actor with each change, until ``stop()``.
    func start(onChange: @escaping (Bool) -> Void)
    func stop()
}

/// The system's own list of calls, cellular and from every app that reports its calls to CallKit.
///
/// The lobby holds no audio session, so the interruption a call would deliver to one never comes:
/// this is the signal instead. Any call that has not ended counts, ringing included, and whichever
/// way it is going: before Join the lobby has reported no call of its own (R46), so every call here
/// is somebody else's. Watched only while the lobby is open, since from Join on our own call is in
/// the list too.
final class ElementCallSystemPhoneCallsMonitor: NSObject, ElementCallPhoneCallsMonitorProtocol, CXCallObserverDelegate {
    private var observer: CXCallObserver?
    private var onChange: ((Bool) -> Void)?
    private let log: (String) -> Void
    private(set) var isAnotherCallActive = false
    
    init(log: @escaping (String) -> Void) {
        self.log = log
    }
    
    func start(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        let observer = CXCallObserver()
        observer.setDelegate(self, queue: .main)
        self.observer = observer
        isAnotherCallActive = Self.hasActiveCall(observer)
        if isAnotherCallActive {
            log("another call already holds the phone")
        }
    }
    
    func stop() {
        observer?.setDelegate(nil, queue: nil)
        observer = nil
        onChange = nil
    }
    
    private static func hasActiveCall(_ observer: CXCallObserver) -> Bool {
        observer.calls.contains { !$0.hasEnded }
    }
    
    nonisolated func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        // Each change says whether this call is outgoing, connected, on hold or ended; logged as it
        // comes, since what a ring looks like here is a fact about each phone and each app.
        let description = "call \(call.isOutgoing ? "outgoing" : "incoming"), connected \(call.hasConnected), on hold \(call.isOnHold), ended \(call.hasEnded)"
        MainActor.assumeIsolated {
            guard let observer else { return }
            log("phone \(description)")
            let isActive = Self.hasActiveCall(observer)
            guard isActive != isAnotherCallActive else { return }
            isAnotherCallActive = isActive
            onChange?(isActive)
        }
    }
}
