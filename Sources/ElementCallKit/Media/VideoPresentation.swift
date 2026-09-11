//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import CoreGraphics
import simd

/// How a surface is asked to present the stream it draws.
///
/// Distinct from the frame's own rotation and mirroring, which are properties of the picture rather
/// than choices about it: those come from the sender and the capturer, this comes from the view.
public nonisolated struct VideoPresentation: Equatable, Sendable {
    public enum ContentMode: Sendable {
        /// The whole picture, letterboxed. What a full-screen tile wants: somebody is actually
        /// looking at what was sent, and cropping a landscape camera to a portrait screen throws
        /// away the sides of it.
        case fit
        /// Covers the surface, overflow clipped. What a small tile wants: a grid of letterboxed
        /// cells is mostly black.
        case fill
    }
    
    public var contentMode: ContentMode
    /// 1 is the picture exactly as `contentMode` asked for it.
    public var zoom: CGFloat
    /// Display space, y down, as a fraction of the drawable: `(0.1, 0)` shifts the picture right by
    /// a tenth of the drawable's width.
    ///
    /// A fraction of the drawable rather than points or a fraction of the overflow, because that is
    /// the only form in which the gesture layer's conversion is `translation / viewSize`: free of
    /// the screen scale, and free of the content's aspect, which it otherwise learns a frame later
    /// than the renderer does and so would track the finger at the wrong speed.
    public var pan: CGSize
    
    public static let fill = VideoPresentation()
    
    public init(contentMode: ContentMode = .fill, zoom: CGFloat = 1, pan: CGSize = .zero) {
        self.contentMode = contentMode
        self.zoom = zoom
        self.pan = pan
    }
}

extension VideoPresentation {
    /// The vertex transform that takes the unit quad to where this presentation wants the picture:
    /// rotate upright, mirror if asked, scale to fit or fill, then shift by the pan.
    ///
    /// The frame's rotation is how far it must turn **clockwise** to be upright (WebRTC semantics);
    /// Metal's y axis points up, so that is a negative angle here.
    ///
    /// Pure, and separate from the renderer, because this is where "bars on the side rather than a
    /// crop" actually lives: a GPU is not needed to check it and a snapshot would only compare it
    /// approximately.
    func transform(frameWidth: Int,
                   frameHeight: Int,
                   rotation: MatrixRTCVideoRotation,
                   isMirrored: Bool,
                   drawableSize: CGSize) -> simd_float4x4 {
        let width = Float(frameWidth)
        let height = Float(frameHeight)
        let angle = -Float(rotation.rawValue) * .pi / 180
        let rotated = rotation == .deg90 || rotation == .deg270
        let contentWidth = max(1, rotated ? height : width)
        let contentHeight = max(1, rotated ? width : height)
        let drawableWidth = Float(max(1, drawableSize.width))
        let drawableHeight = Float(max(1, drawableSize.height))
        
        // Fill takes the larger factor so the drawable is covered and the overflow is clipped; fit
        // takes the smaller so the whole picture is there and the remainder stays the clear colour,
        // which is already black.
        let cover = max(drawableWidth / contentWidth, drawableHeight / contentHeight)
        let contain = min(drawableWidth / contentWidth, drawableHeight / contentHeight)
        let scale = (contentMode == .fill ? cover : contain) * max(0.01, Float(zoom))
        
        // Clamped to what the picture actually overhangs. The gesture layer clamps to the same
        // formula, but it learns a rotation or a layer switch one frame after this does: without
        // the clamp here, a sender rotating mid-pinch would drag the picture off its own edge for
        // that frame.
        let overflowX = max(0, contentWidth * scale - drawableWidth) / 2 / drawableWidth
        let overflowY = max(0, contentHeight * scale - drawableHeight) / 2 / drawableHeight
        let panX = min(max(Float(pan.width), -overflowX), overflowX)
        let panY = min(max(Float(pan.height), -overflowY), overflowY)
        
        // Unit quad → frame pixels → rotated upright → mirrored in display space → drawable NDC.
        let frameExtent = simd_float4x4(diagonal: SIMD4(width / 2, height / 2, 1, 1))
        let rotationMatrix = simd_float4x4(rows: [
            SIMD4(cos(angle), -sin(angle), 0, 0),
            SIMD4(sin(angle), cos(angle), 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(0, 0, 0, 1)
        ])
        let mirror = simd_float4x4(diagonal: SIMD4(isMirrored ? -1 : 1, 1, 1, 1))
        let toNDC = simd_float4x4(diagonal: SIMD4(scale * 2 / drawableWidth, scale * 2 / drawableHeight, 1, 1))
        // Outermost, so the pan is in display space however the frame arrived: dragging right moves
        // the picture right whichever way up the sender is holding their phone. NDC spans 2 across
        // the drawable, hence the doubling, and its y points up where a finger dragging down does not.
        let translate = simd_float4x4(rows: [
            SIMD4(1, 0, 0, 2 * panX),
            SIMD4(0, 1, 0, -2 * panY),
            SIMD4(0, 0, 1, 0),
            SIMD4(0, 0, 0, 1)
        ])
        return translate * toNDC * mirror * rotationMatrix * frameExtent
    }
}
