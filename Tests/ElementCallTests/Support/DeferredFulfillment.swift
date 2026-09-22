//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import Testing

/// Starts consuming now, waits later: the sequence is already being read before the act, so an
/// emission that lands between the two cannot be missed, and `until` skips the ones the act did not
/// cause -- a screen republishes for its own reasons.
///
/// A trimmed copy of the host's helper, `UnitTests/Sources/TestUtilities/DeferredFulfillment.swift`
/// in element-x-ios, which 65 of its test files read this way. Keeping the shape means a host
/// engineer reads these tests without learning anything new. Only the async-sequence half is here:
/// the Combine half needs an `ObservableObject`, and the call screen's state is `@Observable`.
struct DeferredFulfillment<Value: Sendable> {
    fileprivate let stream: AsyncStream<Value>
    fileprivate let task: Task<Void, Never>
    fileprivate let timeout: Duration
    fileprivate let sourceLocation: SourceLocation
    
    /// The matching value, or a recorded issue at the call site if none arrived in time.
    @discardableResult
    func fulfill() async throws -> Value {
        defer { task.cancel() }
        
        return try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { [stream] in
                for await value in stream {
                    return value
                }
                throw DeferredFulfillmentError.noOutput
            }
            // The bound on a broken expectation. A passing test never reaches it.
            group.addTask { [timeout] in
                try await Task.sleep(for: timeout)
                throw DeferredFulfillmentError.noOutput
            }
            defer { group.cancelAll() }
            
            do {
                guard let value = try await group.next() else {
                    throw DeferredFulfillmentError.noOutput
                }
                return value
            } catch {
                Issue.record(Comment(rawValue: "Nothing matched `until` within \(timeout)"), sourceLocation: sourceLocation)
                throw error
            }
        }
    }
}

enum DeferredFulfillmentError: Error {
    case noOutput
}

/// - Parameters:
///   - asyncSequence: what to watch. Consumption starts here rather than in `fulfill()`.
///   - timeout: how long `fulfill()` waits before recording an issue.
///   - condition: which emission is the one being waited for.
func deferFulfillment<Value: Sendable>(_ asyncSequence: any AsyncSequence<Value, Never>,
                                       timeout: Duration = .seconds(10),
                                       sourceLocation: SourceLocation = #_sourceLocation,
                                       until condition: @escaping (Value) -> Bool) -> DeferredFulfillment<Value> {
    let (stream, continuation) = AsyncStream<Value>.makeStream()
    
    let task = Task {
        for await value in asyncSequence where condition(value) {
            continuation.yield(value)
            break
        }
        continuation.finish()
    }
    
    return DeferredFulfillment(stream: stream, task: task, timeout: timeout, sourceLocation: sourceLocation)
}
