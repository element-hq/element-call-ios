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

/// Under the top bar, in a space the lobby always keeps so the preview never moves: while somebody
/// is in the call, that it is in progress and how many (R41); once it has emptied, that it has ended
/// (R57). Empty while loading and while nobody is in the call. The same piece, in the same place, as
/// Android's `CallLobbySummary`; where it sits is design's (Q8).
struct ElementCallLobbySummary: View {
    @Environment(\.elementCallStyle) private var style
    let lobby: ElementCallLobbyViewState
    let isAudioCall: Bool
    
    static let height: CGFloat = 48
    
    var body: some View {
        Group {
            if lobby.isCallEndedNoticeShown {
                // Said as it appears, without moving focus off what the user is on (R58).
                Text(L10nPending.lobbyCallEnded)
                    .font(style.theme.bodyLGSemibold)
                    .foregroundStyle(style.theme.textPrimary)
                    .accessibilityIdentifier(ElementCallAccessibilityIdentifiers.lobbyCallEnded)
                    .onAppear {
                        AccessibilityNotification.Announcement(L10nPending.lobbyCallEnded).post()
                    }
            } else if let count = lobby.shownMemberCount {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        style.icons.icon(isAudioCall ? .voiceCall : .videoCall, size: .small, relativeTo: .bodyLGSemibold)
                            .foregroundStyle(style.theme.iconSecondary)
                            .accessibilityHidden(true)
                        Text(L10nPending.lobbyCallInProgress)
                            .font(style.theme.bodyLGSemibold)
                            .foregroundStyle(style.theme.textPrimary)
                    }
                    // The core counts the call and does not say who is in it before Join (R43), so
                    // a number and no faces. Spoken as a sentence.
                    HStack(spacing: 6) {
                        style.icons.icon(.userProfile, size: .xSmall, relativeTo: .bodySM)
                            .foregroundStyle(style.theme.iconSecondary)
                        Text("\(count)")
                            .font(style.theme.bodySMSemibold)
                            .foregroundStyle(style.theme.textPrimary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10nPending.lobbyMemberCount(count))
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(ElementCallAccessibilityIdentifiers.lobbySummary)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .animation(.easeInOut(duration: 0.25), value: lobby.isCallEndedNoticeShown)
        .animation(.easeInOut(duration: 0.25), value: lobby.shownMemberCount == nil)
    }
}

/// Held sideways, the lobby's summary, controls and Join as a column at the trailing edge, beside
/// the preview: under it they left the preview a strip (Q5). Android's `CallLobbyPanel`, at the same
/// width. At Join the call's own bar takes over along the bottom.
struct ElementCallLobbyPanel: View {
    @Bindable var context: ElementCallScreenContext
    let lobby: ElementCallLobbyViewState
    
    static let maximumWidth: CGFloat = 320
    
    static func width(in screenWidth: CGFloat) -> CGFloat {
        min(maximumWidth, screenWidth / 2)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            ElementCallLobbySummary(lobby: lobby, isAudioCall: context.viewState.isAudioCall)
            ElementCallControlsView(context: context, axis: .horizontal)
            ElementCallLobbyJoinButton(lobby: lobby) { context.send(viewAction: .join) }
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
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
