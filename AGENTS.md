# AGENTS.md — element-call-ios

> Native MatrixRTC call implementation for iOS. Consumed by [element-x-ios] as SwiftPM package.
> Written with substantial AI assistance, reviewed by person before landing.
>
> **Keep current.** Change break fact here — path, command, convention, structure? Fix that fact,
> same PR. Change not described here? Leave file alone.
>
> **Voice:** terse, matching [element-x-ios AGENTS.md][exi-agents], so agent moving between two repos
> reads one register. Terse ≠ thin: reasons stay, prose compresses. Exception is Comments section
> below, which diverges on purpose and says so.

[element-x-ios]: https://github.com/element-hq/element-x-ios
[exi-agents]: https://github.com/element-hq/element-x-ios/blob/develop/AGENTS.md

Read [CONTRIBUTING.md](CONTRIBUTING.md) too. This file is what agent needs that human already knows,
and what tends to go wrong.

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
   re-brands at runtime; copy linked here would never see the override and re-branded host would get
   stock-coloured call screen. `CompoundDesignTokens` fine, being static values.
3. **No host logger, settings or strings.** Use `ElementCallLogging`, `ElementCallOptions`,
   `ElementCallStrings`.
4. **Theme members are computed properties**, read at draw time. Never capture a colour.

SwiftLint enforces 1 and 2 at error severity. **Need something from host? Add a port. Never add a
dependency.**

Fifth target `ElementCallAll` exists only to `@_exported import` the four above, so host takes one
dependency and writes one import. Contains no code, must never contain any: product convenience, not
fifth layer, and anything in it sits outside every boundary in the table.

**Lint custom rules read comments too** — no `match_kinds` on them — so naming the Matrix SDK in a
comment outside `ElementCallMatrix` fails the build. Same trap on `@unchecked Sendable` outside
`ElementCallKit/Media`.

---

## Layout

```
Sources/
├── ElementCallKit/      # the RTC core is the only thing it knows
│   ├── API/             # ElementCallMatrixTransport, MatrixRTCModels
│   ├── Media/           # capture, render, packers, audio engine — the @unchecked Sendable island
│   └── Session/         # MatrixRTCCall/Service/Session, key mapping, feeders, MatrixRTCLog
├── ElementCall/         # call lifecycle, Picture in Picture
│   └── Ports/           # every protocol a host implements, plus the Fakes and token defaults
├── ElementCallUI/       # ElementCallScreenViewModel + models + accessibility identifiers
│   ├── View/            # stage, tiles, controls, minimized bar
│   └── Previews/        # TestablePreview, fixtures, preview factory — ships in the product
├── ElementCallMatrix/   # ElementCallSDKTransport
│   └── Widget/          # the stopgap, see "What is temporary"
└── ElementCallAll/      # re-exports, nothing else

Tests/ElementCallTests/  # one target, everything
├── Support/             # SnapshotEnvironment (the pinned device), RenderCallback
├── __Snapshots__/       # reference PNGs, Git LFS
└── GeneratedPreviewTests.swift   # Sourcery output, do not edit
```

## Tools

| Tool | Command | When |
| --- | --- | --- |
| SwiftLint | `swiftlint` | CI, on every PR |
| SwiftFormat | `swiftformat .` (`--lint` to check) | CI, on every PR |
| Sourcery | `cd Tools/Sourcery && sourcery --config PreviewTestsConfig.yml` | by hand; CI fails on drift |
| Git LFS | `git lfs install --local` | once per checkout, or snapshots arrive as text pointers |

Setup: `brew install swiftformat swiftlint sourcery git-lfs`.

**No XcodeGen, no `project.yml`, no Tools CLI, no `swift run tools`, no git hooks** beyond the four
Git LFS installs. Package, not app. Do not go looking for element-x-ios's build system here.

Sourcery does previews only. **No `AutoMockable`, no generated mocks** — see Testing.

## Key files

