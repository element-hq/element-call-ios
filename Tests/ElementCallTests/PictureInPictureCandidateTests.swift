//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallKit
import Testing

nonisolated struct PictureInPictureCandidateTests {
    private let me = "@alice:example.org:ME"
    
    @Test
    func spotlightScreenShareWinsOverItsCamera() {
        let participants = [participant("bob", camera: true, screenShare: true), participant("carol", camera: true)]
        let candidate = MatrixRTCCall.pictureInPictureCandidate(participants: participants, localMemberID: me, isLocalCameraAvailable: true, spotlightMemberID: "bob")
        #expect(candidate?.memberID == "bob")
        #expect(candidate?.kind == .screenShare)
    }
    
    @Test
    func fallsBackToAnyRemoteVideoWhenTheSpotlightHasNone() {
        let participants = [participant("bob"), participant("carol", camera: true)]
        let candidate = MatrixRTCCall.pictureInPictureCandidate(participants: participants, localMemberID: me, isLocalCameraAvailable: true, spotlightMemberID: "bob")
        #expect(candidate?.memberID == "carol")
        #expect(candidate?.kind == .camera)
    }
    
    @Test
    func fallsBackToOwnCameraOnlyWhenAvailable() {
        let participants = [participant("bob"), participant(me, isLocal: true, camera: true)]
        #expect(MatrixRTCCall.pictureInPictureCandidate(participants: participants, localMemberID: me, isLocalCameraAvailable: true, spotlightMemberID: nil)?.memberID == me)
        #expect(MatrixRTCCall.pictureInPictureCandidate(participants: participants, localMemberID: me, isLocalCameraAvailable: false, spotlightMemberID: nil) == nil)
    }
    
    @Test
    func placeholderNamesTheSpotlightWhenItIsSomebodyElse() {
        let participants = [participant("bob"), participant("carol")]
        #expect(MatrixRTCCall.pictureInPicturePlaceholderMemberID(participants: participants, spotlightMemberID: "carol") == "carol")
    }
    
    /// Showing the user their own avatar tells them nothing about who they are talking to, and the
    /// spotlight is often us in a call where nobody has video.
    @Test
    func placeholderSkipsTheSpotlightWhenItIsUs() {
        let participants = [participant(me, isLocal: true), participant("bob")]
        #expect(MatrixRTCCall.pictureInPicturePlaceholderMemberID(participants: participants, spotlightMemberID: me) == "bob")
    }
    
    @Test
    func placeholderFallsBackToTheFirstRemoteMemberAndIsNilWhenAlone() {
        let participants = [participant(me, isLocal: true), participant("bob"), participant("carol")]
        #expect(MatrixRTCCall.pictureInPicturePlaceholderMemberID(participants: participants, spotlightMemberID: nil) == "bob")
        // A spotlight naming nobody in the call must not be shown either.
        #expect(MatrixRTCCall.pictureInPicturePlaceholderMemberID(participants: participants, spotlightMemberID: "dave") == "bob")
        #expect(MatrixRTCCall.pictureInPicturePlaceholderMemberID(participants: [participant(me, isLocal: true)], spotlightMemberID: nil) == nil)
    }
    
    private func participant(_ memberID: String, isLocal: Bool = false, camera: Bool = false, screenShare: Bool = false) -> MatrixRTCParticipant {
        var streams: [MatrixRTCStreamState] = [.init(kind: .microphone, isMuted: false)]
        if camera {
            streams.append(.init(kind: .camera, isMuted: false))
        }
        if screenShare {
            streams.append(.init(kind: .screenShare, isMuted: false))
        }
        return MatrixRTCParticipant(memberID: memberID, userID: "@\(memberID):example.org", deviceID: nil, isLocal: isLocal, isReachable: true, streams: streams, handRaisedAt: nil)
    }
}
