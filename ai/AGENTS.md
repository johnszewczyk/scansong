# AGENTS

## Engineering

- `ScanSongKit` is the single scanner implementation shared by every host.
- Keep the library independent of AppKit, SwiftUI, Electron, playlists, and host-owned databases.
- The `scansong` executable is a versioned JSONL process boundary and must keep stdout machine-readable.
- Do not add a runtime fallback to a host-specific scanner. Cut over only after parity tests pass.
- Scanner plugins return typed records and diagnostics; they never mutate a host database.

## Documentation

- `subsystem-human/` records sparse implemented behavior.
- `subsystem-agent/` records current ownership, invariants, concurrency, and failure boundaries.
- Keep current state only; do not add changelogs or planning notes.
