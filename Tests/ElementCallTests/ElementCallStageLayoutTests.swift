//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementCallUI
import Foundation
import Testing

/// Pins the rects the stage hands its tiles: a tile keeps its identity across every arrangement, so
/// these frames are what the moves animate between.
struct ElementCallStageLayoutTests {
    /// An iPhone in portrait: 393 wide, 700 of stage above a 34 pt home indicator, 84 pt of controls.
    /// Typed so the expectations compare like with like: `#expect` types each operand on its own.
    let width: CGFloat = 393
    let safeHeight: CGFloat = 700
    let controls: CGFloat = 84
    let margin: CGFloat = 16
    let spacing: CGFloat = 12
    let metrics = ElementCallStageLayout.Metrics(area: CGSize(width: 393, height: 734), bottomInset: 34, controlsClearance: 84)
    
    /// The same phone on its side: 874 x 402, a 21 pt home indicator along the bottom, the sensor
    /// housing 59 pt in on the leading edge, and the controls rail 84 pt in from the trailing one.
    let landscape = ElementCallStageLayout.Metrics(area: CGSize(width: 874, height: 402),
                                                   bottomInset: 21,
                                                   leadingInset: 59,
                                                   controlsClearance: 84)
    /// Where a landscape card may go: inside the sensor housing, inside the rail, above the indicator.
    let landscapeCards = CGRect(x: 75, y: 0, width: 699, height: 369)
    
    let local = tile("alice", isLocal: true)
    let bob = tile("bob")
    let carol = tile("carol")
    
    static func tile(_ name: String, isLocal: Bool = false) -> ElementCallTile {
        ElementCallTile(memberID: "@\(name):example.com:DEVICE", userID: "@\(name):example.com", displayName: name,
                        avatarURL: nil, isLocal: isLocal, isMicrophoneMuted: false, hasMicrophone: true, hasVideo: false, isScreenSharing: false,
                        isSpeaking: false, hasHandRaised: false, isFrontCamera: isLocal, audioLevel: 0, stats: nil)
    }
    
    func placement(_ tile: ElementCallTile, in layout: ElementCallStageLayout) throws -> ElementCallTilePlacement {
        try #require(layout.placements.first { $0.id == tile.id })
    }
    
    @Test
    func aloneInAGroupCallOurTileStandsInTheSpotlightSlot() throws {
        let layout = ElementCallStageLayout.compute(tiles: [local], spotlightMemberID: nil, layout: .group, currentPage: 0, metrics: metrics)
        let only = try placement(local, in: layout)
        #expect(only.frame == CGRect(x: margin, y: 0, width: width - 2 * margin, height: safeHeight * 0.4))
        #expect(only.appearance == .card)
        #expect(!only.isSpotlight)
        #expect(only.page == nil)
        #expect(layout.pageCount == 1)
        #expect(layout.pageIndicatorCenter == nil)
        #expect(layout.pictureInPictureMemberID == nil)
        
        // The first person to arrive takes the spotlight and we slide down into the strip.
        let joined = ElementCallStageLayout.compute(tiles: [local, bob], spotlightMemberID: bob.memberID, layout: .group, currentPage: 0, metrics: metrics)
        let spotlight = try placement(bob, in: joined)
        let ours = try placement(local, in: joined)
        #expect(spotlight.frame == only.frame)
        #expect(ours.frame.minY == only.frame.maxY + spacing)
        #expect(ours.frame.width < only.frame.width)
    }
    
    @Test
    func spotlightOnTopAndTheOthersInTwoColumnsBelow() throws {
        let layout = ElementCallStageLayout.compute(tiles: [local, bob, carol], spotlightMemberID: bob.memberID, layout: .group, currentPage: 0, metrics: metrics)
        let spotlight = try placement(bob, in: layout)
        #expect(spotlight.isSpotlight)
        #expect(spotlight.frame == CGRect(x: margin, y: 0, width: width - 2 * margin, height: safeHeight * 0.4))
        #expect(spotlight.page == nil)
        #expect(layout.pictureInPictureMemberID == bob.memberID)
        
        let first = try placement(local, in: layout)
        let second = try placement(carol, in: layout)
        let cellWidth = (width - 2 * margin - spacing) / 2
        #expect(first.frame.minX == margin)
        #expect(first.frame.minY == safeHeight * 0.4 + spacing)
        #expect(first.frame.width == cellWidth)
        #expect(abs(first.frame.height - cellWidth / 1.2) < 0.001)
        #expect(second.frame.minX == margin + cellWidth + spacing)
        #expect(second.frame.minY == first.frame.minY)
        #expect(first.page == 0)
        #expect(second.page == 0)
    }
    
