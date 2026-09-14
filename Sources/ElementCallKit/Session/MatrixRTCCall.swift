//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import MatrixRtc
import Observation
import Synchronization
import UIKit

/// The media half of a session: publishes the microphone, camera and screen, plays every remote
/// member and hands out video frames for tiles. Owned by `MatrixRTCSession`.
@MainActor
@Observable
public final class MatrixRTCCall {
    public let localMemberID: String
    
    /// The transport's roster (not the membership projection; the two can legitimately differ).
    public private(set) var participants: [MatrixRTCParticipant] = []
    public private(set) var audioLevels: [String: MatrixRTCAudioLevel] = [:]
    public private(set) var receiveStats: [String: MatrixRTCReceiveStats] = [:]
    public private(set) var activeSpeakerIDs: Set<String> = []
    public private(set) var frameEncryption: [String: MatrixRTCFrameEncryptionState] = [:]
    public private(set) var isMicrophoneMuted = false
    public private(set) var isAudioTestToneEnabled = false
    public private(set) var isCameraEnabled = false
    /// The system holds the camera (app backgrounded without the multitasking entitlement); the
    /// track is muted at the transport meanwhile so peers see camera-off rather than a frozen frame.
    public private(set) var isCameraInterrupted = false
    public private(set) var isFrontCamera = true
    public private(set) var isScreenSharing = false
    public private(set) var isMediaDegraded = false
    public private(set) var hasEnded = false
    
    /// Every core event, after the call itself reacted to it.
    public let events: AsyncStream<MatrixRTCCallEvent>
    private let eventsContinuation: AsyncStream<MatrixRTCCallEvent>.Continuation
    
    private let mediaSession: MediaSession
    private let audioEngine = CallAudioEngine()
    @ObservationIgnored private lazy var microphone = MicrophoneCapturer(engine: audioEngine) { [weak self] level in
        Task { @MainActor in self?.setAudioLevel(level, for: self?.localMemberID) }
    }
    
    @ObservationIgnored private lazy var camera: CameraCapturer = {
        let capturer = CameraCapturer { [weak self] frame in
            guard let self else { return }
            localVideo.offer(frame)
            if let info = localVideoMeter.record(frame) {
                Task { @MainActor in self.videoInfos[VideoStreamKey(memberID: self.localMemberID, kind: .camera)] = info }
            }
        }
        capturer.onInterruption = { [weak self] interrupted in
            Task { @MainActor in await self?.handleCameraInterruption(interrupted) }
        }
        return capturer
    }()
    
    private let screenShare = ScreenShareCapturer()
    /// The self view: frames straight from the camera, mirrored for the front one.
    public let localVideo = LocalVideoFanOut()
    
    private var microphoneTrack: FfiLocalTrack?
    private let localVideoMeter = VideoFrameMeter()
    private var cameraTrack: FfiLocalTrack?
    private var playbackSinks = [String: AudioPlaybackSink]()
    private var videoSources = [VideoStreamKey: RemoteVideoSource]()
    private var appliedConstraints = [VideoStreamKey: MatrixRTCVideoConstraints]()
    /// Members whose video is released rather than merely paused. Held as member IDs because that
    /// is what the stage knows: a tile it has paged far away wants neither camera nor screen share.
    private var releasedVideoMembers = Set<String>()
    private var tasks = [Task<Void, Never>]()
    
    private struct VideoStreamKey: Hashable {
        let memberID: String
        let kind: MatrixRTCStreamKind
    }
    
    /// Size and frame rate of the streams being drawn (or captured), refreshed about once a second.
    private var videoInfos = [VideoStreamKey: MatrixRTCVideoInfo]()
    
    public func videoInfo(memberID: String, kind: MatrixRTCStreamKind = .camera) -> MatrixRTCVideoInfo? {
        videoInfos[VideoStreamKey(memberID: memberID, kind: kind)]
    }
    
    /// Upright aspect ratio of a stream seen so far, so a surface can be sized before its first frame.
    public func videoAspect(memberID: String, kind: MatrixRTCStreamKind = .camera) -> CGFloat? {
        videoInfo(memberID: memberID, kind: kind)?.aspect
    }
    
    /// What was last asked of the SFU for a stream.
    public func requestedVideoConstraints(memberID: String, kind: MatrixRTCStreamKind = .camera) -> MatrixRTCVideoConstraints? {
        appliedConstraints[VideoStreamKey(memberID: memberID, kind: kind)]
    }
    
