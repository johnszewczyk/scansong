import Darwin
import Foundation

/// Owns one scanner-launched process and makes cancellation safe even when it
/// races process startup. Scanner subprocesses are placed in a private process
/// group so a decoder helper cannot outlive the process that owns it.
final class ScannerManagedProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var processGroupID: pid_t?
    private var terminationRequested = false
    private var didLaunch = false

    func install(_ process: Process) {
        lock.withLock {
            self.process = process
        }
    }

    /// Starts the installed process unless cancellation won the startup race.
    /// The lock covers the run call so cancellation cannot arrive between the
    /// last cancellation check and the actual process launch.
    @discardableResult
    func launch(_ process: Process) throws -> Bool {
        try lock.withLock {
            guard !terminationRequested else { return false }
            try process.run()
            didLaunch = true

            let pid = process.processIdentifier
            if pid > 0, Darwin.setpgid(pid, pid) == 0 {
                processGroupID = pid
            }
            if terminationRequested {
                terminateLocked()
            }
            return true
        }
    }

    func wasLaunched() -> Bool {
        lock.withLock { didLaunch }
    }

    func clear() {
        lock.withLock {
            process = nil
            processGroupID = nil
        }
    }

    func terminate() {
        lock.withLock {
            terminationRequested = true
            terminateLocked()
        }
    }

    private func terminateLocked() {
        guard let process else { return }
        if let processGroupID, process.isRunning {
            _ = Darwin.kill(-processGroupID, SIGTERM)
        }
        if process.isRunning {
            process.terminate()
        }
    }
}
