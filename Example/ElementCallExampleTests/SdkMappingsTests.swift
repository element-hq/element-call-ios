//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCall
import Foundation
import MatrixRustSDK
import Testing

struct SdkMappingsTests {
    // MARK: Events
    
    @Test
    func stateIsReportedUnderTheSubscribedSpelling() throws {
        let event = RoomStateEvent(eventType: stateEventTypeFromString(s: "org.matrix.msc3401.call.member"),
                                   stateKey: "_@bob:example.org_DEV",
                                   sender: "@bob:example.org",
                                   contentJson: #"{"application":"m.call"}"#,
                                   eventId: "$member",
                                   timestamp: 1234)
        
        let ffi = try #require(SdkMappings.event(event, subscribedAs: "m.call.member"))
        
        #expect(ffi.eventType == "m.call.member")
        #expect(ffi.eventId == "$member")
        #expect(ffi.stateKey == "_@bob:example.org_DEV")
        #expect(ffi.originServerTs == 1234)
        #expect(ffi.contentJson == #"{"application":"m.call"}"#)
        #expect(!ffi.encryption.encrypted)
    }
    
    @Test
    func strippedStateIsDropped() {
        let event = RoomStateEvent(eventType: stateEventTypeFromString(s: "m.call.member"),
                                   stateKey: "",
                                   sender: "@bob:example.org",
                                   contentJson: "{}",
                                   eventId: nil,
                                   timestamp: nil)
        
        #expect(SdkMappings.event(event, subscribedAs: "m.call.member") == nil)
    }
    
    @Test
    func messageLikeEventsCarryTheirEncryption() {
        let event = RoomMessageLikeEvent(eventType: messageLikeEventTypeFromString(s: "m.reaction"),
                                         eventId: "$hand",
                                         sender: "@bob:example.org",
                                         timestamp: 99,
                                         contentJson: "{}",
                                         encryptionInfo: encryptionInfo(senderID: "@bob:example.org", shield: .none))
        
        let ffi = SdkMappings.event(event, subscribedAs: "m.reaction")
        
        #expect(ffi.eventType == "m.reaction")
        #expect(ffi.stateKey == nil)
        #expect(ffi.encryption.encrypted)
        #expect(ffi.encryption.senderDeviceId == "BOBDEVICE")
    }
    
    @Test
    func redactsIsReadFromTheContent() {
        #expect(SdkMappings.redactedEventID(fromContent: #"{"redacts":"$hand","reason":"lowered"}"#) == "$hand")
        // Before room version 11 `redacts` sat beside the content, which the SDK does not hand over.
        #expect(SdkMappings.redactedEventID(fromContent: #"{"reason":"lowered"}"#) == nil)
        #expect(SdkMappings.redactedEventID(fromContent: "not json") == nil)
    }
    
    // MARK: Trust
    
    @Test
    func aSenderIsConfirmedUnlessItsShieldIsRed() {
        #expect(SdkMappings.encryption(encryptionInfo(senderID: "@bob:example.org", shield: .none)).senderConfirmed == true)
        #expect(SdkMappings.encryption(encryptionInfo(senderID: "@bob:example.org", shield: .grey(code: .authenticityNotGuaranteed))).senderConfirmed == true)
        #expect(SdkMappings.encryption(encryptionInfo(senderID: "@bob:example.org", shield: .red(code: .unknownDevice))).senderConfirmed == false)
    }
    
    @Test
    func noEncryptionInfoIsCleartextWithNothingClaimed() {
        let encryption = SdkMappings.encryption(nil)
        
        #expect(!encryption.encrypted)
        #expect(encryption.senderDeviceId == nil)
        #expect(encryption.senderConfirmed == nil)
    }
    
    @Test
    func anUnknownEncryptionStateIsNeverAGuess() {
        #expect(SdkMappings.isEncrypted(.encrypted) == true)
        #expect(SdkMappings.isEncrypted(.notEncrypted) == false)
        #expect(SdkMappings.isEncrypted(.unknown) == nil)
    }
    
    // MARK: Members
    
    @Test
    func membersAreComparedWholeAndNeverDeliveredEmpty() {
        #expect(SdkMappings.shouldDeliver(["@a:x", "@b:x"], lastDelivered: nil))
        #expect(!SdkMappings.shouldDeliver(["@a:x", "@b:x"], lastDelivered: ["@a:x", "@b:x"]))
        // One leaving as another joins keeps the count.
        #expect(SdkMappings.shouldDeliver(["@a:x", "@c:x"], lastDelivered: ["@a:x", "@b:x"]))
        #expect(!SdkMappings.shouldDeliver([], lastDelivered: nil))
    }
    
    // MARK: To-device
    
    @Test
    func anEncryptedMessageComesFromItsAttestedSender() {
        let message = ToDeviceMessage(eventType: "io.element.call.encryption_keys",
                                      senderId: "@mallory:example.org",
                                      content: "{}",
                                      encryptionInfo: encryptionInfo(senderID: "@bob:example.org", shield: .none))
        
        let ffi = SdkMappings.toDeviceMessage(message)
        
        #expect(ffi.sender == "@bob:example.org")
        #expect(ffi.encryption.encrypted)
        #expect(ffi.encryption.senderDeviceId == "BOBDEVICE")
    }
    
