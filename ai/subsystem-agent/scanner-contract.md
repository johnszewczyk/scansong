# Scanner Contract

## Scope

- Shared discovery, inspection, archive handling, catalog persistence, resume,
  diagnostics, and host process boundary.

## Ownership

- `ScanSongKit` is the sole schema-23 catalog writer.
- `CatalogScanner` owns discovery, reuse, inspection, checkpointing, and atomic
  root publication.
- `CanonicalCatalogSchema` owns exact schema-23 installation statements.
  `CanonicalCatalogWriter` owns every SQLite mutation and transaction boundary.
- `CatalogLinkAuditor` owns filesystem existence checks; the writer alone
  persists `dead_sources` and rebuilds projections transactionally.
- `scansong` owns ordered JSONL serialization, exit status, and process-signal
  cancellation.
- `ScanSongApp` owns the native catalog-management window and its
  per-path last-result logs. It may use SwiftUI; `ScanSongKit` may not.
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
- New catalogs and exact schema 23 are accepted. ScanSong does not migrate
  an unrelated or older application database.
- The writer preserves the catalog's durable SQLite journal mode (`DELETE` or
  `WAL`) and never changes it as part of scanning or link maintenance. New
  catalogs begin in SQLite's default `DELETE` mode; a WAL catalog includes its
  `-wal` and `-shm` files while connections remain open.
- `CanonicalCatalogWriter` holds an OS advisory lease beside the selected
  catalog for its lifetime. The lease excludes a second ScanSong writer;
  it never blocks CocoaSpice or SPCBoy query-only reads.
- A player being open is not a locked state. The writer lease excludes only a
  second ScanSong writer; CocoaSpice and SPCBoy may keep read-only SQLite
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
  metadata when grouping; ScanSong never rewrites rows for the preference.
- Structure policy is independent from optional metadata policy. Required child
  or dependency enumeration cannot be deferred.
- A scanner plugin has a `ScannerPluginDescriptor` for routing and a
  `ScanFormatHandler` for structure and metadata. Handlers return a complete
  `ScanInspection` and are the only layer permitted to invoke their parser;
  they never write the catalog directly.
- Unknown inputs and unavailable required adapters are typed diagnostics, never
  invented playable rows or calls into a host scanner.
- The persisted ScanSong file-type policy ignores only documented decoder-absent
  extensions (`.sgc`, NCSF family, Doom `.mus`, and playlist `.m3u` by default).
  The policy is visible and editable under Options > File Types and is passed to
  both loose-file discovery and archive-member routing.
- Discovery does not invent playable rows for unrelated files without a scanner
  route. Archive members with an unknown extension are retained in the optional
  post-operation skip inventory as unsupported-format diagnostics; known decoder
  support/dependency sidecars remain silent, and corrupt routed files remain
  distinct failure cases.
- Ignoring an extension is not a corruption filter. Supported routed members are
  always inspected; malformed members produce retained `ScanFailure` rows and
  scan-log entries. An archive may publish valid sibling tracks while preserving
  the failed member for retry and diagnosis.
- TAR.ZST listing and extraction stream `zstd -dc` into `tar`; ScanSong does not
  create a second full temporary TAR and does not close the producer pipe before
  the consumer finishes.
- Standard output contains JSONL events only, with explicit contract name,
  version, and monotonically increasing sequence. Progress diagnostics are
  rate-limited to phase changes, phase completion, or one event per second so
  output cannot bottleneck scanning.
- ScanSong operation progress uses one bounded presentation channel for Scan,
  Check Links, and Remove Links: the native app retains only the latest update
  and samples it every 250 ms on the main actor. Do not enqueue one GUI task or
  render one current file for every callback; progress presentation must not
  pace any worker operation.
- Scan progress is source-level: each loose file or archive is one work item;
  archive-member inspection updates detail/current-path only. Multi-root
  callers use the session scan API, which discovers every root once and then
  reports one stable aggregate source total.

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
- Archive extraction itself is serialized to one payload at a time. The
  per-archive expanded-byte limit therefore cannot multiply across the source
  pipeline. TAR.ZST archives use a cancellation-safe `zstd -dc` to `tar`
  pipeline for listing and extraction, without first creating a second full
  `expanded.tar`; stale scanner scratch roots older than one day are reaped
  when a new extraction begins. Extracted underscore aliases such as
  `_.ldat.txth` are normalized to the decoder's canonical `.ldat.txth` name
  inside disposable scratch storage.
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
  readable; ScanSong reports the condition and re-enables retry actions.
- Child archive processes are terminated when their task is cancelled. A
  standalone `name.ext.zst` or `name.ext.zstd` is admitted only when `ext` is
  a registered playable format; its basename is the single implicit member
  name, and Zstandard writes that one payload into disposable scan scratch.
  It is not treated as a complete dependency set. TAR.ZST remains the
  multi-member streaming tar path.
