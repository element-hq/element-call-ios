//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCall
import SwiftUI

/// The call screen over a view state written by hand, with no call behind it.
///
/// This is the seam the previews have always used, made public for the example harness. A live
/// screen needs an ``ElementCallScreenViewModel``, which needs a controller, which produces no tiles
/// until it has actually joined something: a harness built that way could only ever show a spinner.
/// Tiles claiming video fall back to their avatar here, because there is no call to pull frames
/// from, which is what a snapshot wants anyway and all a UI test driving the gestures needs.
///
/// Not for shipping. A host presents ``ElementCallScreen``.
public struct ElementCallHarnessScreen: View {
    private let context: ElementCallScreenContext
    
    public init(context: ElementCallScreenContext) {
        self.context = context
    }
    
    public var body: some View {
        ElementCallView(context: context,
                        pictureInPictureSourceView: UIView(),
                        callProvider: { nil })
            .environment(\.elementCallStyle, context.style)
    }
}
