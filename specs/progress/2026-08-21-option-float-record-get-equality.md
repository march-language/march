# `let`-bound `record_get` result compares false against a concrete `Some(<float>)`

Residual of the fix in the same PR. The two directly-typed forms are FIXED:

```march
record_get(r, "z") == Some(0.5)                    -- inline: now true (was false)
let c : Option(Float) = record_get(r, "z")
c == Some(0.5)                                     -- annotated: now true (was false)
```

This one is still wrong compiled (`false`; interpreted says `true`):

```march
let d = record_get(r, "z")   -- NO annotation
d == Some(0.5)               -- compiled: false, interpreted: true
```

## Why

`record_get : a -> String -> Option(b)` with `b` fresh and unconstrained. An
un-annotated `let` generalizes the binding, so `d : Option('_)` survives into
TIR (confirmed in `MARCH_DUMP_TXT=perceus`: `let d : Option('_39927)`, while
the inline and annotated forms both read `Option(Float)`).

Codegen then keys `march_record_get`'s `expected_kind` off that type:

- `Option(Float)` -> kind `'f'` (102) -> runtime returns a BOXED Some cell.
- `Option('_)`    -> kind `'g'` (103) -> runtime returns the ERASED NICHE
  encoding (payload verbatim; see `rec_some_k` in `runtime/march_extras.c`).

The literal `Some(0.5)` is always built BOXED (`Option(Float)` is Boxed
because `niche_payload_ok TFloat = false`). So `==` compares a niche-encoded
value against a boxed one — and it dispatches to `__march_eq_Option_Any`
(chosen from `d`'s erased type), whose both-Some arm is a raw pointer compare.
It ends up comparing raw double bits against a heap box pointer.

This is a REPRESENTATION mismatch, not an equality bug: the same family as
#324 ("the erased/uniform boundary must agree on representation"). Note the
mismatch is Float-specific — for Int the erased form is the low-bit tag, which
is a bijection, so both encodings compare equal anyway.

## Candidate fix, and why it was not taken here

The typechecker already has this exact tool: `demote_to_monomorphic` (applied
to `cap_narrow`/`mint_cap` results) and `demote_vault_handle_vars` (applied to
`Vault` handles). Both exist because the RUNTIME REPRESENTATION is chosen once,
at the call site, so the result must not let-generalize. `record_get` has the
same property and arguably wants the same treatment: demoting its result
payload would keep `d` monomorphic, let the `==` pin it to `Float`, and make
the call site emit kind `'f'`.

It was not done in the same PR as the eq fix because it is a typechecker-wide
change with real blast radius — it would make ANY `record_get` result usable at
only one payload type across its whole scope, which could reject existing
stdlib/downstream helpers. That needs its own change, its own review, and a
full `dune runtest` + downstream sweep.

## Before changing any representation code here

`scripts/run-tests.sh` does NOT run the `test/native/*.expected` goldens —
they are dune rules, so only `dune runtest` covers them. A green
`run-tests.sh` is not evidence. An earlier attempt (reverted in #315) made
every `TFloat` ctor field a boxed `ptr` and regressed six goldens
(`float_generic_field_abi`, `record_pattern`, `native_arr_map2_inline`,
`native_arr_map_inline_{capture,float_box_reuse,unboxed}`) to garbage doubles
and wrong arithmetic. Boxing is the convention only for a field DECLARED
generic; a field declared concrete `Float` is an inline double.

---

## RESOLVED (2026-08-22) — the value restriction, as this file predicted

The "Candidate fix, and why it was not taken here" section above is what
shipped: `record_get` now gets `demote_to_monomorphic` on its result, in the
same `infer_expr` arm style as `cap_narrow`, `mint_cap` and `from_json`
(`lib/typecheck/typecheck.ml`). Nothing in `lib/tir` changed — `llvm_ty`,
`field_load_llty`, `ctor_field_llty` and `llvm_case`'s extraction are untouched,
so the six goldens #315 regressed (`float_generic_field_abi`, `record_pattern`,
`native_arr_map2_inline`, `native_arr_map_inline_{capture,float_box_reuse,unboxed}`)
never came into it. They pass.

### It was generalization, and generalization here was unsound anyway

Confirmed directly rather than inferred. Against the unfixed compiler:

```march
let d = record_get(r, "z")
let u : Option(Float)  = d
let v : Option(String) = d
```

typechecked and ran. One stored field has one representation; reading it at two
payload types only type-checked because the erasure hid the contradiction. That
program is now correctly rejected ("expected `String` but got `Float`"), which
is the real content of the fix — the `==` answering `false` was the symptom.

### Blast radius, measured rather than guessed

The reason this was deferred out of #324 was fear that demoting would reject
existing helpers. In-repo there are no `record_get` callers in `stdlib/` at all,
and `dune runtest` is green. The cost is the one this file already named and
`from_json` already pays: a single `record_get` application can no longer be
used at two different payload types.

### Test

`test/native/record_get_let_bound_eq.march` + `.expected`, wired into
`test/dune` next to the rest of the erased/uniform family. Inline, annotated and
un-annotated `let` forms of `Float`; the same binding consumed by `match`; a
missing key; and an `Int` control. The fixture's header records why the Int rows
cannot carry the test: for `Int` the erased form is the low-bit tag, a
bijection, so both encodings compare equal and an Int-only fixture passes
against the broken compiler.

RED, against the unfixed compiler (line 3 is the un-annotated `let`):

```
  1  true|true
  2  true|true
  3  true|false      <- d == Some(0.5)
  ...
```

Interpreted was `true` throughout, which is what `.expected` was generated from.
GREEN: zero diff.
