# EES tool metadata — 32-bit edition

The package contains an exact release snapshot of the owner-maintained `EES_Tool_Metadata.json`, generated from the authoritative Engineering Tool Dialog database and redistributed with the owner's permission. The catalog helpers always search this packaged JSON. They never merge rows from another catalog or from the configured EES installation.

## Current snapshot

The packaged schema-version 1 file contains 813 routine rows, 353 categories, 1,673 routine-category relationships, 1,586 keywords, 1,184 signatures, and 7,524 parameter rows. Its SHA-256 is `A87F0FD43C68E514C824BA57BD69643D78BC10889137F3D21B086A8BCC8C40C4`.

The helper exposes 814 searchable routine views because the canonical file has one fouling-factor signature, category, and parameter set without a corresponding `Routines` row. It derives a clearly marked `signature_only` view from those same JSON rows at read time. It also resolves the file's two prefixed category links and shared parameter sets for `Notch_Sensitivity` and `gear_Lewis_factor`. These are in-memory relationship repairs only; they do not modify the source file or merge another catalog.

`Get-EES-Catalog-Info.ps1` reports the packaged path, hash, timestamp, schema version, and row counts. The file beside the selected 32-bit EES executable is read only to calculate `installed_metadata_match`; it is never a fallback catalog and its contents are never added to search results. That flag is discovery evidence, not proof that every supporting library dependency will compile.

## Compact and full output

Use compact output for initial discovery:

```powershell
& "$env:LOCALAPPDATA\EES-Codex-Launcher-32bit\Search-EES-Library.ps1" `
  -Query 'compressor efficiency' -Limit 3 -Detail Compact
& "$env:LOCALAPPDATA\EES-Codex-Launcher-32bit\Get-EES-Routine.ps1" `
  -RoutineID 'Compressor2_CL' -Detail Compact
```

Compact mode returns only the routine identifier and type, short description, primary syntax, required load directive, installed-metadata match, and deprecation or replacement information. Use `-Detail Full` for one selected routine when alternate signatures, parameters, keywords, categories, paths, hashes, or help references are needed. `Full` remains the default so existing calls still receive detailed output.

## Availability and `$Load`

During a controlled 32-bit solve, this launcher passes `/AI` to EES so Component, Heat Transfer, Incompressible, Mechanical Design, and NASA are available for that run. Search and detail results still return `required_load_directive` when an exact symbolic directive makes a model portable to an ordinary EES session. The launcher permits four such directives: Component Library, Mechanical, NASA, and Incompressible.

Always compile-test a candidate routine against the installed 32-bit libraries. The installation test uses `/AI` to exercise routines from all five application libraries without `$Load` directives and verifies that the persistent profile autoload setting is unchanged.

Inspect catalog status with:

```powershell
& "$env:LOCALAPPDATA\EES-Codex-Launcher-32bit\Get-EES-Catalog-Info.ps1"
```
