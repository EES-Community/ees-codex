# Engineering Tool Dialog catalog — 32-bit edition

The package includes a normalized machine-readable catalog derived from the authoritative `Database22.xlsm` Engineering Tool Dialog database. The catalog owner confirmed that Database22 is authoritative and that its derived metadata may be redistributed with this launcher.

## Coverage

The normalized catalog contains 813 routine records, 353 category rows, 1,670 routine-category relationships, 1,586 keywords, 1,178 signatures, 7,448 normalized parameter rows, and 50 UnitType definitions.

At runtime, the catalog is combined only with metadata from the configured 32-bit EES installation. Local-only routines remain searchable. `installed_metadata_match` means that local metadata lists the routine; it is not proof that every supporting library dependency is available.

## Recorded normalization

The source hash, row counts, and every structural normalization are recorded in `payload\catalog\catalog-validation.json`. The record covers case-only foreign-key normalization, one stray `Call ` prefix, one duplicated heat-exchanger signature, reversed parameter identifiers, shared function parameters, and one explicitly documented reconstruction of a missing fouling-factor routine row.

## Availability and `$Load`

Some EES libraries are installed but disabled by default. During a controlled 32-bit solve, this launcher passes `/AI` to EES so Component, Heat Transfer, Incompressible, Mechanical Design, and NASA are available for that run. Search and detail results still return `required_load_directive` when an exact symbolic directive makes a model portable to an ordinary EES session. The launcher permits four such directives: Component Library, Mechanical, NASA, and Incompressible.

Always compile-test a candidate routine against the installed 32-bit libraries. The installation test uses `/AI` to exercise routines from all five application libraries without `$Load` directives and verifies that the persistent profile autoload setting is unchanged.

Inspect catalog status with:

```powershell
& "$env:LOCALAPPDATA\EES-Codex-Launcher-32bit\Get-EES-Catalog-Info.ps1"
```
