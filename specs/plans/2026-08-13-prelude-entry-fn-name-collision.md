# Fix: user top-level function names silently collide with Prelude

Design spec for `specs/todos/2026-08-13-user-fn-name-collides-with-prelude-internal-call.md`.
Status: root cause traced to a specific structural gap, with the exact
overwrite site in each backend still to be confirmed by the implementer (see
§4). Fix design and staging are settled; not yet implemented.

---

## 1. Recap: what's broken

Any top-level function (`fn` or `pfn`, public or private, in the user's entry
module) whose bare name matches a name Prelude calls **internally** silently
replaces it program-wide. Two confirmed manifestations (repros in the filed
todo): a misattributed runtime error, and — the one that should set the
priority — a **fully silent no-op** with zero diagnostic in either backend.

## 2. Root cause, traced precisely

### 2.1 Two files get unwrapped into one flat, unprotected scope

`bin/main.ml`'s `load_stdlib_file` (`bin/main.ml:264`) special-cases exactly
one file: `prelude.march`'s `mod Prelude do ... end` wrapper is stripped, so
its members land as **bare, unqualified top-level declarations** — no `DMod`,
no namespace. Every other stdlib file keeps its wrapping `DMod` and is only
reachable as `Module.member`.

`lib/desugar/desugar.ml`'s `desugar_module` takes an `is_entry` flag,
**defaulted to `true`** (`desugar.ml:3258`) — "matching every pre-existing
caller's actual usage." The user's entry `.march` file is desugared with this
default, and the doc comment confirms it explicitly: *"the program's entry
file must NOT have its own top-level mod name folded in (TIR unwraps it — its
members are emitted bare)."*

So **both** prelude.march and the user's entry file are independently
unwrapped into bare top-level declarations, then concatenated. Nothing after
that point distinguishes "this came from Prelude" from "this came from the
user."

### 2.2 The only duplicate-name check is per-file, and never sees the union

`desugar_module` (§2.1) runs **once per file** — once for `prelude.march`,
separately for the entry file — each call blind to the other's declarations.
Whatever catches a same-name collision *within* one file is scoped to that
single call: checked directly with `fn helper(x : Int) do x + 1 end` /
`fn helper(y : Int) do y + 2 end` declared twice in one module — this errors
(via the parser's multi-head-merge attempt, since two `fn`s sharing a name are
first tried as multi-head clauses; the message is a generic "Parse error in
declaration" rather than a clear "already defined," which is itself worth
improving but is a separate, smaller issue from the one this spec fixes). The
point that matters here: whatever mechanism produces that error is scoped to
one `desugar_module` call and never runs again after the two already-desugared,
already-flattened decl lists are concatenated downstream. **The union across
files is never checked.**

### 2.3 The union is built independently at 7+ sites, not once

`grep -rl "prelude.march" --include="*.ml"` outside `_build`/tests turns up:

```
bin/main.ml                       lsp/lib/analysis.ml
js/march_browser_compile.ml       lib/typecheck/typecheck.ml
lib/search/search.ml              lib/modules/module_registry.ml
lib/modules/stdlib_manifest.ml
```

At minimum `bin/main.ml` and `lsp/lib/analysis.ml` independently reimplement
"parse prelude.march, unwrap it, desugar the entry file, concatenate the
decls." There is no single shared function for this. That means a
per-call-site patch has to land (and stay in sync) in every one of them, which
is exactly the class of drift this session already hit twice elsewhere
(`test_stdlib_march.ml`'s stdlib load list vs. the production manifest;
`run-tests.sh` missing a runner). Scope this into the fix design — see §4.

### 2.4 `show` and `print` share a symptom but need two DIFFERENT checks

