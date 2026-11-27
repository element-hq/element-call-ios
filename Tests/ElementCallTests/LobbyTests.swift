//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// `@testable` for the controller's scripted room and join, its camera switch and the phone seam.
import Combine
@testable import ElementCallHost
import ElementCallKit
import Foundation
import Testing
import UIKit

/// Spec 045 over the real controller: the lobby's room is a ``MatrixRTCScriptedRoom`` opened through
/// the controller's seam, the join a scripted one, the clock manual, the permissions and the phone
/// fakes. Everything in between is the shipping path.
@Suite("Call lobby")
@MainActor
struct LobbyTests {
    private let group = ElementCallFakeRoom(roomID: "!room:example.org", isDirect: false)
    
    // MARK: - When the lobby shows (R1–R3, R5, R40, C1)
    
    @Test("Starting and joining a group call open the lobby (R1, R2)")
    func groupCallsOpenTheLobby() {
        for isStarting in [true, false] {
            let fixture = LobbyFixture()
            fixture.controller.startCall(.init(intent: .video, isStartingCall: isStarting), room: group)
            #expect(fixture.controller.connection == .lobby)
            #expect(fixture.controller.lobbyPhase == .loading)
        }
    }
    
    @Test("A direct chat and a skipped lobby go straight in (R3, R5)")
    func directAndSkippedGoStraightIn() {
        let direct = LobbyFixture()
        direct.controller.startCall(.init(intent: .video, isStartingCall: true), room: ElementCallFakeRoom(isDirect: true))
        #expect(direct.controller.connection == .joining)
        #expect(direct.rooms.isEmpty)
        
        let skipped = LobbyFixture()
        skipped.controller.startCall(.init(intent: .video, isStartingCall: false, skipsLobby: true), room: group)
        #expect(skipped.controller.connection == .joining)
        #expect(skipped.rooms.isEmpty)
    }
    
    /// R40: the DM flag as it is at the start, with nothing waiting for a later answer.
    @Test("The decision is the room's DM flag at the start (R40)")
    func theDecisionIsTheFlagAtTheStart() {
        let room = ChangingRoom(isDirect: false)
        let fixture = LobbyFixture()
        fixture.controller.startCall(.init(intent: nil, isStartingCall: false), room: room)
        room.isDirect = true
        #expect(fixture.controller.connection == .lobby)
    }
    
    // MARK: - Nothing reaches the room (R6, R33, R45–R47, C2)
    
    @Test("Nothing reaches the room, the system or the window while the lobby is open (R6, R33, R46, R47)")
    func nothingReachesTheRoom() async throws {
        let fixture = LobbyFixture(memberCount: 2)
        fixture.startLobby()
        try await fixture.waitUntilLoaded()
        try await waitUntil { fixture.permissions.requests.isEmpty && fixture.controller.localCamera?.isCapturing == true }
        
        fixture.controller.setMicrophoneMuted(true)
        fixture.controller.setCameraEnabled(false)
        try await waitUntil { fixture.controller.localCamera?.isCapturing == false }
        fixture.controller.setCameraEnabled(true)
        try await waitUntil { fixture.controller.localCamera?.isCapturing == true }
        fixture.controller.switchCamera()
        fixture.controller.setMembershipFormat(.msc)
        try await fixture.waitUntilLoaded()
        fixture.controller.requestMinimize()
        
        #expect(fixture.system.requests.isEmpty)
        #expect(fixture.controller.rtcCall == nil)
        #expect(fixture.controller.call == nil)
        #expect(!fixture.controller.pictureInPicture.isBound)
        #expect(fixture.controller.isMaximized)
        #expect(fixture.recorder.actions.isEmpty)
        #expect(fixture.analytics.events.isEmpty)
        #expect(fixture.controller.connection == .lobby)
    }
    
    // MARK: - Loading (R59, R60, C7, C22)
    
