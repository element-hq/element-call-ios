# Changelog

Entries under a released version are **generated when the release is cut**, from the `pr-` label on
each merged pull request — see [RELEASING.md](RELEASING.md). There is nothing to add here for an
ordinary change; label the pull request and write a title that reads as a changelog line.

`Unreleased` is for the exception: something a host has to **act** on. A renamed accessibility
identifier, a port gaining a requirement, a new build setting. Write that here by hand, and the
release will carry it into its own section above the generated list, where a host bumping the
version will actually read it.

## Unreleased

**`ElementCallStrings` gained seventeen strings.** Every one is defaulted, so nothing breaks and no
conformance changes — but until you supply them the call screen shows English to every user, whatever
their language.

Seventeen user-facing strings were literals in the views: they never reached the port, so no host
could translate them and nothing failed to say so. They are now `joining`, `connecting`, `callEnded`,
`sharingYourScreen`, `shareScreen`, `stopSharingScreen`, `screenShareTileName`, `ok`, `returnToCall`,
`returnToCallAccessibilityLabel`, `mute`, `unmute`, `turnCameraOn`, `turnCameraOff`, `hangUp`,
`microphoneMuted` and `switchCamera`. Eight are VoiceOver labels rather than drawn text, and are the
only description of the call a VoiceOver user gets; `shareScreen` and `stopSharingScreen` are both.

The two developer toggles — tile stats, audio test tone — stay untranslated on purpose.

**Four accessibility identifiers now reach the UI.** `elementCall.stage`, `elementCall.roomName`,
`elementCall.callState` and `elementCall.tile.<memberID>` were published and asserted, but applied to
no view, so an interop rig querying them found nothing. Nothing is renamed and nothing is removed, so
no rig breaks — but a rig that worked around their absence can now stop.

## 0.1.0-rc.2 - 2026-09-11

**Every `MatrixRtc*` type is now `MatrixRTC*`** — `MatrixRTCCall`, `MatrixRTCSession`,
`MatrixRTCParticipant`, `MatrixRTCLogRecord` and the rest, 33 public types in all. Initialisms are
uniformly cased per the Swift API Design Guidelines. A find-and-replace of `MatrixRtc` followed by
an uppercase letter covers a host's whole migration.

Two things keep the old spelling because they are not ours: the bindings' module, so
`import MatrixRtc` is unchanged, and the bindings' own `MatrixRtcFFI` and `MatrixRtcFfiError`.

**`ElementCallLogging` now takes a record.** Replace

```swift
func log(_ level: ElementCallLogLevel, _ message: String) { … }
```

with

```swift
func log(_ record: ElementCallLogRecord) { … }
```

`ElementCallLogRecord` carries `level`, `message`, `file` and `line`, where `file` is the `#fileID`
of our own call site — so a host formatting logs with a position can stop passing a placeholder.
Call sites are unchanged: `log(_:_:)` still exists as a convenience that fills in the position.

**`MatrixRTCLogRecord` gained `file`, `line`, `timestampMs` and `thread`**, which the Rust core was
already providing and we were dropping. Nothing to change — the struct is only constructed inside
the package — but a host putting `target` in the file slot can now use `file`, and one stamping its
own receive time should prefer `timestampMs`, which is when the record was emitted.

**Minimizing an audio call now opens a Picture in Picture window** showing the avatar placeholder,
where it previously reported `pictureInPictureUnavailable`. A host that puts up its own minimized
bar will stop seeing that action for audio calls — the bar is still used when the window genuinely
cannot open: the host disabled it, the device does not support it, or a screen share is running.
Nothing to change unless the bar was relied on as the audio-call presentation.

`ElementCallOptions` gains `isAutomaticPictureInPictureForAudioCallsEnabled`, which governs whether
*backgrounding* the app during an audio call opens the window by itself. It has a default of
`false`, so existing conformances keep compiling and behaviour is unchanged; set it to `true` to opt
in. Minimizing on purpose is not affected by it.



### What's Changed

