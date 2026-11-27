//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallKit
import Foundation
import UIKit

/// The lobby: our camera preview, the microphone and camera toggles and the call's count, before
/// anything about us reaches the room (045). A phase of this controller, not a screen in front of
/// the call, so Join is a state change and the preview is already the call's camera (C3, C4).
///
/// While it is open there is no membership, no media server, no notification, no system call, no
/// microphone, no audio session and no Picture in Picture: each of those is reached only from
/// ``join()``, through the same `runCall` a call without a lobby runs (R6, R22, R45–R47, C2).
public extension ElementCallController {
    /// Nil outside the lobby.
    var lobbyPhase: ElementCallLobbyPhase? {
        lobby?.phase
    }
    
    /// The core's count for the call, drawn as reported; nil until its first answer (045 R43, R59).
    var lobbyMemberCount: Int? {
        lobby?.memberCount
    }
    
    var hasSeenMembers: Bool {
        lobby?.hasSeenMembers ?? false
    }
    
    /// The call emptied after the lobby had shown somebody in it (R57).
    var isCallEndedNoticeShown: Bool {
        lobby?.isCallEndedNoticeShown ?? false
    }
    
    /// What Join reads, from the count only; nil while loading (R21, R57, R59).
    var lobbyJoinLabel: ElementCallLobbyJoinLabel? {
        lobby?.joinLabel
    }
    
    /// Whether a tap on Join joins. A refused microphone does not, though Join looks available: the
    /// tap explains instead (R27, R51).
    var canJoinFromLobby: Bool {
        connection == .lobby && lobby?.phase == .ready && !isMicrophonePermissionRefused
    }
    
    /// Frames carry the interface orientation; reported by the screen, in the lobby too, so the tag
    /// is already right when the camera is handed to the call (045 R34).
    func updateInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        if let call {
            call.updateInterfaceOrientation(orientation)
        } else {
            localCamera?.setInterfaceOrientation(orientation)
        }
    }
    
    /// From the lobby's Start or Join: runs the join a call without a lobby runs, with the lobby's
    /// room, camera and choices (045 R15, R22, C13). Nothing happens unless the lobby has loaded and
    /// the microphone is allowed; a refused microphone says why instead (R27).
    func join() {
        guard connection == .lobby, let lobby, lobby.phase == .ready, let callData, let room else {
            log(.info, "ignoring join outside a loaded lobby")
            return
        }
        switch permissions.permission(for: .microphone) {
        case .refused:
            isMicrophoneRefusalNoticePending = true
            return
        case .notAsked:
            // The lobby asks as it loads, but a tap can beat the answer: ask, then join on a yes,
            // which is what the tap was for. Never while the dialog is already up.
            guard !isAwaitingMicrophone else { return }
            Task {
                isAwaitingMicrophone = true
                let granted = await permissions.request(.microphone)
                isAwaitingMicrophone = false
                refreshPermissions()
                if granted {
                    join()
                }
            }
            return
        case .granted:
            break
        }
        let label = lobby.joinLabel
        let handedOver = lobby.handOver()
        self.lobby = nil
        lobbyRoomForJoin = handedOver.room
        lobbyRoomFormat = handedOver.format
        joinedLobbyLabel = label
        // The attempt is the tap, not the lobby's opening (044 R6, 045 C16).
        reporter.attempted(callKind: .group)
        log(.info, "joining \(room.roomID) from the lobby as \(label.map { "\($0)" } ?? "none")")
        // In the same frame as the tap: the screen shows the call's joining state at once (R23).
        connection = .joining
        followSignalling()
        followInterruptions()
        runTask = Task { await runCall(callData, room: room) }
    }
}

extension ElementCallController {
    /// The camera from the settled intent, unless the user has chosen meanwhile (045 C24).
    func seedCameraFromSettledIntent() {
        guard !isCameraChosenByUser else { return }
        pendingCameraEnabled = settledIntent == .video && permissions.permission(for: .camera) != .refused
    }
    
    /// A direct chat rings, a group call is an invitation rather than a summons. Either only when
    /// *starting* a call; joining one someone else started happens quietly. From a lobby, starting
    /// is the label the user tapped, never the host's `isStartingCall`, which was fixed before the
    /// lobby showed who is in the call (045 R21, R57, C9).
    static func kind(isStartingCall: Bool,
                     lobbyLabel: ElementCallLobbyJoinLabel?,
                     intent: MatrixRTCCallIntent,
                     isDirect: Bool) -> MatrixRTCCallKind {
        let isStarting = lobbyLabel.map(\.notifies) ?? isStartingCall
        let announced: MatrixRTCCallIntent? = isStarting ? intent : nil
        return isDirect ? .direct(ring: announced) : .group(notify: announced)
    }
    
