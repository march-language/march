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

- Make the insertion point skip a leading `--` comment block, so shape 1 reads
  the way a human would write it.
- The reverse order (`@[attr]` then `doc "..."`) is still a parse error. Either
  accept both orders or say so in `specs/lang/surface-syntax.md`; today the
  restriction is undocumented.
- A `forge/test` case that runs `forge fix --contracts` over a module whose
  functions carry docs and comments and then COMPILES the result. The existing
  case (`test_fix_contracts_inserts_and_is_idempotent`) uses a fixture with
  neither, which is why this survived.
