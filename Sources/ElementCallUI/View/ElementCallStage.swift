//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallHost
import ElementCallKit
import SwiftUI

/// The tiles of the call, each drawn once at the rect `ElementCallStageLayout` gives it. Because a
/// tile is the same view wherever the layout puts it, every change of arrangement animates as a
/// move: the speaker's card grows into the spotlight while the old one shrinks into the grid, a
/// third person joining pulls two rows into a grid, and a rotation is the same kind of move, which
/// is why the two orientations are one set of rects and not two view hierarchies.
///
/// **One `ZStack`, real scrolling.** Every composed tile sits in one `ZStack` inside a vertical
/// `ScrollView`, positioned in content coordinates; the offset is read back into the layout, which
/// places the spotlight at it so the spotlight counter-scrolls and reads as a sticky header while
/// staying in the same stack as the tiles it is promoted from. A `LazyVGrid` with pinned views
/// would give laziness for free, but a tile changing container — grid to header to fullscreen —
/// changes identity, remounts its video view and blinks to the avatar, which is the failure the
/// whole design exists to avoid. Laziness is the layout's: it composes only the rows within a
/// viewport of the screen.
struct ElementCallStage: View {
    @Environment(\.elementCallStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tiles: [ElementCallTile]
    let spotlightID: MatrixRTCTileID?
    /// The tile filling the screen, if any. Not a mode of the stage so much as one more arrangement
    /// of it: the tile keeps its identity, so it grows out of its cell rather than being replaced.
    var fullscreenID: MatrixRTCTileID?
    /// A harness asking for an offset; honoured once per request, clamped like a user's scroll.
    var scrollRequest: ElementCallScrollRequest?
    let memberCount: Int
    let pictureInPictureSourceView: UIView
    let callProvider: () -> MatrixRTCCall?
    /// How far above the safe area the floating controls reach.
    let controlsClearance: CGFloat
    /// Double tap. Ahead of `onAction` for the same reason as on the tile: that one is the trailing
    /// closure at every call site, and a new closure after it would quietly take its place.
    var onToggleFullscreen: (MatrixRTCTileID) -> Void = { _ in }
    /// Single tap, which only means anything while full screen.
    var onToggleChrome: () -> Void = { }
    /// A swipe or a VoiceOver adjustment on the spotlight asks for another hero (R22, R25).
    var onShowHero: (MatrixRTCTileID) -> Void = { _ in }
    let onAction: (ElementCallScreenViewAction) -> Void
    
    /// The visible top, in content coordinates. Fed back into the layout, which is what makes the
    /// spotlight sticky and the composed band follow the screen.
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollPosition = ScrollPosition(edge: .top)
    /// The tiles that were live on the last pass, for the layout's edge hysteresis.
    @State private var liveTileIDs: Set<MatrixRTCTileID> = []
    /// The offset to come back to. Full screen changes the stage's frame (the top bar goes, the
    /// picture runs under the status bar), and a scroller whose viewport grows clamps its offset
    /// without asking; leaving would land somewhere else (R63).
    @State private var offsetBeforeFullscreen: CGFloat?
    /// The first grid tile on screen, and the stage size it was seen at. After a rotation the tile
    /// that was first visible is still visible (R66): the offset is re-set to put it at the top of
    /// the grid area under the new arrangement.
    @State private var anchor: (tileID: MatrixRTCTileID, area: CGSize)?
    
    private static let animation: Animation = .spring(duration: 0.45, bounce: 0.15)
    
    private var animation: Animation? {
        // With reduce motion on, tiles change place without sliding (R41). That also stops the
        // fit blend on a promotion, which is the intended outcome.
        reduceMotion ? nil : Self.animation
    }
    
    var body: some View {
        // The reader stays inside the safe area, and reports the insets of every edge it sits
        // against, whether or not it extends under them. The scroller extends under the bottom
        // one so a full-bleed picture can run under the home indicator, so that inset is real to
        // the layout. The side ones are not: the reader's own edge is already at the sensor
        // housing, and adding them again put a second housing's width of nothing on each side of
        // the stage in landscape.
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            let metrics = ElementCallStageLayout.Metrics(area: CGSize(width: geometry.size.width, height: geometry.size.height + insets.bottom),
                                                         bottomInset: insets.bottom,
                                                         controlsClearance: controlsClearance)
            let stage = ElementCallStageLayout.compute(.init(tiles: tiles,
                                                             spotlightID: spotlightID,
                                                             fullscreenID: fullscreenID,
                                                             scrollOffset: scrollOffset,
                                                             liveTileIDs: liveTileIDs,
                                                             metrics: metrics))
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    ForEach(stage.placements) { placement in
                        tileView(for: placement, in: stage)
                    }
                    if let heroStack = stage.heroStack, let spotlight = stage.placements.first(where: \.isSpotlight) {
                        if metrics.isLandscape {
                            // Arrows on the landscape spotlight's edges, where it has width to
                            // spare; dots under the portrait one, where it has none. Plain
                            // siblings: the spotlight's pan belongs to the content root and
                            // declines touches that start on them (see the gesture).
                            ForEach([-1, 1], id: \.self) { step in
                                let frame = Self.arrowFrame(step: step, spotlight: spotlight.frame)
                                heroArrow(step: step, isEnabled: step < 0 ? heroStack.shown > 0 : heroStack.shown < heroStack.count - 1, in: stage)
                                    .position(x: frame.midX, y: frame.midY - stage.viewport.minY)
                                    .offset(y: stage.viewport.minY)
                                    // Pinned like the spotlight: never animated with the offset.
                                    .animation(nil, value: stage.viewport.minY)
                                    .zIndex(ElementCallStageLayout.spotlightZIndex + 0.5)
                            }
                        } else {
                            heroDots(heroStack)
                                .position(x: spotlight.frame.midX, y: spotlight.frame.maxY + ElementCallStageLayout.Metrics.heroDotsClearance / 2)
                                .zIndex(ElementCallStageLayout.spotlightZIndex + 0.5)
                        }
                    }
                }
                .frame(width: metrics.area.width, height: stage.contentHeight, alignment: .topLeading)
                .contentShape(Rectangle())
                // Once, on the content root: a drag that starts on the spotlight never scrolls the
                // grid (R64) and a sideways one switches heroes (R22). See the gesture for why it
                // is UIKit's and why it is here rather than on the tile.
                .gesture(ElementCallSpotlightPanGesture(spotlightFrame: stage.placements.first(where: \.isSpotlight)?.frame,
                                                        excluded: stage.heroStack != nil && metrics.isLandscape
                                                            ? stage.placements.first(where: \.isSpotlight).map { [Self.arrowFrame(step: -1, spotlight: $0.frame), Self.arrowFrame(step: 1, spotlight: $0.frame)] } ?? []
                                                            : []) { step in showHero(step, in: stage) })
                // On the arrangement with the scroll taken out, not on the layout itself: the
                // offset changes on every frame of a drag and must snap, or the sticky spotlight
                // trails the finger on the spring.
                .animation(animation, value: stage.motion)
            }
            // No snapping, no dots (R26); nothing moves the offset while a tile fills the screen.
            .scrollIndicators(.hidden)
            .scrollDisabled(fullscreenID != nil)
            .scrollPosition($scrollPosition)
            // The bottom clearance is the layout's, so the scroller must not add its own inset
            // for the home indicator on top of it.
            .ignoresSafeArea(.container, edges: .bottom)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                scrollOffset = offset
            }
            .onChange(of: Visibility(stage), initial: true) { _, visibility in
                // A side effect, so it belongs here rather than in the body: releasing is a message
                // to the SFU, and the body runs whenever anything at all about the call changes.
                callProvider()?.setVideoVisibility(paused: visibility.paused, released: visibility.released)
            }
            .onChange(of: stage.detailWindow, initial: true) { _, window in
                // The layout is what knows what is on screen, so it drives the core's detail
                // window too (R52, R55); the call declines an equal one.
                callProvider()?.setDetailWindow(window)
            }
            .onChange(of: Set(stage.placements.filter { $0.visibility == .live }.map(\.id)), initial: true) { _, live in
                liveTileIDs = live
            }
            .onChange(of: stage.maxScrollOffset) { _, maxOffset in
                // A departure that shortens the grid past the offset: the scroller would clamp
                // without animating and the grid would jump. Settling to the new end inside the
                // same animation as the placements is what keeps it from ever showing an empty
                // area below the last row (R42).
                guard fullscreenID == nil, scrollOffset > maxOffset else { return }
                withAnimation(animation) {
                    scrollPosition.scrollTo(y: maxOffset)
                }
            }
            .onChange(of: scrollRequest) { _, request in
                guard let request, fullscreenID == nil else { return }
                withAnimation(animation) {
                    scrollPosition.scrollTo(y: min(max(0, request.offset), stage.maxScrollOffset))
                }
            }
            .onChange(of: fullscreenID != nil) { _, isFullscreen in
                guard isFullscreen else { return }
                offsetBeforeFullscreen = scrollOffset
            }
            .onChange(of: stage, initial: true) { _, stage in
                // Leaving fullscreen: the stage grows back under the top bar over several passes,
                // and a position set in any one of them can be clamped against the wrong content
                // (a one-shot restore landed a row off, once in three runs). So the offset is
                // asked for on every pass until the scroller reports it, and only then is the
                // anchor logic allowed back in.
                if fullscreenID == nil, let offset = offsetBeforeFullscreen {
                    let target = min(offset, stage.maxScrollOffset)
                    if abs(scrollOffset - target) <= 1 {
                        offsetBeforeFullscreen = nil
                    } else {
                        scrollPosition.scrollTo(y: target)
                    }
                    return
                }
                reanchor(in: stage, gridTop: gridTop(in: stage))
            }
        }
    }
    
    /// What the stage is not showing, in the two ways the call tells apart: composed but off screen
    /// (paused, the view stays mounted so its last picture is there when it scrolls in, R49) and
    /// not composed at all (released).
    private struct Visibility: Equatable {
        let paused: Set<MatrixRTCTileID>
        let released: Set<MatrixRTCTileID>
        
        init(_ stage: ElementCallStageLayout) {
            paused = Set(stage.placements.lazy.filter { $0.visibility == .paused }.map(\.id))
            released = stage.hiddenTileIDs
        }
    }
    
    private func tileView(for placement: ElementCallTilePlacement, in stage: ElementCallStageLayout) -> some View {
        // A pinned tile (the spotlight, a fullscreen tile) is placed relative to the offset. That
        // part of its position follows the finger and must never animate, while the rest of it —
        // where the arrangement puts it — springs like every other tile's. They are two modifiers
        // for that reason: rows entering and leaving the composed band open an animation on the
        // stack, and with one `position` the sticky part rode that animation, lagged the finger
        // and sprang back to the top. A grid shorter than three viewports never showed it.
        let pin = placement.isSpotlight || placement.appearance == .fullscreen ? stage.viewport.minY : 0
        return ElementCallTileView(tile: placement.tile,
                            callProvider: callProvider,
                            isSpotlight: placement.isSpotlight,
                            appearance: placement.appearance,
                            memberCount: memberCount,
                            heroStack: placement.isSpotlight ? stage.heroStack : nil,
                            isNameHidden: placement.isSpotlight && stage.viewport.width > stage.viewport.height,
                            // Never for a composed tile: a paused one keeps its video view, and
                            // with it the last frame, so scrolling it in shows a picture rather
                            // than an avatar (R49). The call is what stops its stream meanwhile.
                            isVideoSuspended: false,
                            onToggleFullscreen: { onToggleFullscreen(placement.id) },
                            onToggleChrome: onToggleChrome,
                            onAction: onAction)
            .background {
                if placement.id == stage.pictureInPictureTileID {
                    PictureInPictureSourceView(sourceView: pictureInPictureSourceView)
                }
            }
            .frame(width: placement.frame.width, height: placement.frame.height)
            // Screen readers traverse the spotlight first, then the grid in rank order (R69), and
            // step through the stack with an adjustable action rather than a swipe (R25).
            .accessibilitySortPriority(placement.isSpotlight ? 1 : 0)
            .accessibilityAdjustableAction { direction in
                guard placement.isSpotlight else { return }
                showHero(direction == .increment ? 1 : -1, in: stage)
            }
            .position(x: placement.frame.midX, y: placement.frame.midY - pin)
            .offset(y: pin)
            // Nil on the offset-driven part only: for a grid tile the value never changes, so
            // this is transparent and the stack's spring reaches it as before.
            .animation(nil, value: pin)
            .zIndex(placement.zIndex)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
    }
    
    /// The next or previous hero in the stack, clamped: the stack does not wrap (R23).
    private func showHero(_ step: Int, in stage: ElementCallStageLayout) {
        let heroes = ElementCallSpotlight.heroes(in: tiles)
        guard let heroStack = stage.heroStack else { return }
        let target = min(heroes.count - 1, max(0, heroStack.shown + step))
        guard target != heroStack.shown, heroes.indices.contains(target) else { return }
        onShowHero(heroes[target])
    }
    
    /// Where an arrow sits on the spotlight, in content coordinates: 36 pt in from the edge it
    /// points past, 44 pt square. Named so the gesture can exclude exactly what is drawn.
    static func arrowFrame(step: Int, spotlight: CGRect) -> CGRect {
        CGRect(x: (step < 0 ? spotlight.minX + 36 : spotlight.maxX - 36) - 22, y: spotlight.midY - 22, width: 44, height: 44)
    }
    
    /// One of the landscape spotlight's arrows (R22). Disabled at the end it points past, which is
    /// how the stack says it does not wrap (R23). A system glyph rather than one of the host's
    /// icons: the icon port has no chevrons, and a chevron is not something a host re-brands.
    private func heroArrow(step: Int, isEnabled: Bool, in stage: ElementCallStageLayout) -> some View {
        Button {
            showHero(step, in: stage)
        } label: {
            Image(systemName: step < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                // Interactive, and it has to be: see `ElementCallGlass`.
                .elementCallGlass(in: Circle(), fallback: Color.black.opacity(0.5), isInteractive: true)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(step < 0 ? "Previous shared screen" : "Next shared screen")
        .accessibilityIdentifier(step < 0 ? ElementCallAccessibilityIdentifiers.heroPrevious : ElementCallAccessibilityIdentifiers.heroNext)
    }
    
    /// Which hero is shown, as a row of dots (R19). A readout: the pill on the spotlight names the
    /// position for VoiceOver and the adjustable action moves it.
    private func heroDots(_ heroStack: ElementCallStageLayout.HeroStack) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<heroStack.count, id: \.self) { index in
                Capsule()
                    .fill(index == heroStack.shown ? style.theme.iconPrimary : style.theme.iconQuaternary)
                    .frame(width: index == heroStack.shown ? 16 : 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
    
    /// Where the grid's first row starts: under the spotlight, or at the top.
    private func gridTop(in stage: ElementCallStageLayout) -> CGFloat {
        stage.placements.filter { !$0.isSpotlight && $0.appearance != .fullscreen }.map(\.frame.minY).min() ?? 0
    }
    
    /// Keeps the first visible grid tile in view across a change of stage size (R66), then notes
    /// which tile that now is. The anchor is only *used* when the size it was taken at differs
    /// from the current one, so an ordinary scroll or rank change just refreshes it.
    private func reanchor(in stage: ElementCallStageLayout, gridTop: CGFloat) {
        guard fullscreenID == nil else { return }
        let area = stage.viewport.size
        if let anchor, anchor.area != area,
           let placement = stage.placements.first(where: { $0.id == anchor.tileID && !$0.isSpotlight }) {
            let target = min(stage.maxScrollOffset, max(0, placement.frame.minY - gridTop))
            if abs(target - scrollOffset) > 1 {
                scrollPosition.scrollTo(y: target)
            }
        }
        let firstVisible = stage.placements
            .filter { !$0.isSpotlight && $0.frame.maxY > stage.viewport.minY + gridTop }
            .min { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
        if let firstVisible {
            anchor = (firstVisible.id, area)
        }
    }
}

// MARK: - Previews

struct ElementCallStage_Previews: PreviewProvider, TestablePreview {
    typealias Fixtures = ElementCallPreviewFixtures
    
    /// Derived rather than passed, so a preview cannot show a spotlight the app would not choose.
    /// This is the view state's own rule, and it reads the array as the ranking it now is.
    static func stage(tiles: [ElementCallTile],
                      fullscreen: MatrixRTCTileID? = nil) -> some View {
        ElementCallStage(tiles: tiles,
                         spotlightID: Fixtures.connected(tiles: tiles).spotlightID,
                         fullscreenID: fullscreen,
                         memberCount: tiles.count,
                         pictureInPictureSourceView: UIView(),
                         callProvider: Fixtures.noCall,
                         controlsClearance: ElementCallView.controlsClearance) { _ in }
            .background(ElementCallStyle.stock.theme.bgCanvasDefault)
            .environment(\.colorScheme, .dark)
    }
    
    static var previews: some View {
        stage(tiles: Fixtures.group)
            .previewDisplayName("Grid without a spotlight")
        stage(tiles: Fixtures.listenModeGroup)
            .previewDisplayName("Listen mode")
        stage(tiles: [Fixtures.alice])
            .previewDisplayName("Alone")
        stage(tiles: [Fixtures.alice, Fixtures.bob])
            .previewDisplayName("Two people")
        stage(tiles: [Fixtures.alice, Fixtures.bob, Fixtures.carol])
            .previewDisplayName("Three people")
        stage(tiles: Fixtures.group, fullscreen: Fixtures.bob.id)
            .previewDisplayName("Full screen")
        // A member on two tiles: the one case in which every member-keyed assumption that survived
        // the migration would be wrong, and the only preview that shows a share in a grid cell.
        stage(tiles: Fixtures.sharingGroup)
            .previewDisplayName("A member on two tiles")
        stage(tiles: Fixtures.twoSharesGroup)
            .previewDisplayName("Two heroes")
    }
}