| File | Purpose |
| --- | --- |
| `Package.swift` | targets, products, the deliberately wide SDK range |
| `.swiftlint.yml` | style plus the boundary rules, custom rules at the bottom |
| `.swiftformat` | formatting; `docComments` disabled so `//` stays `//` |
| `Tests/…/Support/SnapshotEnvironment.swift` | pinned device, OS, locale, render devices |
| `Tests/…/PreviewTests.swift` | snapshot harness, record marker, environment assertions |
| `.github/release.yml` | the `pr-` labels that become the changelog |
| `codecov.yml` | coverage, and what is excluded from it |
| `renovate.json` | dependency bumps, labelled `pr-misc` |
| `.swiftpm/xcode/xcshareddata/IDETemplateMacros.plist` | the file header |

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

Three flags not optional. Each fails in way that does not name its own cause:

- **`-ObjC`.** Library targets never link, so `swift build` passes without it and proves nothing.
  Test bundle links, then dies on launch with unrecognised selector on `UIDevice`.
- **Concrete simulator by id.** Generic destination also builds architecture the media xcframework
  has no slice for, and link fails on missing symbols.
- **`-testLanguage en -testRegion GB`.** Snapshot names carry locale. Harness asserts this and tells
  you what to pass.

`swift build` alone fails: package is iOS-only. Always `xcodebuild`.

Pinned device and OS live in `Tests/ElementCallTests/Support/SnapshotEnvironment.swift`. Harness reads
them, fails loudly on mismatch. **Workflows do not read them**, despite the comment in `tests.yml`
saying so: `XCODE_APP`, `SIMULATOR_NAME`, `SIMULATOR_RUNTIME` are duplicated literals in both workflow
files, so changing the pinned device is three edits, not one. `release.yml` deliberately not a fourth:
runs on Linux, gates on the `Tests` run for the commit rather than testing anything itself.

### Re-recording snapshots

Marker file. Harness records whatever fails, then asserts against it next run.

```bash
touch Tests/ElementCallTests/.record-snapshots
# then the xcodebuild command above
rm Tests/ElementCallTests/.record-snapshots
```

`record-snapshots.yml` does the same on CI, triggered by the `record-snapshots` label.

**Do not `rm -rf __Snapshots__` to force a re-record.** Only-what-failed is the point: PNG encoding is
not guaranteed byte-for-byte across Xcode versions, so wholesale re-record rewrites all of them in Git
LFS and buries the one image that actually changed. Check `git lfs status` after recording — new and
changed images only.

**Not `RECORD_FAILURES=true` on the command line.** Harness reads it from its own environment, and
nothing on an `xcodebuild` command line gets there: not a build setting, not the `TEST_RUNNER_` prefix,
not the calling shell. Works when set in a scheme, which is why it works from inside Xcode. On the
command line it does nothing, silently, and you conclude your change had no visual effect.

`SnapshotEnvironment.renderDevices` is what each preview renders as, orientation included. **iPad entry
has always been landscape**: the snapshot library's bare `iPad10_2` means `iPad10_2(.landscape)` while
its bare `iPhoneX` means portrait. No iPad portrait coverage.

---

## Architecture

One screen, no Coordinators. MVVM, hand-rolled, closely parallel to element-x-ios minus the Coordinator
layer. Do not port `StateStoreViewModelV2`, `FlowCoordinator`, `AppRoute` or `NavigationStackCoordinator`
across — nothing here needs them.

| Piece | Where | What |
| --- | --- | --- |
| `ElementCallScreenViewState` | `ElementCallScreenModels.swift` | `nonisolated struct … Sendable`, plain values |
| `ElementCallScreenViewAction` | same | what the view sends |
| `ElementCallScreenContext` | `ElementCallScreenViewModel.swift` | `@Observable final class`. Our `StateStoreViewModelV2` |
| `ElementCallScreenViewModel` | same | owns `ElementCallController`, `observe()` / `refresh()` / `process(viewAction:)` |

