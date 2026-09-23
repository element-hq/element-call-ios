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
    
    /// The spotlight names its own stream now, so this is no longer a question of working out which
    /// of a member's streams was meant: the window continues the picture the stage is showing.
    @Test
    func theSpotlightsOwnStreamIsWhatTheWindowContinues() {
        let participants = [participant("bob", camera: true, screenShare: true), participant("carol", camera: true)]
        let share = MatrixRTCTileID(memberID: "bob", kind: .screenShare)
        #expect(MatrixRTCCall.pictureInPictureCandidate(participants: participants, localMemberID: me, isLocalCameraAvailable: true, spotlight: share) == share)
        let camera = MatrixRTCTileID(memberID: "bob", kind: .person)
        #expect(MatrixRTCCall.pictureInPictureCandidate(participants: participants, localMemberID: me, isLocalCameraAvailable: true, spotlight: camera) == camera)
    }
    
    @Test
    func fallsBackToAnyRemoteVideoWhenTheSpotlightHasNone() {
        let participants = [participant("bob"), participant("carol", camera: true)]
        let candidate = MatrixRTCCall.pictureInPictureCandidate(participants: participants, localMemberID: me, isLocalCameraAvailable: true, spotlight: MatrixRTCTileID(memberID: "bob"))
        #expect(candidate == MatrixRTCTileID(memberID: "carol", kind: .person))
    }
    
    /// A share can stop while the window is continuing it, and the stage takes a moment to catch up.
    /// The candidate has to notice that the stream it was told about is no longer being published,
    /// rather than attaching to a stream nobody is sending.
    @Test
    func aSpotlightWhoseStreamStoppedFallsBackRatherThanAttachingToNothing() {
        let participants = [participant("bob", camera: true), participant("carol", camera: true)]
        let goneShare = MatrixRTCTileID(memberID: "bob", kind: .screenShare)
        let candidate = MatrixRTCCall.pictureInPictureCandidate(participants: participants, localMemberID: me, isLocalCameraAvailable: true, spotlight: goneShare)
        #expect(candidate == MatrixRTCTileID(memberID: "bob", kind: .person))
    }
    
    @Test
    func fallsBackToOwnCameraOnlyWhenAvailable() {
        let participants = [participant("bob"), participant(me, isLocal: true, camera: true)]
        #expect(MatrixRTCCall.pictureInPictureCandidate(participants: participants, localMemberID: me, isLocalCameraAvailable: true, spotlight: nil) == MatrixRTCTileID(memberID: me, kind: .person))
        #expect(MatrixRTCCall.pictureInPictureCandidate(participants: participants, localMemberID: me, isLocalCameraAvailable: false, spotlight: nil) == nil)
    }
    
    @Test
    func placeholderNamesTheSpotlightWhenItIsSomebodyElse() {
        let participants = [participant("bob"), participant("carol")]
        #expect(MatrixRTCCall.pictureInPicturePlaceholderMemberID(participants: participants, spotlight: MatrixRTCTileID(memberID: "carol")) == "carol")
    }
    
    /// Showing the user their own avatar tells them nothing about who they are talking to, and the
    /// spotlight is often us in a call where nobody has video.
    @Test
    func placeholderSkipsTheSpotlightWhenItIsUs() {
        let participants = [participant(me, isLocal: true), participant("bob")]
        #expect(MatrixRTCCall.pictureInPicturePlaceholderMemberID(participants: participants, spotlight: MatrixRTCTileID(memberID: me)) == "bob")
    }
    
    @Test
    func placeholderFallsBackToTheFirstRemoteMemberAndIsNilWhenAlone() {
        let participants = [participant(me, isLocal: true), participant("bob"), participant("carol")]
        #expect(MatrixRTCCall.pictureInPicturePlaceholderMemberID(participants: participants, spotlight: nil) == "bob")
        // A spotlight naming nobody in the call must not be shown either.
        #expect(MatrixRTCCall.pictureInPicturePlaceholderMemberID(participants: participants, spotlight: MatrixRTCTileID(memberID: "dave")) == "bob")
        #expect(MatrixRTCCall.pictureInPicturePlaceholderMemberID(participants: [participant(me, isLocal: true)], spotlight: nil) == nil)
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
