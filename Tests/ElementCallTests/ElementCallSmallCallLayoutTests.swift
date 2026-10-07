//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallKit
@testable import ElementCallUI
import Foundation
import Testing

/// The small-call layout's rules (spec 019), as arithmetic with no view.
@MainActor
struct ElementCallSmallCallLayoutTests {
    private typealias Fixtures = ElementCallPreviewFixtures
    private typealias Layout = ElementCallSmallCallLayout
    
    private let me = Fixtures.tile("Me", isLocal: true, hasVideo: true)
    
    /// The phones `ios.md` works its figures out on, so a test failing here and the plan's tables
    /// can be compared number for number. An iPhone 17: 370 of card width and a 626 band.
    private static let iPhone17 = ElementCallStageLayout.Metrics(area: CGSize(width: 402, height: 756), bottomInset: 34, controlsClearance: 84, topBleed: 120)
    /// An iPhone SE (3rd generation): 343 of card width and a 495 band, with no home indicator.
    private static let iPhoneSE = ElementCallStageLayout.Metrics(area: CGSize(width: 375, height: 591), bottomInset: 0, controlsClearance: 84, topBleed: 80)
    /// An iPhone 17 on its side, the stage running under the sensor housing on the leading edge.
    private static let landscape = ElementCallStageLayout.Metrics(area: CGSize(width: 874, height: 402), bottomInset: 21, leadingInset: 62, trailingInset: 62, controlsClearance: 84)
    /// The two portrait phones, for parameterised tests: arguments are built off the main actor,
    /// where the metrics cannot be.
    enum Phone: CaseIterable {
        case iPhone17, iPhoneSE
        
        var metrics: ElementCallStageLayout.Metrics {
            self == .iPhone17 ? ElementCallSmallCallLayoutTests.iPhone17 : ElementCallSmallCallLayoutTests.iPhoneSE
        }
    }
    
    /// The floating tile above a shown control bar.
    private static let chromeShown = Layout.FloatingInsets(top: 0, bottom: 84)
    
    private static func people(_ names: [String], speaking: String? = nil, video: Set<String> = []) -> [ElementCallTile] {
        names.map { Fixtures.tile($0, hasVideo: video.contains($0), isSpeaking: $0 == speaking) }
    }
    
    private func arrival(_ tiles: [ElementCallTile]) -> ElementCallArrivalOrder {
        var order = ElementCallArrivalOrder()
        order.observe(tiles)
        return order
    }
    
    /// Arrival is the order given unless stated, as it is for a fixture.
    private func arrange(_ remote: [ElementCallTile],
                         own: Bool = true,
                         arrivedAs arrived: [ElementCallTile]? = nil,
                         speaker: MatrixRTCTileID? = nil,
                         corner: ElementCallOwnTileCorner = .bottomRight,
                         insets: Layout.FloatingInsets = chromeShown,
                         metrics: ElementCallStageLayout.Metrics = iPhone17) -> ElementCallStageLayout {
        let tiles = (own ? [me] : []) + remote
        let viewport = CGRect(origin: .zero, size: metrics.area)
        return Layout.arrange(.init(tiles: tiles,
                                    metrics: metrics,
                                    arrivalOrder: arrival(arrived ?? tiles),
                                    speakerID: speaker,
                                    ownCorner: corner,
                                    floatingInsets: insets),
                              viewport: viewport)
    }
    
    private func frame(of tile: ElementCallTile, in layout: ElementCallStageLayout) throws -> CGRect {
        try #require(layout.placements.first { $0.id == tile.id }).frame
    }
    
    private func placement(of tile: ElementCallTile, in layout: ElementCallStageLayout) throws -> ElementCallTilePlacement {
        try #require(layout.placements.first { $0.id == tile.id })
    }
    
    /// Points compared to a tenth: the arithmetic divides, and the plan's tables are rounded.
    private func close(_ lhs: CGFloat, _ rhs: CGFloat, within tolerance: CGFloat = 0.5) -> Bool {
        abs(lhs - rhs) <= tolerance
    }
    
    // MARK: - Selection (R1, R8, R33)
    
    @Test
    func appliesUpToFiveTilesAndNotSixInEitherDirection() {
        let five = [me] + Self.people(["B", "C", "D", "E"])
        let six = five + Self.people(["F"])
        #expect(Layout.applies(to: five))
        #expect(!Layout.applies(to: six))
        #expect(Layout.applies(to: Array(six.dropLast())))
    }
    
