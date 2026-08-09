# Attribution ownership: nested modules, actor handlers, and the prelude

Landed 2026-08-08, on top of the ceiling default (#225). Closes
`specs/todos/2026-08-08-actor-handler-attribution-charges-entry-module.md` —
and the todo's diagnosis turned out to be HALF the bug.

## The todo's half: bare actor-handler names

A handler lowered from `actor Weeble ... on Zorp` is named `Weeble_Zorp` —
bare by contract (the spawn symbol and the HCR manifest both assert the short
spelling), so `Cap_attrib`'s name-derived `owner_of` charged every nested
module's handler to the entry module.

Fix: `lib/tir/handler_owner.ml`, a side table lowering populates (nested
DActor arm, using the module prefix in scope) and attribution consults before
the name-derived fallback. Reset in `lower_module` alongside the other
cross-pass tables; `MARCH_DEBUG_HANDLER_OWNER=1` traces register/lookup.

## The half the todo missed: the prelude

Fixing the handler table changed nothing on the reproducer. The debug trace
showed why: the console capability sat one frame LOWER, in `println$String` —
the PRELUDE wrapper. Prelude declarations are unwrapped into the entry
module, so their TIR names are bare, `owner_of` resolves them to the entry
module, and the entry module is exempt from module-level transparency by the
never-see-through-the-entry rule. Consequence, measured: **any nested module
reaching IO through any prelude wrapper was charged to the entry module** —
no actors required:

```march
mod NestOuter do
  mod Inner do
    needs IO.Console
    fn log_it() do println("hi") end
  end
  fn main() do Inner.run_it() end
end
-- pre-fix: module `NestOuter` uses `IO.Console` ... (Inner's needs useless)
```

Fix: `attribute` gains `?transparent_fns` — per-FUNCTION transparency,
deliberately not subject to the entry guard. bin/main.ml passes the
stdlib-span top-level `DFn` names (the prelude), matched on the bare
`$`-stem so mono suffixes don't defeat it and a user's `MyMod.println` is
never caught. The responsible-owner walk now steps through prelude wrappers
to the true calling module — which for a handler is the handler fn, whose
owner the side table supplies. Both halves are needed; either alone leaves
the reproducer red.

## Why the sweep and suite missed this for so long

Nearly every corpus program is a single module, where "charge the entry
module" is the right answer by coincidence. The nested tests that did exist
used `file_write` — a raw builtin, attributed at the calling function, no
wrapper frame — so they exercised the prefixed-name path and passed. The gap
was only visible to a nested module using a *wrapper*, which is exactly what
real user code does first (`println`).

## Witnesses

- `cap_ceiling`: "nested actor handler covered by declaring module" (RED
  before the fix), and the negative direction re-pointed to typecheck (the
  handler's direct `println` is caught by Check 1b before the ceiling runs,
  naming `Inner` — the property that matters).
- The HCR fixture (`test_stdlib_suite.ml`) dropped its compensating
  `needs IO.Console` on `Outer`; the fixture compiling without it is now
  regression surface for the side table.

## Same branch: the SBPL drift test exists now

`test/test_cap_sandbox_profile.ml` — bin/main.ml's embedded `--cap-sandbox`
profile vs `forge` `Cap_sandbox.profile_for`, compared as normalized clause
SETS (equality both directions, minus forge's explicit launch-target read
which the embedded profile cannot express), plus both polarities of the
conditional grants so two builders that stopped consulting the capability
set would still fail. A non-triviality floor (≥10 clauses) keeps a broken
clause parser from certifying two empty lists. bin/main.ml's comment had
claimed this test existed since 2026-08-03; it did not, until now. Closes
the third bullet of `specs/todos/2026-08-03-cap-sandbox-remaining.md`.
