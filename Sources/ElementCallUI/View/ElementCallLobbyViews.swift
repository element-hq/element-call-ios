//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallHost
import SwiftUI

/// The lobby's Start or Join, under the control bar (045 R21). Where it sits is design's to move
/// (open question Q8); it is placed by ``ElementCallFloatingControls`` alone.
///
/// Disabled only while loading (R59). With the microphone refused it looks as it always does and
/// its tap explains rather than joins (R27): a button that looks disabled leaves the user nowhere to
/// tap to find out what is wrong.
struct ElementCallLobbyJoinButton: View {
    @Environment(\.elementCallStyle) private var style
    let lobby: ElementCallLobbyViewState
    let onJoin: () -> Void
    /// Screen reader focus starts here once the lobby has loaded (R35, C20). Not before: while
    /// loading there is no label to announce, and focus taken then would read "Loading call" and
    /// change under the user.
    @AccessibilityFocusState private var isFocused: Bool
    
    static let height: CGFloat = 50
    
    var body: some View {
        Button(action: onJoin) {
            Text(title)
                .font(style.theme.bodyLGSemibold)
                .lineLimit(1)
                .foregroundStyle(lobby.isLoading ? style.theme.textDisabled : style.theme.iconOnSolidPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: Self.height)
                .background(lobby.isLoading ? style.theme.bgSubtleSecondary : style.theme.bgActionPrimaryRest, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(lobby.isLoading)
        .accessibilityIdentifier(ElementCallAccessibilityIdentifiers.lobbyJoin)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .accessibilityFocused($isFocused)
        .onChange(of: lobby.isLoading, initial: true) { _, isLoading in
            if !isLoading {
                isFocused = true
            }
        }
    }
    
    /// "Loading call" stands in for the label while loading: nothing is guessed (R59).
    private var title: String {
        switch lobby.joinLabel {
        case .start: L10nPending.lobbyStart
        case .join: L10nPending.lobbyJoin
        case .joinAnyway: L10nPending.lobbyJoinAnyway
        case nil: L10nPending.lobbyLoading
        }
    }
    
    /// The count as a sentence when the lobby shows one (R35, R41); "Unavailable" for a Join that
    /// cannot join (R51).
    private var accessibilityValue: String {
        if !lobby.canJoin {
            return L10n.a11yUnavailable
        }
        return lobby.shownMemberCount.map(L10nPending.lobbyMemberCount) ?? ""
    }
    
    /// Why a Join cannot join (R51, C26): loading, or R27's description. The button stays
    /// actionable with the microphone refused, its action being the explanation.
    private var accessibilityHint: String {
        if lobby.isLoading {
            return L10nPending.lobbyLoading
        }
        return lobby.isMicrophoneRefused ? L10nPending.lobbyMicrophoneDescription : ""
    }
}

/// R57's notice: the call emptied after the lobby had shown somebody in it. Over the preview's lower
/// part rather than on the Join line, so the bar and Join never move when it comes (Android's
/// appendix, item 8). Announced as it appears, without moving focus (R58).
struct ElementCallLobbyCallEndedNotice: View {
    @Environment(\.elementCallStyle) private var style
    
    var body: some View {
        Text(L10nPending.lobbyCallEnded)
            .font(style.theme.bodySMSemibold)
            .foregroundStyle(style.theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(style.theme.bgCanvasDefaultLevel.opacity(0.9), in: Capsule())
            .accessibilityIdentifier(ElementCallAccessibilityIdentifiers.lobbyCallEnded)
            .onAppear {
                AccessibilityNotification.Announcement(L10nPending.lobbyCallEnded).post()
            }
    }
}

// MARK: - Previews

/// The lobby's states on the whole screen, so the snapshots pin where each piece sits (Q5, Q8).
struct ElementCallLobby_Previews: PreviewProvider, TestablePreview {
    typealias Fixtures = ElementCallPreviewFixtures
    
    static func screen(_ state: ElementCallScreenViewState) -> some View {
        ElementCallView(context: .preview(state: state),
                        pictureInPictureSourceView: UIView(),
                        callProvider: Fixtures.noCall)
    }
    
    static var previews: some View {
        screen(Fixtures.lobby(isLoading: true))
            .previewDisplayName("Loading")
        screen(Fixtures.lobby(memberCount: 0))
            .previewDisplayName("Nobody in the call")
        screen(Fixtures.lobby(memberCount: 3))
            .previewDisplayName("Call in progress")
        screen(Fixtures.lobby(memberCount: 3, isCameraEnabled: false))
            .previewDisplayName("Camera off")
        screen(Fixtures.lobby(memberCount: 0, isCallEndedNoticeShown: true))
            .previewDisplayName("Call ended")
        screen(Fixtures.lobby(isMicrophoneRefused: true))
            .previewDisplayName("Microphone refused")
        screen(Fixtures.lobby(isCameraRefused: true))
            .previewDisplayName("Camera refused")
    }
}
