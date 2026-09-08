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
}