    @Test
    func aCleartextMessageKeepsItsClaimedSender() {
        let message = ToDeviceMessage(eventType: "io.element.call.encryption_keys", senderId: "@bob:example.org", content: "{}", encryptionInfo: nil)
        
        let ffi = SdkMappings.toDeviceMessage(message)
        
        #expect(ffi.sender == "@bob:example.org")
        #expect(!ffi.encryption.encrypted)
    }
    
    @Test
    func everyRecipientGetsAVerdict() {
        let recipients = [FfiToDeviceRecipient(userId: "@bob:x", deviceId: "B1"),
                          FfiToDeviceRecipient(userId: "@bob:x", deviceId: "B2"),
                          FfiToDeviceRecipient(userId: "@carol:x", deviceId: "C1")]
        
        let deliveries = SdkMappings.deliveries(to: recipients, failures: ["@bob:x": ["B2"]])
        
        #expect(deliveries.map(\.deviceId) == ["B1", "B2", "C1"])
        #expect(deliveries.map { $0.error == nil } == [true, false, true])
    }
    
    // MARK: Transports and failures
    
    @Test
    func transportsAreRebuiltAsTheMSC4143Array() throws {
        let json = SdkMappings.transportsJSON([.liveKit(serviceUrl: "https://sfu.example.org"),
                                               .custom(transportType: "other", data: #"{"url":"https://other.example.org"}"#)])
        
        let array = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: String]])
        #expect(array == [["type": "livekit", "livekit_service_url": "https://sfu.example.org"],
                          ["type": "other", "url": "https://other.example.org"]])
        #expect(SdkMappings.transportsJSON([]) == "[]")
    }
    
    @Test
    func aHomeserverRefusalKeepsItsErrcode() {
        let error = ClientError.MatrixApi(kind: .forbidden, code: "M_FORBIDDEN", msg: "no", details: nil)
        
        guard case .Failed(let errcode, let status, let retryAfterMs, let permanent, _) = SdkMappings.backendError(error) else {
            Issue.record("Expected a failure")
            return
        }
        #expect(errcode == "M_FORBIDDEN")
        #expect(status == nil)
        #expect(retryAfterMs == nil)
        // The core classifies on the code; the mark is only for a final failure with none.
        #expect(!permanent)
    }
    
    @Test
    func aRateLimitCarriesTheServersDelay() {
        let error = ClientError.MatrixApi(kind: .limitExceeded(retryAfterMs: 7000), code: "M_LIMIT_EXCEEDED", msg: "slow down", details: nil)
        
        guard case .Failed(let errcode, _, let retryAfterMs, let permanent, _) = SdkMappings.backendError(error) else {
            Issue.record("Expected a failure")
            return
        }
        #expect(errcode == "M_LIMIT_EXCEEDED")
        #expect(retryAfterMs == 7000)
        #expect(!permanent)
    }
    
    @Test
    func aFailureWithNoCodeIsLeftForTheCoreToRetry() {
        struct Offline: Error { }
        
        guard case .Failed(let errcode, _, let retryAfterMs, let permanent, _) = SdkMappings.backendError(Offline()) else {
            Issue.record("Expected a failure")
            return
        }
        #expect(errcode == nil)
        #expect(retryAfterMs == nil)
        #expect(!permanent)
    }
    
    // MARK: Sticky events
    
    @Test
    func stickyUpdatesFoldIntoTheWholeSet() {
        var set = SdkStickyEventSet()
        let alice = stickyEvent(sender: "@alice:x", id: "$a1")
        let bob = stickyEvent(sender: "@bob:x", id: "$b1")
        
        #expect(set.apply(.reset(events: [])).isEmpty)
        #expect(set.apply(.reset(events: [alice, bob])).map(\.eventId) == ["$a1", "$b1"])
        
        let aliceAgain = stickyEvent(sender: "@alice:x", id: "$a2")
        #expect(set.apply(.changes(added: [], updated: [aliceAgain], removed: [])).map(\.eventId) == ["$a2", "$b1"])
        
        let removal = StickyEventRemoval(key: bob.key, reason: .expired)
        #expect(set.apply(.changes(added: [], updated: [], removed: [removal])).map(\.eventId) == ["$a2"])
    }
    
    @Test
    func aStickyEventIsReportedWithItsWireTypeAndContent() throws {
        let ffi = try #require(SdkMappings.event(stickyEvent(sender: "@alice:x", id: "$a1")))
        
        #expect(ffi.eventType == "org.matrix.msc4143.rtc.member")
        #expect(ffi.sender == "@alice:x")
        #expect(ffi.originServerTs == 42)
        #expect(ffi.contentJson == #"{"slot_id":"m.call#ROOM"}"#)
    }
    
    // MARK: - Fixtures
    
    private func encryptionInfo(senderID: String, shield: ShieldState) -> EventEncryptionInfo {
        EventEncryptionInfo(senderId: senderID,
                            senderDeviceId: "BOBDEVICE",
                            senderCurve25519Key: nil,
                            sessionId: nil,
                            shieldState: shield,
                            shieldStateStrict: shield)
    }
    
    private func stickyEvent(sender: String, id: String) -> StickyEvent {
        let json = #"{"type":"org.matrix.msc4143.rtc.member","origin_server_ts":42,"content":{"slot_id":"m.call#ROOM"}}"#
        return StickyEvent(key: StickyKey(sender: sender, eventType: "m.rtc.member", stickyKey: "\(sender)_DEV"),
                           eventId: id,
                           expiresAtMs: 0,
                           eventJson: json,
                           encryptionInfo: nil)
    }
}
