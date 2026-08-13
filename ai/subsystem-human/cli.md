# Command Line

## Probe

- `media-scan probe PATH...` examines files without writing a database.
- `--recursive` includes descendants of directory arguments.
- `--strict` returns failure when an input is unsupported.
- Output is one JSON object per line for direct use by applications and tests.

## Plugins

- `media-scan plugins` reports every registered format route and its structure and metadata policies.
