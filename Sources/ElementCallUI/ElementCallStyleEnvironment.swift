//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCall
import SwiftUI

public extension EnvironmentValues {
    /// The host's colours, fonts, icons, avatars and text.
    ///
    /// Threaded through the environment rather than every initialiser because almost every view in
    /// the call needs some of it, and the default keeps previews and snapshots working with no host.
    @Entry var elementCallStyle: ElementCallStyle = .stock
}
