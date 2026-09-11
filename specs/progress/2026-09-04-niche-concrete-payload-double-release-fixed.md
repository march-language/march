# FIXED 2026-09-04 — double release of a non-generic niche payload, and the
# aggregate field-read inc it was masking

**Root cause.** `Drop.droppable_ctors` classified types through
`Repr.repr_of_ty`, which reads an Option-shaped type's payload out of the
TCon's type PARAMS:

```
| Some [ (_nullary, []); (_single, [_]) ] ->
  (match params with
   | [p] when niche_payload_ok .. -> Niche ..
   | _ -> Boxed)          <- a NON-GENERIC type has params = [], lands here
```

A user-declared `type Wrap = W(String) | Z` is non-generic, so it fell back to
`Boxed` — but codegen classifies it with `Repr.niche_repr_of_concrete`, which
exists precisely for "a NON-GENERIC Option-shaped ADT", and emits the NICHE
encoding. Under a niche `W(x)` IS `x`: one cell, not two. The deep drop
synthesized off the Boxed answer,

```
case x of W(f) -> let freed = march_decrc_freed(x) in
                  case freed of True -> drop f
```

therefore released the same pointer twice. Generic `Option(String)` was never
affected — its payload rides in `ty_args`, so `repr_of_ty` sees `[p]` and says
Niche correctly. That is why this survived: it needs a user-declared
non-generic type.

**Pre-existing on main**, independent of the aggregate-RC work: verified 6/6
crashes with a compiler built from the commit BEFORE any of it.

**Fix.** `droppable_ctors` now consults `niche_repr_of_concrete` for a
`TCon (n, [])` and declines to synthesize a drop when it reports Niche —
i.e. it asks both predicates and refuses if either says the payload shares the
box's storage.

**Second fix, unblocked by the first.** `insert_rc_expr`'s `EField` arm no
longer runs an aggregate source through `find_inc_vars`. That inc had no
matching dec for a borrowed parameter, so a record passed to a field-reading
helper never reached refcount zero. This exclusion had been tried and reverted
once, because the double release above surfaced the moment the inc stopped
masking it.

**Measured.**

| shape | before | after |
|---|---|---|
| `W(String) \| Z` in a 1000-iteration loop | 6/6 crash | 6/6 clean, correct output |
| record passed to a field-reading helper, 1000 iterations | 2001 live objects | **1** |
| record built and read in one scope | 1 | 1 |

**Verification.** Full suite green — 975 / 273 / 593 / 878 / 61 / 24 / 354 / 5 /
36 / 10 / 7 / 609 across 12 suites, zero failures, including Slow and the
z3-backed refinement cases. Corpus sweep 186 ok, 0 RC underflows. Reuse-neutral:
whole-program `EReuse` counts unchanged at 1134 / 1133. TIR snapshot diff is
exactly the two unbalanced incs disappearing.

**Regression test.** `test/native/niche_concrete_payload_drop.march` plus its
`.expected`, wired as a native golden in `test/dune`. Note these goldens run
under `dune runtest`, NOT under `scripts/run-tests.sh` — which is why the
crashing `record_pattern.march` sat green through several full suite runs, and
why the compile-and-run corpus sweep was what caught it.

---

## Original investigation notes

`[P1]` Aggregate RC: the `EField` inc on an aggregate source blocks the drop for
borrowed record parameters, but removing it breaks niche-represented payloads

## The knot

`insert_rc_expr`'s `EField` arm runs its SOURCE through `find_inc_vars`. That
function documents its atoms as sitting at CONSUMING positions, and a field
projection is not one — so on the face of it the aggregate should be excluded,
the way the `EUpdate` base now is.

It cannot be, yet. The two halves pull opposite ways and both are measured.

## Half 1 — keeping the inc blocks the fix for borrowed record params

`find_inc_vars` emits the inc when the source is live after the projection,
which is always true for a BORROWED parameter (borrowed params are seeded into
the live-at-exit set). Nothing in the callee decs it, and the caller's single
dec only undoes the allocation, so the cell's refcount never reaches zero.

Visible in `test/snapshots/perceus/borrowed_field_escape.expected`:

    fn peek(b : { inner : String }) : String =
      let $rc_1 : String = inc_rc b;
    b.inner in ...

Measured: a 1,000-iteration loop that builds a `{ n : Int, s : String }` and
passes it to a field-reading helper leaks 2,001 objects. The same loop WITHOUT
the helper (reading the field inline) leaks 1. Passing a record to a function
that reads its fields is an ordinary shape, so this is most of the remaining
gap for non-tail-recursive code.