    init(localMemberID: String, mediaSession: MediaSession) {
        self.localMemberID = localMemberID
        self.mediaSession = mediaSession
        (events, eventsContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(64))
    }
    
    /// Starts the event pump **before** anything announces the call as connected (the stream has no
    /// replay), then sweeps the roster for members already publishing.
    func start() async {
        tasks.append(Task { [weak self] in await self?.pumpEvents() })
        tasks.append(Task { [weak self] in await self?.pollReceiveStats() })
        refreshParticipants()
        for participant in participants where !participant.isLocal && participant.stream(.microphone) != nil {
            playAudio(of: participant.memberID)
        }
    }
    
    // MARK: - Audio device
    
    /// From CallKit's `didActivate audioSession` (or directly on the simulator).
    ///
    /// Returns before the engine is actually running: starting it means reconfiguring the graph,
    /// which is exactly what must not happen synchronously on this thread.
    public func startAudio() {
        audioEngine.start()
    }
    
    /// From CallKit's `didDeactivate audioSession`.
    public func stopAudio() {
        audioEngine.stop()
    }
    
    // MARK: - Microphone
    
    public func publishMicrophone() async throws {
        guard microphoneTrack == nil else { return }
        let track: FfiLocalTrack
        do {
            track = try await mediaSession.publish(options: FfiPublishOptions(kind: .microphone,
                                                                              audio: FfiAudioSourceConfig(sampleRate: UInt32(AudioFormat.sampleRate),
                                                                                                          numChannels: UInt32(AudioFormat.channelCount)),
                                                                              video: nil,
                                                                              simulcast: false))
        } catch {
            throw MatrixRTCError.media("Failed to publish the microphone: \(error)")
        }
        microphoneTrack = track
        microphone.setTestToneEnabled(isAudioTestToneEnabled)
        microphone.start(track: track)
        // The transport only learns about a mute once there is a track.
        await setMicrophoneMuted(isMicrophoneMuted)
        MatrixRTCLog.info("Publishing microphone as \(localMemberID)")
    }
    
    /// Stops handing frames over **and** tells the transport, so peers see a deliberate mute rather
    /// than a client that wedged.
    public func setMicrophoneMuted(_ muted: Bool) async {
        isMicrophoneMuted = muted
        microphone.setMuted(muted)
        await setTransportMuted(.microphone, muted: muted)
    }
    
    public func setAudioTestToneEnabled(_ enabled: Bool) {
        isAudioTestToneEnabled = enabled
        microphone.setTestToneEnabled(enabled)
    }
    
    // MARK: - Camera
    
    /// On: start capture, then unmute the transport. Off: **mute the transport first**, then release
    /// the device (a peer told afterwards has already been shown a frozen picture).
    public func setCameraEnabled(_ enabled: Bool) async throws {
        guard isCameraEnabled != enabled else { return }
        if enabled {
            let track: FfiLocalTrack
            if let cameraTrack {
                track = cameraTrack
            } else {
                do {
                    // simulcast is not a quality setting: with one layer dynacast pauses the only
                    // encoding nobody's small tile asked for and no video leaves the device.
                    track = try await mediaSession.publish(options: FfiPublishOptions(kind: .camera,
                                                                                      audio: nil,
                                                                                      video: FfiVideoSourceConfig(width: CameraCapturer.captureWidth,
                                                                                                                  height: CameraCapturer.captureHeight),
                                                                                      simulcast: true))
                } catch {
                    throw MatrixRTCError.media("Failed to publish the camera: \(error)")
                }
                cameraTrack = track
            }
            camera.setInterfaceOrientation(currentInterfaceOrientation)
            try camera.start(track: track)
            isFrontCamera = camera.isFrontFacing
            await setTransportMuted(.camera, muted: false)
        } else {
            await setTransportMuted(.camera, muted: true)
            camera.stop()
        }
        isCameraEnabled = enabled
        MatrixRTCLog.info("Camera \(enabled ? "enabled" : "disabled") for \(localMemberID)")
    }
    
    public func switchCamera() throws {
        isFrontCamera = try camera.switchCamera()
    }
    
    /// Anyone (us included) has video worth showing.
    public var hasVideo: Bool {
        (isCameraEnabled && !isCameraInterrupted) || participants.contains { !$0.isLocal && ($0.isPublishing(.camera) || $0.isPublishing(.screenShare)) }
    }
    
