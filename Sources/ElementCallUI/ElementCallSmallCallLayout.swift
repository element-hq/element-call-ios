//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallKit
import SwiftUI
import UIKit

/// The corner our own floating tile sits in (019 R18, R20). Physical rather than leading and
/// trailing: a right-to-left locale does not mirror it.
public enum ElementCallOwnTileCorner: Sendable, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
    
    var isTop: Bool {
        self == .topLeft || self == .topRight
    }
    
    var isLeft: Bool {
        self == .topLeft || self == .bottomLeft
    }
}

/// The layout for calls of up to five people (spec 019), as pure arithmetic beside the grid's.
///
/// It produces the same ``ElementCallStageLayout`` the grid does, rather than being a view of its
/// own, so a tile keeps its identity when the call crosses between the two: its video view is
/// never remounted, and the switch is every tile moving to its new place (R31).
///
/// Static and caseless, as `ElementCallSpotlight` is, so every rule is a unit test with no view.
enum ElementCallSmallCallLayout {
    /// Room the chrome takes from the floating tile's corners. Not part of the arrangement: only
    /// the floating tile follows the chrome, on the chrome's own animation (R19).
    struct FloatingInsets: Equatable {
        var top: CGFloat
        var bottom: CGFloat
        
        static let zero = FloatingInsets(top: 0, bottom: 0)
    }
    
    private typealias Metrics = ElementCallStageLayout.Metrics
    
    /// Tiles, ourselves included, up to which this layout applies (R1).
    nonisolated static let maximumTiles = 5
    
    /// R6's values, being tuned on a device: the most of the stage width each of the three tiles
    /// takes, and the narrowest any of them may get.
    static let staggerWidthFraction: CGFloat = 0.8
    static let staggerMinimumWidth: CGFloat = 200
    
    /// R17, R28. Smaller than the spec's 140 × 210, which read as too big on a phone; being tuned
    /// on the device (hq 019 ios.md, appendix).
    static let floatingPortraitSize = CGSize(width: 100, height: 150)
    static let floatingLandscapeSize = CGSize(width: 150, height: 100)
    static let floatingAvatarSize = CGSize(width: 100, height: 100)
    static let floatingMargin = Metrics.horizontalMargin
    
    /// Above every tile it floats over, and below a tile going full screen and its scrim, which
    /// replace it like everything else.
    static let floatingZIndex: Double = 2
    
    // MARK: - Selection
    
    /// Whether the stage gets this layout rather than the grid: at most five tiles and no remote
    /// screen share (R1, R8). Counted in tiles rather than members, a share excluded from the count
    /// because its presence alone selects the grid; keyed on the share rather than on being a hero,
    /// because a hero is "a share today, a pin later" and R8 is about shares. Our own share is
    /// never a tile, so it does not switch layouts. No margin and no memory: crossing five and six
    /// switches on every crossing (R33).
    nonisolated static func applies(to tiles: [ElementCallTile]) -> Bool {
        !tiles.contains { $0.isScreenShare && !$0.isLocal }
            && tiles.count { !$0.isScreenShare } <= maximumTiles
    }
    
    /// Whether the arrangement is one picture behind all the chrome: one other person (R4). The
    /// screen extends the stage under the side safe areas for it, which is why it asks here rather
    /// than reading the arrangement, which needs the stage's size first.
    static func isFullBleed(_ tiles: [ElementCallTile]) -> Bool {
        applies(to: tiles) && tiles.count { !$0.isLocal && !$0.isScreenShare } == 1
    }
    
    // MARK: - Arrangement
    