**Corrected during implementation — this section originally concluded "one
root cause, not two," which was wrong in the sense that mattered for the
fix.** Initially plausible that `show` (a "structural interface" name —
`Show`/`Eq`/`Ord`/`Hash` methods get special dispatch treatment, per
`typecheck.ml:340`) was a different mechanism than `print` (an ordinary
builtin). Checked directly: `stdlib/prelude.march` declares seven `show`
overloads, but every one is inside an `impl Show(...) for X do fn show(...)
end end` block (confirmed by reading `prelude.march:179-200`), which mangle to
names like `Show$List.show` at the type level — this session independently
observed that exact mangled form in an unrelated ambiguous-dispatch error
message. Those don't collide with a bare top-level `show` at all.

The bare `show`/`print` that `println` calls are **native builtins**
(`eval.ml:4691`/`4097`, `VBuiltin (...)`) with **no March-source declaration
anywhere** — confirmed by grepping `prelude.march` for a top-level `fn
show`/`fn print` and finding neither. This is the detail that mattered once
implementation started: a checker that only compares `DFn` names across the
two decl lists (§4.1) is *structurally blind* to a collision with `show`/
`print`, because neither ever appears as a `DFn` for it to see. Verified this
the hard way — the first version of the fix, DFn-vs-DFn only, built cleanly,
passed its own unit tests, and then caught neither original repro when run
against the real compiler.

So there are genuinely **two collision sources needing two checks**, both
implemented:

1. A name matching another March-source top-level `fn`/`pfn` in
   `prelude.march` (the ~21 names in §3, e.g. `println`, `map`, `reverse`) —
   checked against the prelude decl list's own `DFn`s.
2. A name matching a **native compiler builtin with no source declaration at
   all** — `show` and `print` are exactly this — checked against
   `Typecheck.builtin_bindings` and `Typecheck.builtin_interface_bindings`,
   the SAME tables the typechecker itself resolves builtin calls against, so
   this can never drift from what the compiler actually treats as a builtin.

### 2.5 What's still open: the exact overwrite site in each backend

Confirmed *that* the collision reaches the interpreter's runtime call
resolution (arity-mismatch and silent-no-op reproduce interpreted) and TIR
lowering (`--dump-tir` shows exactly one `show` symbol in the whole program —
the user's; Prelude's builtin binding for `show` is gone, not merely shadowed
in some secondary lookup). Not traced: whether `typecheck.ml`'s `env.vars`
(built via `bind_var` inside `check_module_core`, `typecheck.ml:13432`),
`lib/tir/lower.ml`'s decl-to-symbol table, and `eval.ml`'s global environment
each independently exhibit "last declaration in list order wins," or whether
one is upstream of the others and the rest just inherit its answer.

**This doesn't block the fix design in §4.** The recommended fix rejects the
collision *before* the merged list reaches any of typecheck/lower/eval, so
none of them need to change. Pin this down only if §4's primary fix is judged
insufficient (see §4.3).

## 3. Blast radius — the static check said zero, the real one found 9

A "reject at compile time" fix is only safe if it doesn't break real
programs. First pass at this was a static `grep` over `examples/*.march` and
`bench/*.march` for 2-space-indented top-level `fn`/`pfn` names matching the
21 true top-level Prelude names (`compose const debug filter flip fold_left
head identity inspect is_nil length map panic println reverse str tail todo
unreachable unwrap unwrap_or`). It reported zero collisions.

**That result was wrong, and the mistake is worth recording.** Once the
actual checker (§4) was implemented and run against the same corpus for
real, it found **9 bench files** — `alphadev_sort.march`, `heapsort.march`,
`insertion_sort.march`, `introsort.march`, `mergesort.march`,
`sort_nearly_sorted.march`, `sort_small_batched.march`, `timsort.march` —
each independently defining a private `pfn head(xs : List(Int)) : Int`
(a safe, zero-defaulting variant of Prelude's `head`, which panics on empty
input) that collides with Prelude's real `head`. The static grep missed
every one of them because these files indent their module bodies at column 0
rather than the 2-space convention the rest of the corpus follows — an
indentation-based heuristic is only as reliable as the assumption it's built
on, and that assumption doesn't hold universally. **The compiler-level
checker doesn't care about indentation at all; it walks the desugared AST.**
This is a small, concrete argument for why the real fix (§4), not a
lint-style static check, is the right shape for this.

