//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import MatrixRtc
import Observation
import Synchronization
import UIKit

/// The local camera, from a lobby's preview into the call that adopts it (045 R49).
///
/// Owned by whoever owns the attempt rather than by the media session, because the session does not
/// exist until the join and the preview runs before it. A session made at Join publishes a track
/// and attaches it to this capture, which is already running at the format the same function
/// chose, so the device is opened once from the lobby into the call: no restart, no black frame, no
/// indicator blinking at the moment the user is watching the picture move.
@MainActor
@Observable
public final class MatrixRTCLocalCamera {
    /// The self view, fed by every frame the camera takes, published or not.
    public let video = LocalVideoFanOut()
    /// Whether the device is open, which is what puts the system's camera indicator on.
    public private(set) var isCapturing = false
    /// The facing the user chose, carried into the call with the object (045 R15). Each frame
    /// carries its own mirroring from it, so the preview and our tile cannot disagree (R16, R38).
    public private(set) var isFrontFacing = true
    /// How many times the device has been opened: a test's view of R49's "no camera restart".
    public private(set) var startCount = 0
    
    /// Whether the device has both a front and a back camera, which is when a flip button changes
    /// anything (019 R24, 045 R12).
    public static var canSwitch: Bool {
        CameraCapturer.hasFrontAndBack
    }
    
    /// Whether starting opens the device. Off for a test and for the harness, which have no camera
    /// to open and draw the test pattern instead; the state still changes, so what follows it can
    /// be checked.
    public let capturesCamera: Bool
    
    /// What also wants each frame besides the self view: the media session's meter.
    @ObservationIgnored private let frameObserver = FrameObserverBox()
    @ObservationIgnored private var orientation: UIInterfaceOrientation = .portrait
    
    @ObservationIgnored private lazy var capturer: CameraCapturer = {
        let video = video
        let frameObserver = frameObserver
        return CameraCapturer { frame in
            video.offer(frame)
            frameObserver.observe(frame)
        }
    }()
    
    public init(capturesCamera: Bool = true) {
        self.capturesCamera = capturesCamera
    }
    
    /// Opens the device with no track: the frames reach the self view only. Does nothing while it is
    /// already open.
    public func start() throws {
        guard !isCapturing else { return }
        if capturesCamera {
            capturer.setInterfaceOrientation(orientation)
            try capturer.startCapture()
            isFrontFacing = capturer.isFrontFacing
        }
        startCount += 1
        isCapturing = true
        MatrixRTCLog.info("Local camera started (\(isFrontFacing ? "front" : "back"))")
    }
    
    /// Releases the device, and with it the indicator. A published track stops receiving frames too.
    public func stop() {
        guard isCapturing else { return }
        if capturesCamera {
            capturer.stop()
        }
        isCapturing = false
        MatrixRTCLog.info("Local camera stopped")
    }
    
    /// Asynchronous by nature: one camera closes and another opens. Only while capturing, which is
    /// the only time the flip button is shown.
    public func switchCamera() throws {
        guard capturesCamera else {
            isFrontFacing.toggle()
            return
        }
        isFrontFacing = try capturer.switchCamera()
    }
    
    /// Frames carry the orientation as metadata; pixels are not rotated. Kept while stopped, so a
    /// start tags its first frame correctly.
    public func setInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        self.orientation = orientation
        guard capturesCamera else { return }
        capturer.setInterfaceOrientation(orientation)
    }
    
    // MARK: - The media session's side
    
    /// The size a track published now has to declare: what the capture runs at, or will run at.
    var publishedSize: CameraCaptureFormat.Size {
        capturesCamera ? capturer.publishedSize : CameraCaptureFormat.fallbackOutput
    }
    
    /// The track receives every frame from here on. Starts the capture if it was not running; one
    /// already running is left alone, which is the point (045 R49).
    func publish(to track: FfiLocalTrack) throws {
        if capturesCamera {
            capturer.attach(track: track)
        }
        do {
            try start()
        } catch {
            if capturesCamera {
                capturer.detach()
            }
            throw error
        }
    }
    
    func setFrameObserver(_ observe: (@Sendable (MatrixRTCVideoFrame) -> Void)?) {
        frameObserver.set(observe)
    }
    
    /// The system took the camera away or gave it back. Without the multitasking-camera entitlement
    /// this fires on every backgrounding.
    func setOnInterruption(_ handler: (@Sendable (Bool) -> Void)?) {
        guard capturesCamera else { return }
        capturer.onInterruption = handler
    }
}

/// Read on the capture queue, written on the main actor. The closure is boxed in a struct rather
/// than stored bare in the `Mutex`, for the reason AGENTS.md gives.
private final nonisolated class FrameObserverBox: Sendable {
    private struct Observer {
        let observe: @Sendable (MatrixRTCVideoFrame) -> Void
    }
    
    private let observer = Mutex<Observer?>(nil)
    
    func set(_ observe: (@Sendable (MatrixRTCVideoFrame) -> Void)?) {
        observer.withLock { $0 = observe.map(Observer.init) }
    }
    
    func observe(_ frame: MatrixRTCVideoFrame) {
        observer.withLock { $0 }?.observe(frame)
    }
}
