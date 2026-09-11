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
    let onAction: (ElementCallScreenViewAction) -> Void
    
    private var cornerRadius: CGFloat {
        appearance == .fullBleed ? 0 : 16
    }
    
    private var isLarge: Bool {
        isSpotlight || appearance == .fullBleed
    }
    
    var body: some View {
        ZStack {
            style.theme.bgSubtleSecondary
            
            if tile.hasVideo || tile.isScreenSharing, !isVideoSuspended {
                let kind: MatrixRTCStreamKind = tile.isScreenSharing && isSpotlight ? .screenShare : .camera
                ElementCallVideoView(memberID: tile.memberID,
                                     kind: kind,
                                     isLocal: tile.isLocal,
                                     callProvider: callProvider,
                                     // `hasVideo` is a claim about signalling, not about pixels.
                                     // When the two disagree the tile would be a black rectangle,
                                     // so the avatar holds the space until a frame actually lands.
                                     placeholder: { avatar })
                    // A tile slot (the spotlight in particular) keeps its view identity when its member
                    // changes; without an explicit identity the renderer would stay attached to the
                    // previous member's stream.
                    .id("\(tile.memberID)/\(kind)")
            } else {
                avatar
            }
            
            switch appearance {
            case .card:
                cardChrome
            case .fullBleed:
                fullBleedChrome
            case .thumbnail:
                thumbnailChrome
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
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(outlineColor, lineWidth: appearance == .thumbnail ? 1 : 3)
        }
        // Keyed by member so the rig can assert about one participant, wherever the layout has put
        // them. `.contain` keeps the mute badge and flip button addressable inside it.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ElementCallAccessibilityIdentifiers.tile(memberID: tile.memberID))
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
                    Text(tile.isScreenSharing && isSpotlight ? style.strings.screenShareTileName : tile.displayName)
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
                        .accessibilityLabel(style.strings.microphoneMuted)
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
        .accessibilityLabel(style.strings.switchCamera)
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
        case .fullBleed:
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

/// Draws a member's stream while on screen; attaching opens the decoder, detaching closes it
/// (after a linger). The local tile draws the camera directly.
struct ElementCallVideoView<Placeholder: View>: View {
    let memberID: String
    let kind: MatrixRTCStreamKind
    let isLocal: Bool
    let callProvider: () -> MatrixRTCCall?
    /// Shown until the stream delivers its first frame. See ``FrameGate``.
    @ViewBuilder let placeholder: Placeholder
    
    @State private var slot = VideoFrameSlot()
    @State private var gate = FrameGate()
    
    var body: some View {
        ZStack {
            if !gate.hasFrame {
                placeholder
            }
            VideoTileView(slot: slot) { size in
                guard !isLocal, let call = callProvider() else { return }
                call.reportDrawnSize(size, slot: slot, memberID: memberID, kind: kind)
            }
            // Kept in the tree rather than branched away, so it is attached and drawing before it
            // is shown; swapping it in on the first frame would mean attaching after it.
            .opacity(gate.hasFrame ? 1 : 0)
        }
        .onAppear {
            guard let call = callProvider() else { return }
            // A slot reused by this tile may already hold a frame from before it went off screen.
            gate.hasFrame = slot.hasReceivedFrame
            slot.setOnFirstFrame { [gate] in
                Task { @MainActor in gate.hasFrame = true }
            }
            if isLocal {
                call.localVideo.attach(slot)
            } else {
                call.attachVideo(slot, memberID: memberID, kind: kind)
            }
        }
        .onDisappear {
            slot.setOnFirstFrame(nil)
            guard let call = callProvider() else { return }
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
    }
}