    @Test
    func stripPagesOnceTheRowsThatFitAreFull() throws {
        // 700 - 84 - 12 = 604 above the controls; a spotlight leaves 604 - 292 = 312, room for two
        // 145 pt rows of two, so the fifth strip tile starts a second page.
        let others = (0..<7).map { Self.tile("m\($0)") }
        let layout = ElementCallStageLayout.compute(tiles: [local] + others, spotlightMemberID: local.memberID, layout: .group, currentPage: 0, metrics: metrics)
        #expect(layout.pageCount == 2)
        let onSecondPage = try placement(others[4], in: layout)
        #expect(onSecondPage.page == 1)
        #expect(onSecondPage.frame.minX == margin + width)
        #expect(onSecondPage.frame.minY == safeHeight * 0.4 + spacing)
        let onFirstPage = try placement(others[3], in: layout)
        #expect(onFirstPage.page == 0)
        #expect(onFirstPage.frame.minY > onSecondPage.frame.minY)
        #expect(layout.pageIndicatorCenter?.x == width / 2)
        
        let turned = ElementCallStageLayout.compute(tiles: [local] + others, spotlightMemberID: local.memberID, layout: .group, currentPage: 1, metrics: metrics)
        let lastMoved = try placement(others[6], in: turned)
        let firstMoved = try placement(others[0], in: turned)
        #expect(lastMoved.frame.minX == margin)
        #expect(firstMoved.frame.minX == margin - width)
        let spotlightBefore = try placement(local, in: layout)
        let spotlightAfter = try placement(local, in: turned)
        #expect(spotlightAfter.frame == spotlightBefore.frame)
    }
    
    @Test
    func promotionKeepsEveryTileAndMovesTwo() throws {
        let before = ElementCallStageLayout.compute(tiles: [local, bob, carol], spotlightMemberID: bob.memberID, layout: .group, currentPage: 0, metrics: metrics)
        let after = ElementCallStageLayout.compute(tiles: [local, bob, carol], spotlightMemberID: carol.memberID, layout: .group, currentPage: 0, metrics: metrics)
        #expect(Set(before.placements.map(\.id)) == Set(after.placements.map(\.id)))
        let (bobBefore, carolBefore, localBefore) = try (placement(bob, in: before), placement(carol, in: before), placement(local, in: before))
        let (bobAfter, carolAfter, localAfter) = try (placement(bob, in: after), placement(carol, in: after), placement(local, in: after))
        #expect(carolAfter.frame == bobBefore.frame)
        #expect(bobAfter.frame == carolBefore.frame)
        #expect(localAfter.frame == localBefore.frame)
    }
    
    @Test
    func aloneInADirectCallOurCameraRunsEdgeToEdge() throws {
        let layout = ElementCallStageLayout.compute(tiles: [local], spotlightMemberID: nil, layout: .oneToOne, currentPage: 0, metrics: metrics)
        let only = try placement(local, in: layout)
        #expect(only.frame == CGRect(origin: .zero, size: metrics.area))
        #expect(only.appearance == .fullBleed)
        #expect(layout.pictureInPictureMemberID == local.memberID)
    }
    
    @Test
    func theOtherPersonTakesTheScreenAndWeBecomeAThumbnailClearOfTheControls() throws {
        let layout = ElementCallStageLayout.compute(tiles: [local, bob], spotlightMemberID: nil, layout: .oneToOne, currentPage: 0, metrics: metrics)
        let remote = try placement(bob, in: layout)
        #expect(remote.frame == CGRect(origin: .zero, size: metrics.area))
        #expect(remote.appearance == .fullBleed)
        #expect(layout.pictureInPictureMemberID == bob.memberID)
        
        let thumbnail = try placement(local, in: layout)
        #expect(thumbnail.appearance == .thumbnail)
        #expect(thumbnail.zIndex > remote.zIndex)
        #expect(thumbnail.frame.maxX == width - margin)
        #expect(thumbnail.frame.maxY == safeHeight - controls - margin)
        #expect(thumbnail.frame.size == ElementCallStageLayout.thumbnailSize(in: CGSize(width: width, height: safeHeight)))
        #expect(abs(thumbnail.frame.width / thumbnail.frame.height - 2 / 3) < 0.001)
    }
    
