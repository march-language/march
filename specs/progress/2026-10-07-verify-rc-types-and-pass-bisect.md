# DONE 2026-10-07: A1 checks 2 and 3, and A4 pass bisection and reduction

Observability plan (`specs/plans/incremental-codegen-cas-plan.md`) §6 checks 2 and
3, and §9. One PR.

## What landed

### Check 2: type consistency (`Tir_verify.check_types`, on by default)

It runs at every stage from `tir-mono` on, under `--verify-tir`. The kind table
comes from `Contract_pipeline.run` once the pipeline builds it (after Defun).
- **Call arity.** A direct call to a top-level function passes as many arguments
  as it has parameters.
- **Argument representation** (needs the kind table). Each argument's
  representation class equals its parameter's class: immediate, float, heap
  pointer, aggregate or vector. Erased types and apply functions are skipped.
- **Case arity.** A branch binds as many variables as its constructor has fields.
- **Field existence.** For a structural record, a named record type, and a
  closure struct's `$fvN` index.
- **No source-named type variable** in a monomorphised signature. The
  typechecker's erased `'_N` placeholders and drop glue are exempt.

A type whose short name is defined twice (`HttpServer.Conn` and
`WebSocket.Conn`) is skipped, because a reference may use either spelling.

### Check 3: RC balance (`lib/tir/tir_verify_rc.ml`, its own switch)

It runs at `tir-perceus` with the borrow map and kind table Perceus used. Every
path through every function is walked, and a count of the references the frame
holds is kept for each tracked object. Tracked means an unrestricted binding
whose type needs RC.

Findings:
- **over-release**: a `dec_rc` or consuming use when the frame holds no reference;
- **use-after-release**: a read after the last reference was released;
- **leak**, opt-in with `MARCH_VERIFY_TIR_LEAKS=1`: a reference still held at a
  path end or a case join.

Each finding names the object, its binding, and the path (`case kv: $Tuple2`).

The model encodes Perceus's own rules:
- borrowed parameters and call positions (`Borrow.is_borrowed`), including the
  last argument of a `$dps` destination-passing helper;
- `Lin` bindings;
- field projections, which borrow from the parent, using the field's type;
- the case handoff, with the scrutinee's dec at the head of an arm and constructor
  reuse;
- the payload-sharing case (`Kind.shares_payload`);
- a use whose atom type is untracked even when its binder's is (`i : '_` bound,
  `i : Int` at the call).

The emitter's case-handoff helpers moved from `llvm_case.ml` to
`lib/tir/case_handoff.ml` so the checker and the emitter share them. The IR
oracle shows the move changes no output.

**Switch.** `--verify-tir-rc` / `MARCH_VERIFY_TIR_RC=1` (each implies the
verifier). It is not under plain `--verify-tir` because it found three real
bugs, two of them in stdlib code every program links. With check 3 on, every
verified build fails until those are fixed
(`specs/todos/2026-10-07-perceus-releases-parent-before-field-use.md`).

### A4: pass switches, bisection, reduction

- **`lib/tir/pass_switch.ml`** names the optional passes. Seven run in the pipeline
  under `opt`. The Opt loop is `opt` as a whole, or `opt.<pass>` for one of its
  nine passes.
  - Mandatory passes have no switch.
  - `--disable-pass P1,P2` / `MARCH_DISABLE_PASS` turns passes off; `--list-passes`
    lists them.
  - The disabled set is in the CAS key (`nopass:...`).
  - This is a module-level set, not the `disabled` parameters the plan sketched.
    Every caller of `Opt.run` would otherwise need threading for the same effect.
- **`march --bisect-pass FILE [--expect OUT]`** compares against the
  interpreter's stdout and exit code, or against OUT. It checks two things
  before searching:
  - the default build is wrong;
  - disabling every optional pass makes it right. If not, it says no optional
    pass is the cause and points at `scripts/triage.sh`.

  It then shrinks the disabled set greedily, in pipeline order, to a 1-minimal
  set, so an interaction between two passes is reported as two passes. This
  deviates from the plan's "first single pass whose removal fixes it".
- **`march --reduce FILE --oracle CMD`** is delta debugging (ddmin).
  - CMD runs through `/bin/sh -c`, with `{}` replaced by the candidate's path or
    the path appended. Exit 0 means the candidate is still interesting.
  - It removes whole declarations first, level by level, re-parsing between
    levels, then single lines. The result goes to `FILE.reduced.march`.
  - The plan's expression-level rewrites (literal of the inferred type, inline a
    `let`, drop an unused arm) are not built. The oracle keeps candidates valid.

## Red

`test/test_codegen.ml` group `tir_verify`:
- **Check 2**: one hand-broken module per rule. The argument-representation case
  is also checked for silence without a kind table, and the named-tvar case for
  silence with erased variables and before mono.
- **Check 3**:
  - a balanced owned parameter is clean;
  - a double release;
  - a use after release;
  - a leak, which is silent unless leaks are asked for;
  - an over-release reported on its own arm's path;
  - the three real bugs below, through the real pipeline.

A4, proven by hand:
- With `Fold`'s `+` perturbed to add 1, `--bisect-pass` on a 6-line program named
  exactly `opt.fold`.
- On the string-match repro (a Perceus bug), it answered "no optional pass is the
  cause".
- `--reduce` on that repro, with a compiled-differs-from-interpreted oracle,
  reduced it to a smaller program that still miscompiles.

## Sweep: every check 3 finding classified (plan open question 5)

The sweep was 439 programs (`test/native`, `bench`, `test/snapshots/src`) with
`MARCH_VERIFY_TIR_RC=1`.

False positives, each fixed in the model:

| Finding | Why it was not a bug | Fix |
|---|---|---|
| `$trmc` cell passed to a `$dps` helper, then written | the destination is borrowed by protocol | the last argument of a dps call is borrowed; the dps parameter is held by the caller |
| a field read in tail position, typed `Int` | the field's own type decides tracking, not the projected value's | use the field type |
| a binder of a scrutinee used after an arm took the scrutinee over | the handoff moves the scrutinee's fields to the binders | orphan the scrutinee's children on takeover |
| `i : '_` released, then passed as `Int` | Perceus counts by the atom's type, which is untracked here | judge a use by the atom's own type |

Real bugs, filed in `specs/todos/2026-10-07-perceus-releases-parent-before-field-use.md`
with repros. Each compiled program gives different output from the interpreter:
- a string `match` on a field with a binder arm (`dispatch_a`/`dispatch_b` in
  `test/native/native_node_send_loopback.march`);
- a nested projection followed by the parent being consumed (`Topology` `offer_lines`
  and `drain_lines`);
- a record update from a `List.find` result (`Topology`'s desired-role merge).
  This one crashes with SIGTRAP.

Check 2 found one real bug: `Range.reduce` passes a curried lambda to a
two-argument fold (`specs/todos/2026-10-07-range-reduce-curried-callback.md`).
