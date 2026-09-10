# Changelog

Entries under a released version are **generated when the release is cut**, from the `pr-` label on
each merged pull request — see [RELEASING.md](RELEASING.md). There is nothing to add here for an
ordinary change; label the pull request and write a title that reads as a changelog line.

`Unreleased` is for the exception: something a host has to **act** on. A renamed accessibility
identifier, a port gaining a requirement, a new build setting. Write that here by hand, and the
release will carry it into its own section above the generated list, where a host bumping the
version will actually read it.

## Unreleased

**Minimizing an audio call now opens a Picture in Picture window** showing the avatar placeholder,
where it previously reported `pictureInPictureUnavailable`. A host that puts up its own minimized
bar will stop seeing that action for audio calls — the bar is still used when the window genuinely
cannot open: the host disabled it, the device does not support it, or a screen share is running.
Nothing to change unless the bar was relied on as the audio-call presentation.

`ElementCallOptions` gains `isAutomaticPictureInPictureForAudioCallsEnabled`, which governs whether
*backgrounding* the app during an audio call opens the window by itself. It has a default of
`false`, so existing conformances keep compiling and behaviour is unchanged; set it to `true` to opt
in. Minimizing on purpose is not affected by it.

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

