# Systematic native-bug hunt — ending the whack-a-mole

## Why we keep playing whack-a-mole

The depot native suite dies at the **first** crash. Each 5-minute iteration
reveals exactly one bug; fixing it reveals the next. Seven fixes in
(`4fdeda08`, `4c4762ad`, `fd520110`, `78e31ff7`, `9849c3b5`, `86c62b98`, plus
march#8 `0d18f46e`), the suite still crashes — now in `Depot.Query.execute →
go$apply` jumping to `0x1`. We have no idea whether 2 or 20 bugs remain,
because the harness can only show one at a time.

Every one of these bugs shares the same meta-shape: **the interpreter is
dynamically checked and correct; native is unchecked and silently corrupts.**
The interpreter is a reference implementation — we just haven't been using it
systematically.

## Taxonomy of the bugs found so far (the classes to hunt)

| Class | Root cause | Instances fixed |
|---|---|---|
| **A. Name-resolution hijacks** | Program-global, first-wins alias tables in `lower.ml` (`_use_aliases`); bare-vs-qualified asymmetry between typechecker / interpreter / lowering | `to_string`→`Bytes.to_string` (4fdeda08); `close`→`Db.close` (9849c3b5); test-local fn shadowed by import (march#8, 0d18f46e) |
| **B. Representation inconsistencies** | Repr (Boxed/Niche/Newtype) decided **locally at each emission site** from different type information (erased vs concrete; params present vs absent). Construct, match, eq, and to_string can disagree about the same value | erased tuple destructure folded to unconditional loads (4c4762ad); `__march_eq_Option_Any` boxed-on-niche (4c4762ad); `Option(Option(_))` None=null vs Some=boxed (86c62b98) |
| **C. Ownership/RC misclassification** | `borrow.ml owned_in` ad-hoc rules: closure captures, join points | `__try_call*` FV capture (fd520110); non-escaping join-point closures (78e31ff7) |
| **D. Closure/slot ABI confusion** | Uniform-slot convention (scalars low-bit tagged in ptr slots) vs raw fn-ptr/field reads; record fields holding closures | OPEN: `go$apply` jumps to `0x1` (= tagged 0 read as code ptr) in `Query.execute` |
| **E. Runtime fidelity gaps** | Native runtime helpers lack RTTI | `march_value_to_string` → `#<tag:N>` (documented, unfixed — Bug B in the repro repo) |

Classes A–C each produced multiple bugs. Any *new* crash is overwhelmingly
likely to be another instance of A–D, so the hunt should be **class-driven**,
not crash-driven.

## The plan

### Phase 1 — See the whole board at once (inventory tooling)

**1a. Crash-trapping test runner** (`runtime/march_runtime.c`).
`march_test_run` already converts panics into recorded failures via
`setjmp(march_test_jmp_buf)` + `march_test_fail_buf`. Extend the same seam to
hardware faults: under `MARCH_TEST_TRAP_SIGNALS=1`, install handlers for
`SIGSEGV/SIGBUS/SIGILL/SIGFPE/SIGABRT` that — when `march_test_in_test` —
format `CRASH: <sig>` into the fail buffer and `longjmp` into the existing
failure path. The suite then **continues past every crasher** and the final
report lists all of them in one run. (Outside a test: restore default handler
and re-raise, so non-test crashes still crash.) SIGABRT trapping also converts
RC-underflow `abort()`s into named failures. Caveat: after a caught SIGSEGV
the heap may be inconsistent, so *subsequent* results are advisory — the tool
is an inventory device, not a green-suite device; it changes no default
behavior.

**1b. Inventory workflow** (depot):
```
MARCH_TEST_TRAP_SIGNALS=1 .march/build/test/depot_test --verbose
  → complete list of ✗ CRASH tests + ordinary failures in ONE run
for each crashing test: lldb --filter=<name> → faulting frame
  → cluster by (faulting symbol, fault address pattern)
```
Fault-address patterns identify the class instantly: `0x8`/`0x10` = null+field
(repr, B); small odd (`0x13`, `0xd`) = tagged scalar deref (repr/hijack, A/B);
`0x1` as PC = tagged slot read as fn ptr (ABI, D); freed-pattern = RC (C).

### Phase 2 — Class-level static detectors (turn crashes into diagnostics)

**2a. Repr-consistency audit** (`llvm_emit.ml`, `MARCH_REPR_AUDIT=1`).
The Class-B bugs all reduce to: *two emission sites committed to different
encodings for the same type*. Record every commitment as it is made — EAlloc
(newtype / niche-null / niche-payload / boxed-fallthrough / boxed), emit_case
`effective_repr`, `ensure_adt_eq_fn` (niche vs boxed) — keyed by
`TypeName(payload-mangle | ?)`, and at end of `emit_module` print any key
group containing **mixed encodings**. Because it records the *actual*
decisions (not a re-derivation), it cannot diverge from codegen. Would have
flagged `Option(Option(String))`: `alloc:None → NicheNull` vs `case → Boxed`
in one build, no debugger needed.

**2b. Alias-ambiguity audit** (`lower.ml`, `MARCH_ALIAS_AUDIT=1`).
Class-A hijacks happen when a bare name resolves through the **global** alias
table while ≥2 distinct qualified candidates exist program-wide. Track all
candidates per short name; when `resolve_use_alias` falls through to the
global table for an ambiguous name, print `name → chosen (also: others)` once
per name. The per-module fix (9849c3b5) already corrected precedence; the
audit lists every remaining ambiguous resolution so hijacks surface at
compile time.

### Phase 3 — Fix by cluster (using phases 1–2 output)

Work the inventory **by class, not by test**: one fix per cluster, validated
against the 918-test compiler suite + the trap-mode depot run (whose crash
count must fall by the whole cluster, not by one).

Known-open clusters going in:
- **D:** `go$apply` @ `0x1` (`Query.execute` row-mapper closures / SqliteOps
  fn-valued record fields).
- **E:** `march_value_to_string` placeholder output (breaks `cast_record`
  change detection — depot-side `==` swap or runtime RTTI).
- Whatever else phase 1 reveals.

### Phase 4 — Prevention (keep the moles from coming back)

- **Checked-destructure mode** (`MARCH_CHECKED=1`): extend the shape-unproven
  panic (4c4762ad) to *every* ptr destructure — tag check before field loads,
  clean panic with function name on mismatch. Debug/CI builds run checked;
  release stays fast. Turns any future Class-B escape into a one-line
  diagnosis.
- **Differential testing in CI**: run the march test corpus + depot suite in
  both interpreter and native (trap mode), diff pass/fail sets; any
  divergence is a compiler bug by definition.
- **Repr single-source-of-truth** (larger refactor): compute each type's repr
  once post-mono into a table consulted by all emitters, instead of local
  re-derivation. Eliminates Class B structurally.
- **`Dynamic` type for reflection builtins** (`record_entries`/`record_get`):
  makes Class-B's favorite entry point (erased values matched at concrete
  shapes) a compile error.