    /// R8: a remote share sends even a two-person call to the grid, and is not what is counted.
    @Test
    func aRemoteShareSelectsTheGrid() {
        #expect(!Layout.applies(to: [me, Fixtures.share("Bob"), Fixtures.tile("Bob")]))
    }
    
    /// R1: a participant with their camera off is still a tile.
    @Test
    func aCameraOffParticipantCounts() {
        #expect(!Layout.applies(to: [me] + Self.people(["B", "C", "D", "E", "F"])))
    }
    
    // MARK: - Alone and one to one (R3, R4)
    
    /// R3: alone, our tile floats in its corner as in any other small call, in both orientations.
    @Test
    func aloneOurTileFloatsInItsCorner() throws {
        for metrics in [Self.iPhone17, Self.landscape] {
            let layout = arrange([], metrics: metrics)
            let own = try placement(of: me, in: layout)
            #expect(own.appearance == .floating)
            #expect(own.frame == Layout.floatingFrame(corner: .bottomRight, size: own.frame.size, metrics: metrics, insets: Self.chromeShown))
            #expect(layout.placements.count == 1)
            #expect(layout.isStatic)
            #expect(layout.readingOrder == [me.id])
        }
        #expect(!Layout.isFullBleed([me]))
        #expect(Layout.isFullBleed([me, Fixtures.tile("Bob")]))
    }
    
    /// R4: the other person runs behind both bars, and is shown whole only for a landscape picture
    /// on a portrait stage; we float over them.
    @Test
    func oneToOneTheOtherPersonFillsTheScreenAndWeFloat() throws {
        let bob = Fixtures.tile("Bob", hasVideo: true)
        let portrait = arrange([bob])
        let remote = try placement(of: bob, in: portrait)
        #expect(remote.appearance == .fullBleed)
        #expect(remote.contentFit == .fitWhenLandscape)
        #expect(remote.frame.minY == -120)
        #expect(remote.frame.maxY == 756)
        #expect(try placement(of: me, in: portrait).appearance == .floating)
        
        let landscape = arrange([bob], metrics: Self.landscape)
        #expect(try placement(of: bob, in: landscape).contentFit == .standard)
        #expect(try frame(of: bob, in: landscape) == CGRect(x: 0, y: 0, width: 874, height: 402))
        #expect(try placement(of: me, in: landscape).appearance == .floating)
    }
    
    // MARK: - Portrait (R5, R6, R11)
    
    /// R5: one above the other, 4:3, as wide as the stage allows, from the top.
    @Test(arguments: Phone.allCases)
    func threeTilesThePairIsStackedFullWidthFromTheTop(phone: Phone) throws {
        let metrics = phone.metrics
        let remote = Self.people(["Bob", "Carol"])
        let layout = arrange(remote, metrics: metrics)
        let first = try frame(of: remote[0], in: layout)
        let second = try frame(of: remote[1], in: layout)
        #expect(first.minY == 0)
        #expect(second.minY == first.maxY + 12)
        #expect(first.minX == second.minX)
        #expect(first.size == second.size)
        #expect(close(first.width / first.height, 4.0 / 3.0, within: 0.001))
        // As wide as they can be: the full width on an iPhone 17, and on an SE as wide as two rows
        // fitting above the controls allow.
        #expect(close(first.width, min(metrics.cardsWidth, (metrics.cardsBottom - 12) / 2 * 4 / 3)))
        #expect(second.maxY <= metrics.cardsBottom)
    }
    
    /// R5 on a stage too short for two full-width rows: they shrink, still 4:3, and stay centred.
    @Test
    func thePairShrinksOnAShortStage() {
        let short = ElementCallStageLayout.Metrics(area: CGSize(width: 402, height: 560), bottomInset: 0, controlsClearance: 84)
        let frames = Layout.pairFrames(metrics: short)
        #expect(close(frames[1].maxY, short.cardsBottom))
        #expect(frames[0].width < short.cardsWidth)
        #expect(close(frames[0].width / frames[0].height, 4.0 / 3.0, within: 0.001))
        #expect(close(frames[0].midX, (short.cardsLeading + short.cardsTrailing) / 2))
    }
    
