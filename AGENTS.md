# AGENTS.md — element-call-ios

> A native MatrixRTC call implementation for iOS, consumed by [element-x-ios] as a SwiftPM package.
> Written with substantial AI assistance, reviewed by a person before landing.
>
> **Keep this file current.** If a change makes a fact here wrong, fix the fact in the same pull
> request. If a change is not described here, leave the file alone.

[element-x-ios]: https://github.com/element-hq/element-x-ios

Read [CONTRIBUTING.md](CONTRIBUTING.md) too. This file is what an agent needs that a human already
knows, and what tends to go wrong.

---

## The four boundaries. Do not cross these.

| Module | May import | Contents |
| --- | --- | --- |
| `ElementCallKit` | the RTC core only | media, session, capture, render, keys |
| `ElementCallHost` | nothing beyond the above | call lifecycle, Picture in Picture, **the ports** |
| `ElementCallUI` | `CompoundDesignTokens` | stage, tiles, controls, minimized bar |
| `ElementCallMatrix` | `MatrixRustSDK` | turnkey transport, widget-driver stopgap |

1. **`MatrixRustSDK` only in `ElementCallMatrix`.** Everywhere else, go through
   `ElementCallMatrixTransportProtocol`.
2. **Never `import Compound`, in any module.** Its colours live on one shared instance the host
   re-brands at runtime; a copy linked here would never see the override and a re-branded host would
   get a stock-coloured call screen. `CompoundDesignTokens` is fine, being static values.
3. **No host logger, settings or strings.** Use `ElementCallLoggingProtocol`, `ElementCallOptions`,
   `ElementCallStrings`.
4. **Theme members are computed properties**, read at draw time. Never capture a colour.

SwiftLint enforces 1 and 2 at error severity. **If you need something from the host, add a port. Never
add a dependency.**

A fifth target, **`ElementCall`**, exists only to `@_exported import` the four above so a host takes
one dependency and writes one import. It contains no code and must never contain any: it is a product
convenience, not a fifth layer, and putting anything in it would put that thing outside every boundary
in the table. Note the lint rules read comments too — they have no `match_kinds` — so naming the Matrix
SDK in a comment anywhere outside `ElementCallMatrix` fails the build, and `Sources/ElementCall/` is
not on the excluded path.

**The bare name belongs to the umbrella, not to a layer.** It used to be the other way round — the
lifecycle-and-ports module was `ElementCall` and the umbrella was `ElementCallAll` — and hosts kept
asking why they had to import a name with no meaning. Do not undo that: `import ElementCall` is the
one line an integrating app writes. `ElementCallHost` is *not* the host's own module; it is the module
holding the ports a host implements, and `ElementCallCore` was rejected for it because `ElementCallKit`
sits below rather than above.

---

## Building and testing

```bash
# Once per machine: snapshots only compare on the pinned device, and there may be none yet.
xcrun simctl create "ElementCall Snapshots" "iPhone SE (3rd generation)" \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5

cd Tools/Sourcery && sourcery --config PreviewTestsConfig.yml && cd ../..

xcodebuild test -scheme ElementCall-Package \
  -destination "id=$SIMULATOR_UDID" \
  -testLanguage en -testRegion GB \
  OTHER_LDFLAGS='$(inherited) -ObjC'
```

Three flags are not optional, and each fails in a way that does not name its own cause:

- **`-ObjC`.** Library targets never link, so `swift build` passes without it and proves nothing. The
  test bundle links, then dies on launch with an unrecognised selector on `UIDevice`.
- **A concrete simulator by id.** A generic destination also builds an architecture the media
  xcframework has no slice for, and the link fails on missing symbols.
- **`-testLanguage en -testRegion GB`.** Snapshot names carry the locale. The harness asserts this and
  tells you what to pass.

`swift build` alone will fail: the package is iOS-only. Always go through `xcodebuild`.

The pinned device and OS live in `Tests/ElementCallTests/Support/SnapshotEnvironment.swift`. The
harness reads them and fails loudly when the simulator does not match. **The workflows do not read
them**, despite the comment in `tests.yml` saying so: `XCODE_APP`, `SIMULATOR_NAME` and
`SIMULATOR_RUNTIME` are duplicated literals in both workflow files, so changing the pinned device is
three edits, not one. `release.yml` is deliberately not a fourth: it runs on Linux and gates on the
`Tests` run for the commit rather than testing anything itself, and the example harness below is not
a fourth either: it is a step in the same `Tests` job and reuses the simulator that job creates.

### The example harness and the UI tests

