# Object capabilities, phase 6: dependency grants — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A project's `forge.toml` limits each dependency's authority with a `grant` written in
the scope language. The compiler checks the dependency's reached code against its grant,
statically where it can. Run-time `ByGrant` frames enforce the rest (computed targets,
function values, spawned actors). Behaviour is identical in the interpreter, `--jit`, the
REPL, compiled code and JS. A build with no grants compiles to byte-identical IR.

**Architecture:** forge writes a small *grants file* listing each granted package: its name,
its library root, its `forge.toml` line and its scope text. forge passes the file to the
compiler as `MARCH_DEP_GRANTS`; without forge, `--dep-grants FILE` does the same. A module
belongs to the package whose library root contains its source file's real path. A grant is
an implicit `needs` limit on every function of the package, entered only when the call comes
from outside the package. Natively, a TIR pass (`Auth_rt.grants`, after `frames`) turns each
package function into a wrapper that enters a `ByGrant(pkg)` layer around its body, and
retargets the package's internal direct calls to the unwrapped body. So only calls that cross
into the package pay for the frame. The type checker proves each package's reached code by
kind against its grant, using the same bound-point machinery as `restrict`. The wrapper is
dropped where that proof is enough, by phase 4's rule. `Authority.enter_grant` pushes the layer
only when the same grant is not already anywhere in the current authority. Intersection is
idempotent, so the interpreter can frame every call into a granted package and still match the
native output.

**Tech stack:** OCaml 5.5.1 (driver, type checker, TIR, interpreter, forge), March
(`stdlib/authority.march`), JS emitter. No C changes are expected: the policy code is March,
retargeted to C by `Auth_native` as in phases 4 and 5.

