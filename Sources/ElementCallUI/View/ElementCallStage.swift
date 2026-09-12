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
/// and a third person joining pulls both into the grid. A rotation is the same kind of move, which
/// is why the two orientations are one set of rects and not two view hierarchies.
///
/// The strip pages by swiping, sideways in portrait and up the column in landscape; only the tiles
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
    let callProvider: () -> MatrixRTCCall?
    /// How far above the safe area the floating controls reach.
    let controlsClearance: CGFloat
    let onAction: (ElementCallScreenViewAction) -> Void
    
    @State private var currentPage = 0
    /// The page the last snap landed on, trailing `currentPage` while the snap animates.
    @State private var settledPage = 0
    @State private var dragTranslation: CGFloat = 0
    
    private static let animation: Animation = .spring(duration: 0.45, bounce: 0.15)
    
    var body: some View {
        // The reader stays inside the safe area, where it reports the insets (a reader that ignores
        // the safe area grows by them but reports none); the stage extends by the bottom one so a
        // full-bleed picture can run under the home indicator. The side insets matter only in
        // landscape, where the sensor housing moves onto one of them and would clip a card's corner.
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            let stage = ElementCallStageLayout.compute(tiles: tiles,
                                                       spotlightMemberID: spotlightMemberID,
                                                       layout: layout,
                                                       currentPage: currentPage,
                                                       metrics: .init(area: CGSize(width: geometry.size.width, height: geometry.size.height + insets.bottom),
                                                                      bottomInset: insets.bottom,
                                                                      leadingInset: insets.leading,
                                                                      trailingInset: insets.trailing,
                                                                      controlsClearance: controlsClearance))
            ZStack(alignment: .topLeading) {
                ForEach(stage.placements) { placement in
                    tileView(for: placement, in: stage)
                }
                if let center = stage.pageIndicatorCenter {
                    pageIndicator(pageCount: stage.pageCount, axis: stage.pageAxis)
                        .position(center)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            // `.contain` rather than the bare identifier: the stage has to be addressable itself
            // without swallowing the tiles inside it, which carry identifiers of their own.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(ElementCallAccessibilityIdentifiers.stage)
            .gesture(pagingGesture(pageCount: stage.pageCount, axis: stage.pageAxis, size: geometry.size),
                     including: stage.pageCount > 1 ? .all : .subviews)
            .animation(Self.animation, value: stage)
            .onChange(of: stage.pageCount) { _, pageCount in
                currentPage = min(currentPage, max(0, pageCount - 1))
                settledPage = min(settledPage, max(0, pageCount - 1))
            }
            .onChange(of: stage.pageAxis) { _, _ in
                // A rotation mid-swipe would otherwise carry a horizontal finger distance into a
                // vertical strip and fling it several pages.
                dragTranslation = 0
            }
            .onChange(of: releasedMemberIDs(in: stage), initial: true) { _, released in
                // A side effect, so it belongs here rather than in the body: releasing is a message
                // to the SFU, and the body runs whenever anything at all about the call changes.
                callProvider()?.setReleasedVideoMembers(released)
            }
        }
    }
    
    private func tileView(for placement: ElementCallTilePlacement, in stage: ElementCallStageLayout) -> some View {
        let isPaged = placement.page != nil
        let visibility = visibility(for: placement.page)
        return ElementCallTileView(tile: placement.tile,
                                   callProvider: callProvider,
                                   isSpotlight: placement.isSpotlight,
                                   appearance: placement.appearance,
                                   memberCount: memberCount,
                                   isVideoSuspended: visibility != .live,
                                   onAction: onAction)
            .background {
                if placement.tile.memberID == stage.pictureInPictureMemberID {
                    PictureInPictureSourceView(sourceView: pictureInPictureSourceView)
                }
            }
            .frame(width: placement.frame.width, height: placement.frame.height)
            .position(x: placement.frame.midX + (isPaged && stage.pageAxis == .horizontal ? dragTranslation : 0),
                      y: placement.frame.midY + (isPaged && stage.pageAxis == .vertical ? dragTranslation : 0))
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
    
    private func visibility(for page: Int?) -> ElementCallTileVisibility {
        .forPage(page, currentPage: currentPage, livePages: livePages)
    }
    
    private func releasedMemberIDs(in stage: ElementCallStageLayout) -> Set<String> {
        Set(stage.placements.lazy.filter { visibility(for: $0.page) == .released }.map(\.tile.memberID))
    }
    
    private func pageIndicator(pageCount: Int, axis: Axis) -> some View {
        let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(spacing: 6))
        return layout {
            ForEach(0..<pageCount, id: \.self) { page in
                Circle()
                    .fill(page == currentPage ? style.theme.iconPrimary : style.theme.iconQuaternary)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
    
    /// The strip follows the finger and snaps to the nearest page, or the next one for a flick.
    /// Portrait pages sideways under the spotlight; landscape pages the column up and down, which is
    /// the direction the column runs and so the direction a thumb on it expects to push.
    private func pagingGesture(pageCount: Int, axis: Axis, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                dragTranslation = axis == .horizontal ? value.translation.width : value.translation.height
            }
            .onEnded { value in
                let projected = axis == .horizontal ? value.predictedEndTranslation.width : value.predictedEndTranslation.height
                let extent = axis == .horizontal ? size.width : size.height
                var page = currentPage
                if projected < -extent / 3 {
                    page += 1
                } else if projected > extent / 3 {
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
    
    static func noCall() -> MatrixRTCCall? {
        nil
    }
    
    static func stage(tiles: [ElementCallTile], spotlight: String? = nil, layout: ElementCallLayout) -> some View {
        ElementCallStage(tiles: tiles,
                         spotlightMemberID: spotlight,
                         layout: layout,
                         memberCount: tiles.count,
                         pictureInPictureSourceView: UIView(),
                         callProvider: noCall,
                         controlsClearance: ElementCallView.controlsClearance) { _ in }
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
