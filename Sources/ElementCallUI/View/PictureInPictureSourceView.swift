//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

/// Hosts the Picture in Picture controller's source view behind the spotlight tile. AVKit needs a real
/// view on screen to start the window automatically on backgrounding and to animate from its frame.
struct PictureInPictureSourceView: UIViewRepresentable {
    let sourceView: UIView
    
    func makeUIView(context: Context) -> UIView {
        sourceView.removeFromSuperview()
        return sourceView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) { }
}
