//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import MetalKit
import SwiftUI

/// Draws a `VideoFrameSlot` with Metal and reports the drawn pixel size so the SFU can be asked
/// for a layer that fits.
public struct VideoTileView: UIViewRepresentable {
    let slot: VideoFrameSlot
    let onPixelSizeChange: (CGSize) -> Void
    
    public init(slot: VideoFrameSlot, onPixelSizeChange: @escaping (CGSize) -> Void = { _ in }) {
        self.slot = slot
        self.onPixelSizeChange = onPixelSizeChange
    }
    
    public func makeUIView(context: Context) -> VideoTileUIView {
        let view = VideoTileUIView(slot: slot)
        view.onPixelSizeChange = onPixelSizeChange
        return view
    }
    
    public func updateUIView(_ uiView: VideoTileUIView, context: Context) {
        uiView.onPixelSizeChange = onPixelSizeChange
    }
    
    public static func dismantleUIView(_ uiView: VideoTileUIView, coordinator: ()) {
        uiView.release()
    }
}

public final class VideoTileUIView: UIView {
    var onPixelSizeChange: ((CGSize) -> Void)?
    private let metalView = MTKView()
    private let renderer: I420MetalRenderer?
    private var lastReportedSize: CGSize = .zero
    private var lifecycleObservers: [NSObjectProtocol] = []
    /// GPU work is forbidden while the app is not active: `nextDrawable` blocks and the system kills
    /// the process. Locking the phone mid-call is the common way to get there.
    private var isRenderingAllowed = UIApplication.shared.applicationState == .active
    
    init(slot: VideoFrameSlot) {
        renderer = I420MetalRenderer(slot: slot)
        super.init(frame: .zero)
        backgroundColor = .black
        
        metalView.device = renderer.map { _ in MTLCreateSystemDefaultDevice() } ?? nil
        metalView.delegate = renderer
        metalView.framebufferOnly = true
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = true
        metalView.backgroundColor = .black
        metalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metalView)
        NSLayoutConstraint.activate([
            metalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            metalView.topAnchor.constraint(equalTo: topAnchor),
            metalView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        // A frame arriving requests one draw; MTKView coalesces requests to the display rate.
        slot.setOnFrame { [weak self] in
            DispatchQueue.main.async { self?.requestDraw() }
        }
        
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isRenderingAllowed = false }
            },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isRenderingAllowed = true
                    self?.requestDraw()
                }
            }
        ]
    }
    
    private func requestDraw() {
        guard isRenderingAllowed else { return }
        metalView.setNeedsDisplay()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        if size != lastReportedSize, size.width > 0 {
            lastReportedSize = size
            onPixelSizeChange?(size)
        }
    }
    
    func release() {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        lifecycleObservers.removeAll()
        renderer?.slot.setOnFrame(nil)
        renderer?.release()
    }
}
