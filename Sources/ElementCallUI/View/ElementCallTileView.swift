//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCall
import ElementCallKit
import SwiftUI

/// How much of its own chrome a tile draws, which depends on where the layout has put it. One
/// parameter rather than booleans because the three are fixed combinations: nothing wants a name
/// pill without a speaker ring.
enum ElementCallTileAppearance {
    /// In the spotlight or the strip: rounded, named, ringed when talking.
    case card
    /// Filling the screen in a one-to-one call: square, unnamed, a mute badge if muted.
    case fullBleed
    /// Our own thumbnail over the other person in a one-to-one call: rounded and otherwise bare.
    case thumbnail
    /// Alone on the screen after a double tap: square, bare, the picture fitted rather than cropped
    /// and zoomable. Its chrome is ``ElementCallFullscreenChrome``, drawn by the screen, because
    /// keeping the name pill clear of the floating controls needs to know where those are.
    case fullscreen
}

/// One participant: video (or the avatar when the camera is off), name and mic badge, the flip
/// button on the self tile, and outlines for the active speaker and a raised hand.
struct ElementCallTileView: View {
    @Environment(\.elementCallStyle) private var style
    let tile: ElementCallTile
    let callProvider: () -> MatrixRTCCall?
    var isSpotlight = false
    var appearance: ElementCallTileAppearance = .card
    var memberCount = 0
    /// Off screen on another strip page: the avatar stands in so no decoder runs for it.
    var isVideoSuspended = false
    /// Double tap: in and out of full screen. Defaulted so the previews need not name it, and ahead
    /// of `onAction` rather than after it because that one is the trailing closure at every call
    /// site: a closure declared after it silently becomes the one a trailing closure binds to.
    var onToggleFullscreen: () -> Void = { }
    /// Single tap, which only means anything while full screen, where it raises and lowers the chrome.
    var onToggleChrome: () -> Void = { }
    let onAction: (ElementCallScreenViewAction) -> Void
    
    /// Committed by the end of a gesture; the in-flight part is separate so a cancelled pinch
    /// unwinds itself rather than leaving the picture stranded halfway.
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero
    /// The tile in points, for turning a finger's travel into the fraction of the surface the
    /// renderer's pan is expressed in.
    @State private var size: CGSize = .zero
    /// Upright width over height of the picture, once one has been drawn. Without it a pan can only
    /// be clamped as though the picture filled the tile, which over-runs on the letterboxed axis.
    @State private var contentAspect: CGFloat?
    
    private var isFullscreen: Bool {
        appearance == .fullscreen
    }
    
    private var cornerRadius: CGFloat {
        appearance == .fullBleed || appearance == .fullscreen ? 0 : 16
    }
    
    private var isLarge: Bool {
        isSpotlight || appearance == .fullBleed || appearance == .fullscreen
    }
    
