# `[P3]` Docs: the linear-types chapter tells readers to work around four fixed bugs

Filed 2026-09-13 from the probe sweep in
`specs/plans/2026-09-13-linearity-holes-plan.md` (step 1).

## The problem

`specs/lang/linear-types.md` and its drifted, served copy
`docs/linear-types.md` describe findings L1, L3, L4 and L8 as open, with
workarounds, and point at `specs/todos/`. None of the four has a todo file
any more. The slice-7 findings were filed in the old monolithic
`specs/todos.md` and didn't survive the split. All four now behave
correctly.

| finding | what the chapter says | measured on main `8eb0d7ee` |
|---|---|---|
| L1 | "there is no `affine` parameter keyword (the form `fn f(affine cap : T)` is a **parse error**)" | parses (`parser.mly`, `param: AFFINE …`) and checks: an affine param dropped on one branch is accepted |
| L3 | a parameter-bound record's double field access "degrades to a warning"; "Bind the record with a `let` first" | rejected: "The linear value `r.st` is used more than once here." (`check_fn`'s param loop registers field sentinels) |
| L4 | declaring a plain type named like a stdlib `always_linear` type (e.g. `Handle`) "silently makes your type linear" | a user `type Handle = Handle(Int)` bound and copied freely is accepted, as an ordinary type should be (`resolves_always_linear`) |
| L8 | a `linear` return type "does NOT currently propagate to a plain `let`"; a dropped `let h = open_file(p)` is "silently accepted" | rejected: "The linear value `h` was never used." |

## Where

`specs/lang/linear-types.md`:

- "Linear Let Bindings" paragraph (L8, ~l.92);
- "Affine Values", the "Spelling matters" paragraph (L1, ~l.100);
- "Linear Record Fields", the first caveat bullet (L3, ~l.143);
- "always_linear Types", the name-collision callout (L4, ~l.176);
- "Linear Types and Actors", the parenthetical "finding L6, `specs/todos/`"
  (L6 was resolved as a doc fix; drop the dangling pointer);
- "Practical Rules" 5 (L3) and 6 (L4).

`docs/linear-types.md` has the same claims without the finding numbers:
~l.113 (L1), ~l.153 and Rule 5 (L3), ~l.180 and Rule 6 (L4). Check its
let-binding section for L8 by reading it, not by grepping for "L8".

## What to do

- Rewrite each passage to describe current behaviour, and cite the corpus
  witness that pins it where one exists.
- **Before rewriting any claim, re-probe it on a freshly built compiler.**
  The table above was measured on `8eb0d7ee`, and a later change can move
  any row.
- **Leave Practical Rule 4 alone.** "Each branch must use it in a compatible
  way" is wrong in the other direction (the checker is laxer than it says),
  and which way it gets fixed is the open decision in
  [[2026-09-13-linear-consumed-on-one-branch-only]].
- Both trees are served. `scripts/check-docs.sh` must stay green.
