//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCall
import ElementCallKit
import SwiftUI

/// The tiles of the call, each drawn once at the rect `ElementCallStageLayout` gives it. Because a
/// tile is the same view wherever the layout puts it, every change of arrangement animates as a
/// move: the new speaker's card grows into the spotlight while the old one shrinks into the strip,
/// our full-screen picture in a DM slides into the corner as the other person's takes the screen,
/// and a third person joining pulls both into the grid. The strip pages by swiping; only the tiles
/// on the page in view decode video, the others stand in with their avatar. A page comes live as
/// soon as a swipe starts pulling it in and the one it replaces stays live until the snap has
/// finished, so both move with their pictures: a hosted video view mounted mid-animation would
/// appear straight at its destination.
struct ElementCallStage: View {
    @Environment(\.elementCallStyle) private var style
    let tiles: [ElementCallTile]
    let spotlightMemberID: String?
    let layout: ElementCallLayout
    let memberCount: Int
    let pictureInPictureSourceView: UIView
    let callProvider: () -> MatrixRtcCall?
    /// How far above the safe area the floating controls reach.
    let controlsClearance: CGFloat
    let onAction: (ElementCallScreenViewAction) -> Void
    
    @State private var currentPage = 0
    /// The page the last snap landed on, trailing `currentPage` while the snap animates.
    @State private var settledPage = 0
    @State private var dragTranslation: CGFloat = 0
    
    private static let animation: Animation = .spring(duration: 0.45, bounce: 0.15)
    
    var body: some View {
        // The reader stays inside the safe area, where it reports the bottom inset (a reader that
        // ignores the safe area grows by the inset but reports none); the stage extends by that
        // much so a full-bleed picture can run under the home indicator.
        GeometryReader { geometry in
            let bottomInset = geometry.safeAreaInsets.bottom
            let stage = ElementCallStageLayout.compute(tiles: tiles,
                                                       spotlightMemberID: spotlightMemberID,
                                                       layout: layout,
                                                       currentPage: currentPage,
                                                       metrics: .init(area: CGSize(width: geometry.size.width, height: geometry.size.height + bottomInset),
                                                                      bottomInset: bottomInset,
                                                                      controlsClearance: controlsClearance))
            ZStack(alignment: .topLeading) {
                ForEach(stage.placements) { placement in
                    tileView(for: placement, in: stage)
                }
                if let center = stage.pageIndicatorCenter {
                    pageIndicator(pageCount: stage.pageCount)
                        .position(center)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(pagingGesture(pageCount: stage.pageCount, width: geometry.size.width), including: stage.pageCount > 1 ? .all : .subviews)
            .animation(Self.animation, value: stage)
            .onChange(of: stage.pageCount) { _, pageCount in
                currentPage = min(currentPage, max(0, pageCount - 1))
                settledPage = min(settledPage, max(0, pageCount - 1))
            }
        }
    }
    
    private func tileView(for placement: ElementCallTilePlacement, in stage: ElementCallStageLayout) -> some View {
        let isPaged = placement.page != nil
        let isLive = placement.page.map { livePages.contains($0) } ?? true
        return ElementCallTileView(tile: placement.tile,
                                   callProvider: callProvider,
                                   isSpotlight: placement.isSpotlight,
                                   appearance: placement.appearance,
                                   memberCount: memberCount,
                                   isVideoSuspended: !isLive,
                                   onAction: onAction)
            .background {
                if placement.tile.memberID == stage.pictureInPictureMemberID {
                    PictureInPictureSourceView(sourceView: pictureInPictureSourceView)
                }
            }
            .frame(width: placement.frame.width, height: placement.frame.height)
            .position(x: placement.frame.midX + (isPaged ? dragTranslation : 0), y: placement.frame.midY)
            .zIndex(placement.zIndex)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
    }
    
    /// The page in view, the one a swipe in progress is pulling in, and the one a snap is leaving.
    private var livePages: Set<Int> {
        var pages: Set<Int> = [currentPage, settledPage]
        if dragTranslation > 0 {
            pages.insert(currentPage - 1)
        } else if dragTranslation < 0 {
            pages.insert(currentPage + 1)
        }
        return pages
    }
    
    private func pageIndicator(pageCount: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<pageCount, id: \.self) { page in
                Circle()
                    .fill(page == currentPage ? style.theme.iconPrimary : style.theme.iconQuaternary)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
    
    /// The strip follows the finger and snaps to the nearest page, or the next one for a flick.
    private func pagingGesture(pageCount: Int, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                dragTranslation = value.translation.width
            }
            .onEnded { value in
                let projected = value.predictedEndTranslation.width
                var page = currentPage
                if projected < -width / 3 {
                    page += 1
                } else if projected > width / 3 {
                    page -= 1
                }
                withAnimation(Self.animation) {
                    currentPage = min(max(0, page), pageCount - 1)
                    dragTranslation = 0
                } completion: {
                    settledPage = currentPage
                }
            }
    }
}

// MARK: - Previews

struct ElementCallStage_Previews: PreviewProvider, TestablePreview {
    static func tile(_ name: String, isLocal: Bool = false, isMuted: Bool = false, isSpeaking: Bool = false) -> ElementCallTile {
        ElementCallTile(memberID: "@\(name.lowercased()):example.com:DEVICE", userID: "@\(name.lowercased()):example.com", displayName: isLocal ? "You" : name,
                        avatarURL: nil, isLocal: isLocal, isMicrophoneMuted: isMuted, hasMicrophone: true, hasVideo: false, isScreenSharing: false,
                        isSpeaking: isSpeaking, hasHandRaised: false, isFrontCamera: isLocal, audioLevel: 0, stats: nil)
    }
    
    static let local = tile("Alice", isLocal: true)
    static let bob = tile("Bob", isMuted: true)
    static let group = [local, bob, tile("Carol", isSpeaking: true), tile("Dan"), tile("Erin"), tile("Frank"), tile("Grace"), tile("Heidi")]
    
    static func noCall() -> MatrixRtcCall? {
        nil
    }
    
    static func stage(tiles: [ElementCallTile], spotlight: String? = nil, layout: ElementCallLayout) -> some View {
        ElementCallStage(tiles: tiles,
                         spotlightMemberID: spotlight,
                         layout: layout,
                         memberCount: tiles.count,
                         pictureInPictureSourceView: UIView(),
                         callProvider: noCall,
                         controlsClearance: 84) { _ in }
            .background(ElementCallStyle.stock.theme.bgCanvasDefault)
            .environment(\.colorScheme, .dark)
    }
    
    static var previews: some View {
        stage(tiles: group, spotlight: group[2].memberID, layout: .group)
            .previewDisplayName("Group with spotlight")
        stage(tiles: [local], layout: .group)
            .previewDisplayName("Alone in a group call")
        stage(tiles: [local, bob], layout: .oneToOne)
            .previewDisplayName("One-to-one")
        stage(tiles: [local], layout: .oneToOne)
            .previewDisplayName("One-to-one, alone")
    }
}