    var body: some View {
        ZStack {
            // The gestures belong to the picture, and the chrome is layered over it rather than
            // inside it, so that a tap landing on the flip button is a tap on the flip button and
            // nothing else. With the whole stack behind one gesture, double-tapping that button
            // flipped the camera twice *and* went full screen.
            picture
            
            switch appearance {
            case .card:
                cardChrome
            case .fullBleed:
                fullBleedChrome
            case .thumbnail:
                thumbnailChrome
            case .fullscreen:
                // Drawn by the screen instead, where the controls' clearance is known.
                EmptyView()
            }
            
            if let stats = tile.stats {
                VStack(spacing: 0) {
                    Spacer()
                    Text(stats)
                        .font(.system(size: 9, design: .monospaced))
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.bottom, 36)
                // A readout, never a target: without this it would be a dead patch across the
                // bottom of every tile where a double tap does nothing.
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(outlineColor, lineWidth: appearance == .thumbnail ? 1 : 3)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ElementCallAccessibilityIdentifiers.tile(memberID: tile.memberID))
        // A double tap is how VoiceOver activates anything at all, so the gesture is invisible to
        // it: without this the feature does not exist for anyone using it.
        .accessibilityAction(named: Text("Full screen")) { onToggleFullscreen() }
    }
    
    private var picture: some View {
        ZStack {
            style.theme.bgSubtleSecondary
            
            if tile.hasVideo || tile.isScreenSharing, !isVideoSuspended {
                // A share is what a big tile is for, and full screen is the biggest there is: this
                // read `isSpotlight` alone, so double-tapping someone who was sharing swapped their
                // screen for their camera, which is the one picture nobody was asking for.
                let kind: MatrixRTCStreamKind = tile.isScreenSharing && (isSpotlight || isFullscreen) ? .screenShare : .camera
                // The crop opens as the tile grows rather than at the moment it is told to: see
                // ``AnimatableFit``.
                AnimatableFit(fit: isFullscreen ? 1 : 0) { fit in
                    ElementCallVideoView(memberID: tile.memberID,
                                         kind: kind,
                                         isLocal: tile.isLocal,
                                         callProvider: callProvider,
                                         presentation: presentation(fit: fit),
                                         onContentSizeChange: { contentAspect = $0.height > 0 ? $0.width / $0.height : nil },
                                         // `hasVideo` is a claim about signalling, not about pixels.
                                         // When the two disagree the tile would be a black rectangle,
                                         // so the avatar holds the space until a frame actually lands.
                                         placeholder: { avatar })
                        // A tile slot (the spotlight in particular) keeps its view identity when its
                        // member changes; without an explicit identity the renderer would stay
                        // attached to the previous member's stream.
                        .id("\(tile.memberID)/\(kind)")
                }
            } else {
                avatar
            }
        }
        // The clip shape clips hit testing with it, so without this the corners do not answer.
        .contentShape(Rectangle())
        // Attached first and so innermost, which is what makes it win: with the single tap first,
        // that one resolves every double tap as two singles and full screen is unreachable. The
        // precedence is the point, so it is stated here rather than left to modifier order to imply.
        .gesture(TapGesture(count: 2).onEnded { onToggleFullscreen() })
        // Masked off rather than branched away: an `if` around a modifier changes the view's
        // identity, which would tear down and rebuild the video view, i.e. detach and reattach the
        // stream, every time you entered or left full screen.
        .gesture(TapGesture(count: 1).onEnded { onToggleChrome() },
                 including: isFullscreen ? .all : .subviews)
        .gesture(zoomAndPan, including: isFullscreen ? .all : .subviews)
        .onChange(of: appearance) { _, appearance in
            guard appearance != .fullscreen else { return }
            zoom = 1
            pan = .zero
        }
    }
    
    // MARK: - Zoom and pan
    
    /// How far in a pinch may go, and how far past its ends a finger may drag before it springs back.
    private static let maximumZoom: CGFloat = 4
    private static let rubberBand: CGFloat = 1.2
    
    /// What the renderer is asked for, at a point on the way between filling and fitting. Only full
    /// screen zooms and pans: a cell is too small to be worth moving a picture around inside.
    private func presentation(fit: CGFloat) -> VideoPresentation {
        guard isFullscreen else { return VideoPresentation(fit: fit) }
        return VideoPresentation(fit: fit, zoom: liveZoom, pan: livePan)
    }
    
    private var liveZoom: CGFloat {
        min(max(zoom * pinch, 1 / Self.rubberBand), Self.maximumZoom * Self.rubberBand)
    }
    
    private var livePan: CGSize {
        clampedPan(CGSize(width: pan.width + drag.width / max(1, size.width),
                          height: pan.height + drag.height / max(1, size.height)),
                   zoom: liveZoom)
    }
    
    /// The pan the picture can actually take at this zoom, as the fraction of the tile the renderer
    /// expects. Clamped here as well as in the renderer so the committed value never runs past the
    /// edge: it would take the same distance of dead travel to drag back into view.
    private func clampedPan(_ pan: CGSize, zoom: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        // Without an aspect yet, assume the picture covers the tile: the honest guess, and it errs
        // towards allowing the pan the renderer will clamp rather than forbidding one it would not.
        let aspect = contentAspect ?? size.width / size.height
        let fitted = aspect > size.width / size.height
            ? CGSize(width: size.width, height: size.width / aspect)
            : CGSize(width: size.height * aspect, height: size.height)
        let overflowX = max(0, fitted.width * zoom - size.width) / 2 / size.width
        let overflowY = max(0, fitted.height * zoom - size.height) / 2 / size.height
        return CGSize(width: min(max(pan.width, -overflowX), overflowX),
                      height: min(max(pan.height, -overflowY), overflowY))
    }
    
    /// Pinch and drag together, so lifting one finger mid-zoom carries on panning from where the
    /// picture is rather than restarting from nothing. The drag needs a minimum distance or it
    /// claims the touch down and no tap ever completes.
    private var zoomAndPan: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in
                withAnimation(.spring(duration: 0.3)) {
                    zoom = min(max(zoom * value.magnification, 1), Self.maximumZoom)
                    pan = clampedPan(pan, zoom: zoom)
                }
            }
            .simultaneously(with: DragGesture(minimumDistance: 10)
                .updating($drag) { value, state, _ in state = value.translation }
                .onEnded { value in
                    pan = clampedPan(CGSize(width: pan.width + value.translation.width / max(1, size.width),
                                            height: pan.height + value.translation.height / max(1, size.height)),
                                     zoom: zoom)
                })
    }
    
    private var avatar: some View {
        style.avatars.avatar(userID: tile.userID,
                             displayName: tile.displayName,
                             avatarURL: tile.avatarURL,
                             size: appearance == .thumbnail ? .thumbnail : .full)
    }
    
    private var cardChrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                if isSpotlight, memberCount > 0 {
                    badge {
                        style.icons.icon(.userProfile, size: .xSmall, relativeTo: .bodySM)
                        Text("\(memberCount)")
                    }
                }
                if tile.hasHandRaised {
                    badge { style.icons.icon(.raisedHand, size: .xSmall, relativeTo: .bodySM) }
                }
                Spacer()
            }
            Spacer()
            HStack(alignment: .bottom, spacing: 4) {
                badge {
                    style.icons.icon(tile.isMicrophoneMuted ? .micOff : .micOn, size: .xSmall, relativeTo: .bodySM)
                    Text(tile.isScreenSharing && isSpotlight ? "(Screen share)" : tile.displayName)
                        .lineLimit(1)
                }
                Spacer()
                if tile.isLocal, tile.hasVideo {
                    switchCameraButton
                }
            }
        }
        .padding(8)
    }
    
    /// The name is in the top bar and the only other person is us, so all that is left to say
    /// about them is whether they can be heard (and whether their hand is up). Our own tile has the
    /// screen while the other side is still ringing: our mute state is on the control, so only the
    /// flip button.
    private var fullBleedChrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                if tile.hasHandRaised {
                    badge { style.icons.icon(.raisedHand, size: .xSmall, relativeTo: .bodySM) }
                }
                Spacer()
                if tile.isMicrophoneMuted, !tile.isLocal {
                    style.icons.icon(.micOff, size: .xSmall, relativeTo: .bodySM)
                        .foregroundStyle(style.theme.iconCriticalPrimary)
                        .frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.5), in: Circle())
                        .accessibilityLabel("Microphone muted")
                }
            }
            Spacer()
            if tile.isLocal, tile.hasVideo {
                HStack(spacing: 0) {
                    Spacer()
                    switchCameraButton
                }
            }
        }
        .padding(12)
    }
    
    /// Our own mute state is on the button we set it with; the flip button acts on the picture it
    /// sits on and saves the bar a sixth control.
    private var thumbnailChrome: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 0) {
                Spacer()
                if tile.hasVideo {
                    switchCameraButton
                }
            }
        }
        .padding(8)
    }
    
    private var switchCameraButton: some View {
        Button { onAction(.switchCamera) } label: {
            style.icons.icon(.switchCamera, size: .small, relativeTo: .bodySM)
                .padding(6)
                .background(Color.black.opacity(0.5), in: Circle())
        }
        .accessibilityLabel("Switch camera")
    }
    
    /// The thumbnail gets a hairline so it has an edge when both cameras are off and it would
    /// otherwise be an avatar floating over the other person's background. With two people there
    /// is nobody to tell apart, so no speaker ring in a one-to-one call.
    private var outlineColor: Color {
        switch appearance {
        case .card:
            if tile.hasHandRaised {
                return style.theme.iconAccentPrimary
            }
            return tile.isSpeaking ? style.theme.borderSuccessSubtle : .clear
        case .fullBleed, .fullscreen:
            return .clear
        case .thumbnail:
            return style.theme.borderInteractiveSecondary
        }
    }
    
    private func badge(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 4) { content() }
            .font(style.theme.bodySMSemibold)
            .foregroundStyle(style.theme.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.5), in: Capsule())
    }
}

