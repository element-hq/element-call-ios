//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallHost
import ElementCallKit
import SwiftUI

/// The full-screen call: top bar, the stage with the tiles and the floating control bar. The stage
/// arranges the tiles as spotlight and strip, or in a DM with just the two of us, the other person
/// full-bleed with our thumbnail over them. Layout follows the iOS call design; the paging strip is
/// Android's answer to big calls (tiles keep their size, pages grow).
struct ElementCallView: View {
    @Environment(\.elementCallStyle) private var style
    @Bindable var context: ElementCallScreenContext
    let pictureInPictureSourceView: UIView
    /// Read at render time: the call exists only once media is connected.
    let callProvider: () -> MatrixRTCCall?
    
    var body: some View {
        // Orientation is read as the shape of the space we were given, not from the device or the
        // size class: a half-screen iPad app in portrait wants the portrait arrangement whatever
        // the hardware is doing, and an iPad in landscape is landscape even though its vertical
        // size class says regular. The stage decides the same way, so the two cannot disagree.
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            ZStack {
                // Minimized (bar or Picture in Picture): nothing mounted, so the tiles' streams close
                // and only the window's own slot keeps decoding.
                if context.viewState.isMaximized {
                    style.theme.bgCanvasDefault.ignoresSafeArea()
                    
                    VStack(spacing: 12) {
                        if fullscreenTile == nil {
                            topBar
                                .padding(.horizontal, 16)
                            if context.viewState.isScreenSharing {
                                screenShareBanner
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        content
                            // A fitted picture is centred on what it is given, so full screen gives
                            // it the screen: centred on the notch-shaped remainder instead, the
                            // letterbox above and below would not match.
                            .ignoresSafeArea(.container, edges: fullscreenTile == nil ? [] : .all)
                    }
                    .animation(.easeInOut(duration: 0.25), value: context.viewState.isScreenSharing)
                    
                    if let fullscreenTile {
                        if context.isFullscreenChromeVisible {
                            ElementCallFullscreenChrome(tile: fullscreenTile,
                                                        context: context,
                                                        isLandscape: isLandscape,
                                                        onExit: { setFullscreen(nil) },
                                                        onAction: { context.send(viewAction: $0) })
                                .transition(.opacity)
                        }
                    } else {
                        ElementCallFloatingControls(context: context)
                    }
                } else {
                    Color.clear
                        .onAppear(perform: declareMinimizedDetailWindow)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: context.isFullscreenChromeVisible)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .environment(\.colorScheme, .dark)
        .alert(context.alertInfo?.title ?? "",
               isPresented: Binding(get: { context.alertInfo != nil },
                                    set: {
                                        if !$0 {
                                            context.alertInfo = nil
                                        }
                                    }),
               presenting: context.alertInfo) { _ in
            Button("OK") { context.alertInfo = nil }
        } message: { alert in
            Text(alert.message)
        }
        .statusBarHidden(fullscreenTile != nil && !context.isFullscreenChromeVisible)
        .onChange(of: context.viewState.isMaximized) { _, isMaximized in
            // Minimizing ends full screen rather than suspending it. The window continues whatever
            // the ordinary arrangement gives it, and coming back is the stage: one state fewer to
            // reason about, and no way to return to a screen whose chrome you had left hidden.
            guard !isMaximized else { return }
            setFullscreen(nil)
        }
        .onChange(of: context.viewState.tiles) { _, tiles in
            // The tile you were watching can go. The arrangement falls back on its own, but the
            // screen would go on believing it was full screen: top bar hidden, chrome hidden, and
            // nothing left on screen that brings either back. Two ways now rather than one — their
            // member leaves, or they stop sharing and the share tile goes with them.
            guard let tileID = context.fullscreenTileID,
                  !tiles.contains(where: { $0.id == tileID }) else { return }
            setFullscreen(nil)
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
    
    /// The stage is gone while minimized, so nothing declares the window. A small head range plus
    /// whatever the window continues (R52, partial: see the core-rs feedback on a call-wide "any
    /// remote video" flag); the stage declares its own again the moment it is back.
    private func declareMinimizedDetailWindow() {
        guard let call = callProvider() else { return }
        let spotlightID = context.viewState.spotlightID
        let also = [spotlightID, call.pictureInPictureCandidate(spotlight: spotlightID)].compactMap { $0 }
        call.setDetailWindow(.init(ranks: 0..<Self.minimizedDetailWindowLength, also: Set(also)))
    }
    
    /// The tile full screen right now, if it is still in the call.
    private var fullscreenTile: ElementCallTile? {
        guard let tileID = context.fullscreenTileID else { return nil }
        return context.viewState.tiles.first { $0.id == tileID }
    }
    
    /// Entering always starts with the chrome down, so the first thing a full-screen tile shows is
    /// the picture; leaving puts it back down for next time.
    private func setFullscreen(_ tileID: MatrixRTCTileID?) {
        withAnimation(.easeInOut(duration: 0.25)) {
            context.fullscreenTileID = tileID
            context.isFullscreenChromeVisible = false
        }
    }
    
    // MARK: - Top bar
    
    private var topBar: some View {
        HStack(spacing: 8) {
            Button { context.send(viewAction: .minimize) } label: {
                style.icons.icon(.collapse)
            }
            .buttonStyle(ElementCallRoundButtonStyle())
            .accessibilityLabel(style.strings.back)
            // The same omission as the one fixed for `.more` below, and for the same reason: the
            // top bar does not go through `ElementCallControlsView.controlButton`, which is the
            // only caller of `control(for:)`, so a constant that exists and is pinned by name in
            // the identifier tests still reached no view and nothing could tap this button.
            .accessibilityIdentifier(ElementCallAccessibilityIdentifiers.minimize)
            
            Spacer()
            
            VStack(spacing: 2) {
                Text(context.viewState.roomName)
                    .font(style.theme.bodyLGSemibold)
                    .foregroundStyle(style.theme.textPrimary)
                    .lineLimit(1)
                statusLine
            }
            
            Spacer()
            
            // The diagnostics menu, and only that. Screen sharing used to be duplicated here from
            // the control bar, which is where a user actually reaches for it; the audio test tone
            // that used to sit alongside the stats overlay is gone entirely.
            //
            // The version row is why the menu is never empty, which matters because everything else
            // in it is gated. Unlocalised, like the toggle: neither is a product string.
            Menu {
                // Absent rather than inert when developer mode is off. The toggle was always shown
                // and the controller silently refused the tap, which looked like a broken toggle.
                //
                // A nested Menu is a submenu, which keeps the diagnostics one level down and leaves
                // the top level to things a user might actually want. The Toggle inside renders as
                // a checked menu item, so the checkmark is the state: there is no need to say
                // "show/hide" in the label, and a plain Button would lose that.
                if context.viewState.isDeveloperModeEnabled {
                    Menu("Developer Options") {
                        Toggle("Tile stats", isOn: Binding(get: { context.viewState.isTileStatsVisible }, set: { _ in context.send(viewAction: .toggleTileStats) }))
                    }
                    Divider()
                }
                // A disabled button rather than a Section header or a bare Text: an empty Section
                // is dropped by SwiftUI, and a Menu does not render loose Text. Disabled gives a
                // dimmed, unselectable row, which is what this is.
                Button("version: \(ElementCallVersion.current)") { }
                    .disabled(true)
            } label: {
                style.icons.icon(.overflow)
            }
            .buttonStyle(ElementCallRoundButtonStyle())
            // Applied here rather than through `control(for:)`, which only the control bar calls.
            // The constant existed and was pinned by name in the identifier tests, but reached no
            // view, so nothing could find this button — including the UI test that reads the menu.
            .accessibilityIdentifier(ElementCallAccessibilityIdentifiers.more)
        }
    }
    
    /// Sharing has no picture of its own on this side, so the screen says so and offers the way out.
    private var screenShareBanner: some View {
        HStack(spacing: 8) {
            style.icons.icon(.shareScreen, size: .xSmall, relativeTo: .bodySMSemibold)
            Text("You\u{2019}re sharing your screen")
                .font(style.theme.bodySMSemibold)
                .lineLimit(1)
            Button(style.strings.stop) {
                context.send(viewAction: .toggleScreenShare)
            }
            .font(style.theme.bodySMSemibold)
            .foregroundStyle(style.theme.iconAccentPrimary)
            .buttonStyle(.plain)
        }
        .foregroundStyle(style.theme.textPrimary)
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(style.theme.bgAccentRest, in: Capsule())
        .accessibilityElement(children: .combine)
    }
    
    @ViewBuilder
    private var statusLine: some View {
        switch context.viewState.connection {
        case .idle, .joining:
            Text("Joining…").font(style.theme.bodySM).foregroundStyle(style.theme.textSecondary)
        case .connectingMedia:
            Text("Connecting…").font(style.theme.bodySM).foregroundStyle(style.theme.textSecondary)
        case .connected:
            if let connectedAt = context.viewState.connectedAt {
                Text(connectedAt, style: .timer)
                    .font(style.theme.bodySM)
                    .foregroundStyle(context.viewState.isMediaDegraded ? style.theme.textCriticalPrimary : style.theme.textSecondary)
                    .monospacedDigit()
            }
        case .ended:
            Text("Call ended").font(style.theme.bodySM).foregroundStyle(style.theme.textSecondary)
        case .failed(let message):
            Text(message).font(style.theme.bodySM).foregroundStyle(style.theme.textCriticalPrimary).lineLimit(2)
        }
    }
    
    // MARK: - Content
    
    /// How far the floating controls reach in from the edge they are on. The placement itself lives
    /// on ``ElementCallFloatingControls``, which the full-screen chrome shares.
    static let controlsClearance = ElementCallFloatingControls.clearance
    /// The ranks kept in detail while minimized: enough for the bar and the window's fallbacks.
    static let minimizedDetailWindowLength = 8
    
    @ViewBuilder
    private var content: some View {
        let state = context.viewState
        // The spinner means "no call yet". That used to be the same thing as "no tiles" and is not
        // any more: the model's ranked list is *empty* when you are the only person in the call, and
        // your own tile — which is never in it — is the whole stage. Keying the spinner on emptiness
        // answers exactly that case with a spinner there is no way out of. The own tile is spliced
        // in unconditionally so the list is not actually empty here, but the invariant should not be
        // the only thing standing between a user alone in a call and a permanent loading screen.
        if state.connection != .connected, state.tiles.isEmpty {
            Spacer()
            ProgressView()
                .tint(style.theme.iconPrimary)
            Spacer()
        } else {
            ElementCallStage(tiles: state.tiles,
                             spotlightID: state.spotlightID,
                             fullscreenID: fullscreenTile?.id,
                             scrollRequest: context.scrollRequest,
                             memberCount: state.memberCount,
                             pictureInPictureSourceView: pictureInPictureSourceView,
                             callProvider: callProvider,
                             controlsClearance: Self.controlsClearance,
                             onToggleFullscreen: { tileID in
                                 // The same tile again is the way back out, which is what makes one
                                 // gesture do both halves of it.
                                 setFullscreen(context.fullscreenTileID == tileID ? nil : tileID)
                             },
                             onToggleChrome: {
                                 withAnimation(.easeInOut(duration: 0.2)) {
                                     context.isFullscreenChromeVisible.toggle()
                                 }
                             },
                             // A way of looking, so it lives on the context beside the fullscreen
                             // tile; the view model resolves it by identity on the next refresh.
                             onShowHero: { context.shownHeroID = $0 }) { action in
                context.send(viewAction: action)
            }
        }
    }
}

// MARK: - Previews

struct ElementCallView_Previews: PreviewProvider, TestablePreview {
    static let joiningViewModel = ElementCallScreenPreviewFactory.makeViewModel(connection: .joining)
    static let failedViewModel = ElementCallScreenPreviewFactory.makeViewModel(connection: .failed("Homeserver offers no LiveKit transport"))
    
    static func screen(_ state: ElementCallScreenViewState) -> some View {
        ElementCallView(context: .preview(state: state),
                        pictureInPictureSourceView: UIView(),
                        callProvider: ElementCallPreviewFixtures.noCall)
    }
    
    /// Full screen is written onto the context rather than reached by tapping, which is the same
    /// seam the rest of these previews use: there is no call here to tap anything on.
    static func fullscreen(isChromeVisible: Bool) -> some View {
        let context = ElementCallScreenContext.preview(state: ElementCallPreviewFixtures.connected(tiles: ElementCallPreviewFixtures.group))
        context.fullscreenTileID = ElementCallPreviewFixtures.carol.id
        context.isFullscreenChromeVisible = isChromeVisible
        return ElementCallView(context: context,
                               pictureInPictureSourceView: UIView(),
                               callProvider: ElementCallPreviewFixtures.noCall)
    }
    
    static var previews: some View {
        ElementCallView(context: joiningViewModel.context, pictureInPictureSourceView: UIView()) { nil }
            .previewDisplayName("Joining")
        ElementCallView(context: failedViewModel.context, pictureInPictureSourceView: UIView()) { nil }
            .previewDisplayName("Failed")
        screen(ElementCallPreviewFixtures.connected(tiles: ElementCallPreviewFixtures.group))
            .previewDisplayName("Connected group")
        // Alone in the call: the model's ranked list is empty and our own tile is the whole stage.
        // This used to render as a spinner you could not get out of.
        screen(ElementCallPreviewFixtures.connected(tiles: [ElementCallPreviewFixtures.alice]))
            .previewDisplayName("Alone in the call")
        screen(ElementCallPreviewFixtures.connected(tiles: [ElementCallPreviewFixtures.alice,
                                                            ElementCallPreviewFixtures.bob],
                                                    isDirect: true))
            .previewDisplayName("Two people")
        screen(ElementCallPreviewFixtures.connected(tiles: ElementCallPreviewFixtures.listenModeGroup))
            .previewDisplayName("Listen mode")
        screen(ElementCallPreviewFixtures.connected(tiles: ElementCallPreviewFixtures.twoSharesGroup))
            .previewDisplayName("Two heroes")
        screen(ElementCallPreviewFixtures.connected(tiles: ElementCallPreviewFixtures.group,
                                                    isMicrophoneMuted: true,
                                                    isScreenSharing: true))
            .previewDisplayName("Muted and sharing")
        fullscreen(isChromeVisible: false)
            .previewDisplayName("Full screen")
        fullscreen(isChromeVisible: true)
            .previewDisplayName("Full screen with chrome")
    }
}
