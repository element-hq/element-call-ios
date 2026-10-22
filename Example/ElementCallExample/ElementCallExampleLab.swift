//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVFoundation
import Combine
import ElementCall
import Foundation

/// What the lab's QR code carries (`element-call-feature-hq/harness/lab.md`, "Accounts and joining"):
///
///     elementcall-lab://join?hs=https://hs-a.192-168-1-10.nip.io&user=alice&password=…&room=!abc:lab-a
///
/// The same four parameters on both platforms, the way fixture keys are shared. Unknown parameters
/// are ignored. `-lab <url>` passes one at launch, for `devicectl` and the simulator.
struct ElementCallExampleLabJoin: Equatable {
    static let scheme = "elementcall-lab"
    static let launchArgument = "-lab"
    
    let homeserver: String
    let user: String
    let password: String
    let roomID: String
    
    init?(url: URL) {
        guard url.scheme == Self.scheme, url.host() == "join",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let value = { (name: String) in items.first { $0.name == name }?.value }
        guard let homeserver = value("hs"), let user = value("user"),
              let password = value("password"), let roomID = value("room") else { return nil }
        self.homeserver = homeserver
        self.user = user
        self.password = password
        self.roomID = roomID
    }
    
    /// Where the lab serves its CA: the same name suffix as the homeserver, under `lab.`.
    var certificateURL: URL? {
        guard let hs = URL(string: homeserver), let host = hs.host(),
              let dot = host.firstIndex(of: ".") else { return nil }
        return URL(string: "https://lab\(host[dot...])/lab-ca.crt")
    }
}

/// Makes the Rust media layer trust the lab's CA. The phone trusts it for the SDK's HTTP once the
/// profile is installed, but the core's token exchange and SFU socket use rustls, which reads
/// `SSL_CERT_FILE` rather than the system's trust settings. So the CA is fetched (over TLS the
/// phone already trusts) and the variable set before anything in the core opens a connection.
enum ElementCallExampleLabTrust {
    static func install(from url: URL?) async {
        guard let url else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let dir = URL.applicationSupportDirectory.appending(path: "lab-ca")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appending(path: "lab-ca.pem")
            try data.write(to: file)
            setenv("SSL_CERT_FILE", file.path(percentEncoded: false), 1)
        } catch {
            FileHandle.standardError.write(Data("[lab] could not fetch the lab CA from \(url): \(error)\n".utf8))
        }
    }
}

/// The system port for a lab call: no CallKit, so the audio session is ours to activate. The
/// controller starts audio only once the system says the session is up (it normally hears that
/// from CallKit), and on a device nothing else would say it.
@MainActor
final class ElementCallExampleLabSystem: ElementCallSystemProvidingProtocol {
    private let subject = PassthroughSubject<ElementCallSystemEvent, Never>()
    
    var events: AnyPublisher<ElementCallSystemEvent, Never> {
        subject.eraseToAnyPublisher()
    }
    
    func startCall(roomID: String, displayName: String, isVideo: Bool) async {
        do {
            try CallAudioSessionConfigurator.configure()
            try CallAudioSessionConfigurator.activate()
            subject.send(.audioSessionActivated)
        } catch {
            FileHandle.standardError.write(Data("[lab] could not activate the audio session: \(error)\n".utf8))
        }
    }
    
    func reportConnected(roomID: String) { }
    
    func endCall(roomID: String, reason: ElementCallEndReason) {
        subject.send(.audioSessionDeactivated)
        CallAudioSessionConfigurator.deactivate()
    }
    
    func setMicrophoneEnabled(_ enabled: Bool, roomID: String) { }
}

/// The package's log on stderr, beside the core's, which the app already sends there.
struct ElementCallExampleLabLogger: ElementCallLoggingProtocol {
    func log(_ record: ElementCallLogRecord) {
        FileHandle.standardError.write(Data("[ElementCall \(record.level)] \(record.message)\n".utf8))
    }
}