All 9 were fixed as part of landing this change — `head` renamed to
`first_or_zero` (matching what the helper actually computes: the first
element of a sorted list, or 0 if empty), consistently across definition and
every call site. These were latent instances of the exact bug this spec
fixes — they happened never to trigger a visible symptom only because none
of these programs' own control flow depends on Prelude's real `head` working
correctly anywhere else in the same run.

Three other corpus failures surfaced in the same pass (`csv_server.march`: a
type mismatch; `http_get.march`/`http_get_close.march`/
`http_get_keepalive.march`: a missing `else` branch) — confirmed unrelated:
none of the four diagnostics mention a collision, and the errors are
ordinary pre-existing type/syntax problems in what look like stale example
files, not something this change touches. Left as-is; not this spec's
concern.

After the rename, `examples/`/`bench/` is clean under the real checker (see
§5 for the verification run).

**A second, more instructive miss** turned up running the FULL test suite,
not the corpus survey: `test/native/*.march` (a different fixture set,
gated by `llvm_ir_validity_gate`) had 3 more failures — `unwrap` colliding
in `newtype_counter.march` and `or_pattern.march` (same as the bench
`head`s: fixed by renaming, this time to `unwrap_counter`/`unwrap_either`),
and `iface_method_collision.march`, which was NOT a bug in the corpus at
all. Its own header comment: *"a user top-level function whose name
collides with an interface method (here `show`) must not hijack the
interface dispatch used inside prelude generics."* This is a standing,
already-fixed, already-regression-tested feature — a bare top-level `fn
show(x)` at the correct 1-argument arity is legitimately resolved by
argument type, the same as an explicit `impl Show(X)`. The first version of
this fix didn't know that and broke it, treating every `show` as an
unconditional collision. Forced §4.1's arity-aware carve-out: `show`/`hash`
(1-arg) and `eq`/`compare` (2-arg) are exempt from the collision check
**only** when the entry function's own arity matches — a mismatched arity
can never be a valid overload (there's no way to call a 2-argument function
through a 1-argument interface slot), so it's still flagged, which is
exactly what the original filed repro's `pfn show(label, t)` needed.

The lesson underneath both misses: **a survey (static grep, or a
hand-picked corpus) only finds what it thinks to look for.** The real
checker, run against every fixture the test suite already exercises, found
a genuine feature this fix would otherwise have silently broken. Running
the full suite — not just the targeted corpus check — is what surfaced it.

## 4. Fix design

### 4.1 Primary fix: detect the collision where the two lists are concatenated

**IMPLEMENTED** (2026-08-14), as `lib/modules/prelude_collision.ml`. Matches
the design below with two corrections, both forced by running it for real
rather than by design review:

- Forced by §2.4: **two checks, not one**, because `show`/`print` have no
  `DFn` for a DFn-vs-DFn check to find — one against Prelude's own `DFn`s,
  one against `Typecheck.builtin_bindings`.
- Forced by §3's second finding: `show`/`eq`/`compare`/`hash` need a THIRD,
  arity-gated path rather than blanket inclusion in the builtin-name check
  — see `Typecheck.builtin_interface_bindings` and the module's own doc
  comment for the full argument. A same-name function at the WRONG arity
  for that interface method is still flagged through this same path (it
  cannot be a valid dispatch overload), so the original filed repro
  (`pfn show(label, t)`, 2-arg) is still caught — the exemption only
  applies when the arity genuinely matches.

**Reuse the existing precedent rather than inventing a new mechanism.**
Same-file duplicate names are already caught (§2.2) by the multi-head-merge
path in desugar. The fix runs an equivalent check **once, at the point
where Prelude's already-desugared decl list and the entry module's
already-desugared decl list are joined** — since post-desugar, any legitimate
multi-head merging has already happened *within* each list separately, so any
remaining same-bare-name collision *across* the two lists is unambiguously a
genuine collision, never a false positive against multi-head syntax.

The actual signature:

