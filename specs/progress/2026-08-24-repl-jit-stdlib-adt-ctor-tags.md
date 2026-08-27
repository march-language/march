# REPL JIT: every stdlib ADT constructor was built with tag 0 (fixed 2026-08-27)

Filed as a `[P3]` rendering nit — `Logger.Warn` and `Http.Post` both printing
`= #<tag:0>` — with the filing itself asking to check whether the wrong tag
also reached `match` before fixing it. **It did.** This was a silent
wrong-answer bug in the default REPL, not a display defect:

```
                                                          JIT     interp
match Logger.Debug do Debug -> 0 | Info -> 1 | Warn -> 2 | Error -> 3 end
                                                            0        0
match Logger.Info  do ... end                               0        1
match Logger.Warn  do ... end                               0        2
match Logger.Error do ... end                               0        3
match Http.Post do Get -> "get" | Post -> "post" | _ -> … end
                                                        "get"   "post"
```

Every stdlib constructor compared equal to the first arm. Both cold and warm
cache; `MARCH_REPL_INTERP=1` was correct throughout.

## Root cause

Confirmed as filed, and one step wider than filed.

An expression fragment is its own LLVM module, and `Llvm_toplevel.build_ctor_info`
numbers constructor tags from exactly the `~types` list that fragment is emitted
with (`ctx.loaded_tir_types @ tir.tm_types`). A name that misses falls through
to `ctor_entry`'s default, `ce_tag = 0`. So a missing `type_def` does not
degrade to "unknown" — it silently asserts "variant 0", for the constructor
being **built** and for every `match` arm it is **compared** against.

`Repl_jit.precompile_stdlib` never put stdlib's `type_def`s anywhere a fragment
could see them, on either path:

- **Cache hit** (the common path): dlopens `~/.cache/march/stdlib_prelude_*.so`
  and reads the `.names` companion, deliberately never lowering stdlib to TIR —
  that is the entire point of the cache. No stdlib `type_def` exists in the
  process at all.
- **Cache miss**: *does* lower stdlib, passes `tir.tm_types` as the prelude
  fragment's `~types`, and then drops the list on the floor. So a cold session
  mis-tagged identically to a warm one. The filing assumed only the hit path was
  affected; it was both.

Nothing reached `ctx.global_type_defs` either, which is why the printer showed
`#<tag:0>` rather than a constructor name.

## Fix

