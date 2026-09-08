//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import ElementCallKit
import Foundation
import Synchronization

// Fakes for every port, shipped in the product rather than the test target on purpose: a host needs
// them for its own previews, and the example harness runs on them.

/// Answers every Matrix call with nothing. Enough for a controller that never joins, and the
/// starting point for a test that scripts specific answers.
public final nonisolated class ElementCallFakeTransport: ElementCallMatrixTransport {
    public let userID: String
    public let deviceID: String
    public let transports: [MatrixRtcTransport]
    
    public init(userID: String = "@alice:example.org",
                deviceID: String = "FAKEDEVICE",
                transports: [MatrixRtcTransport] = [.liveKit(serviceURL: URL(string: "https://sfu.example.org")!)]) {
        self.userID = userID
        self.deviceID = deviceID
        self.transports = transports
    }
    
    public func rtcTransports(roomID: String) async throws -> [MatrixRtcTransport] {
        transports
    }
    
    public func sendStateEvent(roomID: String, eventType: String, stateKey: String, contentJSON: String) async throws -> String {
        "$event"
    }
    
    public func sendStickyEvent(roomID: String, eventType: String, contentJSON: String, durationMs: UInt64) async throws -> String {
        ""
    }
    
    public func sendDelayedEvent(roomID: String, eventType: String, contentJSON: String, delayMs: UInt64) async throws -> String {
        "delay"
    }
    
    public func sendDelayedStateEvent(roomID: String, eventType: String, stateKey: String, contentJSON: String, delayMs: UInt64) async throws -> String {
        "delay"
    }
    
    public func updateDelayedEvent(roomID: String, delayID: String, action: MatrixRtcDelayedEventAction) async throws { }
    
    public func sendToDeviceMessage(eventType: String, messages: [String: [String: String]]) async throws -> [String: [String]] {
        [:]
    }
    
    public func sendRoomEvent(roomID: String, eventType: String, contentJSON: String) async throws -> String {
        "$event"
    }
    
    public func redactEvent(roomID: String, eventID: String, reason: String?) async throws { }
    
    public func requestOpenIDToken() async throws -> MatrixRtcOpenIDToken {
        .init(accessToken: "", tokenType: "Bearer", matrixServerName: "example.org", expiresIn: 3600)
    }
    
    public func toDeviceMessages(eventTypes: [String]) -> AsyncStream<MatrixRtcToDeviceMessage> {
        AsyncStream { $0.finish() }
    }
    
    public func roomStateEvents(roomID: String, eventType: String) -> AsyncStream<[MatrixRtcRoomStateEvent]> {
        AsyncStream { $0.finish() }
    }
    
    public func joinedMemberIDs(roomID: String) -> AsyncStream<[String]> {
        AsyncStream { $0.finish() }
    }
    
    public func isRoomEncrypted(roomID: String) async -> Bool {
        true
    }
}

/// Records what the call asked the system to do, and lets a test push events back.
@MainActor
public final class ElementCallFakeSystem: ElementCallSystemProviding {
    public enum Request: Sendable, Equatable {
        case start(roomID: String, displayName: String, isVideo: Bool)
        case connected(roomID: String)
        case end(roomID: String)
        case microphone(enabled: Bool, roomID: String)
    }
    
    public private(set) var requests: [Request] = []
    private let subject = PassthroughSubject<ElementCallSystemEvent, Never>()
    
    public init() { }
    
    public var events: AnyPublisher<ElementCallSystemEvent, Never> {
        subject.eraseToAnyPublisher()
    }
    
    public func send(_ event: ElementCallSystemEvent) {
        subject.send(event)
    }
    
    public func startCall(roomID: String, displayName: String, isVideo: Bool) async {
        requests.append(.start(roomID: roomID, displayName: displayName, isVideo: isVideo))
    }
    
    public func reportConnected(roomID: String) {
        requests.append(.connected(roomID: roomID))
    }
    
    public func endCall(roomID: String) {
        requests.append(.end(roomID: roomID))
    }
    
    public func setMicrophoneEnabled(_ enabled: Bool, roomID: String) {
        requests.append(.microphone(enabled: enabled, roomID: roomID))
    }
}

/// A fixed room, with publishers that never emit because nothing about it changes.
@MainActor
public final class ElementCallFakeRoom: ElementCallRoomContext {
    public let roomID: String
    public let displayName: String
    public let isDirect: Bool
    public let memberProfiles: [String: ElementCallMemberProfile]
    
    public init(roomID: String = "!room:example.org",
                displayName: String = "Product | Lobby",
                isDirect: Bool = false,
                memberProfiles: [String: ElementCallMemberProfile] = [:]) {
        self.roomID = roomID
        self.displayName = displayName
        self.isDirect = isDirect
        self.memberProfiles = memberProfiles
    }
    
    public var displayNamePublisher: AnyPublisher<String, Never> {
        Just(displayName).eraseToAnyPublisher()
    }
    
    public var isDirectPublisher: AnyPublisher<Bool, Never> {
        Just(isDirect).eraseToAnyPublisher()
    }
    
    public var memberProfilesPublisher: AnyPublisher<[String: ElementCallMemberProfile], Never> {
        Just(memberProfiles).eraseToAnyPublisher()
    }
}

/// Keeps every line, so a test can assert on what was logged.
public final nonisolated class ElementCallFakeLogger: ElementCallLogging {
    private let recorded = Mutex<[(level: ElementCallLogLevel, message: String)]>([])
    
    public init() { }
    
    public var messages: [String] {
        recorded.withLock { $0.map(\.message) }
    }
    
    public func log(_ level: ElementCallLogLevel, _ message: String) {
        recorded.withLock { $0.append((level, message)) }
    }
}

public extension ElementCallController {
    /// A controller with faked dependencies, for previews and snapshot tests. Never joins anything.
    static func fake(connection: ElementCallConnection,
                     room: any ElementCallRoomContext = ElementCallFakeRoom(),
                     isAudioCall: Bool = false,
                     style: ElementCallStyle = .stock) -> ElementCallController {
        let transport = ElementCallFakeTransport()
        let controller = ElementCallController(rtcService: MatrixRtcService(transport: transport),
                                               transport: transport,
                                               system: ElementCallFakeSystem(),
                                               options: ElementCallDefaultOptions(areTileStatsAvailable: true),
                                               style: style,
                                               logger: nil)
        controller.setPreviewState(callData: .init(isAudioCall: isAudioCall, isStartingCall: true),
                                   room: room,
                                   connection: connection)
        return controller
    }
}
