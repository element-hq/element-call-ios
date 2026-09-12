//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVKit
import ElementCall
import SwiftUI

/// The floating control bar from the design: mic, camera, audio route, screen share, hang up.
/// Along the bottom in portrait, up the trailing edge in landscape, where height is the scarce
/// side and a horizontal bar would cost the spotlight a fifth of it.
///
/// `AnyLayout` rather than a branch between an `HStack` and a `VStack`: the layout changes but the
/// buttons keep their identity, so a rotation slides each one to its new place instead of tearing
/// the bar down and fading a new one in.
struct ElementCallControlsView: View {
    @Bindable var context: ElementCallScreenContext
    @Environment(\.elementCallStyle) private var style
    var axis: Axis = .horizontal
    
    /// The bar's thickness across the axis it runs along: a 56 pt button in 8 pt of capsule. The
    /// same number either way round, which is what lets the stage reserve one clearance for both.
    static let thickness: CGFloat = 56 + 2 * 8
    
    /// Tighter up the rail than along the bar: five 56 pt buttons at 12 pt apart come to 344 pt,
    /// which overflows the 375 pt short side of a phone and clipped the mic and the hang-up button
    /// off both ends. Landscape has width to spare and no height at all.
    private var layout: AnyLayout {
        axis == .horizontal ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 8))
    }
    
    var body: some View {
        layout {
            controlButton(icon: context.viewState.isMicrophoneMuted ? .micOff : .micOn,
                          isActive: !context.viewState.isMicrophoneMuted,
                          label: context.viewState.isMicrophoneMuted ? style.strings.unmute : style.strings.mute) {
                context.send(viewAction: .toggleMicrophone)
            }
            controlButton(icon: context.viewState.isCameraEnabled ? .videoCall : .videoCallOff,
                          isActive: context.viewState.isCameraEnabled,
                          label: context.viewState.isCameraEnabled ? style.strings.turnCameraOff : style.strings.turnCameraOn) {
                context.send(viewAction: .toggleCamera)
            }
            audioRouteButton
            controlButton(icon: .shareScreen,
                          isActive: !context.viewState.isScreenSharing,
                          label: context.viewState.isScreenSharing ? style.strings.stopSharingScreen : style.strings.shareScreen) {
                context.send(viewAction: .toggleScreenShare)
            }
            Button {
                context.send(viewAction: .hangUp)
            } label: {
                style.icons.icon(.endCall)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(style.theme.bgCriticalPrimary, in: Circle())
            }
            .accessibilityLabel(style.strings.hangUp)
            .accessibilityIdentifier(ElementCallAccessibilityIdentifiers.hangUp)
        }
        .padding(8)
        .background(style.theme.bgCanvasDefaultLevel.opacity(0.9), in: Capsule())
    }
    
    /// Speaker toggles the loudspeaker; a long press opens the system route picker for
    /// Bluetooth and other outputs.
    private var audioRouteButton: some View {
        ZStack {
            controlButton(icon: context.viewState.isLoudspeaker ? .volumeOn : .volumeOff,
                          isActive: !context.viewState.isLoudspeaker,
                          label: "Audio output") {
                context.send(viewAction: .toggleLoudspeaker)
            }
            ElementCallAudioRoutePicker()
                .frame(width: 56, height: 56)
                .opacity(0.02)
        }
    }
    
    /// `isActive` is the resting state, a dark circle; the inverse is the highlighted white circle
    /// the design uses for mic off, camera off, sharing and loudspeaker.
    private func controlButton(icon: ElementCallIcon,
                               isActive: Bool,
                               label: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            style.icons.icon(icon)
                .foregroundStyle(isActive ? style.theme.iconPrimary : style.theme.iconOnSolidPrimary)
                .frame(width: 56, height: 56)
                .background(isActive ? style.theme.bgSubtleSecondary : style.theme.bgActionPrimaryRest, in: Circle())
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(ElementCallAccessibilityIdentifiers.control(for: icon))
    }
}

/// The small circular buttons in the top bar. A `ButtonStyle` cannot read the environment in
/// `makeBody`, so the label goes into a nested view that can.
struct ElementCallRoundButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Background(configuration: configuration)
    }
    
    private struct Background: View {
        let configuration: Configuration
        @Environment(\.elementCallStyle) private var style
        
        var body: some View {
            configuration.label
                .foregroundStyle(style.theme.iconPrimary)
                .frame(width: 44, height: 44)
                .background(style.theme.bgSubtleSecondary.opacity(configuration.isPressed ? 0.6 : 1), in: Circle())
        }
    }
}

/// The system output picker, drawn nearly transparent over the speaker button so a tap reaches it.
struct ElementCallAudioRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        return view
    }
    
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) { }
}

// MARK: - Previews

struct ElementCallControlsView_Previews: PreviewProvider, TestablePreview {
    static func controls(_ state: ElementCallScreenViewState, axis: Axis = .horizontal) -> some View {
        ElementCallControlsView(context: .preview(state: state), axis: axis)
            .padding()
            .background(ElementCallStyle.stock.theme.bgCanvasDefault)
            .environment(\.colorScheme, .dark)
    }
    
    static var previews: some View {
        controls(ElementCallPreviewFixtures.connected(tiles: ElementCallPreviewFixtures.group))
            .previewDisplayName("Resting")
        controls(ElementCallPreviewFixtures.connected(tiles: ElementCallPreviewFixtures.group,
                                                      isMicrophoneMuted: true,
                                                      isScreenSharing: true))
            .previewDisplayName("Muted and sharing")
        controls(ElementCallPreviewFixtures.connected(tiles: ElementCallPreviewFixtures.group), axis: .vertical)
            .previewDisplayName("Vertical rail")
    }
}
