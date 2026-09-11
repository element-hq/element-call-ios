//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// Deliberately the only import: this file exists to prove that one import reaches all four
// modules. Adding `import ElementCallKit` here to fix a build failure would defeat it — fix the
// re-export in Sources/ElementCallAll instead.
import ElementCallAll
import Testing

/// The umbrella is a compile-time promise, so these are compile-time assertions that happen to run.
nonisolated struct UmbrellaProductTests {
    @Test
    func reachesEveryModuleThroughOneImport() {
        // ElementCallKit
        #expect(MatrixRTCStreamKind.camera != .screenShare)
        // ElementCall
        #expect(ElementCallDefaultOptions().isPictureInPictureEnabled)
        // ElementCallUI
        #expect(!ElementCallAccessibilityIdentifiers.minimizedBar.isEmpty)
        // ElementCallMatrix, and with it that the conformance still crosses the boundary: the
        // protocol comes from ElementCallKit and the type implementing it from ElementCallMatrix,
        // so this only compiles if the umbrella re-exports both. Named rather than constructed
        // because a transport needs a real Client.
        let transport: any ElementCallMatrixTransport.Type = ElementCallSDKTransport.self
        #expect(transport is ElementCallSDKTransport.Type)
    }
}
