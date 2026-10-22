//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallKit
import Foundation

/// Host settings the call reads. Named Options rather than Configuration because hosts embedding the
/// Element Call widget already have a configuration type of their own.
///
/// A value rather than a protocol, because every member is data a host simply states. Each is read
/// at a discrete moment — compat when a session joins, the Picture in Picture flags when the window
/// binds, developer mode when a toggle is tapped — never per frame, so a live pull has nothing to
/// win. This *was* a protocol of computed properties, on the theory that a host backing it with
/// settings would want a change seen mid-session. No read path ever needed that, and the one host
/// member that was settings-backed could not change while a stack lived, because the same flag
/// decided whether the stack existed. If a live value is genuinely wanted one day, the controller's
/// `options` can gain a setter without breaking anyone; shipping one before there is a caller would
/// only invite a host to wire a publisher to a value read once at join.
///
/// Adding a member is source-compatible as long as its initialiser parameter is defaulted. That is
/// the mechanism to reach for — not a protocol extension supplying a default, which is what this
/// needed while it was a protocol and which hid the addition from every host.
public nonisolated struct ElementCallOptions: Sendable {
    /// Whether a minimized call may open a Picture in Picture window. A host without the
    /// background mode entitlement should set this false, and calls minimize to the bar instead.
    public var isPictureInPictureEnabled: Bool
    /// How membership is published. Pinned by the host because it has to match the other clients in
    /// the room, and it cannot change once a session has joined.
    public var membershipFormat: MatrixRTCMembershipFormat
    /// Whether the call screen offers its developer affordances, currently the per-tile stats
    /// overlay. That is raw RTP counters in 9pt monospace, so this belongs on whatever a host
    /// already uses to reveal developer surface, never on a feature flag ordinary users carry.
    ///
    /// Deliberately not what gates screen sharing: a host may well want to ship that to everyone
    /// while keeping diagnostics to itself, so the two are separate axes.
    public var isDeveloperModeEnabled: Bool
    /// Whether *this* user may start sharing their screen. Receiving someone else's share is never
    /// affected — a remote share still takes the spotlight and renders — because a call with a Web
    /// peer presenting would otherwise look broken.
    ///
    /// The same kind of question as ``isPictureInPictureEnabled`` — the package supporting a feature
    /// is not enough, the host has work of its own — but the opposite default, because that work is
    /// not done yet. Off until a host opts in, rather than on and half-wired.
    public var isScreenSharingEnabled: Bool
    /// Whether *leaving the app* during an audio-only call may open the window by itself. A video
    /// call always may.
    ///
    /// Separate from ``isPictureInPictureEnabled``, which governs minimizing on purpose. The
    /// default is false because CallKit's island already represents a backgrounded audio call, and
    /// a window appearing on every app switch is intrusive when there is only an avatar to show.
    public var isAutomaticPictureInPictureForAudioCallsEnabled: Bool
    /// Above this many people in the call, counting ourselves, nobody joining or leaving plays a
    /// sound. Read when media connects. Not a user setting: it is how big a call has to be before
    /// arrivals stop being news, and both platforms default to the same number.
    ///
    /// Join and leave sounds have no off switch, as on web; this is the only thing that quiets them.
    /// Any switch for other sound effects, such as reactions, is a separate option.
    public var participantCapForJoinLeaveSounds: Int
    /// Whether our media may move to another member's media server once ours has been down for
    /// ten seconds while the homeserver answers and a peer's server is up (034 R25). Off by
    /// default, because it only works where that server accepts users from other homeservers, and
    /// which deployments do is something only the host can know: the homeserver's transport list
    /// cannot say, since the SDK drops every field of a LiveKit entry but its URL. Read when media
    /// connects.
    public var isSFUFallbackEnabled: Bool
    
    public init(isPictureInPictureEnabled: Bool = true,
                membershipFormat: MatrixRTCMembershipFormat = .roomState,
                isDeveloperModeEnabled: Bool = false,
                isScreenSharingEnabled: Bool = false,
                isAutomaticPictureInPictureForAudioCallsEnabled: Bool = false,
                participantCapForJoinLeaveSounds: Int = MatrixRTCMediaSession.defaultParticipantCapForJoinLeaveSounds,
                isSFUFallbackEnabled: Bool = false) {
        self.isPictureInPictureEnabled = isPictureInPictureEnabled
        self.membershipFormat = membershipFormat
        self.isDeveloperModeEnabled = isDeveloperModeEnabled
        self.isScreenSharingEnabled = isScreenSharingEnabled
        self.isAutomaticPictureInPictureForAudioCallsEnabled = isAutomaticPictureInPictureForAudioCallsEnabled
        self.participantCapForJoinLeaveSounds = participantCapForJoinLeaveSounds
        self.isSFUFallbackEnabled = isSFUFallbackEnabled
    }
}

