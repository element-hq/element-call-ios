//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

// MARK: - Theme

/// Colours and fonts, supplied by the host.
///
/// Every member is a computed property read at draw time, never a value captured once. That matters
/// for a host whose design system can be re-branded at runtime: a snapshot taken at construction
/// would leave the call screen on stock colours while the rest of the app changed.
public nonisolated protocol ElementCallTheme: Sendable {
    // Backgrounds
    @MainActor var bgCanvasDefault: Color { get }
    @MainActor var bgCanvasDefaultLevel: Color { get }
    @MainActor var bgSubtleSecondary: Color { get }
    @MainActor var bgAccentRest: Color { get }
    @MainActor var bgActionPrimaryRest: Color { get }
    @MainActor var bgCriticalPrimary: Color { get }
    
    // Icons
    @MainActor var iconPrimary: Color { get }
    @MainActor var iconQuaternary: Color { get }
    @MainActor var iconAccentPrimary: Color { get }
    @MainActor var iconCriticalPrimary: Color { get }
    /// For an icon drawn on top of a filled button, where the usual icon colour would disappear.
    @MainActor var iconOnSolidPrimary: Color { get }
    
    // Text
    @MainActor var textPrimary: Color { get }
    @MainActor var textSecondary: Color { get }
    @MainActor var textCriticalPrimary: Color { get }
    
    // Borders
    @MainActor var borderSuccessSubtle: Color { get }
    @MainActor var borderInteractiveSecondary: Color { get }
    
    // Fonts
    @MainActor var bodySM: Font { get }
    @MainActor var bodySMSemibold: Font { get }
    @MainActor var bodyLGSemibold: Font { get }
}

// MARK: - Icons

public nonisolated enum ElementCallIcon: Sendable, CaseIterable {
    case endCall
    case micOn
    case micOff
    case videoCall
    case videoCallOff
    case switchCamera
    case shareScreen
    case volumeOn
    case volumeOff
    case raisedHand
    case userProfile
    case overflow
    case collapse
}

public nonisolated enum ElementCallIconSize: Sendable {
    case xSmall, small, medium
}

/// The text style an icon scales alongside, so it grows with Dynamic Type the way its label does.
public nonisolated enum ElementCallTextStyle: Sendable {
    case bodySM, bodySMSemibold, bodyLGSemibold
}

/// Icons, supplied by the host so they match the rest of its app and scale with Dynamic Type.
public nonisolated protocol ElementCallIconRendering: Sendable {
    @MainActor
    func icon(_ icon: ElementCallIcon, size: ElementCallIconSize, relativeTo textStyle: ElementCallTextStyle?) -> AnyView
}

public extension ElementCallIconRendering {
    @MainActor
    func icon(_ icon: ElementCallIcon, size: ElementCallIconSize = .medium) -> AnyView {
        self.icon(icon, size: size, relativeTo: nil)
    }
}

// MARK: - Avatars

public nonisolated enum ElementCallAvatarSize: Sendable {
    /// The small tile in a one-to-one layout, and the strip in a group call.
    case thumbnail
    /// A full-bleed tile, and the Picture in Picture placeholder.
    case full
}

/// Avatars, supplied by the host. Keeping this on the host's side means the package never loads or
/// caches media, and avatars keep whatever placeholder colours and initials the host already uses.
public nonisolated protocol ElementCallAvatarRendering: Sendable {
    @MainActor
    func avatar(userID: String, displayName: String?, avatarURL: URL?, size: ElementCallAvatarSize) -> AnyView
}

// MARK: - The bag

/// Everything presentational the host supplies, gathered so it can be handed to the view tree once.
public nonisolated struct ElementCallStyle: Sendable {
    public let theme: any ElementCallTheme
    public let icons: any ElementCallIconRendering
    public let avatars: any ElementCallAvatarRendering
    public let strings: ElementCallStrings
    
    public init(theme: any ElementCallTheme,
                icons: any ElementCallIconRendering,
                avatars: any ElementCallAvatarRendering,
                strings: ElementCallStrings = .init()) {
        self.theme = theme
        self.icons = icons
        self.avatars = avatars
        self.strings = strings
    }
    
    /// The real Compound design tokens, for previews, snapshots and any host with no design system
    /// of its own to plug in. Tokens only, never the Compound component library: see
    /// `ElementCallTokenStyle.swift` for why that distinction matters.
    public static let stock = ElementCallStyle(theme: ElementCallTokenTheme(),
                                               icons: ElementCallTokenIcons(),
                                               avatars: ElementCallTokenAvatars())
}