- Archive paths, symlinks, member count/name size, and expanded bytes are
  validated before records are accepted.
- Required adapters currently include libgme enumeration and timing, direct
  NSF/GBS header harvesting, in-process SPC ID666 and xID6 harvesting, PSF-style
  tags for PSF/QSF/GSF families, VGM/VGZ GD3 and timing reads, direct
  Commodore 64 SID PSID/RSID header reads, the
  Core Audio standard-audio inspector for FLAC/Vorbis comments and exact
  decoded duration (with AVFoundation metadata fallback for other ordinary
  audio),
  scanner-owned vgmstream CLI plugin for raw vgmstream formats, TXTP structures,
  and HD-bank structures, the scanner-owned
  Highly Complete inspection plugin for GSF/miniGSF, and OpenMPT tracker/module
  intake (S3M, MOD, IT, XM, MTM, STM, and related) as structurally-known single
  rows. ScanSong never invokes CocoaSpice's app or a player-owned helper. A
  missing executable is a typed adapter failure. The Highly Complete adapter creates a parser handle before reading
  metadata, so a miniGSF is rejected unless its extracted sibling dependencies
  resolve. GSF/miniGSF exposes exactly one validated track per file.
  Dependency-enumerated formats without their own plugin fail explicitly.
- GameCube intake is fixture-backed: primary DSP, ADP, AGSC, H4M, LDAT,
  LOGG, RSF, THP, and TXTP members route through the bundled vgmstream
  inspector. Extracted TXTH files, including archive-specific `_.ext.txth`
  aliases normalized to `.<ext>.txth`, and bank/data files remain dependencies
  and never become duplicate catalog rows.
- When a TXTP references an otherwise playable stream, the extracted stream is
  retained for decoder access but suppressed as a separate catalog member;
  the TXTP-authored mixing, subsong, and loop structure is authoritative.
- vgmstream extensions and admission roles come from VGMBoy's database-free
  `VGMBoyFormatCore`; ScanSong retains native inspection, archive handling, and
  schema-23 publication ownership.
- SNDH admission uses the direct `psgplay` route and the shared `VGMBoySNDH`
  metadata product. Each declared subtune becomes one scanner track with its
  SNDH timing and a contiguous zero-based `track_index`; every row repeats the
  file's declared `track_count`. The PSG engine is not started during metadata
  inspection. Playback selection is validated separately in VGMBoy because
  scanner publication alone cannot prove that a native subtune can restart.
- HES inspection applies a same-basename sibling `.m3u` when one is present.
  The playlist remains a non-track support file, while its authored track
  mapping and timing determine the HES rows published by the scanner.
- Native CLI inspectors share one bounded process runner with a 30-second
  deadline, 4 MiB stdout, 256 KiB stderr, concurrent draining, and cancellation
  termination. Decoder-family adapters remain separate files.

## Files

- [CatalogScanner.swift](/Users/john/Downloads/Code/VGMMan/ScanSong/Sources/ScanSongKit/CatalogScanner.swift)
- [CanonicalCatalogWriter.swift](/Users/john/Downloads/Code/VGMMan/ScanSong/Sources/ScanSongKit/CanonicalCatalogWriter.swift)
- [CanonicalCatalogSchema.swift](/Users/john/Downloads/Code/VGMMan/ScanSong/Sources/ScanSongKit/CanonicalCatalogSchema.swift)
- [CatalogLinkAuditor.swift](/Users/john/Downloads/Code/VGMMan/ScanSong/Sources/ScanSongKit/CatalogLinkAuditor.swift)
- [ScannerInspectors.swift](/Users/john/Downloads/Code/VGMMan/ScanSong/Sources/ScanSongKit/ScannerInspectors.swift)
- [InspectorProcessRunner.swift](/Users/john/Downloads/Code/VGMMan/ScanSong/Sources/ScanSongKit/InspectorProcessRunner.swift)
- [TXTPDependencyResolver.swift](/Users/john/Downloads/Code/VGMMan/ScanSong/Sources/ScanSongKit/TXTPDependencyResolver.swift)
- [ArchiveMemberEnumerator.swift](/Users/john/Downloads/Code/VGMMan/ScanSong/Sources/ScanSongKit/ArchiveMemberEnumerator.swift)
- [StandaloneArchiveExtractor.swift](/Users/john/Downloads/Code/VGMMan/ScanSong/Sources/ScanSongKit/StandaloneArchiveExtractor.swift)
- [ScanSongCommand.swift](/Users/john/Downloads/Code/VGMMan/ScanSong/Sources/scansong/ScanSongCommand.swift)
- [ScanSongApp.swift](/Users/john/Downloads/Code/VGMMan/ScanSong/Sources/ScanSongApp/ScanSongApp.swift)