    /// R6: left, right, left, from the top of the band to its bottom, with the ordinary gap between
    /// rows rather than an overlap. Neither phone fits three rows at 80%, so both shrink: 268 pt on
    /// an iPhone 17, 209 pt on an SE.
    @Test(arguments: Phone.allCases)
    func fourTilesStaggerLeftRightLeftWithoutOverlapping(phone: Phone) throws {
        let metrics = phone.metrics
        let remote = Self.people(["Bob", "Carol", "Dan"])
        let frames = try remote.map { try frame(of: $0, in: arrange(remote, metrics: metrics)) }
        let height = (metrics.cardsBottom - 24) / 3
        #expect(frames.allSatisfy { close($0.height, height) && close($0.width, height * 4 / 3) })
        #expect(frames[0].width < 0.8 * metrics.cardsWidth)
        #expect(frames[0].minY == 0)
        #expect(close(frames[1].minY - frames[0].maxY, 12))
        #expect(close(frames[2].minY - frames[1].maxY, 12))
        #expect(close(frames[2].maxY, metrics.cardsBottom))
        #expect(frames[0].minX == metrics.cardsLeading && frames[2].minX == metrics.cardsLeading)
        #expect(frames[1].maxX == metrics.cardsTrailing)
    }
    
    /// R6: a stage tall enough keeps them at 80%, spread with a wider gap.
    @Test
    func theStaggerStaysAtItsWidthWhenItFits() {
        let tall = ElementCallStageLayout.Metrics(area: CGSize(width: 402, height: 900), bottomInset: 0, controlsClearance: 84)
        let frames = Layout.staggerFrames(metrics: tall)
        #expect(close(frames[0].width, 0.8 * tall.cardsWidth))
        #expect(frames[1].minY - frames[0].maxY >= 12)
    }
    
    /// R6: never below the minimum width, where a very short stage then overlaps them.
    @Test
    func theStaggerShrinksButNotBelowItsMinimum() {
        let short = ElementCallStageLayout.Metrics(area: CGSize(width: 402, height: 420), bottomInset: 0, controlsClearance: 84)
        let frames = Layout.staggerFrames(metrics: short)
        #expect(frames[0].width == Layout.staggerMinimumWidth)
        #expect(frames[0].maxY > frames[1].minY)
    }
    
    /// R9: a speaker is shown by the ring alone. No arrangement moves, grows or raises a tile for
    /// whoever talks, the stack of three included.
    @Test(arguments: [1, 2, 3, 4])
    func outsideTheStaggerTheSpeakerMovesNothing(remoteCount: Int) {
        let remote = Self.people(Array(["Bob", "Carol", "Dan", "Erin"].prefix(remoteCount)))
        #expect(arrange(remote).placements == arrange(remote, speaker: remote[0].id).placements)
    }
    
    /// R11: two columns at the top, not centred, clear of the floating tile's bottom corners.
    @Test(arguments: Phone.allCases)
    func fiveTilesAreATwoByTwoAtTheTop(phone: Phone) throws {
        let metrics = phone.metrics
        let remote = Self.people(["Bob", "Carol", "Dan", "Erin"])
        let layout = arrange(remote, metrics: metrics)
        let frames = try remote.map { try frame(of: $0, in: layout) }
        #expect(frames[0].minY == 0 && frames[0].minX == metrics.cardsLeading)
        #expect(frames[1].minY == 0 && frames[1].maxX == metrics.cardsTrailing)
        #expect(frames[2].minY == frames[0].maxY + 12)
        #expect(frames.allSatisfy { close($0.width / $0.height, 4.0 / 3.0, within: 0.001) })
        let floating = try frame(of: me, in: layout)
        #expect(frames.allSatisfy { !$0.intersects(floating) })
    }
    
    // MARK: - Landscape (R2, R16)
    
    /// R16: ourselves inline and first, then by arrival; same-size 4:3 tiles in centred rows.
    @Test(arguments: [2, 3, 4])
    func landscapeOurTileIsInlineFirstInCentredRows(remoteCount: Int) throws {
        let remote = Self.people(Array(["Bob", "Carol", "Dan", "Erin"].prefix(remoteCount)))
        let metrics = Self.landscape
        let layout = arrange(remote, metrics: metrics)
        let own = try placement(of: me, in: layout)
        #expect(own.appearance == .card)
        let frames = try ([me] + remote).map { try frame(of: $0, in: layout) }
        #expect(Set(frames.map(\.size)).count == 1)
        #expect(close(frames[0].width / frames[0].height, 4.0 / 3.0, within: 0.001))
        #expect(frames[0].minX < frames[1].minX)
        // Each row centred on the cards, and the block on the band.
        for row in Dictionary(grouping: frames, by: \.minY).values {
            let span = row.reduce(CGRect.null) { $0.union($1) }
            #expect(close(span.minX - metrics.cardsLeading, metrics.cardsTrailing - span.maxX))
        }
        let block = frames.reduce(CGRect.null) { $0.union($1) }
        #expect(close(block.minY, metrics.cardsBottom - block.maxY))
        #expect(layout.readingOrder == ([me] + remote).map(\.id))
    }
    
