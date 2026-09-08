//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import ElementCall
import ElementCallKit
import SwiftUI

/// What the views read and write. Kept as a separate object from the view model so the views take
/// one observable thing and hold no reference to the call itself.
@Observable
@MainActor
public final class ElementCallScreenContext {
    public fileprivate(set) var viewState: ElementCallScreenViewState
    /// Bound by the screen, so an alert shows once and clears itself.
    public var alertInfo: ElementCallAlert?
    /// Colours, fonts, icons, avatars and text, all supplied by the host.
    public let style: ElementCallStyle
    
    fileprivate var handler: ((ElementCallScreenViewAction) -> Void)?
    
    fileprivate init(viewState: ElementCallScreenViewState, style: ElementCallStyle) {
        self.viewState = viewState
        self.style = style
    }
    
    /// Builds a context around a state written by hand, with nothing behind it.
    ///
    /// This is the seam that makes a connected call renderable without one. The live view model
    /// needs a `MatrixRtcCall` to produce tiles, and that class wraps handles from the Rust core and
    /// cannot be constructed in a test. The view state it projects into is a plain struct, so a
    /// preview skips the projection and writes the answer. Tiles claiming video draw their avatar,
    /// because there is no call to pull frames from, which is what a snapshot wants anyway.
    public static func preview(state: ElementCallScreenViewState,
                               style: ElementCallStyle = .stock) -> ElementCallScreenContext {
        ElementCallScreenContext(viewState: state, style: style)
    }
    
    public func send(viewAction: ElementCallScreenViewAction) {
        handler?(viewAction)
    }
}

/// Projects the session-scoped ``ElementCallController`` into a view state. The controller owns the
/// call; this only renders it and forwards taps.
///
/// It reads the controller directly rather than subclassing a host view-model base class, because
/// the controller is already observable and the extra indirection only made sense inside the host's
/// own architecture.
@MainActor
public final class ElementCallScreenViewModel {
    public let context: ElementCallScreenContext
    
    /// The call whose frames the tiles draw; nil until media is connected.
    public var call: MatrixRtcCall? {
        controller.call
    }
    
    /// Placed behind the spotlight tile so the system can start Picture in Picture from it.
    public var pictureInPictureSourceView: UIView {
        controller.pictureInPictureSourceView
    }
    
    private let controller: ElementCallController
    private var observationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var profiles: [String: ElementCallMemberProfile] = [:]
    private var hasRequestedDismissal = false
    
    public init(controller: ElementCallController) {
        self.controller = controller
        let room = controller.room
        profiles = room?.memberProfiles ?? [:]
        context = ElementCallScreenContext(viewState: .init(roomName: room?.displayName ?? "",
                                                            isDirect: room?.isDirect ?? false),
                                           style: controller.style)
        context.handler = { [weak self] action in self?.process(viewAction: action) }
        
        if let room {
            room.displayNamePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] name in self?.context.viewState.roomName = name }
                .store(in: &cancellables)
            
