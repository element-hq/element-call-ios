//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallAll
import SwiftUI

/// Pushes generated frames into whatever slots the stage has mounted, at something like a call's
/// frame rate.
///
/// This is what makes the harness worth having for the renderer rather than only for the layout.
/// With avatars in every tile, fitting against filling, zoom, pan and — above all — the shape of the
/// picture *through* a move are all invisible, and a move is the hardest thing to look at closely in
/// a real call.
///
/// Sizes differ by member on purpose. A 16:9 landscape picture full screen on an upright phone is
/// the case this feature exists for, and a portrait one beside it is the control: whether a border
/// runs off the edges or has black beside it is the whole question, and one answer is not proof.
@MainActor
final class TestPatternVideo {
    private struct Attachment {
        let slot: VideoFrameSlot
        let size: CGSize
    }
    
    private var attachments: [UUID: Attachment] = [:]
    private var timer: Timer?
    private var phase = 0
    
    /// Landscape unless the member is one of these, so both shapes are on the stage at once.
    private static let portraitMembers = ["@bob:example.com:DEVICE", "@erin:example.com:DEVICE"]
    /// Deliberately modest. In a real call every tile is sent a layer that suits the size it is
    /// drawn at, so a strip cell a couple of hundred points wide never receives 720p; handing every
    /// tile a full-size frame is both far more work than the real thing and less like it. Nothing
    /// the harness is for — fitting, zoom, pan, the shape of a picture through a move — depends on
    /// how sharp the picture is.
    private static let landscape = CGSize(width: 640, height: 360)
    private static let portrait = CGSize(width: 360, height: 640)
    
    var source: ElementCallPreviewVideo {
        ElementCallPreviewVideo(attach: { [weak self] slot, memberID, _ in
            self?.attach(slot, memberID: memberID)
        }, detach: { [weak self] slot in
            self?.detach(slot)
        })
    }
    
    private func attach(_ slot: VideoFrameSlot, memberID: String) {
        let size = Self.portraitMembers.contains(memberID) ? Self.portrait : Self.landscape
        attachments[slot.id] = Attachment(slot: slot, size: size)
        // The first frame goes in straight away: a slot mounted mid-animation would otherwise show
        // its avatar until the next tick, which is the very stutter this is here to look for.
        offerAll()
        start()
    }
    
    private func detach(_ slot: VideoFrameSlot) {
        attachments[slot.id] = nil
        if attachments.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }
    
    /// One frame per distinct size per tick, handed to every slot that wants that size. Frames are
    /// immutable reference types, so sharing one is just a retain, where generating six identical
    /// pictures was six times the work for the same result.
    private func offerAll() {
        // Keyed by width, which is enough to tell the two sizes apart and saves making CGSize
        // hashable from outside the module that owns it.
        var generated: [Int: MatrixRTCVideoFrame] = [:]
        for attachment in attachments.values {
            let width = Int(attachment.size.width)
            let frame = generated[width] ?? MatrixRTCTestPattern.frame(width: width,
                                                                       height: Int(attachment.size.height),
                                                                       phase: phase)
            generated[width] = frame
            attachment.slot.offer(frame)
        }
    }
    
    private func start() {
        guard timer == nil else { return }
        // On `.common` rather than the default mode, which is what `Timer.scheduledTimer` installs.
        // In the default mode the timer stops while the run loop is tracking a touch, so the tile
        // was starved of frames for exactly the length of a gesture — and a surface that is not
        // given frames holds its last one, stretched to whatever shape it has reached. That made
        // the harness look considerably worse than the app it stands in for, which is the one way a
        // harness can waste more time than it saves.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.phase += 8
                self.offerAll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
