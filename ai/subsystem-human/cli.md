# Command Line

## Probe

- `media-scan probe PATH...` examines files without writing a database.
- `--recursive` includes descendants of directory arguments.
- `--strict` returns failure when an input is unsupported.
- Output is one JSON object per line for direct use by applications and tests.

## Plugins

- `media-scan plugins` reports every registered format route and its structure and metadata policies.

## Catalog

- `media-scan catalog validate PATH` opens an existing canonical schema-23 catalog read-only and reports its path, attached-root count, and track count.

## Native Test App

- `MediaScanner` browses for an existing catalog, validates it read-only, and restores that selected path on the next launch.
- Add Files and Add Folder build a test input list without modifying the catalog.
- Test Scan reports live discovery/routing status and typed diagnostics.
- Cancel stops discovery or routing cooperatively and retains the input list.
- The current test scan does not publish catalog rows.
