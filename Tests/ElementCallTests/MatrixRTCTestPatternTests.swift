//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementCallKit
import Testing

/// The generated picture the example harness runs on. Worth pinning because it is built a row at a
/// time from templates rather than a pixel at a time — which is what makes it cheap enough to run at
/// thirty a second on a phone, and also what makes an off-by-one in the plane sizes plausible.
nonisolated struct MatrixRTCTestPatternTests {
    @Test("The planes are exactly the size an I420 frame of this shape needs", arguments: [
        (640, 360), (360, 640), (2, 2), (7, 5)
    ])
    func planeSizes(width: Int, height: Int) {
        let frame = MatrixRTCTestPattern.frame(width: width, height: height)
        #expect(frame.width == width)
        #expect(frame.height == height)
        frame.withPlanes { y, u, v in
            #expect(y.width == width)
            #expect(y.height == height)
            #expect(u.width == (width + 1) / 2)
            #expect(u.height == (height + 1) / 2)
            #expect(v.width == (width + 1) / 2)
            #expect(v.height == (height + 1) / 2)
        }
    }
    
    /// The border is the whole point of the pattern: where it ends up tells you whether the picture
    /// was cropped, letterboxed or stretched.
    @Test("The border is drawn on every edge")
    func borderOnEveryEdge() {
        let frame = MatrixRTCTestPattern.frame(width: 640, height: 360)
        frame.withPlanes { y, _, _ in
            let rows = [0, y.height - 1]
            let columns = [0, y.width - 1]
            for row in rows {
                for column in 0..<y.width {
                    #expect(y.pointer.load(fromByteOffset: row * y.stride + column, as: UInt8.self) == 128)
                }
            }
            for column in columns {
                for row in 0..<y.height {
                    #expect(y.pointer.load(fromByteOffset: row * y.stride + column, as: UInt8.self) == 128)
                }
            }
        }
    }
    
    /// The bars are the ruler the picture is read with, so they have to be the same width as each
    /// other. They were not: the border was drawn over the full width rather than around the bars,
    /// so it ate a slice off the end bar and hid itself entirely against the white one at the other
    /// end. Measured here by run length rather than trusted from the arithmetic, because the
    /// arithmetic was right and the picture was still wrong.
    @Test("Every bar is the same width, and the border is around them rather than over them")
    func barsAreEven() {
        let width = 640
        let frame = MatrixRTCTestPattern.frame(width: width, height: 360)
        let middle: [UInt8] = frame.withPlanes { y, _, _ in
            (0..<y.width).map { y.pointer.load(fromByteOffset: (y.height / 2) * y.stride + $0, as: UInt8.self) }
        }
        
        var runs: [(value: UInt8, length: Int)] = []
        for value in middle {
            if runs.last?.value == value {
                runs[runs.count - 1].length += 1
            } else {
                runs.append((value, 1))
            }
        }
        
        // Border, eight bars, border. The border is its own colour, so it never merges with a bar.
        #expect(runs.count == 10, "expected a border, eight bars and a border, got \(runs.map(\.length))")
        let barLengths = runs.dropFirst().dropLast().map(\.length)
        #expect(Set(barLengths).count == 1, "bars are uneven: \(barLengths)")
        #expect(runs.first?.length == runs.last?.length, "the two borders differ")
    }
    
    /// Something has to move, or there is no telling a live stream from a still one.
    @Test("The sweeping band moves with the phase")
    func theSweepMoves() {
        func luma(ofRow row: Int, in frame: MatrixRTCVideoFrame) -> [UInt8] {
            frame.withPlanes { y, _, _ in
                (0..<y.width).map { y.pointer.load(fromByteOffset: row * y.stride + $0, as: UInt8.self) }
            }
        }
        let first = MatrixRTCTestPattern.frame(width: 640, height: 360, phase: 100)
        let later = MatrixRTCTestPattern.frame(width: 640, height: 360, phase: 200)
        #expect((0..<360).contains { luma(ofRow: $0, in: first) != luma(ofRow: $0, in: later) })
    }
}
