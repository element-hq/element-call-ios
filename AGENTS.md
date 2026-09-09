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
| `ElementCall` | nothing beyond the above | call lifecycle, Picture in Picture, **the ports** |
| `ElementCallUI` | `CompoundDesignTokens` | stage, tiles, controls, minimized bar |
| `ElementCallMatrix` | `MatrixRustSDK` | turnkey transport, widget-driver stopgap |

1. **`MatrixRustSDK` only in `ElementCallMatrix`.** Everywhere else, go through
   `ElementCallMatrixTransport`.
2. **Never `import Compound`, in any module.** Its colours live on one shared instance the host
   re-brands at runtime; a copy linked here would never see the override and a re-branded host would
   get a stock-coloured call screen. `CompoundDesignTokens` is fine, being static values.
3. **No host logger, settings or strings.** Use `ElementCallLogging`, `ElementCallOptions`,
   `ElementCallStrings`.
4. **Theme members are computed properties**, read at draw time. Never capture a colour.

SwiftLint enforces 1 and 2 at error severity. **If you need something from the host, add a port. Never
add a dependency.**

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
`Tests` run for the commit rather than testing anything itself.

### Re-recording snapshots

Delete the images and run the tests; the harness records whatever is missing.

```bash
rm -rf Tests/ElementCallTests/__Snapshots__/PreviewTests
# then the xcodebuild command above
```

**Not `RECORD_FAILURES=true` on the command line.** The harness reads it from its own environment,
and nothing on an `xcodebuild` command line gets there: not a build setting, not the `TEST_RUNNER_`
prefix, not the calling shell. It works when set in a scheme, which is why it works from inside
Xcode. On the command line it does nothing, silently, and you conclude your change had no visual
effect. `record-snapshots.yml` deletes for this reason.

`SnapshotEnvironment.renderDevices` is what each preview is rendered as, and the orientation is part
of it. Note the **iPad entry has always been landscape**: the snapshot library's bare `iPad10_2`
means `iPad10_2(.landscape)` while its bare `iPhoneX` means portrait. There is no iPad portrait
coverage.

---

## Releasing

A release is a **tag**, nothing more. Bare semver — `0.1.0`, `0.2.0-rc.1` — because that is what
SwiftPM matches a host's `exactVersion` against, and **the tag is the only place a version exists**:
there is no version constant, no `MARKETING_VERSION`, nothing to bump in a pull request.

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
- `MatrixRtc*` prefixed types name **protocol** concepts and keep that prefix. `ElementCall*` names our
  own API. Nothing may be called `MatrixRtc`, which is the bindings' own module.
- File headers come from `.swiftpm/xcode/xcshareddata/IDETemplateMacros.plist`. One copyright line.
- Previews for every main state, `PreviewProvider` not `#Preview`, conforming to `TestablePreview` so
  the snapshot cases generate.
- Accessibility identifiers on the call UI are **public API**: an external interop rig pins against
  them. A rename is a breaking change and its test will tell you so.

[Swift API Design Guidelines]: https://www.swift.org/documentation/api-design-guidelines/

## Comments

Comment the **why**, never the what. Where a decision is not obvious from the code, the reason sits
next to it, including the reasons that were got wrong first, because those are the ones that get
re-broken. Several comments here are longer than usual for that reason; do not shorten them into
restatements of the code.
