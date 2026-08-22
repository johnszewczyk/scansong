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
- `MediaScannerApp` owns the native catalog-management window and its
  per-path last-result logs. It may use SwiftUI; `MediaScannerKit` may not.
- `CanonicalCatalogReader` owns query-only catalog presentation. The scanner
  app uses it to load attached paths and their statistics while player apps
  have the catalog open.
- Player hosts own presentation, playback, settings, and query-only adapters.

## Invariants

- CocoaSpice and SPCBoy open the chosen catalog with OS-level read-only SQLite
  handles plus `PRAGMA query_only=ON`; neither host exposes catalog mutations.
- Catalog presentation must not open `CanonicalCatalogWriter` merely to load
  paths or statistics. Reader connections do not participate in the scanner's
  writer lease.
- New catalogs and exact schema 23 are accepted. MediaScanner does not migrate
  an unrelated or older application database.
- The writer preserves the catalog's durable SQLite journal mode (`DELETE` or
  `WAL`) and never changes it as part of scanning or link maintenance. New
  catalogs begin in SQLite's default `DELETE` mode; a WAL catalog includes its
  `-wal` and `-shm` files while connections remain open.
- `CanonicalCatalogWriter` holds an OS advisory lease beside the selected
  catalog for its lifetime. The lease excludes a second MediaScanner writer;
  it never blocks CocoaSpice or SPCBoy query-only reads.
- A player being open is not a locked state. The writer lease excludes only a
  second MediaScanner writer; CocoaSpice and SPCBoy may keep read-only SQLite
  connections open. SQLite `BUSY`/`LOCKED` remains a retryable condition, not
  catalog corruption.
- One hidden staging root represents an unpublished scan. Publication replaces
  the live root rows and both sidebar projections in one transaction.
- A checkpoint covers one complete loose source or one complete physical
  archive. Partial archive results are never resumable or published.
- Cancellation pauses useful staged work. Resume always rediscovers sources and
  validates fingerprints before reusing checkpoints.
- A failed refresh preserves last-known-good playable rows, records the current
  failure in staged inventory, and omits its checkpoint so it is retried.
- The native window refuses immediate closure while scan or link-maintenance
  work is active. A confirmed scan close requests cooperative cancellation and
  waits for `CatalogScanner` to finish its checkpoint boundary; maintenance
  closes only after its current writer operation returns.
- Attached roots are catalog state, not ephemeral GUI state. Removing a root
  detaches it; it does not purge its indexed records.
- Link tests operate once per distinct physical source. Missing paths enter
  `dead_sources`, remain fingerprinted and retained, and are excluded from both
  rebuilt projections and player queries. Clean Links is the only UI
  action that deletes those indexed rows.
- Per-path human-readable scan logs are optional app-support results keyed
  by catalog identity and root ID. They never alter the catalog or determine
  scanner results.
- Console-tag preference is player presentation state, never a scanner option.
  The compatibility `browser_system` projection is deterministically derived
  from the root-relative collection path; embedded `system` metadata is stored
  independently and never replaces that projection during scanning.
- The folder projection recognizes the collection's console directory, such as
  `set/Nintendo DS/game.tar.zst`. Players may choose that value or embedded
  metadata when grouping; MediaScanner never rewrites rows for the preference.
- Structure policy is independent from optional metadata policy. Required child
  or dependency enumeration cannot be deferred.
- A scanner plugin has a `ScannerPluginDescriptor` for routing and a
  `ScanFormatHandler` for structure and metadata. Handlers return a complete
  `ScanInspection` and are the only layer permitted to invoke their parser;
  they never write the catalog directly.
- Unknown inputs and unavailable required adapters are typed diagnostics, never
  invented playable rows or calls into a host scanner.
- TAR.ZST is fully decompressed to a bounded temporary TAR before listing and
  extraction; the scanner never closes a producer pipe early.
- Standard output contains JSONL events only, with explicit contract name,
  version, and monotonically increasing sequence.

## Concurrency and Failure Boundaries

- Cancellation is checked during discovery, archive processes, source
  inspection, persistence boundaries, and between roots.
- Sources are processed through a bounded cross-archive pipeline (default 4
  archives in flight, tunable via the CLI `--archive-limit`): several archives
  extract and inspect at once, all member inspections share one permit pool
  (default 8, `--permits`) so the total subprocess count stays bounded, and
  catalog checkpoints commit serially in the coordinator so the SQLite writer
  is never touched concurrently. Completed per-source checkpoints persist on
  cancellation, preserving resume; record order stays deterministic.
- Archive member inspection runs under the shared bounded permit pool
  (`ScanResourceScheduler`) so subprocess adapters (vgmstream, Highly Complete)
  run concurrently while records keep deterministic member order. Loose
  inspection and catalog persistence remain ordered.
- Fingerprint reuse compares the persisted epoch `modified_at` double rather
  than the internal `Date` value: `Date(timeIntervalSince1970:)` can land one
  double-ULP off Foundation's `contentModificationDate` for the same
  filesystem instant, which would silently re-scan unchanged sources.
- Phase telemetry (`ScanPhaseTimeline`) is reported per root in the CLI's
  `sessionFinished` event so discovery/extraction/inspection/persistence
  throughput can be monitored when tuning `--permits` or `--archive-limit`.
- SQLite write contention waits through the configured busy timeout. A timeout
  or conflicting writer leaves completed transactions atomic and the catalog
  readable; MediaScanner reports the condition and re-enables retry actions.
- Child archive processes are terminated when their task is cancelled.
- Archive paths, symlinks, member count/name size, and expanded bytes are
  validated before records are accepted.
- Required adapters currently include libgme enumeration, SPC tags, PSF tags,
  plain VGM metadata, direct Commodore 64 SID PSID/RSID header reads, the
  scanner-owned vgmstream CLI plugin for raw vgmstream formats, the scanner-owned
  Highly Complete inspection plugin for GSF/miniGSF, and OpenMPT tracker/module
  intake (S3M, MOD, IT, XM, MTM, STM, and related) as structurally-known single
  rows. ScanSong never invokes CocoaSpice's app or a player-owned helper. A
  missing executable is a typed adapter failure. The Highly Complete adapter creates a parser handle before reading
  metadata, so a miniGSF is rejected unless its extracted sibling dependencies
  resolve. GSF/miniGSF exposes exactly one validated track per file.
  Dependency-enumerated formats without their own plugin fail explicitly.

## Files

- [CatalogScanner.swift](/Users/john/Downloads/Code/MediaScanner/Sources/MediaScannerKit/CatalogScanner.swift)
- [CanonicalCatalogWriter.swift](/Users/john/Downloads/Code/MediaScanner/Sources/MediaScannerKit/CanonicalCatalogWriter.swift)
- [ScannerInspectors.swift](/Users/john/Downloads/Code/MediaScanner/Sources/MediaScannerKit/ScannerInspectors.swift)
- [StandaloneArchiveExtractor.swift](/Users/john/Downloads/Code/MediaScanner/Sources/MediaScannerKit/StandaloneArchiveExtractor.swift)
- [MediaScanCommand.swift](/Users/john/Downloads/Code/MediaScanner/Sources/media-scan/MediaScanCommand.swift)
- [MediaScannerApp.swift](/Users/john/Downloads/Code/MediaScanner/Sources/MediaScannerApp/MediaScannerApp.swift)
