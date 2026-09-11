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

/// How much of a tile's video is still worth asking the SFU for.
///
/// Three states rather than two because the core draws the same distinction: a tile one swipe away
/// is paused so its picture comes straight back, while a tile several pages away is released, which
/// is the only one that stops a thirty-person call from holding thirty subscriptions.
enum ElementCallTileVisibility: Equatable {
    /// On screen, drawing: subscribed at the size it draws.
    case live
    /// A page away: paused, instant to resume.
    case paused
    /// Further than a swipe: unsubscribed as fully as the transport allows.
    case released
    
    /// A tile that does not page (the spotlight, either half of a one-to-one call) is always drawn.
    /// Otherwise it is how far its page is from the one in view: the neighbour is a single swipe
    /// away and only pauses, so its picture is there the instant the finger moves, and anything
    /// beyond it is released. That one step of slack is what keeps paging feeling instant while
    /// still letting a thirty-person call hold far fewer than thirty subscriptions.
    ///
    /// `livePages` rather than just the current page because a swipe in progress has two pages on
    /// screen at once, and the one being left has to keep its picture until the snap finishes.
    static func forPage(_ page: Int?, currentPage: Int, livePages: Set<Int>) -> ElementCallTileVisibility {
        guard let page else { return .live }
        if livePages.contains(page) {
            return .live
        }
        return abs(page - currentPage) == 1 ? .paused : .released
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
        /// The side safe areas. Zero in portrait; in landscape the sensor housing sits on one of
        /// them, and a card drawn under it loses a corner.
        var leadingInset: CGFloat = 0
        var trailingInset: CGFloat = 0
        /// How far the floating controls reach in from the edge they are on: up from the safe area
        /// in portrait, in from the trailing edge in landscape.
        var controlsClearance: CGFloat
        
        static let horizontalMargin: CGFloat = 16
        static let spacing: CGFloat = 12
        static let columns = 2
        static let maxRowsPerPage = 3
        /// A landscape page is one tile wide, so it takes more rows before paging earns its keep.
        static let maxRowsPerLandscapePage = 4
        /// Landscape without a spotlight is a wide empty stage; two columns would be enormous.
        static let landscapeColumnsWithoutSpotlight = 3
        /// The design's ratio for a strip cell.
        static let stripAspectRatio: CGFloat = 1.2
        /// The spotlight's share of the height above the controls, in portrait.
        static let spotlightFraction: CGFloat = 0.4
        /// The landscape tile column's share of the width, and the bounds it is held within: a
        /// share alone gives a useless 90 pt column on a small phone and a 300 pt one on an iPad.
        static let landscapeColumnFraction: CGFloat = 0.22
        static let landscapeColumnRange: ClosedRange<CGFloat> = 140...220
        /// The fewest tiles the landscape column is widened down to fit. A share of the width alone
        /// put a 179 pt column on a 375 pt phone, whose 149 pt cells missed a second row by 8 pt:
        /// seven people became seven pages, each showing one tile beside half a column of nothing.
        /// The column is as wide as the share allows or as wide as two rows allow, whichever is less.
        static let landscapeColumnMinimumRows = 2
        
        /// Landscape is a stage wider than it is tall, and that is the whole of what the layout
        /// needs to know. Not the device, not the size class: a half-screen iPad app in portrait
        /// wants the portrait arrangement whatever the hardware is doing.
        var isLandscape: Bool {
            area.width > area.height
        }
        
        /// Where the bottom safe area starts.
        var safeBottom: CGFloat {
            area.height - bottomInset
        }
        
        /// The lowest point a card may reach. In portrait the controls float above the safe area
        /// and cards stop short of them; in landscape the controls are off to the trailing side, so
        /// the only thing below a card is the safe area itself.
        var cardsBottom: CGFloat {
            isLandscape ? safeBottom - Self.spacing : safeBottom - controlsClearance - Self.spacing
        }
        
        var cardsLeading: CGFloat {
            leadingInset + Self.horizontalMargin
        }
        
        /// Inside the safe area, and inside the controls rail when landscape has put it here.
        var cardsTrailing: CGFloat {
            area.width - trailingInset - Self.horizontalMargin - (isLandscape ? controlsClearance : 0)
        }
        
        var cardsWidth: CGFloat {
            cardsTrailing - cardsLeading
        }
        
        /// The whole area a card may use, both orientations.
        var cardsFrame: CGRect {
            CGRect(x: cardsLeading, y: 0, width: cardsWidth, height: cardsBottom)
        }
    }
    
