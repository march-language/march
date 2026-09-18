# FIXED 2026-09-18: `forge publish` no longer certifies an unannotated return-type change as a PATCH

This is the dangerous half of `specs/todos/2026-07-31-forge-semantic-semver.md`.
That todo stays open for the other half (below).

## The bug

`forge/lib/resolver_api_surface.ml` diffs public signatures as rendered text. A
public function with no return-type annotation renders `return_raw = ""` on both
sides, so its return type was invisible to the diff. Changing

    fn size(xs : List(Int)) do List.length(xs) end

to

    fn size(xs : List(Int)) do "many" end

broke every caller, and `forge publish --old-source` certified it as a PATCH.

## The fix

This is the "cheaper guard" from `specs/2026-09-18-forge-p1-design.md` §3. Each
`fn_sig` now also carries `clauses_raw`: the whole definition, rendered by the
formatter (`Format.emit_fn`) with the doc string removed and no comments. When
a public function's parameters and (absent) return annotation are unchanged but
`clauses_raw` differs, `diff` reports the new change `UnverifiableFn`. That
change counts as MAJOR, and the message names the function and explains that a
return-type annotation gives a precise verdict. This works the same way an
unparseable file already does: a surface the diff cannot see is not certified.

- **Sound.** The guard only ever refuses; it never certifies anything new.
- **No noise for annotated code.** An annotated function whose body changes is
  still a PATCH.
- **No noise for edits a caller cannot observe.** Layout, comments and the doc
  string are excluded from `clauses_raw`.
- **Noise it does add.** Any body change to an unannotated public function of a
  package at 1.0.0 or later now needs a major bump. (Before 1.0.0, enforcement
  is skipped entirely, as before.) Adding the annotation is itself a signature
  change, so it costs one major release, and later body changes are then judged
  precisely.

## Verification

`forge/test/test_api_surface.ml`, group `unannotated-return`, with real sources
through `extract_from_string`:

- `size` changing from returning an Int to returning a String requires MAJOR,
  and the message names `size` and suggests the annotation. RED before the fix:
  the verdict was `Ok` for 1.0.0 → 1.0.1.
- An annotated body change is still a PATCH.
- An unannotated reformat, plus a doc string and a comment, is still a PATCH.

## Still open

The false MAJOR, where renaming a parameter or a type variable reads as a break,
and precision for unannotated functions both need a comparison of inferred types
rather than text. That is `specs/todos/2026-07-31-forge-semantic-semver.md`.
