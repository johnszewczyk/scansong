# Scanner Contract

## Scope

- Shared discovery, inspection, archive handling, catalog persistence, resume,
  diagnostics, and host process boundary.

## Ownership

- `MediaScannerKit` is the sole schema-23 catalog writer.
- `CatalogScanner` owns discovery, reuse, inspection, checkpointing, and atomic
  root publication.
- `CanonicalCatalogWriter` owns schema creation and every SQLite mutation.
- `media-scan` owns ordered JSONL serialization, exit status, and process-signal
  cancellation.
- `MediaScannerApp` owns the native test/operation window. It may use SwiftUI;
  `MediaScannerKit` may not.
- Player hosts own presentation, playback, settings, and query-only adapters.

## Invariants

- CocoaSpice and SPCBoy open the chosen catalog with OS-level read-only SQLite
  handles plus `PRAGMA query_only=ON`; neither host exposes catalog mutations.
- New catalogs and exact schema 23 are accepted. MediaScanner does not migrate
  an unrelated or older application database.
- The writer uses rollback-journal (`DELETE`) mode. Publication leaves one
  self-contained database file that remains readable after the writer exits.
- One hidden staging root represents an unpublished scan. Publication replaces
  the live root rows and both sidebar projections in one transaction.
- A checkpoint covers one complete loose source or one complete physical
  archive. Partial archive results are never resumable or published.
- Cancellation pauses useful staged work. Resume always rediscovers sources and
  validates fingerprints before reusing checkpoints.
- A failed refresh preserves last-known-good playable rows, records the current
  failure in staged inventory, and omits its checkpoint so it is retried.
- Structure policy is independent from optional metadata policy. Required child
  or dependency enumeration cannot be deferred.
- Unknown inputs and unavailable required adapters are typed diagnostics, never
  invented playable rows or calls into a host scanner.
- TAR.ZST is fully decompressed to a bounded temporary TAR before listing and
  extraction; the scanner never closes a producer pipe early.
- Standard output contains JSONL events only, with explicit contract name,
  version, and monotonically increasing sequence.

## Concurrency and Failure Boundaries

- Cancellation is checked during discovery, archive processes, source
  inspection, persistence boundaries, and between roots.
- Child archive processes are terminated when their task is cancelled.
- Archive paths, symlinks, member count/name size, and expanded bytes are
  validated before records are accepted.
- Required adapters currently implemented in-process are libgme enumeration,
  SPC tags, PSF tags, and plain VGM metadata. Missing dependency-enumeration
  adapters fail explicitly until moved into this package.

## Files

- [CatalogScanner.swift](/Users/john/Downloads/Code/MediaScanner/Sources/MediaScannerKit/CatalogScanner.swift)
- [CanonicalCatalogWriter.swift](/Users/john/Downloads/Code/MediaScanner/Sources/MediaScannerKit/CanonicalCatalogWriter.swift)
- [ScannerInspectors.swift](/Users/john/Downloads/Code/MediaScanner/Sources/MediaScannerKit/ScannerInspectors.swift)
- [StandaloneArchiveExtractor.swift](/Users/john/Downloads/Code/MediaScanner/Sources/MediaScannerKit/StandaloneArchiveExtractor.swift)
- [MediaScanCommand.swift](/Users/john/Downloads/Code/MediaScanner/Sources/media-scan/MediaScanCommand.swift)
- [MediaScannerApp.swift](/Users/john/Downloads/Code/MediaScanner/Sources/MediaScannerApp/MediaScannerApp.swift)
