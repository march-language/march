# DONE 2026-09-22: `forge fix --contracts` places the attribute where it parses

## What was actually wrong

Re-measured on origin/main (`bfb22f1e`) before changing anything, with a fixture
covering every shape of leading prose: the fix is `FInsert { after_line =
decl_span.start_line - 1 }`, and `decl_span` starts at the `fn` keyword (the
`DOC STRING [attrs] fn_decl` rules keep the inner `fn_decl` span), so whenever
`fn` starts its own line the attribute already lands directly above it: BELOW a
`--` comment block and AFTER a `doc` string. That is legal
(`DOC STRING attrs fn_decl`) and is how the stdlib writes it by hand
(`stdlib/array.march:346-348`, `stdlib/hamt.march:188-189`: comment, then
attribute, then `fn`).

Shape 1 below (`@[no_alloc]` ABOVE the comment) was not forge's output. The
cube_forge commit `c3298fd` shows what happened: forge put the attribute
between `doc` and `fn`, which did not parse before the 2026-09-03 grammar fix,
and the workaround turned each `doc` into a `--` comment and left the
attribute above it (`lib/cube_forge/chunk.march` `get_or_air`,
`f32buf.march` `clear`, and others in that diff). So "skip the leading comment
block" needed no change; the new test pins the placement (comment, attribute,
`fn`).

The position that really did NOT parse was a `fn` that shares its line with
what precedes it: `doc "..." fn f(...)` (and `@[attr] fn f(...)`). The line
above is then in front of the `doc`, so the fix produced

```
                                      @[no_alloc]
  doc "The doc on the fn's own line." fn same_line_doc(b : Box) : Box do
```

which fails with "I got stuck here" on the `doc` (attribute-before-doc is the
reverse order, a parse error). It also indented by `start_col`, so both inline
shapes got an attribute indented 20+ columns.

## Fix

`bin/main.ml` `contract_attr_fix`: read the declaration's source line (from
`src`, or `read_file` for a `MARCH_LIB_PATH` sibling, same as
`cap_ceiling_fix_indent`). If the text before `fn` is only whitespace, keep
the line-above `FInsert` and use that whitespace as the indent. Otherwise emit
a one-line `FReplace` of the empty span at the `fn` column with
`"@[no_alloc] "`, so the result is `doc "..." @[no_alloc] fn f(...)`: after
the `doc`, after any existing attribute, directly before `fn`. `forge fix`
already applies single-line `FReplace`s. The LSP quick fix
(`lsp/lib/code_actions_diag.ml`) already inserts at the `fn` column, so it was
never affected.

## Verification

New `forge/test/test_build_check.ml` case "documented and commented fns:
result compiles" (`contracts_documented_module`): six reuse-candidate
functions (two-line comment block, doc, comment+doc, doc+comment, same-line
doc, same-line attribute). It checks the fixture itself with `march --check`,
requires `--report-contracts` to name all six, runs `Cmd_fix.run
~contracts:true`, then `march --check`s the RESULT (exit 0), asserts each
attribute's exact placement, and asserts a second report is empty and a
second fix run is a no-op.

- Red control (origin/main `bin/main.ml` swapped in by copy):
  `dune build --root . @forge/test/runtest` exit 1, only this case failing:
  `ASSERT the fixed file does not check (rc=1)` / `I got stuck here:` /
  `41 |   doc "The doc on the fn's own line." fn same_line_doc(...)`.
- Green: `dune build --root . @forge/test/runtest` exit 0 (22/22 in the
  build-check suite); `scripts/run-tests.sh -q compiler` exit 0 (covers
  `test_alloc_contract`'s `--report-contracts` `after_line` assertion).

---

The original todo, kept for history:

# `forge fix --contracts` inserts attributes into positions that do not parse

Found 2026-09-03 while re-running the `@[no_alloc]` sweep over `~/code/cube_forge`
with a dev compiler. Reproduced identically with the compiler at
`1eb43d39` (i.e. it is not a regression from the unboxed-aggregate /
transient-contract work), on 15 declarations in that project.

`--report-contracts` emits its fix as
`FInsert { after_line = decl_span.start_line - 1; text = indent ^ attr }` —
"the line above the declaration". Two shapes put something else on that line.

## 1. A leading `--` comment — FIXED for the attribute, still misplaced

```march
  -- Skylight at a world coordinate; 0 outside the world.
  fn light_at(w : World, x : Int, y : Int, z : Int) : Int do
```

becomes

```march
  @[no_alloc]
  -- Skylight at a world coordinate; 0 outside the world.
  fn light_at(...)
```

This parses (comments are stripped by the lexer) but reads badly: the
attribute is separated from the declaration it applies to by prose about the
declaration. The insert should land above the comment BLOCK, not inside it.

## 2. A `doc` string — did not parse at all, now does

```march
  doc "Replace the world's skylight field."
  fn set_light(w : World, la : NativeU8Arr) : World do ... end
```

became

```march
  doc "Replace the world's skylight field."
  @[no_alloc]
  fn set_light(...)
```

which was a hard parse error: `decl` had `DOC STRING fn_decl` and
`attrs fn_decl` as separate productions and no rule combining them, in EITHER
order, so a documented function could not carry an attribute at all — by hand
or by tooling.

**The grammar half of this is fixed** (2026-09-03): `decl` gained
`DOC STRING attrs fn_decl`, with the same attribute-payload validation as the
attributes-only rule. Menhir's conflict count is unchanged at 11.

## Still to do

Trimmed 2026-09-09: the "reverse order... undocumented" bullet that used to
sit here is done — `specs/lang/surface-syntax.md:753-754` now states the
order explicitly ("A `doc` string comes FIRST, then the attributes, then the
declaration... the reverse order is a parse error"). The two remaining
bullets are still open; re-verified `forge/test/test_build_check.ml`'s
`contracts_module` fixture (used by `test_fix_contracts_inserts_and_is_idempotent`)
still has neither a doc string nor a leading comment on any function.

- Make the insertion point skip a leading `--` comment block, so shape 1 reads
  the way a human would write it.
- A `forge/test` case that runs `forge fix --contracts` over a module whose
  functions carry docs and comments and then COMPILES the result. The existing
  case (`test_fix_contracts_inserts_and_is_idempotent`) uses a fixture with
  neither, which is why this survived.