    @Test("The lobby loads until the room, the intent and the first count have all answered (R59)")
    func loadingWaitsForAllThree() async throws {
        let fixture = LobbyFixture(memberCount: nil)
        let opening = fixture.holdOpen()
        fixture.startLobby()
        
        try await Task.sleep(for: .milliseconds(20))
        #expect(fixture.controller.lobbyPhase == .loading)
        #expect(fixture.controller.lobbyJoinLabel == nil)
        let intent = fixture.holdNextIntent()
        opening.release()
        
        try await waitUntil { fixture.rooms.count == 1 }
        try await Task.sleep(for: .milliseconds(20))
        #expect(fixture.controller.lobbyPhase == .loading)
        intent.release()
        
        // Settled in the lobby, and not yet the controller's: nothing appears before loading ends.
        try await waitUntil { fixture.controller.lobby?.settledIntent == .video }
        #expect(fixture.controller.settledIntent == nil)
        try await Task.sleep(for: .milliseconds(20))
        // No count yet: still loading, nothing asked, the camera closed, no label.
        #expect(fixture.controller.lobbyPhase == .loading)
        #expect(fixture.controller.lobbyJoinLabel == nil)
        #expect(fixture.permissions.requests.isEmpty)
        #expect(fixture.controller.localCamera?.isCapturing == false)
        #expect(!fixture.controller.isCameraEnabled)
        
        fixture.rooms[0].setMemberCount(2)
        try await fixture.waitUntilLoaded()
        #expect(fixture.controller.lobbyJoinLabel == .join)
        #expect(fixture.controller.lobbyMemberCount == 2)
        try await waitUntil { fixture.controller.localCamera?.isCapturing == true }
    }
    
    @Test("The camera starts from the core's order: the host's intent, else the members', else video (R17, R18)")
    func theIntentIsTheCoresOrder() async throws {
        let cases: [(host: MatrixRTCCallIntent?, members: MatrixRTCCallIntent?, settled: MatrixRTCCallIntent)] = [
            (nil, .audio, .audio),
            (nil, .video, .video),
            (nil, nil, .video),
            (.video, .audio, .video),
            (.audio, .video, .audio)
        ]
        for (host, members, settled) in cases {
            let fixture = LobbyFixture(membersIntent: members)
            fixture.startLobby(intent: host)
            try await fixture.waitUntilLoaded()
            #expect(fixture.rooms[0].intentRequests == [host])
            #expect(fixture.controller.settledIntent == settled)
            #expect(fixture.controller.isCameraEnabled == (settled == .video))
            fixture.controller.hangUp()
        }
    }
    
    @Test("A room that does not open, an intent that fails and a count that ends early are R60's failure")
    func unreadableCallsFail() async throws {
        let openFails = LobbyFixture()
        openFails.openFailure = MatrixRTCError.ffi("no")
        openFails.startLobby()
        try await openFails.waitUntilFailed()
        
        let intentFails = LobbyFixture()
        intentFails.intentFailure = MatrixRTCError.ffi("no")
        intentFails.startLobby()
        try await intentFails.waitUntilFailed()
        
        let countEnds = LobbyFixture(memberCount: nil)
        countEnds.startLobby()
        try await waitUntil { countEnds.controller.lobby?.settledIntent != nil }
        countEnds.rooms[0].finishMemberCounts()
        try await countEnds.waitUntilFailed()
        
        for fixture in [openFails, intentFails, countEnds] {
            // An attempt and its failure (044 R6, C16); nothing claimed, so nothing ended (C7).
            #expect(fixture.analytics.events.first.map(\.isAttempt) == true)
            #expect(fixture.analytics.events.contains { $0.isFailure })
            #expect(fixture.system.requests.isEmpty)
            #expect(fixture.controller.localCamera?.isCapturing != true)
        }
    }
    
