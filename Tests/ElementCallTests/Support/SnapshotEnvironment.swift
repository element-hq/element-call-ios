//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// The one place the snapshot environment is written down.
///
/// In element-x-ios the same three facts live in the harness, the workflow and the continuous
/// integration bootstrap, which is four edits per Xcode bump and an afternoon of confusing failures
/// when one is missed. The workflow reads these values from here instead.
enum SnapshotEnvironment {
    /// Font rendering differs between devices, so snapshots are only comparable on one. This is the
    /// same device Compound pins, so anyone maintaining both packages needs one simulator.
    static let simulatorName = "iPhone SE (3rd generation)"
    static let simulatorModelIdentifier = "iPhone14,6"
    static let requiredOSVersion = (major: 26, minor: 5)
    
    /// The simulator the workflow creates. Named so a developer's own simulators are left alone.
    static let simulatorLabel = "ElementCall Snapshots"
    
    /// Snapshot file names carry the locale, so it has to be fixed or every image is machine-specific.
    ///
    /// element-x-ios pins this in a test plan, which a SwiftPM package does not have, so it comes from
    /// `-testLanguage en -testRegion GB` on the xcodebuild command instead. Matching element-x-ios
    /// keeps the two repositories' snapshots named the same way.
    static let requiredLanguage = "en"
    static let requiredRegion = "GB"
    
    /// What each preview is rendered as. The name is what lands in the file name; the device only
    /// selects a size and safe area, and is unrelated to the simulator above.
    ///
    /// The orientation goes in the name rather than in a segment of its own, so that a landscape
    /// image sits next to its portrait twin under a name that already tells them apart and the file
    /// name template needs to know nothing about orientations.
    ///
    /// The iPad has always been rendered on its side, because the snapshot library's bare `iPad10_2`
    /// means `iPad10_2(.landscape)` while its bare `iPhoneX` means portrait. Saying so here rather
    /// than leaving it implicit: reading the flag as false and "correcting" it silently re-renders
    /// twenty-one reference images into a shape nobody asked for. There is no iPad portrait yet,
    /// which is a gap now that the layout has two shapes to get wrong.
    static let renderDevices = [(name: "iPhone", device: "iPhone 17", isLandscape: false),
                                (name: "iPad", device: "iPad", isLandscape: true),
                                (name: "iPhone-landscape", device: "iPhone 17", isLandscape: true)]
}