public nonisolated enum ElementCallLogLevel: Sendable {
    case debug, info, warning, error
}

/// Where our log lines go. The host owns this so call logs land in the same place, and the same
/// rageshake, as everything else it writes.
///
/// Note this covers only this package's own lines. The media layer's logs, and the Rust core's, go
/// through the core's own subscriber, which the host installs separately.
/// One of our own log lines, with the position it came from.
public nonisolated struct ElementCallLogRecord: Sendable {
    public let level: ElementCallLogLevel
    public let message: String
    /// `#fileID` of the call site, e.g. `ElementCall/ElementCallController.swift`.
    public let file: String
    public let line: Int
    
    public init(level: ElementCallLogLevel, message: String, file: String, line: Int) {
        self.level = level
        self.message = message
        self.file = file
        self.line = line
    }
}

public nonisolated protocol ElementCallLoggingProtocol: Sendable {
    /// The one method a host implements.
    ///
    /// Takes a record rather than `(level, message, file, line)` because the convenience below
    /// needs `#fileID` and `#line` defaults, and Swift does not allow default arguments on a
    /// protocol requirement — an extension with the same signature would become the requirement's
    /// own default implementation and recurse forever on a host that did not override it.
    func log(_ record: ElementCallLogRecord)
}

public nonisolated extension ElementCallLoggingProtocol {
    /// What everything in this package calls. The defaults make the call site attribute itself,
    /// so a host formatting a line with a position gets our source rather than its own bridge.
    func log(_ level: ElementCallLogLevel, _ message: String, file: String = #fileID, line: Int = #line) {
        log(ElementCallLogRecord(level: level, message: message, file: file, line: line))
    }
}

