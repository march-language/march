# The forge `[P1]`: three features, one already designed, one a language question

**Date:** 2026-09-18
**Status:** design / triage.
**Scope:** what was `specs/todos/2026-07-31-p1-tooling-forge-build-tool.md` —
**split on 2026-09-18** into `2026-07-31-forge-offline-mode.md`,
`2026-07-31-forge-feature-flags.md` and `2026-07-31-forge-semantic-semver.md` —
whose three
bullets are unrelated features filed together under one priority. This document
takes them one at a time, because they are not the same kind of work and
should not share a priority.

**Recommendation up front:** split the todo into three files and re-prioritise.
**Executed 2026-09-18** with the priorities in the table below.
None of the three is a defect. Sitting at `[P1]` beside a live miscompile, they
misstate the order work should happen in.

| Item | State | Real priority |
|---|---|---|
| §1 Offline mode | **designed**, half landed | P2 — the rest is scheduled work |
| §2 Optional deps / feature flags | a language-design question | P3 — needs a decision before a design |
| §3 Semantic semver checking | a correctness gap in `forge publish` | **P2** — it can wave through a breaking release |

---

## §1. Vendoring / explicit offline mode

> *"`forge vendor`, `--offline` — partly mitigated by the CAS cache; no explicit
> story."*

**This already has a design:**
`specs/2026-09-11-forge-offline-and-versioned-dep-cache-design.md`. Its own
§0 found the todo's "partly mitigated by the CAS cache" to overstate what
existed. Status, from its header:

- **Landed 2026-09-12:** §2, the version-aware dependency cache
  (`specs/progress/2026-09-12-version-aware-dep-cache.md`), and the §0.3
  lockfile hash-domain alignment.
- **Still proposed:** §3 `--offline`, §4's verification, §2.4's tarball cache.
- **Explicitly out of scope:** vendoring proper — `forge vendor` and an
  in-tree committed `vendor/` (its §7).

So there is nothing to design here. The remaining work is that document's §3,
and it should be tracked as that, not as a bullet under a `[P1]`.

The one open question the todo implies and the design sets aside is whether
`forge vendor` is wanted at all. The version-aware cache plus `--offline` covers
"build without the network". Vendoring additionally covers "build from a
checkout alone, with no cache". The case for it is air-gapped CI and
reproducible archives. That is a product call, not an engineering gap, and it
should be made by whoever owns forge's scope rather than left implied.

---

## §2. Optional dependencies / feature flags

> *"conditional deps and compile-time features (a language-design question)."*

The todo is right that this is a language question first. A design written now
would be a design for a decision nobody has made. What it needs is the decision,
and the options are distinct enough to state:

**A. Cargo-style additive features.** `[features] tls = ["dep:rustls"]`; a
feature enables optional deps and sets a compile-time flag. Well understood,
and additive by construction. **Cost in March:** the flag has to reach code, and
March has no conditional compilation. That means a new construct (`@[cfg(...)]`
on declarations, or a `cfg(feature)` builtin the optimiser folds), and an answer
to how the refinement checker, the capability ceiling and the LSP see code
behind a disabled flag.

**B. Optional deps without source-level flags.** A dep is optional; the code
that uses it lives in a separate module the consumer opts into by importing it.
No new language construct — the module system does the gating. **Cost:** coarser
grained, and each "feature" has to be its own module.

**C. Capability-shaped features.** Express the optional surface as a
capability the consumer grants, reusing the `needs` / `Cap(...)` machinery the
language already enforces. On-brand for March. **Cost:** capabilities gate
*effects*, not *code presence*, so this answers "may this run" rather than "is
this compiled in". It does not remove the dependency from the build.

B is the cheapest and needs no language change. A is the most familiar and the
most expensive. C is the most distinctive and answers a different question. The
first thing to establish is which question users are actually asking: smaller
binaries and fewer deps (points to A or B), or finer-grained permission (points
to C).

**Not recommended:** designing A speculatively. `cfg` interacts with every
whole-program analysis in the compiler — refinement, capabilities, the
exhaustive-stdlib manifest, mono. It should not be started without a user who
needs it.

---

## §3. Semantic semver checking on `forge publish`

> *"`Resolver_api_surface` is text-heuristic; linearity/generic diffing needs
> compiler integration."*

This is the one item with a correctness consequence, and it is **undersold** by
the todo.

### What is true today

