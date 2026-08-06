# Capability unforgeability (R3), and the `needs` coverage gap it uncovered

Status: **implemented 2026-08-05.** See
`specs/progress/2026-08-05-cap-unforgeability.md` for what actually landed.

Three claims below were wrong and are corrected in place, marked
**[corrected]** — the design said to cover a `let`-annotation position, an
`EAnnot` position and an alias right-hand side, and predicted the deferred
sweep would be sufficient on its own:

1. `EAnnot` and alias-RHS have no source spelling, so neither has a reject
   witness; both are covered defensively.
2. The deferred sweep alone was **not** sufficient — the value restriction was
   also required, or `let x = from_json(s)` generalizes and the recorded node
   never gets pinned.
3. The migration-cost estimate for Check B named three affected test sites; the
   real number was zero, because all three already sat under a covering `needs`.

Implements **R3** and pins **R4** from
`specs/2026-08-04-provable-sandbox-design.md`, which names R3 as the only item
on that page that closes a live hole and recommends doing it first regardless
of whether the rest of the sandbox work ever happens.

Companions: `specs/2026-08-03-forge-cap-audit-design.md` (artifact channel),
`specs/2026-08-04-path-scoped-capabilities-design.md`,
`specs/progress/2026-08-04-cap-ceiling-strict.md` (the ceiling).

---

## 1. What was measured

Every claim in this section was checked against the compiler built from
`7ad39a97`, not inferred from reading the source.

### R3's four bullets are not four vectors

R3 asks that `Cap(X)` be excluded from casts, deserialization, default
construction, and `from_json`-reachable field positions. Two of those have no
vector in March today:

| R3 bullet | vector |
|---|---|
| deserialization producing a `Cap` | **open** |
| `derive(FromJson)` producing a `Cap` | **open** |
| cast / reinterpretation (`Bytes` → `Cap`) | **none** — no `unsafe_cast`, `transmute`, `reinterpret`, or coercion builtin exists |
| default-value / zero construction | **none** — March has no default-value construction |

So R3 is two checks, not four.

### The deserialization hole

`to_json`, `from_json`, and `from_json_events` are each typed
`poly2 (fun a b -> TArrow (a, b))` — fully unconstrained — at
`lib/typecheck/typecheck.ml:2087-2094`. They are the only three builtins with
that type. This typechecks clean, `--cap-strict` included, exit 0:

```march
mod A1 do
  needs IO.Console
  fn main() do
    let forged: Cap(IO) = from_json("{}")
    let w: Cap(IO.FileWrite) = cap_narrow(forged)
    println("forged a cap")
  end
end
```

At runtime it fails with `from_json: cannot determine target type from JSON
value`. **That is not a defense.** It is the unimplemented return-type dispatch
tracked in `specs/todos/2026-07-31-from-json-return-type-dispatch-unimplemented.md`
— an open item to *build* that feature. The forge completes the day it lands.

The derive path is further along: `derive Json for T` where `T` carries a
`Cap` generates a codec over the cap position without objection (the
`encoder_for_ty` / `decode_value_at` fallback in `lib/desugar/desugar.ml:1585+`
treats an unrecognized type as "assume it also derives Json"), and the decoder
runs far enough to return a `DecodeError` rather than refusing to exist.

### The `needs` coverage gap (not in R3)

Check 1's decl walk (`lib/typecheck/typecheck.ml:8012-8060`) visits `DFn`
signatures, `DActor` handler signatures, and `DExtern` cap types, then ends in
`| _ -> []`. `cap_paths_in_surface_ty` (`:1854-1869`) likewise ends in
`| _ -> []`. Consequences, both verified accepting under `needs IO.Console`
with `--cap-strict`:

```march
let forged : Cap(IO) = ...                -- let annotation: uncovered
type Loot = { tok : Cap(IO.FileWrite) }   -- type-decl field: uncovered
```

A module can name a capability it never declared. Unlike the deserialization
hole this needs no unimplemented feature to reach.

This is a recurrence of a pattern that has produced several prior bugs in this
codebase: a wildcard arm in a capability decl walk that is "empirically inert
today" until it isn't.

