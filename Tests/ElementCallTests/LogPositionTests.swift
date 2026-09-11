//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCall
import Testing

nonisolated struct LogPositionTests {
    @Test
    func recordsCarryTheCallSite() {
        let logger = ElementCallFakeLogger()
        let line = #line + 1
        logger.log(.info, "hello")
        
        #expect(logger.records.count == 1)
        #expect(logger.records.first?.line == line)
        #expect(logger.records.first?.file.hasSuffix("LogPositionTests.swift") == true)
    }
    
    /// The whole point of threading `file` and `line` through the forwarding wrappers: a helper
    /// that logs on someone's behalf must report *their* position, not its own. Without the
    /// defaulted parameters every line in `ElementCallController` resolved to its private `log`.
    @Test
    func aForwardingWrapperReportsItsCallerNotItself() {
        let logger = ElementCallFakeLogger()
        let wrapper = Wrapper(logger: logger)
        let line = #line + 1
        wrapper.emit("via a helper")
        
        #expect(logger.records.first?.line == line)
    }
    
    @Test
    func levelAndMessageSurviveTheRecord() {
        let logger = ElementCallFakeLogger()
        logger.log(.warning, "careful")
        
        #expect(logger.records.first?.level == .warning)
        #expect(logger.messages == ["careful"])
    }
    
    /// Shaped like the private wrappers in `ElementCallController` and `WidgetMatrixBridge`.
    private nonisolated struct Wrapper {
        let logger: any ElementCallLogging
        
        func emit(_ message: String, file: String = #fileID, line: Int = #line) {
            logger.log(.info, message, file: file, line: line)
        }
    }
}
