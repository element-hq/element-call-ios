//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallKit
import Testing

struct PictureInPictureCandidateTests {
    private let me = "@alice:example.org:ME"
    
    @Test
    func spotlightScreenShareWinsOverItsCamera() {
        let participants = [participant("bob", camera: true, screenShare: true), participant("carol", camera: true)]
        let candidate = MatrixRtcCall.pictureInPictureCandidate(participants: participants, localMemberID: me, isLocalCameraAvailable: true, spotlightMemberID: "bob")
        #expect(candidate?.memberID == "bob")
        #expect(candidate?.kind == .screenShare)
    }
    
    @Test
    func fallsBackToAnyRemoteVideoWhenTheSpotlightHasNone() {
        let participants = [participant("bob"), participant("carol", camera: true)]
        let candidate = MatrixRtcCall.pictureInPictureCandidate(participants: participants, localMemberID: me, isLocalCameraAvailable: true, spotlightMemberID: "bob")
        #expect(candidate?.memberID == "carol")
        #expect(candidate?.kind == .camera)
    }
    
    @Test
    func fallsBackToOwnCameraOnlyWhenAvailable() {
        let participants = [participant("bob"), participant(me, isLocal: true, camera: true)]
        #expect(MatrixRtcCall.pictureInPictureCandidate(participants: participants, localMemberID: me, isLocalCameraAvailable: true, spotlightMemberID: nil)?.memberID == me)
        #expect(MatrixRtcCall.pictureInPictureCandidate(participants: participants, localMemberID: me, isLocalCameraAvailable: false, spotlightMemberID: nil) == nil)
    }
    
    private func participant(_ memberID: String, isLocal: Bool = false, camera: Bool = false, screenShare: Bool = false) -> MatrixRtcParticipant {
        var streams: [MatrixRtcStreamState] = [.init(kind: .microphone, isMuted: false)]
        if camera {
            streams.append(.init(kind: .camera, isMuted: false))
        }
        if screenShare {
            streams.append(.init(kind: .screenShare, isMuted: false))
        }
        return MatrixRtcParticipant(memberID: memberID, userID: "@\(memberID):example.org", deviceID: nil, isLocal: isLocal, isReachable: true, streams: streams, handRaisedAt: nil)
    }
}