`Example/` is a sample app over the port fakes, and the UI tests that drive it. It exists for one
reason: **a gesture is the one thing the package's own tests cannot reach.** Everything else runs
in-process, but a double tap that is declared correctly and never arrives, because something above
the tile claimed the touch first, looks identical to a working one from inside. Only a real touch
tells them apart, and only XCUITest can send one, which needs an application and so a project.

```bash
brew install xcodegen                       # once per machine
cd Example && xcodegen generate && cd ..
xcodebuild test -project Example/ElementCallExample.xcodeproj \
  -scheme ElementCallExample \
  -destination "id=$SIMULATOR_UDID"
```

- **The project is generated, not committed.** `Example/project.yml` is what gets reviewed and
  `Example/*.xcodeproj` is ignored, for the same reason `GeneratedPreviewTests.swift` is regenerated
  in CI: nobody reads a pbxproj and everybody conflicts on one. The app target needs the same
  `-ObjC` the package's test bundle does, for the same reason.
- **No server, no camera, no call.** The app builds its screen from `ElementCallPreviewFixtures`
  through `ElementCallHarnessScreen`, which is the seam the previews have always used, made public.
  `ElementCallController.fake(...)` cannot serve here: it never joins, so it produces no tiles and
  the screen would be a spinner. Which arrangement the app opens on comes from `-arrangement` in the
  launch arguments, so a test starts where it means to.
- **Put a test here only if it needs a real touch.** Arrangement belongs in
  `ElementCallStageLayoutTests`, appearance in the snapshots, and geometry in a unit test: a UI test
  is twenty seconds against their twenty milliseconds. What earns its place is gesture arbitration —
  the strip's paging drag against a tile's pan, and the `Button` inside a tile.
- **The `video` arrangement draws real frames**, from `MatrixRTCTestPattern`: colour bars with a
  heavy border, because the questions are geometric. A border running off the edges is a crop, a
  border with black beside it is a letterbox, and a border that changes thickness partway through a
  move is the picture being stretched rather than redrawn. Some members are portrait sources and
  some landscape, so both answers are on the stage at once. It reaches the tiles through
  `ElementCallPreviewVideo`, an environment value consulted only where there is no call — nil in
  every shipping build.
  
  Keep it honest, or it is worse than nothing. Two things had to be fixed before it was: the
  pattern is generated a row at a time rather than a pixel at a time, and one frame per size is
  shared by every tile that wants it; and its timer runs on `.common`, because on the default mode
  it stops while the run loop tracks a touch, which starved the tiles of frames for exactly the
  length of a gesture and made the harness stutter far worse than the app it stands in for.
- **Exact geometry is still pinned by `VideoPresentationTests`**, which asserts on the vertex
  transform. The harness is for looking; a test that compares pictures would only be approximate
  where that one is exact.
- **`DeviceScreenshotTests` is how you see a device.** Some questions have no answer in the
  simulator at all — Picture in Picture is the standing one, since
  `AVPictureInPictureController.isPictureInPictureSupported()` is false on every simulator — and
  there is no tool that photographs a device: `simctl` does not reach one and `devicectl` has no
  screenshot command. A UI test runs *on* the device, so it takes the picture itself and attaches it
  to the result bundle, which `xcresulttool` then hands back. It captures the whole screen, so
  system windows are in it; a Picture in Picture window belongs to another process and still
  appears.

  ```bash
  TEST_RUNNER_ARRANGEMENT=video xcodebuild test \
    -project Example/ElementCallExample.xcodeproj -scheme ElementCallExample \
    -destination "id=$DEVICE_UDID" -only-testing:ElementCallExampleUITests/DeviceScreenshotTests \
    -resultBundlePath /tmp/res.xcresult
  xcrun xcresulttool export attachments --path /tmp/res.xcresult --output-path /tmp/shots
  ```

  Two things it is easy to lose an afternoon to. `XCTAttachment.lifetime` must be `.keepAlways`, or
  a *passing* test throws its attachments away, which is exactly the run you wanted the picture
  from. And the variable must be `TEST_RUNNER_`-prefixed: a bare `ARRANGEMENT=…` on the `xcodebuild`
  line never reaches the runner, silently — the same trap `RECORD_FAILURES` sets below, for the same
  reason.

#### Running it by hand, and watching a move frame by frame

Open `Example/ElementCallExample.xcodeproj` and run it, or from the command line:

```bash
xcrun simctl install "$SIMULATOR_UDID" \
  "$(find ~/Library/Developer/Xcode/DerivedData -name ElementCallExample.app -path '*Debug-iphonesimulator*' | head -1)"
xcrun simctl launch "$SIMULATOR_UDID" io.element.call.example.ElementCallExample -arrangement pagedStrip
```

**This is the answer to "do I have to join a real call to see it?"** — you do not, for anything the
layout does. Which is most of what goes wrong: the arrangements, the chrome, and every animation
between them are the same code in the harness as in a host.

