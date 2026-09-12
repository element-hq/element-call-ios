//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCall
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
                        topBar
                            .padding(.horizontal, 16)
                            // The rail runs up the trailing edge and is centred, so it reaches into
                            // the top bar's row: without this the overflow button sits on top of it.
                            .padding(.trailing, isLandscape ? Self.controlsClearance : 0)
                        if context.viewState.isScreenSharing {
                            screenShareBanner
                                .padding(.trailing, isLandscape ? Self.controlsClearance : 0)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        content
                    }
                    .animation(.easeInOut(duration: 0.25), value: context.viewState.isScreenSharing)
                    
                    controls(isLandscape: isLandscape)
                } else {
                    Color.clear
                }
            }
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
            Button(style.strings.ok) { context.alertInfo = nil }
        } message: { alert in
            Text(alert.message)
        }
        .statusBarHidden(false)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
    
    // MARK: - Top bar
    
    private var topBar: some View {
        HStack(spacing: 8) {
            Button { context.send(viewAction: .minimize) } label: {
                style.icons.icon(.collapse)
            }
            .buttonStyle(ElementCallRoundButtonStyle())
            .accessibilityLabel(style.strings.back)
            
            Spacer()
            
            VStack(spacing: 2) {
                Text(context.viewState.roomName)
                    .font(style.theme.bodyLGSemibold)
                    .foregroundStyle(style.theme.textPrimary)
                    .lineLimit(1)
                    .accessibilityIdentifier(ElementCallAccessibilityIdentifiers.roomName)
                statusLine
                    .accessibilityIdentifier(ElementCallAccessibilityIdentifiers.callState)
            }
            
            Spacer()
            
            Menu {
                // Deliberately not in ElementCallStrings: these two are developer diagnostics, not
                // product text, and a host turns them off entirely with `areTileStatsAvailable`.
                Toggle("Tile stats", isOn: Binding(get: { context.viewState.isTileStatsVisible }, set: { _ in context.send(viewAction: .toggleTileStats) }))
                Toggle("Audio test tone (440 Hz)", isOn: Binding(get: { context.viewState.isAudioTestToneEnabled }, set: { _ in context.send(viewAction: .toggleAudioTestTone) }))
                Button {
                    context.send(viewAction: .toggleScreenShare)
                } label: {
                    Label {
                        Text(context.viewState.isScreenSharing ? style.strings.stopSharingScreen : style.strings.shareScreen)
                    } icon: {
                        style.icons.icon(.shareScreen, size: .xSmall, relativeTo: .bodySM)
                    }
                }
            } label: {
                style.icons.icon(.overflow)
            }
            .buttonStyle(ElementCallRoundButtonStyle())
        }
    }
    
    /// Sharing has no picture of its own on this side, so the screen says so and offers the way out.
    private var screenShareBanner: some View {
        HStack(spacing: 8) {
            style.icons.icon(.shareScreen, size: .xSmall, relativeTo: .bodySMSemibold)
            Text(style.strings.sharingYourScreen)
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
            Text(style.strings.joining).font(style.theme.bodySM).foregroundStyle(style.theme.textSecondary)
        case .connectingMedia:
            Text(style.strings.connecting).font(style.theme.bodySM).foregroundStyle(style.theme.textSecondary)
        case .connected:
            if let connectedAt = context.viewState.connectedAt {
                Text(connectedAt, style: .timer)
                    .font(style.theme.bodySM)
                    .foregroundStyle(context.viewState.isMediaDegraded ? style.theme.textCriticalPrimary : style.theme.textSecondary)
                    .monospacedDigit()
            }
        case .ended:
            Text(style.strings.callEnded).font(style.theme.bodySM).foregroundStyle(style.theme.textSecondary)
        case .failed(let message):
            Text(message).font(style.theme.bodySM).foregroundStyle(style.theme.textCriticalPrimary).lineLimit(2)
        }
    }
    
    // MARK: - Content
    
    /// The floating controls sit this far in from the edge they are on. Their thickness is the same
    /// either way round, so the stage reserves one clearance and does not care which edge it is.
    private static let controlsEdgePadding: CGFloat = 12
    static let controlsClearance: CGFloat = ElementCallControlsView.thickness + controlsEdgePadding
    
    /// Pinned to the bottom in portrait and to the trailing edge in landscape, over the stage
    /// either way: the stage has already kept its cards out from under them.
    @ViewBuilder
    private func controls(isLandscape: Bool) -> some View {
        if isLandscape {
            HStack(spacing: 0) {
                Spacer()
                ElementCallControlsView(context: context, axis: .vertical)
                    .padding(.trailing, Self.controlsEdgePadding)
            }
        } else {
            VStack(spacing: 0) {
                Spacer()
                ElementCallControlsView(context: context, axis: .horizontal)
                    .padding(.bottom, Self.controlsEdgePadding)
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        let state = context.viewState
        if state.tiles.isEmpty {
            Spacer()
            ProgressView()
                .tint(style.theme.iconPrimary)
            Spacer()
        } else {
            ElementCallStage(tiles: state.tiles,
                             spotlightMemberID: state.spotlightMemberID,
                             layout: state.layout,
                             memberCount: state.memberCount,
                             pictureInPictureSourceView: pictureInPictureSourceView,
                             callProvider: callProvider,
                             controlsClearance: Self.controlsClearance) { action in
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
    
    static var previews: some View {
        ElementCallView(context: joiningViewModel.context, pictureInPictureSourceView: UIView()) { nil }
            .previewDisplayName("Joining")
        ElementCallView(context: failedViewModel.context, pictureInPictureSourceView: UIView()) { nil }
            .previewDisplayName("Failed")
        screen(ElementCallPreviewFixtures.connected(tiles: ElementCallPreviewFixtures.group,
                                                    spotlight: ElementCallPreviewFixtures.carol.memberID))
            .previewDisplayName("Connected group")
        screen(ElementCallPreviewFixtures.connected(tiles: [ElementCallPreviewFixtures.alice,
                                                            ElementCallPreviewFixtures.bob],
                                                    isDirect: true))
            .previewDisplayName("Connected one to one")
        screen(ElementCallPreviewFixtures.connected(tiles: ElementCallPreviewFixtures.group,
                                                    spotlight: ElementCallPreviewFixtures.carol.memberID,
                                                    isMicrophoneMuted: true,
                                                    isScreenSharing: true))
            .previewDisplayName("Muted and sharing")
    }
}