    /// C22: one timeout from the lobby opening over all three reads, not one per read.
    @Test("One loading timeout covers the three reads (C22)")
    func oneTimeoutForAllThree() async throws {
        let fixture = LobbyFixture()
        let opening = fixture.holdOpen()
        fixture.startLobby()
        try await Task.sleep(for: .milliseconds(10))
        fixture.clock.advance(by: .seconds(20))
        _ = fixture.holdNextIntent()
        opening.release()
        try await waitUntil { fixture.rooms.count == 1 }
        try await Task.sleep(for: .milliseconds(10))
        #expect(fixture.controller.lobbyPhase == .loading)
        
        fixture.clock.advance(by: .seconds(10))
        try await fixture.waitUntilFailed()
        try await waitUntil { fixture.rooms[0].isShutDown }
    }
    
    @Test("A format failing in MSC offers Room state, as a failed join does (C7, 043 R18)")
    func anMSCFailureOffersRoomState() async throws {
        let fixture = LobbyFixture()
        fixture.preferences.membershipFormat = .msc
        fixture.openFailure = MatrixRTCError.ffi("no")
        fixture.startLobby()
        try await waitUntil {
            if case .failed(.mscJoinFailed) = fixture.controller.connection {
                true
            } else {
                false
            }
        }
    }
    
    @Test("A count that stops after loading keeps its value, and Join stays enabled (R60)")
    func aStalledCountKeepsItsValue() async throws {
        let fixture = LobbyFixture(memberCount: 3)
        fixture.startLobby()
        try await fixture.waitUntilLoaded()
        fixture.rooms[0].finishMemberCounts()
        try await Task.sleep(for: .milliseconds(20))
        #expect(fixture.controller.connection == .lobby)
        #expect(fixture.controller.lobbyMemberCount == 3)
        #expect(fixture.controller.canJoinFromLobby)
    }
    
    // MARK: - The count and the label (R21, R41–R43, R57, C8)
    
    @Test("The label follows the count, and an emptied call reads Join anyway until somebody is back (R21, R42, R57)")
    func theLabelFollowsTheCount() async throws {
        let fixture = LobbyFixture(memberCount: 0)
        fixture.startLobby()
        try await fixture.waitUntilLoaded()
        let room = fixture.rooms[0]
        #expect(fixture.controller.lobbyJoinLabel == .start)
        #expect(!fixture.controller.isCallEndedNoticeShown)
        
        room.setMemberCount(2)
        try await waitUntil { fixture.controller.lobbyJoinLabel == .join }
        room.setMemberCount(0)
        try await waitUntil { fixture.controller.lobbyJoinLabel == .joinAnyway }
        #expect(fixture.controller.isCallEndedNoticeShown)
        room.setMemberCount(1)
        try await waitUntil { fixture.controller.lobbyJoinLabel == .join }
        #expect(!fixture.controller.isCallEndedNoticeShown)
    }
    
    /// R43: drawn as reported, whoever is in it, ourselves included.
    @Test("The count is the core's, as reported (R43)")
    func theCountIsTheCores() async throws {
        let fixture = LobbyFixture(memberCount: 1)
        fixture.startLobby()
        try await fixture.waitUntilLoaded()
        #expect(fixture.controller.lobbyMemberCount == 1)
        #expect(fixture.controller.lobbyJoinLabel == .join)
    }
    
    @Test("A format change reopens the room after shutting the old one, and forgets what it saw (R52, C23)")
    func aFormatChangeReloads() async throws {
        let fixture = LobbyFixture(memberCount: 2)
        fixture.startLobby()
        try await fixture.waitUntilLoaded()
        fixture.rooms[0].setMemberCount(0)
        try await waitUntil { fixture.controller.isCallEndedNoticeShown }
        fixture.controller.setMicrophoneMuted(true)
        fixture.nextMemberCount = 0
        
        fixture.controller.setMembershipFormat(.msc)
        #expect(fixture.controller.lobbyPhase == .loading)
        #expect(fixture.controller.lobbyMemberCount == nil)
        try await waitUntil { fixture.rooms.count == 2 }
        #expect(fixture.shutDownBeforeNextOpen == [true])
        try await fixture.waitUntilLoaded()
        #expect(fixture.openedFormats == [.roomState, .msc])
        #expect(!fixture.controller.hasSeenMembers)
        #expect(!fixture.controller.isCallEndedNoticeShown)
        #expect(fixture.controller.lobbyJoinLabel == .start)
        #expect(fixture.controller.isMicrophoneMuted)
        // Asked once per lobby, not again after the reload (Android's appendix, item 12).
        #expect(fixture.permissions.requests.isEmpty)
    }
    
