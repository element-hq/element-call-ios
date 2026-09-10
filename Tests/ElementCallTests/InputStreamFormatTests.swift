//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementCallKit
import Testing

struct InputStreamFormatTests {
    @Test(arguments: [8000.0, 16000.0, 24000.0, 44100.0, 48000.0], [1, 2, 4])
    func packingRoundTrips(sampleRate: Double, channelCount: Int) {
        for isInterleaved in [true, false] {
            let format = InputStreamFormat(channelCount: channelCount,
                                           isInterleaved: isInterleaved,
                                           sampleRate: sampleRate)
            #expect(InputStreamFormat(packed: format.packed) == format)
        }
    }
    
    @Test
    func unknownRoundTripsAndReadsAsNotYetKnown() {
        let unknown = InputStreamFormat(packed: InputStreamFormat.unknown.packed)
        #expect(unknown == .unknown)
        // The render path keys off this to drop audio rather than resample by a guess.
        #expect(unknown.sampleRate == 0)
    }
    
    @Test
    func neverDecodesAChannelCountOfZero() {
        // A stride of zero would make the render path read the same sample forever; a garbage word
        // has to degrade to a harmless mono read instead.
        #expect(InputStreamFormat(packed: 0).channelCount == 1)
        #expect(InputStreamFormat(packed: .max).channelCount >= 1)
    }
    
    /// The guard that stands between an inactive audio session and an uncatchable AVFAudio
    /// exception. An iOS app running on macOS never gets CallKit's activation, so the input node
    /// reports 0 Hz forever, and connecting a node to that format kills the process.
    @Test
    func aFormatFromAnInactiveSessionIsNotUsable() {
        #expect(!InputStreamFormat.unknown.isUsable)
        #expect(!InputStreamFormat(channelCount: 2, isInterleaved: false, sampleRate: 0).isUsable)
        #expect(!InputStreamFormat(channelCount: 0, isInterleaved: false, sampleRate: 48000).isUsable)
    }
    
    @Test
    func aRealHardwareFormatIsUsable() {
        #expect(InputStreamFormat(channelCount: 1, isInterleaved: false, sampleRate: 48000).isUsable)
        #expect(InputStreamFormat(channelCount: 2, isInterleaved: true, sampleRate: 44100).isUsable)
    }
    
    @Test
    func carriesFieldsIndependently() {
        let format = InputStreamFormat(channelCount: 2, isInterleaved: true, sampleRate: 44100)
        let decoded = InputStreamFormat(packed: format.packed)
        #expect(decoded.channelCount == 2)
        #expect(decoded.isInterleaved)
        #expect(decoded.sampleRate == 44100)
    }
}
