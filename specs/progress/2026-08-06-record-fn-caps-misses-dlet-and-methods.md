# `record_fn_caps` gives no `own(...)` entry to `DLet` bodies, interface methods, or impl methods

**Filed:** 2026-08-06, while landing demand-driven Check 4 propagation
(`specs/progress/2026-08-06-demand-driven-cap-propagation.md`). This is the
design doc's own open question
(`specs/2026-08-06-per-function-capability-closure-design.md`, "Open questions")
turned into a concrete, now-load-bearing defect.

## The gap

`record_fn_caps` (in `check_module_needs`, `lib/typecheck/typecheck.ml`) is
driven by `used_caps` / `body_cap_uses` / `extern_cap_uses`, which between them
cover `DFn` signatures and bodies, actor handlers, and `DExtern`. They do **not**
cover:

- module-level `DLet` binding bodies,
- `DInterface` default methods,
- `DImpl` methods,
- **default-argument expressions** — an `FPDefault (p, e)`'s `e`. Both the
  `own(...)` body scan (`body_cap_uses`, which walks `clause.fc_body`) and
  `record_fn_refs` (which walks `fc_body :: fc_guard`) skip it, so
  `fn f(x = noisy())` records neither `noisy`'s capability nor a reference edge
  to it. Pre-existing — the `own(...)` scan has always skipped it — but the
  closure is now enforcement-bearing, so it belongs in this fix: a default
  argument is evaluated at every call site that omits the parameter, which is
  exactly the "promises something and does not deliver" direction below.

Those names get no entry in `env.own_cap_closures`, so
`fn_transitive_capability_closures` returns `[]` for them — and, worse, returns
a **silently truncated** closure for anything that references them.

## Why it matters now

Until 2026-08-06 the table was analysis-only. Check 4 now consults it, so the
truncation can drop a capability the compiler previously required. Two cases,
only the first of which is guarded:

| Shape | Guarded? |
|---|---|
| The importer references the entry-less name **directly** (`import M` then `M.some_let`) | **Yes** — `import_required_caps`'s `caps_of_name` finds no entry and falls back to the imported module's whole declared `needs` set, i.e. the pre-change answer. Pinned by `cap-closure` test `a name with no closure entry falls back to module caps`. |
| The importer references a `DFn` that itself **reaches** an entry-less form | **No** — the `DFn` has an entry, so `caps_of_name` succeeds and returns its truncated closure. The fallback never fires. |

So: `mod M do needs IO.Console; let banner = ...print...; fn greet() do banner end end`
— an importer referencing only `greet` may no longer be required to declare
`IO.Console`, where before this change it was. That is the "promises something
and does not deliver" direction, which the plan's global constraints call as
serious as a false positive.

Bounded, but not zero: it needs the referenced `DFn` to reach a capability
*exclusively* through one of the three uncovered forms. Any path through an
ordinary `DFn` or builtin call is still counted.

## Shape of the fix

Give the three forms an `own(...)` entry the same way `DFn` gets one — extend
the `decls` walks that feed `record_fn_caps` (and `record_fn_refs`, so the
reference edges are there too) to include `DLet` binding bodies, `DInterface`
method bodies, and `DImpl` method bodies, keyed consistently with the existing
`cap_qname_prefix` scheme. For default arguments the fix is smaller and local:
include each `FPDefault (_, e)`'s `e` in the expression lists both scans walk
(alongside `fc_body` and `fc_guard`), with the clause's params bound.

Watch for: the `march caps` cross-check
(`test_transitive_cap_union_matches_module_level`) compares the transitive union
against `fn_own_capability_closures`, so both tables must gain the same entries
or that test will (correctly) go red. Adding entries can only *increase* what
Check 4 requires, so this fix is **not** in the strictly-loosening class —
re-run the corpus sweep and the scratch positive control, and expect the
possibility of genuinely new errors on code that under-declares today.

## Related

- Blocks a confident re-measurement of Step 4's blast radius
  (`specs/2026-08-06-per-function-capability-closure-design.md`, "Step 4"),
  since the 176-file figure was measured before any of this.
- The `KEEP IN SYNC`-style note lives on
  `fn_transitive_capability_closures_tbl`'s docstring in
  `lib/typecheck/typecheck.ml`, and the user-facing statement is in
  `docs/capabilities.md` + `specs/lang/capabilities.md`.

---

## Resolved 2026-08-06

Closed in `lib/typecheck/typecheck.ml`'s `check_module_needs`. All four forms now
get an `own(...)` entry and reference edges:

| Form | Key |
|---|---|
| module-level `DLet` body | `cap_qname n` for every `n` the pattern binds — keyed exactly like a `DFn` of that name, so an ordinary reference resolves |
| `DInterface` default method body | `cap_qname (Iface ^ "$default." ^ method)`, parallel to the impl mangling |
| `DImpl` method body | `cap_qname (Iface ^ "$" ^ TyKey ^ "." ^ method)`, mirroring TIR's `Iface$Ty.method` mangling |
| default argument | walked directly (undesugared path) **and** via an alias from desugar's arity-mangled `f$N` onto the base name `f` (production path) |

