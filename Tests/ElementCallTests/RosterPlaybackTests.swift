//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementCallKit
import Foundation
import Testing

/// Who gets a playback sink is a function of the roster, pinned here because it used to be a
/// function of the event stream -- and a lagged event stream silenced people.
struct RosterPlaybackTests {
    private let me = "@alice:example.com:ME"
    
    private func participant(_ id: String, isLocal: Bool = false, streams: [MatrixRTCStreamKind] = [.microphone]) -> MatrixRTCParticipant {
        MatrixRTCParticipant(memberID: id,
                             userID: "@\(id):example.com",
                             deviceID: nil,
                             isLocal: isLocal,
                             isReachable: true,
                             streams: streams.map { MatrixRTCStreamState(kind: $0, isMuted: $0 == .microphone && id == "muted") },
                             handRaisedAt: nil)
    }
    
    @Test
    func everyoneElseWithAMicrophoneIsPlayedMutedOrNot() {
        let roster = [participant(me, isLocal: true), participant("talking"), participant("muted"), participant("silent", streams: [.camera])]
        #expect(MatrixRTCCall.microphoneMembers(roster, localMemberID: me) == ["talking", "muted"])
    }
    
    /// Our own row can arrive before the core marks it local; the id is what keeps us from hearing ourselves.
    @Test
    func weAreNeverPlayedBackEvenBeforeTheRosterMarksUsLocal() {
        #expect(MatrixRTCCall.microphoneMembers([participant(me)], localMemberID: me).isEmpty)
    }
}
