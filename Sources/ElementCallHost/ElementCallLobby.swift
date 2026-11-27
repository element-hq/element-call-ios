//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import ElementCallKit
import Foundation
import Observation
import UIKit

/// Whether the lobby has read the call yet (045 R59).
public nonisolated enum ElementCallLobbyPhase: Equatable, Sendable {
    /// The room is being opened, the intent settled or the first count awaited. Only settings and
    /// back work; nothing is asked and the camera is not opened.
    case loading
    /// All three have answered: the label, the count and the camera state appear together.
    case ready
}

/// What the lobby's button reads, which is also what the join does with the room: Start notifies
/// it, the other two do not (045 R21, R57). One type for the button and the join, so the two cannot
/// disagree about which one the user tapped.
public nonisolated enum ElementCallLobbyJoinLabel: Equatable, Sendable {
    /// Nobody is in the call.
    case start
    /// Somebody is in the call.
    case join
    /// The call emptied after the lobby had shown somebody in it (R57).
    case joinAnyway
    
    /// Whether joining from this label notifies the room (R21, R57).
    public var notifies: Bool {
        self == .start
    }
}

/// The lobby's reading of the call, from opening the room until the user joins or leaves: the
/// loading, the count and the label that follow the call, and the two things that pause the
/// preview, the app leaving the screen and another call on the phone.
///
/// A phase of the controller rather than a screen of its own (045 C3), and an object of its own only
/// because the controller is long enough. What the user chose — microphone, camera, facing — stays
/// with the controller, which carries it into the join.
@MainActor
@Observable
final class ElementCallLobby {
    /// One timeout over the three reads, from the lobby opening: as long as the room's own seeding
    /// timeout, so a stalled seed hits both at once, harmlessly (045 C22). Never one per read, which
    /// lets a slow seed, a slow intent and a slow first count add up to a minute and a half.
    static let loadingTimeout: Duration = .seconds(30)
    
    private(set) var phase: ElementCallLobbyPhase = .loading
    /// The core's count for the call, nil until its first answer (045 R43).
    private(set) var memberCount: Int?
    /// Set the first time the count is above zero; cleared only by a format change (R57, C23).
    private(set) var hasSeenMembers = false
    /// The call emptied after the lobby had shown somebody in it (R57).
    private(set) var isCallEndedNoticeShown = false
    /// The intent R17 settled, by the core's order; nil while loading.
    private(set) var settledIntent: MatrixRTCCallIntent?
    /// The app is on screen. The camera stops when it is not (R31).
    private(set) var isAppVisible = true
    /// Another call holds the phone, ringing or answered (R48).
    private(set) var isAnotherCallActive = false
    /// The format the lobby's room was opened in, for the join to reuse it and for what a failure
    /// says (043 R18).
    private(set) var format: MatrixRTCMembershipFormat
    
    /// Nil while loading: no label is guessed and corrected a moment later (R59).
    var joinLabel: ElementCallLobbyJoinLabel? {
        guard phase == .ready, let memberCount else { return nil }
        if isCallEndedNoticeShown {
            return .joinAnyway
        }
        return memberCount > 0 ? .join : .start
    }
    
    /// Whether anything stops the camera besides the user's choice and the permission: loading, the
    /// app off screen, another call on the phone.
    var isCameraPaused: Bool {
        phase == .loading || !isAppVisible || isAnotherCallActive
    }
    
    /// What the lobby was opened for.
    let requestedIntent: MatrixRTCCallIntent?
    let roomID: String
    
    /// Called once per load, when it ends: `isFirst` is false after a format change (C23).
    @ObservationIgnored var onLoaded: ((_ isFirst: Bool) -> Void)?
    /// The call could not be read, or the timeout came first (R60). Called once, then nothing more.
    @ObservationIgnored var onFailure: ((String) -> Void)?
    /// Whatever pauses or resumes the camera changed.
    @ObservationIgnored var onCameraGateChange: (() -> Void)?
    /// The app came back: a permission may have changed in Settings (R29).
    @ObservationIgnored var onReturnToForeground: (() -> Void)?
    
