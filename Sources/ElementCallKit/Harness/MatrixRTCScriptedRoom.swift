//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// A room read before anything is joined, with nothing behind it: what a lobby reads, played by
/// hand. The harness's lobby fixtures and the controller's tests open lobbies on it, so the lobby
/// itself, its loading, its permissions and its Join are the shipping path (045).
///
/// The intent answers as the core's does — the requested one, else ``membersIntent``, else video —
/// so a fixture says what the members agree on and the order is still exercised.
public final class MatrixRTCScriptedRoom: MatrixRTCRoomProtocol {
    public let roomID: String
    /// What the call's members agree on, or nil when they agree on nothing.
    public var membersIntent: MatrixRTCCallIntent?
    /// Thrown by the next intent read instead of answering.
    public var intentFailure: (any Error)?
    /// Awaited before the intent answers: a test holds it to keep the lobby loading.
    public var beforeIntent: (() async -> Void)?
    /// Every intent asked for, in order, as `requested`.
    public private(set) var intentRequests: [MatrixRTCCallIntent?] = []
    /// The count a new reader is given first; nil until there is one, which keeps a lobby loading.
    public private(set) var memberCount: Int?
    public private(set) var isShutDown = false
    
    private var readers: [UUID: AsyncStream<Int>.Continuation] = [:]
    
    public init(roomID: String, membersIntent: MatrixRTCCallIntent? = nil, memberCount: Int? = 0) {
        self.roomID = roomID
        self.membersIntent = membersIntent
        self.memberCount = memberCount
    }
    
    public func callIntent(requested: MatrixRTCCallIntent?, applicationSlotID: String?) async throws -> MatrixRTCCallIntent {
        intentRequests.append(requested)
        await beforeIntent?()
        if let intentFailure {
            throw intentFailure
        }
        guard !isShutDown else { throw MatrixRTCError.ffi("\(roomID) is shut down") }
        return requested ?? membersIntent ?? .video
    }
    
    public func memberCountUpdates(applicationSlotID: String?) -> AsyncStream<Int> {
        let (updates, continuation) = AsyncStream<Int>.makeStream(bufferingPolicy: .bufferingNewest(1))
        guard !isShutDown else {
            continuation.finish()
            return updates
        }
        let id = UUID()
        readers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.readers[id] = nil }
        }
        if let memberCount {
            continuation.yield(memberCount)
        }
        return updates
    }
    
    /// Every reader is told, as a change in the core's snapshot would tell it.
    public func setMemberCount(_ count: Int) {
        memberCount = count
        readers.values.forEach { $0.yield(count) }
    }
    
    /// Ends every count stream without shutting the room: the core's subscription failing.
    public func finishMemberCounts() {
        readers.values.forEach { $0.finish() }
        readers.removeAll()
    }
    
    public func shutdown() async {
        guard !isShutDown else { return }
        isShutDown = true
        finishMemberCounts()
    }
}