A third companion file next to the `.so`, `stdlib_prelude_<hash>.types`: a
Marshal'd `Tir.type_def list` holding **exactly** the `~types` list the `.so`
was compiled with. On a cache hit it is read back and installed into both
consumers of constructor numbering — `ctx.loaded_tir_types` (codegen's input)
and `ctx.global_type_defs` (the printer's table). The miss path now installs the
same list after its own dlopen succeeds.

Order is load-bearing and preserved verbatim: `build_ctor_info` is first-wins
and order-sensitive, and the colliding-type path (`reserve_global_tag`) hands
out global tags in list order, so a re-derived or differently-ordered list would
disagree with the already-compiled prelude. The list is cached, never rebuilt
from a partial lowering.

All three files are now required for a hit; a missing or unreadable `.types`
falls through to the recompile branch, which is why it is read *before* the
`.so` is adopted. The existing error handler additionally clears
`loaded_tir_types` / `global_type_defs`, matching what it already did for
`compiled_fns`: two copies of the list would make first-wins numbering depend on
which arrived first.

### Cache keying

The prelude key already digests `content_hash ^ "|" ^ compiler_id`, where
`compiler_id` is the compiler executable's size + mtime (added when a
mismatched-codegen prelude was loaded twice while fixing the mutual-TCO gap).
Any compiler carrying this change therefore already keys differently from one
that predates it, so a pre-change `.names`/`.so` pair can never be paired with a
new-shape reader. The filename prefix also gained a generation tag —
`stdlib_prelude_O1_tln2_` → `stdlib_prelude_O1_tln2_ty1_` — so the format
dependency is stated rather than left to that side effect. Bump `ty1` whenever
the companion-file set or its encoding changes.

## The second half: "tag = index in the ctor list" is not true

Registering stdlib's type_defs fixes evaluation and immediately breaks the
*previous* fix's regression test — `type Color = Red | Green | Blue` typed at
the prompt started printing `#<tag:33554506>` where it had printed `Green`,
while `match Blue do … end` still answered `3`. Correct tags, wrong decode.

The cause is a real consequence of the fix, not a mistake in it. Stdlib already
declares two types with the short name `Color` (a bare `Color` and
`Plot.Color`), so once stdlib is in the list the short name is a *collision* —
and a prompt-declared `Color` joins it, and `build_ctor_info` deliberately
numbers colliding types (and actor-message types) from global counters at
`0x0200_0000` / `0x0100_0000` rather than 0..n-1, so two same-named types'
constructors can never share a tag. The printer had `List.nth_opt ctors tag`
hard-coded — an assumption that was true only while every type it could see
was an ordinary one.

Rather than reproduce the counters in the printer, the numbering is now
computed once and shared: `Llvm_toplevel.variant_ctor_tags` returns
`type_name -> tag list` for a `type_def list`, and `build_ctor_info` *consumes
it* — so the two cannot drift, and the IR oracle proves the extraction is
faithful. `repl_jit` derives the same table from `ctx.loaded_tir_types` (the
list, not the unordered `global_type_defs` table — the numbering is
order-sensitive) and maps tag back to constructor through it.

## The rendering half: bare vs. module-qualified type names

Fixing the tags fixed evaluation but not all of the printing, and the reason is
a separate mismatch that the missing type_defs had been hiding:

`Lower` registers a module-nested type under its qualified name
(`"Logger.Level"`, `"Http.Method"`), but the TIR type referring to it — an
expression fragment's `fn_ret_ty`, or a constructor's declared field type — is
spelled with the **bare** name (`"Level"`, `"Method"`). Every printer lookup is
by exact name, so while no stdlib type was registered the mismatch was
invisible; both spellings missed. With them registered it decides more than the
name shown: `is_raw_word_ty` missing the lookup reports "heap cell" about a
niche/enum type's raw word, and the printer then dereferences an integer.

`canonical_type_name` / `qualify_ty` resolve a bare name to its registered key
before any lookup in `pp_heap_value` and `is_raw_word_ty`. Exact match wins; a
suffix match is accepted only when **unique**. Display only — codegen's own
numbering is keyed by the type-qualified ctor name `Lower` emits and never goes
through this.

`Http.Post` now prints `Post`. `Logger.Warn` still prints `#<tag:N>`, because
four stdlib types are named `*.Level` (`Logger`, `Compress.Gzip`,
`Compress.Zstd`, `Compress.Brotli`) and the resolution refuses to guess between
them. That is deliberate: guessing would print a confidently wrong constructor
name. The real repair is for `Lower` to spell the TCon with the same qualified
name it registers the `type_def` under — a change to emitted IR, out of scope
for a REPL-plumbing fix, and worth its own item.

## Verification

- Witness above, JIT vs `MARCH_REPL_INTERP=1`, cold **and** warm cache, under a
  private `HOME` (the shared `~/.cache/march` has produced phantom results).
- `scripts/ir-oracle.sh check` against a baseline recorded with the pre-fix
  binary: **IR IDENTICAL across 241 programs**. This is the load-bearing check
  on the `build_ctor_info` extraction, which is the one edit outside the
  REPL/JIT plumbing.
- `test/run_eval.exe`'s *JIT: nullary ctor tags of a REPL-declared type* — the
  previous fix's regression test — is what caught the tag-decode half. It went
  red on the first version of this fix and is green now.

## Tests

`test/test_jit.ml` → `repl_session` → *stdlib ADT ctor tags, cold and warm cache
(JIT)*, plus an interpreter parity control. Drives a real `march` REPL
subprocess (the JIT is never exercised by `Test_helpers.repl_eval_exprs`, which
drives the tree-walking interpreter directly — the same reason the earlier
nullary-ctor fix needed a subprocess test). Runs the session **twice against the
same HOME** on purpose: the first may build the prelude cache, the second is
guaranteed to hit it, and the hit path is the broken one.

All four `Logger` levels are asserted together. Checking only `Debug` would pass
on the broken build, since `Debug` is variant 0 and answered 0 by luck.

Verified to fail on the pre-fix binary by a file-copy swap of
`_build/default/bin/main.exe` (`= 0` four times, `= "get"`, `= #<tag:0>`).