🙌 Improvements
* Carry file and line through both log ports by @BillCarsonFr in https://github.com/element-hq/element-call-ios/pull/9

🐛 Bugfixes
* Fixes the hang-up deadlock by @BillCarsonFr in https://github.com/element-hq/element-call-ios/pull/6
* Show the avatar until a stream actually delivers a frame by @BillCarsonFr in https://github.com/element-hq/element-call-ios/pull/11
* App running on macOS dies on call start with an uncatchable AVFAudio exception by @BillCarsonFr in https://github.com/element-hq/element-call-ios/pull/12
* Fix: Audio not starting on iOS app by @BillCarsonFr in https://github.com/element-hq/element-call-ios/pull/14

⚠️ API Changes
* Open Picture in Picture for audio calls, showing the avatar by @BillCarsonFr in https://github.com/element-hq/element-call-ios/pull/7
* Add an umbrella product so a host takes one dependency by @BillCarsonFr in https://github.com/element-hq/element-call-ios/pull/8
* Rename MatrixRtc types to MatrixRTC by @BillCarsonFr in https://github.com/element-hq/element-call-ios/pull/10

🧱 Build
* Release 0.1.0-rc.1 by @BillCarsonFr in https://github.com/element-hq/element-call-ios/pull/5
* Declare the render-block boxes Sendable by @BillCarsonFr in https://github.com/element-hq/element-call-ios/pull/13


**Full Changelog**: https://github.com/element-hq/element-call-ios/compare/0.1.0-rc.1...0.1.0-rc.2

## 0.1.0-rc.1 - 2026-09-09

Initial release: a native [MatrixRTC](https://github.com/matrix-org/matrix-spec-proposals/blob/main/proposals/4143-matrix-rtc.md)
implementation of Element Call for iOS. Audio and video calls the app renders itself, with no web view
involved.

The integration a web view cannot reach is the point of it. Calls are driven by the host's CallKit
provider, so they behave like calls — system call UI, the lock screen, and interruptions from other
apps. Audio routing follows the system's own choice of earpiece, headset or Bluetooth, and asks for
the speaker on a video call. Screen sharing captures through ReplayKit, and the call keeps rendering
in Picture in Picture when the app goes to the background.

**Four things a host has to do**, none of them optional:

- **Implement three ports:** `ElementCallSystemProviding` (your CallKit provider, plus audio-session
  and mute events coming back), `ElementCallRoomContext` and `ElementCallAvatarRendering`. The rest is
  turnkey — `ElementCallSDKTransport` covers the whole Matrix side, and theming, icons, strings,
  options and logging all have defaults.
- **Add `-ObjC`** to the app target's Other Linker Flags. Without it libwebrtc's Objective-C
  categories are dead-stripped from the static archive, so the app builds and then aborts at runtime
  on an unrecognised selector. Measured cost: 15.7 MiB on the linked binary.
- **Set `EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64`.** The media xcframework ships device and
  Apple Silicon simulator slices only, and a package cannot declare this for the projects that
  consume it.
- **Build `ElementCallStack` when the session is created, not when a call starts.** To-device
  delivery has no catch-up, so a stack that subscribes after its own membership has gone out can miss
  the keys sent in that window, and the first remote frames arrive black.

Consumed as a **source** dependency, pinned to an exact version — see the README for why.



### What's Changed

✨ Features
* Basic landscape layout support (not final) by @BillCarsonFr in https://github.com/element-hq/element-call-ios/pull/1

🧱 Build
* Release pipeline by @BillCarsonFr in https://github.com/element-hq/element-call-ios/pull/2
* Fixup dry run by @BillCarsonFr in https://github.com/element-hq/element-call-ios/pull/3
* Devx/ci relax by @BillCarsonFr in https://github.com/element-hq/element-call-ios/pull/4

### New Contributors
* @BillCarsonFr made their first contribution in https://github.com/element-hq/element-call-ios/pull/1

**Full Changelog**: https://github.com/element-hq/element-call-ios/commits/0.1.0-rc.1