    /// R16: the lone tile of the second row is the size of the others.
    @Test
    func landscapeFiveIsARowOfFourAndARowOfOne() throws {
        let remote = Self.people(["Bob", "Carol", "Dan", "Erin"])
        let layout = arrange(remote, metrics: Self.landscape)
        let frames = try ([me] + remote).map { try frame(of: $0, in: layout) }
        #expect(Set(frames.prefix(4).map(\.minY)).count == 1)
        #expect(frames[4].minY > frames[0].maxY)
        #expect(frames[4].size == frames[0].size)
        #expect(close(frames[4].midX, (Self.landscape.cardsLeading + Self.landscape.cardsTrailing) / 2))
        // Wide enough that four fill the row: shrinking is only for two rows that do not fit.
        #expect(close(frames[0].width, (Self.landscape.cardsWidth - 36) / 4))
    }
    
    // MARK: - Order (R7, R13, R27)
    
    /// Arrival decides the places, whatever the ranking: the same people in a new rank order give
    /// the same frames.
    @Test
    func arrivalNotRankDecidesThePlaces() throws {
        let bob = Fixtures.tile("Bob")
        let carol = Fixtures.tile("Carol")
        let dan = Fixtures.tile("Dan")
        let arrived = [me, bob, carol, dan]
        let ranked = arrange([dan, carol, bob], arrivedAs: arrived)
        let asArrived = arrange([bob, carol, dan], arrivedAs: arrived)
        for tile in [bob, carol, dan] {
            #expect(try frame(of: tile, in: ranked) == frame(of: tile, in: asArrived))
        }
        #expect(try frame(of: bob, in: ranked).minY == 0)
        #expect(ranked.readingOrder == [bob.id, carol.id, dan.id, me.id])
    }
    
    /// Each placement carries its rank, for the detail window, which covers every remote tile.
    @Test
    func placementsCarryRanksAndEverythingIsLive() throws {
        let bob = Fixtures.tile("Bob")
        let carol = Fixtures.tile("Carol")
        let layout = arrange([carol, bob], arrivedAs: [me, bob, carol])
        #expect(try placement(of: carol, in: layout).orderIndex == 0)
        #expect(try placement(of: bob, in: layout).orderIndex == 1)
        #expect(try placement(of: me, in: layout).orderIndex == nil)
        #expect(layout.detailWindow.ranks == 0..<2)
        #expect(layout.placements.allSatisfy { $0.visibility == .live })
        #expect(layout.hiddenTileIDs.isEmpty)
        #expect(layout.contentHeight == Self.iPhone17.area.height)
    }
    
    // MARK: - Our floating tile (R10, R17, R19, R21, R28)
    
    @Test
    func theFloatingTileTakesTheShapeOfThePicture() {
        #expect(Layout.floatingSize(hasVideo: false, videoAspect: 16.0 / 9.0, isLandscape: false) == Layout.floatingAvatarSize)
        #expect(Layout.floatingSize(hasVideo: true, videoAspect: 9.0 / 16.0, isLandscape: true) == Layout.floatingPortraitSize)
        #expect(Layout.floatingSize(hasVideo: true, videoAspect: 4.0 / 3.0, isLandscape: false) == Layout.floatingLandscapeSize)
        // Before the first frame, the stage's orientation.
        #expect(Layout.floatingSize(hasVideo: true, videoAspect: nil, isLandscape: false) == Layout.floatingPortraitSize)
        #expect(Layout.floatingSize(hasVideo: true, videoAspect: nil, isLandscape: true) == Layout.floatingLandscapeSize)
        // A portrait shape and its landscape turn, and a square: whatever the sizes are tuned to.
        #expect(Layout.floatingPortraitSize.width == Layout.floatingLandscapeSize.height)
        #expect(Layout.floatingAvatarSize.width == Layout.floatingAvatarSize.height)
    }
    
