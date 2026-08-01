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
