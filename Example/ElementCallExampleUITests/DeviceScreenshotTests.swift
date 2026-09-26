//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import XCTest

/// Captures the harness on a real device into the test results, for the questions only a device can
/// answer.
///
/// Everything the layout does can be seen in the simulator, and the snapshots cover how it draws. A
/// few things cannot be seen there at all — Picture in Picture is the standing example, since
/// `AVPictureInPictureController.isPictureInPictureSupported()` is false on every simulator — and
/// before this the only way to look at one was to ask somebody to photograph their phone. `simctl`
/// does not reach a device and `devicectl` has no screenshot command, but a UI test runs *on* the
/// device and can take one.
///
/// It captures the whole screen rather than the app, so system windows are in it: a Picture in
/// Picture window belongs to another process and still appears.
///
/// ```bash
/// TEST_RUNNER_ARRANGEMENT=video xcodebuild test \
///   -project Example/ElementCallExample.xcodeproj -scheme ElementCallExample \
///   -destination "id=$DEVICE_UDID" -only-testing:ElementCallExampleUITests/DeviceScreenshotTests \
///   -resultBundlePath /tmp/res.xcresult
/// xcrun xcresulttool export attachments --path /tmp/res.xcresult --output-path /tmp/shots
/// ```
final class DeviceScreenshotTests: XCTestCase {
    /// Which fixture to open. `TEST_RUNNER_` prefixed, because that is the only spelling that
    /// reaches the runner's environment: a bare `ARRANGEMENT=…` on the `xcodebuild` line silently
    /// does not arrive, the same trap `RECORD_FAILURES` sets for the snapshot harness.
    private var arrangement: String {
        ProcessInfo.processInfo.environment["TEST_RUNNER_ARRANGEMENT"]
            ?? ProcessInfo.processInfo.environment["ARRANGEMENT"]
            ?? "group"
    }
    
    func testCaptureTheHarness() {
        let app = XCUIApplication()
        app.launchArguments = ["-arrangement", arrangement]
        app.launch()
        
        let tiles = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "elementCall.tile."))
        let appeared = expectation(for: NSPredicate(format: "count > 0"), evaluatedWith: tiles)
        XCTAssertEqual(XCTWaiter().wait(for: [appeared], timeout: 20), .completed,
                       "The call screen should be up before anything is captured.")
        
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "harness-\(arrangement)"
        // Attachments on a *passing* test are discarded without this, which is exactly the case a
        // screenshot is wanted for.
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