```
View ──send(viewAction:)──► Context ──► ViewModel ──► ElementCallController ──► ElementCallKit
     ◄──context.viewState───                                                          │
     ◄──$context.alertInfo──►                                                    the RTC core
```

`viewState` is `fileprivate(set)`: views read, only the view model writes. `context.preview(state:)` is
what every preview builds against — no host, no controller, no call.

`ElementCallController` is internal to construct. `ElementCallStack.init` is the composition root and
the only place one is made.

### Errors

One mechanism. `controller.errorMessage` → drained in `refresh()` → `context.alertInfo` →
`ElementCallAlert` → the single `.alert` in `ElementCallView`. Shown once, then cleared.

**No toasts, no user indicators, no HUD.** Host's are not reachable from here. Do not invent one.
Connection states are not errors — they render as status text ("Joining…", "Connecting…").

### Dependency injection

Ports *are* the DI story. Constructor injection throughout, host passes conformances to
`ElementCallStack.init`, stack hands them down.

**Zero singletons of ours.** No `static let shared`, no service locator, no global mutable state. Only
`.shared` in the tree are Apple's own (`UIApplication`, `RPScreenRecorder`). Keep it that way.

One deliberate global: `MatrixRTCLog`. See below.

---

## Styling

Never `import Compound`. Read the style out of the environment instead:

```swift
@Environment(\.elementCallStyle) private var style   // ElementCallStyleEnvironment.swift

style.icons.icon(.endCall)
    .foregroundStyle(style.theme.iconPrimary)
    .background(style.theme.bgCriticalPrimary, in: Circle())
```

`ElementCallStyle` rides `EnvironmentValues.elementCallStyle` (`@Entry`, defaults `.stock`) rather than
initialisers, because almost every view needs some of it — and that default is why previews and
snapshots work with no host. Sub-ports: `style.theme`, `style.icons`, `style.avatars`, `style.strings`.
Token-backed defaults in `Sources/ElementCall/Ports/ElementCallTokenStyle.swift`.

Colours and fonts are **computed properties, read at draw time**. Never capture one into a `let`.

## Strings

**Every string a user can read goes in `ElementCallStrings`.** Host supplies translations; English
defaults ship so a host with none still gets readable text.

Nothing catches a literal left in a view. No `.strings` file, so no missing-key failure; no Localazy,
no SwiftGen, no `L10n`, no translation pass to notice. Seventeen literals shipped English to every language for
exactly that reason. Do not add a bundle — translation is the host's job, it is one of the ports.

Developer-only affordances (the tile-stats and test-tone toggles) stay literal on purpose, and say so
in a comment where they sit.

## Logging & PII

Two loggers, split by boundary. **Not an accident, do not "unify" them.**

| Logger | Where | Shape |
| --- | --- | --- |
| `ElementCallLogging` | `ElementCall`, `ElementCallUI`, `ElementCallMatrix` | injected port, `log(.info, "…")`, call site attributes itself via `#fileID`/`#line` |
| `MatrixRTCLog` | `ElementCallKit` only | static enum, forwards to the Rust core's own subscriber |

`MatrixRTCLog` is static because the port lives in `ElementCall`, which depends on `ElementCallKit`.
Injecting it would invert the boundary. That is the obvious cleanup someone will attempt; it does not
work.

`print`, `println`, `os_log` banned at error severity.

Levels: default `.info`. Recoverable problem `.warning`. Unexpected failure `.error`. Noisy dev detail
`.debug`.

**Never log key material, tokens, or message content.** Matrix IDs are safe — user, room, member,
device. Key *metadata* is safe and useful (index, sender, cross-signed); the key is not. Enum carrying
a secret in an associated value must conform `CustomStringConvertible` and log the case name only.

---

## Testing

**Swift Testing only.** `@Test`, `#expect`, `#require`, `@Suite`. No XCTest anywhere, do not add it.
Suites are `nonisolated struct` unless they need the main actor.

