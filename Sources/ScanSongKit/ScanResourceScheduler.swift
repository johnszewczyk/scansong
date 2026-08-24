import Foundation

/// Cancellation-aware async permits bound independent scanner plugins without
/// blocking a host actor or serializing synchronous decoder work on this actor.
public actor ScanResourceScheduler {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var availablePermits: Int
    private var waiters: [Waiter] = []

    public init(permits: Int) {
        availablePermits = max(1, permits)
    }

    public func acquire() async throws {
        try Task.checkCancellation()
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }

        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: waiterID, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: waiterID) }
        }
    }

    public func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.continuation.resume()
        } else {
            availablePermits += 1
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    public func withPermit<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await acquire()
        do {
            try Task.checkCancellation()
            let task = Task.detached(priority: .utility, operation: operation)
            let result = try await withTaskCancellationHandler(
                operation: { try await task.value },
                onCancel: { task.cancel() }
            )
            release()
            return result
        } catch {
            release()
            throw error
        }
    }
}