    @Test
    func thumbnailFollowsTheOrientationAndStaysUnderHalfTheArea() {
        let portrait = ElementCallStageLayout.thumbnailSize(in: CGSize(width: 393, height: 700))
        #expect(portrait.width < portrait.height)
        #expect(abs(portrait.width - width * 0.38) < 0.001)
        
        let landscape = ElementCallStageLayout.thumbnailSize(in: CGSize(width: 700, height: 393))
        #expect(landscape.width > landscape.height)
        #expect(abs(landscape.height - width * 0.38) < 0.001)
        
        let square = ElementCallStageLayout.thumbnailSize(in: CGSize(width: 300, height: 300))
        #expect(square.width <= 150)
        #expect(square.height <= 150)
    }
    
    @Test
    func noTilesNoPlacements() {
        let layout = ElementCallStageLayout.compute(tiles: [], spotlightMemberID: nil, layout: .group, currentPage: 0, metrics: metrics)
        #expect(layout.placements.isEmpty)
        #expect(layout.pageCount == 0)
    }
    
    // MARK: - Landscape
    
    static let group = ["bob", "carol", "dan", "erin", "frank", "grace", "heidi"].map { tile($0) }
    
    @Test
    func landscapeGivesTheSpotlightTheWidthAndQueuesTheRestBesideIt() throws {
        let tiles = [local] + Self.group
        let layout = ElementCallStageLayout.compute(tiles: tiles, spotlightMemberID: bob.memberID, layout: .group, currentPage: 0, metrics: landscape)
        let spotlight = try placement(bob, in: layout)
        
        // Most of the width, all of the height between the top and the home indicator. Portrait's
        // 40%-of-the-height spotlight would be a 6:1 letterbox here.
        #expect(spotlight.isSpotlight)
        #expect(spotlight.frame.minX == landscapeCards.minX)
        #expect(spotlight.frame.minY == 0)
        #expect(spotlight.frame.height == landscapeCards.height)
        #expect(spotlight.frame.width > landscapeCards.width * 0.6)
        
        // Everyone else is one tile wide, in a column, in the order they came.
        let column = layout.placements.filter { !$0.isSpotlight }
        #expect(column.count == Self.group.count)
        #expect(Set(column.map(\.frame.width)).count == 1)
        #expect(Set(column.map(\.frame.minX)).count == 1)
        let columnX = try #require(column.first?.frame.minX)
        #expect(columnX > spotlight.frame.maxX)
        #expect(layout.pageAxis == .vertical)
    }
    
    /// The regression this whole layout exists for: portrait's arithmetic put a 346 pt tile into
    /// 96 pt of space, so tiles ran off the bottom of the screen and under the control bar.
    @Test
    func landscapeKeepsEveryTileOnScreenAndClearOfTheChrome() {
        let tiles = [local] + Self.group
        for page in 0..<4 {
            let layout = ElementCallStageLayout.compute(tiles: tiles, spotlightMemberID: bob.memberID, layout: .group, currentPage: page, metrics: landscape)
            // Only the page in view has to be on screen; the others are parked a stage away, which
            // is what makes the swipe a translation rather than a rebuild.
            for placement in layout.placements where placement.page == nil || placement.page == page {
                #expect(placement.frame.minX >= landscapeCards.minX)
                #expect(placement.frame.maxX <= landscapeCards.maxX)
                #expect(placement.frame.minY >= 0)
                #expect(placement.frame.maxY <= landscapeCards.maxY)
                #expect(placement.frame.height > 0)
            }
        }
    }
    
    @Test
    func landscapePagesUpTheColumnRatherThanSideways() throws {
        let tiles = [local] + Self.group
        let layout = ElementCallStageLayout.compute(tiles: tiles, spotlightMemberID: bob.memberID, layout: .group, currentPage: 0, metrics: landscape)
        
        // Two cells fit the column, so seven others need four pages.
        #expect(layout.pageCount == 4)
        let first = try #require(layout.placements.first { $0.page == 0 })
        let second = try #require(layout.placements.first { $0.page == 1 })
        #expect(second.frame.minX == first.frame.minX)
        #expect(second.frame.minY == first.frame.minY + landscape.area.height)
        
        // The dots stack in the gutter the layout guarantees between spotlight and column.
        let indicator = try #require(layout.pageIndicatorCenter)
        let spotlight = try placement(bob, in: layout)
        #expect(indicator.x < first.frame.minX)
        #expect(indicator.x > spotlight.frame.maxX)
    }
    