    /// Remote tiles by arrival, never by rank (R7), so nobody moves when someone else talks (R13).
    /// Our own tile floats (R2) and is placed apart from them, alone included (R3), unless it is
    /// inline: in landscape with three tiles or more (R16).
    ///
    /// Everything is on screen, so everything is live and nothing is hidden or released, and the
    /// detail window covers every remote tile (R12). Each placement still carries its *rank* rather
    /// than its arrival index, because the detail window is a rank range.
    static func arrange(_ input: ElementCallStageLayout.Input, viewport: CGRect) -> ElementCallStageLayout {
        let metrics = input.metrics
        let own = input.tiles.first(where: \.isLocal)
        let remote = remoteInArrivalOrder(input.tiles, arrivalOrder: input.arrivalOrder)
        let ranks = Dictionary(uniqueKeysWithValues: input.tiles.filter { !$0.isLocal }.enumerated().map { ($1.id, $0) })
        let isFloating = own != nil && (!metrics.isLandscape || remote.count <= 1)
        
        var placements = [ElementCallTilePlacement]()
        func place(_ tile: ElementCallTile, _ frame: CGRect, _ appearance: ElementCallTileAppearance, zIndex: Double = 0, fit: ElementCallTileFit = .standard) {
            placements.append(ElementCallTilePlacement(tile: tile,
                                                       frame: frame,
                                                       appearance: appearance,
                                                       isSpotlight: false,
                                                       visibility: .live,
                                                       orderIndex: ranks[tile.id],
                                                       zIndex: zIndex,
                                                       contentFit: fit))
        }
        
        if remote.isEmpty {
            // R3: only us, in our corner like any other small call. A whole-screen tile of our own
            // put the flip button under the control bar, and moved our tile on the first arrival.
        } else if remote.count == 1 {
            // R4: filled, except a landscape picture on a portrait stage, which is shown whole.
            place(remote[0], fullBleedFrame(metrics), .fullBleed, fit: metrics.isLandscape ? .standard : .fitWhenLandscape)
        } else if metrics.isLandscape {
            for (tile, frame) in zip((own.map { [$0] } ?? []) + remote, inlineFrames(count: remote.count + (own == nil ? 0 : 1), metrics: metrics)) {
                place(tile, frame, .card)
            }
        } else if remote.count == 2 {
            for (tile, frame) in zip(remote, pairFrames(metrics: metrics)) {
                place(tile, frame, .card)
            }
        } else if remote.count == 3 {
            // The speaker is ringed and nothing else (R9): with the rows not overlapping there is
            // nothing to be on top of, and growing the speaker ate the gap beside it, unevenly, since
            // a top or bottom row could only grow inwards.
            for (tile, frame) in zip(remote, staggerFrames(metrics: metrics)) {
                place(tile, frame, .card)
            }
        } else {
            for (tile, frame) in zip(remote, twoColumnFrames(count: remote.count, metrics: metrics)) {
                place(tile, frame, .card)
            }
        }
        
        if isFloating, let own {
            let size = floatingSize(hasVideo: own.hasVideo, videoAspect: input.ownVideoAspect, isLandscape: metrics.isLandscape)
            place(own, floatingFrame(corner: input.ownCorner, size: size, metrics: metrics, insets: input.floatingInsets), .floating, zIndex: floatingZIndex)
        }
        
        // R27: remote tiles by arrival, then ourselves; ourselves first when drawn first.
        let ownID = own.map { [$0.id] } ?? []
        let remoteIDs = remote.map(\.id)
        return ElementCallStageLayout(placements: placements,
                                      contentHeight: viewport.height,
                                      viewport: viewport,
                                      detailWindow: .init(ranks: 0..<ranks.count, also: []),
                                      heroStack: nil,
                                      pictureInPictureTileID: pictureInPictureTile(tiles: input.tiles, arrivalOrder: input.arrivalOrder, speakerID: input.speakerID),
                                      isStatic: true,
                                      readingOrder: isFloating ? remoteIDs + ownID : ownID + remoteIDs)
    }
    
    /// The remote person tiles in arrival order. A tile the order has not seen yet goes after it in
    /// the order given, so a caller with no arrival record (a grid test, the first pass of a
    /// preview) gets the tiles as listed rather than none.
    nonisolated static func remoteInArrivalOrder(_ tiles: [ElementCallTile], arrivalOrder: ElementCallArrivalOrder) -> [ElementCallTile] {
        let remote = tiles.filter { !$0.isLocal && !$0.isScreenShare }
        let byID = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        let arrived = arrivalOrder.ids.compactMap { byID[$0] }
        let known = Set(arrivalOrder.ids)
        return arrived + remote.filter { !known.contains($0.id) }
    }
    
    /// The whole screen, behind both bars (R4). In content coordinates, which start under the
    /// portrait top bar, so it reaches above zero by the room the bar and the status bar take. The
    /// sides are the stage's own, which runs under the side safe areas while this is up; the bottom
    /// already includes the home indicator.
    static func fullBleedFrame(_ metrics: ElementCallStageLayout.Metrics) -> CGRect {
        CGRect(x: 0, y: -metrics.topBleed, width: metrics.area.width, height: metrics.area.height + metrics.topBleed)
    }
    