    func openLobby(_ callData: ElementCallData, room: any ElementCallRoomContextProtocol) {
        let format = membershipFormat
        joiningFormat = format
        // Unknown until the lobby has read the call: the camera starts from the settled intent, never
        // from the host's guess corrected a moment later (R59).
        pendingCameraEnabled = false
        hasAskedInLobby = false
        isAskingInLobby = false
        let roomID = room.roomID
        let lobby = ElementCallLobby(requestedIntent: callData.intent,
                                     roomID: roomID,
                                     format: format,
                                     clock: clock,
                                     phoneCalls: phoneCallsMonitor ?? ElementCallSystemPhoneCallsMonitor { [weak self] in self?.log(.info, $0) },
                                     notificationCenter: appNotifications,
                                     log: { [weak self] level, message in self?.log(level, message) },
                                     openRoom: { [weak self] format in
                                         guard let self else { throw CancellationError() }
                                         if let scriptedRoom {
                                             return try await scriptedRoom(format)
                                         }
                                         return try await rtcClient.room(roomID: roomID, format: format)
                                     })
        lobby.onLoaded = { [weak self] _ in self?.lobbyDidLoad() }
        lobby.onFailure = { [weak self] message in self?.failLobby(message) }
        lobby.onCameraGateChange = { [weak self] in self?.updateLobbyCamera() }
        lobby.onReturnToForeground = { [weak self] in
            // A permission granted in Settings since (R29). On iOS that grant relaunches the app, so
            // this is for a process that survives (C12).
            self?.refreshPermissions()
            self?.updateLobbyCamera()
        }
        self.lobby = lobby
        connection = .lobby
        log(.info, "opening the lobby for \(roomID) in format \(format)")
        lobby.start()
    }
    
    /// The label, the count and the camera appear together (R59). After a format change the intent
    /// may have changed too; the camera follows it unless the user has chosen (R52, C23).
    private func lobbyDidLoad() {
        guard let lobby else { return }
        settledIntent = lobby.settledIntent
        joiningFormat = lobby.format
        seedCameraFromSettledIntent()
        // Once per lobby: a format change returns to loading, and would otherwise ask a refused
        // microphone again.
        if !hasAskedInLobby {
            hasAskedInLobby = true
            askInLobby()
        }
        updateLobbyCamera()
    }
    
    /// 042's order, once loaded (R26): the microphone, then the camera only if it starts on and the
    /// microphone was granted (042 C4). The preview waits for the answers, so what the user sees
    /// follows the order of the questions.
    private func askInLobby() {
        isAskingInLobby = true
        Task {
            defer {
                isAskingInLobby = false
                refreshPermissions()
                updateLobbyCamera()
            }
            if permissions.permission(for: .microphone) == .notAsked {
                log(.info, "the lobby asks for the microphone")
                isAwaitingMicrophone = true
                _ = await permissions.request(.microphone)
                isAwaitingMicrophone = false
            }
            guard connection == .lobby else { return }
            guard permissions.permission(for: .microphone) == .granted else {
                // No camera question after a refused microphone: the camera is off and a tap asks.
                pendingCameraEnabled = false
                return
            }
            if pendingCameraEnabled, permissions.permission(for: .camera) == .notAsked {
                log(.info, "the lobby asks for the camera")
                if await !permissions.request(.camera) {
                    pendingCameraEnabled = false
                }
            }
        }
    }
    
    /// Runs the preview exactly when the user's choice is on, the permission granted, the lobby
    /// loaded and its questions answered, the app on screen and no other call on the phone
    /// (R8, R31, R48, C15). Rotation is none of these, so it stops nothing (R34).
    func updateLobbyCamera() {
        guard connection == .lobby, let lobby, let localCamera else { return }
        let shouldRun = pendingCameraEnabled
            && !lobby.isCameraPaused
            && !isAskingInLobby
            && permissions.permission(for: .camera) == .granted
        if shouldRun, !localCamera.isCapturing {
            do {
                try localCamera.start()
            } catch {
                log(.warning, "could not start the lobby's camera: \(error)")
            }
        } else if !shouldRun, localCamera.isCapturing {
            localCamera.stop()
        }
    }
    
    /// Close or back: nothing was joined, claimed or reported, so there is nothing to leave or end,
    /// and nothing of the lobby is kept (R20, R37, C14, C16).
    func closeLobby() {
        log(.info, "closing the lobby")
        lobby?.close()
        lobby = nil
        localCamera?.stop()
        isEnding = true
        connection = .ended(.left)
        actionsSubject.send(.ended)
    }
    
    /// The call could not be read, or not in time: the failure screen, as a join whose room does not
    /// open (R60, C7). It counts as an attempt that failed (044 R6, C16). The format is the lobby's,
    /// so a failure in MSC offers Room state (043 R18).
    private func failLobby(_ message: String) {
        guard connection == .lobby else { return }
        joiningFormat = lobby?.format ?? membershipFormat
        lobby = nil
        localCamera?.stop()
        reporter.attempted(callKind: .group)
        failJoin(.other(message), reporting: .failed(.other, .homeserver, .unknown))
    }
    
    /// Re-read rather than mirrored: a grant or a refusal can happen in Settings at any time.
    func refreshPermissions() {
        let microphoneRefused = permissions.permission(for: .microphone) == .refused
        if microphoneRefused != isMicrophonePermissionRefused {
            isMicrophonePermissionRefused = microphoneRefused
        }
        let cameraRefused = permissions.permission(for: .camera) == .refused
        if cameraRefused != isCameraPermissionRefused {
            isCameraPermissionRefused = cameraRefused
        }
    }
}
