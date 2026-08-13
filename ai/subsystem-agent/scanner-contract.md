# Scanner Contract

## Scope

- Shared source identity, routing policy, events, diagnostics, and host process boundary.

## Ownership

- `MediaScannerKit` owns scanner routing policy, inventory primitives, scheduler, and typed process events.
- `media-scan` owns JSONL serialization and process exit status.
- Hosts own presentation, playback, and application settings.

## Invariants

- Protocol events carry an explicit contract version.
- Structure policy is independent from metadata policy.
- Dry-run probing never writes a catalog or host database.
- Standard output contains JSONL events only.
- Unknown input is a typed diagnostic, never an invented playable row.
- CocoaSpice imports the shared routing, inventory, and scheduler types. SPCBoy builds and stages the executable and validates its event stream; its production catalog scan has not yet moved to the Swift process.
- Plugin concurrency uses cancellation-aware async permits. A cancelled waiter is removed before it can start decoder work, and synchronous plugin work runs outside the scheduler actor.

## Files

- [ScannerContract.swift](/Users/john/Downloads/Code/MediaScanner/Sources/MediaScannerKit/ScannerContract.swift)
- [BuiltInScannerPlugins.swift](/Users/john/Downloads/Code/MediaScanner/Sources/MediaScannerKit/BuiltInScannerPlugins.swift)
- [DryRunProbe.swift](/Users/john/Downloads/Code/MediaScanner/Sources/MediaScannerKit/DryRunProbe.swift)
- [ScanResourceScheduler.swift](/Users/john/Downloads/Code/MediaScanner/Sources/MediaScannerKit/ScanResourceScheduler.swift)
- [main.swift](/Users/john/Downloads/Code/MediaScanner/Sources/media-scan/main.swift)
