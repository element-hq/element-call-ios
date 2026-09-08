//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import CoreMedia
import CoreVideo
@testable import ElementCallKit
import Testing

/// The packer is the inverse of the repacker: I420 → NV12 → I420 must be the identity.
struct NV12PackerTests {
    @Test
    func roundTripsThroughTheRepacker() throws {
        let width = 6
        let height = 4
        let y = Data((0..<(width * height)).map { UInt8($0) })
        let u = Data((0..<6).map { UInt8(100 + $0) })
        let v = Data((0..<6).map { UInt8(200 + $0) })
        let planes = I420Repacker.Planes(width: width, height: height, y: y, u: u, v: v)
        let frame = MatrixRtcVideoFrame(planes: planes, rotation: .deg90, isMirrored: true)
        
        let sampleBuffer = try #require(NV12Packer().makeSampleBuffer(from: frame))
        let pixelBuffer = try #require(CMSampleBufferGetImageBuffer(sampleBuffer))
        #expect(CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        
        let unpacked = try #require(I420Repacker.repack(pixelBuffer))
        #expect(unpacked.y == y)
        #expect(unpacked.u == u)
        #expect(unpacked.v == v)
        
        let attachments = try #require(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]])
        #expect(attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] as? Bool == true)
    }
}
