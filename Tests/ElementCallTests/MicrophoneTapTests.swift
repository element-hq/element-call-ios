//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVFoundation
@testable import ElementCallKit
import Testing

struct MicrophoneTapTests {
    /// The load-bearing line in this file is the initialiser below: a tap is built from a ring and
    /// a format snapshot and **nothing else**. The render block used to ask `CallAudioEngine` for
    /// the input format from the IO thread, which took `AVAudioEngine`'s mutex there and deadlocked
    /// hang-up against `detach`. If a change gives the tap an engine to ask, this file stops
    /// compiling — which is the regression test.
    private func makeTap(_ format: InputStreamFormat = .init(channelCount: 1,
                                                             isInterleaved: false,
                                                             sampleRate: 48000),
                         ringCapacity: Int = 16384) -> (MicrophoneTap, PCMRingBuffer) {
        let ring = PCMRingBuffer(capacity: ringCapacity)
        let snapshot = InputFormatSnapshot()
        snapshot.store(format)
        return (MicrophoneTap(ring: ring, format: snapshot), ring)
    }
    
    private func read(_ ring: PCMRingBuffer, count: Int) -> [Int16] {
        var output = [Int16](repeating: 0, count: count)
        output.withUnsafeMutableBufferPointer { ring.read(into: $0) }
        return output
    }
    
    @Test
    func convertsMonoPlanarFloatsToInt16() {
        let (tap, ring) = makeTap()
        let samples: [Float] = [0, 0.5, -0.5, 1, -1]
        
        withAudioBufferList(samples) { list in
            _ = tap.render(frameCount: AVAudioFrameCount(samples.count), audioBufferList: list)
        }
        
        #expect(ring.availableToRead == samples.count)
        #expect(read(ring, count: samples.count) == [0, 16383, -16383, 32767, -32767])
    }
    
    @Test
    func takesChannelZeroOfInterleavedStereo() {
        let (tap, ring) = makeTap(.init(channelCount: 2, isInterleaved: true, sampleRate: 48000))
        // Channel 1 is deliberately full scale: if the stride is wrong, it shows up in the output.
        let samples: [Float] = [0.5, -1, 0.25, 1, 0, -1]
        
        withAudioBufferList(samples, channelCount: 2) { list in
            _ = tap.render(frameCount: 3, audioBufferList: list)
        }
        
        #expect(read(ring, count: 3) == [16383, 8191, 0])
    }
    
    @Test
    func convertsACallbackLargerThanTheScratchBufferInPasses() {
        let count = MicrophoneTap.scratchCapacity + 904
        let (tap, ring) = makeTap(ringCapacity: count * 2)
        // A ramp, so an out-of-order or duplicated pass is visible rather than merely plausible.
        let samples = (0..<count).map { Float($0 % 1000) / 1000 }
        
        withAudioBufferList(samples) { list in
            _ = tap.render(frameCount: AVAudioFrameCount(count), audioBufferList: list)
        }
        
        #expect(ring.availableToRead == count)
        let output = read(ring, count: count)
        let expected = samples.map { Int16(max(-1, min(1, $0)) * Float(Int16.max)) }
        #expect(output == expected)
        #expect(tap.oversizedCallbacks.load(ordering: .relaxed) == 1)
    }
    
    @Test
    func writesNothingBeforeTheFormatIsKnown() {
        let (tap, ring) = makeTap(.unknown)
        
        withAudioBufferList([0.5, 0.5, 0.5]) { list in
            _ = tap.render(frameCount: 3, audioBufferList: list)
        }
        
        #expect(ring.availableToRead == 0)
    }
    
    @Test
    func writesNothingAfterStopAndResumes() {
        let (tap, ring) = makeTap()
        tap.stop()
        
        withAudioBufferList([0.5, 0.5]) { list in
            _ = tap.render(frameCount: 2, audioBufferList: list)
        }
        #expect(ring.availableToRead == 0)
        
        tap.resume()
        withAudioBufferList([0.5, 0.5]) { list in
            _ = tap.render(frameCount: 2, audioBufferList: list)
        }
        #expect(ring.availableToRead == 2)
    }
    
    /// `min(1, .nan)` yields 1 in Swift, so a NaN sample saturates rather than trapping
    /// `Int16.init` on the real-time thread. That is a property of the clamp's argument order, not
    /// of anything explicit, so it is pinned here: rewriting the clamp as `sample.clamped(to:)`
    /// would crash the audio thread on the first bad sample.
    @Test
    func saturatesRatherThanTrappingOnNaNAndOutOfRangeSamples() {
        let (tap, ring) = makeTap()
        let samples: [Float] = [.nan, 10, -10, .infinity, -.infinity]
        
        withAudioBufferList(samples) { list in
            _ = tap.render(frameCount: AVAudioFrameCount(samples.count), audioBufferList: list)
        }
        
        #expect(read(ring, count: samples.count) == [32767, 32767, -32767, 32767, -32767])
    }
    
    /// Sustained callbacks through a ring far smaller than the total, so every wrap-around is
    /// exercised and the scratch buffer is proven reusable across calls rather than only correct
    /// once.
    ///
    /// Deliberately modest: this suite runs in parallel with timing-sensitive tests elsewhere, and
    /// an iteration count high enough to time a regression starves them into failing instead.
    @Test
    func sustainsManyCallbacksWithoutGrowing() {
        let iterations = 5000
        let (tap, ring) = makeTap(ringCapacity: 2048)
        let samples = [Float](repeating: 0.25, count: 480)
        // Drained through one reused buffer, so the only allocation left in the loop would be the
        // tap's own — which is the thing under test.
        var drain = [Int16](repeating: 0, count: 480)
        var total = 0
        
        for _ in 0..<iterations {
            withAudioBufferList(samples) { list in
                _ = tap.render(frameCount: 480, audioBufferList: list)
            }
            total += drain.withUnsafeMutableBufferPointer { ring.read(into: $0) }
        }
        
        #expect(total == iterations * 480)
        #expect(drain.allSatisfy { $0 == 8191 })
        #expect(tap.oversizedCallbacks.load(ordering: .relaxed) == 0)
    }
}
