//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

/// What the system Picture in Picture window shows when the member on screen has no video: their
/// avatar and name on black.
///
/// It lives here rather than in the view module because the window is hosted by the controller,
/// which is the thing AVKit talks to, and because it must keep drawing after the call screen itself
/// has gone away.
struct ElementCallPictureInPicturePlaceholder: View {
    let profile: ElementCallMemberProfile?
    let fallbackName: String
    let style: ElementCallStyle
    
    private var name: String {
        profile?.displayName ?? profile?.userID ?? fallbackName
    }
    
    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 8) {
                style.avatars.avatar(userID: profile?.userID ?? fallbackName,
                                     displayName: profile?.displayName,
                                     avatarURL: profile?.avatarURL,
                                     size: .full)
                Text(name)
                    .font(style.theme.bodySMSemibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding()
        }
    }
}