    @ObservationIgnored private let openRoom: (MatrixRTCMembershipFormat) async throws -> any MatrixRTCRoomProtocol
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let phoneCalls: any ElementCallPhoneCallsMonitorProtocol
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private let log: (ElementCallLogLevel, String) -> Void
    
    /// The room, once open and wanted.
    @ObservationIgnored private var room: (any MatrixRTCRoomProtocol)?
    /// The open in flight and not yet taken by a load, run to completion whatever happens to the
    /// lobby meanwhile (C29): a reopen waits for it and the end shuts what it opens, so the core
    /// never holds a room nobody owns, which would refuse the next lobby (C23, `RoomAlreadyOpen`).
    @ObservationIgnored private var opening: Task<Result<any MatrixRTCRoomProtocol, any Error>, Never>?
    /// Bumped by every reload and by the end, so a read that answers for an earlier one is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var hasLoadedOnce = false
    @ObservationIgnored private var isOver = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var countTask: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    
    init(requestedIntent: MatrixRTCCallIntent?,
         roomID: String,
         format: MatrixRTCMembershipFormat,
         clock: any Clock<Duration>,
         phoneCalls: any ElementCallPhoneCallsMonitorProtocol,
         notificationCenter: NotificationCenter = .default,
         log: @escaping (ElementCallLogLevel, String) -> Void,
         openRoom: @escaping (MatrixRTCMembershipFormat) async throws -> any MatrixRTCRoomProtocol) {
        self.requestedIntent = requestedIntent
        self.roomID = roomID
        self.format = format
        self.clock = clock
        self.phoneCalls = phoneCalls
        self.notificationCenter = notificationCenter
        self.log = log
        self.openRoom = openRoom
    }
    
