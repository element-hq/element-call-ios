//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallHost
import ElementCallKit
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
                          label: context.viewState.isMicrophoneMuted ? "Unmute" : "Mute") {
                context.send(viewAction: .toggleMicrophone)
            }
            controlButton(icon: context.viewState.isCameraEnabled ? .videoCall : .videoCallOff,
                          isActive: context.viewState.isCameraEnabled,
                          label: context.viewState.isCameraEnabled ? "Turn camera off" : "Turn camera on") {
                context.send(viewAction: .toggleCamera)
            }
            audioRouteButton
            if context.viewState.isScreenSharingEnabled {
                controlButton(icon: .shareScreen,
                              isActive: !context.viewState.isScreenSharing,
                              label: context.viewState.isScreenSharing ? "Stop sharing screen" : "Share screen") {
                    context.send(viewAction: .toggleScreenShare)
                }
            }
            Button {
                context.send(viewAction: .hangUp)
            } label: {
                style.icons.icon(.endCall)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(style.theme.bgCriticalPrimary, in: Circle())
            }
            .accessibilityLabel("Hang up")
            .accessibilityIdentifier(ElementCallAccessibilityIdentifiers.hangUp)
        }
        .padding(8)
        // The bar is the glass (R46) and the buttons sit on it with their own fills: design's
        // decision after seeing the three shapes on a phone. Glass on glass flattens the inner
        // shapes and a union loses their states, so the buttons are not glass here; the top bar's
        // buttons and the spotlight's arrows, which have no bar, are.
        .elementCallGlass(in: Capsule(), fallback: style.theme.bgCanvasDefaultLevel.opacity(0.9))
    }
    
    /// With only the phone's own outputs, a speaker toggle. With a headset, a menu of every output.
    ///
    /// Our own menu rather than the system's `AVRoutePickerView`, which used to sit over the toggle
    /// at 2% opacity and never once received the tap. The menu is built from the view state, so
    /// the harness and the snapshots can show it with no headset in reach.
    @ViewBuilder
    private var audioRouteButton: some View {
        let state = context.viewState
        if state.hasExternalAudioOutput {
            Menu {
                Picker("Audio output", selection: Binding(get: { state.audioOutput },
                                                          set: { $0.map { context.send(viewAction: .selectAudioOutput($0)) } })) {
                    ForEach(state.audioOutputs) { output in
                        Label(label(for: output), systemImage: systemImage(for: output))
                            .tag(Optional(output))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                controlCircle(icon: audioOutputIcon, isActive: isOnEarpiece)
            }
            .accessibilityLabel("Audio output")
            .accessibilityValue(audioOutputValue)
            // Set here because `control(for:)` reaches only `controlButton`.
            .accessibilityIdentifier(ElementCallAccessibilityIdentifiers.audioOutput)
        } else {
            controlButton(icon: audioOutputIcon,
                          isActive: isOnEarpiece,
                          label: "Audio output") {
                context.send(viewAction: .toggleLoudspeaker)
            }
            .accessibilityValue(audioOutputValue)
        }
    }
    
    /// The earpiece is the resting state; anything else, speaker, headset or car, is highlighted,
    /// so a glance says the sound is not at the user's ear. Unknown reads as the earpiece.
    private var isOnEarpiece: Bool {
        context.viewState.audioOutput.map { $0.kind == .receiver } ?? true
    }
    
    /// Where the sound is going, so VoiceOver says what the icon shows.
    private var audioOutputValue: String {
        context.viewState.audioOutput.map(label(for:)) ?? ""
    }
    
    /// What the call is coming out of, readable without opening anything: the struck-through volume
    /// is the earpiece, as on Android.
    private var audioOutputIcon: ElementCallIcon {
        switch context.viewState.audioOutput?.kind {
        case .speaker: .volumeOn
        case .receiver, nil: .volumeOff
        case .bluetooth: .bluetooth
        // The car too, until there is a glyph for it.
        case .wired, .usb, .car: .headphones
        }
    }
    
    private func label(for output: CallAudioOutput) -> String {
        switch output.kind {
        case .speaker: style.strings.speaker
        case .receiver: style.strings.phone
        case .wired: style.strings.headphones
        case .bluetooth, .usb, .car: output.name
        }
    }
    
    /// System symbols, not the host's icons: a menu row draws only an `Image`, and the port takes
    /// an `AnyView`. Bluetooth is plain headphones, not AirPods: the port says only that it is
    /// Bluetooth, and the same row is a bone-conduction headset or a car kit.
    private func systemImage(for output: CallAudioOutput) -> String {
        switch output.kind {
        case .speaker: "speaker.wave.2"
        case .receiver: "iphone"
        case .bluetooth, .wired, .usb: "headphones"
        case .car: "car"
        }
    }
    
    /// `isActive` is the resting state, a dark circle; the inverse is the highlighted white circle
    /// the design uses for mic off, camera off, sharing and any audio output but the earpiece.
    private func controlButton(icon: ElementCallIcon,
                               isActive: Bool,
                               label: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            controlCircle(icon: icon, isActive: isActive)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(ElementCallAccessibilityIdentifiers.control(for: icon))
    }
    
    private func controlCircle(icon: ElementCallIcon, isActive: Bool) -> some View {
        style.icons.icon(icon)
            .foregroundStyle(isActive ? style.theme.iconPrimary : style.theme.iconOnSolidPrimary)
            .frame(width: 56, height: 56)
            .background(isActive ? style.theme.bgSubtleSecondary : style.theme.bgActionPrimaryRest, in: Circle())
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
                .opacity(configuration.isPressed ? 0.6 : 1)
                // The same material as the bar, so the top bar and the fullscreen exit button do
                // not mix surfaces with it.
                .elementCallGlass(in: Circle(), fallback: style.theme.bgSubtleSecondary, isInteractive: true)
        }
    }
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
        controls(ElementCallPreviewFixtures.connected(tiles: ElementCallPreviewFixtures.group,
                                                      audioOutputs: ElementCallPreviewFixtures.headsetAudioOutputs))
            .previewDisplayName("Headset")
    }
}