- Property-based differential fuzzing (generate small March programs, diff
  interp vs native) — the long-term net.

## Deliverables now (this session)

1. This plan.
2. Phase 1a implemented + validated (918 tests; repro repo crash reported not
   fatal) — committed.
3. Phase 2a implemented + validated — committed.
4. Phase 1b executed on depot: the complete clustered inventory, written back
   into this file (Appendix A) + memory.
5. Phase 2b if budget allows; otherwise specced above.

## Appendix A — inventory results (2026-07-01)

**Round 1** (trap runner, first full pass ever): 1333 tests, **115 failures,
3 crashes** — vs. one-crash-per-5-minute-cycle before. Clusters:
- 77× `match failure` panics (the 4c4762ad guard firing — previously silent
  SIGSEGVs), unattributable (no fn name in message → fixed, see below);
- 22× `assertion failed`;
- 12× `record_entries/record_get: value carries no record shape metadata`;
- 3× SIGBUS (`Query.execute → go$apply` jumping to `0x1` — offset/limit tests);
- 1× `List.head: empty list`.

**Repr audit round 1**: flagged `Option` MIXED Boxed/Niche — and caught a bug
*introduced by* 86c62b98: erased (`Any`) payloads had `case=Niche` but
`alloc-None=Boxed`. Fixed (nullary alloc keeps niche for TVar).