**Nested modules are fine.** A `Cap` in a nested module's *signature* is
caught and attributed to the inner module, so `DMod` falling through the
wildcard is correct-by-construction, not a seventh hole. The exhaustive match
must say so in a comment rather than leave the next reader to re-derive it.

---

## 2. Design

Two checks over types, sharing one predicate.

### Check A — `Cap` is not a serializable type, in either direction

`Cap(X)` may not appear in:

- the argument type of `to_json`,
- the result type of `from_json` or `from_json_events`,
- anywhere in the declaration of a type `derive Json` is applied to
  (record field, variant argument, alias RHS).

**Why both directions.** Rejecting only decoding would leave `derive Json for
T` half-generated: a working encoder and a rejected decoder. Encoding a cap
leaks nothing at runtime — capabilities are opaque unit sentinels, and
`march_cap_narrow` is literally `return cap;` — but it manufactures the wire
value a decoder would consume. One symmetric rule is easier to state, easier
to test, and leaves no direction to put a hole in later.

**Hard error, unconditional.** Not gated on `--cap-strict`. Unforgeability is
not opt-in, and there is no legitimate reason to serialize a capability.
Check A's migration cost is zero: a repo-wide scan finds no stdlib type
declaration holding a `Cap` (only `extern "…" : Cap(Ffi)` blocks, which Check 5
already handles) and no `derive Json` over a cap-bearing type.

Check B's is near zero but not zero. A repo-wide scan finds exactly three
affected sites, all in tests and all the same shape —
`let _console : Cap(IO.Console) = cap_narrow(cap)` in
`test/native/main_cap_io.march`, `test/test_eval.ml`, and
`test/test_compiler.ml`. Each should already sit under a covering `needs`; if
any does not, that is Check B finding a real gap on its first run, and the fix
is to add the declaration, not to weaken the check.

**[corrected]** The real cost was zero: all three already sat under a covering
`needs`, and all four test suites passed unchanged.

**Two implementation sites, and they differ.**

*Derive* is eager. `derive Json for T` walks `T`'s declaration directly; no
inference is involved. The error is reported at the derive decl and names the
offending field.

*Call sites are deferred, and this is the load-bearing part of the design.*
`from_json`'s result type is frequently an unsolved `TVar` at the application
site, pinned only by later unification. A check at the application site sees a
bare var and passes. This is the same trap documented for `cap_narrow` at
`lib/typecheck/typecheck.ml:5490-5496` ("`a` is pinned by LATER unification").

So Check A records each `to_json` / `from_json` / `from_json_events`
application's relevant type var in an env-side list — mirroring the existing
`mint_cap_sites` mechanism — and runs a **deferred pass at end-of-module
checking**, zonking each recorded var then.