**Method keying, stated because a colliding key would silently merge two
functions' capabilities.** An ordinary qualified name never contains `$` (see
`Tir_names.is_iface_mangled`), so the mangled key cannot collide with a `DFn` of
the same short name, and two impls of the same method for different types get
distinct keys. Because a reference site says the *bare* method name, the bare
name additionally becomes a **dispatch node** carrying one edge per impl — the
union over impls, which is the sound reading of a name whose target is chosen by
type. It is emitted only when the module declares no `DFn` of that name, so a
plain function's identity can never be absorbed
(`test_impl_dispatch_node_does_not_capture_a_same_named_fn`).

An interface default body gets the **same** treatment, keyed
`Iface$default.method`. The first version of this change did not: it wrote the
default body's caps straight onto the bare `cap_qname md_name` with no mangling
and no guard, on the (false) assumption that a module could not declare both an
interface method and a plain `fn` of that name. It can —

```march
mod Inner do
  interface Greeter(a) do
    fn greet : a -> Unit
    fn greet_loud : a -> Unit do fn (x) -> print("loud") end
  end
  fn greet_loud(n : Int) : Int do n + 1 end
end
```

typechecks with exit 0, and since `record_fn_caps` merges, the pure `greet_loud`
absorbed `IO.Console` — visible on the hot-deploy manifest, which reads
`fn_own_capability_closures` unfiltered, so Check 4's `mod_caps` filter offers no
protection there. Caught in review, fixed, and pinned by
`test_interface_default_does_not_capture_a_same_named_fn`, whose FIRST assertion
is on the own-caps table because that is the table the manifest reads.

**Default arguments, traced rather than assumed.** Desugar's
`expand_defaults_decl` runs *before* the typechecker and rewrites
`fn f(x \\ d)` into `f$0`/`f$1` with `d` moved into `f$0`'s body — but it does
not rewrite call sites and emits no dispatcher `DFn`, so the base name `f` had
no entry at all. The alias is what makes a caller's reference to `f` resolve.

**Why this cannot make Check 4 stricter than the pre-demand-driven rule.**
`import_required_caps` *filters* the imported module's declared `needs` by the
demand set rather than returning the demand set. The result is a subset of
`mod_caps` by construction, so no addition to `own_cap_closures` can require
more than the old module-granular answer.

**Blast radius, measured.** *(Round-1 text below; a per-function sweep was added
in review — see the paragraph after it. The diagnostic byte-diff and the
module-level `march caps` union are both insensitive to per-function
misattribution WITHIN a module, which is how the interface-default false
positive above escaped them.)* `--check` over `stdlib/*.march`,
`test/native/*.march` and `bench/*.march` (277 files) against a compiler built
from `11f9acdf`: **byte-identical output on every file**, so zero newly-erroring
files and no false positives. `march caps` over the same corpus: identical on
all 277 (252 produce a report, 183 non-empty). Non-vacuousness is carried by the
positive controls instead — the `ProviderQ7`/`ConsumerQ7` program goes 0 → 1
Check-4 errors, six new tests were RED before the change, and each of the four
walks is individually load-bearing under mutation.

**One expectation deliberately flipped.** `test_import_of_entryless_name_falls_
back_to_module_caps` used a *pure* module-level `let` to exercise the "no entry
→ whole module set" fallback. That let now has an entry, so the correct
expectation becomes "a pure let costs the importer nothing"; the test was
rewritten as `test_import_of_pure_module_let_costs_nothing`, with the impure
sibling as its control. Instrumenting the `| None -> mod_caps` branch showed it
now fires **zero** times across the whole `run_compiler` suite and the corpus
sweep — it is a defensive backstop for a key-shape miss, not a covered path.

**Observed, not fixed — filed separately.** `own_caps_of_this_module`
(`bin/main.ml`, feeding `--cap-sandbox` and `--cap-strict`) builds its
`user_fn_names` set from `DFn` declarations only, so a bare or `Iface$Ty.`-
prefixed key never `belongs` and the new entries are invisible to it. `march
caps` uses a *different* `belongs` (module-name prefix, `run_check_cmd`) and does
see them. The two surfaces therefore do not share a filter, contrary to
`own_caps_of_this_module`'s docstring.


**Per-function own-caps sweep (added in review).** A temporary
`MARCH_DUMP_FN_CAPS` hook, patched into both `bin/main.ml` copies and reverted
after, dumped every `fn_own_capability_closures` pair for all 277 corpus files
per side. Result: **0 keys removed, 0 keys where the same function's own-caps
changed**, and 6,316 purely additive new keys (5,491 impl-mangled, 824 bare —
module `let`s, dispatch nodes and arity aliases — 1 interface-default-mangled).
No pre-existing function anywhere in the corpus gained or lost a capability, and
no dispatch node collided with an existing key.

Its limit, stated because it matters more than the result: this sweep would
**not** have caught the interface-default false positive either. The corpus
holds exactly one interface default method and no module declaring both a
default and a same-named `fn`. Corpus sweeps bound the blast radius; only a
REJECT test pinning a specific function at EMPTY catches misattribution.
