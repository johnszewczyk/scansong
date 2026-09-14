# Project Info

## Product

`ScanSong` is the independent Swift package and native scanner app. `ScanSongKit` owns
discovery, inspection, archive handling, schema-23 catalog creation, resumable staging, and
publication. The product is the sole catalog writer consumed by CocoaSpice and SPCBoy.

## Major Components

- `ScanSongKit` — host-independent scanning and catalog engine.
- `VGMBoyFormatDataCore` — dependency-free byte readers supplied by VGMBoy for
  AY, NSF/GBS/NSFE/SAP, and HES/M3U metadata that does not require a playback
  decoder.
- `MetaManCore` — shared decoder-independent metadata reading for APE,
  SID PSID/RSID, SPC ID666/xID6, S98, VGM/VGZ, and PSF/PSF2/SSF/USF/2SF tag
  footers. ScanSong maps neutral documents to schema 23.
- `scansong` — versioned JSONL command-line boundary.
- `ScanSong` — native catalog-management interface.
- `build-app.sh` and `launch.sh` — fresh packaging and launch boundary.

APE (`.ape`) is a supported single-track route. MetaMan reads its container
timing and native tags in-process; ScanSong adapts the neutral document and
does not link VGMBoyKit, invoke a decoder, or transcode the source. VGMBoy
retains FFmpeg for playback.
GSF/miniGSF and QSF/miniQSF also use ScanSong-owned, in-process readers for
container validation, dependency chains, tags, and authored timing. They do not
start mGBA/Highly Complete or the QSound playback core. Those cores remain in
VGMBoy for playback. Scanner inspectors use VGMBoy's narrow inspection target;
scanner-plugin preparation does not invoke the broad playback dependency
builder or prepare mGBA/QSF as scanner build-time collateral.
CRI ADX headers and native loop timing are also read in-process by ScanSong;
the vgmstream helper remains for other streams and non-CRI/Monster payloads
that reuse `.adx` (including Ogg and RIFF).
Sony CD-XA sectors and interleaved subsongs are also read in-process; unrelated
formats using `.xa` remain on the vgmstream route.
Atomic Planet AUS headers now provide codec-independent timing and loop data
in-process; non-AUS payloads with the `.aus` suffix retain the vgmstream route.
Recognized Sony MSF headers are likewise read in-process, including codec-based
sample/loop timing and stream names; `MSF ` and other non-Sony aliases remain on
the vgmstream route.
Known Konami and SNK SVAG headers are also read in-process, with unrelated
`.svag` signatures retaining the vgmstream route.

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
scanner's bundled inspector: `.strm`, `.ahx`, `.bik`, `.bika`, `.xmd`, `.txtp`,
and `.hd`/`.hbd`/`.iecs`. TXTP dependency aliases are materialized
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
- SPC metadata is harvested in-process by MetaManCore from text/binary ID666
  headers and optional xID6 chunks; dump date, dumper, emulator, soundtrack, and
  native timing facts remain available in the shared document. The ScanSong
  projection retains the established catalog values, including the 150-second
  default for valid tagless files. Production targets do not link or invoke
  libgme for SPC inspection; VGMBoy keeps libgme for playback.
- MetaManCore reads PSF-style `[TAG]` footers and authored length/fade hints
  for PSF/PSF2, SSF, USF, and 2SF without starting their playback plugins.
  GSF/miniGSF use a ScanSong-owned PSF v0x22/container reader that validates
  compressed payloads and the dependency chain while preserving authored tags
  and timing; mGBA remains playback-only. QSF/miniQSF use a ScanSong-owned PSF
  v0x41/container and QSound block reader that validates sibling QSFLib
  dependencies and extracts tags/timing without playback code.
  NSF/GBS use a
  dependency-free header route for enumeration and native text metadata; their
  formats do not contain authored per-track names or timing, so the reader
  preserves libgme's unknown intro/loop/fade values and 150-second default
  play-length policy without starting playback. NSFE uses the matching
  dependency-free chunk route, including playlist, labels, authors, and
  authored time/fade values.
- VGM and gzip-compressed VGZ GD3/timing data are read through `MetaManCore`;
  GD3 release date, converter, notes, both language variants, and original tag
  bytes are exposed. VGZ expansion is bounded in MetaManCore. ScanSong preserves
  its existing notes-only comment projection. S98 v0-v3 header, device, tag,
  and command timing are also read through `MetaManCore`, with the full ordered
  tag set and original block preserved. A v3 `DATE` is exposed independently
  from `YEAR`; direct timing uses the actual header loop offset for intro
  duration. A test-only libvgm oracle records these known improvements
  separately from regressions.
  GYM remains a legacy structure-known libVGM route without scanner metadata;
  it is not a MetaMan migration target.
- HES inspection applies a same-basename sibling `.m3u` when present. The
  playlist is not catalogued as a track itself, but it maps raw HES address
  slots to authored music/SFX tracks and their lengths.
- SAP inspection uses the Foundation-only `SAPFormatDataReader` for subsong
  count, header identity, and per-track `TIME` hints; finite times become play
  lengths and `LOOP` times become intro-to-loop positions. SAP no longer uses
  libgme in ScanSong. AY inspection uses the Foundation-only
  `AYFormatDataReader` for signed relative-pointer metadata, native subtune
  ordering, and per-track 50 Hz lengths. AY corpus parity covers all 1,175 files
  in the Project AY fixture archive. SAP corpus parity covers all 6,335 local
  ASMA files; no SAP rows were present in the inspected CocoaSpice catalog.
- Silent Hill: Shattered Memories `.ss2` members fail to open. `.ss2` is an
  established route, so these remain visible archive-member failures and are
  not ignored.
- Silent Hill HD Collection `.hd` members fail to open through the current
  `.hd`/`.hbd`/`.iecs` adapter. The archive contains IECS `.hd` indexes with
  `.td` control data and separate Sony `.msf` ATRAC streams. The direct MSF
  reader opens those streams, but vgmstream's `hd_bd` reader expects a standard
  `.hd` plus `.bd` layout (or a combined `.hbd`). The `.hd` files therefore
  remain a format-adapter gap rather than evidence that the audio is corrupt;
  keep their failures visible until the matching IECS/`.td` adapter is added.

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
