# Unicode 18.0.0 grapheme data

Official Unicode data for task 640. Sources and SHA256 hashes are recorded in
manifest.json. These inputs are fixed to version 18.0.0, not a mutable latest URL.
Redistribution is covered by the accompanying Unicode License v3 in LICENSE.txt.
The segmentation design targets UAX #29 revision 49. Display width remains at
Unicode 15.1.0 and is independent of these segmentation properties.

GraphemeBreakProperty supplies GCB, emoji-data supplies Extended_Pictographic,
DerivedCoreProperties supplies InCB, and GraphemeBreakTest supplies the official
conformance cases. Run `python scripts/make-grapheme-table.py --check` to verify
the generated product table and pinned input hashes. Run
`python tests/scripts/verify-graphemes.py --sigma PATH` to compare the public words
against every official test case.
`zig build test` also checks all official cases. The fixture is embedded only in
the core test executable, never in the product executable.