    @Test
    func landscapeCardsClearTheSensorHousingAndTheControlsRail() {
        let layout = ElementCallStageLayout.compute(tiles: [local] + Self.group, spotlightMemberID: bob.memberID, layout: .group, currentPage: 0, metrics: landscape)
        let onScreen = layout.placements.filter { $0.page == nil || $0.page == 0 }
        // 59 pt of housing plus the 16 pt margin on one side; 84 pt of rail plus the margin on the other.
        #expect(onScreen.map(\.frame.minX).min() == 75)
        #expect(onScreen.map(\.frame.maxX).max() == 774)
    }
    
    /// The column is sized to fit its tiles, not to a share of the width and then whatever happens.
    /// A phone on its side leaves the stage about 300 pt tall under the top bar, and 22% of 812 pt
    /// is a 179 pt column whose cells miss a second row by 8 pt: seven people became seven pages,
    /// each one tile beside half a column of nothing.
    @Test
    func aShortLandscapeStageNarrowsTheColumnRatherThanPagingEveryTile() throws {
        let tight = ElementCallStageLayout.Metrics(area: CGSize(width: 812, height: 300), bottomInset: 1, controlsClearance: 84)
        let layout = ElementCallStageLayout.compute(tiles: [local] + Self.group, spotlightMemberID: bob.memberID, layout: .group, currentPage: 0, metrics: tight)
        
        let onFirstPage = layout.placements.filter { $0.page == 0 }
        #expect(onFirstPage.count == 2)
        #expect(layout.pageCount == 4)
        // Still a usable column, not a sliver.
        let cell = try #require(onFirstPage.first?.frame)
        #expect(cell.width >= 140)
        // And the two of them still fit above the home indicator.
        #expect(onFirstPage.map(\.frame.maxY).max() ?? 0 <= tight.cardsBottom)
    }
    
    @Test
    func landscapeAloneGivesTheOneTileTheWholeStage() throws {
        let layout = ElementCallStageLayout.compute(tiles: [local], spotlightMemberID: nil, layout: .group, currentPage: 0, metrics: landscape)
        let only = try placement(local, in: layout)
        // Nobody to sit beside, so it takes the column's room too rather than leaving a gap.
        #expect(only.frame == landscapeCards)
        #expect(layout.pageCount == 1)
    }
    
    @Test
    func landscapeThumbnailDodgesTheRailInsteadOfTheBottomBar() throws {
        let layout = ElementCallStageLayout.compute(tiles: [local, bob], spotlightMemberID: nil, layout: .oneToOne, currentPage: 0, metrics: landscape)
        let main = try placement(bob, in: layout)
        let thumbnail = try placement(local, in: layout)
        
        #expect(main.appearance == .fullBleed)
        #expect(main.frame == CGRect(origin: .zero, size: landscape.area))
        // The rail is on the trailing edge now, so the thumbnail stops short of it rather than
        // hovering above a bottom bar that is no longer there.
        #expect(thumbnail.frame.maxX == landscape.area.width - 84 - 16)
        #expect(thumbnail.frame.maxY == landscape.area.height - 21 - 16)
    }
    
    // MARK: - Visibility
    
    @Test
    func onlyTheNeighbouringPagePausesAndTheRestIsReleased() {
        // A tile that never pages, and the page in view: both drawing.
        #expect(ElementCallTileVisibility.forPage(nil, currentPage: 3, livePages: [3]) == .live)
        #expect(ElementCallTileVisibility.forPage(3, currentPage: 3, livePages: [3]) == .live)
        // Either neighbour is one swipe away, so it keeps its subscription and only pauses.
        #expect(ElementCallTileVisibility.forPage(2, currentPage: 3, livePages: [3]) == .paused)
        #expect(ElementCallTileVisibility.forPage(4, currentPage: 3, livePages: [3]) == .paused)
        // Anything further is a closed tile in the core's sense, and costs a subscription to keep.
        #expect(ElementCallTileVisibility.forPage(1, currentPage: 3, livePages: [3]) == .released)
        #expect(ElementCallTileVisibility.forPage(9, currentPage: 3, livePages: [3]) == .released)
        // A swipe in progress has two pages on screen, and the one being left keeps its picture
        // until the snap finishes: a page that is live is live however far away it counts as.
        #expect(ElementCallTileVisibility.forPage(4, currentPage: 3, livePages: [3, 4]) == .live)
        #expect(ElementCallTileVisibility.forPage(2, currentPage: 3, livePages: [2, 3]) == .live)
    }
    