    // MARK: - Permissions (R26–R30, R44, C11)
    
    @Test("Once loaded the lobby asks for the microphone, then the camera (R26)")
    func theLobbyAsksInOrder() async throws {
        let fixture = LobbyFixture(microphone: .notAsked, camera: .notAsked)
        fixture.startLobby()
        try await fixture.waitUntilLoaded()
        try await waitUntil { fixture.permissions.requests == [.microphone, .camera] }
        try await waitUntil { fixture.controller.localCamera?.isCapturing == true }
    }
    
    @Test("A refused microphone keeps the lobby, asks nothing more, and a tap explains (R26, R27)")
    func aRefusedMicrophoneExplains() async throws {
        let fixture = LobbyFixture(microphone: .notAsked, camera: .notAsked)
        fixture.permissions.answerWhenAsked = false
        fixture.startLobby()
        try await fixture.waitUntilLoaded()
        try await waitUntil { fixture.controller.isMicrophonePermissionRefused }
        #expect(fixture.permissions.requests == [.microphone])
        #expect(!fixture.controller.isCameraEnabled)
        #expect(!fixture.controller.canJoinFromLobby)
        
        fixture.controller.join()
        #expect(fixture.controller.isMicrophoneRefusalNoticePending)
        #expect(fixture.controller.connection == .lobby)
        fixture.controller.isMicrophoneRefusalNoticePending = false
        
        fixture.controller.setMicrophoneMuted(true)
        #expect(fixture.controller.isMicrophoneRefusalNoticePending)
        #expect(!fixture.controller.isMicrophoneMuted)
        #expect(fixture.analytics.events.isEmpty)
    }
    
    @Test("A refused camera is off, its tap explains, and Join still joins (R28)")
    func aRefusedCameraExplains() async throws {
        let fixture = LobbyFixture(camera: .refused)
        fixture.scriptJoin()
        fixture.startLobby()
        try await fixture.waitUntilLoaded()
        #expect(!fixture.controller.isCameraEnabled)
        #expect(fixture.controller.isCameraPermissionRefused)
        
        fixture.controller.setCameraEnabled(true)
        try await waitUntil { fixture.controller.isCameraRefusalNoticePending }
        
        fixture.controller.join()
        #expect(fixture.controller.connection == .joining)
        try await fixture.hangUp()
    }
    
    @Test("A microphone the user turned off still joins (R30)")
    func aMutedMicrophoneJoins() async throws {
        let fixture = LobbyFixture()
        fixture.scriptJoin()
        fixture.startLobby()
        try await fixture.waitUntilLoaded()
        fixture.controller.setMicrophoneMuted(true)
        
        fixture.controller.join()
        #expect(fixture.controller.connection == .joining)
        // The mute the lobby had no system call to tell, told once one exists (R46).
        try await waitUntil { fixture.system.requests.contains(.microphone(enabled: false, roomID: group.roomID)) }
        let start = fixture.system.requests.firstIndex {
            if case .start = $0 {
                true
            } else {
                false
            }
        }
        let mute = fixture.system.requests.firstIndex(of: .microphone(enabled: false, roomID: group.roomID))
        #expect(start.map { start in mute.map { $0 > start } ?? false } == true)
        try await fixture.hangUp()
    }
    