## Half 2 — removing the inc corrupts memory on niche payloads

`test/native/record_pattern.march` dies with a NONDETERMINISTIC SIGBUS (138) or
RC-underflow abort (134) — the mode varies run to run — on the second call to:

    type Wrap = W({ rate : Float, code : Int }) | Z
    fn wrapped(w : Wrap) : String do
      match w do
        W({ rate: 1.5, code: c }) -> "exact " ++ int_to_string(c)
        W({ rate: r, code: _ })   -> float_to_string(r)
        Z                         -> "z"
      end
    end

Minimal repro: two calls, the first taking the literal arm, the second the
fall-through arm. The ONLY TIR difference is the two removed
`inc_rc $f<payload>` before the field reads.

Isolated to the representation: adding a third constructor (`| Z | Y`), which
forces BOXED representation, makes the identical program pass. `Wrap` with two
constructors is NICHE-shaped, so `W(r) ≡ r` — the payload binder and the
scrutinee are one cell, which the function does not own.
`add_scrutinee_free_for` already declines to free a niche scrutinee
(`scrutinee_shares_payload_storage`); the incs were the remaining thing keeping
that shared cell alive across the callee.

## What the masked bug actually is (narrowed 2026-09-04)

It is a genuine HEAP CORRUPTION, pre-existing, that the incs merely hide. With
the aggregate inc suppressed:

- `lldb` stops in `libsystem_malloc`'s `_xzm_xzone_malloc_freelist_outlined`
  with `EXC_BREAKPOINT` — malloc's own freelist-corruption detector.
- Roughly half of runs instead hit the runtime's guard with a GARBAGE refcount:
  `march: RC underflow (rc was -6048672674068485440) at 0xba8c00900`. A wild rc
  value means the dec landed on something that is not a live heap header.

Trigger, minimised (`Wrap = W({rate : Int, code : Int}) | Z`, two calls):

| calls                      | result |
|----------------------------|--------|
| literal arm only           | ok     |
| fall-through arm only      | ok     |
| literal, then fall-through | **ok** |
| fall-through twice         | CRASH  |
| literal twice              | CRASH  |

So it needs the SAME match arm to execute twice — a per-arm object is released
twice — and it does not matter which arm. Two hypotheses are already excluded:

- **Not Float-specific.** The original fixture used `rate : Float`; an all-`Int`
  record reproduces identically.
- **Not the static-closure path.** Capture-free join-point closures are interned
  as immortal globals with rc = 2^40 (`Llvm_ctx.intern_static_closure`), so
  decrementing one is harmless by design — and the minimised repro emits no
  `$static_clo` at all; its join-point closure is a real `march_alloc(32)`.

The remaining suspect is the join-point closure chain that a literal-pattern arm
builds (`$jp_clo_b = alloc $Clo(..., $jp_clo_a)` followed immediately by
`dec_rc $jp_clo_b`, whose deep drop releases `$jp_clo_a` while the enclosing
scope may still hold it). That is a hypothesis, NOT established — verify before
acting on it.

## Why a targeted guard is not obvious

The `EField` arm cannot see the niche-ness: its source is the payload binder,
typed as the RECORD (`{ rate : Float, code : Int }`), not as `Wrap`. The
information needed — "this binder aliases a scrutinee the function borrows" —
lives at the `ECase` that bound it.

## Direction

Mark a niche/newtype payload binder as borrowed at the `ECase` that binds it
(the natural companion to `scrutinee_shares_payload_storage`), so it lands in
`borrowed_field_vars`. `find_inc_vars ~include_borrowed_fields:false` then
suppresses the inc for it specifically, and the aggregate exclusion can be
applied to every other source without touching the niche case.

Verify with BOTH witnesses, since either alone is satisfiable on its own:
- `test/native/record_pattern.march` must exit 0 across repeated runs (the
  failure is nondeterministic — one clean run proves nothing).
- The borrowed-param loop above must drop from 2,001 to ~1 live objects.

## Measurement note

`.march/cas/artifacts-v2` MUST be cleared between compiler variants when
bisecting this. An earlier bisect of exactly this bug produced three mutually
contradictory results because cached artifacts were reused across compilers.
Also check that the experimental edit BUILT: making a binding unused turns into
a warning-as-error, dune fails, and the previous binary silently answers.
