//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallKit
import SwiftUI

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
    static let maximumTiles = 5
    
    /// R6's starting values, to be tuned on a device: the share of the stage width each of the
    /// three overlapping tiles takes, the narrowest any of them may get, and the most of a tile's
    /// height its neighbour may cover before they shrink.
    static let staggerWidthFraction: CGFloat = 0.8
    static let staggerMinimumWidth: CGFloat = 200
    static let staggerMaximumOverlap: CGFloat = 0.5
    /// How much the speaker's tile grows in the overlap (R9), as a fraction of each side.
    static let speakerBoost: CGFloat = 0.1
    
    /// R17, R28.
    static let floatingPortraitSize = CGSize(width: 140, height: 210)
    static let floatingLandscapeSize = CGSize(width: 210, height: 140)
    static let floatingAvatarSize = CGSize(width: 140, height: 140)
    static let floatingMargin = Metrics.horizontalMargin
    
    /// Above every tile it floats over, and below a tile going full screen and its scrim, which
    /// replace it like everything else.
    static let floatingZIndex: Double = 2
    /// The speaker's tile in the overlap, above its neighbours (R6, R9).
    static let staggerTopZIndex = 0.5
    
    // MARK: - Selection
    
    /// Whether the stage gets this layout rather than the grid: at most five tiles and no remote
    /// screen share (R1, R8). Counted in tiles rather than members, a share excluded from the count
    /// because its presence alone selects the grid; keyed on the share rather than on being a hero,
    /// because a hero is "a share today, a pin later" and R8 is about shares. Our own share is
    /// never a tile, so it does not switch layouts. No margin and no memory: crossing five and six
    /// switches on every crossing (R33).
    static func applies(to tiles: [ElementCallTile]) -> Bool {
        !tiles.contains { $0.isScreenShare && !$0.isLocal }
            && tiles.count { !$0.isScreenShare } <= maximumTiles
    }
    
    /// Whether the arrangement is one picture behind all the chrome (R3, R4): ourselves alone, or one
    /// other person. The screen extends the stage under the side safe areas for these, which is
    /// why it asks here rather than reading the arrangement, which needs the stage's size first.
    static func isFullBleed(_ tiles: [ElementCallTile]) -> Bool {
        !tiles.isEmpty && applies(to: tiles) && tiles.count { !$0.isLocal && !$0.isScreenShare } <= 1
    }
    
    // MARK: - Arrangement
    
    /// Remote tiles by arrival, never by rank (R7), so nobody moves when someone else talks (R13).
    /// Our own tile floats (R2) and is placed apart from them, unless it is inline: alone (R3) or
    /// in landscape with three tiles or more (R16).
    ///
    /// Everything is on screen, so everything is live and nothing is hidden or released, and the
    /// detail window covers every remote tile (R12). Each placement still carries its *rank* rather
    /// than its arrival index, because the detail window is a rank range.
    static func arrange(_ input: ElementCallStageLayout.Input, viewport: CGRect) -> ElementCallStageLayout {
        let metrics = input.metrics
        let own = input.tiles.first(where: \.isLocal)
        let remote = remoteInArrivalOrder(input.tiles, arrivalOrder: input.arrivalOrder)
        let ranks = Dictionary(uniqueKeysWithValues: input.tiles.filter { !$0.isLocal }.enumerated().map { ($1.id, $0) })
        let isFloating = own != nil && !remote.isEmpty && (!metrics.isLandscape || remote.count == 1)
        
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
        
        if remote.isEmpty, let own {
            // R3: the whole screen and the picture whole, so you can check your hair.
            place(own, fullBleedFrame(metrics), .fullBleed, fit: .fit)
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
            let top = remote.first { $0.id == input.speakerID } ?? remote[1]
            for (tile, frame) in zip(remote, staggerFrames(metrics: metrics)) {
                let isTop = tile.id == top.id
                // Only the speaker grows; the 2nd tile on top for want of one keeps its size (R9).
                let grown = isTop && tile.id == input.speakerID ? boosted(frame, metrics: metrics) : frame
                place(tile, grown, .card, zIndex: isTop ? staggerTopZIndex : 0)
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
    static func remoteInArrivalOrder(_ tiles: [ElementCallTile], arrivalOrder: ElementCallArrivalOrder) -> [ElementCallTile] {
        let remote = tiles.filter { !$0.isLocal && !$0.isScreenShare }
        let byID = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        let arrived = arrivalOrder.ids.compactMap { byID[$0] }
        let known = Set(arrivalOrder.ids)
        return arrived + remote.filter { !known.contains($0.id) }
    }
    
    /// The whole screen, behind both bars (R3, R4). In content coordinates, which start under the
    /// portrait top bar, so it reaches above zero by the room the bar and the status bar take. The
    /// sides are the stage's own, which runs under the side safe areas while this is up; the bottom
    /// already includes the home indicator.
    static func fullBleedFrame(_ metrics: ElementCallStageLayout.Metrics) -> CGRect {
        CGRect(x: 0, y: -metrics.topBleed, width: metrics.area.width, height: metrics.area.height + metrics.topBleed)
    }
    
    /// R5: two 3:4 tiles side by side at the top, leaving the bottom for our floating tile.
    private static func pairFrames(metrics: Metrics) -> [CGRect] {
        let width = (metrics.cardsWidth - Metrics.spacing) / 2
        let height = width / (3.0 / 4.0)
        return (0..<2).map { CGRect(x: metrics.cardsLeading + CGFloat($0) * (width + Metrics.spacing), y: 0, width: width, height: height) }
    }
    
    /// R6: three 4:3 rows, left, right, left, the first at the top and the third at the bottom of the
    /// band, overlapping by whatever it takes to fit. Past ``staggerMaximumOverlap`` they shrink
    /// instead, but never below ``staggerMinimumWidth``, which only a split screen or a very short
    /// stage reaches.
    static func staggerFrames(metrics: ElementCallStageLayout.Metrics) -> [CGRect] {
        let band = metrics.cardsBottom
        var width = min(max(staggerWidthFraction * metrics.cardsWidth, staggerMinimumWidth), metrics.cardsWidth)
        var height = width / Metrics.tileAspect
        if (3 * height - band) / 2 > staggerMaximumOverlap * height {
            // The height at which neighbours overlap by exactly the maximum.
            height = band / (3 - 2 * staggerMaximumOverlap)
            width = min(max(height * Metrics.tileAspect, staggerMinimumWidth), metrics.cardsWidth)
            height = width / Metrics.tileAspect
        }
        let lowest = band - height
        let ys = [0, lowest / 2, lowest]
        let xs = [metrics.cardsLeading, metrics.cardsTrailing - width, metrics.cardsLeading]
        return zip(xs, ys).map { CGRect(x: $0, y: $1, width: width, height: height) }
    }
    
    /// R9: grown around its centre, then moved back inside the band if that pushed it out.
    private static func boosted(_ frame: CGRect, metrics: Metrics) -> CGRect {
        let grown = frame.insetBy(dx: -frame.width * speakerBoost / 2, dy: -frame.height * speakerBoost / 2)
        let x = min(max(grown.minX, metrics.cardsLeading), metrics.cardsTrailing - grown.width)
        let y = min(max(grown.minY, 0), metrics.cardsBottom - grown.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: grown.size)
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
    
    /// A drag's translation, held so the whole tile stays inside the bounds (R21).
    static func clampedDrag(_ translation: CGSize, from frame: CGRect, in bounds: CGRect) -> CGSize {
        CGSize(width: min(max(translation.width, bounds.minX - frame.minX), bounds.maxX - frame.maxX),
               height: min(max(translation.height, bounds.minY - frame.minY), bounds.maxY - frame.maxY))
    }
    
    // MARK: - Speaker
    
    /// Who counts as speaking for the small layout: the tile on top of the overlap (R6, R9) and the
    /// one Picture in Picture continues (R15). One choice for both, so the window never shows
    /// someone other than the tile the stage is raising.
    ///
    /// - Parameters:
    ///   - tiles: the composed tiles, ourselves included; we are never the speaker (R15).
    ///   - arrivalOrder: breaks a tie between two people starting to speak at once.
    ///   - held: the previous answer. Kept while it is still speaking, so two people talking over
    ///     each other do not swap on every word, and kept through silence, so the last speaker
    ///     stays rather than the slot emptying (R9). Dropped once they leave.
    static func speaker(tiles: [ElementCallTile],
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
    static func pictureInPictureTile(tiles: [ElementCallTile],
                                     arrivalOrder: ElementCallArrivalOrder,
                                     speakerID: MatrixRTCTileID?) -> MatrixRTCTileID? {
        speakerID ?? remoteInArrivalOrder(tiles, arrivalOrder: arrivalOrder).first?.id ?? tiles.first(where: \.isLocal)?.id
    }
}
