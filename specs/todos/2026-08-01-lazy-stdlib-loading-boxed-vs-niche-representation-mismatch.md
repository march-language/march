# Lazy stdlib loading silently miscompiles niche-eligible generics (class bug, confirmed live 2026-08-01)

`[P1]` - [ ] **Any stdlib module NOT in `bin/main.ml`'s `stdlib_file_list` can silently
miscompile a generic `Option`/`Result`-returning function when called at a
concrete niche-eligible type — wrong VALUE, no diagnostic, compiled only.**

## Root cause

A module outside `stdlib_file_list` is only reachable via
`Module_registry.ensure_loaded` (`lib/modules/module_registry.ml:227`), which
parses + desugars it purely to extract export **shapes** for typecheck's
qualified-name resolution — the body is never run through full type
inference in the context of its caller. When such a module exports a generic
function like `ConsistentHash.get(ring: HashRing(a), key: String) : Option(a)`,
monomorphization reaches the call site with the callee's return type still an
unresolved `'_` tvar, can't specialize the callee body, and falls back to a
generic (`Boxed`) representation for the `Option`. But the *caller*, compiled
with a concrete type (e.g. `Option(Int)`), expects the **niche** encoding
(payload stored inline, no box) — so the caller reads the discarded box's
heap address as if it were the payload.