    /// R19: bottom right over a shown bar ends 16 pt inside the cards' trailing edge and 16 pt above
    /// the bar, which on an iPhone 17 is x 386, y 622.
    @Test
    func theFloatingTileSitsInItsCornerClearOfTheChrome() {
        let size = Layout.floatingPortraitSize
        let metrics = Self.iPhone17
        let bottomRight = Layout.floatingFrame(corner: .bottomRight, size: size, metrics: metrics, insets: Self.chromeShown)
        #expect(bottomRight.maxX == 386 && bottomRight.maxY == 622)
        #expect(bottomRight.size == size)
        #expect(Layout.floatingFrame(corner: .bottomRight, size: size, metrics: metrics, insets: .zero).maxY == metrics.safeBottom - 16)
        #expect(Layout.floatingFrame(corner: .topLeft, size: size, metrics: metrics, insets: .init(top: 60, bottom: 84)).origin == CGPoint(x: 16, y: 76))
    }
    
    /// R21: released, the tile goes to the corner of the quadrant its centre is in, and a drag
    /// stops at the edges.
    @Test
    func aReleaseSnapsToTheNearestCornerAndADragStopsAtTheEdge() {
        let bounds = CGRect(x: 16, y: 16, width: 370, height: 600)
        #expect(Layout.nearestCorner(to: CGPoint(x: 100, y: 100), in: bounds) == .topLeft)
        #expect(Layout.nearestCorner(to: CGPoint(x: 300, y: 100), in: bounds) == .topRight)
        #expect(Layout.nearestCorner(to: CGPoint(x: 100, y: 500), in: bounds) == .bottomLeft)
        #expect(Layout.nearestCorner(to: CGPoint(x: 300, y: 500), in: bounds) == .bottomRight)
        
        let frame = CGRect(x: 246, y: 406, width: 140, height: 210)
        #expect(Layout.clampedDrag(CGSize(width: 500, height: 500), from: frame, in: bounds) == .zero)
        #expect(Layout.clampedDrag(CGSize(width: -1000, height: -1000), from: frame, in: bounds) == CGSize(width: -230, height: -390))
        #expect(Layout.clampedDrag(CGSize(width: -10, height: 0), from: frame, in: bounds) == CGSize(width: -10, height: 0))
    }
    
    /// R21 with inertia: a flick goes to the corner it was thrown towards, a slow release stays in
    /// the quadrant it was dropped in.
    @Test
    func aFlickCarriesTheTileToTheCornerItWasThrownTowards() {
        let bounds = CGRect(x: 16, y: 16, width: 370, height: 600)
        let bottomRight = CGPoint(x: 300, y: 500)
        // Barely moving: where it was let go.
        #expect(Layout.releaseCorner(center: bottomRight, velocity: CGSize(width: 0, height: -50), in: bounds) == .bottomRight)
        // Flicked upwards from the bottom half: the top corner on the same side.
        #expect(Layout.releaseCorner(center: bottomRight, velocity: CGSize(width: 0, height: -1500), in: bounds) == .topRight)
        // Flicked up and to the left: the far corner.
        #expect(Layout.releaseCorner(center: bottomRight, velocity: CGSize(width: -1500, height: -1500), in: bounds) == .topLeft)
        // About half a second of coasting, as a scroll view's normal rate gives.
        #expect(abs(Layout.projectedDistance(1000) - 499) < 1)
    }
    
    /// R18: corners are physical, so the arithmetic has no notion of reading direction to follow.
    @Test
    func theCornerIsKeptAcrossLayouts() throws {
        let remote = Self.people(["Bob", "Carol"])
        let topLeft = try frame(of: me, in: arrange(remote, corner: .topLeft))
        #expect(topLeft.minX == Self.iPhone17.cardsLeading)
        #expect(topLeft.minY == 16)
        let alone = try frame(of: me, in: arrange([Fixtures.tile("Bob")], corner: .topLeft, metrics: Self.landscape))
        #expect(alone.minX == Self.landscape.cardsLeading)
    }
    
    // MARK: - Speaker (R9, R15)
    
    /// Two people starting together: the first to have arrived, whatever the ranking says.
    @Test
    func theFirstSpeakerByArrivalIsChosen() {
        let bob = Fixtures.tile("Bob", isSpeaking: true)
        let carol = Fixtures.tile("Carol", isSpeaking: true)
        let order = arrival([me, bob, carol])
        #expect(Layout.speaker(tiles: [me, carol, bob], arrivalOrder: order, held: nil) == bob.id)
    }
    
