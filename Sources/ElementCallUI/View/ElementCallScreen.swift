//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCall
import SwiftUI

/// The full-screen call. This is what a host presents.
///
/// The view model is passed in rather than built here so the host owns its lifetime, which is what
/// its own coordinators expect, and so the observation it starts is not restarted by a redraw.
///
/// Everything the inner view needs, the Picture in Picture anchor, the live call for the video
/// tiles, and the host's style, is wired here rather than being asked of the host.
public struct ElementCallScreen: View {
    private let viewModel: ElementCallScreenViewModel
    
    public init(viewModel: ElementCallScreenViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ElementCallView(context: viewModel.context,
                        pictureInPictureSourceView: viewModel.pictureInPictureSourceView) { [viewModel] in
            viewModel.call
        }
        .environment(\.elementCallStyle, viewModel.context.style)
    }
}