This is the same bug class already point-fixed twice before (see the
`deque.march` comment history in `bin/main.ml` and
`specs/progress/2026-06-23-codegen-hardening-niche-match-on-an-unresolved-scrutinee-type-lib.md`,
which hardened `emit_case` to recover niche shape from branch constructors
when the **match site itself** has an unresolved scrutinee — but that fix
only covers matches occurring *inside* a lazily-loaded module's own body. It
does not cover the case here: a boxed value **crossing a call boundary**
into code that was compiled expecting the niche encoding.

## Confirmed live 2026-08-01

Minimal repro (HEAD `504aa60d`, before this todo's accompanying fix):

```march
mod Main do
  fn main() do
    let r0 = ConsistentHash.new(3)
    let r1 = ConsistentHash.add(r0, "node-a", 42)
    let r2 = ConsistentHash.add(r1, "node-b", 99)
    match ConsistentHash.get(r2, "hello") do
    Some(v) -> println("SOME " ++ int_to_string(v))
    None -> println("NONE")
    end
  end
end
```

- Interpreted: `SOME 42` (correct).
- Compiled (`march --compile`): `SOME 2197058856` / `SOME 2176234792` /
  `SOME 20306724416` — a different garbage pointer value on every run, no
  crash, no diagnostic.
- Control: the identical pattern through `Map.get` (Map IS in
  `stdlib_file_list`, i.e. eagerly loaded) returns `SOME 42` consistently
  across repeated compiles and runs.

## What was done today (point fix only, not the class fix)

Audited every `.march` file under `stdlib/` against `stdlib_file_list` and
found 6 files that were silently excluded (beyond the deliberately-excluded
`lazy_niche_probe.march`, a regression fixture that MUST stay excluded — see
its own doc comment): `compress.march`, `consistent_hash.march`,
`dist_link.march`, `dist_supervisor.march`, `ring_buf.march`,
`work_dispatch.march`. All export at least one generic `Option`/`Result`
function over a would-be-niche-eligible type. Added all 6 to
`stdlib_file_list` (`bin/main.ml`), matching the exact precedent set by the
`deque.march`/`cluster_load.march` fixes. Re-ran the `ConsistentHash` repro
post-fix: `SOME 42` consistently across 3 runs.

**This is a point fix for 6 known instances, not the class bug.** Any stdlib
module added in the future that is *not* added to `stdlib_file_list` (an easy
mistake — nothing enforces the list is exhaustive over `stdlib/`) reintroduces
this exact failure mode. Two structural fixes were proposed in the original
merge-loss todo and remain the real options:

1. Make lazy loading (`ensure_loaded`) typecheck enough of the callee body to
   resolve the caller's binders — i.e. give lazy modules real type inference,
   not just export-shape extraction.
2. Make monomorphization refuse to emit a call it could not specialize
   (compile error) instead of silently falling back to a generic/boxed body
   that then disagrees with a concrete caller's representation choice.

A cheaper, immediate guardrail worth adding regardless of which structural
fix is chosen: a test or doc-lint asserting `stdlib_file_list` (+
`js_only_stdlib_file_list`) is exhaustive over `stdlib/*.march` **except** an
explicit allowlist (currently just `lazy_niche_probe.march`) — so this can
never again silently reintroduce itself as more stdlib modules are added.

## Provenance

Split out of `specs/todos/2026-07-24-merge-loss-round-2-14-commits-on-docs-core-march-types-skeleton.md`,
which first named this class bug (found while auditing a lost-commit branch)
but never independently reproduced or scoped it. This file supersedes that
bullet.

---

# Implementation spec (added 2026-08-03)

Do these in order. Step 1 is an afternoon and stops the bleeding permanently; steps 2-3 are
the class fix and can follow at leisure. Doing 2 or 3 first, without 1, leaves the door
open the whole time.

## Step 1 — the exhaustiveness guardrail (do this first, regardless)

Measured on `origin/main` today, `stdlib_file_list` **is currently exhaustive**, with
exactly four files on disk absent from it:

| File | Why absent | Where it belongs |
|---|---|---|
| `dom.march`, `canvas.march`, `audio.march` | JS-only | already in `js_only_stdlib_file_list` |
| `lazy_niche_probe.march` | regression fixture that MUST stay lazy | explicit allowlist |

So the invariant to lock in is exactly:

```
{stdlib/*.march}  ==  stdlib_file_list
                    ∪ js_only_stdlib_file_list
                    ∪ {lazy_niche_probe.march}
```

Write it as a test in `test/test_compiler.ml` (not doc-lint — this is a property of a
compiler data structure, and it must fail the build). Read the directory at test time; do
not hardcode a count, or the test becomes the thing that goes stale.

**The failure message is the deliverable.** Someone adding a stdlib module a year from now
will hit this test with no context, so it has to say: *this file is not in
`bin/main.ml`'s `stdlib_file_list`; a module outside that list is loaded for export shapes
only, and a generic `Option`/`Result` it exports will silently miscompile to a wrong value
at a concrete niche-eligible type — add it to the list, or to the allowlist here if it is
deliberately lazy and you have understood that consequence.*

Non-vacuity check: remove one entry from `stdlib_file_list` and confirm the test fails.
The list is exhaustive today, so a broken test would otherwise pass silently forever.

## Step 1 — DONE 2026-08-03

`stdlib_file_list` / `js_only_stdlib_file_list` moved to
`lib/modules/stdlib_manifest.ml` (a library, so a test can reach them) alongside a new
`lazily_loaded_allowlist`. Two tests in `test/test_compiler.ml` under `stdlib-manifest`:
the manifest is exhaustive over `stdlib/`, and every manifest entry has a file behind it
(a phantom entry would silently load nothing). Non-vacuity confirmed by removing
`consistent_hash.march` and checking the failure carries the full explanation, not just a
diff.

## Step 2 — measurement taken 2026-08-03; the naive predicate is REFUTED

The fallback is `lib/tir/mono.ml`, the `subst = []` branch of the `EApp` case. Its own
comment names the conflation: *"No specialization needed (monomorphic or unresolved TVar
args)"*. Those are two very different situations sharing one branch.

Instrumented it temporarily and measured:

| Corpus | Fallbacks | With `args_unresolved=true` |
|---|---|---|
| 11 bench programs | 0 | 0 |
| 46 golden conformance programs | 8 | **1** |
| the `ConsistentHash` repro, module removed from the manifest | 8 | **1** |

The repro's risky hit is exactly the miscompiling call —
`ConsistentHash.get callee_poly=true args_unresolved=true` — and the binary prints
`SOME 2174096712`. So the site is right and the instrumentation finds the bug.

**But the golden corpus's one risky hit is benign.**
`CRDT.ORSet.union_tags` in `g44_crdt_convergence.march` also reports
`args_unresolved=true`, and its compiled output is byte-identical to its interpreted
output. So `args_unresolved=true` **cannot** be the error condition: erroring on it would
break a passing golden test that is not miscompiling.

This confirms the thing the spec flagged as the real content of the fix, with a concrete
counter-example to test against: the predicate must be *the caller's chosen representation
differs from the callee's*, not merely *specialization failed*. `union_tags` is the case
where the fallback is correct because caller and callee agree; `ConsistentHash.get` is the
case where they do not.

Next step for whoever picks this up: work out where the caller's representation choice is
observable at that point in `mono.ml` (`lib/tir/rc_types.ml`'s niche-eligibility logic is
the likely source), and gate the error on the disagreement. The two programs above are
your accept/reject pair — `g44_crdt_convergence.march` must keep compiling, and the
`ConsistentHash` repro must become a compile error.

## Step 3 — give lazy modules real inference (option 1, only if step 2 proves too coarse)

Option 2 from the original analysis, and the one to take: **monomorphization refuses to
emit a call it could not specialize**, rather than falling back to a generic boxed body
that then disagrees with a concrete caller's representation.

The bug is not that specialization failed; it is that failing was indistinguishable from
succeeding. Today the fallback produces a program that runs and prints garbage — no crash,
no diagnostic, different garbage per run. A compile error naming the call site and the
unresolved type variable turns a silent wrong-value class into a build failure.

Where: `lib/tir/mono.ml`, at the point where a call's callee type still contains an
unresolved tvar and the generic body is selected. Two things to establish before writing
the error, because they decide whether this is viable:

1. **How often does the fallback fire legitimately today?** If a large corpus compiles
   with hundreds of unspecialized calls, an error is a non-starter and this becomes a
   warning plus a `--strict-mono` gate. Instrument first: count fallbacks across the
   stdlib and the golden corpus, and put the number in the progress entry. Do not guess.
2. **Is the boxed fallback ever CORRECT?** It is, whenever the caller also uses the boxed
   representation. The error must fire only where the caller's chosen representation
   differs from the callee's — that predicate is the actual content of this fix, and
   `lib/tir/rc_types.ml` / the niche-eligibility logic is where to find it.

## Step 3 — give lazy modules real inference (option 1, only if step 2 proves too coarse)

Make `Module_registry.ensure_loaded` (`lib/modules/module_registry.ml:227`) run enough type
inference to resolve a caller's binders, not just extract export shapes. Strictly better
than step 2 — it makes the code *work* rather than making the failure visible — but it is
also the expensive one, and it partially defeats the purpose of lazy loading. Only worth it
if step 2's measurement shows the fallback firing on code that genuinely must keep working.

## Acceptance

- Step 1: removing any entry from `stdlib_file_list` fails the suite with the message above.
- Step 2: the `ConsistentHash` repro in this file, with `consistent_hash.march` REMOVED
  from `stdlib_file_list`, becomes a compile error rather than `SOME 2197058856`. That is
  the REJECT witness, and it is the whole point — a fix that merely makes the repro print
  `SOME 42` (because the module got eagerly loaded again) has tested nothing.
- `lazy_niche_probe.march` still compiles and still demonstrates the lazy path, since it is
  the fixture the class depends on. Check its doc comment before touching anything near it.
- Full suite green, and the golden corpus compiles with no new errors — step 2 can only be
  landed with evidence that its error fires exclusively on genuinely-broken calls.