    /// What a single-tile surface (Picture in Picture) should show: the spotlight member's screen share
    /// or camera, else the first remote member with video, else our own camera.
    public func pictureInPictureCandidate(spotlightMemberID: String?) -> (memberID: String, kind: MatrixRTCStreamKind)? {
        Self.pictureInPictureCandidate(participants: participants,
                                       localMemberID: localMemberID,
                                       isLocalCameraAvailable: isCameraEnabled && !isCameraInterrupted,
                                       spotlightMemberID: spotlightMemberID)
    }
    
    public nonisolated static func pictureInPictureCandidate(participants: [MatrixRTCParticipant],
                                                             localMemberID: String,
                                                             isLocalCameraAvailable: Bool,
                                                             spotlightMemberID: String?) -> (memberID: String, kind: MatrixRTCStreamKind)? {
        func candidate(for participant: MatrixRTCParticipant) -> (memberID: String, kind: MatrixRTCStreamKind)? {
            if participant.isPublishing(.screenShare) {
                return (participant.memberID, .screenShare)
            }
            if participant.isPublishing(.camera) {
                return (participant.memberID, .camera)
            }
            return nil
        }
        if let spotlightMemberID, let spotlight = participants.first(where: { $0.memberID == spotlightMemberID && !$0.isLocal }),
           let candidate = candidate(for: spotlight) {
            return candidate
        }
        if let remote = participants.filter({ !$0.isLocal }).compactMap(candidate(for:)).first {
            return remote
        }
        if isLocalCameraAvailable {
            return (localMemberID, .camera)
        }
        return nil
    }
    
    /// Who the single-tile surface should *name* when nobody has video and it falls back to an
    /// avatar. Separate from ``pictureInPictureCandidate(spotlightMemberID:)``, which answers what
    /// stream to show and returns nil in exactly that case.
    public func pictureInPicturePlaceholderMemberID(spotlightMemberID: String?) -> String? {
        Self.pictureInPicturePlaceholderMemberID(participants: participants, spotlightMemberID: spotlightMemberID)
    }
    
    public nonisolated static func pictureInPicturePlaceholderMemberID(participants: [MatrixRTCParticipant],
                                                                       spotlightMemberID: String?) -> String? {
        // The spotlight can be us — it is only excluded when picking a stream — and showing the
        // user their own avatar in the window tells them nothing about who they are talking to.
        if let spotlightMemberID, participants.contains(where: { $0.memberID == spotlightMemberID && !$0.isLocal }) {
            return spotlightMemberID
        }
        return participants.first { !$0.isLocal }?.memberID
    }
    
    private func handleCameraInterruption(_ interrupted: Bool) async {
        guard isCameraEnabled, isCameraInterrupted != interrupted else { return }
        isCameraInterrupted = interrupted
        // The user's camera choice stays what it was; only the transport state follows the interruption.
        await setTransportMuted(.camera, muted: interrupted)
    }
    