```ocaml
(* lib/modules/prelude_collision.ml *)
val check :
  prelude_decls:Ast.decl list ->   (* the FULL stdlib list; only prelude.march's
                                       own bare DFns are visible to this, since
                                       every other stdlib file keeps its DMod *)
  builtin_names:string list ->     (* Typecheck.builtin_bindings @
                                       Typecheck.builtin_interface_bindings,
                                       qualified forms filtered out — the
                                       source of truth for §2.4's second
                                       collision class *)
  entry_decls:Ast.decl list ->
  Errors.ctx -> unit
```

It walks both decl lists collecting top-level `DFn` bare names only —
`DImpl` is a distinct AST variant (confirmed in `lib/ast/ast.ml`), so an
`impl Show(...) for X do fn show(...) end end` block's `show` is invisible
to this walk and never produces a false positive against a module defining
its own `Show`/`Eq`/`Ord`/`Hash` impl. For each entry-module name: if it
matches a prelude `DFn`, or if it's in `builtin_names`, report a compile
error naming *why* it matters, not just "already defined" — the danger here
is that the collision looks completely innocuous at the definition site:

```
error: `show` redefines a March compiler builtin.
March's Prelude (println, show, print, and others) calls its own members
unqualified, so a top-level function in your program sharing one of those
names silently REPLACES it for the whole program — including inside
Prelude's own code. This can fail loudly (a confusing runtime error), or
fail completely silently (no error, no crash, just wrong output).
Rename this function — `show_impl`, a more specific name, or similar.
```

`lib/modules/module_registry.ml` (the site originally proposed above) turned
out to be the wrong home — it depends on being about *qualified* module
exports, a different concern, and more importantly `march_typecheck` itself
depends on `march_modules`, so a check needing `Typecheck.builtin_bindings`
cannot live inside `march_modules` without a circular dependency. It's its
own small file in the same library instead, called from `bin/main.ml` (which
already depends on both `march_modules` and `march_typecheck`) with the
builtin-name list sourced there and passed in.

### 4.2 Scope of the fix: centralize, don't patch 7 sites independently

§2.3 found this pattern duplicated across at least `bin/main.ml` and
`lsp/lib/analysis.ml`, with no shared function to hang the check on. Patching
each call site's copy independently is exactly the failure mode that produced
two other bugs found this session (a stdlib load-list drifting from the
production manifest; a test runner silently missing an entire suite). Do not
repeat it here.

**Staged, so the safety fix isn't blocked on a larger refactor:**

- **Stage 1 (required for this fix):** add `check_no_prelude_collision` (or
  equivalent) to `bin/main.ml`'s pipeline — the path `march --compile`,
  `march --check`, and plain `march file.march` all go through. This alone
  closes the SIGBUS and the silent-no-op for the primary compiler entry
  point.
- **Stage 2 (required for this fix, not optional):** the same check in
  `lsp/lib/analysis.ml`. Skipping this means a user's editor shows no
  diagnostic for code that `march --compile` now rejects — a compiler/LSP
  disagreement, which this codebase has hit before and treats as a real bug
  class, not a cosmetic gap.
- **Stage 3 (explicitly out of scope for this fix; file as its own
  follow-up):** extract the whole "load prelude, unwrap, desugar entry,
  concatenate" sequence into one shared function in `lib/modules/`, migrate
  `bin/main.ml`, `lsp/lib/analysis.ml`, `js/march_browser_compile.ml`, and
  the REPL path onto it. This is the right long-term fix for the duplication
  itself — it's a distinct, larger refactor, and bundling it into a
  correctness/safety fix risks delaying the fix for a scope increase that
  deserves its own review.

### 4.3 Fallback if Stage 1 can't land cleanly: pin Prelude's own calls

If detection at the merge point turns out to be awkward for some caller
(e.g. a caller that doesn't have both decl lists available at once, or needs
the check to run before decls are fully desugared), the fallback is
**defense at the source** instead of **defense at the boundary**: when
desugaring `prelude.march` specifically, rewrite Prelude's *own* internal
bare calls (`show`, `print`, and whichever others are load-bearing) to a
form that cannot be shadowed regardless of what the entry module later
declares — e.g. a reserved, unspellable-by-user-source internal name, or
routing them through the builtin table directly rather than through
ordinary bare-identifier resolution.