    /// Clear of every z position the other arrangements hand out: the spotlight's 1 and the
    /// one-to-one thumbnail's 2. Named so the relationship is something a test can assert rather
    /// than something the next person has to notice.
    static let fullscreenZIndex: Double = 3
    
    var placements: [ElementCallTilePlacement]
    var pageCount: Int
    /// Where the page dots go when there are pages to show.
    var pageIndicatorCenter: CGPoint?
    /// Which way the strip pages, and so which way a swipe is read and the dots stack.
    var pageAxis: Axis = .horizontal
    /// Whose tile hosts the Picture in Picture source view: the picture the window continues.
    var pictureInPictureMemberID: String?
    /// Members the arrangement leaves out altogether, which today means everyone but the one tile
    /// filling the screen. The stage releases them: it derives the released set from the placements,
    /// and a single placement would otherwise compute the empty set and un-release the whole call at
    /// the very moment nobody is looking at it. **Declared last** because the memberwise initialiser
    /// follows declaration order and the arrangements below call it with trailing labels.
    var hiddenMemberIDs: Set<String> = []
    
    static func compute(tiles: [ElementCallTile],
                        spotlightMemberID: String?,
                        fullscreenMemberID: String? = nil,
                        layout: ElementCallLayout,
                        currentPage: Int,
                        metrics: Metrics) -> ElementCallStageLayout {
        guard !tiles.isEmpty else {
            return ElementCallStageLayout(placements: [], pageCount: 0)
        }
        // A member who has left is no longer in `tiles`, and the arrangement falls back on its own
        // rather than showing an empty screen. The screen clears the stale id when it notices.
        if let fullscreenMemberID, let tile = tiles.first(where: { $0.memberID == fullscreenMemberID }) {
            return fullscreen(tile: tile, others: tiles.filter { $0.memberID != fullscreenMemberID }, metrics: metrics)
        }
        if layout == .oneToOne, let local = tiles.first(where: \.isLocal) {
            return oneToOne(local: local, remote: tiles.first { !$0.isLocal }, metrics: metrics)
        }
        return group(tiles: tiles, spotlightMemberID: spotlightMemberID, currentPage: currentPage, metrics: metrics)
    }
    
    // MARK: - Full screen
    
