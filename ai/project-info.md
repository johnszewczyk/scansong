# Project Info

## Product

`ScanSong` is the independent Swift package and native scanner app. `ScanSongKit` owns
discovery, inspection, archive handling, schema-23 catalog creation, resumable staging, and
publication. The product is the sole catalog writer consumed by CocoaSpice and SPCBoy.

## Major Components

- `ScanSongKit` — host-independent scanning and catalog engine.
- `scansong` — versioned JSONL command-line boundary.
- `ScanSong` — native catalog-management interface.
- `build-app.sh` and `launch.sh` — fresh packaging and launch boundary.

## Task Routing

- Scanner ownership and protocol: [scanner-contract.md](/Users/john/Downloads/Code/VGMMan/ScanSong/ai/subsystem-agent/scanner-contract.md)
- Per-plugin intake behavior: [format-accommodations.md](/Users/john/Downloads/Code/VGMMan/ScanSong/ai/subsystem-agent/format-accommodations.md)
- Build and plugin packaging: [build-integration.md](/Users/john/Downloads/Code/VGMMan/ScanSong/ai/subsystem-agent/build-integration.md)
- Command-line behavior: [cli.md](/Users/john/Downloads/Code/VGMMan/ScanSong/ai/subsystem-human/cli.md)
- Native catalog management: [catalog-management.md](/Users/john/Downloads/Code/VGMMan/ScanSong/ai/subsystem-human/catalog-management.md)

## Local Rules

- ScanSong is the sole schema-23 catalog writer.
- Player apps read the catalog; they do not receive scanner write access.
- ScanSong receives inspection executables from VGMBoy and never invokes a player frontend.
- Human notes describe implemented UI behavior; agent notes describe scanner ownership and failure boundaries.

## File-type policy and unsupported formats

ScanSong's Options window exposes the scanner's persisted **File Types** policy.
Checked extensions are skipped before discovery or archive-member routing. This
list is intentionally limited to families for which the current bundled
decoder set has no implementable scanner route:

| Extension | Family | Current status |
| --- | --- | --- |
| `.sgc` | Sega Game Gear / SGC | No established decoder in VGMBoy or the scanner. Do not route through vgmstream. |
| `.ncsf`, `.minincsf`, `.ncsflib` | Nintendo DS NCSF | Dependency-based Nintendo DS sound format has no usable decoder adapter. |
| `.mus` | Doom MUS | The Doom MUS members examined here are rejected by the bundled vgmstream path; no scanner decoder is available. |
| `.m3u` | Playlist wrapper | A playlist is not itself a playable scanner source; the referenced files are scanned independently. |

The default policy ignores those extensions and can be changed from Options so
future decoder work can be tested without changing catalog code. This is not a
generic error suppressor: supported families remain inspectable. For example,
`.ss2` is a supported vgmstream route, so a malformed Silent Hill PS2 member is
reported as an archive-member failure instead of being hidden.

The following previously failing vgmstream routes are now wired through the
scanner's bundled inspector: `.strm`, `.ahx`, `.bik`, `.bika`, `.msf`, `.xmd`,
`.txtp`, and `.hd`/`.hbd`/`.iecs`. TXTP dependency aliases are materialized
inside the extracted archive before inspection, including underscore-prefixed
TXTH aliases such as `_.ldat.txth`. Archive inspection keeps valid
members when another member fails, and records the failed member in the scan
inventory and result log. Archive members with genuinely unknown extensions are
retained as grouped `unrecognized` diagnostics; known decoder sidecars and
archive documentation remain quiet. Archive extraction is serialized to one
payload at a time, TAR.ZST uses a streaming `zstd -dc` to `tar` pipeline rather
than a second full temporary TAR, and stale scratch roots older than one day
are removed when extraction starts. Disposable scratch prefixes are removed
from failure messages before catalog persistence as well as log rendering.

## Current failure boundary

The latest JohnS report confirms these are different cases and must not be
collapsed into one ignored-format bucket:

- Game Boy `.gbs` in the Bakukyuu Renpatsu archive is rejected by the selected
  emulator route (`Wrong file type for this emulator`). It remains a decoder
  integration gap until the correct VGMBoy/Game Boy sound route is proven.
- SPC metadata is harvested in-process from the ID666 header and optional xID6
  chunk. Unknown xID6 item types are skipped after bounds validation, and
  binary/text ID666 layouts both contribute native timing without starting
  libgme for ordinary SPC metadata.
- PSF-style QSF/GSF tags are harvested directly, including authored length and
  fade values, before the required QSound/Highly Complete validation step.
  NSF/GBS fixed headers similarly provide game, author, and copyright text while
  libgme remains authoritative for their track timing and enumeration.
- VGM and gzip-compressed VGZ GD3/timing data are harvested directly with a
  bounded decompression limit; GYM and S98 remain on the libVGM route until
  their native metadata structures have fixture-backed readers.
- HES inspection applies a same-basename sibling `.m3u` when present. The
  playlist is not catalogued as a track itself, but it maps raw HES address
  slots to authored music/SFX tracks and their lengths.
- Silent Hill: Shattered Memories `.ss2` members fail to open. `.ss2` is an
  established route, so these remain visible archive-member failures and are
  not ignored.
- Silent Hill HD Collection `.hd` members fail to open through the current
  `.hd`/`.hbd`/`.iecs` adapter. The archive contains IECS `.hd` indexes with
  `.td` control data and separate `.msf` ATRAC streams, while the bundled
  vgmstream `hd_bd` reader expects a standard `.hd` plus `.bd` layout (or a
  combined `.hbd`). The `.msf` payloads open successfully, so this is a
  format-adapter gap rather than evidence that the audio is corrupt; keep the
  `.hd` failures visible until the matching IECS/`.td` adapter is added.

The last-result scan log uses uniform `status | detail | path` columns. Paths
are relative to the selected scanner root, including the `archive#member`
identifier for an archive error. Redundant member names are removed from the
detail column. Successful archive members are never listed; skipped archive
members are grouped by archive and extension. Unknown archive members use
`unrecognized` rows without becoming catalog candidates, while known support
files and extensionless archive material remain quiet.
Scan, Check Links, and Remove Links share one operation telemetry model in the
native UI: item progress, failure/missing counts, elapsed `HH:MM`/`HH:MM:SS`,
and completion time are reported uniformly.
The CLI progress stream is rate-limited to phase changes, phase completion, or
at most one progress event per second so diagnostics cannot become the scan's
throughput limiter.

## Human Docs

- `ai/subsystem-human/` contains the current catalog-management and command-line behavior notes.
- `README.md` contains the user-facing build and scanner overview.