This is strictly worse as a *primary* fix — it only protects Prelude's own
calls, not a stdlib file's calls into Prelude, and it doesn't stop the user
from still shadowing an *unrelated* name and getting a different, equally
silent surprise elsewhere. Treat it as a fallback for a specific caller, not
a replacement for §4.1.

### 4.4 Deliberately out of scope for this fix

- **Constructors and types.** §3's blast-radius check and §4.1's design cover
  functions only. Whether the same collision class exists for bare
  constructor/type names between Prelude and an entry module is a real
  question but a separate one — check it, but don't block this fix on
  answering it.
- **Collisions between two *stdlib* files** (as opposed to Prelude vs. the
  entry module). Every other stdlib file keeps its `DMod` wrapper (§2.1), so
  this specific unprotected-flat-scope mechanism doesn't apply to them.

## 5. Verification — done for Stage 1, Stage 2 (LSP) not yet started

Followed this session's own methodology: golden repros, checked both
interpreted and compiled, plus a check that the fix doesn't reject anything
it shouldn't.

1. **DONE — unit tests for the checker itself**, `test/test_compiler.ml`'s
   `prelude-collision` group, 6 cases: detects a shared prelude `DFn` name,
   names the colliding identifier in the message, silent when nothing
   collides, ignores `impl Show`'s own `show`, detects a native-builtin
   collision, silent for an ordinary non-builtin name. Every case proven
   non-vacuous by sabotage (flip the check to never fire / always fire /
   also descend into `impl` bodies; confirm the expected test breaks each
   time; restore).
2. **DONE — the two repros from the filed todo, against the real compiler**,
   interpreted and `--check`: both now exit 1 with the new diagnostic
   naming the colliding identifier, not the old misattributed arity error
   and not silent success.
3. **DONE — the same two repros compiled** (`--compile --opt 2`): both now
   exit 1 with the diagnostic, no binary produced — not the SIGBUS this
   used to be.
4. **DONE, and it found something** — the full `examples/`/`bench/` corpus
   run through the real `--check`, not the static grep §3 originally used.
   Found 9 real collisions the static check had missed (§3) — fixed by
   renaming; corpus is clean under the real checker afterward, modulo 4
   pre-existing unrelated failures. This is the single most useful
   verification step in this list: it caught a live blast-radius mistake
   that #1–3 could not have caught on their own.
5. **DONE — `impl Show` path confirmed unaffected**, both by a dedicated
   unit test (item 1, strengthened after an initial version of it turned out
   to be a false-negative-shaped test — see the module's own doc comment)
   and because the real corpus (item 4) includes stdlib/example code using
   `derive`/`impl Show` without incident.
6. **DONE — trivial-program non-regression**: a plain non-colliding program
   confirmed unaffected at all three call sites — silent under `--check`,
   compiles, and actually runs and prints correctly interpreted. Necessary
   because a checker that never false-positives on the two repros could
   still false-positive on ordinary code; this rules that out directly
   rather than by inference from the corpus alone.
7. **NOT DONE — LSP parity (Stage 2 of §4.2)**. `lsp/lib/analysis.ml`
   independently reimplements the same prelude-unwrap-and-merge sequence
   (§2.3) and has not been touched. Until it is, the LSP will show no
   diagnostic for code `march --compile`/`march --check` now reject — a
   known compiler/LSP disagreement class this codebase treats seriously.
   Filed as follow-up work, not closed here.

## 6. Why this outranks the `Parse` throughput work

Filed as `[P0]` deliberately. The `16.5x` combinator-vs-hand-written question
is an *adoption* question for a library nothing in the codebase depends on
yet. This is a *correctness* question reachable by an ordinary user action —
naming a private helper function `print` — with a demonstrated silent-wrong-
output failure mode and no diagnostic in either backend. Recommend
prioritizing this over any further `Parse` work.