An animation is worth *seeing*, and the snapshots cannot: they are end states. Record the simulator
across a run and make a contact sheet of the moment:

```bash
xcrun simctl io "$SIMULATOR_UDID" recordVideo -f /tmp/run.mp4 &
xcodebuild test-without-building -project Example/ElementCallExample.xcodeproj \
  -scheme ElementCallExample -destination "id=$SIMULATOR_UDID" \
  -only-testing:ElementCallExampleUITests/TileFullscreenUITests/testDoubleTappingAgainComesBackToTheStage
kill -INT %1
ffmpeg -ss 9.4 -t 1.2 -i /tmp/run.mp4 -vf "fps=25,scale=260:-1,tile=6x5" -frames:v 1 /tmp/move.png
```

`build-for-testing` first, then `test-without-building`, or the recording is mostly a build. This is
how the z-order of the growing tile was checked: a tile going full screen has to be **above** the
ones it replaces, because they are leaving and a leaving view keeps its z position for as long as
its transition runs. At the strip's own zero the spotlight faded out on top of it all the way up.
`ElementCallStageLayout.fullscreenZIndex` and the test that pins it are what stop that returning.

### Re-recording snapshots

Touch the marker file and run the tests; the harness overwrites whatever no longer matches.

```bash
touch Tests/ElementCallTests/.record-snapshots
# then the xcodebuild command above, then remove the marker
```

**Prefer that to deleting the directory.** Deleting also works — the harness records whatever is
missing — but it re-records all 87 images rather than the few that changed, and PNG re-encoding is
not byte-identical across Xcode versions. The references are ordinary blobs rather than Git LFS
pointers (see CONTRIBUTING.md for why they must stay that way), so a wholesale re-record puts 5.5 MB
of new blobs in the repository permanently and buries the images a reviewer has to look at.

**Not `RECORD_FAILURES=true` on the command line.** The harness reads it from its own environment,
and nothing on an `xcodebuild` command line gets there: not a build setting, not the `TEST_RUNNER_`
prefix, not the calling shell. It works when set in a scheme, which is why it works from inside
Xcode. On the command line it does nothing, silently, and you conclude your change had no visual
effect. The marker file is what `record-snapshots.yml` uses, for this reason.

`SnapshotEnvironment.renderDevices` is what each preview is rendered as, and the orientation is part
of it. Note the **iPad entry has always been landscape**: the snapshot library's bare `iPad10_2`
means `iPad10_2(.landscape)` while its bare `iPhoneX` means portrait. There is no iPad portrait
coverage.

---

## Releasing

A release is a **tag**, nothing more. Bare semver — `0.1.0`, `0.2.0-rc.1` — because that is what
SwiftPM matches a host's `exactVersion` against, and **nothing is bumped in a pull request**: there
is no `MARKETING_VERSION` and nobody edits a version by hand.

There is one version constant, `ElementCallVersion.current`, which the call screen shows so a bug
report can quote it. **`scripts/release.sh` stamps it**, in the same step that closes the
`## Unreleased` heading, so it lands inside the commit the release tags and a host resolving that tag
gets a tree that describes itself. The script fails the release if the rewrite does not take, and
`release.yml` names the file in its `git add` — the commit is path-explicit, not `git add -A`, so a
new generated file has to be named there or it never reaches the tag. On `main` between releases the
constant reads as the previous release, which is only ever visible in a build made from this
repository rather than from a tag.

The pipeline is `.github/workflows/release.yml` plus `scripts/release.sh`, which holds all of the
validation and never touches the remote so it can be rehearsed locally. Release notes come from the
`pr-` labels via `.github/release.yml`, and land in `CHANGES.md` inside the tagged commit.

Three things about it are easy to break by tidying:

- **Releases are cut from a `release/<version>` branch, never from `main`.** That is what keeps the
  whole pipeline on the built-in `GITHUB_TOKEN`: it pushes only to that unprotected branch and a new
  tag, and the changelog reaches `main` through an ordinary pull request. Pointing it at `main` would
  need a token that can bypass branch protection.
- **The newest release tag is read with `git tag --merged HEAD` and `versionsort.suffix=-`.** The
  first scopes it to the branch's own line of history, so a fix to an older line is neither refused
  for going backwards nor given notes generated against a release it does not contain. The second
  stops git ranking `0.2.0-rc.1` above `0.2.0`, which would make `previous_tag_name` the rc.
- **`CHANGES.md` keeps a `## Unreleased` heading**, which the release renames to `## <version> -
  <date>` before opening a fresh one. Hand-written entries there are carried into the released
  section above the generated list. Do not delete the heading; the release refuses without it.