    @Test("Join before the microphone is answered asks for it, then joins (Android's appendix, item 11)")
    func joinBeforeTheAnswerAsks() async throws {
        let fixture = LobbyFixture(microphone: .notAsked)
        fixture.scriptJoin()
        let dialogs = fixture.holdDialogs()
        fixture.startLobby()
        try await fixture.waitUntilLoaded()
        try await waitUntil { fixture.permissions.requests == [.microphone] }
        
        // The dialog the lobby opened is up: a tap meanwhile asks nothing more.
        fixture.controller.join()
        #expect(fixture.permissions.requests == [.microphone])
        dialogs.answer(true)
        try await waitUntil { fixture.controller.isMicrophonePermissionRefused == false && fixture.controller.isAskingInLobby == false }
        fixture.controller.join()
        #expect(fixture.controller.connection == .joining)
        try await fixture.hangUp()
    }
    
    // MARK: - Closing (R20, R37, C14, C16, C29)
    
    @Test("Close ends the lobby with nothing to leave, end or report, and the next lobby starts afresh (R20, R37)")
    func closingLeavesNothing() async throws {
        let fixture = LobbyFixture()
        fixture.startLobby()
        try await fixture.waitUntilLoaded()
        try await waitUntil { fixture.controller.localCamera?.isCapturing == true }
        fixture.controller.setMicrophoneMuted(true)
        
        fixture.controller.hangUp()
        #expect(fixture.controller.connection == .ended(.left))
        #expect(fixture.recorder.endedCount == 1)
        #expect(fixture.controller.localCamera?.isCapturing == false)
        try await waitUntil { fixture.rooms[0].isShutDown }
        #expect(fixture.system.requests.isEmpty)
        #expect(fixture.analytics.events.isEmpty)
        
        fixture.controller.reset()
        fixture.startLobby()
        #expect(fixture.controller.connection == .lobby)
        #expect(!fixture.controller.isMicrophoneMuted)
        try await fixture.waitUntilLoaded()
        #expect(fixture.controller.isCameraEnabled)
    }
    
    /// C29: an open that completes after the lobby has gone is shut at once, so the next lobby for
    /// the room is not refused.
    @Test("A room opened after the lobby closed is shut (C29)")
    func aLateRoomIsShut() async throws {
        let fixture = LobbyFixture()
        let opening = fixture.holdOpen()
        fixture.startLobby()
        try await Task.sleep(for: .milliseconds(10))
        fixture.controller.hangUp()
        opening.release()
        try await waitUntil { fixture.rooms.count == 1 && fixture.rooms[0].isShutDown }
    }
    
    @Test("A second start while the lobby is open is refused (Q9)")
    func aSecondStartIsRefused() {
        let fixture = LobbyFixture()
        fixture.startLobby()
        fixture.controller.startCall(.init(intent: .audio, isStartingCall: true), room: ElementCallFakeRoom(roomID: "!other:example.org"))
        #expect(fixture.controller.connection == .lobby)
        #expect(fixture.controller.room?.roomID == group.roomID)
    }
    
    // MARK: - The camera's gates (R31, R34, R48, C15, C27)
    
    @Test("The camera stops off screen and comes back in the state the user left (R31)")
    func theCameraFollowsTheApp() async throws {
        let fixture = LobbyFixture()
        fixture.startLobby()
        try await fixture.waitUntilLoaded()
        try await waitUntil { fixture.controller.localCamera?.isCapturing == true }
        
        fixture.app.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        try await waitUntil { fixture.controller.localCamera?.isCapturing == false }
        #expect(fixture.controller.isCameraEnabled)
        fixture.app.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        try await waitUntil { fixture.controller.localCamera?.isCapturing == true }
        
        fixture.controller.setCameraEnabled(false)
        try await waitUntil { fixture.controller.localCamera?.isCapturing == false }
        fixture.app.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        fixture.app.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        try await Task.sleep(for: .milliseconds(20))
        #expect(fixture.controller.localCamera?.isCapturing == false)
    }
    