    /// Talking over each other does not swap the tile on top on every word.
    @Test
    func theHeldSpeakerKeepsTheSlotWhileStillSpeaking() {
        let bob = Fixtures.tile("Bob", isSpeaking: true)
        let carol = Fixtures.tile("Carol", isSpeaking: true)
        let tiles = [me, bob, carol]
        #expect(Layout.speaker(tiles: tiles, arrivalOrder: arrival(tiles), held: carol.id) == carol.id)
    }
    
    /// R9: when nobody is speaking the last speaker stays, until they leave.
    @Test
    func theLastSpeakerIsHeldThroughSilenceUntilTheyLeave() {
        let bob = Fixtures.tile("Bob")
        let carol = Fixtures.tile("Carol")
        let tiles = [me, bob, carol]
        #expect(Layout.speaker(tiles: tiles, arrivalOrder: arrival(tiles), held: carol.id) == carol.id)
        let gone = [me, bob]
        #expect(Layout.speaker(tiles: gone, arrivalOrder: arrival(gone), held: carol.id) == nil)
    }
    
    /// R15: we never count as the speaker, however loud.
    @Test
    func weAreNeverTheSpeaker() {
        let loudMe = Fixtures.tile("Me", isLocal: true, isSpeaking: true)
        let tiles = [loudMe, Fixtures.tile("Bob")]
        #expect(Layout.speaker(tiles: tiles, arrivalOrder: arrival(tiles), held: nil) == nil)
    }
    
    // MARK: - Picture in Picture (R15)
    
    @Test
    func pictureInPictureFollowsTheSpeakerThenTheFirstArrivalThenUs() {
        let bob = Fixtures.tile("Bob")
        let carol = Fixtures.tile("Carol")
        let tiles = [me, carol, bob]
        let order = arrival([me, bob, carol])
        #expect(Layout.pictureInPictureTile(tiles: tiles, arrivalOrder: order, speakerID: carol.id) == carol.id)
        #expect(Layout.pictureInPictureTile(tiles: tiles, arrivalOrder: order, speakerID: nil) == bob.id)
        #expect(Layout.pictureInPictureTile(tiles: [me], arrivalOrder: arrival([me]), speakerID: nil) == me.id)
    }
    
    /// The window follows the small call's choice exactly, and the grid's spotlight with fallbacks.
    @Test
    func theWindowIsTheSmallCallsChoiceExactlyAndTheSpotlightOtherwise() {
        let carol = Fixtures.tile("Carol", isSpeaking: true)
        let small = Fixtures.connected(tiles: [me, Fixtures.tile("Bob"), carol])
        #expect(small.pictureInPictureTile.id == carol.id)
        #expect(small.pictureInPictureTile.isExact)
        let share = Fixtures.share("Bob")
        let grid = Fixtures.connected(tiles: [me, share, Fixtures.tile("Bob"), carol])
        #expect(grid.pictureInPictureTile.id == share.id)
        #expect(!grid.pictureInPictureTile.isExact)
    }
    
    // MARK: - Accessibility (R25-R27)
    
    /// R26: our tile says whether our camera is on, and where it floats; inline, no corner.
    @Test
    func ourTileIsAnnouncedWithItsCameraAndCorner() {
        #expect(ElementCallTileView.ownLabel(name: "You", hasVideo: true, corner: .bottomRight) == "You, camera on, bottom right")
        #expect(ElementCallTileView.ownLabel(name: "You", hasVideo: false, corner: .topLeft) == "You, camera off, top left")
        #expect(ElementCallTileView.ownLabel(name: "You", hasVideo: true, corner: nil) == "You, camera on")
    }
    
    /// R25: every corner but the one it is in, so VoiceOver can reach all four without a drag.
    @Test
    func theOtherThreeCornersAreOfferedAsActions() {
        for corner in ElementCallOwnTileCorner.allCases {
            let offered = ElementCallTileView.cornersToMoveTo(from: corner)
            #expect(offered.count == 3)
            #expect(!offered.contains(corner))
        }
        #expect(ElementCallTileView.spokenName(of: .bottomLeft) == "bottom left")
    }
    
    /// R27: alone, our tile is all there is to read; with others, it comes after them.
    @Test
    func aloneOrFloatingOurTileIsReadLast() {
        #expect(arrange([]).readingOrder == [me.id])
        let remote = Self.people(["Bob", "Carol"])
        #expect(arrange(remote).readingOrder == remote.map(\.id) + [me.id])
    }
}
