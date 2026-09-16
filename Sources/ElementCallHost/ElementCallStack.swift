//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallKit
import Foundation

/// Everything the host needs to hold on to, built once per logged-in session.
///
/// Build it with the session rather than with the first call.
///
/// To-device delivery has no catch-up, so a core that subscribes only after its own membership has
/// gone out can miss keys sent in that window. That is recoverable rather than fatal: peers
/// re-distribute on join, usually minting a fresh key. But the race costs nothing to avoid, and
/// avoiding it means the first frames decrypt instead of arriving black for a moment.
@MainActor
public final class ElementCallStack {
    /// The call, whether or not one is in progress. Observable, so a view can be driven straight
    /// from it.
    public let controller: ElementCallController
    
    private let rtcService: MatrixRTCService
    private let logger: (any ElementCallLogging)?
    
    public init(transport: any ElementCallMatrixTransport,
                system: any ElementCallSystemProviding,
                options: any ElementCallOptions = ElementCallDefaultOptions(),
                style: ElementCallStyle = .stock,
                logger: (any ElementCallLogging)? = nil) {
        let rtcService = MatrixRTCService(transport: transport)
        self.rtcService = rtcService
        self.logger = logger
        controller = ElementCallController(rtcService: rtcService,
                                           transport: transport,
                                           system: system,
                                           options: options,
                                           style: style,
                                           logger: logger)
    }
    
    /// Starts the core. Call this as soon as the session exists rather than when a call begins.
    /// Idempotent, and the core's own handle is held for us, so there is nothing to keep alive here.
    public func start() async {
        logger?.log(.info, "starting the MatrixRTC core")
        await rtcService.start()
    }
    
    public func stop() {
        logger?.log(.info, "stopping the MatrixRTC core")
        rtcService.stop()
    }
}
