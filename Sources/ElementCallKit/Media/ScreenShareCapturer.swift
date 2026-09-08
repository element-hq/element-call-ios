//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import CoreMedia
import MatrixRtc
import ReplayKit
import Synchronization

/// In-app screen capture through ReplayKit: no extension, no app-group IPC, captures this app only.
/// A system-wide share needs a Broadcast Upload Extension (documented follow-up).
///
/// A screen is mostly still and every pixel is repacked on the way out, so this caps the long edge
/// and halves the frame rate.
final nonisolated class ScreenShareCapturer: @unchecked Sendable {
    static let maxLongEdge = 1280
    static let frameInterval: TimeInterval = 1.0 / 15.0
    
    private let state = Mutex<State>(.init())
    
    private struct State {
        var track: FfiLocalTrack?
        var lastTimestamp: TimeInterval = 0
        var isCapturing = false
    }
    
    var isCapturing: Bool {
        state.withLock { $0.isCapturing }
    }
    
    func start(track: FfiLocalTrack) async throws {
        state.withLock { state in
            state.track = track
            state.isCapturing = true
        }
        let recorder = RPScreenRecorder.shared()
        // ReplayKit answers -5803 "Recording failed to start" for many reasons it will not name;
        // the two it does expose are worth having in the error.
        guard recorder.isAvailable else {
            state.withLock { $0.isCapturing = false }
            throw MatrixRtcError.media("Screen recording is unavailable (restricted, or another app is recording)")
        }
        if recorder.isRecording {
            MatrixRtcLog.warning("Screen recorder still reports an active recording before capture starts")
        }
        recorder.isMicrophoneEnabled = false
        // ReplayKit calls back on its own queues. The sample handler is a method reference: a
        // closure literal here would inherit the caller's actor and trap, and marking it `@Sendable`
        // hands its non-Sendable sample over as `sending`, so the bridged block over-releases it.
        // The completion handler only carries an Error and can be `@Sendable`. ReplayKit may also
        // call a completion handler more than once, and resuming twice traps.
        let resume = ResumeOnce()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            recorder.startCapture(handler: handleCapture, completionHandler: { @Sendable error in
                resume.perform {
                    if let error {
                        continuation.resume(throwing: MatrixRtcError.media("Screen capture failed to start: \(error)"))
                    } else {
                        MatrixRtcLog.info("Screen capture started")
                        continuation.resume()
                    }
                }
            })
        }
    }
    
    func stop() async {
        let wasCapturing = state.withLock { state -> Bool in
            defer {
                state.track = nil
                state.isCapturing = false
            }
            return state.isCapturing
        }
        guard wasCapturing else { return }
        let resume = ResumeOnce()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            RPScreenRecorder.shared().stopCapture { @Sendable error in
                if let error {
                    MatrixRtcLog.warning("Screen capture stop error: \(error)")
                }
                resume.perform { continuation.resume() }
            }
        }
        MatrixRtcLog.info("Screen capture stopped")
    }
    
    private func handleCapture(_ sampleBuffer: CMSampleBuffer, _ type: RPSampleBufferType, _ error: Error?) {
        if let error {
            MatrixRtcLog.warning("Screen capture error: \(error)")
        }
        guard type == .video else { return }
        handle(sampleBuffer)
    }
    
    private func handle(_ sampleBuffer: CMSampleBuffer) {
        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        let track = state.withLock { state -> FfiLocalTrack? in
            guard state.isCapturing, timestamp - state.lastTimestamp >= Self.frameInterval else { return nil }
            state.lastTimestamp = timestamp
            return state.track
        }
        guard let track, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let planes = I420Repacker.repack(pixelBuffer, maxLongEdge: Self.maxLongEdge) else { return }
        do {
            try track.captureVideo(frame: planes.ffiFrame(rotation: .deg0, timestampUs: Int64(timestamp * 1_000_000)))
        } catch {
            // A frame in flight while the share is being unpublished lands here; expected once per stop.
            MatrixRtcLog.debug("Screen share captureVideo failed: \(error)")
        }
    }
}

/// Runs its body the first time only, from any thread.
private final nonisolated class ResumeOnce: Sendable {
    private let done = Mutex(false)
    
    func perform(_ body: @Sendable () -> Void) {
        let first = done.withLock { done -> Bool in
            defer { done = true }
            return !done
        }
        if first {
            body()
        }
    }
}