    @Test("Another call on the phone stops the camera until it is over, and the lobby waits (R48)")
    func anotherCallStopsTheCamera() async throws {
        let fixture = LobbyFixture()
        fixture.startLobby()
        try await fixture.waitUntilLoaded()
        try await waitUntil { fixture.controller.localCamera?.isCapturing == true }
        
        fixture.phoneCalls.ring()
        #expect(fixture.controller.localCamera?.isCapturing == false)
        #expect(fixture.controller.connection == .lobby)
        // Opened once on load, not stopped and reopened by the questions that follow it.
        #expect(fixture.controller.localCamera?.startCount == 1)
        let started = fixture.controller.localCamera?.startCount ?? 0
        fixture.phoneCalls.hangUp()
        #expect(fixture.controller.localCamera?.isCapturing == true)
        #expect(fixture.controller.localCamera?.startCount == started + 1)
    }
    
    @Test("A call already on the phone when the lobby opens keeps the camera off (R48)")
    func aCallAlreadyOnThePhone() async throws {
        let fixture = LobbyFixture()
        fixture.phoneCalls.ring()
        fixture.startLobby()
        try await fixture.waitUntilLoaded()
        try await Task.sleep(for: .milliseconds(20))
        #expect(fixture.controller.localCamera?.isCapturing == false)
        fixture.phoneCalls.hangUp()
        #expect(fixture.controller.localCamera?.isCapturing == true)
    }
    
    @Test("The phone is watched only while the lobby is open")
    func thePhoneIsWatchedOnlyInTheLobby() async throws {
        let fixture = LobbyFixture()
        fixture.scriptJoin()
        fixture.startLobby()
        try await fixture.waitUntilLoaded()
        #expect(fixture.phoneCalls.isStarted)
        fixture.controller.join()
        #expect(!fixture.phoneCalls.isStarted)
        try await fixture.hangUp()
    }
    
    // MARK: - Join (R15, R22–R25, C9, C13, C16, C28)
    
    @Test("Join switches to joining at once, reports the attempt at the tap, and keeps the lobby's camera running (R23, R49, C16)")
    func joinKeepsTheCamera() async throws {
        let fixture = LobbyFixture(memberCount: 0)
        fixture.scriptJoin()
        fixture.startLobby()
        try await fixture.waitUntilLoaded()
        try await waitUntil { fixture.controller.localCamera?.isCapturing == true }
        #expect(fixture.analytics.events.isEmpty)
        let camera = fixture.controller.localCamera
        
        fixture.controller.join()
        #expect(fixture.controller.connection == .joining)
        #expect(fixture.controller.joinedLobbyLabel == .start)
        #expect(fixture.analytics.events.first.map(\.isAttempt) == true)
        try await waitUntil { fixture.controller.call != nil }
        #expect(fixture.controller.localCamera === camera)
        #expect(camera?.isCapturing == true)
        #expect(camera?.startCount == 1)
        try await fixture.hangUp()
        #expect(camera?.isCapturing == false)
    }
    
    /// C28: from the tap until the call is joined, our video never reads off.
    @Test("Our camera never reads off through the handover (C28)")
    func theCameraNeverReadsOffThroughTheHandover() async throws {
        let fixture = LobbyFixture(memberCount: 2)
        fixture.scriptJoin()
        fixture.startLobby()
        try await fixture.waitUntilLoaded()
        try await waitUntil { fixture.controller.isCameraEnabled }
        
        var readings: [Bool] = []
        let sampler = Task { @MainActor in
            while !Task.isCancelled {
                readings.append(fixture.controller.isCameraEnabled)
                await Task.yield()
            }
        }
        fixture.controller.join()
        try await waitUntil { fixture.controller.call?.isCameraEnabled == true }
        try await Task.sleep(for: .milliseconds(20))
        sampler.cancel()
        #expect(!readings.contains(false))
        try await fixture.hangUp()
    }
    
