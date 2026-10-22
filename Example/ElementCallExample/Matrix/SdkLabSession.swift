//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import ElementCall
import Foundation
import MatrixRustSDK

/// A logged-in Rust SDK session for the lab (`element-call-feature-hq/harness/lab.md`): a password
/// login, the sync running, and the one room the call is in. The only place the example app makes a
/// `Client`; the reference backend over it is `SdkMatrixBackend`, unchanged.
///
/// A fresh device every time: the lab's accounts are throwaway, and restoring a session the SDK
/// stored would need the session kept across launches, which the lab has no use for.
final nonisolated class SdkLabSession: Sendable {
    enum Error: Swift.Error, LocalizedError {
        case roomNotJoined(String)
        case noSession
        
        var errorDescription: String? {
            switch self {
            case .roomNotJoined(let roomID): "the account is not in \(roomID), or the sync has not delivered it"
            case .noSession: "the client has no user or device"
            }
        }
    }
    
    let client: Client
    let backend: SdkMatrixBackend
    let room: Room
    /// Held so the sync keeps running for as long as the session lives.
    private let syncService: SyncService
    
    private init(client: Client, backend: SdkMatrixBackend, room: Room, syncService: SyncService) {
        self.client = client
        self.backend = backend
        self.room = room
        self.syncService = syncService
    }
    
    static func login(homeserver: String,
                      username: String,
                      password: String,
                      roomID: String,
                      logger: (any ElementCallLoggingProtocol)?) async throws -> SdkLabSession {
        // One directory per login, wiped on the next: a store with an old session in it would
        // refuse a second login, and nothing here outlives the call.
        let root = URL.applicationSupportDirectory.appending(path: "lab")
        try? FileManager.default.removeItem(at: root)
        let base = root.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        
        logger?.log(.info, "lab: logging in as \(username) on \(homeserver)")
        let client = try await ClientBuilder()
            .serverNameOrHomeserverUrl(serverNameOrUrl: homeserver)
            .sessionPaths(dataPath: base.appending(path: "data").path(percentEncoded: false),
                          cachePath: base.appending(path: "cache").path(percentEncoded: false))
            .slidingSyncVersionBuilder(versionBuilder: .native)
            .build()
        try await client.login(username: username, password: password, initialDeviceName: "Element Call lab", deviceId: nil)
        
        let syncService = try await client.syncService().finish()
        await syncService.start()
        
        // The room arrives with the first sync; the seed script has every account in it already.
        var room: Room?
        for _ in 0..<60 {
            if let found = try? client.getRoom(roomId: roomID) {
                room = found
                break
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        guard let room else { throw Error.roomNotJoined(roomID) }
        guard let backend = SdkMatrixBackend(client: client, logger: logger) else { throw Error.noSession }
        logger?.log(.info, "lab: logged in as \(backend.ownUserId()) / \(backend.ownDeviceId()), room \(roomID) synced")
        return SdkLabSession(client: client, backend: backend, room: room, syncService: syncService)
    }
}

/// The call package's room port over an SDK `Room`, for the lab: name, directness and members read
/// once on load. The lab's room does not change mid-call, so the publishers only carry the load.
final class SdkLabRoomContext: ElementCallRoomContextProtocol {
    let roomID: String
    private let room: Room
    private let name: CurrentValueSubject<String, Never>
    private let direct = CurrentValueSubject<Bool, Never>(false)
    private let profiles = CurrentValueSubject<[String: ElementCallMemberProfile], Never>([:])
    
    init(room: Room) {
        self.room = room
        roomID = room.id()
        name = CurrentValueSubject(room.rawName() ?? room.id())
    }
    
    /// Reads what the port serves from the SDK. Called once, after the sync has the room.
    func load() async {
        if let displayName = room.displayName() {
            name.send(displayName)
        }
        await direct.send(room.isDirect())
        guard let iterator = try? await room.members() else { return }
        var members = [String: ElementCallMemberProfile]()
        while let chunk = iterator.nextChunk(chunkSize: 100), !chunk.isEmpty {
            for member in chunk {
                members[member.userId] = ElementCallMemberProfile(userID: member.userId,
                                                                  displayName: member.displayName,
                                                                  avatarURL: member.avatarUrl.flatMap(URL.init(string:)))
            }
        }
        profiles.send(members)
    }
    
    var displayName: String {
        name.value
    }
    
    var displayNamePublisher: AnyPublisher<String, Never> {
        name.removeDuplicates().eraseToAnyPublisher()
    }
    
    var isDirect: Bool {
        direct.value
    }
    
    var isDirectPublisher: AnyPublisher<Bool, Never> {
        direct.removeDuplicates().eraseToAnyPublisher()
    }
    
    var memberProfiles: [String: ElementCallMemberProfile] {
        profiles.value
    }
    
    var memberProfilesPublisher: AnyPublisher<[String: ElementCallMemberProfile], Never> {
        profiles.eraseToAnyPublisher()
    }
}