    @Test
    func aBigCallReleasesFarMoreThanItHolds() {
        // Thirty people, two to a landscape page: the point of the exercise is that what we keep
        // does not grow with the call.
        let tiles = (0..<30).map { Self.tile("member\($0)") }
        let layout = ElementCallStageLayout.compute(tiles: tiles, spotlightMemberID: tiles[0].memberID, layout: .group, currentPage: 0, metrics: landscape)
        let states = layout.placements.map { ElementCallTileVisibility.forPage($0.page, currentPage: 0, livePages: [0]) }
        #expect(states.filter { $0 == .live }.count == 3)
        #expect(states.filter { $0 == .paused }.count == 2)
        #expect(states.filter { $0 == .released }.count == 25)
    }
    
    // MARK: - Full screen
    
    @Test
    func fullScreenGivesOneTileTheWholeAreaAndHidesTheRest() throws {
        let tiles = (0..<30).map { Self.tile("member\($0)") }
        let layout = ElementCallStageLayout.compute(tiles: tiles,
                                                    spotlightMemberID: tiles[0].memberID,
                                                    fullscreenMemberID: tiles[7].memberID,
                                                    layout: .group,
                                                    currentPage: 0,
                                                    metrics: metrics)
        let only = try #require(layout.placements.first)
        #expect(layout.placements.count == 1)
        #expect(only.tile.memberID == tiles[7].memberID)
        #expect(only.appearance == .fullscreen)
        // The whole area, safe areas and the controls' clearance included: a fitted picture is
        // centred on what it is given.
        #expect(only.frame == CGRect(origin: .zero, size: metrics.area))
        #expect(only.page == nil)
        #expect(layout.pageCount == 1)
        // The window continues the picture you were actually watching.
        #expect(layout.pictureInPictureMemberID == tiles[7].memberID)
        
        // The twenty-nine nobody is looking at. Named rather than simply dropped: the stage derives
        // what it releases from the placements, so a single placement would otherwise release
        // nobody at the exact moment there is nobody left to watch.
        #expect(layout.hiddenMemberIDs.count == 29)
        #expect(!layout.hiddenMemberIDs.contains(tiles[7].memberID))
        #expect(layout.hiddenMemberIDs.contains(tiles[0].memberID))
    }
    
    /// The tiles full screen replaces do not vanish, they animate out, and a leaving view keeps its
    /// z position while it does. So the one growing has to be above every z position any other
    /// arrangement hands out, or something fades away on top of it: which is exactly what the
    /// spotlight's 1 did to a strip tile's 0.
    @Test
    func theFullScreenTileIsAboveEveryTileItReplaces() throws {
        let tiles = [local, bob, carol] + Self.group
        let everyOtherZIndex = [ElementCallLayout.group, .oneToOne].flatMap { layout in
            [metrics, landscape].flatMap { metrics in
                ElementCallStageLayout.compute(tiles: tiles,
                                               spotlightMemberID: bob.memberID,
                                               layout: layout,
                                               currentPage: 0,
                                               metrics: metrics).placements.map(\.zIndex)
            }
        }
        let highest = try #require(everyOtherZIndex.max())
        #expect(ElementCallStageLayout.fullscreenZIndex > highest)
        
        let fullScreen = ElementCallStageLayout.compute(tiles: tiles,
                                                        spotlightMemberID: bob.memberID,
                                                        fullscreenMemberID: carol.memberID,
                                                        layout: .group,
                                                        currentPage: 0,
                                                        metrics: metrics)
        #expect(fullScreen.placements.first?.zIndex == ElementCallStageLayout.fullscreenZIndex)
    }
    
    /// The member you were watching can leave. The arrangement has to stand on its own when that
    /// happens; the screen clears the stale id separately, and this is what makes the gap harmless.
    @Test
    func fullScreenOnAMemberWhoHasLeftFallsBackToTheOrdinaryLayout() throws {
        let layout = ElementCallStageLayout.compute(tiles: [local, bob, carol],
                                                    spotlightMemberID: bob.memberID,
                                                    fullscreenMemberID: "@ghost:example.com:DEVICE",
                                                    layout: .group,
                                                    currentPage: 0,
                                                    metrics: metrics)
        #expect(layout.placements.count == 3)
        #expect(layout.hiddenMemberIDs.isEmpty)
        #expect(try placement(bob, in: layout).isSpotlight)
    }
    
    @Test
    func fullScreenWorksInAOneToOneCallToo() {
        let layout = ElementCallStageLayout.compute(tiles: [local, bob],
                                                    spotlightMemberID: nil,
                                                    fullscreenMemberID: local.memberID,
                                                    layout: .oneToOne,
                                                    currentPage: 0,
                                                    metrics: metrics)
        #expect(layout.placements.count == 1)
        #expect(layout.placements.first?.tile.memberID == local.memberID)
        #expect(layout.hiddenMemberIDs == [bob.memberID])
    }
}
