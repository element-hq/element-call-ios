//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

/// Marks a preview as one the snapshot suite should render.
///
/// It lives in the product rather than the test target because Sourcery scans `Sources/` to generate
/// the test cases, which is the same arrangement Compound uses.
public protocol TestablePreview { }
