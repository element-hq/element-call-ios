//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

/// Where one tile sits on the stage and how it draws itself there.
struct ElementCallTilePlacement: Identifiable, Equatable {
    let tile: ElementCallTile
    /// In the stage's coordinate space: origin top leading, the bottom safe area included.
    var frame: CGRect
    var appearance: ElementCallTileAppearance
    var isSpotlight: Bool
    /// The strip page the tile is on; nil for tiles that don't page (the spotlight, a one-to-one call).
    var page: Int?
    var zIndex: Double
    
    var id: String {
        tile.id
    }
}

/// The arrangement of every tile for one state of the call, computed as rects so that a tile keeps
/// its view identity however the call changes around it: a spotlight change, the other person
/// arriving in a DM or a third person turning it into a group call all become the same tiles moving
/// and resizing, which is what makes the screen feel native rather than a sequence of fades.
struct ElementCallStageLayout: Equatable {
    /// What the stage has to work with. Distances in points.
    struct Metrics: Equatable {
        /// The whole stage, bottom safe area included.
        var area: CGSize
        /// The bottom safe area, which only a full-bleed picture may run under.
        var bottomInset: CGFloat
        /// How far above the safe area the floating controls reach.
        var controlsClearance: CGFloat
        
        static let horizontalMargin: CGFloat = 16
        static let spacing: CGFloat = 12
        static let columns = 2
        static let maxRowsPerPage = 3
        /// The design's ratio for a strip cell.
        static let stripAspectRatio: CGFloat = 1.2
        /// The spotlight's share of the height above the controls.
        static let spotlightFraction: CGFloat = 0.4
        
        /// Where the bottom safe area starts.
        var safeBottom: CGFloat {
            area.height - bottomInset
        }
        
        /// The lowest point a card may reach: above the controls with a gap.
        var cardsBottom: CGFloat {
            safeBottom - controlsClearance - Self.spacing
        }
        
        var cardsWidth: CGFloat {
            area.width - 2 * Self.horizontalMargin
        }
    }
    
    var placements: [ElementCallTilePlacement]
    var pageCount: Int
    /// Where the page dots go when there are pages to show.
    var pageIndicatorCenter: CGPoint?
    /// Whose tile hosts the Picture in Picture source view: the picture the window continues.
    var pictureInPictureMemberID: String?
    
    static func compute(tiles: [ElementCallTile],
                        spotlightMemberID: String?,
                        layout: ElementCallLayout,
                        currentPage: Int,
                        metrics: Metrics) -> ElementCallStageLayout {
        guard !tiles.isEmpty else {
            return ElementCallStageLayout(placements: [], pageCount: 0)
        }
        if layout == .oneToOne, let local = tiles.first(where: \.isLocal) {
            return oneToOne(local: local, remote: tiles.first { !$0.isLocal }, metrics: metrics)
        }
        return group(tiles: tiles, spotlightMemberID: spotlightMemberID, currentPage: currentPage, metrics: metrics)
    }
    
    // MARK: - One-to-one
    
    /// The thumbnail's short side as a share of the area's short side, its short over long side,
    /// and the most either side may take of the matching side of the area (near-square windows).
    private static let thumbnailFraction: CGFloat = 0.38
    private static let thumbnailAspect: CGFloat = 2 / 3
    private static let thumbnailMaxFraction: CGFloat = 0.5
    private static let thumbnailMargin: CGFloat = 16
    
    /// The other person edge to edge, ourselves as a thumbnail in the bottom trailing corner, kept
    /// clear of the floating controls. Until they arrive our own camera has the screen instead.
    private static func oneToOne(local: ElementCallTile, remote: ElementCallTile?, metrics: Metrics) -> ElementCallStageLayout {
        let main = remote ?? local
        var placements = [ElementCallTilePlacement(tile: main,
                                                   frame: CGRect(origin: .zero, size: metrics.area),
                                                   appearance: .fullBleed,
                                                   isSpotlight: false,
                                                   page: nil,
                                                   zIndex: 0)]
        if remote != nil {
            let size = thumbnailSize(in: CGSize(width: metrics.area.width, height: metrics.safeBottom))
            let origin = CGPoint(x: metrics.area.width - thumbnailMargin - size.width,
                                 y: metrics.safeBottom - metrics.controlsClearance - thumbnailMargin - size.height)
            placements.append(ElementCallTilePlacement(tile: local,
                                                       frame: CGRect(origin: origin, size: size),
                                                       appearance: .thumbnail,
                                                       isSpotlight: false,
                                                       page: nil,
                                                       zIndex: 2))
        }
        return ElementCallStageLayout(placements: placements, pageCount: 1, pictureInPictureMemberID: main.memberID)
    }
    