| Layer | Where |
| --- | --- |
| Pure logic | `Tests/ElementCallTests`, runs anywhere |
| Snapshots from previews | same target, needs the pinned simulator |
| Widget bridge wire protocol | same target, fakes the driver channel with a pair of pipes |
| Real media call | needs `demo/backend` docker stack from matrix-rust-rtc, run by hand |

**Fakes are hand-written and ship in the product**, at `Sources/ElementCall/Ports/ElementCallFakes.swift`
— one `Fake*` per port, so a host can preview against them too. No Sourcery mocks, no `AutoMockable`,
no mocking library. Name a new one `Fake*`.

Previews for every main state. `PreviewProvider`, **not** `#Preview` — Sourcery scans for the former.
Conform to `TestablePreview` so the snapshot case generates.

A view that cannot be previewed is a view with no visual coverage. If it takes something a preview
cannot build, split the rendering into a value-taking view and preview that — `ElementCallMinimizedBar`
and its `…Content` are the worked example. `ElementCallScreen` is the exception: it looks up the window
scene, and there is nothing meaningful to snapshot.

Anything drawn from a live clock cannot be snapshotted. Pass nil or a fixed date.

## Accessibility

Identifiers on the call UI are **public API**. External interop rig drives real host builds through
them. Rename is a breaking change, and `AccessibilityIdentifierTests` will say so.

**Declaring one is half the job — apply it to a view.** Four were declared, asserted, and applied to
nothing; the rig could not find them and the suite stayed green, because it only compared strings to
themselves. `everyIdentifierIsApplied` now reads the sources and fails on the gap. It skips where the
simulator cannot read the checkout (macOS blocks `~/Documents` and `~/Desktop`), so **CI is where it
actually holds**.

Use `.accessibilityElement(children: .contain)` on a container before its identifier, or the identifier
swallows the children's.

Spoken labels are strings — through `ElementCallStrings`, like anything else.

---

## Conventions

### Code style

- Swift 6.2, main-actor isolation by default in every module. Do not add redundant `@MainActor`.
- **`import SwiftUI` re-exports Foundation.** Never both. Non-view file that needs neither SwiftUI nor
  UIKit imports Foundation alone.
- `import UIKit` only for genuine UIKit work — four files, all in `ElementCallKit`. SwiftUI otherwise.
- Member order: properties → `init` → `body` → functions, private helpers under `// MARK: - Private`.
- Follow the [Swift API Design Guidelines]: `ID` not `Id`, `URL` not `Url`.
- File headers come from `.swiftpm/…/IDETemplateMacros.plist`. One copyright line.

### Concurrency

- **`@unchecked Sendable` confined to `ElementCallKit/Media`**, sixteen types, deliberate: audio render
  callbacks, capture delegates and Metal draws run on threads the compiler cannot reason about, and
  actor hops there cost frames. Those types synchronise by hand. **Banned everywhere else**, SwiftLint
  enforces at error severity. Concurrency fighting you outside the media layer? Design is wrong.
- **Zero `nonisolated(unsafe)`.** Keep it zero.
- Never store a function value directly in a generic `Mutex`. Each `withLock` reabstracts and writes
  back one more thunk, so per-frame callback overflows the stack after a few minutes. Box it in a
  struct.

### Naming

`MatrixRTC*` prefixed types name **protocol** concepts and keep that prefix. `ElementCall*` names our
own API. Casing is uniform per the API design guidelines. Bindings' own module is `MatrixRtc`, spelled
exactly that way — `import MatrixRtc` and the `MatrixRtc.`-qualified uses in `VideoFrameSlot.swift` are
references to *it*, not to us. Bulk re-casing must leave those alone, with `MatrixRtcFFI` and
`MatrixRtcFfiError`. Nothing of ours may be called `MatrixRtc`.

### Layout