/// Hands its content the value an animation is currently passing through.
///
/// SwiftUI interpolates what it can see is interpolating, and a value handed across into a
/// `UIViewRepresentable` is not that: it arrives at its destination in one step. So the crop used to
/// spring from filled to fitted in a single frame at the *start* of a move the tile then took half a
/// second to finish, which read as a jolt exactly where the eye was already following something.
/// Conforming a view to `Animatable` is how you ask for the values in between; its `body` is then
/// re-evaluated per frame, which is what carries them down to the renderer.
private struct AnimatableFit<Content: View>: View, Animatable {
    var fit: CGFloat
    let content: (CGFloat) -> Content
    
    var animatableData: CGFloat {
        get { fit }
        set { fit = newValue }
    }
    
    var body: some View {
        content(fit)
    }
}

/// Draws a member's stream while on screen; attaching opens the decoder, detaching closes it
/// (after a linger). The local tile draws the camera directly.
struct ElementCallVideoView<Placeholder: View>: View {
    let memberID: String
    let kind: MatrixRTCStreamKind
    let isLocal: Bool
    let callProvider: () -> MatrixRTCCall?
    var presentation: VideoPresentation = .fill
    var onContentSizeChange: (CGSize) -> Void = { _ in }
    /// Shown until the stream delivers its first frame. See ``FrameGate``.
    @ViewBuilder let placeholder: Placeholder
    
