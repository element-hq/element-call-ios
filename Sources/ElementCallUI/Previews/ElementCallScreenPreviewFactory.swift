//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCall
import Foundation

/// Builds view models over the port fakes, so previews and snapshots need no host and no network.
@MainActor
public enum ElementCallScreenPreviewFactory {
    public static func makeViewModel(connection: ElementCallConnection,
                                     isDirect: Bool = false) -> ElementCallScreenViewModel {
        let room = ElementCallFakeRoom(displayName: "Product | Lobby", isDirect: isDirect)
        return ElementCallScreenViewModel(controller: .fake(connection: connection, room: room))
    }
}
