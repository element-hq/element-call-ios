//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import ElementCall
import SwiftUI

/// The ongoing call, shrunk to a bar at the top of the app. Tapping it restores the full screen.
///
/// The host places this itself, because only the host knows where the top of its own chrome is. It
/// is offered for a call with no video to show, and for a video call whose Picture in Picture window
/// could not open, both of which arrive as
/// ``ElementCallControllerAction/pictureInPictureUnavailable``.
public struct ElementCallMinimizedBar: View {
    private let controller: ElementCallController
    private let onTap: () -> Void
    
    @Environment(\.elementCallStyle) private var style
    @State private var roomName: String
    
    public init(controller: ElementCallController, onTap: @escaping () -> Void) {
        self.controller = controller
        self.onTap = onTap
        roomName = controller.room?.displayName ?? "Call"
    }
    
    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                style.icons.icon(.videoCall, size: .small, relativeTo: .bodySMSemibold)
                Text(roomName)
                    .lineLimit(1)
                if let connectedAt = controller.connectedAt {
                    Text(connectedAt, style: .timer)
                        .monospacedDigit()
                }
                Spacer()
                style.icons.icon(controller.call?.isMicrophoneMuted == true ? .micOff : .micOn,
                                 size: .small,
                                 relativeTo: .bodySMSemibold)
                Text("Return")
            }
            .font(style.theme.bodySMSemibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(style.theme.bgAccentRest, in: Capsule())
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Return to call")
        .accessibilityIdentifier(ElementCallAccessibilityIdentifiers.minimizedBar)
        .environment(\.elementCallStyle, controller.style)
        .onReceive(namePublisher) { roomName = $0 }
    }
    
    /// A room opened moments ago may not have its name yet, so the bar follows it rather than
    /// capturing whatever was known when the call started.
    private var namePublisher: AnyPublisher<String, Never> {
        controller.room?.displayNamePublisher ?? Empty().eraseToAnyPublisher()
    }
}
