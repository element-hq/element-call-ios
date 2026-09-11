//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import CoreVideo
@testable import ElementCallKit
import Testing

/// The repacker copies row by row: padded strides must not leak into the picture, and chroma is
/// half resolution rounded up.
nonisolated struct I420RepackerTests {
    @Test
    func repacksPaddedNV12IntoTightPlanes() throws {
        let width = 6
        let height = 4
        let pixelBuffer = try makeNV12(width: width, height: height)
        
        let planes = try #require(I420Repacker.repack(pixelBuffer))
        
        #expect(planes.width == width)
        #expect(planes.height == height)
        #expect(planes.y.count == width * height)
        #expect(planes.u.count == 3 * 2)
        #expect(planes.v.count == 3 * 2)
        // Y is row * 16 + column, so a stride leak would shift rows.
        #expect(Array(planes.y.prefix(width)) == [0, 1, 2, 3, 4, 5])
        #expect(Array(planes.y.suffix(width)) == [48, 49, 50, 51, 52, 53])
        // Cb is 100 + index, Cr is 200 + index, interleaved in the source.
        #expect(Array(planes.u) == [100, 101, 102, 103, 104, 105])
        #expect(Array(planes.v) == [200, 201, 202, 203, 204, 205])
    }
    
    @Test
    func oddWidthRoundsChromaUp() throws {
        let pixelBuffer = try makeNV12(width: 5, height: 3)
        let planes = try #require(I420Repacker.repack(pixelBuffer))
        #expect(planes.chromaWidth == 3)
        #expect(planes.chromaHeight == 2)
        #expect(planes.u.count == 6)
    }
    
    @Test
    func downscalesToTheLongEdge() throws {
        let pixelBuffer = try makeNV12(width: 64, height: 32)
        let planes = try #require(I420Repacker.repack(pixelBuffer, maxLongEdge: 32))
        #expect(planes.width == 32)
        #expect(planes.height == 16)
        #expect(planes.y.count == 32 * 16)
        #expect(planes.u.count == 16 * 8)
    }
    
    /// An NV12 buffer with a padded stride whose Y is `row * 16 + column` and whose chroma samples are numbered.
    private func makeNV12(width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferBytesPerRowAlignmentKey: 64]
        let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, attributes as CFDictionary, &pixelBuffer)
        let buffer = try #require(status == kCVReturnSuccess ? pixelBuffer : nil)
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let yBase = try #require(CVPixelBufferGetBaseAddressOfPlane(buffer, 0)).assumingMemoryBound(to: UInt8.self)
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        if width % 64 != 0 {
            #expect(yStride > width, "the test relies on a padded stride")
        }
        for row in 0..<height {
            for column in 0..<width {
                yBase[row * yStride + column] = UInt8(truncatingIfNeeded: row * 16 + column)
            }
        }
        
        let uvBase = try #require(CVPixelBufferGetBaseAddressOfPlane(buffer, 1)).assumingMemoryBound(to: UInt8.self)
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        let chromaWidth = (width + 1) / 2
        let chromaHeight = (height + 1) / 2
        for row in 0..<chromaHeight {
            for column in 0..<chromaWidth {
                let index = row * chromaWidth + column
                uvBase[row * uvStride + column * 2] = UInt8(truncatingIfNeeded: 100 + index)
                uvBase[row * uvStride + column * 2 + 1] = UInt8(truncatingIfNeeded: 200 + index)
            }
        }
        return buffer
    }
}
