//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVFoundation

/// Calls `body` with an `AudioBufferList` wrapping `samples`, the way an IO unit would.
///
/// Only the first buffer is populated: the render paths under test read channel 0 and stride past
/// the rest, which is exactly the behaviour worth pinning.
func withAudioBufferList<Result>(_ samples: [Float],
                                 channelCount: Int = 1,
                                 body: (UnsafePointer<AudioBufferList>) -> Result) -> Result {
    var samples = samples
    return samples.withUnsafeMutableBufferPointer { buffer in
        var list = AudioBufferList(mNumberBuffers: 1,
                                   mBuffers: AudioBuffer(mNumberChannels: UInt32(channelCount),
                                                         mDataByteSize: UInt32(buffer.count * MemoryLayout<Float>.size),
                                                         mData: buffer.baseAddress))
        return withUnsafePointer(to: &list) { body($0) }
    }
}
