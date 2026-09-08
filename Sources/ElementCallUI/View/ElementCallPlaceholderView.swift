//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCall
import SwiftUI

/// What the Picture in Picture window shows for a member without video: avatar and name.
struct ElementCallPlaceholderView: View {
    @Environment(\.elementCallStyle) private var style
    let displayName: String
    let avatarURL: URL?
    let userID: String
    
    var body: some View {
        ZStack {
            style.theme.bgSubtleSecondary
            VStack(spacing: 8) {
                style.avatars.avatar(userID: userID,
                                     displayName: displayName,
                                     avatarURL: avatarURL,
                                     size: .full)
                Text(displayName)
                    .font(style.theme.bodySMSemibold)
                    .foregroundStyle(style.theme.textPrimary)
                    .lineLimit(1)
            }
            .padding(8)
        }
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Previews

struct ElementCallPlaceholderView_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        ElementCallPlaceholderView(displayName: "Bob", avatarURL: nil, userID: "@bob:example.com")
            .frame(width: 160, height: 120)
            .previewDisplayName("Named")
        ElementCallPlaceholderView(displayName: "@carol:example.com", avatarURL: nil, userID: "@carol:example.com")
            .frame(width: 160, height: 120)
            .previewDisplayName("Unresolved name")
    }
}