**[corrected]** Deferring is necessary but was *not* sufficient. Even with the
sweep in place, `let x = from_json(s)` let-generalizes `x` to `∀b. b`: every
use instantiates a fresh var pinned to that use's type while the single
recorded node stays unbound forever, so the sweep still read `TVar` and
reported nothing. The fix is `demote_to_monomorphic` on the instantiated arrow,
exactly as `cap_narrow` and `mint_cap` already do — that function's docstring
had already described this failure ("REOPENING the forge in every
let-/generic-flow position"). The deferred-zonk test caught it after the other
four reject cases were green.

### Check B — type declarations and `let` annotations are cap uses

Extend Check 1 past function signatures to:

- `DType` / `DAlwaysLinearType`: record fields, variant arguments, alias RHS,
- `bind_ty` on `let` bindings,
- `EAnnot` in expression position.

**[corrected]** Two of these are defensive only — they are walked, but no
source program can reach them, so neither has a reject witness:

- **alias RHS**: `type T = Cap(IO.FileRead)` parses as a VARIANT declaring a
  constructor named `Cap` (verified — `T` does not unify with `Cap(_)`), and
  `type T = (Cap(IO.FileRead), Int)` does not parse at all.
- **`EAnnot`**: the parser never produces one. Desugar synthesizes the sole
  instance, a hardcoded `SupervisorSpec` on an `app` block's spec field.

The reject witness for the container case (`List(Cap(X))`) took the alias
slot instead, and is better coverage: it is the shape a real evasion takes,
and it fails a walk that does not recurse through type arguments.

`type Handle = { c : Cap(IO.FileWrite) }` under `needs IO.Console` becomes an
error. The module cannot *obtain* a `FileWrite` by declaring that field, but it
can hold and pass one, which is exactly what the ceiling exists to make
visible — and it is how signatures are already treated.

Spans point at the annotation or field, not the enclosing function.

These positions also count as **uses** for the existing "declared but never
used" warning. Adding a covering `needs` must silence the error without
raising that warning in its place; otherwise the fix for one diagnostic
produces another and the check reads as broken.

**Both walks become exhaustive.** `cap_paths_in_surface_ty`'s `| _ -> []` and
the decl walk's `| _ -> []` are replaced by matches naming every constructor,
with an explicit `(* no cap position *)` — or, for `DMod`, `(* nested modules
get their own Check 1 pass *)` — where there is genuinely nothing to walk. A
future AST constructor should break the build, not silently open a hole.

**One deliberate limitation, stated rather than discovered.** A `let`-annotation
cap does **not** feed that function's `cap_closures` propagation. Signature
caps propagate to callers because they are the function's interface; a local
annotation is not, and wiring it in would widen the propagated ceiling in ways
this design has not measured. Check B reports the `needs` violation and stops.

---

## 3. Testing

Every case is an **accept/reject pair**. An accept-only witness cannot
distinguish a working contract from one that checks nothing — the failure mode
that shipped in the refinement-measure work — and only a test asserting
*silence* catches an over-broad check.

New cases extend the existing cap corpus (`specs/lang/types/{accept,reject}/`,
`t45`–`t63`).

### The test that decides whether Check A works at all

```march
let x = from_json(s)
let w = cap_narrow(x)      -- pins x to Cap(IO) only HERE, after the app site
```

An eager call-site check sees a bare `TVar` and passes this. If this case does
not fail before the fix and pass after, the deferred-pass mechanism is
unverified no matter what the other cases report. Write it first.

### Matrix

| | reject | matching accept — must be **silent** |
|---|---|---|
| **A** | `derive Json` over a variant with a `Cap` argument; over a record with a `Cap` field; `to_json` of a cap-bearing value; `from_json_events`; the deferred-zonk case above | `derive Json` for a cap-free type *in a cap-using module*; `from_json` producing an ordinary type |
| **B** | `Cap` in record field / variant arg / alias RHS / `bind_ty` / `EAnnot`, each under a `needs` too narrow to cover it | each with a covering `needs`, asserting no "declared but never used" warning either; plus `Cap(IO.Console)` under `needs IO` to prove subsumption reaches the new positions |

### R4 — regression pin, no production change

Attenuation is already monotone, measured both directions:

| | result |
|---|---|
| `Cap(IO.Console)` → `Cap(IO.FileWrite)` (widen) | rejected: `` expected `IO` but got `IO.Console` `` |
| `Cap(IO)` → `Cap(IO.FileWrite)` (narrow) | accepted |

This is enforced structurally through unification — `cap_narrow` demands the
*parent* `Cap(IO)` at its argument — not by a separate lattice call, and the
runtime `march_cap_narrow` is deliberate erasure. Do not "fix" the identity
function; do not write a property test over it.

The pin is an accept/reject pair over `cap_narrow` in both lattice directions,
next to `test_cap_scope.ml`'s subsumption tests. Justification for spending an
afternoon on behaviour that already works: the subsumption direction was
written backwards twice during the sandbox work and shipped once.

### Process notes

- `@types-check` asserts diagnostic **text**, and it is **CI-only** —
  `scripts/run-tests.sh` does not run it. Wording the new errors without
  running that alias locally is how this comes back red after looking green.
- Check B's errors reuse existing `needs`-coverage message text. Check A's two
  messages are new strings the corpus will pin.
- Run the full suite, not `-q`; the cap tests are not all quick.

---

## 4. What this does and does not earn

Completing this reaches **stage 1** of the sandbox design's ladder:

> "capabilities cannot be fabricated, only received and narrowed"

It does **not** touch ambient IO (R1), which remains the gap in a sentence:
*March has capability-safe machinery and does not point it at IO.* A module
still calls `file_read(p)` with no token in scope. Stage 1 is independent of
that and is not wasted if the effect-row work never happens.

It also does not close console egress (R8a), which no stage closes.