    @State private var slot = VideoFrameSlot()
    @State private var gate = FrameGate()
    /// Only ever set by the example harness. See ``ElementCallPreviewVideo``.
    @Environment(\.elementCallPreviewVideo) private var previewVideo
    
    var body: some View {
        ZStack {
            if !gate.hasFrame {
                placeholder
            }
            VideoTileView(slot: slot,
                          presentation: presentation,
                          onPixelSizeChange: { size in
                              guard !isLocal, let call = callProvider() else { return }
                              call.reportDrawnSize(size, slot: slot, memberID: memberID, kind: kind)
                          },
                          onContentSizeChange: onContentSizeChange)
                // Kept in the tree rather than branched away, so it is attached and drawing before it
                // is shown; swapping it in on the first frame would mean attaching after it.
                .opacity(gate.hasFrame ? 1 : 0)
        }
        .onAppear {
            // Wired before the call is asked for, not after: the harness feeds the same slot, and
            // with this below the guard its first frame would arrive with nothing listening and the
            // avatar would stay up over a picture that was already drawing.
            //
            // A slot reused by this tile may already hold a frame from before it went off screen.
            gate.hasFrame = slot.hasReceivedFrame
            slot.setOnFirstFrame { [gate] in
                Task { @MainActor in gate.hasFrame = true }
            }
            guard let call = callProvider() else {
                previewVideo?.attach(slot, memberID, kind)
                return
            }
            if isLocal {
                call.localVideo.attach(slot)
            } else {
                call.attachVideo(slot, memberID: memberID, kind: kind)
            }
        }
        .onDisappear {
            slot.setOnFirstFrame(nil)
            guard let call = callProvider() else {
                previewVideo?.detach(slot)
                return
            }
            if isLocal {
                call.localVideo.detach(slot)
            } else {
                call.detachVideo(slot, memberID: memberID, kind: kind)
            }
        }
    }
}

/// Carries "a frame has arrived" from the offering thread to the view.
///
/// A reference type because the slot's callback is `@Sendable` and fires off the main actor: it
/// can capture this and hop, where it could not capture the view's own state.
@Observable
private final class FrameGate {
    var hasFrame = false
}

// MARK: - Previews

struct ElementCallTileView_Previews: PreviewProvider, TestablePreview {
    typealias Fixtures = ElementCallPreviewFixtures
    
    static func tileView(_ tile: ElementCallTile,
                         appearance: ElementCallTileAppearance = .card,
                         isSpotlight: Bool = false) -> some View {
        ElementCallTileView(tile: tile,
                            callProvider: Fixtures.noCall,
                            isSpotlight: isSpotlight,
                            appearance: appearance,
                            memberCount: 4) { _ in }
            .frame(width: 180, height: 240)
            .environment(\.colorScheme, .dark)
    }
    
    static var previews: some View {
        tileView(Fixtures.carol)
            .previewDisplayName("Speaking")
        tileView(Fixtures.bob)
            .previewDisplayName("Muted")
        tileView(Fixtures.tile("Dan", hasMicrophone: false))
            .previewDisplayName("No microphone stream")
        tileView(Fixtures.tile("Erin", hasHandRaised: true))
            .previewDisplayName("Hand raised")
        tileView(Fixtures.tile("Frank", isScreenSharing: true), isSpotlight: true)
            .previewDisplayName("Screen sharing spotlight")
        tileView(Fixtures.alice, appearance: .thumbnail)
            .previewDisplayName("Own thumbnail")
        tileView(Fixtures.bob, appearance: .fullBleed)
            .previewDisplayName("Full bleed")
        tileView(Fixtures.tile("Grace", stats: "640x360 @ 30 fps\nasked 640x360\ne2ee: ok\npkts 1200 lost 3"))
            .previewDisplayName("With stats")
        // Bare on purpose: its chrome is ``ElementCallFullscreenChrome``, drawn by the screen.
        tileView(Fixtures.carol, appearance: .fullscreen)
            .previewDisplayName("Full screen")
    }
}