    /// Starts reading the call and following the app and the phone.
    func start() {
        // `.background`, not `.inactive`: Control Centre and the app switcher keep the app visible.
        // Not left to the capture session's own interruption either: a host with the
        // multitasking-camera entitlement keeps the camera running in the background (R31, C15).
        notificationCenter.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.setAppVisible(false) }
            .store(in: &cancellables)
        notificationCenter.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.setAppVisible(true) }
            .store(in: &cancellables)
        phoneCalls.start { [weak self] isActive in
            self?.setAnotherCallActive(isActive)
        }
        isAnotherCallActive = phoneCalls.isAnotherCallActive
        load()
    }
    
    /// A membership format changed in the lobby's Developer options: the room is reopened in it and
    /// the lobby loads again, with what it saw of the old format forgotten (R52, C23).
    func reload(format: MatrixRTCMembershipFormat) {
        guard !isOver, format != self.format else { return }
        log(.info, "lobby reopening \(roomID) in format \(format)")
        self.format = format
        phase = .loading
        memberCount = nil
        hasSeenMembers = false
        isCallEndedNoticeShown = false
        settledIntent = nil
        onCameraGateChange?()
        load()
    }
    
    /// The user joined: the room goes to the join, still open, along with the format it is in. The
    /// count stops being read here, since the call's own count takes over; nothing pauses the camera
    /// any more (C15).
    func handOver() -> (room: (any MatrixRTCRoomProtocol)?, format: MatrixRTCMembershipFormat) {
        let room = room
        self.room = nil
        end()
        return (room, format)
    }
    
    /// Closed without joining, or failed: the room is shut, and an open still in flight is shut as it
    /// completes (C29).
    func close() {
        let room = room
        self.room = nil
        end()
        if let room {
            Task { await room.shutdown() }
        }
    }
    
    // MARK: - Loading
    
    private func load() {
        generation += 1
        let generation = generation
        timeoutTask?.cancel()
        timeoutTask = clock.schedule(after: Self.loadingTimeout) { [weak self] in
            self?.fail("The call was not read within \(Self.loadingTimeout)", generation: generation)
        }
        countTask?.cancel()
        countTask = nil
        let previousRoom = room
        room = nil
        let previousOpening = opening
        let format = format
        let openRoom = openRoom
        let opening = Task { () -> Result<any MatrixRTCRoomProtocol, any Error> in
            // The old room is shut before the new one is opened: the core refuses a second live
            // room for the same room (C23).
            if let earlier = try? await previousOpening?.value.get() {
                await earlier.shutdown()
            }
            await previousRoom?.shutdown()
            do {
                return try await .success(openRoom(format))
            } catch {
                return .failure(error)
            }
        }
        self.opening = opening
        loadTask = Task { [weak self] in
            await self?.read(opening, generation: generation)
        }
    }
    
    /// The three reads, in order: the room, the intent, the first count.
    private func read(_ opening: Task<Result<any MatrixRTCRoomProtocol, any Error>, Never>, generation: Int) async {
        let opened: any MatrixRTCRoomProtocol
        switch await opening.value {
        case .success(let room):
            opened = room
        case .failure(let error):
            fail("Could not open the room: \(error)", generation: generation)
            return
        }
        guard isCurrent(generation) else {
            // Opened for a lobby that has gone or reloaded meanwhile: nobody wants it (C29).
            await opened.shutdown()
            return
        }
        // Taken: from here the room is shut by whoever ends the lobby, or handed to the join.
        if self.opening == opening {
            self.opening = nil
        }
        room = opened
        
        let intent: MatrixRTCCallIntent
        do {
            intent = try await opened.callIntent(requested: requestedIntent, applicationSlotID: nil)
        } catch {
            fail("Could not read the call's intent: \(error)", generation: generation)
            return
        }
        guard isCurrent(generation) else { return }
        settledIntent = intent
        
        let counts = opened.memberCountUpdates(applicationSlotID: nil)
        countTask = Task { [weak self] in
            for await count in counts {
                guard let self, isCurrent(generation) else { return }
                apply(count: count)
            }
            guard let self, isCurrent(generation) else { return }
            if memberCount == nil {
                fail("The call's members could not be read", generation: generation)
            } else {
                // A stalled count keeps its last value and Join stays enabled (R60).
                log(.warning, "the lobby's count stopped updating at \(memberCount ?? 0)")
            }
        }
    }
    
    private func apply(count: Int) {
        if count != memberCount {
            log(.info, "lobby count \(count)")
        }
        memberCount = count
        if count > 0 {
            hasSeenMembers = true
            isCallEndedNoticeShown = false
        } else if hasSeenMembers {
            isCallEndedNoticeShown = true
        }
        if phase == .loading {
            timeoutTask?.cancel()
            timeoutTask = nil
            phase = .ready
            let isFirst = !hasLoadedOnce
            hasLoadedOnce = true
            log(.info, "lobby loaded: intent \(settledIntent.map { "\($0)" } ?? "none"), \(count) in the call")
            onLoaded?(isFirst)
            onCameraGateChange?()
        }
    }
    
    private func fail(_ message: String, generation: Int) {
        guard isCurrent(generation) else { return }
        end()
        let room = room
        self.room = nil
        if let room {
            Task { await room.shutdown() }
        }
        onFailure?(message)
    }
    
    private func isCurrent(_ generation: Int) -> Bool {
        !isOver && generation == self.generation
    }
    
    // MARK: - The camera's gates
    
    private func setAppVisible(_ isVisible: Bool) {
        guard !isOver, isVisible != isAppVisible else { return }
        log(.info, "lobby \(isVisible ? "back on screen" : "off screen")")
        isAppVisible = isVisible
        onCameraGateChange?()
        if isVisible {
            onReturnToForeground?()
        }
    }
    
    private func setAnotherCallActive(_ isActive: Bool) {
        guard !isOver, isActive != isAnotherCallActive else { return }
        log(.info, isActive ? "another call holds the phone: the lobby's camera stops" : "the other call is over")
        isAnotherCallActive = isActive
        onCameraGateChange?()
    }
    
    private func end() {
        isOver = true
        generation += 1
        timeoutTask?.cancel()
        timeoutTask = nil
        countTask?.cancel()
        countTask = nil
        cancellables.removeAll()
        phoneCalls.stop()
        // An open still in flight, not yet taken by a load, is shut as soon as it completes:
        // nobody will want it (C29).
        if let opening {
            self.opening = nil
            Task {
                if let late = try? await opening.value.get() {
                    await late.shutdown()
                }
            }
        }
    }
}
