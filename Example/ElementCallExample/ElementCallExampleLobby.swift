//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCall
import Foundation

/// fixtures.md's Lobby section (045, contract C25): a group call opened on the lobby, in a room named
/// "Lobby" with Bob and Carol, through the real controller. The core is a ``MatrixRTCScriptedRoom``
/// played from here, and Join joins a scripted call, so the lobby itself, its loading, its
/// questions and its move into the call are the shipping path.
struct ElementCallExampleLobby {
    /// The intent the host passes; nil is a plain join (R18).
    var hostIntent: MatrixRTCCallIntent? = .video
    /// What the call's members agree on, for the core's order to fall back on (R17).
    var membersIntent: MatrixRTCCallIntent?
    /// The core's count once the call is read.
    var memberCount = 0
    /// Later counts, from the lobby opening; repeated from the start once played (R42, R57).
    var countChanges: [(at: Duration, count: Int)] = []
    /// How long the call takes to read (R59).
    var readableAfter: Duration = .zero
    /// The room fails to open after this long (R60).
    var failsAfter: Duration?
    /// The permission that answers refused, whatever the device has granted (R27, R28).
    var refused: ElementCallMediaDevice?
    /// The remote roster Join lands in, as a scenario writes it.
    var joinRoster = "CAROLv BOBv"
    /// How long the join takes after the tap, which is when the core reports our tile (R49): a
    /// real one takes seconds, and the preview's move plays out before it lands.
    var joinTakes: Duration = .seconds(2)
    
    static let roomName = "Lobby"
    
    static let empty = Self(joinRoster: "")
    static let inProgress = Self(memberCount: 3, joinRoster: "CAROLv BOBv DAN")
    static let countChanges = Self(countChanges: [(.seconds(5), 2), (.seconds(10), 0)])
    static let join = Self(memberCount: 2)
    static let voice = Self(hostIntent: .audio, memberCount: 2)
    static let noIntentVoiceCall = Self(hostIntent: nil, membersIntent: .audio, memberCount: 2, joinRoster: "CAROL BOB")
    static let microphoneRefused = Self(memberCount: 1, refused: .microphone, joinRoster: "CAROLv")
    static let cameraRefused = Self(memberCount: 2, refused: .camera)
    static let loading = Self(memberCount: 2, readableAfter: .seconds(3))
    static let unreadable = Self(failsAfter: .seconds(2))
    
    /// What Join plays: our camera, then the roster.
    var joinScenario: String {
        ["0s me v", joinRoster.isEmpty ? nil : "0s \(joinRoster)"].compactMap(\.self).joined(separator: "\n")
    }
    
    /// Opens the scripted room as the core would: after the call is read, or failing.
    @MainActor
    func openRoom(roomID: String) async throws -> MatrixRTCScriptedRoom {
        if let failsAfter {
            try await Task.sleep(for: failsAfter)
            throw MatrixRTCError.roomNotReady(roomID: roomID)
        }
        try await Task.sleep(for: readableAfter)
        let room = MatrixRTCScriptedRoom(roomID: roomID, membersIntent: membersIntent, memberCount: memberCount)
        if !countChanges.isEmpty {
            playCounts(on: room)
        }
        return room
    }
    
    /// Until the room is shut, which a closed lobby or a Join's end does.
    @MainActor
    private func playCounts(on room: MatrixRTCScriptedRoom) {
        let changes = countChanges
        Task { [weak room] in
            while let room, !room.isShutDown {
                var elapsed = Duration.zero
                for change in changes {
                    try? await Task.sleep(for: change.at - elapsed)
                    elapsed = change.at
                    guard !room.isShutDown else { return }
                    room.setMemberCount(change.count)
                }
                try? await Task.sleep(for: .seconds(5))
                guard !room.isShutDown else { return }
                room.setMemberCount(memberCount)
            }
        }
    }
}

/// The device's own permissions, but one of them answers refused whatever the device has granted,
/// so a refusal can be looked at without resetting the phone (fixtures.md, `lobby_mic_refused`,
/// `lobby_camera_refused`).
@MainActor
final class ElementCallExampleRefusingPermissions: ElementCallMediaPermissionsProtocol {
    private let system = ElementCallSystemMediaPermissions()
    private let refused: ElementCallMediaDevice?
    
    init(refusing refused: ElementCallMediaDevice?) {
        self.refused = refused
    }
    
    func permission(for device: ElementCallMediaDevice) -> ElementCallMediaPermission {
        device == refused ? .refused : system.permission(for: device)
    }
    
    func request(_ device: ElementCallMediaDevice) async -> Bool {
        device == refused ? false : await system.request(device)
    }
    
    func openSettings() {
        system.openSettings()
    }
}
