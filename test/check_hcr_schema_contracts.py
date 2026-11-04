#!/usr/bin/env python3
"""Print the contract part of the fixture actors' .schemas.json entries.

The schema file also lists every stdlib actor the prelude links in, so only
the fixture's two actors are printed, one line per recorded fact, for
test/native/hcr_schema_contracts.expected to pin.
"""
import json
import sys

schemas = json.load(open(sys.argv[1]))
for actor in ("Tally", "Odd"):
    s = schemas.get(actor)
    if s is None:
        print(f"{actor}: MISSING")
        continue
    print(f"{actor}: contracts={s.get('contracts')}")
    for key in ("invariant", "invariant_unsupported", "refine_unsupported"):
        if key in s:
            print(f"{actor}: {key}={s[key]}")
    for f in s["state_fields"]:
        print(f"{actor}: field {f['name']} refine={f.get('refine')}")
    for h in s.get("handlers", []):
        print(f"{actor}: handler {h['name']} refines={h.get('refines')}")