    public func updateInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        camera.setInterfaceOrientation(orientation)
    }
    
    // MARK: - Screen share
    
    /// A screen has no "off": stopping **unpublishes** rather than mutes, otherwise every peer keeps
    /// drawing an empty tile for a share that ended.
    public func setScreenShareEnabled(_ enabled: Bool) async throws {
        guard isScreenSharing != enabled else { return }
        if enabled {
            let track: FfiLocalTrack
            do {
                track = try await mediaSession.publish(options: FfiPublishOptions(kind: .screenShare,
                                                                                  audio: nil,
                                                                                  video: FfiVideoSourceConfig(width: UInt32(ScreenShareCapturer.maxLongEdge),
                                                                                                              height: UInt32(ScreenShareCapturer.maxLongEdge * 9 / 16)),
                                                                                  simulcast: true))
            } catch {
                throw MatrixRTCError.media("Failed to publish the screen share: \(error)")
            }
            do {
                try await screenShare.start(track: track)
            } catch {
                try? await mediaSession.unpublish(kind: .screenShare)
                throw error
            }
            await setTransportMuted(.screenShare, muted: false)
        } else {
            await screenShare.stop()
            do {
                try await mediaSession.unpublish(kind: .screenShare)
            } catch {
                MatrixRTCLog.warning("Could not unpublish the screen share: \(error)")
            }
        }
        isScreenSharing = enabled
        MatrixRTCLog.info("Screen share \(enabled ? "started" : "stopped") for \(localMemberID)")
    }
    
    // MARK: - Remote video
    
    /// Attaches a tile's slot to the member's stream, opening the decoder on first attach.
    public func attachVideo(_ slot: VideoFrameSlot, memberID: String, kind: MatrixRTCStreamKind = .camera) {
        let key = VideoStreamKey(memberID: memberID, kind: kind)
        let source = videoSources[key] ?? {
            let mediaSession = mediaSession
            let source = RemoteVideoSource {
                mediaSession.videoStream(memberId: memberID, kind: kind.ffi).map(VideoFrameStreamBox.init)
            } onIdle: { [weak self] in
                // Nobody draws it any more: stop asking the SFU for it.
                Task { @MainActor in self?.setVideoConstraints(.init(isVisible: false, pixelSize: nil), memberID: memberID, kind: kind) }
            }
            source.onVideoInfo = { [weak self] info in
                Task { @MainActor in self?.videoInfos[key] = info }
            }
            videoSources[key] = source
            return source
        }()
        source.attach(slot)
        // A tile only attaches once it is on screen, so whatever the stage last decided about this
        // member is out of date the moment we get here: drop the release before asking for the
        // stream, or the diff below would immediately take it away again.
        releasedVideoMembers.remove(memberID)
        // A tile that comes back after the stream went idle (or was released) needs the SFU sending
        // again; the tile's own size report refines this shortly after.
        let applied = appliedConstraints[key]
        if applied == nil || applied?.isVisible == false || applied?.isEnabled == false {
            setVideoConstraints(.init(isVisible: true, pixelSize: applied?.pixelSize), memberID: memberID, kind: kind)
        }
    }
    
    public func detachVideo(_ slot: VideoFrameSlot, memberID: String, kind: MatrixRTCStreamKind = .camera) {
        videoSources[VideoStreamKey(memberID: memberID, kind: kind)]?.detach(slot)
        reportDrawnSize(nil, slot: slot, memberID: memberID, kind: kind)
    }
    
    /// Drawn sizes per surface, so the SFU is asked for the largest of everything currently showing
    /// a stream rather than for whichever surface happened to lay out last.
    private var drawnSizes = [VideoStreamKey: [UUID: CGSize]]()
    /// Members paused and waiting out ``releaseLinger`` before they are released.
    private var pendingReleases = [String: Task<Void, Never>]()
    
    /// A surface reports how big it draws a stream (nil when it stops drawing it).
    public func reportDrawnSize(_ size: CGSize?, slot: VideoFrameSlot, memberID: String, kind: MatrixRTCStreamKind = .camera) {
        guard memberID != localMemberID else { return }
        // A surface that is still laid out but released (Picture in Picture keeps one alive) must
        // not re-subscribe the stream behind the stage's back.
        guard !releasedVideoMembers.contains(memberID) else { return }
        let key = VideoStreamKey(memberID: memberID, kind: kind)
        var sizes = drawnSizes[key] ?? [:]
        sizes[slot.id] = size
        drawnSizes[key] = sizes.isEmpty ? nil : sizes
        guard let largest = sizes.values.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
            // The idle path (linger) tells the SFU to stop; nothing to ask for meanwhile.
            return
        }
        setVideoConstraints(.init(isVisible: true, pixelSize: largest), memberID: memberID, kind: kind)
    }
    
    /// Say how big the tile really is; the SFU then sends the layer that fits. De-duplicated: layout
    /// recomputes on every pass and most land on the same numbers.
    public func setVideoConstraints(_ constraints: MatrixRTCVideoConstraints, memberID: String, kind: MatrixRTCStreamKind = .camera) {
        // Our own streams are not subscribed from the SFU; and layout jitters by a pixel between
        // passes, which is not news worth a round trip: snap to a 16 px grid.
        guard memberID != localMemberID else { return }
        let constraints = MatrixRTCVideoConstraints(isEnabled: constraints.isEnabled,
                                                    isVisible: constraints.isEnabled && constraints.isVisible,
                                                    pixelSize: constraints.pixelSize.map { size in
                                                        CGSize(width: (size.width / 16).rounded() * 16, height: (size.height / 16).rounded() * 16)
                                                    })
        let key = VideoStreamKey(memberID: memberID, kind: kind)
        guard appliedConstraints[key] != constraints else { return }
        appliedConstraints[key] = constraints
        MatrixRTCLog.info("Constraints for \(memberID) (\(kind)): enabled=\(constraints.isEnabled) visible=\(constraints.isVisible) size=\(constraints.pixelSize.map { "\(Int($0.width))x\(Int($0.height))" } ?? "auto")")
        
        let detail: FfiVideoDetail = if constraints.isVisible, let size = constraints.pixelSize {
            .dimensions(width: UInt32(size.width), height: UInt32(size.height))
        } else {
            .auto
        }
        let mediaSession = mediaSession
        Task.detached(priority: .utility) {
            mediaSession.setConstraints(memberId: memberID,
                                        kind: kind.ffi,
                                        constraints: FfiMediaConstraints(enabled: constraints.isEnabled, visible: constraints.isVisible, detail: detail, lowBandwidth: false))
        }
    }
    
    /// How long a member stays merely paused before being released outright. Long enough to cover
    /// looking at one tile and changing your mind, short enough that actually settling on one frees
    /// the call's bandwidth.
    private static let releaseLinger = Duration.seconds(3)
    
    /// The members the stage is no longer drawing: paged far enough away, or hidden because one tile
    /// has the whole screen. For both the camera and a screen share, since neither is being shown.
    ///
    /// Getting there takes two steps, and the difference between them is the whole reason the core
    /// draws a line between paused and released. Pausing is immediate and resumes instantly;
    /// releasing frees the subscription but costs a visible re-negotiation to undo. So a member
    /// named here is **paused at once and released only if they are still named a few seconds
    /// later**: going full screen and straight back out, or swiping past a page, then costs nothing,
    /// while settling on one tile still gives a thirty-person call its bandwidth back.
    ///
    /// This is a set rather than a per-tile call so there is one place that knows which members are
    /// released. An earlier shape had each tile release itself on the way out, and members who left
    /// while off screen were never restored, because the tile that owed them the call had gone.
    public func setReleasedVideoMembers(_ memberIDs: Set<String>) {
        let released = memberIDs.subtracting([localMemberID])
        guard released != releasedVideoMembers else { return }
        // Only the members that changed side need a round trip; setVideoConstraints de-duplicates
        // the rest anyway, but a big call would otherwise walk every member on every swipe.
        let changed = released.symmetricDifference(releasedVideoMembers)
        releasedVideoMembers = released
        for memberID in changed {
            // Whichever way this member just went, any release still waiting on them is stale.
            pendingReleases.removeValue(forKey: memberID)?.cancel()
            let isReleased = released.contains(memberID)
            for kind in [MatrixRTCStreamKind.camera, .screenShare] {
                let key = VideoStreamKey(memberID: memberID, kind: kind)
                // A surface going away reports a nil size, and `reportDrawnSize` drops that report
                // when the member is already released. Releasing and unmounting happen in one pass
                // and in no defined order, so whenever the release lands first the departing
                // surface's size would stay here for the rest of the call and go on inflating the
                // maximum for whoever draws the stream next. One tile at a time while paging; a
                // whole call at once now that a tile can go full screen.
                if isReleased {
                    drawnSizes[key] = nil
                }
                let applied = appliedConstraints[key]
                // Both directions land on paused. Leaving stops there because it is the tile's own
                // attach that says it is being drawn again and at what size; arriving stops there
                // because the release is the step below.
                setVideoConstraints(.init(isEnabled: true, isVisible: false, pixelSize: applied?.pixelSize),
                                    memberID: memberID,
                                    kind: kind)
            }
            guard isReleased else { continue }
            pendingReleases[memberID] = Task { [weak self] in
                try? await Task.sleep(for: Self.releaseLinger)
                guard !Task.isCancelled else { return }
                self?.release(memberID)
            }
        }
    }
    
    /// The second step of ``setReleasedVideoMembers(_:)``, once the member has stayed unwatched.
    private func release(_ memberID: String) {
        pendingReleases[memberID] = nil
        // They may have come back while this was waiting, in which case the cancel above raced us.
        guard releasedVideoMembers.contains(memberID) else { return }
        for kind in [MatrixRTCStreamKind.camera, .screenShare] {
            let applied = appliedConstraints[VideoStreamKey(memberID: memberID, kind: kind)]
            setVideoConstraints(.init(isEnabled: false, isVisible: false, pixelSize: applied?.pixelSize),
                                memberID: memberID,
                                kind: kind)
        }
    }
    
    // MARK: - Teardown
    
    public func disconnect() async {
        pendingReleases.values.forEach { $0.cancel() }
        pendingReleases.removeAll()
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        audioLevelFlush?.cancel()
        audioLevelFlush = nil
        microphone.stop()
        camera.stop()
        await screenShare.stop()
        playbackSinks.values.forEach { $0.stop() }
        playbackSinks.removeAll()
        videoSources.values.forEach { $0.close() }
        videoSources.removeAll()
        releasedVideoMembers.removeAll()
        // Stops the engine *and* detaches every node in one hop. Each `stop()` above only flips a
        // flag and enqueues its detach, so the whole audio teardown costs this actor microseconds
        // rather than blocking it on graph reconfiguration — which is what the render thread used
        // to deadlock against.
        audioEngine.shutdown()
        do {
            try await mediaSession.disconnect()
        } catch {
            MatrixRTCLog.warning("Failed to disconnect the media session: \(error)")
        }
        eventsContinuation.finish()
    }
    
    // MARK: - Private
    
    private var currentInterfaceOrientation: UIInterfaceOrientation {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.interfaceOrientation ?? .portrait
    }
    
    private func pumpEvents() async {
        while !Task.isCancelled, let ffiEvent = await mediaSession.nextEvent() {
            let event = MatrixRTCCallEvent(ffiEvent)
            handle(event)
            eventsContinuation.yield(event)
            refreshParticipants()
        }
        MatrixRTCLog.debug("Media event pump stopped")
    }
    
    private func handle(_ event: MatrixRTCCallEvent) {
        switch event {
        case .streamStarted(let memberID, .microphone) where memberID != localMemberID:
            playAudio(of: memberID)
        case .streamStopped(let memberID, .microphone), .participantLeft(let memberID):
            stopPlayback(of: memberID)
        case .activeSpeakers(let speakers):
            hasTransportSpeakerEvents = true
            activeSpeakerIDs = Set(speakers.map(\.memberID))
        case .frameEncryptionState(let memberID, let state):
            if frameEncryption[memberID] != state {
                MatrixRTCLog.warning("Frame encryption \(state) for \(memberID) (was \(frameEncryption[memberID].map { "\($0)" } ?? "unknown"))")
            }
            frameEncryption[memberID] = state
        case .keyDiscarded(let memberID, let reason):
            MatrixRTCLog.warning("Key for \(memberID) discarded: \(reason)")
        case .keyImported(let memberID, let keyIndex):
            MatrixRTCLog.info("Key index \(keyIndex) imported for \(memberID)")
        case .mediaConnectionDegraded(let degraded):
            isMediaDegraded = degraded
        case .ended(let reason):
            MatrixRTCLog.info("Media session ended: \(reason)")
            hasEnded = true
            playbackSinks.values.forEach { $0.stop() }
            playbackSinks.removeAll()
        default:
            break
        }
    }
    
    /// `streamStarted` and the initial roster sweep both fire for a member already publishing; the
    /// dictionary claim keeps a member from being played twice, slightly out of step.
    private func playAudio(of memberID: String) {
        guard memberID != localMemberID, playbackSinks[memberID] == nil else { return }
        guard let stream = mediaSession.audioStream(memberId: memberID, kind: .microphone) else {
            MatrixRTCLog.warning("Cannot open the audio stream for \(memberID)")
            return
        }
        let sink = AudioPlaybackSink(memberID: memberID, engine: audioEngine) { [weak self] memberID, level in
            Task { @MainActor in self?.setAudioLevel(level, for: memberID) }
        }
        playbackSinks[memberID] = sink
        sink.start(stream: stream)
        MatrixRTCLog.info("Playing audio of \(memberID)")
    }
    
    private func stopPlayback(of memberID: String) {
        playbackSinks.removeValue(forKey: memberID)?.stop()
        audioLevels[memberID] = nil
        pendingAudioLevels[memberID] = nil
        for key in videoSources.keys where key.memberID == memberID {
            videoSources.removeValue(forKey: key)?.close()
        }
    }
    
    private func refreshParticipants() {
        let refreshed = mediaSession.participants().map(MatrixRTCParticipant.init)
        // Bail before assigning rather than after: this is now called on a timer as well as on
        // every event, and `participants` is observed by every tile, so an unconditional write
        // would rebuild the whole stage once a second for nothing.
        guard refreshed != participants else { return }
        if Set(refreshed.map(\.memberID)) != Set(participants.map(\.memberID)) {
            MatrixRTCLog.info("Media roster \(refreshed.count): \(refreshed.map { "\($0.memberID)\($0.isLocal ? " (self)" : "")" })")
        }
        participants = refreshed
    }
    
    /// Above this RMS a member counts as speaking when the transport sends no speaker events.
    private static let speakingThreshold: Float = 0.02
    private var hasTransportSpeakerEvents = false
    
    /// Meters report ten times a second *per member*; published one by one, an eleven-person call
    /// would rebuild every tile over a hundred times a second. Levels are collected here and
    /// published in one batch per sample period, which is all a meter needs.
    private static let audioLevelSamplePeriod: Duration = .milliseconds(100)
    @ObservationIgnored private var pendingAudioLevels: [String: MatrixRTCAudioLevel] = [:]
    @ObservationIgnored private var audioLevelFlush: Task<Void, Never>?
    
    private func setAudioLevel(_ level: MatrixRTCAudioLevel, for memberID: String?) {
        guard let memberID else { return }
        pendingAudioLevels[memberID] = level
        guard audioLevelFlush == nil else { return }
        audioLevelFlush = Task { [weak self] in
            try? await Task.sleep(for: Self.audioLevelSamplePeriod)
            guard !Task.isCancelled else { return }
            self?.flushAudioLevels()
        }
    }
    
    private func flushAudioLevels() {
        audioLevelFlush = nil
        guard !pendingAudioLevels.isEmpty else { return }
        var levels = audioLevels
        for (memberID, level) in pendingAudioLevels {
            levels[memberID] = level
        }
        pendingAudioLevels.removeAll(keepingCapacity: true)
        audioLevels = levels
        
        // LiveKit's active-speaker updates have not been observed through the core, so
        // derive them from the decoded audio until they show up.
        guard !hasTransportSpeakerEvents else { return }
        let speaking = Set(audioLevels.filter { $0.value.level > Self.speakingThreshold }.keys)
        if speaking != activeSpeakerIDs {
            activeSpeakerIDs = speaking
            let ranked = speaking.sorted { (audioLevels[$0]?.level ?? 0) > (audioLevels[$1]?.level ?? 0) }
            eventsContinuation.yield(.activeSpeakers(ranked.map { .init(memberID: $0, level: audioLevels[$0]?.level ?? 0) }))
        }
    }
    
    /// RTCP reports arrive about once a second; polling faster only repeats values.
    private func pollReceiveStats() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            // The roster is re-read here, not only after an event. The snapshot taken at join can
            // report a member's camera as unmuted before the transport has learned otherwise, and
            // if that member then does nothing, no event ever arrives to correct it: joining a
            // call where somebody already has their camera off left their tile black for as long
            // as they stayed still. Observed against Element Web, and it repaired itself the
            // moment they toggled their camera, which is what identified the stale read.
            refreshParticipants()
            var stats = [String: MatrixRTCReceiveStats]()
            for participant in participants where !participant.isLocal {
                if let audio = await mediaSession.receiveStats(memberId: participant.memberID, kind: .microphone) {
                    stats[participant.memberID] = .init(audio)
                }
            }
            receiveStats = stats
        }
    }
    
    private func setTransportMuted(_ kind: MatrixRTCStreamKind, muted: Bool) async {
        do {
            try await mediaSession.setLocalMuted(kind: kind.ffi, muted: muted)
        } catch {
            MatrixRTCLog.warning("Could not tell the transport \(kind) is \(muted ? "muted" : "unmuted"): \(error)")
        }
    }
}

/// Fans the local camera frames out to every self-view slot.
public final nonisolated class LocalVideoFanOut: Sendable {
    private let slots = Mutex<[UUID: VideoFrameSlot]>([:])
    
    public func attach(_ slot: VideoFrameSlot) {
        slots.withLock { $0[slot.id] = slot }
    }
    
    public func detach(_ slot: VideoFrameSlot) {
        slots.withLock { $0[slot.id] = nil }; slot.clear()
    }
    
    func offer(_ frame: MatrixRTCVideoFrame) {
        for slot in slots.withLock({ Array($0.values) }) {
            slot.offer(frame)
        }
    }
}
