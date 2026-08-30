import Foundation

enum InspectorProcessRunner {
    static let defaultTimeout: Duration = .seconds(30)
    static let defaultStandardOutputLimit = 4 * 1_024 * 1_024
    static let defaultStandardErrorLimit = 256 * 1_024

    static func run(
        executable: URL,
        arguments: [String],
        timeout: Duration = defaultTimeout,
        standardOutputLimit: Int = defaultStandardOutputLimit,
        standardErrorLimit: Int = defaultStandardErrorLimit
    ) async throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let processBox = ScannerManagedProcess()
        let output = BoundedPipeCapture(limit: standardOutputLimit) { processBox.terminate() }
        let errors = BoundedPipeCapture(limit: standardErrorLimit) { processBox.terminate() }
        process.standardOutput = output.pipe
        process.standardError = errors.pipe

        let completion = ProcessCompletion()
        process.terminationHandler = { completion.finish(status: $0.terminationStatus) }
        processBox.install(process)

        let status: Int32
        do {
            status = try await withTaskCancellationHandler {
                do {
                    guard try processBox.launch(process) else { throw CancellationError() }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw ScannerInspectionError.library(
                        "Could not launch \(executable.lastPathComponent): \(error.localizedDescription)"
                    )
                }
                return try await withThrowingTaskGroup(of: Int32.self) { group in
                    group.addTask { await completion.value() }
                    group.addTask {
                        try await Task.sleep(for: timeout)
                        processBox.terminate()
                        throw InspectorProcessFailure.timedOut
                    }
                    defer { group.cancelAll() }
                    return try await group.next()!
                }
            } onCancel: {
                processBox.terminate()
            }
        } catch {
            if processBox.wasLaunched() {
                processBox.terminate()
                _ = await completion.value()
            }
            processBox.clear()
            output.finish()
            errors.finish()
            if Task.isCancelled { throw CancellationError() }
            if case InspectorProcessFailure.timedOut = error {
                throw ScannerInspectionError.library(
                    "\(executable.lastPathComponent) exceeded the \(timeout) inspection timeout."
                )
            }
            throw error
        }

        processBox.clear()
        output.finish()
        errors.finish()
        if output.didExceedLimit {
            throw ScannerInspectionError.library(
                "\(executable.lastPathComponent) exceeded the \(standardOutputLimit)-byte stdout safety limit."
            )
        }
        if errors.didExceedLimit {
            throw ScannerInspectionError.library(
                "\(executable.lastPathComponent) exceeded the \(standardErrorLimit)-byte stderr safety limit."
            )
        }
        let errorText = String(decoding: errors.data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard status == 0 else {
            throw ScannerInspectionError.library(
                errorText.isEmpty
                    ? "\(executable.lastPathComponent) could not inspect the file."
                    : errorText
            )
        }
        try Task.checkCancellation()
        return output.data
    }
}

private enum InspectorProcessFailure: Error {
    case timedOut
}

private final class ProcessCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var status: Int32?
    private var continuation: CheckedContinuation<Int32, Never>?

    func finish(status: Int32) {
        let continuation = lock.withLock { () -> CheckedContinuation<Int32, Never>? in
            self.status = status
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(returning: status)
    }

    func value() async -> Int32 {
        await withCheckedContinuation { continuation in
            let completedStatus = lock.withLock { () -> Int32? in
                if let status { return status }
                self.continuation = continuation
                return nil
            }
            if let completedStatus { continuation.resume(returning: completedStatus) }
        }
    }
}

private final class BoundedPipeCapture: @unchecked Sendable {
    let pipe = Pipe()

    private let lock = NSLock()
    private let limit: Int
    private let onLimitExceeded: @Sendable () -> Void
    private var storage = Data()
    private var exceeded = false

    init(limit: Int, onLimitExceeded: @escaping @Sendable () -> Void) {
        self.limit = max(0, limit)
        self.onLimitExceeded = onLimitExceeded
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.append(chunk)
        }
    }

    var data: Data { lock.withLock { storage } }
    var didExceedLimit: Bool { lock.withLock { exceeded } }

    func finish() {
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = nil
        append(handle.readDataToEndOfFile())
        try? handle.close()
    }

    private func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        let crossedLimit = lock.withLock { () -> Bool in
            guard !exceeded else { return false }
            let remaining = max(0, limit - storage.count)
            storage.append(chunk.prefix(remaining))
            if chunk.count > remaining {
                exceeded = true
                return true
            }
            return false
        }
        if crossedLimit { onLimitExceeded() }
    }
}
