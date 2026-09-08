//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVKit
import Combine
import ElementCallKit
import Observation
import SwiftUI

enum ElementCallPictureInPictureAction: Sendable {
    case started
    /// The user tapped the window to come back to the app.
    case restoreRequested
    /// The user closed the window: the call should end.
    case closed
    case failed
}

/// The system Picture in Picture window for a video call, showing the spotlight member through an
/// `AVSampleBufferDisplayLayer` (Metal must not draw while the app is inactive).
///
/// The source view is a stable `UIView` the call screen places behind its spotlight tile: AVKit needs it
/// on screen to start automatically when the app is backgrounded, and uses its frame for the shrink.
final class ElementCallPictureInPictureController: NSObject, AVPictureInPictureControllerDelegate {
    private enum StopReason {
        case restore, userClosed, programmatic
    }
    
    /// Place this view in the full-screen call layout; it is created once per controller.
    let sourceView = UIView()
    
    var actions: AnyPublisher<ElementCallPictureInPictureAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    private let actionsSubject = PassthroughSubject<ElementCallPictureInPictureAction, Never>()
    
    /// Set by the controller that owns this; nil until then, which only costs a few log lines.
    var logger: (any ElementCallLogging)?
    
    var isActive: Bool {
        pictureInPictureController?.isPictureInPictureActive ?? false
    }
    
    var isPossible: Bool {
        pictureInPictureController?.isPictureInPicturePossible ?? false
    }
    
    var isBound: Bool {
        call != nil
    }
    
    private let contentViewController = AVPictureInPictureVideoCallViewController()
    private let videoView = SampleBufferVideoView()
    private let placeholderHost = UIHostingController(rootView: AnyView(EmptyView()))
    /// Builds the avatar shown when the member in the window has no video (nil = nobody to show).
    var placeholderProvider: ((String?) -> AnyView)?
    private var pictureInPictureController: AVPictureInPictureController?
    private var stopReason: StopReason?
    private var attached: (memberID: String, kind: MatrixRtcStreamKind)?
    private var observationTask: Task<Void, Never>?
    private var automaticStartTask: Task<Void, Never>?
    private weak var call: MatrixRtcCall?
    private var spotlightProvider: (() -> String?)?
    
