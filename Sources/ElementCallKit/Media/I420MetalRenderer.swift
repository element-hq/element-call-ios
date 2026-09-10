//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Metal
import MetalKit
import Synchronization
import UIKit

/// Uploads the three I420 planes as R8 textures straight from the frame's memory and converts to
/// RGB on the GPU (BT.601 limited range, what libwebrtc decodes to). Rotation, mirroring and
/// aspect-fill are a vertex transform, so no pixel is touched on the CPU.
final nonisolated class I420MetalRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct Vertex { float4 position [[position]]; float2 uv; };
    struct Uniforms { float4x4 transform; };
    vertex Vertex i420_vertex(uint id [[vertex_id]], constant Uniforms &uniforms [[buffer(0)]]) {
        float2 positions[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
        float2 uvs[4] = { float2(0, 1), float2(1, 1), float2(0, 0), float2(1, 0) };
        Vertex out;
        out.position = uniforms.transform * float4(positions[id], 0, 1);
        out.uv = uvs[id];
        return out;
    }
    fragment float4 i420_fragment(Vertex in [[stage_in]],
                                  texture2d<float> yTexture [[texture(0)]],
                                  texture2d<float> uTexture [[texture(1)]],
                                  texture2d<float> vTexture [[texture(2)]]) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float y = (yTexture.sample(s, in.uv).r - 16.0 / 255.0) * (255.0 / 219.0);
        float u = uTexture.sample(s, in.uv).r - 0.5;
        float v = vTexture.sample(s, in.uv).r - 0.5;
        float3 rgb = float3(y + 1.402 * v, y - 0.344136 * u - 0.714136 * v, y + 1.772 * u);
        return float4(clamp(rgb, 0.0, 1.0), 1.0);
    }
    """
    
    private struct Uniforms {
        var transform: simd_float4x4
    }
    
    let slot: VideoFrameSlot
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let lock = NSLock()
    private var textures: (y: MTLTexture, u: MTLTexture, v: MTLTexture)?
    private var textureSize = (0, 0)
    private var lastFrame: MatrixRTCVideoFrame?
    private var isReleased = false
    
    init?(slot: VideoFrameSlot) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.shaderSource, options: nil) else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "i420_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "i420_fragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        
        self.slot = slot
        self.device = device
        self.commandQueue = commandQueue
        self.pipeline = pipeline
        super.init()
    }
    
    /// Releasing and drawing are mutually exclusive: SwiftUI can tear the view down while a frame
    /// is being uploaded.
    func release() {
        lock.withLock {
            isReleased = true
            lastFrame = nil
            textures = nil
        }
    }
    
    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
    
    func draw(in view: MTKView) {
        // Never touch the GPU while inactive: `currentDrawable` blocks and the system kills the app.
        guard UIApplication.shared.applicationState == .active else { return }
        lock.withLock {
            guard !isReleased else { return }
            if let frame = slot.take() {
                lastFrame = frame
            }
            guard let frame = lastFrame,
                  let drawable = view.currentDrawable,
                  let passDescriptor = view.currentRenderPassDescriptor,
                  let commandBuffer = commandQueue.makeCommandBuffer() else { return }
            
            upload(frame)
            guard let textures else { return }
            
            var uniforms = Uniforms(transform: transform(for: frame, drawableSize: view.drawableSize))
            passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.setFragmentTexture(textures.y, index: 0)
            encoder.setFragmentTexture(textures.u, index: 1)
            encoder.setFragmentTexture(textures.v, index: 2)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
    
    // MARK: - Private
    
    private func upload(_ frame: MatrixRTCVideoFrame) {
        if textures == nil || textureSize != (frame.width, frame.height) {
            textures = makeTextures(width: frame.width, height: frame.height)
            textureSize = (frame.width, frame.height)
        }
        guard let textures else { return }
        // replaceRegion copies synchronously, so the frame may be released right after this returns.
        frame.withPlanes { y, u, v in
            textures.y.replace(region: MTLRegionMake2D(0, 0, y.width, y.height), mipmapLevel: 0, withBytes: y.pointer, bytesPerRow: y.stride)
            textures.u.replace(region: MTLRegionMake2D(0, 0, u.width, u.height), mipmapLevel: 0, withBytes: u.pointer, bytesPerRow: u.stride)
            textures.v.replace(region: MTLRegionMake2D(0, 0, v.width, v.height), mipmapLevel: 0, withBytes: v.pointer, bytesPerRow: v.stride)
        }
    }
    
    private func makeTextures(width: Int, height: Int) -> (MTLTexture, MTLTexture, MTLTexture)? {
        func make(_ width: Int, _ height: Int) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
            descriptor.usage = .shaderRead
            return device.makeTexture(descriptor: descriptor)
        }
        guard let y = make(width, height), let u = make((width + 1) / 2, (height + 1) / 2), let v = make((width + 1) / 2, (height + 1) / 2) else { return nil }
        return (y, u, v)
    }
    
    /// Rotate upright, mirror if asked, then scale to fill the drawable while keeping the aspect ratio.
    /// The frame's rotation is how far it must turn **clockwise** to be upright (WebRTC semantics);
    /// Metal's y axis points up, so that is a negative angle here.
    private func transform(for frame: MatrixRTCVideoFrame, drawableSize: CGSize) -> simd_float4x4 {
        let width = Float(frame.width)
        let height = Float(frame.height)
        let angle = -Float(frame.rotation.rawValue) * .pi / 180
        let rotated = frame.rotation == .deg90 || frame.rotation == .deg270
        let contentWidth = rotated ? height : width
        let contentHeight = rotated ? width : height
        let drawableWidth = Float(max(1, drawableSize.width))
        let drawableHeight = Float(max(1, drawableSize.height))
        // Aspect fill: the larger factor covers the drawable, the overflow is clipped.
        let fill = max(drawableWidth / contentWidth, drawableHeight / contentHeight)
        
        // Unit quad → frame pixels → rotated upright → mirrored in display space → drawable NDC.
        let frameExtent = simd_float4x4(diagonal: SIMD4(width / 2, height / 2, 1, 1))
        let rotation = simd_float4x4(rows: [
            SIMD4(cos(angle), -sin(angle), 0, 0),
            SIMD4(sin(angle), cos(angle), 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(0, 0, 0, 1)
        ])
        let mirror = simd_float4x4(diagonal: SIMD4(frame.isMirrored ? -1 : 1, 1, 1, 1))
        let toNDC = simd_float4x4(diagonal: SIMD4(fill * 2 / drawableWidth, fill * 2 / drawableHeight, 1, 1))
        return toNDC * mirror * rotation * frameExtent
    }
}