    /// R5: two 4:3 tiles one above the other, from the top, as wide as the stage allows: the full
    /// width, unless two rows that wide do not fit above the controls (an SE), when they are as wide
    /// as fits and centred. Our floating tile overlaps the lower one (R2).
    static func pairFrames(metrics: ElementCallStageLayout.Metrics) -> [CGRect] {
        let height = min(metrics.cardsWidth / Metrics.tileAspect, (metrics.cardsBottom - Metrics.spacing) / 2)
        let width = height * Metrics.tileAspect
        let leading = metrics.cardsLeading + (metrics.cardsWidth - width) / 2
        return (0..<2).map { CGRect(x: leading, y: CGFloat($0) * (height + Metrics.spacing), width: width, height: height) }
    }
    
    /// R6: three 4:3 rows, left, right, left, the first at the top and the third at the bottom of the
    /// band, with at least the ordinary gap between them. At ``staggerWidthFraction`` three rows do
    /// not fit a phone's band, so they shrink until they do, but never below ``staggerMinimumWidth``,
    /// which only a split screen or a very short stage reaches and where they then overlap. They
    /// used to overlap instead of shrinking, as R6 first said, which hid the middle tile's name
    /// under the third.
    static func staggerFrames(metrics: ElementCallStageLayout.Metrics) -> [CGRect] {
        let band = metrics.cardsBottom
        var width = min(max(staggerWidthFraction * metrics.cardsWidth, staggerMinimumWidth), metrics.cardsWidth)
        var height = width / Metrics.tileAspect
        let heightThatFits = (band - 2 * Metrics.spacing) / 3
        if height > heightThatFits {
            width = min(max(heightThatFits * Metrics.tileAspect, staggerMinimumWidth), metrics.cardsWidth)
            height = width / Metrics.tileAspect
        }
        let lowest = band - height
        let ys = [0, lowest / 2, lowest]
        let xs = [metrics.cardsLeading, metrics.cardsTrailing - width, metrics.cardsLeading]
        return zip(xs, ys).map { CGRect(x: $0, y: $1, width: width, height: height) }
    }
    
    /// R11: 4:3 in two columns at the top of the stage, not centred, leaving the bottom for our
    /// floating tile.
    private static func twoColumnFrames(count: Int, metrics: Metrics) -> [CGRect] {
        let width = (metrics.cardsWidth - Metrics.spacing) / 2
        let height = width / Metrics.tileAspect
        return (0..<count).map { index in
            CGRect(x: metrics.cardsLeading + CGFloat(index % 2) * (width + Metrics.spacing),
                   y: CGFloat(index / 2) * (height + Metrics.spacing),
                   width: width,
                   height: height)
        }
    }
    
    /// R16: 4:3, rows of at most four, every tile the same size, each row and the whole block
    /// centred. As wide as the stage allows, shrinking only when two rows do not fit its height.
    static func inlineFrames(count: Int, metrics: ElementCallStageLayout.Metrics) -> [CGRect] {
        let perRow = min(count, 4)
        let rows = (count + 3) / 4
        let widthThatFitsTheRow = (metrics.cardsWidth - CGFloat(perRow - 1) * Metrics.spacing) / CGFloat(perRow)
        let widthThatFitsTheRows = (metrics.cardsBottom - CGFloat(rows - 1) * Metrics.spacing) / CGFloat(rows) * Metrics.tileAspect
        let width = min(widthThatFitsTheRow, widthThatFitsTheRows)
        let height = width / Metrics.tileAspect
        let blockHeight = CGFloat(rows) * height + CGFloat(rows - 1) * Metrics.spacing
        let top = (metrics.cardsBottom - blockHeight) / 2
        return (0..<count).map { index in
            let row = index / 4
            let inRow = min(count - row * 4, 4)
            let rowWidth = CGFloat(inRow) * width + CGFloat(inRow - 1) * Metrics.spacing
            let leading = metrics.cardsLeading + (metrics.cardsWidth - rowWidth) / 2
            return CGRect(x: leading + CGFloat(index % 4) * (width + Metrics.spacing),
                          y: top + CGFloat(row) * (height + Metrics.spacing),
                          width: width,
                          height: height)
        }
    }
    
    // MARK: - Our own floating tile
    
    /// R10, R17, R28: a square avatar with the camera off, otherwise the shape of the picture.
    /// Before the first frame the stage's own orientation stands in for it, since our capture is
    /// upright in the interface orientation.
    static func floatingSize(hasVideo: Bool, videoAspect: CGFloat?, isLandscape: Bool) -> CGSize {
        guard hasVideo else { return floatingAvatarSize }
        let isLandscapePicture = videoAspect.map { $0 > 1 } ?? isLandscape
        return isLandscapePicture ? floatingLandscapeSize : floatingPortraitSize
    }
    