**This package ships source, not a binary**, and that is a decision with reasons rather than a
limitation — `matrix-rust-rtc` ships an xcframework because it contains Rust, not because that is how
Swift packages are released. Do not add a `binaryTarget` or a build-and-attach step to the release
workflow. [RELEASING.md](RELEASING.md) has the reasoning and the trigger that would justify revisiting
it.

## What is temporary

`Sources/ElementCallMatrix/Widget/` drives the SDK's widget driver in process as a stand-in for
bindings the released SDK lacks: delayed events, a room-state feed, to-device messaging. It is
**scheduled for deletion**, and `WidgetMatrixBridge.swift`'s header lists the exact bindings that
retire it and the removal steps. Do not build new features on it, and do not let it leak past
`ElementCallSDKTransport`.

`openBridge` is the **only** place a bridge is created, deliberately. An earlier version had two
creation paths and only one wired up the to-device pump, so media keys reached nobody and every remote
tile went black. The bridge and its pump are one value now so the type system forbids that. Keep it
that way.

---

## Conventions

- Swift 6.2, main-actor isolation by default in every module, so do not add redundant `@MainActor`.
- **`@unchecked Sendable` is confined to `ElementCallKit/Media`**, where it appears about a dozen times
  and is deliberate: audio render callbacks, capture delegates and Metal draws run on threads the
  compiler cannot reason about, and actor hops there cost frames. Those types synchronise by hand.
  **Anywhere else it is banned**, including the other three modules. If concurrency fights you outside
  the media layer, the design is wrong.
- Never store a function value directly in a generic `Mutex`. Each `withLock` reabstracts and writes
  back one more thunk, so a per-frame callback overflows the stack after a few minutes. Box it in a
  struct.
- **Orientation is the shape of the space, never the size class.** `ElementCallStageLayout.Metrics`
  and `ElementCallView` both decide on `width > height` and must keep agreeing. An iPad in landscape
  has a *regular* vertical size class, so a size-class branch would leave its controls at the bottom
  while the stage laid its tiles out for a side rail.
- Follow the [Swift API Design Guidelines]: `ID` not `Id`, `URL` not `Url`.
- **Every port protocol ends in `Protocol`**, and this is a deliberate exception to those
  guidelines, which would have `ElementCallSystemProvidingProtocol` be `ElementCallSystemProviding`
  and `ElementCallRoomContextProtocol` be `ElementCallRoomContext`. The host asked for it: element-x-ios
  suffixes every protocol it owns, its Sourcery mock template derives a mock name by stripping
  `Protocol`, and the package's ports were the only unsuffixed protocols in files that otherwise
  carry the suffix throughout. Uniform rather than selective, so the rule can be stated in one line
  — including on the four that read as capabilities and so double up a little. **Do not "correct"
  these back**; the concrete types that implement them (`ElementCallTokenTheme`,
  `ElementCallSDKTransport`, the `ElementCallFake*` family) keep plain names, which is what makes the
  suffix carry information. So does a port that is a plain value rather than something a host
  implements — `ElementCallOptions` and `ElementCallStrings` are structs with every member defaulted,
  and the suffix would be a lie on them.
- `MatrixRTC*` prefixed types name **protocol** concepts and keep that prefix. `ElementCall*` names our
  own API. Note the casing: the initialism is uniform, per the API design guidelines below. The
  bindings' own module is `MatrixRtc`, spelled exactly that way, and `import MatrixRtc` plus the
  `MatrixRtc.`-qualified uses in `VideoFrameSlot.swift` are references to *it* rather than to us —
  a bulk re-casing must leave those alone, along with the bindings' `MatrixRtcFFI` and
  `MatrixRtcFfiError`. Nothing of ours may be called `MatrixRtc`.
- File headers come from `.swiftpm/xcode/xcshareddata/IDETemplateMacros.plist`. One copyright line.
- Previews for every main state, `PreviewProvider` not `#Preview`, conforming to `TestablePreview` so
  the snapshot cases generate.
- Accessibility identifiers on the call UI are **public API**: an external interop rig pins against
  them, and the UI tests in `Example/` now do too. A rename is a breaking change and its test will
  tell you so. Note that `control(for:)` derives a control's identifier from its *icon*, so a button
  borrowing another's glyph must set its own identifier explicitly or the two collide — which
  `AccessibilityIdentifierTests.distinctness` does not catch, since it only walks icons.

[Swift API Design Guidelines]: https://www.swift.org/documentation/api-design-guidelines/

## Comments

Comment the **why**, never the what. Where a decision is not obvious from the code, the reason sits
next to it, including the reasons that were got wrong first, because those are the ones that get
re-broken. Several comments here are longer than usual for that reason; do not shorten them into
restatements of the code.