**Orientation is the shape of the space, never the size class.** `ElementCallStageLayout.Metrics` and
`ElementCallView` both decide on `width > height` and must keep agreeing. iPad in landscape has a
*regular* vertical size class, so a size-class branch would leave its controls at the bottom while the
stage laid its tiles out for a side rail.

---

## Comments

Comment the **why**, never the what. Where a decision is not obvious from the code, the reason sits next
to it, including the reasons that were got wrong first, because those are the ones that get re-broken.

**Deliberate divergence from element-x-ios**, which asks for one-line comments. Several here are longer
than usual, on purpose. Do not shorten them into restatements of the code.

---

## Pull requests

- Branch from `main`. Not `develop` — no such branch here.
- Sentence-style titles, no conventional commits. **Title is the changelog entry**, so describe the
  change, not the issue number.
- **Exactly one `pr-` label** (see `.github/release.yml`). Nothing enforces it; a reviewer noticing is
  all that keeps the entry out of the catch-all *Others*. Recoverable — notes generate at release, not
  at merge.
- ~500 lines of production code. Split anything bigger.
- Screenshots or video for visual changes. Re-record snapshots on the pinned device.
- Commits need title and description. No tiny commits, no enormous ones, no history rewrites under
  review.
- `CHANGES.md` by hand **only** for something a host must act on: renamed accessibility identifier, new
  port requirement, new build setting, new string to translate. Under `## Unreleased`. Ordinary changes
  need nothing there.

---

## Releasing

Release is a **tag**, nothing more. Bare semver — `0.1.0`, `0.2.0-rc.1` — because that is what SwiftPM
matches a host's `exactVersion` against, and **the tag is the only place a version exists**: no version
constant, no `MARKETING_VERSION`, nothing to bump in a PR.

Pipeline is `.github/workflows/release.yml` plus `scripts/release.sh`, which holds all validation and
never touches the remote so it can be rehearsed locally. Notes come from `pr-` labels via
`.github/release.yml`, land in `CHANGES.md` inside the tagged commit.

Three things easy to break by tidying:

- **Releases cut from `release/<version>` branch, never `main`.** That is what keeps the pipeline on the
  built-in `GITHUB_TOKEN`: pushes only to that unprotected branch and a new tag, changelog reaches
  `main` through an ordinary PR. Pointing at `main` would need a token that bypasses branch protection.
- **Newest tag read with `git tag --merged HEAD` and `versionsort.suffix=-`.** First scopes it to the
  branch's own history, so a fix to an older line is neither refused for going backwards nor given notes
  generated against a release it does not contain. Second stops git ranking `0.2.0-rc.1` above `0.2.0`,
  which would make `previous_tag_name` the rc.
- **`CHANGES.md` keeps a `## Unreleased` heading**, renamed to `## <version> - <date>` before a fresh one
  opens. Hand-written entries carry into the released section above the generated list. Do not delete the
  heading; release refuses without it.

**Ships source, not binary.** Decision with reasons, not a limitation — `matrix-rust-rtc` ships an
xcframework because it contains Rust, not because that is how Swift packages are released. Do not add a
`binaryTarget` or a build-and-attach step. [RELEASING.md](RELEASING.md) has the reasoning and the one
trigger that would justify revisiting it.

---

## What is temporary

`Sources/ElementCallMatrix/Widget/` drives the SDK's widget driver in process, standing in for bindings
the released SDK lacks: delayed events, room-state feed, to-device messaging. **Scheduled for deletion.**
`WidgetMatrixBridge.swift`'s header lists the exact bindings that retire it and the removal steps. Do not
build new features on it. Do not let it leak past `ElementCallSDKTransport`.

`openBridge` is the **only** place a bridge is created, deliberately. Earlier version had two creation
paths and only one wired up the to-device pump, so media keys reached nobody and every remote tile went
black. Bridge and pump are one value now, so the type system forbids it. Keep it that way.

[Swift API Design Guidelines]: https://www.swift.org/documentation/api-design-guidelines/