/// Text the call screen shows. English defaults, because a host without translations should still
/// get something readable rather than a key.
public nonisolated struct ElementCallStrings: Sendable {
    public var you: String
    public var error: String
    public var stop: String
    public var back: String
    /// The audio output menu's rows for the built-in outputs and wired headphones. Other hardware
    /// is named by its port, which is the name the user gave their headset or car.
    public var speaker: String
    public var phone: String
    public var headphones: String
    /// Beneath the room's name while a direct call rings the other person.
    public var calling: String
    /// What a screen reader says for the ringing avatar, given the callee's name.
    public var callingPerson: @Sendable (String) -> String
    /// Why a call failed, shown on the failure screen until the user closes it (034 R27): a title
    /// per kind of failure, and a sentence per cause beneath it.
    public var connectionLostTitle: String
    public var connectionFailedTitle: String
    public var joinFailedTitle: String
    public var callFailedTitle: String
    public var connectionLost: String
    public var connectionRefused: String
    public var connectionNeverEstablished: String
    public var joinTimedOut: String
    public var joinRefused: String
    /// The failure screen's one button.
    public var close: String
    /// What a screen reader says for a control an interruption has disabled (034 R15).
    public var unavailable: String
    /// What a screen reader says for a tile's loading indicator: our own media server is not up
    /// yet, the connection carrying the member's media is being re-established, or their media
    /// cannot be decrypted (034 R40); and for the icon that replaces it once their keys have stayed
    /// away (034 Q8), or when they sent their media unencrypted.
    public var mediaConnecting: String
    public var mediaReconnecting: String
    public var mediaUndecryptable: String
    public var mediaKeysMissing: String
    public var mediaNotEncrypted: String
    /// The service interruptions indicator, and what a screen reader says when it goes (034 R35,
    /// R40). Short: it sits over the stage.
    public var interruptions: String
    public var interruptionsResolved: String
    /// The list's entries (034 R13, R17, R23, R29). The server entry reads `ownServerLapsed` once
    /// the others have dropped us.
    public var ownServerUnreachable: String
    public var ownServerLapsed: String
    public var ownMediaReconnecting: String
    public var othersMediaInterrupted: String
    
    public init(you: String = "You",
                error: String = "Error",
                stop: String = "Stop",
                back: String = "Back",
                speaker: String = "Speaker",
                phone: String = "Phone",
                headphones: String = "Headphones",
                calling: String = "Calling\u{2026}",
                callingPerson: @escaping @Sendable (String) -> String = { "Calling \($0)" },
                connectionLostTitle: String = "Connection lost",
                connectionFailedTitle: String = "Couldn\u{2019}t connect",
                joinFailedTitle: String = "Couldn\u{2019}t join the call",
                callFailedTitle: String = "Call failed",
                connectionLost: String = "Your connection to the call couldn\u{2019}t be restored.",
                connectionRefused: String = "The call\u{2019}s media server refused the connection.",
                connectionNeverEstablished: String = "The call\u{2019}s media server couldn\u{2019}t be reached.",
                joinTimedOut: String = "Your server didn\u{2019}t respond in time.",
                joinRefused: String = "Your server refused to let you join.",
                close: String = "Close",
                unavailable: String = "Unavailable",
                mediaConnecting: String = "Connecting",
                mediaReconnecting: String = "Reconnecting",
                mediaUndecryptable: String = "Waiting for encryption keys",
                mediaKeysMissing: String = "Encryption keys missing",
                mediaNotEncrypted: String = "Not encrypted",
                interruptions: String = "Service interruptions",
                interruptionsResolved: String = "Connection restored",
                ownServerUnreachable: String = "Your server is unreachable. Some services are temporarily unavailable.",
                // The same as above until 034's Q5 settles whether a lapse stops our media at all.
                ownServerLapsed: String = "Your server is unreachable. Some services are temporarily unavailable.",
                ownMediaReconnecting: String = "Reconnecting your audio and video",
                othersMediaInterrupted: String = "Some participants\u{2019} audio or video isn\u{2019}t reaching you") {
        self.you = you
        self.error = error
        self.stop = stop
        self.back = back
        self.speaker = speaker
        self.phone = phone
        self.headphones = headphones
        self.calling = calling
        self.callingPerson = callingPerson
        self.connectionLostTitle = connectionLostTitle
        self.connectionFailedTitle = connectionFailedTitle
        self.joinFailedTitle = joinFailedTitle
        self.callFailedTitle = callFailedTitle
        self.connectionLost = connectionLost
        self.connectionRefused = connectionRefused
        self.connectionNeverEstablished = connectionNeverEstablished
        self.joinTimedOut = joinTimedOut
        self.joinRefused = joinRefused
        self.close = close
        self.unavailable = unavailable
        self.mediaConnecting = mediaConnecting
        self.mediaReconnecting = mediaReconnecting
        self.mediaUndecryptable = mediaUndecryptable
        self.mediaKeysMissing = mediaKeysMissing
        self.mediaNotEncrypted = mediaNotEncrypted
        self.interruptions = interruptions
        self.interruptionsResolved = interruptionsResolved
        self.ownServerUnreachable = ownServerUnreachable
        self.ownServerLapsed = ownServerLapsed
        self.ownMediaReconnecting = ownMediaReconnecting
        self.othersMediaInterrupted = othersMediaInterrupted
    }
    
    /// The failure screen's title for a failure.
    public func title(for failure: ElementCallFailure) -> String {
        switch failure {
        case .connectionLost(.budget): connectionLostTitle
        case .connectionLost(.refused), .connectionLost(.neverConnected): connectionFailedTitle
        case .joinTimedOut, .joinRefused: joinFailedTitle
        case .other: callFailedTitle
        }
    }
    
    /// The sentence beneath the title.
    public func text(for failure: ElementCallFailure) -> String {
        switch failure {
        case .connectionLost(.budget): connectionLost
        case .connectionLost(.refused): connectionRefused
        case .connectionLost(.neverConnected): connectionNeverEstablished
        case .joinTimedOut: joinTimedOut
        case .joinRefused: joinRefused
        case .other(let message): message
        }
    }
}