**Spec:** `specs/2026-11-10-object-capability-design.md` §3 (a grant is the third size of limit),
§5 (callbacks keep the caller's authority), §10 (grants), §15, §18 (the grants and callbacks
lines), §21 (module-level code under the package's grant), phases table §17 row 6. Grant syntax,
the forge → compiler channel's purpose, packages, caches and `forge audit` carry over from
`specs/2026-11-09-dependency-grants-and-restrict-design.md` §4 and §6. Where they differ, the
2026-11-10 design wins: callbacks are no longer run under the grant. This plan builds on phase 4
(`specs/plans/2026-11-15-ocap-p4-runtime-plan.md`) and phase 5
(`specs/plans/2026-11-19-ocap-p5-restrict-plan.md`).

## What phases 4 and 5 already give us

- `CapLimit` already has `ByGrant(String)`, and `Authority.limit_text` prints it as
  `the grant to package <p>` (`stdlib/authority.march:74`). No Prelude change is needed.
- `Auth_rt.frames` (`lib/tir/auth_rt.ml:228`) shows the wrapper/body split
  (`f` = enter layer, call `f$auth`, restore) and the `$auth_layer` once-per-site cell. Phase 5's
  `restricts` shows the frame-drop rule applied to a non-function site.
- `bin/main.ml:4906-4911` and `lib/jit/repl_jit.ml:593-596` run `restricts` → `frames` →
  `captures`. The JS path shares `bin/main.ml`'s.
- `Restrict_block` in `Typecheck_env.bound_origin` and `restrict_owner` show how a bound point
  that is not a function is recorded and checked by `Typecheck.check_fn_bounds`; the reach chain
  comes from `cap_reach_chain` (`lib/typecheck/typecheck.ml:10164`).
- `Eval.framed_call` (`lib/eval/eval.ml:3914`) is the interpreter's frame entry.
- `test/run_cap_conformance.exe` runs every fixture in five modes, with `-- GRANT:` and
  `-- EXIT-ONLY` headers, `js_unsupported` and `repl_unsupported`.
- From the forge survey:
  - `forge/lib/project.ml:6-21` (the dep variants) and `parse_dep_table` (:155) have no
    `grant` key. `forge/lib/toml.ml:96-120` has no single-quoted literal strings, and a bare
    value stops at the first `,`.
  - `Cmd_build.lib_paths` / `lib_path_env` (`cmd_build.ml:258-297`) and
    `Cmd_test.project_env` (`cmd_test.ml:157`) build `MARCH_LIB_PATH`; `collect_transitive_deps`
    (:191) flattens transitive deps, nearest wins. Each dep expands to its lib root plus every
    subdirectory.
  - The resolver (`lib/resolver/resolver.ml:674`) silently keeps the first of two modules with
    the same name. A dep can shadow an app module.
  - The compiler CAS key hashes every `.march` file on the lib path but not the lib path itself;
    `check_all_cache_key` (`cmd_build.ml:594`) hashes the `lib_path_env` string.
  - `forge audit` and `forge.caps.lock` exist (`forge/lib/cmd_audit.ml`).

## Global Constraints

- A grant is a limit around every function defined in the dependency's package. It is
  intersection, it never widens, and a dependency with no grant is limited only by its own
  `needs` and its caller's authority (design §3, §10).
- `grant` is a list of strings in `needs` syntax, including every scope form. `grant = []`
  grants nothing.
- Reached code only. A reached violation the compiler can see is a build error naming the
  dependency, the `forge.toml` line, the target (or kind) and the call chain. Unreached code
  costs nothing (design §10).
- A transitive dependency reached by direct calls from a granted one runs under that grant,
  and under its own grant too if the consumer gives it one (design §10).
- A callback passed into a granted dependency runs with the caller's authority. A closure,
  pid or handle the dependency hands back carries the dependency's narrowed authority
  (design §5, §10).
- A granted dependency's module-level code runs under the launch authority narrowed by its
  module's `needs` and its package's grant. A function value created there behaves as one of
  the package's named functions (design §21).
- An `extern` reached in a granted dependency needs `IO.Foreign` in the grant (design §10).
- A module belongs to the package whose library root contains its file's real path (design §10).
- Refusals are values: `Err(CapError(kind, target, ByGrant("<package>"), "<grant text>"))`.
- Every runtime gives the same output (design §15). The JS target has no tasks or actors, so
  fixtures that need them go in `js_unsupported` with the reason "the JS target has no tasks".
- A build with no grants (no grants file, or a file with no entries) compiles to byte-identical
  IR (`scripts/oracle-base.sh ir`, rerun on the final head), and the pure-compute benches stay
  within noise.
- Repo rules (CLAUDE.md):
  - Run `dune build --root .` in the worktree.
  - Stage files by name.
  - No attribution lines in commits or PR text.
  - Merge `origin/main`; never rebase or force-push.
  - Never skip or quarantine a test.
  - Update `specs/todos/`, `specs/progress/`, `CHANGELOG.md` and `specs/lang/` (then run
    `scripts/gen-lang-docs.py`) in the same commit.
  - No parser or lexer change is planned. If one becomes necessary, it comes with the
    tree-sitter grammar.
  - A new `bench/*.march` is registered in `test/test_bench_gate.ml`.
  - When stdlib modules change, regenerate `docs/_data/authority.json`
    (`scripts/gen-authority-data.py`) and the explainer fallbacks
    (`node scripts/render-explainer-fallbacks.js`).
  - New slow suites get their own runner; the `compiler` and `rest` CI shards are near 75 minutes.

## Decisions taken in this plan (for the owner to check)

**Open questions for the owner** (my recommendation first; the plan is written to it):

- **Q1. Grants written in a dependency's own `forge.toml`.** If package A's manifest grants its
  dependency B something, does that grant apply when the app is built?
  - *Recommended:* no, not in phase 6. Only the root project's manifest grants. `forge audit`
    lists nested grants as "not applied", and a todo records the follow-up. A nested grant should
    hold only on calls from A into B, not on the app's own calls into B. That needs per-edge
    frames, which is a different mechanism.
  - *Alternative:* apply nested grants on every entry into B. That is simpler to build, but it
    would also limit the app's own direct use of B, which the app never agreed to.
- **Q2. The same module name in two packages.** Today the resolver silently keeps the first.
  - *Recommended:* make it a build error (`dep_module_conflict`) only when a grants file is in
    effect. This covers app vs dep, dep vs dep, a dep module that shadows a stdlib module, and a
    path dep nested inside the project's own library directory. Builds without grants keep
    today's behaviour, so nothing existing breaks and the IR stays identical.
  - *Alternative:* an error in every build. This is stricter, but it can break existing projects
    and it would be a separate `### Changed` item.
- **Q3. Compile-time check of a literal target under a scoped grant.** An example is the
  telemetry URL in design §10's example. The literal-target check for a scoped `needs` clause or
  `restrict` was deferred in phases 4 and 5 (`specs/todos/2026-11-17-ocap-scoped-fn-needs-literal-check.md`).
  - *Recommended:* build it in phase 6 as one helper that takes any scoped bound, and turn it on
    for grants only. The spec's own grant example needs it. Turning it on for `needs` clauses and
    `restrict` can then follow as a one-line change, with its own corpus churn, and the todo stays
    open for that.
  - *Alternative:* grants checked by kind only, and the literal case left to the run-time refusal.

**Settled with the spec (no question):**

1. **A dependency with no `grant` entry** keeps today's behaviour. It is limited only by its own
   `needs` and by its caller's authority, because authority is given and never declared
   (design §10, the `legacy` line and the second **Changed** bullet). It gets no frame and costs
   nothing. `forge audit` marks it "no grant", so an ungranted dependency is visible in review.
2. **`MARCH_LIB_PATH` builds without forge** have no packages and no grants, as today. Every
   lib-path directory is ordinary code under its caller's authority.
   - To use grants without forge, pass `--dep-grants FILE` (or set `MARCH_DEP_GRANTS=FILE`) in
     the grants-file format below. A grant's library root must be one of the `MARCH_LIB_PATH`
     directories, or a parent of some of them. A root that is neither is the error
     `dep_grant_invalid`.
   - forge is just one writer of the file.

**Builder's calls:**

3. **The channel is a file**, not a flag per grant: grant text contains quotes and commas that
   survive neither `MARCH_LIB_PATH`'s `:` list nor shell quoting well.
   - Format: UTF-8, one package per line, four tab-separated fields:
     `<package>\t<lib root, absolute>\t<manifest>:<line>\t<scope text>`.
   - A line starting with `#` is a comment. A field containing a tab or newline is rejected.
   - The scope text is the grant's strings joined with `", "`. `()` means `grant = []`.
   - forge writes `<project>/.forge/dep-grants` only when at least one dependency has a grant;
     otherwise it writes nothing and leaves `MARCH_DEP_GRANTS` unset.
   - Precedence: `--dep-grants` overrides `MARCH_DEP_GRANTS`.
4. **Parsing a grant in OCaml** reuses the real parser with no grammar change.
   `Dep_grants.parse_scope_text` parses `mod G__ do needs <text> end` with
   `March_parser.Parse.module_`, accepts only a module whose sole content is that `needs` line,
   and returns its entries. The entries are then checked with `validate_cap_scopes`. On an error,
   the diagnostic's span is the manifest line.
5. **Package membership** is the longest library root that is a prefix of the file's
   `Unix.realpath`. Files under no root belong to no package: the app, the stdlib and ungranted
   deps all fall here. Membership is decided once per file and cached.
6. **Which calls enter a grant (native).** `Auth_rt.grants` runs after `frames`, on pre-mono TIR.
   - Every top-level fn tagged with granted package P becomes a wrapper under its own name. The
     wrapper enters `ByGrant(P)` and calls `f$grant`, which holds the original body.
   - A direct call to a P-tagged fn is retargeted to its `$grant` body only when it sits in the
     body of a P fn whose own wrapper is kept (so the grant is certainly in force), and not
     inside a lambda: a lambda can run after its maker returns. If a P fn's wrapper was dropped,
     its calls keep the callee's wrapper name. Otherwise a dropped caller could reach a framed
     callee (one that spawns an actor, say) without the grant.
   - All other calls keep the original name, and so enter the frame: calls from the app, from
     other packages, from stdlib code (including generic code that mono later resolves to a P
     impl), and value uses. The safe name is the default, so a path the pass does not know about
     costs a frame, never a hole.
   - Wrappers that nothing outside P calls are removed by dead-code elimination.
7. **When the grant frame is dropped (native).** A P fn keeps its wrapper unless all of these
   hold:
   - the grant text carries no scope;
   - the type checker proved the fn's transitive row within the grant's kinds
     (`Dep_grants.proven`);
   - the fn is in neither `reaches_actor_spawn` nor `reaches_indirect_call`.
   This is phase 4's rule plus the proof bit. The proof bit keeps a frame on code the checker did
   not report only because it was unreached. The interpreter always frames.
8. **`Authority.enter_grant(layer)`** pushes unless a layer with the same limit and text is
   anywhere in the current list. Intersection is idempotent, so this is exact, and it keeps deep
   recursion through a granted package (which interleaves fn-needs layers) from growing the list.
   `enter_fn` is unchanged.
9. **Module-level code of a granted package.**
   - Its initialisers run inside the package's grant frame. Natively they are P-tagged zero-arg
     init fns, so they get wrappers; the interpreter evaluates P's top-level lets under
     `enter_grant`.
   - A lambda made by P's module-level code still captures nothing (design §21). It gets a grant
     prologue instead (`enter_grant` / `cap_restore` around its body), so it runs as one of P's
     named functions would: under its caller's authority ∩ the grant. Without this, a package
     could park `let leak = fn url -> HttpClient.get(url)` at top level and escape its grant.
10. **The static check.**
    - For each granted package, one bound point is recorded, keyed `<package>$grant`, with origin
      `Dep_grant { pkg; manifest; text }` and the grant's kinds.
    - Its reach is:
      - every P fn referenced from code outside P: direct calls, value uses and dispatch-node
        edges into P impls;
      - P's module-level expressions.
    - `check_fn_bounds` judges it as it judges a restrict. An `extern` counts as `IO.Foreign`
      already (`typecheck_caps.ml:1990`), so the `IO.Foreign` rule needs no new code, only a test.
    - New diagnostic `dep_grant_exceeded`, with this message (the reach chain is
      `cap_reach_chain`'s, prefixed by the outside caller):
      "`<pkg>` is granted `<text>`, but `<fn>` needs `<kind>` (`<chain>`)".
      - Primary span: the outside call that starts the chain.
      - Note: `granted at <manifest>:<line>`.
      - Hint: "widen the grant in forge.toml, or stop calling `<entry>`".
    - The checker also fills `Dep_grants.proven` with the P fns whose rows lie within the grant
      (decision 7).
11. **Diagnostic codes:**
    - `dep_grant_exceeded`: reached code needs a kind the grant lacks.
    - `dep_grant_scope`: a literal target outside a scoped grant (Q3).
    - `dep_grant_invalid`: a malformed grant, or a bad grants file or library root.
    - `dep_module_conflict`: Q2.
    Each gets a `--explain` page and error-corpus cases.
12. **Caches.** The grants file's digest (or `none`) becomes the flag tag `grants:<hex>` in:
    - the compiler CAS key for `--check` and for `--compile` (`build_cas_key`);
    - the depend-mode key;
    - `interp_cap_cache_key`.
    forge hashes the file's contents in `check_all_cache_key`. With no grants the tag is absent,
    not `none`, so cache keys and IR for grant-free builds are unchanged.
13. **forge.**
    - `grant` is accepted in inline dep tables and `[deps.X]` sections of `deps`, `dev_deps` and
      `test_deps`.
    - `toml.ml` gains single-quoted literal strings and arrays whose strings contain commas.
    - Each `dep` gets a grant through a wrapper record: `type dep_entry = { source : dep; grant :
      string list option; grant_line : int }`. Only the root project's grants are written (Q1).
    - `MARCH_DEP_GRANTS` is added in `lib_path_env`, in `Cmd_test.project_env`, and in the other
      lib-path builders (`cmd_audit.ml:1013`, `cmd_notebook.ml:61,212`, `cmd_install.ml:77`).
    - `forge audit` shows each dep's grant beside its declared and inferred capabilities, or "no
      grant".
    - `forge.caps.lock` records the grant, and a widened or added grant is reported as an
      escalation by `diff`.
14. **Deferred, each with a todo:** Q1's nested grants; Q3 for `needs` clauses and `restrict`
    (widen the existing todo); mutual tail recursion across granted wrappers grows the stack by one
    wrapper per hop (append to `specs/todos/2026-11-17-ocap-framed-mutual-tail-recursion.md`).

## Performance approach and budget

| Path | Mechanism | Budget (checked by) |
|---|---|---|
| No grants | No grants file is loaded; `Auth_rt.grants` returns the module physically unchanged; no cache tag | `scripts/oracle-base.sh ir`: **zero** changed programs, run after Task 3 and again on the final head |
| Pure compute | Unchanged | `scripts/perf-ab.sh` verdict `~` on cpu for `fib tree_transform binary_trees list_ops list_ops_nested json_stream println_loop` |
| Unscoped grant, proven, frame dropped | The call is a plain call | `bench/grant_enter_static.march`: within noise of the same loop calling an ungranted copy |
| Grant boundary, framed | One `$auth_layer` cell read, `enter_grant` (a scan of 1–3 layers: two string compares each), one `cap_restore` | `bench/grant_enter.march`: report ns per boundary call; target ≤ 50 ns |
| Call inside a granted package | Retargeted to the body: no frame | Same bench, inner loop of 1,000 internal calls per boundary call: within noise of the ungranted copy |
| Compile time | Membership is one `realpath` per file; the bound point reuses the restrict machinery | `--check` wall time on `examples/` with and without a grants file, reported |

The cost per boundary call is (bench wall time − the wall time of the same loop against an
ungranted copy of the package) / boundary calls, measured compiled at `--opt 2` with 11
interleaved runs. All numbers go into the PR body.

## Review Focus

1. **A dependency function used as a value by the app** (`List.map(xs, Dep.fetch)`) and **a
   dependency impl reached through generic stdlib code** (`Show` of a dependency type). Each runs
   under the grant, because value uses and mono-resolved impl calls keep the wrapper's name.
   Pinned by `grant_named_fn_value` and `grant_impl_dispatch`.
2. **A closure made by a granted package's module-level code and called by the app.** It runs
   under the app's authority ∩ the grant, never the app's full authority. Pinned by
   `grant_module_level_closure`.
3. **Recursion that goes in and out of the package**: app → dep → callback in the app → dep,
   10,000 deep. Each callback runs with the app's authority, and each re-entry narrows again.
   The layer list stays bounded within one level of nesting. Pinned by `grant_callback_reentry`.
4. **A grants file with a hostile or odd entry**: a root that is a symlink to the app's own lib,
   a root with a trailing `/`, a relative root, a tab inside the scope text, two packages whose
   roots nest. The first three are normalised or rejected with `dep_grant_invalid`, never
   silently ignored. Nested roots attribute by longest prefix. Pinned in `test/test_dep_grants.ml`.
5. **A dependency that defines a module the app or the stdlib also defines**, under a grant
   (Q2). It is `dep_module_conflict`, not a silent shadow that runs ungranted. Pinned by the
   error-corpus case `dep_module_conflict_1`.

---

### Task 1: The grants file and package membership (`March_caps.Dep_grants`)

**Files:**
- Create: `lib/caps/dep_grants.ml` + `.mli` (add to `lib/caps/dune`; it may need
  `march_parser` as a dependency for decision 4. If that makes a cycle, put the module in
  `lib/driver/` instead and note it in the commit)
- Modify: `bin/main.ml` (the `--dep-grants FILE` flag on the compile/check/run path, `march test`
  and `march repl`; load once, before resolving imports)
- Test: `test/test_dep_grants.ml` (new), run by a new `test/run_dep_grants.exe` (dune, plus
  `scripts/run-tests.sh` suite `dep_grants`, plus a rule in `scripts/affected.sh` and
  `scripts/test-affected.sh`, plus a CI job or an existing small shard: not `compiler` or `rest`)

**Interfaces (Produces):**
```ocaml
type grant = {
  g_pkg : string;            (* forge dep name, as written *)
  g_root : string;           (* realpath of the library root, no trailing slash *)
  g_manifest : string;       (* "forge.toml" path as given *)
  g_line : int;              (* 1-based line of the dep's entry *)
  g_text : string;           (* canonical scope text, "()" for none *)
  g_entries : (March_ast.Ast.name list * string option) list;
  g_scoped : bool;
}
val load : ?flag:string -> unit -> (grant list, string * int option) result
  (* flag > MARCH_DEP_GRANTS > none; Ok [] when neither is set *)
val parse_scope_text : string -> ((March_ast.Ast.name list * string option) list, string) result
val set_active : grant list -> unit
val active : unit -> grant list                       (* [] = no grants: every pass is the identity *)
val package_of_file : string -> grant option          (* longest-root match on realpath, memoised *)
val digest : unit -> string option                    (* None when no grants are active *)
val proven : (string, unit) Hashtbl.t                 (* filled by the type checker, Task 3 *)
```

- [ ] Step 1: Write tests:
  - `load_none` (no flag, no env → `Ok []`, `digest () = None`);
  - `load_two` (a two-line file round-trips every field; `g_text` of `'IO.NetConnect("a.test/v1/", methods(get))'` keeps its exact text and `g_scoped = true`);
  - `load_unit` (`()` gives `g_entries = []`);
  - `load_rejects` (a malformed scope, a relative root, a missing field and a nonexistent root each give `Error` with the line number);
  - `membership_longest_prefix` (roots `/t/a` and `/t/a/sub`: a file in `/t/a/sub/x.march` is in the second; `/t/ab/x.march` is in neither);
  - `membership_symlink` (a symlinked file inside a root is attributed by its real path);
  - `flag_overrides_env`.
- [ ] Step 2: Run `scripts/run-tests.sh dep_grants` and expect FAIL.
- [ ] Step 3: Implement. Wire the flag into `bin/main.ml` so that `active ()` is set before anything type-checks.
- [ ] Step 4: Run `scripts/run-tests.sh dep_grants compiler` and expect PASS.
- [ ] Step 5: Commit `ocap p6: the dep-grants file and package membership`.

### Task 2: `enter_grant`, grant layers, and the conflict check

**Files:**
- Modify: `stdlib/authority.march`:
  - add `grant_layer(pkg : String, text : String) : Layer`, which returns `Layer(ByGrant(pkg), text, parsed)` and panics with `internal:` on a parse failure (the text was validated at compile time);
  - add `enter_grant(layer : Layer) : CapAuthRef`, which calls `cap_save()` if any layer in `cap_layers()` has the same limit and text, and `cap_push(layer)` otherwise;
  - add `has_layer`.
- Modify: `lib/tir/auth_native.ml`, only if the C retarget needs to know the new fns (check `Auth_native.applicable` still holds: no new short type names)
- Modify: `lib/resolver/resolver.ml` (:674 and :401): when `Dep_grants.active () <> []`, a module name defined by two files in different packages (counting "no package" and the stdlib each as one side) is `dep_module_conflict`. This includes a dep module that shadows a stdlib module, and a granted root inside the project's own library directory. Builds without grants are unchanged (Q2)
- Modify: `lib/errors/code.ml` (`dep_grant_exceeded`, `dep_grant_scope`, `dep_grant_invalid`, `dep_module_conflict`) and the explain registry
- Regenerate: `docs/_data/authority.json` and the explainer fallbacks
- Test: `test/stdlib/test_authority.march` (doctests/tests for `enter_grant`); `test/test_dep_grants.ml` (conflict cases); `test/errors/dep_module_conflict_1` (seeded with `scripts/seed-error-corpus.sh`; if `run_errors` cannot set up a lib dir and a grants file, add a `-- DEP:` header to it the way Task 6 adds one to the conformance runner, and document it in its header comment)

- [ ] Step 1: Write tests:
  - `enter_grant` on a list that already holds the same grant two layers down leaves `List.length(cap_layers())` unchanged;
  - on a list without it, the length grows by one;
  - `describe` of a refusal by `grant_layer("weather", "IO.Console")` prints `IO.Clock refused by the grant to package weather (IO.Console)`;
  - conflict tests: app vs dep, dep vs dep, dep vs stdlib (`List`), each an error under a grants file and accepted, as today, without one.
- [ ] Step 2: Run `scripts/run-tests.sh -q stdlib_march dep_grants errors` and expect FAIL.
- [ ] Step 3: Implement.
- [ ] Step 4: Run the same suites and expect PASS. Run `scripts/oracle-base.sh ir` and expect **zero** changed programs: the new March fns must not be linked into a program that never calls them.
- [ ] Step 5: Commit `ocap p6: grant layers, enter_grant, and the same-module conflict check`.

### Task 3: The static check

**Files:**
- Modify: `lib/typecheck/typecheck_env.ml`: add `Dep_grant of { pkg : string; manifest : string; text : string }` to `bound_origin`, and a `grant_owner` record beside `restrict_owner` (`go_refs : (string * Ast.span * string (* outside caller *) * ref_use) list`, `go_ops` for P's module-level expressions)
- Modify: `lib/typecheck/typecheck_caps.ml` / `typecheck.ml`:
  - while walking each fn's refs, a ref from a fn whose decl file is outside package P to a fn of P (a call, a value use or a dispatch edge into a P impl) is added to P's `go_refs`;
  - P's module-level expressions go to `go_ops`;
  - record the bound point `<pkg>$grant`;
  - in `check_fn_bounds`, report a violation with `dep_grant_exceeded` (decision 10). Report one diagnostic per (package, kind), at the first outside call in source order;
  - fill `Dep_grants.proven` with every P fn whose transitive row is within the grant's kinds and does not reach unknown;
  - validate each grant's entries with `validate_cap_scopes` and report problems as `dep_grant_invalid` at the manifest line.
- Create (Q3): `lib/typecheck/scoped_literal_check.ml`. It holds one function that runs the module-scope literal checks (hosts via `Host_scope`, paths via `Cap_scope`, names via `name_uses`) over a set of fns, against given scope entries, and reports with a given code and wording. Call it for each scoped grant over the P fns in the reach of `<pkg>$grant`, as `dep_grant_scope`: "`<pkg>` is granted `<text>`, but `<fn>` connects to `<target>` (`<chain>`)". Comment that `needs` clauses and `restrict` can call it (the todo stays open).
- Test: `test/test_dep_grants.ml` (end-to-end `march --check` with a temp lib dir and grants file); `test/errors/` cases:
  - `dep_grant_exceeded_1` (kind);
  - `dep_grant_exceeded_2` (reached through a transitive ungranted dep);
  - `dep_grant_exceeded_3` (an `extern` without `IO.Foreign`);
  - `dep_grant_scope_1` (a literal telemetry host);
  - `dep_grant_invalid_1`.

- [ ] Step 1: Write tests, with fixtures under `test/dep_grants/<case>/{app.march,lib/...}`:
  - the owner's three cases, end to end:
    - an API client limited to one path with GET passes `--check`;
    - a many-feature dep whose unreached `Telemetry.ping` connects elsewhere passes `--check`;
    - reaching `Telemetry.ping` fails with `dep_grant_scope`, and the message names `weather`, `forge.toml:<line>`, the host and `Main.main → Weather.forecast → Weather.Telemetry.ping`;
  - a kind outside the grant is `dep_grant_exceeded`;
  - a dep with no grant entry that does the same thing passes;
  - an app-level callback passed to the dep that does IO outside the grant passes (the callback is charged to the app);
  - `grant = []` with a reached `println` fails.
- [ ] Step 2: Run `scripts/run-tests.sh dep_grants errors` and expect FAIL.
- [ ] Step 3: Implement.
- [ ] Step 4: Seed and regenerate only the new error cases (`ERRORS_ONLY=dep_grant_ UPDATE_ERRORS=1 ./_build/default/test/run_errors.exe -e`), review `git diff test/errors/`, then run `scripts/run-tests.sh compiler errors dep_grants` and expect PASS. Run `scripts/oracle-base.sh types` and `scripts/oracle-base.sh ir`, and expect no changed fixture.
- [ ] Step 5: Commit `ocap p6: check a granted package's reached code against its grant`.

### Task 4: Native frames: `Auth_rt.grants` (compiled, `--jit`, REPL JIT, JS)

**Files:**
- Modify: `lib/tir/lower_state.ml`: `type fn_grant = { fg_pkg : string; fg_text : string; fg_scoped : bool; fg_proven : bool }` and `fn_grant_tbl : (string, fn_grant) Hashtbl.t`, keyed by TIR fn name and reset with `fn_needs_tbl`. Fill it at the four `note_fn_needs` sites (`lib/tir/lower.ml:886,925,1026`, `lib/tir/lower_decls.ml:521`) from the def's span file via `Dep_grants.package_of_file`, plus each module-level init fn. `fg_proven` reads `Dep_grants.proven` by the fn's qualified name
- Modify: `lib/tir/auth_rt.ml` + `.mli`:
  ```ocaml
  val grants :
    Tir.tir_module -> tbl:(string, Lower_state.fn_grant) Hashtbl.t -> Tir.tir_module * bool
    (* decisions 6, 7, 9; [m] physically and [false] when [tbl] is empty *)
  ```
  The layer fn is `<pkg>$grant$auth_layer() = Authority.grant_layer("<pkg>", "<text>")`, one per package, so `march_cap_layer_once` and the JS memo apply. The wrapper is `let l = …; let s = Authority.enter_grant(l); let r = f$grant(args); cap_restore(s); r`. Module-init lambdas of P (`Lower_state.is_module_init_lambda`) get the same prologue around their body.
- Modify: `bin/main.ml:4906-4911` and `lib/jit/repl_jit.ml:593-596`: run `grants` after `frames`, and set `has_frames = frames_kept || restricts_kept || grants_kept` for `captures`
- Test: `test/test_auth_rt.ml` (cases on lowered TIR with a synthetic `fn_grant_tbl`); `test/snapshots/src/auth_grant.march` (new TIR snapshot. If the snapshot runner cannot take a grants file, set the table directly in the test instead and say so)

- [ ] Step 1: Write `test_auth_rt.ml` cases:
  - an empty table leaves the module physically equal, with `kept = false`;
  - a scoped grant wraps every P fn, and an internal call is retargeted to `$grant` while a call from a non-P fn is not, and neither is a call inside a lambda made in a P fn;
  - an unscoped grant where P fn `f` is proven and dropped but `g` spawns an actor: `f`'s call of `g` keeps `g`'s wrapper name;
  - an unscoped, proven, spawn-free fn is not wrapped;
  - an unscoped fn that is not proven is wrapped;
  - an unscoped proven fn that reaches `List.map(xs, f)` is wrapped;
  - a P module-init lambda gets the grant prologue;
  - a lambda made inside a wrapped fn is captured (`captures` with `has_frames = true`).
- [ ] Step 2: Run `scripts/run-tests.sh -q compiler` and expect FAIL.
- [ ] Step 3: Implement.
- [ ] Step 4: Run `scripts/run-tests.sh compiler codegen test_jit`, add the snapshot, review `git diff test/snapshots/` (only `auth_grant` may change), and expect PASS. Run `scripts/oracle-base.sh ir` and expect zero changes.
- [ ] Step 5: Commit `ocap p6: ByGrant frames at package boundaries; drop them where the proof suffices`.

### Task 5: The interpreter

**Files:**
- Modify: `lib/eval/eval.ml`:
  - next to `framed_call`, add `granted_call`. When the fn's decl file is in a granted package, it enters the package's layer (built once per package with March `Authority.grant_layer`) with `Authority.enter_grant`, and restores under `Fun.protect`. Wrap it outside `framed_call`, at the three sites that build a fn's closure (:3957, :4045, :4678);
  - evaluate a granted module's top-level lets under the same entry;
  - give a lambda made by that module-level code the same prologue (decision 9).
- Test: `test/test_eval.ml` cases (with a temp lib dir and grants file, or by setting `Dep_grants.set_active` directly)

- [ ] Step 1: Write cases:
  - `grant_refuses_computed_eval`: a dep fn computing a path outside `IO.FileRead("/srv/")` gets an `Err` whose `describe` ends `refused by the grant to package up (IO.FileRead("/srv/"))`;
  - `grant_callback_eval`: an app callback run by the dep is admitted;
  - `grant_module_closure_eval`: a dep's top-level closure called by the app is refused.
- [ ] Step 2: Run `scripts/run-tests.sh -q eval` and expect FAIL.
- [ ] Step 3: Implement.
- [ ] Step 4: Run `scripts/run-tests.sh eval stdlib_march` and expect PASS.
- [ ] Step 5: Commit `ocap p6: grants in the interpreter`.

### Task 6: Conformance fixtures across the five modes

**Files:**
- Modify: `test/run_cap_conformance.ml`: a repeatable header `-- DEP: <package> <dir relative to test/cap_conformance/> <scope text or "none">`. The runner adds each dir to `MARCH_LIB_PATH`, writes a grants file (to the private temp dir) for those whose text is not `none`, and sets `MARCH_DEP_GRANTS` for every mode including the REPL. Document the header in the file comment.
- Create: `test/cap_conformance/deps/<pkg>/…` library dirs and these fixtures (a `.march` and an `.expected` each). As in phase 5, put the probing calls in named helper fns, not in `main`'s body, so the REPL reports the same lines.
  - `grant_refuses_scoped` (a dep's computed file path or URL outside the grant);
  - `grant_callback_keeps_caller_authority`;
  - `grant_callback_reentry` (Review Focus 3);
  - `grant_returned_closure_keeps_grant` (the closure is called by the app after the dep call returns);
  - `grant_named_fn_value`;
  - `grant_impl_dispatch`;
  - `grant_module_level_closure`;
  - `grant_transitive_inherits` (granted A calls ungranted B: refused by A's grant);
  - `grant_transitive_both` (B granted too: the innermost refusing layer is named);
  - `grant_ungranted_dep_unrestricted`;
  - `grant_unit_grants_nothing` (a computed probe under `grant = []`);
  - `grant_unscoped_frame_dropped` (same output in all modes while natively there is no frame);
  - `grant_reenter_noop` (10,000-deep recursion inside the dep; prints the layer count at the bottom);
  - `grant_panic_caught_restores`;
  - `grant_actor_restricted_for_life` (a dep-spawned actor, across a supervisor restart);
  - `grant_task_inherits`;
  - `grant_under_restrict` (an app `restrict` around a dep call: both layers, innermost refusal named);
  - `grant_under_launch` (`-- GRANT:` narrower than the request; a refusal by the launch names the launch).
  - Add the actor and task fixtures to `js_unsupported` with "the JS target has no tasks".
- [ ] Step 1: Write the fixtures. Generate the `.expected` files from the interpreter with `UPDATE_CAP_CONFORMANCE=1` **only after** checking each against the rule it names. The commit body gets one line per fixture.
- [ ] Step 2: Run `scripts/run-tests.sh cap_conformance`. Every mode must agree (JS `SKIP` only where listed). On a mismatch, fix the backend, not the fixture.
- [ ] Step 3: Prove it goes red: make `Auth_rt.grants` return the module unchanged, run the suite, and confirm `grant_refuses_scoped` fails in compiled, jit and js modes. Then make the interpreter's `granted_call` a pass-through and confirm the interpreted mode fails. Revert both, and record them in the commit body.
- [ ] Step 4: Commit `test: ocap p6 conformance fixtures for dependency grants`.

### Task 7: forge: `grant` in `forge.toml`, the grants file, caches, `forge audit`, `forge.caps.lock`

**Files:**
- Modify: `forge/lib/toml.ml` (single-quoted literal strings; strings inside arrays may contain `,`, `]` and `#`)
- Modify: `forge/lib/project.ml` (`dep_entry` per decision 13; `parse_dep_table`, `parse_deps_section`, `parse_section_deps`; `dep_table_keys` gains `grant`; record the entry's line)
- Modify: `forge/lib/cmd_build.ml` (write `.forge/dep-grants` from the root project's grants and each granted dep's resolved lib root; `lib_path_env` adds `MARCH_DEP_GRANTS=<abs path>`; `check_all_cache_key` hashes the file's contents), `forge/lib/cmd_test.ml` (`project_env`), `cmd_audit.ml:1013`, `cmd_notebook.ml:61,212`, `cmd_install.ml:77`
- Modify: `forge/lib/cmd_audit.ml` (a "grant" column, "no grant" for ungranted deps, and "not applied" for nested-manifest grants per Q1; `write_baseline` / `read_baseline` / `diff` carry the grant; a new or widened grant is an escalation, and a narrowed one is not)
- Modify: `bin/main.ml` (`grants:<hex>` in the CAS flags, `build_cas_key`, the depend-mode key and `interp_cap_cache_key`, per decision 12)
- Test: the forge test suite (find with `ls forge/test`): TOML literal strings with commas; a dep with a grant round-trips; a `forge build` of a two-package fixture writes the expected `.forge/dep-grants` and sets the env; no grant means no file and no env; `forge.caps.lock` diff flags a widened grant. `test/test_dep_grants.ml`: changing one byte of the grants file changes the `--check` CAS key; no file gives the same key as before this branch (compare against a key computed with grants inactive).

- [ ] Step 1: Write the tests.
- [ ] Step 2: Run them and expect FAIL.
- [ ] Step 3: Implement.
- [ ] Step 4: Run the forge suite, `scripts/run-tests.sh dep_grants`, and an end-to-end `forge build` + run of `test/dep_grants/forge_e2e/` (a two-package project whose dep is refused at run time by a scoped grant). Expect PASS.
- [ ] Step 5: Commit `forge: dependency grants in forge.toml, the grants file, audit and lock`.

### Task 8: Benchmarks, IR proof, docs, specs, changelog, PR

**Files:**
- Create:
  - `bench/grant_enter.march`, with its dependency in `bench/grant_enter_dep/`: 1,000,000 app → dep calls of a fn under a scoped grant, each doing 1,000 internal dep calls of `n + 1`; prints the sum.
  - `bench/grant_enter_static.march`: the same with an unscoped proven grant.
  - Register both in `test/test_bench_gate.ml`. If the gate cannot pass a lib path and a grants file, extend it with a per-bench environment (preferred) rather than skip-listing them.
  - `scripts/bench-grants.sh`: builds both benches and an ungranted control, with 11 interleaved runs, and prints ns per boundary call.
- Modify:
  - `specs/benchmarks.md` (grant changes → these two benches, plus `list_ops`);
  - `specs/lang/capabilities.md` (a "Dependency grants" section: syntax, meaning, ungranted deps, transitive deps, callbacks, module-level code, `extern`, packages and conflicts, `--dep-grants` and its file format, `ByGrant`, when a frame is kept); then run `scripts/gen-lang-docs.py`;
  - the forge docs that describe `forge.toml` deps and `forge audit` (find with `grep -rln "forge.caps.lock\|\[deps\]" docs specs/lang forge/README*`);
  - `CHANGELOG.md` `[Unreleased]`: `### Added` for dependency grants, `--dep-grants`, and the `forge audit` and lock grant columns; `### Changed` for `dep_module_conflict` under grants.
- Create: `specs/progress/2026-11-22-ocap-p6-grants.md`; the todos in decision 14 (new: `specs/todos/2026-11-22-ocap-nested-manifest-grants.md`); update `specs/todos/2026-11-12-ocap-capture-checking.md` if it names phase 6.

- [ ] Step 1: Write the benches, register them, and run `scripts/run-tests.sh -q` (bench gate).
- [ ] Step 2: Perf:
  - Run `scripts/perf-ab.sh --runs 15 --no-counter-gate --cand-dir . --benches "fib tree_transform binary_trees list_ops list_ops_nested json_stream println_loop" origin/main` and record the load average. Repeat once if any row is outside noise.
  - Run `scripts/bench-grants.sh` and report ns per boundary call against the budget.
  - Report `--check` wall time on `examples/` with and without a grants file.
- [ ] Step 3: Run `scripts/check-docs.sh`, `scripts/check-tree-sitter.sh`, and the full `scripts/run-tests.sh` (including `refinecheck`), and expect PASS.
- [ ] Step 4: Commit `docs/specs: ocap phase 6`. Merge `origin/main`, then run `scripts/oracle-base.sh ir` on the **final head** and expect zero changed programs outside the new benches. Push, and open the PR with the perf and IR numbers in its body. Drive CI and Doc lint to green, mark the PR ready for review, and do not merge it.

---

## Self-review notes

- **Spec coverage:**
  - §10 syntax and meaning: Tasks 1, 4, 5 and 7.
  - "reached code only" and the error naming the dep, line, target and chain: Task 3 (and Q3).
  - Transitive deps: `grant_transitive_*`.
  - `extern` needs `IO.Foreign`: `dep_grant_exceeded_3`.
  - Package by real path, and same name in two packages: Tasks 1 and 2 (Q2).
  - `forge audit` and `forge.caps.lock`: Task 7.
  - Caches: Task 7 (decision 12).
  - Both **Changed** bullets: `grant_callback_keeps_caller_authority`, `grant_returned_closure_keeps_grant`, `grant_ungranted_dep_unrestricted`.
  - §21 module-level code: decision 9, `grant_module_level_closure`.
  - §15 every runtime: Task 6. §18 grants and callbacks: Task 6.
  - §15 cost: the budget table.
- **Not in the spec but needed:** the grants-file format and `--dep-grants` (design §20 leaves the channel to the builder).
- **Types:** `Dep_grants.grant`, `Lower_state.fn_grant`, `Dep_grant` and `Authority.enter_grant` / `grant_layer` are named the same in every task that uses them.
