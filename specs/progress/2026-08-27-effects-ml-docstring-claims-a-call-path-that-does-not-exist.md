# `lib/effects/effects.ml`'s docstring claims a call path that does not exist

**Filed**: 2026-08-25
**Found by**: the substantive claim audit of `specs/features/compiler-pipeline.md`
**Severity**: low (documentation-in-code; no runtime effect)
**Scope note**: found during a docs-only audit and deliberately *not* fixed there.

## The claim

`lib/effects/effects.ml` ends its doc comment on `check_capabilities` with:

```
    All paths (eval and compile) pass through this function via [bin/main.ml]. *)
```

and the module header says it is "the explicit call-site hook that runs on both
the eval and compile paths (see bin/main.ml)".

## Why it is false

`bin/main.ml` never calls `Effects.check_capabilities`. Reverse reference:

```
$ grep -rn "check_capabilities" lib bin test lsp forge
lib/effects/effects.ml:19:let check_capabilities ?(errors = ...
bin/main.ml:2611:     See also: March_effects.Effects.check_capabilities *)
test/test_codegen.ml:9419:  let ctx = March_effects.Effects.check_capabilities m in
test/test_codegen.ml:9428:  let ctx = March_effects.Effects.check_capabilities m in
```

The `bin/main.ml` hit is inside a comment. The only real callers are two
assertions in `test/test_codegen.ml`. `bin/main.ml` reaches capability
enforcement directly, through `Typecheck.check_module_full` →
`check_module_needs`.

`forge search --callers check_capabilities` agrees.

## Why it is worth fixing

Capabilities *are* enforced, so nothing is broken. But the comment makes
`effects.ml` look load-bearing when it is bypassed, which is the same trap
`lib/codegen/codegen.ml` set — a plausibly-named module that a reader assumes is
the implementation. Someone modifying capability enforcement could edit this
file and observe no behavior change at all.

## Suggested fix

Reword the doc comment to say what is true: enforcement lives in
`Typecheck.check_module_needs`; this module is a thin convenience wrapper used
by tests, not a pipeline stage. Alternatively, wire `bin/main.ml` through it so
the comment becomes true — but that is a behavior change and needs its own
decision, since `check_capabilities` calls `check_module` (not
`check_module_full`) and would duplicate the typecheck.

## Repro

```bash
cd <repo>
grep -rn "check_capabilities" lib bin test
# observe: zero non-comment callers outside test/
```

---

# Fixed 2026-08-27

Landed alongside Target A of
`specs/plans/2026-08-27-remaining-decomposition-targets.md`.

**Documentation only. Nothing was rewired** — the report's alternative ("wire
`bin/main.ml` through it so the comment becomes true") is deliberately not taken,
because it is a behavior change that would duplicate the typecheck.

The claim was re-verified before the edit, not assumed:

```
$ grep -rn "check_capabilities" lib bin test lsp forge js
lib/effects/effects.ml:19      the definition
bin/main.ml:1647               inside a comment
test/test_codegen.ml:9411,9419,9420,9428,9429   the only real callers
```

`lib/effects/effects.ml`'s header now says what is true: enforcement lives in
`Typecheck.check_module_needs`, which `check_module_core` calls unconditionally
(`typecheck.ml:7873`), so every path that typechecks a module enforces
capabilities; this module is a thin convenience wrapper used by tests, not a
pipeline stage. The `check_capabilities` doc comment's "All paths (eval and
compile) pass through this function via `bin/main.ml`" line is replaced by a
pointer to that header.

The sibling half of the same false impression is fixed too: `bin/main.ml`'s
"See also: March_effects.Effects.check_capabilities" now says explicitly that
this file does **not** call it. Left as a pointer rather than deleted — the
cross-reference is genuinely useful, it was only the implied call that was wrong.
