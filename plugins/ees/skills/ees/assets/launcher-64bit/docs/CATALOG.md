# Engineering Tool Dialog catalog — 64-bit edition

The package includes the normalized Database22 Engineering Tool Dialog catalog: 813 routine records, 353 categories, 1,670 routine-category relationships, 1,586 keywords, 1,178 signatures, 7,448 parameter rows, and 50 UnitType definitions.

At runtime it is combined with metadata from the configured 64-bit EES installation. An `installed_metadata_match` is discovery evidence, not proof that all supporting dependencies are available.

During a controlled solve, the launcher passes `/AI` to EES so Component, Heat Transfer, Incompressible, Mechanical Design, and NASA are available for that run. Search results retain `required_load_directive` for portability to ordinary EES sessions.

Always compile-test a candidate. The installation test uses `/AI` to exercise routines from all five application libraries without `$Load` directives and verifies that the persistent profile autoload setting is unchanged.

Detailed normalization provenance is recorded in `payload\catalog\catalog-validation.json`.
