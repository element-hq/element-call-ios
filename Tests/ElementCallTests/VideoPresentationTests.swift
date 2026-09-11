//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import CoreGraphics
@testable import ElementCallKit
import simd
import Testing

/// The vertex transform is where "bars on the side rather than a crop" actually lives, and it is
/// arithmetic, so it is pinned here rather than by comparing pictures.
///
/// Everything is measured as the box the quad's four corners land in, in normalised device
/// coordinates: the drawable is exactly -1...1 on both axes, so a half-extent of 1 is an edge
/// reached, less than 1 is a bar, and more than 1 is a crop. Corners rather than one chosen vertex
/// because rotation and mirroring move which corner is which.
nonisolated struct VideoPresentationTests {
    /// A landscape picture, and a drawable shaped like a phone held upright: the case the feature
    /// exists for.
    let frame = (width: 1600, height: 900)
    let portraitDrawable = CGSize(width: 400, height: 800)
    
    struct Box {
        var centre: SIMD2<Float>
        var halfWidth: Float
        var halfHeight: Float
    }
    
    func box(_ presentation: VideoPresentation,
             frameWidth: Int? = nil,
             frameHeight: Int? = nil,
             rotation: MatrixRTCVideoRotation = .deg0,
             isMirrored: Bool = false,
             drawableSize: CGSize? = nil) -> Box {
        let matrix = presentation.transform(frameWidth: frameWidth ?? frame.width,
                                            frameHeight: frameHeight ?? frame.height,
                                            rotation: rotation,
                                            isMirrored: isMirrored,
                                            drawableSize: drawableSize ?? portraitDrawable)
        let corners = [SIMD4<Float>(-1, -1, 0, 1), SIMD4<Float>(1, -1, 0, 1),
                       SIMD4<Float>(-1, 1, 0, 1), SIMD4<Float>(1, 1, 0, 1)].map { matrix * $0 }
        let minimum = corners.reduce(SIMD2<Float>(.greatestFiniteMagnitude, .greatestFiniteMagnitude)) {
            SIMD2(min($0.x, $1.x), min($0.y, $1.y))
        }
        let maximum = corners.reduce(SIMD2<Float>(-.greatestFiniteMagnitude, -.greatestFiniteMagnitude)) {
            SIMD2(max($0.x, $1.x), max($0.y, $1.y))
        }
        return Box(centre: (minimum + maximum) / 2,
                   halfWidth: (maximum.x - minimum.x) / 2,
                   halfHeight: (maximum.y - minimum.y) / 2)
    }
    
    @Test("Fit reaches the sides and leaves a bar above and below")
    func fitLetterboxes() {
        let fitted = box(VideoPresentation(contentMode: .fit))
        #expect(abs(fitted.halfWidth - 1) < 1e-4)
        #expect(fitted.halfHeight < 1)
        // 16:9 in a 1:2 drawable: a quarter of the height is picture.
        #expect(abs(fitted.halfHeight - 0.28125) < 1e-4)
        #expect(abs(fitted.centre.x) < 1e-4)
        #expect(abs(fitted.centre.y) < 1e-4)
    }
    
    @Test("Fill reaches the top and bottom and crops the sides")
    func fillCrops() {
        let filled = box(VideoPresentation(contentMode: .fill))
        #expect(abs(filled.halfHeight - 1) < 1e-4)
        #expect(filled.halfWidth > 1)
    }
    
    @Test("Zoom scales the picture about its centre")
    func zoomScales() {
        let fitted = box(VideoPresentation(contentMode: .fit))
        let zoomed = box(VideoPresentation(contentMode: .fit, zoom: 2))
        #expect(abs(zoomed.halfWidth - fitted.halfWidth * 2) < 1e-4)
        #expect(abs(zoomed.halfHeight - fitted.halfHeight * 2) < 1e-4)
        #expect(abs(zoomed.centre.x) < 1e-4)
    }
    
    /// Unzoomed and fitted there is nothing to see past the edges, so a pan has nowhere to go. The
    /// gesture layer clamps too, but a stale offset from the frame before a rotation gets here.
    @Test("A pan with no overflow to move into is ignored")
    func panWithoutOverflowIsIgnored() {
        let panned = box(VideoPresentation(contentMode: .fit, pan: CGSize(width: 0.5, height: 0.5)))
        #expect(abs(panned.centre.x) < 1e-4)
        #expect(abs(panned.centre.y) < 1e-4)
    }
    
    /// Zoomed to 2, the fitted picture is twice the drawable's width, so half a drawable hangs off
    /// each side. Panned to the limit, that side's edge should sit exactly on the drawable's.
    @Test("A pan past the limit stops with the picture's edge on the drawable's")
    func panClampsToTheOverflow() {
        let panned = box(VideoPresentation(contentMode: .fit, zoom: 2, pan: CGSize(width: 1, height: 0)))
        #expect(abs(panned.halfWidth - 2) < 1e-4)
        #expect(abs(panned.centre.x - 1) < 1e-4)
        // Left edge flush with the drawable's left edge, nothing black showing.
        #expect(abs((panned.centre.x - panned.halfWidth) + 1) < 1e-4)
    }
    
    /// A finger dragging down moves the picture down, and NDC's y points the other way.
    @Test("A downward pan moves the picture down the screen")
    func panYFollowsTheFinger() {
        let panned = box(VideoPresentation(contentMode: .fit, zoom: 8, pan: CGSize(width: 0, height: 0.1)))
        #expect(panned.centre.y < -1e-4)
    }
    
    @Test("A sideways frame is fitted by its upright shape")
    func rotationSwapsTheContentExtents() {
        // 1600x900 turned a quarter is 900 wide and 1600 tall. Still wider in proportion than the
        // 400x800 drawable, so the sides still bind, but the bars are now a sliver rather than most
        // of the screen: which is the whole of what rotation changes here.
        let fitted = box(VideoPresentation(contentMode: .fit), rotation: .deg90)
        #expect(abs(fitted.halfWidth - 1) < 1e-4)
        #expect(fitted.halfHeight < 1)
        #expect(abs(fitted.halfHeight - 0.8889) < 1e-3)
        // And it is taller than the same frame upright, which is the point of measuring it upright.
        #expect(fitted.halfHeight > box(VideoPresentation(contentMode: .fit)).halfHeight)
    }
    
    /// The pan is applied after the rotation and the mirror, so it is in the space the finger is in
    /// rather than the one the sender's camera was in.
    @Test("Pan direction survives rotation and mirroring", arguments: [
        (MatrixRTCVideoRotation.deg0, false),
        (.deg90, false),
        (.deg180, false),
        (.deg270, false),
        (.deg0, true),
        (.deg90, true)
    ])
    func panIsInDisplaySpace(rotation: MatrixRTCVideoRotation, isMirrored: Bool) {
        let panned = box(VideoPresentation(contentMode: .fit, zoom: 8, pan: CGSize(width: 0.05, height: 0)),
                         rotation: rotation,
                         isMirrored: isMirrored)
        #expect(panned.centre.x > 1e-4, "\(rotation) mirrored: \(isMirrored) panned the wrong way")
    }
    
    @Test("A zero drawable does not divide by zero")
    func degenerateDrawable() {
        let degenerate = box(VideoPresentation(contentMode: .fit), drawableSize: .zero)
        #expect(degenerate.halfWidth.isFinite)
        #expect(degenerate.halfHeight.isFinite)
    }
}
