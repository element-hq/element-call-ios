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
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                VStack(spacing: side * 0.04) {
                    ScaledToFit(side: side * 0.45) {
                        style.avatars.avatar(userID: profile?.userID ?? fallbackName,
                                             displayName: profile?.displayName,
                                             avatarURL: profile?.avatarURL,
                                             size: .full)
                    }
                    Text(name)
                        .font(style.theme.bodySMSemibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        // The window is as small as the user drags it, and a truncated name is
                        // worse than a small one when it is the only thing identifying the call.
                        .minimumScaleFactor(0.5)
                }
                .padding(side * 0.08)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

/// Shrinks whatever the host produced to fit a square of `side`, never enlarging it.
///
/// The host sizes `.full` for a full-bleed tile on the call screen, which is several times the
/// height of a Picture in Picture window, and it is entitled to: the same case draws the stage.
/// An outer `.frame` will not shrink a view that set its own, so the natural size is measured and
/// the result scaled — which works whatever the host's avatar turns out to be.
private struct ScaledToFit<Content: View>: View {
    let side: CGFloat
    @ViewBuilder let content: Content
    
    @State private var naturalSide: CGFloat = 0
    
    var body: some View {
        content
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { max($0.size.width, $0.size.height) } action: { naturalSide = $0 }
            .scaleEffect(naturalSide > 0 ? min(1, side / naturalSide) : 1)
            .frame(width: side, height: side)
    }
}
