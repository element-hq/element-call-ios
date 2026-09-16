//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// One dependency and one import for a host that wants the whole thing, without collapsing the four
// modules into one. This module is the bare name because that is the name a host reaches for: it
// used to belong to the lifecycle-and-ports layer, which is now ElementCallHost, and the umbrella
// was called ElementCallAll. Hosts asked why, and there was no answer beyond "the name was taken".
//
// The split behind it is load-bearing and stays: it is what lets SwiftLint keep the Matrix bindings
// confined to ElementCallMatrix by path, and what stops the media layer growing a dependency on the
// view layer. A host that only wants the media layer can still depend on ElementCallKit alone,
// because all four products are still published.
//
// (Naming those bindings' module in a comment here would itself trip that rule, which has no
// match_kinds and so reads comments too, and this file is not on the excluded path. Hence the
// circumlocution.)
//
// `@_exported` is underscored, and it is the only way to do this: a product listing several
// targets still makes the host write one import per module, because a product is a linkage unit
// rather than a module. Re-exporting is stable, widely used for exactly this, and the failure mode
// if it ever went away is a compile error in the host rather than anything subtle.

@_exported import ElementCallHost
@_exported import ElementCallKit
@_exported import ElementCallMatrix
@_exported import ElementCallUI
