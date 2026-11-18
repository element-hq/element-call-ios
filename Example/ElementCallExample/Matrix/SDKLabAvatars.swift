//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCall
import MatrixRustSDK
import SwiftUI

/// The lab's avatars: the members' own pictures, fetched through the SDK, over the stock initials.
/// The package never loads media (see `ElementCallAvatarRenderingProtocol`), so a host that wants
/// photos supplies a renderer like this one; Element X's is `NativeCallAvatars`.
nonisolated struct SDKLabAvatars: ElementCallAvatarRenderingProtocol {
    private let client: Client
    private let cache: SDKLabAvatarCache
    
    @MainActor
    init(client: Client) {
        self.client = client
        cache = SDKLabAvatarCache()
    }
    
    @MainActor
    func avatar(userID: String, displayName: String?, avatarURL: URL?, size: ElementCallAvatarSize) -> AnyView {
        AnyView(SDKLabAvatarImage(client: client,
                                  cache: cache,
                                  avatarURL: avatarURL,
                                  initials: ElementCallTokenAvatars().avatar(userID: userID,
                                                                             displayName: displayName,
                                                                             avatarURL: nil,
                                                                             size: size),
                                  diameter: size == .thumbnail ? 52 : 140))
    }
}

/// Every tile asks for its avatar on every draw, and a tile remounts when the layout changes, so
/// without this a picture would drop back to initials and be fetched again on each move.
@MainActor
private final class SDKLabAvatarCache {
    private var images = [URL: UIImage]()
    private var loads = [URL: Task<UIImage?, Never>]()
    
    func image(for url: URL) -> UIImage? {
        images[url]
    }
    
    /// One request per URL however many tiles show the same member. A failure is not remembered,
    /// so the next tile to appear tries again.
    func load(_ url: URL, pixels: UInt64, client: Client) async -> UIImage? {
        if let image = images[url] {
            return image
        }
        let task = loads[url] ?? Task {
            do {
                let source = try MediaSource.fromUrl(url: url.absoluteString)
                let data = try await client.getMediaThumbnail(mediaSource: source, width: pixels, height: pixels)
                guard let image = UIImage(data: data) else {
                    Self.log("avatar \(url): \(data.count) bytes that are not an image")
                    return nil
                }
                return image
            } catch {
                Self.log("avatar \(url) failed: \(error)")
                return nil
            }
        }
        if loads[url] == nil {
            Self.log("avatar \(url): loading")
        }
        loads[url] = task
        let image = await task.value
        loads[url] = nil
        images[url] = image
        return image
    }
    
    /// On the lab's log, beside the call's, where a person reading why a picture is missing looks.
    private nonisolated static func log(_ message: String) {
        FileHandle.standardError.write(Data("[lab] \(message)\n".utf8))
    }
}

/// The initials until the picture arrives, at the same diameter, so the stage's scaling and the
/// sound waves sized from it do not move when it does.
private struct SDKLabAvatarImage: View {
    let client: Client
    let cache: SDKLabAvatarCache
    let avatarURL: URL?
    let initials: AnyView
    let diameter: CGFloat
    
    /// What this view loaded, with the URL it was for, since a reused view can be handed another
    /// member. Read in `body` so the arrival redraws it; the cache serves views made after it.
    @State private var loaded: (url: URL, image: UIImage)?
    
    private var image: UIImage? {
        guard let avatarURL else { return nil }
        if let loaded, loaded.url == avatarURL {
            return loaded.image
        }
        return cache.image(for: avatarURL)
    }
    
    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
        } else {
            initials
                .task(id: avatarURL) {
                    guard let avatarURL else { return }
                    // The `.full` size is drawn at 140 pt and scaled down from there; 3× covers
                    // every screen without loading the original.
                    if let image = await cache.load(avatarURL, pixels: UInt64(diameter * 3), client: client) {
                        loaded = (avatarURL, image)
                    }
                }
        }
    }
}
