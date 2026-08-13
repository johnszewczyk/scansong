# Scanner Contract

## Scope

- Shared source identity, routing policy, events, diagnostics, and host process boundary.

## Ownership

- `MediaScannerKit` owns scanner routing policy, recursive discovery, inventory/planning primitives, lifecycle/telemetry, host-neutral metadata and pipeline results, archive/format plugin protocols, scheduler, and typed process events.
- `media-scan` owns JSONL serialization and process exit status.
- `MediaScannerApp` owns the native test window. It may depend on AppKit/SwiftUI; `MediaScannerKit` may not.
- Hosts own presentation, playback, and application settings.

## Invariants

- Protocol events carry an explicit contract version.
- Structure policy is independent from metadata policy.
- Dry-run probing never writes a catalog or host database.
- Probe discovery and routing check cooperative cancellation and surface progress without UI types in the library.
- Standard output contains JSONL events only.
- Unknown input is a typed diagnostic, never an invented playable row.
- Scanner metadata has no dependency on either host's playlist or playback models.
- CocoaSpice and SPCBoy open the canonical catalog query-only and do not start their legacy writer paths. Until MediaScanner publication exists, no production process writes the catalog.
- Plugin concurrency uses cancellation-aware async permits. A cancelled waiter is removed before it can start decoder work, and synchronous plugin work runs outside the scheduler actor.

## Files

- [ScannerContract.swift](/Users/john/Downloads/Code/MediaScanner/Sources/MediaScannerKit/ScannerContract.swift)
- [ScanDomain.swift](/Users/john/Downloads/Code/MediaScanner/Sources/MediaScannerKit/ScanDomain.swift)
- [BuiltInScannerPlugins.swift](/Users/john/Downloads/Code/MediaScanner/Sources/MediaScannerKit/BuiltInScannerPlugins.swift)
- [DryRunProbe.swift](/Users/john/Downloads/Code/MediaScanner/Sources/MediaScannerKit/DryRunProbe.swift)
- [ScanResourceScheduler.swift](/Users/john/Downloads/Code/MediaScanner/Sources/MediaScannerKit/ScanResourceScheduler.swift)
- [main.swift](/Users/john/Downloads/Code/MediaScanner/Sources/media-scan/main.swift)
- [MediaScannerApp.swift](/Users/john/Downloads/Code/MediaScanner/Sources/MediaScannerApp/MediaScannerApp.swift)