    override init() {
        super.init()
        sourceView.backgroundColor = .clear
        sourceView.isUserInteractionEnabled = false
        let container = UIView()
        container.backgroundColor = .black
        let placeholderView: UIView = placeholderHost.view
        for subview in [videoView, placeholderView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
            NSLayoutConstraint.activate([
                subview.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                subview.topAnchor.constraint(equalTo: container.topAnchor),
                subview.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }
        placeholderHost.view.backgroundColor = .clear
        placeholderHost.view.isHidden = true
        contentViewController.view = container
        contentViewController.addChild(placeholderHost)
        placeholderHost.didMove(toParent: contentViewController)
        contentViewController.preferredContentSize = CGSize(width: 1080, height: 1920)
        videoView.onAspectChange = { [weak self] aspect in
            self?.applyPreferredSize(aspect: aspect)
        }
        videoView.onPixelSizeChange = { [weak self] size in
            guard let self, let call, let attached else { return }
            call.reportDrawnSize(size, slot: videoView.slot, memberID: attached.memberID, kind: attached.kind)
        }
    }
    
    /// Binds to a call; the spotlight provider is read whenever the call's video state changes.
    func bind(call: MatrixRtcCall, spotlightProvider: @escaping () -> String?) {
        self.call = call
        self.spotlightProvider = spotlightProvider
        if pictureInPictureController == nil, AVPictureInPictureController.isPictureInPictureSupported() {
            let controller = AVPictureInPictureController(contentSource: .init(activeVideoCallSourceView: sourceView,
                                                                               contentViewController: contentViewController))
            controller.delegate = self
            pictureInPictureController = controller
        }
        observeAutomaticStart()
    }
    
    /// Leaving the app during a full-screen video call shrinks it to the window, like FaceTime (subject
    /// to the system's "Start PiP Automatically" setting); an audio-only call keeps the bar instead.
    private func observeAutomaticStart() {
        automaticStartTask?.cancel()
        automaticStartTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        self.pictureInPictureController?.canStartPictureInPictureAutomaticallyFromInline = self.call?.hasVideo ?? false
                    } onChange: {
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    func start() {
        guard let pictureInPictureController, !pictureInPictureController.isPictureInPictureActive else { return }
        stopReason = nil
        // The size is only honoured when set before the window appears, and the first frame arrives after.
        if let call, let candidate = call.pictureInPictureCandidate(spotlightMemberID: spotlightProvider?()),
           let aspect = call.videoAspect(memberID: candidate.memberID, kind: candidate.kind) {
            applyPreferredSize(aspect: aspect)
        }
        pictureInPictureController.startPictureInPicture()
    }
    
    private func applyPreferredSize(aspect: CGFloat) {
        let size = aspect >= 1
            ? CGSize(width: 1080, height: (1080 / aspect).rounded())
            : CGSize(width: (1080 * aspect).rounded(), height: 1080)
        guard contentViewController.preferredContentSize != size else { return }
        logger?.log(.info, "picture in picture aspect \(aspect), preferred size \(size)")
        contentViewController.preferredContentSize = size
    }
    
    /// Ends the window from our side (restoring the screen, or the call ended).
    func stop() {
        guard let pictureInPictureController, pictureInPictureController.isPictureInPictureActive else { return }
        stopReason = .programmatic
        pictureInPictureController.stopPictureInPicture()
    }
    
    func unbind() {
        stop()
        detach()
        observationTask?.cancel()
        observationTask = nil
        automaticStartTask?.cancel()
        automaticStartTask = nil
        call = nil
        pictureInPictureController = nil
    }
    
    // MARK: - AVPictureInPictureControllerDelegate
    
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            // Attach before the screen collapses so the spotlight stream never goes idle in between.
            self.stopReason = nil
            self.observeVideoSource()
        }
    }
    
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            logger?.log(.info, "picture in picture started")
            self.actionsSubject.send(.started)
        }
    }
    
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        // The handler is not Sendable, so it is answered right here; the screen restores on the main
        // actor a moment later, which is what the system animates towards anyway.
        Task { @MainActor in
            self.stopReason = .restore
            self.actionsSubject.send(.restoreRequested)
        }
        completionHandler(true)
    }
    
    nonisolated func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            // Neither a restore nor our own stop: the user tapped the close button.
            if self.stopReason == nil {
                self.stopReason = .userClosed
            }
        }
    }
    
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            let reason = self.stopReason
            self.stopReason = nil
            self.observationTask?.cancel()
            self.observationTask = nil
            self.detach()
            logger?.log(.info, "picture in picture stopped (\(reason.map { "\($0)" } ?? "unknown"))")
            if reason == .userClosed {
                self.actionsSubject.send(.closed)
            }
        }
    }
    
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in
            logger?.log(.warning, "picture in picture failed to start: \(error)")
            self.detach()
            self.actionsSubject.send(.failed)
        }
    }
    
    // MARK: - Private
    
    /// Follows the call's video state while the window is up, switching what it shows.
    private func observeVideoSource() {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        self.updateVideoSource()
                    } onChange: {
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    private func updateVideoSource() {
        guard let call else { return }
        let candidate = call.pictureInPictureCandidate(spotlightMemberID: spotlightProvider?())
        if candidate == nil {
            // Nobody has video: show who we are in the call with instead of a black window.
            let shown = spotlightProvider?() ?? call.participants.first { !$0.isLocal }?.memberID
            placeholderHost.rootView = placeholderProvider?(shown) ?? AnyView(Color.black)
            placeholderHost.view.isHidden = false
        } else {
            placeholderHost.view.isHidden = true
        }
        guard candidate?.memberID != attached?.memberID || candidate?.kind != attached?.kind else { return }
        detach()
        guard let candidate else { return }
        if let aspect = call.videoAspect(memberID: candidate.memberID, kind: candidate.kind) {
            applyPreferredSize(aspect: aspect)
        }
        if candidate.memberID == call.localMemberID {
            call.localVideo.attach(videoView.slot)
        } else {
            call.attachVideo(videoView.slot, memberID: candidate.memberID, kind: candidate.kind)
        }
        attached = candidate
        logger?.log(.info, "picture in picture showing \(candidate.memberID) (\(candidate.kind))")
    }
    
    private func detach() {
        guard let attached, let call else { return }
        if attached.memberID == call.localMemberID {
            call.localVideo.detach(videoView.slot)
        } else {
            call.detachVideo(videoView.slot, memberID: attached.memberID, kind: attached.kind)
        }
        self.attached = nil
        videoView.clear()
    }
}