`forge/lib/resolver_api_surface.ml` stopped being text-heuristic on 2026-08-03 —
it reads the real AST now
(`specs/progress/2026-08-03-forge-api-surface-parser-wrong-syntax.md`). But it
compares what it reads as **rendered strings**:

```ocaml
type fn_sig    = { name : string; params_raw : string; return_raw : string }
type type_decl = { type_name : string; body_raw : string }
```

`cmd_publish.ml` calls `diff` and refuses an under-bumped release. So the
verdict gates publishing, and a string comparison is doing the gating.

### Wrong in both directions

**False MAJOR, which is annoying:**
- Renaming a parameter (`fn f(x : Int)` → `fn f(y : Int)`) changes
  `params_raw`, so it reads as a signature change. Callers are unaffected.
- Renaming a type variable (`List(a)` → `List(b)`) — same.
- Loosening a refinement (`{Int | _ > 0}` → `Int`) accepts strictly more
  callers and is compatible, but the text changed.

**False PATCH, which is dangerous:**
- **A public function with no return-type annotation has `return_raw = ""`.**
  March infers return types, so this is common. Changing what such a function
  returns is invisible to the diff, and a breaking release publishes as a patch
  unchallenged. This is the silent pass the 2026-08-03 rewrite existed to
  eliminate, reached by another route.
- A change to an **unexported** type that is exposed through an exported
  function's signature is not in `types` at all.

### Design

> **Correction, 2026-09-18 — found while executing this section.** The
> paragraph below originally said *"the compiler can already emit them:
> `march --emit-core-ast`"*. **It cannot.** Checked against a module with an
> unannotated public function: the JSON's `module.decls[].fn.ret_ty` is `null`
> for exactly the functions this gap is about — it is the desugared SURFACE AST,
> not the inferred one — and its `schemes` section covers polymorphic
> instantiations, not every public binding. There is no per-binding inferred
> type in any output the compiler has today.
>
> A second gap the original missed: `cmd_publish` gets the OLD surface by
> **parsing** the previous version, which needs no dependencies. Typechecking it
> does — the old version's whole dependency tree, at the versions it was
> published against. That is the expensive part of this design, and it was not
> in the estimate.
>
> So Step 1 needs a new compiler output (the inferred type of every public
> binding, e.g. a `bindings` section on `--emit-core-ast` read out of the
> typecheck env) and a way to typecheck an old version with its own deps. See
> "A cheaper guard" below for what can ship without either.

Compare **resolved types**, not rendered text. So:

1. For each of the old and new trees, run the typechecker and take every public
   binding's **inferred** type — which fills the missing return annotations —
   in a normalised form: type variables alpha-renamed to canonical order,
   aliases expanded, parameter names dropped.
2. Diff those. A changed normalised type is MAJOR; an added binding is MINOR.
3. Classify refinements by **direction**: a strictly weaker precondition or a
   strictly stronger postcondition is compatible. That needs the refinement
   checker's implication query, so ship it after 1–2, falling back to "any
   change is MAJOR" meanwhile, which is the safe side.
4. Treat a variant with **added constructors** as MAJOR (it breaks exhaustive
   matches in callers), which the string diff happens to get right today and
   the structural one must keep.

### A cheaper guard for the dangerous direction

The false PATCH is the one that matters, and it can be closed without a
typechecker by treating it the way `extract_from_directory_checked` already
treats an unparseable file: **as a surface the diff cannot see, and therefore
cannot certify.** If a public function has no return-type annotation in the
old or the new version, and its clauses changed between them, the string diff
cannot rule out a return-type change, so `cmd_publish` refuses to certify a
PATCH or MINOR bump for it and says which function and why. Annotating the
return type gets a precise verdict back, which is also good API hygiene.

- Sound: it only ever refuses, never certifies wrongly.
- Cheap: the parser already has the clauses; this is a comparison and a message.
- Noisy in proportion to how much public API is unannotated. That noise is the
  real cost, and whether it is acceptable is a product call — hence this is an
  option, not a decision.

This does nothing for the false MAJOR direction, which is annoying rather than
dangerous and can wait for the full design.

### Verification bar

A fixture pair per row of "wrong in both directions" above, each asserting the
current behaviour first (RED — the string diff gets it wrong) and the new
behaviour after. The unannotated-return case is the one that matters: it must
flip from PATCH to MAJOR.

### Effort

**Revised: L**, up from M. The parser walk and the diff/classification skeleton
exist; a per-binding inferred-type output does not, and typechecking the OLD
version needs its dependency tree resolved. The cheaper guard above is **S** and
closes the dangerous direction on its own.
