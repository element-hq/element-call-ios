//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCall
import SwiftUI

/// A call screen with no call behind it, for driving by hand or by a UI test.
///
/// It opens on a catalogue of fixtures and minimizes back to it, which is how the Android harness
/// works and for the same reason: the handover between full screen and minimized is the host's job,
/// and a harness that cannot leave the call screen cannot show it going wrong.
///
/// `-arrangement <name>` skips the catalogue and opens that fixture directly, so a test starts where
/// it means to rather than tapping its way there through a menu it does not care about. With the
/// argument present the hierarchy is exactly what it was before the catalogue existed.
@main
struct ElementCallExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ElementCallExampleRootView(target: .fromLaunchArguments())
        }
    }
}

struct ElementCallExampleRootView: View {
    let target: ElementCallExampleLaunchTarget
    
    @State private var host = ElementCallExampleHost()
    @State private var video = TestPatternVideo()
    
    var body: some View {
        ZStack {
            // The catalogue is not merely covered while the call is up, it is unmounted. A `List`
            // losing its scroll position costs nothing, and in exchange the accessibility tree a UI
            // test walks during a call is the one it walked before any of this existed.
            if host.session == nil || host.isMinimized {
                ElementCallExampleCatalogue(target: target) { host.open($0) }
                    // An inset rather than an overlay: it pushes the list down instead of covering
                    // its first row, which is what a host does and what makes the point of the
                    // thing — you can see the catalogue behind the call — actually legible.
                    .safeAreaInset(edge: .top) {
                        if let session = host.session {
                            ElementCallMinimizedBar(controller: session.controller) { host.restore() }
                        }
                    }
            }
            
            // Unmounted while minimized rather than left to draw `ElementCallView`'s own minimized
            // branch. That branch is `Color.clear`, which SwiftUI still hit-tests, so a shipping
            // host gets away with it and a full-screen one over this catalogue would silently eat
            // every tap on the list and look like a broken list.
            if let session = host.session, !host.isMinimized {
                callScreen(session)
            }
        }
        .onAppear {
            guard case .fixture(let fixture) = target, host.session == nil else { return }
            host.open(fixture)
        }
    }
    
    @ViewBuilder
    private func callScreen(_ session: ElementCallExampleHost.Session) -> some View {
        switch session.presentation {
        case .harness(let context):
            ElementCallHarnessScreen(context: context)
                .environment(\.elementCallPreviewVideo, session.fixture.wantsVideo ? video.source : nil)
        case .live(let viewModel):
            // The shipping view, not the harness one: a connecting state is the one thing a real
            // view model can render without a joined call, so there is no reason to fake it.
            ElementCallScreen(viewModel: viewModel)
        }
    }
}