    /// Where the floating tile's frame may be: inside the cards' margins, and clear of whatever
    /// chrome is showing at the top and the bottom (R19). Its corners are the four snap points, and
    /// a drag cannot take the tile outside it (R21).
    static func floatingBounds(metrics: ElementCallStageLayout.Metrics, insets: FloatingInsets) -> CGRect {
        let top = insets.top + floatingMargin
        let bottom = metrics.safeBottom - insets.bottom - floatingMargin
        return CGRect(x: metrics.cardsLeading, y: top, width: metrics.cardsWidth, height: bottom - top)
    }
    
    static func floatingFrame(corner: ElementCallOwnTileCorner, size: CGSize, metrics: ElementCallStageLayout.Metrics, insets: FloatingInsets) -> CGRect {
        let bounds = floatingBounds(metrics: metrics, insets: insets)
        return CGRect(x: corner.isLeft ? bounds.minX : bounds.maxX - size.width,
                      y: corner.isTop ? bounds.minY : bounds.maxY - size.height,
                      width: size.width,
                      height: size.height)
    }
    
    /// The corner whose quadrant the tile's centre was released in (R21).
    static func nearestCorner(to center: CGPoint, in bounds: CGRect) -> ElementCallOwnTileCorner {
        switch (center.y < bounds.midY, center.x < bounds.midX) {
        case (true, true): .topLeft
        case (true, false): .topRight
        case (false, true): .bottomLeft
        case (false, false): .bottomRight
        }
    }
    
    /// The corner a released tile goes to (R21): the one nearest where it would coast to from the
    /// finger's velocity, so a flick towards a corner reaches it from wherever it was let go. A slow
    /// release projects almost nowhere, and is the corner of the quadrant it was dropped in.
    static func releaseCorner(center: CGPoint, velocity: CGSize, in bounds: CGRect) -> ElementCallOwnTileCorner {
        nearestCorner(to: CGPoint(x: center.x + projectedDistance(velocity.width),
                                  y: center.y + projectedDistance(velocity.height)),
                      in: bounds)
    }
    
    /// How far something moving at `velocity` points per second coasts before it stops, at the
    /// rate a scroll view decelerates. The projection Apple's own fluid interfaces use for a flick.
    static func projectedDistance(_ velocity: CGFloat) -> CGFloat {
        let rate = UIScrollView.DecelerationRate.normal.rawValue
        return velocity / 1000 * rate / (1 - rate)
    }
    
    /// A drag's translation, held so the whole tile stays inside the bounds (R21).
    static func clampedDrag(_ translation: CGSize, from frame: CGRect, in bounds: CGRect) -> CGSize {
        CGSize(width: min(max(translation.width, bounds.minX - frame.minX), bounds.maxX - frame.maxX),
               height: min(max(translation.height, bounds.minY - frame.minY), bounds.maxY - frame.maxY))
    }
    
    // MARK: - Speaker
    
    /// Who counts as speaking for the small layout: the one Picture in Picture continues (R15).
    ///
    /// - Parameters:
    ///   - tiles: the composed tiles, ourselves included; we are never the speaker (R15).
    ///   - arrivalOrder: breaks a tie between two people starting to speak at once.
    ///   - held: the previous answer. Kept while it is still speaking, so two people talking over
    ///     each other do not swap on every word, and kept through silence, so the last speaker
    ///     stays rather than the window emptying (R15). Dropped once they leave.
    nonisolated static func speaker(tiles: [ElementCallTile],
                                    arrivalOrder: ElementCallArrivalOrder,
                                    held: MatrixRTCTileID?) -> MatrixRTCTileID? {
        let remote = remoteInArrivalOrder(tiles, arrivalOrder: arrivalOrder)
        if let held, remote.contains(where: { $0.id == held && $0.isSpeaking }) {
            return held
        }
        if let first = remote.first(where: \.isSpeaking) {
            return first.id
        }
        if let held, remote.contains(where: { $0.id == held }) {
            return held
        }
        return nil
    }
    
    /// The tile the Picture in Picture window continues while the small layout is up (R15): the
    /// speaker, else whoever arrived first, else ourselves when we are alone.
    nonisolated static func pictureInPictureTile(tiles: [ElementCallTile],
                                                 arrivalOrder: ElementCallArrivalOrder,
                                                 speakerID: MatrixRTCTileID?) -> MatrixRTCTileID? {
        speakerID ?? remoteInArrivalOrder(tiles, arrivalOrder: arrivalOrder).first?.id ?? tiles.first(where: \.isLocal)?.id
    }
}
