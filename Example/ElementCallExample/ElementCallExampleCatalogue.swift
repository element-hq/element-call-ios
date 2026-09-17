//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

/// The fixture list the app opens on, and what a minimized call is minimized *over*.
///
/// Every identifier here is prefixed `example.`, never `elementCall.`. The UI tests find tiles by
/// matching the `elementCall.tile.` prefix across the whole hierarchy, so an example-app identifier
/// borrowing the package's namespace would quietly join that set.
struct ElementCallExampleCatalogue: View {
    let target: ElementCallExampleLaunchTarget
    let onPick: (ElementCallExampleFixture) -> Void
    
    var body: some View {
        List {
            if case .unknown(let name) = target {
                unknownArrangement(name)
            }
            ForEach(ElementCallExampleFixture.Category.allCases, id: \.self) { category in
                Section(category.rawValue) {
                    ForEach(ElementCallExampleFixture.fixtures(in: category), id: \.self) { fixture in
                        row(fixture)
                    }
                }
            }
        }
    }
    
    private func row(_ fixture: ElementCallExampleFixture) -> some View {
        Button {
            onPick(fixture)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(fixture.title)
                    .font(.body)
                Text(fixture.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The label is a whole stack, so without this the button answers to both lines run
            // together and a test would have to know the detail string to find a row.
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("example.fixture.\(fixture.rawValue)")
    }
    
    /// Shown rather than silently substituted. `-arrangement` used to fall back to `.group` on
    /// anything it did not recognise, so a typo ran the strip tests against an eight-person stage
    /// and failed with "this tile is not hittable" — a true statement about nothing. On screen, it
    /// is in the failure screenshot; logged, it is in the run's console too.
    private func unknownArrangement(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name.isEmpty ? "No arrangement given after \(ElementCallExampleFixture.launchArgument)"
                              : "Unknown arrangement \u{201C}\(name)\u{201D}")
                .font(.headline)
            Text("Showing the catalogue. Known: \(ElementCallExampleFixture.allCases.map(\.rawValue).joined(separator: ", "))")
                .font(.caption)
        }
        .foregroundStyle(.red)
        .accessibilityIdentifier("example.unknownArrangement")
    }
}