    @Test("Join does nothing while loading (C13)")
    func joinWhileLoadingDoesNothing() {
        let fixture = LobbyFixture(memberCount: nil)
        fixture.startLobby()
        fixture.controller.join()
        #expect(fixture.controller.connection == .lobby)
        #expect(fixture.analytics.events.isEmpty)
    }
    
    @Test("A failure after the tap ends on the failure screen, never back in the lobby (R25)")
    func aFailedJoinDoesNotReturn() async throws {
        let fixture = LobbyFixture()
        fixture.controller.scriptedJoin = { throw MatrixRTCError.ffi("no") }
        fixture.startLobby()
        try await fixture.waitUntilLoaded()
        fixture.controller.join()
        try await fixture.waitUntilFailed()
    }
}

// MARK: - The fixture

@MainActor
final class LobbyFixture {
    let system = ElementCallFakeSystem()
    let permissions: ElementCallFakeMediaPermissions
    let analytics = ElementCallFakeAnalytics()
    let preferences = ElementCallFakePreferencesStore()
    let clock = MatrixRTCManualClock()
    let phoneCalls = FakePhoneCalls()
    /// The app's comings and goings, for this fixture alone: tests run in parallel.
    let app = NotificationCenter()
    let controller: ElementCallController
    let recorder: ActionRecorder
    
    /// Every room the lobby opened, in order.
    private(set) var rooms: [MatrixRTCScriptedRoom] = []
    private(set) var openedFormats: [MatrixRTCMembershipFormat] = []
    /// For each open after the first, whether every earlier room was shut first (C23).
    private(set) var shutDownBeforeNextOpen: [Bool] = []
    var openFailure: (any Error)?
    var intentFailure: (any Error)?
    var membersIntent: MatrixRTCCallIntent?
    var nextMemberCount: Int?
    private var openGate: Gate?
    private var intentGate: Gate?
    
    init(microphone: ElementCallMediaPermission = .granted,
         camera: ElementCallMediaPermission = .granted,
         membersIntent: MatrixRTCCallIntent? = nil,
         memberCount: Int? = 0) {
        permissions = ElementCallFakeMediaPermissions(microphone: microphone, camera: camera)
        self.membersIntent = membersIntent
        nextMemberCount = memberCount
        controller = ElementCallController(backend: ElementCallFakeMatrixBackend(),
                                           system: system,
                                           options: ElementCallOptions(),
                                           style: .stock,
                                           logger: nil,
                                           preferences: preferences,
                                           permissions: permissions,
                                           analytics: analytics)
        controller.clock = clock
        controller.isAudioEnabled = false
        controller.capturesCamera = false
        controller.phoneCallsMonitor = phoneCalls
        controller.appNotifications = app
        recorder = ActionRecorder(controller)
        controller.scriptedRoom = { [weak self] format in
            guard let self else { throw CancellationError() }
            return try await open(format)
        }
    }
    
    private func open(_ format: MatrixRTCMembershipFormat) async throws -> MatrixRTCScriptedRoom {
        if !rooms.isEmpty {
            shutDownBeforeNextOpen.append(rooms.allSatisfy(\.isShutDown))
        }
        if let openGate {
            await openGate.wait()
        }
        if let openFailure {
            throw openFailure
        }
        let room = MatrixRTCScriptedRoom(roomID: "!room:example.org", membersIntent: membersIntent, memberCount: nextMemberCount)
        room.intentFailure = intentFailure
        if let intentGate {
            room.beforeIntent = { await intentGate.wait() }
        }
        rooms.append(room)
        openedFormats.append(format)
        return room
    }
    
    func startLobby(intent: MatrixRTCCallIntent? = .video) {
        controller.startCall(.init(intent: intent, isStartingCall: true), room: ElementCallFakeRoom(roomID: "!room:example.org"))
    }
    
    /// The next open waits until released.
    func holdOpen() -> Gate {
        let gate = Gate()
        openGate = gate
        return gate
    }
    
    /// The next room's intent waits until released.
    func holdNextIntent() -> Gate {
        let gate = Gate()
        intentGate = gate
        return gate
    }
    
