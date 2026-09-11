//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVFoundation
@testable import ElementCallKit
import Testing

nonisolated struct AudioPlaybackRendererTests {
    /// As with ``MicrophoneTapTests``, the initialiser is the assertion: a renderer is built from a
    /// ring and a prefill and cannot reach the engine or the sink.
    private func makeRenderer(prefill: Int = 4, ringCapacity: Int = 16384) -> (AudioPlaybackRenderer, PCMRingBuffer) {
        let ring = PCMRingBuffer(capacity: ringCapacity)
        return (AudioPlaybackRenderer(ring: ring, prefill: prefill), ring)
    }
    
    private func fill(_ ring: PCMRingBuffer, _ samples: [Int16]) {
        samples.withUnsafeBufferPointer { ring.write($0) }
    }
    
    private func render(_ renderer: AudioPlaybackRenderer, frames: Int) -> [Float] {
        var output = [Float](repeating: .nan, count: frames)
        output.withUnsafeMutableBufferPointer { buffer in
            var list = AudioBufferList(mNumberBuffers: 1,
                                       mBuffers: AudioBuffer(mNumberChannels: 1,
                                                             mDataByteSize: UInt32(frames * MemoryLayout<Float>.size),
                                                             mData: buffer.baseAddress))
            withUnsafeMutablePointer(to: &list) {
                _ = renderer.render(frameCount: AVAudioFrameCount(frames), audioBufferList: $0)
            }
        }
        return output
    }
    
    @Test
    func playsSilenceUntilPrefilled() {
        let (renderer, ring) = makeRenderer(prefill: 8)
        fill(ring, [Int16](repeating: .max, count: 4))
        
        #expect(render(renderer, frames: 4) == [0, 0, 0, 0])
        
        // Crossing the prefill threshold is what starts playback.
        fill(ring, [Int16](repeating: .max, count: 4))
        #expect(render(renderer, frames: 4).allSatisfy { $0 == 1 })
    }
    
    @Test
    func convertsInt16ToNormalisedFloats() {
        let (renderer, ring) = makeRenderer(prefill: 0)
        fill(ring, [0, Int16.max, -Int16.max])
        
        let output = render(renderer, frames: 3)
        #expect(output[0] == 0)
        #expect(output[1] == 1)
        #expect(output[2] == -1)
    }
    
    @Test
    func countsAnUnderrunAndZeroFillsTheShortfall() {
        let (renderer, ring) = makeRenderer(prefill: 0)
        fill(ring, [Int16.max, Int16.max])
        
        let output = render(renderer, frames: 4)
        #expect(output == [1, 1, 0, 0])
        #expect(renderer.underruns.load(ordering: .relaxed) == 1)
    }
    
    @Test
    func fallsBackToPrefillingAfterAFullyEmptyRead() {
        let (renderer, ring) = makeRenderer(prefill: 4)
        fill(ring, [Int16](repeating: .max, count: 4))
        _ = render(renderer, frames: 4)
        
        // Nothing left: the renderer un-primes, so it waits for the prefill again rather than
        // stuttering one frame at a time.
        #expect(render(renderer, frames: 4) == [0, 0, 0, 0])
        #expect(renderer.underruns.load(ordering: .relaxed) == 1)
        
        fill(ring, [Int16](repeating: .max, count: 2))
        #expect(render(renderer, frames: 2) == [0, 0])
    }
    
    @Test
    func playsSilenceAfterDetach() {
        let (renderer, ring) = makeRenderer(prefill: 0)
        fill(ring, [Int16](repeating: .max, count: 4))
        renderer.detach()
        
        #expect(render(renderer, frames: 4) == [0, 0, 0, 0])
    }
    
    @Test
    func servesACallbackLargerThanTheScratchBufferInPasses() {
        let count = AudioPlaybackRenderer.scratchCapacity + 512
        let (renderer, ring) = makeRenderer(prefill: 0, ringCapacity: count * 2)
        let samples = (0..<count).map { Int16(truncatingIfNeeded: $0 % 32767) }
        fill(ring, samples)
        
        let output = render(renderer, frames: count)
        let expected = samples.map { Float($0) / Float(Int16.max) }
        #expect(output == expected)
        #expect(renderer.underruns.load(ordering: .relaxed) == 0)
    }
}
