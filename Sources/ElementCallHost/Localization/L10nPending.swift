//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// The call lobby's strings, before they are in the element-call Localazy project (feature-hq 045,
/// contract C26 and C30): the keys Android uses, with its English.
///
/// Written by hand, and kept out of `Localizable.strings` and `L10n` on purpose: both are generated,
/// a download would drop keys Localazy does not have, and the weekly translations run deletes the
/// whole `Localizations` directory first. So the table lives in `Resources/PendingLocalizations`,
/// in English only, and is looked up through ``ElementCallLocalization`` like the rest, in the
/// host's language with English behind it.
///
/// To retire a key once it is in `mobile.json`: run `scripts/download-strings.sh`, replace
/// `L10nPending.x` with the generated `L10n.x`, and delete the key here and from `Pending.strings`
/// or `Pending.stringsdict`. When the last one goes, so do this file and the table.
package nonisolated enum L10nPending {
    private static let table = "Pending"
    
    /// Camera not allowed
    package static var a11yCameraNotAllowed: String {
        ElementCallLocalization.string(table, "element_call_a11y_camera_not_allowed")
    }
    
    /// Your camera
    package static var a11yLobbyCamera: String {
        ElementCallLocalization.string(table, "element_call_a11y_lobby_camera")
    }
    
    /// The call has ended
    package static var lobbyCallEnded: String {
        ElementCallLocalization.string(table, "element_call_lobby_call_ended")
    }
    
    /// Group call in progress…
    package static var lobbyCallInProgress: String {
        ElementCallLocalization.string(table, "element_call_lobby_call_in_progress")
    }
    
    /// Join call
    package static var lobbyJoin: String {
        ElementCallLocalization.string(table, "element_call_lobby_join")
    }
    
    /// Join anyway
    package static var lobbyJoinAnyway: String {
        ElementCallLocalization.string(table, "element_call_lobby_join_anyway")
    }
    
    /// Loading call
    package static var lobbyLoading: String {
        ElementCallLocalization.string(table, "element_call_lobby_loading")
    }
    
    /// Allow access to the microphone to join.
    package static var lobbyMicrophoneDescription: String {
        ElementCallLocalization.string(table, "element_call_lobby_microphone_description")
    }
    
    /// Start group call
    package static var lobbyStart: String {
        ElementCallLocalization.string(table, "element_call_lobby_start")
    }
    
    /// %1$d person in the call / %1$d people in the call
    package static func lobbyMemberCount(_ count: Int) -> String {
        ElementCallLocalization.string(table, "element_call_lobby_member_count", count)
    }
}
