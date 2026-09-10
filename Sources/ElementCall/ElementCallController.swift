//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVFoundation
import Combine
import ElementCallKit
import Foundation
import Observation
import SwiftUI

public nonisolated enum ElementCallConnection: Equatable, Sendable {
    case idle
    case joining
    case connectingMedia
    case connected
    case ended
    case failed(String)
}

/// What the host has to do about a change in the call, beyond drawing it.
public nonisolated enum ElementCallControllerAction: Sendable {
    /// The user asked to shrink the call. The host decides where it goes.
    case minimizeRequested
    /// The user asked to come back to the full-screen call, from the bar or the system window.
    case restoreRequested
    /// The call is over and its screen should go away.
    case ended
    /// A Picture in Picture window opened, possibly because the app was backgrounded rather than
    /// because anyone asked. Whatever the host put in the minimized slot should come down.
    case pictureInPictureStarted
    /// Minimizing cannot use a system window, so the host needs its own minimized presentation.
    case pictureInPictureUnavailable
}

/// Owns the call above the UI, so the call is a fact about the app rather than about the screen
/// showing it: the full-screen view and a minimized bar are two renderings of one thing.
///
/// One per user session, created with the ``ElementCallStack``. Mutations are funnelled through the
/// main actor so the UI only ever sees whole snapshots.
@Observable
@MainActor
public final class ElementCallController {
    public private(set) var callData: ElementCallData?
    public private(set) var connection: ElementCallConnection = .idle
    public private(set) var connectedAt: Date?
    public private(set) var isLoudspeaker = false
    public private(set) var isMaximized = true
    public private(set) var isTileStatsVisible = false
    
    /// The room the current call is in, for as long as there is one.
    public private(set) var room: (any ElementCallRoomContext)?
    
    /// The last failure worth telling the user about; the screen shows it once and clears it.
    public var errorMessage: String?
    
    public private(set) var session: MatrixRtcSession?
    public private(set) var call: MatrixRtcCall?
    
    /// The system window for a minimized call, audio ones included — an audio call shows the
    /// avatar placeholder. Internal because the host drives it through ``requestMinimize()`` and
    /// ``restore()`` rather than directly.
    let pictureInPicture = ElementCallPictureInPictureController()
    
    public var actions: AnyPublisher<ElementCallControllerAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    /// Anyone in the call has video to show.
    ///
    /// No longer decides whether minimizing uses the window — every call does — but it still
    /// decides whether *backgrounding* the app opens one by itself, unless the host opted audio
    /// calls in through ``ElementCallOptions/isAutomaticPictureInPictureForAudioCallsEnabled``.
    public var hasVideo: Bool {
        call?.hasVideo ?? false
    }
    
    /// The member spotlighted by the layout: a screen share, else the loudest recent speaker.
    public private(set) var spotlightMemberID: String?
    
    public var isInCall: Bool {
        switch connection {
        case .joining, .connectingMedia, .connected: true
        default: false
        }
    }
    
    /// Public so the view module can seed its style environment and read the tile-stats flag.
    public let style: ElementCallStyle
    public let options: any ElementCallOptions
    