    /// Every dialog stays open until answered, in the order asked.
    func holdDialogs() -> Dialogs {
        let dialogs = Dialogs()
        permissions.answers = { _ in await dialogs.next() }
        return dialogs
    }
    
    func scriptJoin() {
        let scripted = MatrixRTCScriptedCall(roomID: "!room:example.org", status: .connected(since: .now, isDegraded: false))
        let player = MatrixRTCScenarioPlayer(scenario: MatrixRTCScenario(name: "lobby", frames: []))
        controller.scriptedJoin = { (scripted.call, player.call) }
    }
    
    func waitUntilLoaded() async throws {
        try await waitUntil { self.controller.lobbyPhase == .ready }
    }
    
    func waitUntilFailed() async throws {
        try await waitUntil {
            if case .failed = self.controller.connection {
                true
            } else {
                false
            }
        }
    }
    
    func hangUp() async throws {
        controller.hangUp()
        try await waitUntil {
            switch self.controller.connection {
            case .ended, .failed, .idle: true
            default: false
            }
        }
    }
}

/// Released by hand, once.
@MainActor
final class Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    
    func release() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// Dialogs held open, answered one at a time.
@MainActor
final class Dialogs {
    private var pending: [CheckedContinuation<Bool, Never>] = []
    private var early: [Bool] = []
    
    func next() async -> Bool {
        if !early.isEmpty {
            return early.removeFirst()
        }
        return await withCheckedContinuation { pending.append($0) }
    }
    
    func answer(_ granted: Bool) {
        if pending.isEmpty {
            early.append(granted)
        } else {
            pending.removeFirst().resume(returning: granted)
        }
    }
}

@MainActor
final class FakePhoneCalls: ElementCallPhoneCallsMonitorProtocol {
    private(set) var isAnotherCallActive = false
    private var onChange: ((Bool) -> Void)?
    var isStarted: Bool {
        onChange != nil
    }
    
    func start(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }
    
    func stop() {
        onChange = nil
    }
    
    func ring() {
        isAnotherCallActive = true
        onChange?(true)
    }
    
    func hangUp() {
        isAnotherCallActive = false
        onChange?(false)
    }
}

@MainActor
final class ActionRecorder {
    private(set) var actions: [ElementCallControllerAction] = []
    private var cancellable: AnyCancellable?
    
    var endedCount: Int {
        actions.filter {
            if case .ended = $0 {
                true
            } else {
                false
            }
        }.count
    }
    
    init(_ controller: ElementCallController) {
        cancellable = controller.actions.sink { [weak self] in self?.actions.append($0) }
    }
}

/// A room whose DM flag changes after the call starts (R40).
@MainActor
private final class ChangingRoom: ElementCallRoomContextProtocol {
    let roomID = "!room:example.org"
    let displayName = "Changing"
    var isDirect: Bool
    let memberProfiles: [String: ElementCallMemberProfile] = [:]
    
    init(isDirect: Bool) {
        self.isDirect = isDirect
    }
    
    var displayNamePublisher: AnyPublisher<String, Never> {
        Just(displayName).eraseToAnyPublisher()
    }
    
    var isDirectPublisher: AnyPublisher<Bool, Never> {
        Just(isDirect).eraseToAnyPublisher()
    }
    
    var memberProfilesPublisher: AnyPublisher<[String: ElementCallMemberProfile], Never> {
        Just(memberProfiles).eraseToAnyPublisher()
    }
}

private extension ElementCallAnalyticsEvent {
    var isAttempt: Bool {
        if case .callJoinAttempted = self {
            true
        } else {
            false
        }
    }
    
    var isFailure: Bool {
        switch self {
        case .callFailure: true
        case .callJoinOutcome(_, _, .failed): true
        default: false
        }
    }
}

private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<1000 where !condition() {
        try await Task.sleep(for: .milliseconds(5))
    }
    try #require(condition())
}