    /// One tile and nothing else, edge to edge. The others keep their place in the call but not on
    /// the stage, so they are named as hidden rather than simply dropped.
    ///
    /// The picture fits rather than fills at this size (see ``VideoPresentation``), so the frame is
    /// the whole area whatever shape the picture turns out to be: the letterbox is the renderer's
    /// business, and giving the tile an aspect-shaped frame here would make the layout depend on a
    /// stream it cannot see.
    ///
    /// Above everything, hence ``fullscreenZIndex``: the tiles it replaces are *leaving*, and a
    /// leaving view keeps its z position for as long as its transition runs. At the strip's own
    /// zero, a tile growing out of the strip had the spotlight's 1 fading out on top of it all the
    /// way up, which is the one moment in the whole move when something is covering the thing you
    /// just asked to see.
    private static func fullscreen(tile: ElementCallTile, others: [ElementCallTile], metrics: Metrics) -> ElementCallStageLayout {
        ElementCallStageLayout(placements: [ElementCallTilePlacement(tile: tile,
                                                                     frame: CGRect(origin: .zero, size: metrics.area),
                                                                     appearance: .fullscreen,
                                                                     isSpotlight: false,
                                                                     page: nil,
                                                                     zIndex: fullscreenZIndex)],
                               pageCount: 1,
                               pictureInPictureMemberID: tile.memberID,
                               hiddenMemberIDs: Set(others.map(\.memberID)))
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
            // The thumbnail dodges the controls on whichever edge they are: below it in portrait,
            // beside it in landscape. Only the picture behind it runs full bleed.
            let trailingChrome = metrics.trailingInset + (metrics.isLandscape ? metrics.controlsClearance : 0)
            let bottomChrome = metrics.isLandscape ? 0 : metrics.controlsClearance
            let origin = CGPoint(x: metrics.area.width - trailingChrome - thumbnailMargin - size.width,
                                 y: metrics.safeBottom - bottomChrome - thumbnailMargin - size.height)
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
    
    /// Where the spotlight sits, where the strip runs and which way its pages slide. Portrait
    /// stacks the two, landscape puts them side by side, and everything after this point is the
    /// same arithmetic over whatever rect the strip got. Forking the two orientations into separate
    /// functions duplicated the paging maths, which is the part actually worth getting right.
    private struct StripPlan {
        var spotlightFrame: CGRect
        var stripFrame: CGRect
        var columns: Int
        var maxRowsPerPage: Int
        var pageAxis: Axis
    }
    
    private static func plan(metrics: Metrics, hasSpotlight: Bool) -> StripPlan {
        guard metrics.isLandscape else {
            let spotlightFrame = CGRect(x: metrics.cardsLeading,
                                        y: 0,
                                        width: metrics.cardsWidth,
                                        height: metrics.safeBottom * Metrics.spotlightFraction)
            let stripTop = hasSpotlight ? spotlightFrame.maxY + Metrics.spacing : 0
            return StripPlan(spotlightFrame: spotlightFrame,
                             stripFrame: CGRect(x: metrics.cardsLeading,
                                                y: stripTop,
                                                width: metrics.cardsWidth,
                                                height: metrics.cardsBottom - stripTop),
                             columns: Metrics.columns,
                             maxRowsPerPage: Metrics.maxRowsPerPage,
                             pageAxis: .horizontal)
        }
        
        // Landscape has height to spare nowhere and width to spare everywhere, so the spotlight
        // takes the width and the others queue up beside it in a single column. A two-column strip
        // under a 40%-height spotlight, which is what portrait does, leaves a 96 pt slot for a
        // 346 pt tile: the tiles ran off the bottom of the screen and under the control bar.
        guard hasSpotlight else {
            return StripPlan(spotlightFrame: metrics.cardsFrame,
                             stripFrame: metrics.cardsFrame,
                             columns: Metrics.landscapeColumnsWithoutSpotlight,
                             maxRowsPerPage: Metrics.maxRowsPerLandscapePage,
                             pageAxis: .vertical)
        }
        let rows = CGFloat(Metrics.landscapeColumnMinimumRows)
        let widthThatFitsTheRows = (metrics.cardsBottom - (rows - 1) * Metrics.spacing) / rows * Metrics.stripAspectRatio
        let columnWidth = min(max(min(metrics.area.width * Metrics.landscapeColumnFraction, widthThatFitsTheRows),
                                  Metrics.landscapeColumnRange.lowerBound),
                              Metrics.landscapeColumnRange.upperBound)
        let columnX = metrics.cardsTrailing - columnWidth
        return StripPlan(spotlightFrame: CGRect(x: metrics.cardsLeading,
                                                y: 0,
                                                width: columnX - Metrics.spacing - metrics.cardsLeading,
                                                height: metrics.cardsBottom),
                         stripFrame: CGRect(x: columnX, y: 0, width: columnWidth, height: metrics.cardsBottom),
                         columns: 1,
                         maxRowsPerPage: Metrics.maxRowsPerLandscapePage,
                         pageAxis: .vertical)
    }
    
    /// The spotlight, and everyone else in pages of a grid beside or beneath it so tiles keep their
    /// size however big the call gets. Alone (the spotlight is never ourselves) our own tile stands
    /// in the spotlight slot and slides into its cell as the first person arrives.
    private static func group(tiles: [ElementCallTile], spotlightMemberID: String?, currentPage: Int, metrics: Metrics) -> ElementCallStageLayout {
        var placements: [ElementCallTilePlacement] = []
        let spotlightTile = tiles.first { $0.memberID == spotlightMemberID }
        let plan = plan(metrics: metrics, hasSpotlight: spotlightTile != nil)
        
        if let spotlight = spotlightTile {
            placements.append(ElementCallTilePlacement(tile: spotlight,
                                                       frame: plan.spotlightFrame,
                                                       appearance: .card,
                                                       isSpotlight: true,
                                                       page: nil,
                                                       zIndex: 1))
        }
        
        let strip = tiles.filter { $0.memberID != spotlightMemberID }
        if placements.isEmpty, strip.count == 1, let only = strip.first {
            // Nobody to compare against, so the one tile takes the room the spotlight would have
            // had: the whole stage in landscape, the spotlight slot in portrait, which is where it
            // is already sitting when the first person arrives and the strip appears beneath it.
            let soloFrame = metrics.isLandscape ? metrics.cardsFrame : plan.spotlightFrame
            placements.append(ElementCallTilePlacement(tile: only,
                                                       frame: soloFrame,
                                                       appearance: .card,
                                                       isSpotlight: false,
                                                       page: nil,
                                                       zIndex: 1))
            return ElementCallStageLayout(placements: placements, pageCount: 1, pageAxis: plan.pageAxis)
        }
        
        let cellWidth = (plan.stripFrame.width - CGFloat(plan.columns - 1) * Metrics.spacing) / CGFloat(plan.columns)
        let cellHeight = cellWidth / Metrics.stripAspectRatio
        let rowsThatFit = Int(((plan.stripFrame.height + Metrics.spacing) / (cellHeight + Metrics.spacing)).rounded(.down))
        let rowsPerPage = min(plan.maxRowsPerPage, max(1, rowsThatFit))
        let perPage = rowsPerPage * plan.columns
        let pageCount = max(1, (strip.count + perPage - 1) / perPage)
        
        // The column runs the full height but its rows rarely divide it exactly, and on an iPad the
        // remainder is most of a tile: centring puts it half above and half below instead of
        // leaving the column hanging from the top with a hole under it. Centred on the page's
        // capacity rather than on how many tiles this page happens to hold, so a half-full last
        // page keeps its tiles where the full pages had them.
        let usedHeight = CGFloat(rowsPerPage) * cellHeight + CGFloat(rowsPerPage - 1) * Metrics.spacing
        let rowsOffset = plan.pageAxis == .vertical ? max(0, plan.stripFrame.height - usedHeight) / 2 : 0
        
        for (index, tile) in strip.enumerated() {
            let page = index / perPage
            let row = (index % perPage) / plan.columns
            let column = index % plan.columns
            // A page off to the side is a page's worth of stage away, which is what makes the swipe
            // a translation of rects rather than a rebuild of views.
            let pageOffset = CGFloat(page - currentPage)
            var x = plan.stripFrame.minX + CGFloat(column) * (cellWidth + Metrics.spacing)
            var y = plan.stripFrame.minY + rowsOffset + CGFloat(row) * (cellHeight + Metrics.spacing)
            switch plan.pageAxis {
            case .horizontal:
                x += pageOffset * metrics.area.width
            case .vertical:
                y += pageOffset * metrics.area.height
            }
            placements.append(ElementCallTilePlacement(tile: tile,
                                                       frame: CGRect(x: x, y: y, width: cellWidth, height: cellHeight),
                                                       appearance: .card,
                                                       isSpotlight: false,
                                                       page: page,
                                                       zIndex: 0))
        }
        
        return ElementCallStageLayout(placements: placements,
                                      pageCount: pageCount,
                                      pageIndicatorCenter: pageCount > 1 ? indicatorCenter(plan: plan,
                                                                                           metrics: metrics,
                                                                                           rowsPerPage: rowsPerPage,
                                                                                           cellHeight: cellHeight) : nil,
                                      pageAxis: plan.pageAxis,
                                      pictureInPictureMemberID: spotlightTile?.memberID)
    }
    
    /// Portrait has room under the strip for a row of dots. Landscape has none, so they go in the
    /// gutter between the spotlight and the column, which is the one gap the layout guarantees.
    private static func indicatorCenter(plan: StripPlan, metrics: Metrics, rowsPerPage: Int, cellHeight: CGFloat) -> CGPoint {
        switch plan.pageAxis {
        case .horizontal:
            let stripBottom = plan.stripFrame.minY + CGFloat(rowsPerPage) * cellHeight + CGFloat(rowsPerPage - 1) * Metrics.spacing
            return CGPoint(x: metrics.area.width / 2, y: min(stripBottom + Metrics.spacing, metrics.cardsBottom))
        case .vertical:
            return CGPoint(x: plan.stripFrame.minX - Metrics.spacing / 2, y: plan.stripFrame.midY)
        }
    }
}
