//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementCallKit
import Foundation
import Synchronization
import Testing

struct VideoFrameSlotTests {
    /// The frame callback used to be reabstracted and re-stored on every offer, growing a chain of
    /// thunks that overflowed the stack after a few minutes of video. A hundred thousand offers is
    /// what a five-minute call delivers; invoking and releasing the handler must both stay flat.
    @Test
    func frameCallbackDoesNotGrowWithEveryOffer() {
        let slot = VideoFrameSlot()
        let count = Mutex(0)
        slot.setOnFrame { count.withLock { $0 += 1 } }
        let frame = MatrixRtcVideoFrame(planes: .init(width: 2, height: 2, y: Data(count: 4), u: Data(count: 1), v: Data(count: 1)),
                                        rotation: .deg0,
                                        isMirrored: false)
        
        for _ in 0..<100_000 {
            slot.offer(frame)
        }
        #expect(count.withLock { $0 } == 100_000)
        #expect(slot.take() === frame)
        #expect(slot.take() == nil)
        
        slot.setOnFrame(nil)
        slot.offer(frame)
        #expect(count.withLock { $0 } == 100_000)
    }
}