            room.isDirectPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] isDirect in self?.context.viewState.isDirect = isDirect }
                .store(in: &cancellables)
            
            room.memberProfilesPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] profiles in
                    self?.profiles = profiles
                    self?.refresh()
                }
                .store(in: &cancellables)
        }
        
        observe()
    }
    
    private func process(viewAction: ElementCallScreenViewAction) {
        switch viewAction {
        case .toggleMicrophone:
            controller.setMicrophoneMuted(!(controller.call?.isMicrophoneMuted ?? false))
        case .toggleCamera:
            controller.setCameraEnabled(!(controller.call?.isCameraEnabled ?? false))
        case .switchCamera:
            controller.switchCamera()
        case .toggleScreenShare:
            controller.setScreenShareEnabled(!(controller.call?.isScreenSharing ?? false))
        case .toggleLoudspeaker:
            controller.setLoudspeaker(!controller.isLoudspeaker)
        case .toggleTileStats:
            controller.toggleTileStats()
        case .toggleAudioTestTone:
            controller.setAudioTestToneEnabled(!(controller.call?.isAudioTestToneEnabled ?? false))
        case .minimize:
            controller.requestMinimize()
        case .hangUp:
            controller.hangUp()
        case .dismiss:
            controller.reset()
        }
    }
    
    // MARK: - Private
    
    /// Re-reads the controller's snapshot whenever anything it, or the call, publishes changes.
    private func observe() {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        self.refresh()
                    } onChange: {
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    private func refresh() {
        var state = context.viewState
        state.connection = controller.connection
        state.connectedAt = controller.connectedAt
        state.isLoudspeaker = controller.isLoudspeaker
        state.isTileStatsVisible = controller.isTileStatsVisible
        state.areTileStatsAvailable = controller.options.areTileStatsAvailable
        state.isMaximized = controller.isMaximized
        state.memberCount = controller.session?.memberCount ?? 0
        state.spotlightMemberID = controller.spotlightMemberID
        
        if let message = controller.errorMessage {
            context.alertInfo = ElementCallAlert(title: context.style.strings.error, message: message)
            controller.errorMessage = nil
        }
        
        guard let call = controller.call else {
            state.tiles = []
            context.viewState = state
            // The call object is gone once the call ended, so this must come after the state is
            // published but still run on the ended transition.
            if case .ended = controller.connection, !hasRequestedDismissal {
                hasRequestedDismissal = true
            }
            return
        }
        
        state.isMicrophoneMuted = call.isMicrophoneMuted
        state.isCameraEnabled = call.isCameraEnabled
        state.isFrontCamera = call.isFrontCamera
        state.isScreenSharing = call.isScreenSharing
        state.isMediaDegraded = call.isMediaDegraded
        state.isAudioTestToneEnabled = call.isAudioTestToneEnabled
        
        state.tiles = call.participants.map { participant in
            let profile = profiles[participant.userID]
            let stats = call.receiveStats[participant.memberID]
            return ElementCallTile(memberID: participant.memberID,
                                   userID: participant.userID,
                                   displayName: participant.isLocal ? context.style.strings.you : (profile?.displayName ?? participant.userID),
                                   avatarURL: profile?.avatarURL,
                                   isLocal: participant.isLocal,
                                   isMicrophoneMuted: participant.isLocal ? call.isMicrophoneMuted : !participant.isPublishing(.microphone),
                                   hasMicrophone: participant.isLocal || participant.stream(.microphone) != nil,
                                   hasVideo: participant.isLocal ? call.isCameraEnabled : participant.isPublishing(.camera),
                                   isScreenSharing: participant.isPublishing(.screenShare),
                                   isSpeaking: call.activeSpeakerIDs.contains(participant.memberID),
                                   hasHandRaised: participant.handRaisedAt != nil,
                                   isFrontCamera: call.isFrontCamera,
                                   audioLevel: call.audioLevels[participant.memberID]?.level ?? 0,
                                   stats: controller.isTileStatsVisible
                                       ? Self.describe(stats,
                                                       hasMicrophone: participant.isLocal || participant.stream(.microphone) != nil,
                                                       encryption: call.frameEncryption[participant.memberID],
                                                       video: call.videoInfo(memberID: participant.memberID),
                                                       requested: participant.isLocal ? nil : call.requestedVideoConstraints(memberID: participant.memberID))
                                       : nil)
        }
        
        context.viewState = state
    }
    
    private static func describe(_ stats: MatrixRtcReceiveStats?,
                                 hasMicrophone: Bool,
                                 encryption: MatrixRtcFrameEncryptionState?,
                                 video: MatrixRtcVideoInfo?,
                                 requested: MatrixRtcVideoConstraints?) -> String {
        var lines = [String]()
        // The badge says muted for this too; here "they muted" and "we were never given their
        // audio" are different answers, and the far end hears them fine in the second case.
        if !hasMicrophone {
            lines.append("NO MIC STREAM")
        }
        if let video {
            lines.append("\(video.width)x\(video.height) @ \(video.framesPerSecond) fps")
        } else {
            lines.append("no video")
        }
        if let requested {
            if let size = requested.pixelSize, requested.isVisible {
                lines.append("asked \(Int(size.width))x\(Int(size.height))")
            } else {
                lines.append(requested.isVisible ? "asked auto" : "asked hidden")
            }
        }
        if let encryption {
            lines.append("e2ee: \(encryption)")
        }
        if let stats {
            lines.append("pkts \(stats.packetsReceived) lost \(stats.packetsLost)")
            lines.append("frames \(stats.framesDecoded) dropped \(stats.framesDropped)")
            if let concealed = stats.concealedFraction {
                lines.append(String(format: "concealed %.0f%%", concealed * 100))
            }
        }
        return lines.joined(separator: "\n")
    }
}