    private let rtcService: MatrixRtcService
    private let transport: any ElementCallMatrixTransport
    private let system: any ElementCallSystemProviding
    private let logger: (any ElementCallLogging)?
    private let actionsSubject = PassthroughSubject<ElementCallControllerAction, Never>()
    private var eventsTask: Task<Void, Never>?
    private var routeObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    
    init(rtcService: MatrixRtcService,
         transport: any ElementCallMatrixTransport,
         system: any ElementCallSystemProviding,
         options: any ElementCallOptions,
         style: ElementCallStyle,
         logger: (any ElementCallLogging)?) {
        self.rtcService = rtcService
        self.transport = transport
        self.system = system
        self.options = options
        self.style = style
        self.logger = logger
        pictureInPicture.logger = logger
        
        routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isLoudspeaker = CallAudioSessionConfigurator.isLoudspeaker }
        }
        
        pictureInPicture.actions
            .sink { [weak self] action in
                guard let self else { return }
                switch action {
                case .started:
                    actionsSubject.send(.pictureInPictureStarted)
                case .restoreRequested:
                    actionsSubject.send(.restoreRequested)
                case .failed:
                    actionsSubject.send(.pictureInPictureUnavailable)
                case .closed:
                    // Closing the window is how you leave a call from Picture in Picture, which is
                    // what FaceTime does too.
                    hangUp()
                }
            }
            .store(in: &cancellables)
        
        system.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                switch event {
                case .audioSessionActivated:
                    audioSessionDidActivate()
                case .audioSessionDeactivated:
                    audioSessionDidDeactivate()
                case .microphoneMuteChanged(let isMuted):
                    applySystemMute(isMuted)
                case .endCallRequested:
                    hangUp()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Lifecycle
    
    public func startCall(_ callData: ElementCallData, room: any ElementCallRoomContext) {
        guard !isInCall else {
            log(.warning, "already in a call, ignoring start for \(room.roomID)")
            return
        }
        self.callData = callData
        self.room = room
        connection = .joining
        isMaximized = true
        
        // The system window has to show something when the member on screen has their camera off.
        // Built here rather than in the view layer because everything it needs, the host's avatars
        // and the room's profiles, is already to hand.
        pictureInPicture.placeholderProvider = { [weak self] memberID in
            guard let self else { return AnyView(Color.black) }
            return AnyView(ElementCallPictureInPicturePlaceholder(profile: memberID.flatMap { self.profile(forMemberID: $0) },
                                                                  fallbackName: room.displayName,
                                                                  style: style))
        }
        
        runTask = Task { await runCall(callData, room: room) }
    }
    
    public func hangUp() {
        Task { await endCall(leave: true) }
    }
    
    /// The view where the system anchors the Picture in Picture shrink animation. The host places it
    /// in the full-screen call layout; AVKit needs it on screen for the window to start by itself
    /// when the app is backgrounded.
    public var pictureInPictureSourceView: UIView {
        pictureInPicture.sourceView
    }
    
    /// Shrinks the call, and says how. Any call with the system window available uses it; every
    /// other case reports ``ElementCallControllerAction/pictureInPictureUnavailable`` so the host
    /// puts up its own minimized presentation, usually a bar.
    ///
    /// Audio calls go to the window too. They used to be excluded on `hasVideo`, which meant that
    /// with every camera off the collapse button silently did nothing — the window shows the
    /// avatar placeholder, which was already built and wired but unreachable. The bar remains the
    /// fallback for the cases that are genuinely not about video: the host disabling the window,
    /// a device that cannot do it, or a screen share holding it.
    public func requestMinimize() {
        isMaximized = false
        actionsSubject.send(.minimizeRequested)
        if options.isPictureInPictureEnabled, pictureInPicture.isPossible {
            pictureInPicture.start()
        } else {
            actionsSubject.send(.pictureInPictureUnavailable)
        }
    }
    
    /// Back to full screen, from the bar or from the system window.
    public func restore() {
        pictureInPicture.stop()
        isMaximized = true
    }
    
    func setMaximized(_ maximized: Bool) {
        isMaximized = maximized
    }
    
    public func toggleTileStats() {
        guard options.areTileStatsAvailable else { return }
        isTileStatsVisible.toggle()
        log(.info, "tile stats \(isTileStatsVisible ? "shown" : "hidden")")
    }
    
    // MARK: - Media controls
    
    /// From the UI: mutes the call and tells the system, whose echo comes back through
    /// ``applySystemMute(_:)``.
    public func setMicrophoneMuted(_ muted: Bool) {
        guard let roomID = room?.roomID else { return }
        Task { await call?.setMicrophoneMuted(muted) }
        system.setMicrophoneEnabled(!muted, roomID: roomID)
    }
    
    /// From the system call UI, including our own transaction echoing back. Idempotent at the call level.
    func applySystemMute(_ muted: Bool) {
        guard let call, call.isMicrophoneMuted != muted else { return }
        Task { await call.setMicrophoneMuted(muted) }
    }
    
    public func setCameraEnabled(_ enabled: Bool) {
        Task {
            do {
                if enabled, await !requestCameraAccess() {
                    return
                }
                try await call?.setCameraEnabled(enabled)
            } catch {
                log(.warning, "could not \(enabled ? "enable" : "disable") the camera: \(error)")
            }
        }
    }
    
    public func switchCamera() {
        do {
            try call?.switchCamera()
        } catch {
            log(.warning, "could not switch camera: \(error)")
        }
    }
    
    /// ReplayKit refuses to capture, with -5803, while the app holds a Picture in Picture controller,
    /// so the window is given up for the duration of a share and comes back when it ends. A call
    /// minimized meanwhile uses the bar.
    public func setScreenShareEnabled(_ enabled: Bool) {
        Task {
            guard let call else { return }
            if enabled {
                pictureInPicture.unbind()
            }
            do {
                try await call.setScreenShareEnabled(enabled)
            } catch {
                log(.warning, "could not \(enabled ? "start" : "stop") the screen share: \(error)")
                if enabled {
                    errorMessage = "Screen sharing could not start. \(Self.describe(error))"
                }
            }
            if !call.isScreenSharing {
                bindPictureInPictureIfEnabled(call)
            }
        }
    }
    
    private func bindPictureInPictureIfEnabled(_ call: MatrixRtcCall) {
        guard options.isPictureInPictureEnabled, !pictureInPicture.isBound else { return }
        pictureInPicture.automaticStartIncludesAudioCalls = options.isAutomaticPictureInPictureForAudioCallsEnabled
        pictureInPicture.bind(call: call) { [weak self] in self?.spotlightMemberID }
    }
    
    public func setLoudspeaker(_ enabled: Bool) {
        do {
            try CallAudioSessionConfigurator.setLoudspeaker(enabled)
            isLoudspeaker = CallAudioSessionConfigurator.isLoudspeaker
        } catch {
            log(.warning, "could not switch the audio output: \(error)")
        }
    }
    
    public func setAudioTestToneEnabled(_ enabled: Bool) {
        call?.setAudioTestToneEnabled(enabled)
    }
    
    // MARK: - System audio session
    
    private var isAudioSessionActive = false
    
    /// The system activated the audio session. It may happen before or after media connects, so the
    /// engine starts from whichever comes second.
    func audioSessionDidActivate() {
        isAudioSessionActive = true
        startAudioIfReady()
    }
    
    func audioSessionDidDeactivate() {
        isAudioSessionActive = false
        call?.stopAudio()
    }
    
    /// A video call is looked at, not held to an ear, so it starts on the loudspeaker. A headset
    /// still wins over both built-in outputs when one is connected.
    private func startAudioIfReady() {
        guard isAudioSessionActive, let call else { return }
        call.startAudio()
        if let callData, !callData.isAudioCall, CallAudioSessionConfigurator.isBuiltInReceiver {
            setLoudspeaker(true)
        }
    }
    
    // MARK: - Private
    
    /// The join in flight, cancelled by ``endCall(leave:)``. Joining takes seconds and a hang-up can
    /// land anywhere inside it; without this the join carried on, published camera and microphone
    /// into a session nobody owned any more, and the app kept both open with no screen left to stop
    /// them.
    private var runTask: Task<Void, Never>?
    
    private func runCall(_ callData: ElementCallData, room: any ElementCallRoomContext) async {
        log(.info, "joining \(room.roomID)")
        guard let (session, transport) = await joinSession(for: callData, room: room) else { return }
        
        connection = .connectingMedia
        let call: MatrixRtcCall
        do {
            call = try await session.connectMedia(transport: transport)
        } catch {
            await session.leave()
            await rtcService.release(roomID: room.roomID)
            fail("Media failed: \(error)")
            return
        }
        guard !Task.isCancelled else {
            await abandon(session: session, call: call, roomID: room.roomID)
            return
        }
        self.call = call
        bindPictureInPictureIfEnabled(call)
        
        await publishMedia(on: call, session: session, callData: callData, room: room)
    }
    
    /// Claims the system call, finds a transport and joins the session, which puts our membership out.
    private func joinSession(for callData: ElementCallData,
                             room: any ElementCallRoomContext) async -> (MatrixRtcSession, MatrixRtcTransport)? {
        // Claim the system call *before* our membership goes out: the incoming-call watcher reads
        // our own membership as "answered elsewhere" and would end the ringing call under us.
        // For an outgoing call this requests the start action; the system activates the audio session
        // either way and reports it back through the events publisher.
        do {
            try CallAudioSessionConfigurator.configure()
        } catch {
            log(.warning, "could not configure the audio session: \(error)")
        }
        await system.startCall(roomID: room.roomID, displayName: room.displayName, isVideo: !callData.isAudioCall)
        
        let transports: [MatrixRtcTransport]
        do {
            transports = try await transport.rtcTransports(roomID: room.roomID)
        } catch {
            fail("Could not discover the homeserver's RTC transports: \(error)")
            return nil
        }
        log(.info, "homeserver offers \(transports)")
        guard !Task.isCancelled else { return nil }
        guard let mediaTransport = transports.first(where: {
            if case .liveKit = $0 {
                return true
            } else {
                return false
            }
        }) else {
            fail("Homeserver offers no LiveKit transport")
            return nil
        }
        
        let compat = options.elementCallCompatibility
        log(.info, "joining with Element Call compatibility \(compat)")
        
        let session: MatrixRtcSession
        do {
            session = try await rtcService.joinSession(roomID: room.roomID,
                                                       transport: mediaTransport,
                                                       compat: compat,
                                                       notify: notify(for: callData, room: room))
        } catch {
            fail("Join failed: \(error)")
            return nil
        }
        guard !Task.isCancelled else {
            await abandon(session: session, roomID: room.roomID)
            return nil
        }
        self.session = session
        return (session, mediaTransport)
    }
    
    /// Microphone, then camera for a video call. The call counts as connected once the microphone is up.
    private func publishMedia(on call: MatrixRtcCall,
                              session: MatrixRtcSession,
                              callData: ElementCallData,
                              room: any ElementCallRoomContext) async {
        #if targetEnvironment(simulator)
        // CallKit never activates the session on the simulator.
        try? CallAudioSessionConfigurator.activate()
        isAudioSessionActive = true
        #endif
        // The system usually activated the session while we were still joining.
        startAudioIfReady()
        
        do {
            try await call.publishMicrophone()
        } catch {
            fail("Microphone failed: \(error)")
            return
        }
        guard !Task.isCancelled else {
            await abandon(session: session, call: call, roomID: room.roomID)
            return
        }
        log(.info, "connected as \(call.localMemberID)")
        
        eventsTask = Task { [weak self] in
            for await event in call.events {
                self?.handle(event)
            }
        }
        
        if !callData.isAudioCall, await requestCameraAccess(), !Task.isCancelled {
            try? await call.setCameraEnabled(true)
        }
        guard !Task.isCancelled else {
            await abandon(session: session, call: call, roomID: room.roomID)
            return
        }
        
        connection = .connected
        connectedAt = .now
        updateSpotlight(speakers: [])
        isLoudspeaker = CallAudioSessionConfigurator.isLoudspeaker
        system.reportConnected(roomID: room.roomID)
    }
    
    private func handle(_ event: MatrixRtcCallEvent) {
        switch event {
        case .activeSpeakers(let speakers):
            updateSpotlight(speakers: speakers.map(\.memberID))
        case .streamStarted(let memberID, .screenShare):
            spotlightMemberID = memberID
        case .streamStopped(_, .screenShare), .participantLeft, .participantJoined, .streamStarted(_, .camera):
            updateSpotlight(speakers: [])
        case .ended:
            // From a different task than the event collector: teardown cancels that task.
            Task { await endCall(leave: false) }
        default:
            break
        }
    }
    
    /// A screen share wins; otherwise the loudest speaker other than us, keeping the current one
    /// while they are still talking so tiles do not shuffle on every word.
    private func updateSpotlight(speakers: [String]) {
        guard let call else { return }
        if let sharer = call.participants.first(where: { $0.isPublishing(.screenShare) }) {
            spotlightMemberID = sharer.memberID
            return
        }
        let remoteSpeakers = speakers.filter { $0 != call.localMemberID }
        if let current = spotlightMemberID, remoteSpeakers.contains(current) {
            return
        }
        if let loudest = remoteSpeakers.first {
            spotlightMemberID = loudest
        } else if spotlightMemberID == nil || !call.participants.contains(where: { $0.memberID == spotlightMemberID }) {
            spotlightMemberID = call.participants.first { !$0.isLocal }?.memberID
        }
    }
    
    /// Only when *starting* a call; joining one someone else started happens quietly. A direct chat
    /// rings, a group call is an invitation rather than a summons.
    private func notify(for callData: ElementCallData, room: any ElementCallRoomContext) -> MatrixRtcNotify? {
        guard callData.isStartingCall else { return nil }
        return MatrixRtcNotify(kind: room.isDirect ? .ring : .notification,
                               intent: callData.isAudioCall ? .audio : .video)
    }
    
    private static func describe(_ error: Error) -> String {
        if case MatrixRtcError.media(let message) = error {
            return message
        }
        return "\(error)"
    }
    
    private func requestCameraAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
    
    /// The host's profile for whoever is on a tile. A member ID identifies a device rather than a
    /// person, so it goes through the participant list to find the user first. Falls back to a
    /// bare profile, because a member can be in the call before their room membership has loaded.
    public func profile(forMemberID memberID: String) -> ElementCallMemberProfile? {
        guard let participant = call?.participants.first(where: { $0.memberID == memberID }) else { return nil }
        return room?.memberProfiles[participant.userID]
            ?? ElementCallMemberProfile(userID: participant.userID, displayName: nil, avatarURL: nil)
    }
    
    private func log(_ level: ElementCallLogLevel, _ message: String) {
        logger?.log(level, message)
    }
    
    private func fail(_ message: String) {
        log(.error, message)
        connection = .failed(message)
        Task { await endCall(leave: true) }
    }
    
    /// Tears down what a join produced after the call was ended under it. Leaving is idempotent, so a
    /// session that already left costs nothing to leave again.
    private func abandon(session: MatrixRtcSession, call: MatrixRtcCall? = nil, roomID: String) async {
        log(.info, "join of \(roomID) was cancelled, releasing what it set up")
        await call?.disconnect()
        await session.leave()
        await rtcService.release(roomID: roomID)
        if self.call === call {
            self.call = nil
        }
        if self.session === session {
            self.session = nil
        }
    }
    
    private func endCall(leave: Bool) async {
        guard let roomID = room?.roomID else { return }
        log(.info, "ending call in \(roomID) (leave=\(leave))")
        runTask?.cancel()
        runTask = nil
        eventsTask?.cancel()
        eventsTask = nil
        pictureInPicture.unbind()
        
        if let session {
            if leave {
                await session.leave()
            } else {
                await session.call?.disconnect()
            }
            await rtcService.release(roomID: roomID)
        }
        call = nil
        session = nil
        system.endCall(roomID: roomID)
        #if targetEnvironment(simulator)
        CallAudioSessionConfigurator.deactivate()
        #endif
        
        if case .failed = connection {
            // Keep the failure visible until the screen is dismissed.
        } else {
            connection = .ended
        }
        connectedAt = nil
        spotlightMemberID = nil
        actionsSubject.send(.ended)
    }
    
    /// Back to idle once the screen has gone; a new call can start.
    public func reset() {
        guard !isInCall else { return }
        callData = nil
        room = nil
        connection = .idle
    }
    
    /// Previews and tests only: shows a state without joining anything.
    func setPreviewState(callData: ElementCallData, room: any ElementCallRoomContext, connection: ElementCallConnection) {
        self.callData = callData
        self.room = room
        self.connection = connection
    }
}
