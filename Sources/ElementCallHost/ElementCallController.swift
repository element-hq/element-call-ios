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
    public private(set) var room: (any ElementCallRoomContextProtocol)?
    
    /// The last failure worth telling the user about; the screen shows it once and clears it.
    public var errorMessage: String?
    
    public private(set) var session: MatrixRTCSession?
    public private(set) var call: MatrixRTCCall?
    
    /// The user's media intent while there is no call to hold it. The control bar is on screen from
    /// `.joining` onwards -- it is drawn whenever the screen is maximized, with no gate on the
    /// connection -- so a tap on mute or camera arrives before `call` does. Those taps used to be
    /// dropped: the button snapped back on the next refresh and the microphone went up unmuted.
    private var pendingMicrophoneMuted = false
    private var pendingCameraEnabled = false
    
    /// Computed rather than mirrored, so the call is the single truth the moment it exists and the
    /// two cannot drift -- `applySystemMute(_:)` writes to the call directly.
    public var isMicrophoneMuted: Bool {
        call?.isMicrophoneMuted ?? pendingMicrophoneMuted
    }
    
    public var isCameraEnabled: Bool {
        call?.isCameraEnabled ?? pendingCameraEnabled
    }
    
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
    
    /// The tile the layout gives its largest slot: the hero if the model marked one, else the head
    /// of the model's ranking.
    ///
    /// **Computed, because there is nothing left to remember.** This used to be stored state
    /// maintained by an `updateSpotlight` that re-implemented the ranking: a sharer wins, else the
    /// loudest remote speaker, else keep the current one while they are still talking, else the
    /// first remote. Every clause of that is the model's now, and damped — the "keep the current
    /// one" clause was this app's entire hysteresis and it had no timer at all. A stored copy would
    /// be a second ranking, free to disagree with the one being drawn.
    ///
    /// Never ourselves, and that costs nothing now: our own tile is not in the ranked list.
    public var spotlightTileID: MatrixRTCTileID? {
        guard let tiles = call?.tiles else { return nil }
        // The hero rather than simply the head, because a hero is a fact the model states and the
        // order is an arrangement of it. They agree today; if they ever stop, the hero is right.
        return (tiles.order.first(where: \.isHero) ?? tiles.order.first)?.id
    }
    
    public var isInCall: Bool {
        switch connection {
        case .joining, .connectingMedia, .connected: true
        default: false
        }
    }
    
    /// Public so the view module can seed its style environment and read the developer-mode flag.
    public let style: ElementCallStyle
    public let options: ElementCallOptions
    
    private let rtcService: MatrixRTCService
    private let transport: any ElementCallMatrixTransportProtocol
    private let system: any ElementCallSystemProvidingProtocol
    private let logger: (any ElementCallLoggingProtocol)?
    private let actionsSubject = PassthroughSubject<ElementCallControllerAction, Never>()
    private var eventsTask: Task<Void, Never>?
    private var routeObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    
    init(rtcService: MatrixRTCService,
         transport: any ElementCallMatrixTransportProtocol,
         system: any ElementCallSystemProvidingProtocol,
         options: ElementCallOptions,
         style: ElementCallStyle,
         logger: (any ElementCallLoggingProtocol)?) {
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
    
    public func startCall(_ callData: ElementCallData, room: any ElementCallRoomContextProtocol) {
        guard !isInCall else {
            log(.warning, "already in a call, ignoring start for \(room.roomID)")
            return
        }
        self.callData = callData
        self.room = room
        connection = .joining
        isMaximized = true
        // The starting point for the controls, which are live from here on. A tap before the call
        // exists overwrites these, and `publishMedia` joins with whatever they end up saying.
        pendingMicrophoneMuted = false
        pendingCameraEnabled = !callData.isAudioCall
        
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
        guard options.isDeveloperModeEnabled else { return }
        isTileStatsVisible.toggle()
        log(.info, "tile stats \(isTileStatsVisible ? "shown" : "hidden")")
    }
    
    // MARK: - Media controls
    
    /// From the UI: mutes the call and tells the system, whose echo comes back through
    /// ``applySystemMute(_:)``.
    public func setMicrophoneMuted(_ muted: Bool) {
        pendingMicrophoneMuted = muted
        Task { await call?.setMicrophoneMuted(muted) }
        // Only the system needs a room. The intent above is recorded either way, or a mute made
        // before the call connects is lost.
        if let roomID = room?.roomID {
            system.setMicrophoneEnabled(!muted, roomID: roomID)
        }
    }
    
    /// From the system call UI, including our own transaction echoing back. Idempotent, which is what
    /// makes our own echo a no-op.
    ///
    /// Guarded on the intent rather than on the call, so that muting from the system UI while we are
    /// still joining survives the join the same way muting from our own controls does.
    func applySystemMute(_ muted: Bool) {
        guard isMicrophoneMuted != muted else { return }
        pendingMicrophoneMuted = muted
        Task { await call?.setMicrophoneMuted(muted) }
    }
    
    public func setCameraEnabled(_ enabled: Bool) {
        Task {
            do {
                if enabled, await !requestCameraAccess() {
                    return
                }
                // After the gate, so declining the prompt leaves the intent off rather than joining
                // with a camera the user was never given.
                pendingCameraEnabled = enabled
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
        // Only starting is gated. Stopping stays available unconditionally so a share already in
        // flight can always be ended, whatever the option says.
        guard options.isScreenSharingEnabled || !enabled else { return }
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
    
    private func bindPictureInPictureIfEnabled(_ call: MatrixRTCCall) {
        guard options.isPictureInPictureEnabled, !pictureInPicture.isBound else { return }
        pictureInPicture.automaticStartIncludesAudioCalls = options.isAutomaticPictureInPictureForAudioCallsEnabled
        pictureInPicture.bind(call: call) { [weak self] in self?.spotlightTileID }
    }
    
    public func setLoudspeaker(_ enabled: Bool) {
        do {
            try CallAudioSessionConfigurator.setLoudspeaker(enabled)
            isLoudspeaker = CallAudioSessionConfigurator.isLoudspeaker
        } catch {
            log(.warning, "could not switch the audio output: \(error)")
        }
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
    
    private func runCall(_ callData: ElementCallData, room: any ElementCallRoomContextProtocol) async {
        log(.info, "joining \(room.roomID)")
        guard let (session, transport) = await joinSession(for: callData, room: room) else { return }
        
        connection = .connectingMedia
        let call: MatrixRTCCall
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
        
        await publishMedia(on: call, session: session, room: room)
    }
    
    /// Claims the system call, finds a transport and joins the session, which puts our membership out.
    private func joinSession(for callData: ElementCallData,
                             room: any ElementCallRoomContextProtocol) async -> (MatrixRTCSession, MatrixRTCTransport)? {
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
        
        let transports: [MatrixRTCTransport]
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
        
        let session: MatrixRTCSession
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
    private func publishMedia(on call: MatrixRTCCall,
                              session: MatrixRTCSession,
                              room: any ElementCallRoomContextProtocol) async {
        // Where nothing else owns the session, we do: the simulator, and an iOS app on macOS,
        // where the host's system-call port is inert because CallKit is unavailable. Runtime
        // rather than `#if`, because an iOS-on-Mac binary is indistinguishable from an iOS one at
        // compile time.
        if CallAudioSessionConfigurator.isSelfActivating {
            do {
                try CallAudioSessionConfigurator.activate()
                isAudioSessionActive = true
            } catch {
                log(.error, "could not activate the audio session: \(error)")
            }
        }
        // The system usually activated the session while we were still joining.
        startAudioIfReady()
        
        // `pendingMicrophoneMuted`, not `isMicrophoneMuted`: `self.call` is assigned before this runs,
        // so the accessor would already be answering from the fresh call -- unmuted -- and would
        // discard a mute made while joining. The same goes for the camera below.
        do {
            try await call.publishMicrophone(muted: pendingMicrophoneMuted)
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
        
        if pendingCameraEnabled, await requestCameraAccess(), !Task.isCancelled {
            try? await call.setCameraEnabled(true)
        }
        guard !Task.isCancelled else {
            await abandon(session: session, call: call, roomID: room.roomID)
            return
        }
        
        connection = .connected
        connectedAt = .now
        isLoudspeaker = CallAudioSessionConfigurator.isLoudspeaker
        system.reportConnected(roomID: room.roomID)
    }
    
    private func handle(_ event: MatrixRTCCallEvent) {
        // Everything else this switch used to carry existed only to recompute the spotlight, which
        // the model now ranks and damps for us.
        guard case .ended = event else { return }
        // From a different task than the event collector: teardown cancels that task.
        Task { await endCall(leave: false) }
    }
    
    /// Only when *starting* a call; joining one someone else started happens quietly. A direct chat
    /// rings, a group call is an invitation rather than a summons.
    private func notify(for callData: ElementCallData, room: any ElementCallRoomContextProtocol) -> MatrixRTCNotify? {
        guard callData.isStartingCall else { return nil }
        return MatrixRTCNotify(kind: room.isDirect ? .ring : .notification,
                               intent: callData.isAudioCall ? .audio : .video)
    }
    
    private static func describe(_ error: Error) -> String {
        if case MatrixRTCError.media(let message) = error {
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
        guard let call else { return nil }
        // The tile roster's references carry the user id for exactly this; our own tile is beside it.
        let userID = call.tiles.order.first { $0.id.memberID == memberID }?.userID
            ?? (call.ownTile?.memberID == memberID ? call.ownTile?.userID : nil)
            ?? call.participants.first { $0.memberID == memberID }?.userID
        guard let userID else { return nil }
        return room?.memberProfiles[userID]
            ?? ElementCallMemberProfile(userID: userID, displayName: nil, avatarURL: nil)
    }
    
    /// Forwards the caller's position rather than its own, or every line in this file would be
    /// attributed to the line below.
    private func log(_ level: ElementCallLogLevel, _ message: String, file: String = #fileID, line: Int = #line) {
        logger?.log(level, message, file: file, line: line)
    }
    
    private func fail(_ message: String) {
        log(.error, message)
        connection = .failed(message)
        Task { await endCall(leave: true) }
    }
    
    /// Tears down what a join produced after the call was ended under it. Leaving is idempotent, so a
    /// session that already left costs nothing to leave again.
    private func abandon(session: MatrixRTCSession, call: MatrixRTCCall? = nil, roomID: String) async {
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
        // Paired with the activation in publishMedia through the same predicate, so the two
        // cannot disagree about which platforms they apply to and leave the session up.
        if CallAudioSessionConfigurator.isSelfActivating {
            CallAudioSessionConfigurator.deactivate()
            // Only where we own the session. On device CallKit owns it and reports the
            // deactivation through `didDeactivate`; clearing the flag here instead would mean a
            // second call starting before that arrives never sees an activation of its own, and
            // `startAudioIfReady` would refuse to start audio for a call that is otherwise fine.
            isAudioSessionActive = false
        }
        
        if case .failed = connection {
            // Keep the failure visible until the screen is dismissed.
        } else {
            connection = .ended
        }
        connectedAt = nil
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
    /// `connectedAt` is defaulted because only a joined call normally has one, and it is offered at
    /// all so the minimized bar's duration timer is reachable without one: it is the single branch
    /// of that view no preview, snapshot or harness could otherwise draw.
    func setPreviewState(callData: ElementCallData,
                         room: any ElementCallRoomContextProtocol,
                         connection: ElementCallConnection,
                         connectedAt: Date? = nil) {
        self.callData = callData
        self.room = room
        self.connection = connection
        self.connectedAt = connectedAt
        // The same seed `startCall` makes, so a preview of a connecting call draws the controls a
        // real one would: the camera reads as on for a video call from the moment it is joining,
        // which is what it will join with.
        pendingCameraEnabled = !callData.isAudioCall
    }
}