**Repr audit round 2**: still flagged — 11 `alloc-some-boxed(?)` sites:
`Some(x)` with an erased-TVar arg was BOXED while every match/eq site is
NICHE → niche matchers read the box cell as the payload (silent garbage in
`alist_get`, `Repo.one/get_by`, `Query.first`, `nth_opt`, …). Fixed
(erased-TVar payload passes through raw, per the erased convention).

**Round 2** (after both audit-caught fixes, panics now fn-attributed):
1333 tests, **90 failures, 0 crashes**, repr audit **0 types flagged**.
- 71× match failure in `Depot.Schema.parse_field_spec` — ONE depot-source
  function (tuple-spec match on `record_entries` values; needs the bare-value
  arm, same as the SPEC.md column_sql fix);
- 6× match failure in `Depot.Migration.column_sql` (the documented SPEC.md
  depot-source bug);
- 12× record-shape-metadata (runtime gap: some record construction path skips
  `march_record_set_shape` — next compiler/runtime target);
- 1× `assertion failed` (singleton, uninvestigated).

**Net effect of the systematic pass**: 3 crash clusters + 25 silent-garbage
tests eliminated by two audit-caught compiler fixes (`f0fe40cc`); the
remaining board is 2 two-line depot fixes + 1 runtime metadata gap + 1
singleton. The whack-a-mole is over: every remaining failure is named,
clustered, and attributed.

**Round 3** (after the depot bare-spec arms in `parse_field_spec` /
`column_sql` / `parse_col_spec`): 85 failures — the 71-cluster *moved
deeper* to 74× "no record shape metadata" + a newly-visible 10× cluster
(`parse_one_assoc`, same bare-arm class) + 1 assert. Enriched the runtime
shape panic to self-diagnose the value (null / tagged imm / heap tag+rc):
all 74 were **tag=0 rc=1 heap cells**.

**Root cause of the 74** (lldb on one test): the C-side Option builders
`rec_some_k`/`rec_none_k` (march_extras.c) used BOXED cells for 'f'/'g'
kinds, while `record_get`'s March type is `Option(erased)` — decoded NICHE
by everything compiled. An absent 'g' field returned a boxed-None tag-0
cell that niche callers read as `Some(cell)`; the cell then flowed on as a
"record". **The C runtime helpers are a fourth repr-commitment site the TIR
audit cannot see.** Fixed: niche encoding for all kinds.

**Round 5** (niche C helpers + `parse_one_assoc` arm): **1333 tests,
1 failure** — one SIGSEGV: `__march_eq_Option_Float @ 0x8`. The mirror-image
boundary bug: concrete `Option(Float)` is BOXED (tag-load at +8), but the
value arrived in the erased-niche encoding (null None from `record_get`).
Fixed by a degenerate-value guard at the top of every generated boxed ADT
eq fn: ptr-equal → eq; null vs heap-cell → compare the cell's tag against
the NULLARY ctor; low-bit immediates → not-eq.

**Round 6 (final): 1333 tests, 1 failure, 0 crashes.** The residual is the
*documented-irreducible* niche edge case: `record_get(b, "ratio") ==
Some(0.0)` — the erased-niche encoding cannot represent `Some(0.0)`
distinctly from `None` (float bits 0 = null; repr.ml has always excluded
Float from niche for exactly this reason). A clean wrong-answer at one
precisely-known boundary, no longer a crash. Eliminating it requires the
phase-4 uniform-Option-encoding (or kind-aware erased decoders) — the top
candidate for the next deep session.

**Phase 2b implemented** (`MARCH_ALIAS_AUDIT=1`, lower.ml): every alias
registration records its candidate; a bare name resolving through the
GLOBAL fallback with ≥2 distinct candidates is reported once (the
registration-order-dependent hijack fingerprint). Depot run: **zero
findings** — the per-module precedence fix (9849c3b5) fully retired the
class; the audit now guards against its return.

**Final arc: pre-tooling = suite dies at first SIGSEGV, unknown bug count.
Post: 115 failures/3+ hidden crash clusters → 1 known-boundary failure,
0 crashes, repr audit clean, alias audit clean, in 7 instrumented runs.**
