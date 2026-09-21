# Changelog

Entries under a released version are **generated when the release is cut**, from the `pr-` label on
each merged pull request — see [RELEASING.md](RELEASING.md). There is nothing to add here for an
ordinary change; label the pull request and write a title that reads as a changelog line.

`Unreleased` is for the exception: something a host has to **act** on. A renamed accessibility
identifier, a port gaining a requirement, a new build setting. Write that here by hand, and the
release will carry it into its own section above the generated list, where a host bumping the
version will actually read it.

## Unreleased

**`matrix-rust-rtc` moved to `element-hq`**, pinned at `0.3.0-rc.1` (was `BillCarsonFr` at
`0.2.0-rc.1`). No API change. If you declare `matrix-rust-rtc` yourself, switch to the new URL in the
same commit: both spellings share the identity `matrix-rust-rtc`, so declaring them together fails
resolution.

**Every port protocol now ends in `Protocol`.** Requested by the host: element-x-ios suffixes every
protocol it owns, so the package's ports were the only unsuffixed ones in files that otherwise carry
the suffix throughout. Seven renames, and nothing but the names changed:

| Was | Now |
| --- | --- |
| `ElementCallMatrixTransport` | `ElementCallMatrixTransportProtocol` |
| `ElementCallLogging` | `ElementCallLoggingProtocol` |
| `ElementCallTheme` | `ElementCallThemeProtocol` |
| `ElementCallIconRendering` | `ElementCallIconRenderingProtocol` |
| `ElementCallAvatarRendering` | `ElementCallAvatarRenderingProtocol` |
| `ElementCallSystemProviding` | `ElementCallSystemProvidingProtocol` |
| `ElementCallRoomContext` | `ElementCallRoomContextProtocol` |

A host updates its conformance declarations and any stored-property or parameter types spelled with
the old name. The compiler finds all of them.

**The concrete types keep their plain names** — `ElementCallTokenTheme`, `ElementCallTokenIcons`,
`ElementCallTokenAvatars`, `ElementCallSDKTransport` and the `ElementCallFake*` family are untouched,
as is `ElementCallStrings`, which is a struct rather than a port. So is every method on every port:
no requirement was added, removed or resignatured.

**The settings port is now a struct, and `areTileStatsAvailable` is now `isDeveloperModeEnabled`.**
`ElementCallOptionsProtocol` and `ElementCallDefaultOptions` are both gone, replaced by one value
type:

```swift
options: ElementCallOptions(isDeveloperModeEnabled: appSettings.developerOptionsEnabled)
```

Every member is defaulted, so a host states only what it wants to change — the defaults are Picture
in Picture on, `.stateEvents` compatibility, developer mode off, automatic Picture in Picture for
audio calls off. **A host that had a type conforming to the port can delete it**; pass a constructed
`ElementCallOptions` instead. Note this is the only port that lost its `Protocol` suffix in the same
release it gained one: a concrete type keeps a plain name, so the spelling is `ElementCallOptions`,
which is what it was called before either change.

It is read once, when the stack is built, rather than on every access. Nothing in the call ever
needed a fresher value — compatibility is read when a session joins, the Picture in Picture flags
when the window binds, developer mode when a toggle is tapped — so a host backing these with live
settings should know the values are captured. If that is a problem for you, say so and the stack can
gain a setter.

**Developer mode gates the stats overlay, and hides it.** The overflow menu now holds a
**Developer Options** submenu, and `isDeveloperModeEnabled` decides whether that submenu exists at
all — previously the "Tile stats" toggle was shown unconditionally and the tap was silently refused.
The toggle inside carries a checkmark, so reopening the menu says whether the overlay is on. Point
this at whatever reveals developer surface in your app, not at the flag that enables calls: the
overlay is raw RTP counters in 9pt monospace and is not meant for ordinary users.

**The audio test tone is gone.** The 440 Hz sine that could be injected into the microphone from the
overflow menu, and the generator behind it, are removed outright — it was an early bring-up aid and
had outlived its purpose. `MatrixRTCCall.setAudioTestToneEnabled(_:)`,
`ElementCallController.setAudioTestToneEnabled(_:)` and the `isAudioTestToneEnabled` view-state
property are all deleted; a host calling any of them will not compile.

**Screen sharing is now opt-in, through `isScreenSharingEnabled`, and defaults to off.** It needs
work on the host side before a share behaves, so a host asks for it when it is ready rather than
finding the feature half-wired. Deliberately *not* folded into developer mode: a host may want to
ship sharing to everyone while keeping diagnostics to itself, so the two are separate axes — wire
this to your developer flag today and change one line later.

