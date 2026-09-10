//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// One dependency and one import for a host that wants the whole thing, without collapsing the four
// modules into one.
//
// The split is load-bearing and stays: it is what lets SwiftLint keep the Matrix SDK confined to
// ElementCallMatrix by path, and what stops the media layer growing a dependency on the view
// layer. A host that only wants the media layer can still depend on ElementCallKit alone, because
// all four products are still published.
//
// (Naming the SDK import in a comment here would itself trip that rule, which has no
// match_kinds and so reads comments too. Hence the circumlocution.)
//
// `@_exported` is underscored, and it is the only way to do this: a product listing several
// targets still makes the host write one import per module, because a product is a linkage unit
// rather than a module. Re-exporting is stable, widely used for exactly this, and the failure mode
// if it ever went away is a compile error in the host rather than anything subtle.

@_exported import ElementCall
@_exported import ElementCallKit
@_exported import ElementCallMatrix
@_exported import ElementCallUI