    /// Sized from the area's short side so it is the same share of the screen whichever way the
    /// phone is held; its long side follows the area's orientation because the renderer centre-crops
    /// and a sideways camera sends a landscape frame.
    static func thumbnailSize(in area: CGSize) -> CGSize {
        let shortSide = min(area.width, area.height) * thumbnailFraction
        let longSide = shortSide / thumbnailAspect
        var width = area.width > area.height ? longSide : shortSide
        var height = area.width > area.height ? shortSide : longSide
        let scale = min(1, area.width * thumbnailMaxFraction / width, area.height * thumbnailMaxFraction / height)
        width *= scale
        height *= scale
        return CGSize(width: width, height: height)
    }
    
    // MARK: - Group
    
    /// The spotlight on top, everyone else in pages of a two-column grid under it so tiles keep
    /// their size however big the call gets. Alone (the spotlight is never ourselves) our own tile
    /// stands in the spotlight slot and slides down into its cell as the first person arrives.
    private static func group(tiles: [ElementCallTile], spotlightMemberID: String?, currentPage: Int, metrics: Metrics) -> ElementCallStageLayout {
        var placements: [ElementCallTilePlacement] = []
        var stripTop: CGFloat = 0
        let spotlightTile = tiles.first { $0.memberID == spotlightMemberID }
        let spotlightFrame = CGRect(x: Metrics.horizontalMargin, y: 0, width: metrics.cardsWidth, height: metrics.safeBottom * Metrics.spotlightFraction)
        
        if let spotlight = spotlightTile {
            placements.append(ElementCallTilePlacement(tile: spotlight,
                                                       frame: spotlightFrame,
                                                       appearance: .card,
                                                       isSpotlight: true,
                                                       page: nil,
                                                       zIndex: 1))
            stripTop = spotlightFrame.maxY + Metrics.spacing
        }
        
        let strip = tiles.filter { $0.memberID != spotlightMemberID }
        if placements.isEmpty, strip.count == 1, let only = strip.first {
            placements.append(ElementCallTilePlacement(tile: only,
                                                       frame: spotlightFrame,
                                                       appearance: .card,
                                                       isSpotlight: false,
                                                       page: nil,
                                                       zIndex: 1))
            return ElementCallStageLayout(placements: placements, pageCount: 1)
        }
        
        let cellWidth = (metrics.cardsWidth - Metrics.spacing) / CGFloat(Metrics.columns)
        let cellHeight = cellWidth / Metrics.stripAspectRatio
        let rowsThatFit = Int(((metrics.cardsBottom - stripTop + Metrics.spacing) / (cellHeight + Metrics.spacing)).rounded(.down))
        let rowsPerPage = min(Metrics.maxRowsPerPage, max(1, rowsThatFit))
        let perPage = rowsPerPage * Metrics.columns
        let pageCount = max(1, (strip.count + perPage - 1) / perPage)
        
        for (index, tile) in strip.enumerated() {
            let page = index / perPage
            let row = (index % perPage) / Metrics.columns
            let column = index % Metrics.columns
            let x = Metrics.horizontalMargin + CGFloat(column) * (cellWidth + Metrics.spacing) + CGFloat(page - currentPage) * metrics.area.width
            let y = stripTop + CGFloat(row) * (cellHeight + Metrics.spacing)
            placements.append(ElementCallTilePlacement(tile: tile,
                                                       frame: CGRect(x: x, y: y, width: cellWidth, height: cellHeight),
                                                       appearance: .card,
                                                       isSpotlight: false,
                                                       page: page,
                                                       zIndex: 0))
        }
        
        let stripBottom = stripTop + CGFloat(rowsPerPage) * cellHeight + CGFloat(rowsPerPage - 1) * Metrics.spacing
        let indicatorCenter = pageCount > 1 ? CGPoint(x: metrics.area.width / 2, y: min(stripBottom + Metrics.spacing, metrics.cardsBottom)) : nil
        return ElementCallStageLayout(placements: placements,
                                      pageCount: pageCount,
                                      pageIndicatorCenter: indicatorCenter,
                                      pictureInPictureMemberID: spotlightTile?.memberID)
    }
}