With it off, the share button is absent from the control bar and `setScreenShareEnabled(true)` is
refused. **Receiving a share is unaffected**: a remote presenter still takes the spotlight, renders,
and is labelled, because a call with a Web peer sharing would otherwise look broken. Stopping a share
is never gated either, so one already in flight can always be ended.

The screen share entry is also **gone from the overflow menu**, where it duplicated the control bar
button exactly. The bar is where a user reaches for it; the menu is now diagnostics only.

**The call screen shows the package version**, as a disabled `version: <semver>` row at the foot of
the overflow menu, so a bug report can quote it — readable as `ElementCallVersion.current` if a host
wants it elsewhere. It is stamped by the release, so it is exact for any host that resolves a tag.

## 0.1.0-rc.5 - 2026-09-16

**`import ElementCallAll` is now `import ElementCall`, and the product is `ElementCall`.** The
umbrella module — the one that does nothing but re-export the four layers — has taken the bare name,
because that is the name an integrating app reaches for and there was no answer to "why `All`?" beyond
"the name was taken". Two edits in a host:

- every `import ElementCallAll` becomes `import ElementCall`;
- `product: ElementCallAll` becomes `product: ElementCall` (or
  `.product(name: "ElementCall", package: "element-call-ios")`).

`ElementCallAll` is gone rather than deprecated, so both show up as errors: an unresolved product at
resolution and an unknown module at build.

**The module formerly named `ElementCall` is now `ElementCallHost`**: the call lifecycle, Picture in
Picture, and the ports. A host importing the umbrella never names it and has nothing to do. A host
that depended on the `ElementCall` *product* to get only that layer must switch to `ElementCallHost`
— the `ElementCall` product now vends everything, so such a host keeps compiling but links the view
and transport layers it was deliberately avoiding.

Nothing else moved: the four boundaries, every public type name, and every accessibility identifier
are unchanged.



### What's Changed

⚠️ API Changes
* Packaging: Rename ElementCallAll import to ElementCall  by @BillCarsonFr in https://github.com/element-hq/element-call-ios/pull/27


**Full Changelog**: https://github.com/element-hq/element-call-ios/compare/0.1.0-rc.4...0.1.0-rc.5

## 0.1.0-rc.4 - 2026-09-14

**This package no longer uses Git LFS**, and this is the first version a host can resolve without
`git-lfs` installed. Every earlier tag fails on Xcode Cloud, which has no `git-lfs` on the image:

> Couldn't check out revision '…' — git-lfs command not found

Nothing to act on beyond bumping to this version. `git-lfs` is no longer needed to work on the
package either, and can come off a development machine once no older tag is in use — but leave the
LFS objects on the remote, because tags up to and including 0.1.0-rc.3 still point at pointer blobs
and cannot be checked out without them.

The snapshot reference images are ordinary blobs now. They were the only thing in LFS, and SwiftPM
cannot cope with it at all: it clones with `--mirror`, which never fetches LFS objects, then checks
out into a separate worktree where the smudge filter fires and fails
([swift-package-manager#5351](https://github.com/swiftlang/swift-package-manager/issues/5351), open
since 2018). History is untouched; only the filter is gone.



### What's Changed

✨ Features
* Double-tap a tile to fill the screen with it by @BillCarsonFr in https://github.com/element-hq/element-call-ios/pull/24

🧱 Build
* Store the snapshot references as ordinary blobs, not Git LFS by @BillCarsonFr in https://github.com/element-hq/element-call-ios/pull/25


**Full Changelog**: https://github.com/element-hq/element-call-ios/compare/0.1.0-rc.3...0.1.0-rc.4

## 0.1.0-rc.3 - 2026-09-11

**`compound-design-tokens` is now a range starting at 11.0.0**, where it was pinned exactly at
10.2.4. Nothing in the public surface changes, but a host whose Compound still resolves tokens below
11.0.0 will no longer resolve against this package at all — update Compound first.

The exact pin was the problem. Two `exact` requirements on one package have no solution, so once
`compound-ios` moved to tokens 11.0.0 the integration failed at resolution, before anything compiled.
The range means a host bumping Compound ahead of a release here no longer has to wait for one.



### What's Changed

🧱 Build
* Import Compound as a range to avoid resolution problems on exi by @BillCarsonFr in https://github.com/element-hq/element-call-ios/pull/21


**Full Changelog**: https://github.com/element-hq/element-call-ios/compare/0.1.0-rc.2...0.1.0-rc.3

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

