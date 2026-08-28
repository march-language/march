# Decomposing `lower.ml`, `desugar.ml`, `perceus.ml` (finding 3)

> **For agentic workers:** each task is a *behaviour-preserving band move*. There is no
> new behaviour to test, so the TDD cycle is replaced by an equivalent discipline:
> record an oracle baseline, prove the oracle goes **RED** on a deliberate perturbation,
> then require **GREEN** plus a byte-identical splice check. Steps use `- [ ]` syntax.

**Goal:** close finding 3 of `specs/2026-08-25-file-decomposition-analysis.md` — the three
sizeable, actively-edited pass files that never got a decomposition phase.

**Architecture:** each file already has a helper family (`lower_*`, `perceus_*`) or none at
all (`desugar`). Each retains exactly one oversized band. Move that band **verbatim** into a
new sibling module and re-export the names the rest of the file still uses, via the
one-line alias idiom these files already use (`let lower_ty = Lower_types.lower_ty`).
No call sites change; no code is edited in transit.

**Tech stack:** OCaml 5.3.0, dune, opam switch `march`.

## Global Constraints

- Never `git stash` in a march worktree (shared stash stack). Use a temporary WIP commit.
- `git add` explicit paths only — never `-A`, `.`, `-a`, `*`.
- No `Co-Authored-By` trailers.
- Never prefix a command with `eval $(opam env …)`.
- Build with `dune build --root . <targets>`; a targetless `dune build --root .` wedges.
- Judge every command by its exit code, never by tail output, and never through a pipe.
- Run all oracles under a **private `HOME`** — `~/.cache/march` is shared across worktrees
  and its cached spans carry the populating worktree's absolute paths (phantom diffs).
- Suffix every `/tmp` path with a worktree slug; other agents share this box.
- Update `specs/todos/` → `specs/progress/` and `CHANGELOG.md` in the same commit.

## Measured seams (re-derive before trusting)

Measured at `5d91f41d`, recursion-group aware. Dependency direction checked on
**comment-stripped code**, because a plain `grep` counts prose mentions and invents
forward dependencies that do not exist (this happened on F1: `insert_rc`, `perceus`
and `insert_fbip` all appear only in comments).

| Task | File | Band | Lines | Needs from above | Forward deps | Names to re-export | File after |
|---|---|---|---:|---|---|---:|---:|
| D | `lib/desugar/desugar.ml` | `:1339–2529` | 1,191 | none | none | 6 | 3,320 → 2,135 |
| E | `lib/tir/lower.ml` | `:101–1050` | 950 | 16 (all existing one-line aliases) | none | 3 | 2,000 → 1,051 |
| F | `lib/tir/perceus.ml` | `:134–1375` | 1,242 | `fresh_rc_var` (3) | none | 14 | 1,997 → 756 |

**Order: D → E → F**, by ascending risk. D is a leaf cluster with zero dependencies in
either direction. E sits at the centre of an existing broken cycle
(`Lower_match.install_lower_expr`), so its init hook must travel with the band. F is RC
code, where bugs are historically expensive, so it goes last and additionally runs the
FBIP benchmark.

## What is NOT in this plan, and why

Two `desugar.ml` clusters look extractable and are not:

- **The `~H` sigil cluster (`:105–693`, 589 lines)** calls *forward* into `desugar_expr`
  (3 sites) and `desugar_module` (1). Extracting it creates a cycle that would need a
  second forward-ref hook of the `install_lower_expr` kind. Not worth a 589-line win.
- **The intra-module qualification tail (`:2857–3320`, 464 lines)** needs 13 names from
  above *and* defines the public `desugar_module`, so it cannot sit on either side of
  `desugar.ml` without a cycle. It would require turning `desugar.ml` into a thin
  re-export shell — a different, larger change.

`lower.ml` and `perceus.ml` were each already decomposed once (Wave 3 Tasks 9 and 5).
Their headers are accurate: what remains is the orchestrator plus the mutually-recursive
core. This plan takes the one further band each that is provably clean, and stops.

---

### Task D: extract the derive-expansion cluster

**Files:**
- Create: `lib/desugar/desugar_derive.ml`
- Modify: `lib/desugar/desugar.ml` (remove `:1339–2529`, add 6 alias lines at that position)

**Interfaces:**
- Produces: `Desugar_derive.{mk_name, respan_ty, collect_type_defs, collect_fns,
  expand_derive, expand_satisfy}` — plus `derive_impl`, which is private to the band and
  has exactly one call site, inside the band's own `expand_derive`.
- Consumes: nothing. The band references no name defined elsewhere in `desugar.ml`.

- [ ] **Step 1: record the baseline** (before any edit)

```bash
export HOME=/tmp/march-home-bartik-D
mkdir -p "$HOME/.cache"
scripts/ir-oracle.sh     baseline /tmp/ir-base-bartik-D
scripts/types-oracle.sh  baseline /tmp/ty-base-bartik-D
scripts/refine-oracle.sh baseline /tmp/rf-base-bartik-D
```

- [ ] **Step 2: prove the oracle is not vacuous — it must go RED**

Perturb one arm deliberately, then check. Expected: **non-identical**.

```bash
sed -i '' 's/impl_methods     = methods;/impl_methods     = List.rev methods;/' lib/desugar/desugar.ml
scripts/ir-oracle.sh check /tmp/ir-base-bartik-D   # must report a DIFFERENCE
git checkout -- lib/desugar/desugar.ml
```

If this reports IDENTICAL, stop: the oracle is not covering this file and the rest of the
task proves nothing.

- [ ] **Step 3: move the band verbatim**

```bash
sed -n '1339,2529p' lib/desugar/desugar.ml > /tmp/bartik-band-D.ml
{ printf '%s\n' \
  '(** Derive expansion: [derive Eq, Show, …] and [satisfy] expansion, plus the' \
  '    span-uniquification machinery every derived node depends on.' \
  '' \
  '    Moved VERBATIM out of [Desugar] (finding 3 of the file-decomposition' \
  '    analysis).  The band was self-contained: it referenced nothing defined' \
  '    elsewhere in [desugar.ml] and nothing below it, which is why it could' \
  '    move without a forward-ref hook.  Six names are re-exported from' \
  '    [Desugar] so external callers and the rest of the pass are unchanged. *)' \
  '' \
  'open March_ast.Ast' \
  'module Err = March_errors.Errors' \
  '' ; cat /tmp/bartik-band-D.ml; } > lib/desugar/desugar_derive.ml
```

Then delete `:1339–2529` from `desugar.ml` and put this in its place:

```ocaml
(* ── Derive expansion (moved to [Desugar_derive]; re-exported so the rest of
   this pass and [desugar.mli] are unchanged) ─────────────────────────────── *)
let mk_name = Desugar_derive.mk_name
let respan_ty = Desugar_derive.respan_ty
let collect_type_defs = Desugar_derive.collect_type_defs
let collect_fns = Desugar_derive.collect_fns
let expand_derive = Desugar_derive.expand_derive
let expand_satisfy = Desugar_derive.expand_satisfy
```

- [ ] **Step 4: build**

Run: `dune build --root . lib/desugar/desugar.cma bin/main.exe`
Expected: exit 0. A missing name here means the dependency scan was short — add the
alias, do **not** edit the moved band.

- [ ] **Step 5: prove the move was verbatim (splice check)**

Comment-stripped code, spliced back at the alias site, must equal the original **in order**:

```bash
git show HEAD:lib/desugar/desugar.ml > /tmp/bartik-D-base.ml
python3 /tmp/bartik-strip.py /tmp/bartik-D-base.ml > /tmp/bartik-D-base.code
# reconstruct: current desugar.ml with the 6 alias lines replaced by the module's code
```
Expected: empty diff apart from the 6 alias lines and the new file's `open`/`module Err`
header. Any other difference is an edit in transit — revert and redo the move.

- [ ] **Step 6: oracles must be GREEN against the Step 1 baseline**

```bash
scripts/ir-oracle.sh     check /tmp/ir-base-bartik-D
scripts/types-oracle.sh  check /tmp/ty-base-bartik-D
scripts/refine-oracle.sh check /tmp/rf-base-bartik-D
```
Expected: IDENTICAL on all three.

- [ ] **Step 7: full suite**

Run: `scripts/run-tests.sh`
Expected: exit 0, `All suites passed`, 3,177 tests.

- [ ] **Step 8: commit**

```bash
git add lib/desugar/desugar.ml lib/desugar/desugar_derive.ml CHANGELOG.md
git commit -m "refactor(desugar): move derive expansion to desugar_derive.ml"
```

---

### Task E: extract the ANF lowering core

**Files:**
- Create: `lib/tir/lower_expr.ml`
- Modify: `lib/tir/lower.ml` (remove `:101–1050`, add 3 alias lines)

**Interfaces:**
- Produces: `Lower_expr.{lower_to_atom_k, lower_expr, lower_atoms_k}` — one `let rec … and`
  group, the ANF core every other `lower_*` module calls into.
- Consumes: the 16 aliases `lower.ml:57–88` already declares
  (`ty_of_span`, `ty_of_expr`, `unknown_ty`, `lower_ty`, `lower_linearity`, `fresh_name`,
  `fresh_var`, `_fn_param_types`, `_use_aliases`, `_protocol_roles`, `_current_module_fns`,
  `resolve_use_alias`, `_ensure_module_lowered`, `_default_dispatch`,
  `resolve_iface_method`, `lower_fn_def`). Re-declare that alias block at the top of
  `lower_expr.ml`; it is 16 one-line references to `Lower_state`/`Lower_types`/`Lower_decls`,
  not a copy of any logic.

**CRITICAL — the init hook travels with the band.** `lower.ml:1050` is

```ocaml
let () = Lower_match.install_lower_expr lower_expr
```

`Lower_match` is mutually recursive with `lower_expr` (2 call directions, 5 edges) and the
cycle is broken by this forward-ref. The hook must end up in `lower_expr.ml`, immediately
after the band, and must not be duplicated. After the move assert exactly one:

```bash
grep -rc 'install_lower_expr' lib/tir/lower_expr.ml   # must be 1
grep -rc 'install_lower_expr' lib/tir/lower.ml        # must be 0
```

- [ ] **Step 1: baseline** — as Task D Step 1, with `-E` suffixes.
- [ ] **Step 2: prove RED** — perturb one arm of `lower_expr`, `ir-oracle.sh check` must
      differ, then `git checkout --` the file.
- [ ] **Step 3: move `:101–1050` verbatim** into `lower_expr.ml`, prefixed by the module
      doc comment, `module Ast = March_ast.Ast`, `module Typecheck = March_typecheck.Typecheck`,
      and the 16-alias block.
- [ ] **Step 4: add the 3 aliases** at the band's old position in `lower.ml`:

```ocaml
let lower_to_atom_k = Lower_expr.lower_to_atom_k
let lower_expr = Lower_expr.lower_expr
let lower_atoms_k = Lower_expr.lower_atoms_k
```

- [ ] **Step 5: build** — `dune build --root . bin/main.exe`, exit 0. A dune **cycle**
      error here means the init hook was left behind in `lower.ml`; move it, don't re-wire it.
- [ ] **Step 6: assert the hook invariant** — the two `grep -c` commands above.
- [ ] **Step 7: splice check** — as Task D Step 5.
- [ ] **Step 8: oracles GREEN** + `scripts/run-tests.sh` exit 0.
- [ ] **Step 9: commit**

```bash
git add lib/tir/lower.ml lib/tir/lower_expr.ml CHANGELOG.md
git commit -m "refactor(tir): move the ANF lowering core to lower_expr.ml"
```

---

### Task F: extract the RC-insertion core

**Files:**
- Create: `lib/tir/perceus_core.ml`
- Modify: `lib/tir/perceus.ml` (remove `:134–1375`, add 14 alias lines)

**Interfaces:**
- Produces: `Perceus_core.{env, empty_env, insert_rc_expr, find_inc_vars, needs_rc,
  is_apply_fn, live_before, name_free_in, vars_of_atom, vars_of_atoms, fbip_arity_marker,
  same_arity, collect_closure_fvs, collect_moved_vars, collect_actor_sent_vars}`.
- Consumes: `fresh_rc_var` (3 uses), defined above `:134`. Move `fresh_rc_var` into
  `perceus_core.ml` too and re-export it if `perceus.ml` still needs it; check with
  `grep -c` on comment-stripped code before deciding.

**`env` is a 123-line record.** `perceus.ml` must re-export it with the full type equation
`type env = Perceus_core.env = { … }` so `perceus.mli` is unchanged. OCaml enforces the
field list matches, so divergence is a compile error, not a silent bug — but do not
hand-retype it: copy the record verbatim.

**None of `Perceus_liveness`, `Perceus_elide`, `Perceus_fbip`, `Perceus_scrut` may gain a
dependency on `Perceus_core`,** and `Perceus_core` may not depend on `Perceus`. dune
rejects either as a cycle; that is the check, and it is automatic.

- [ ] **Step 1: baseline** — as Task D, `-F` suffixes.
- [ ] **Step 2: prove RED** — perturb one RC arm; `ir-oracle.sh check` must differ; revert.
- [ ] **Step 3: move `:134–1375` verbatim** into `perceus_core.ml`.
- [ ] **Step 4: add the 14 aliases + the `env` re-export** at the old position.
- [ ] **Step 5: build** — `dune build --root . bin/main.exe`, exit 0.
- [ ] **Step 6: splice check** — as Task D Step 5.
- [ ] **Step 7: oracles GREEN** + `scripts/run-tests.sh` exit 0 (3,177).
- [ ] **Step 8: RC-specific benchmark** — Perceus/FBIP changes must be benchmarked
      **compiled**; interpreted takes hours.

```bash
dune build --root . bin/main.exe
./_build/default/bin/main.exe --compile --opt 2 bench/tree_transform.march -o /tmp/tt-bartik
/tmp/tt-bartik
```
Expected: same output and no material slowdown vs. a run of the same benchmark built from
`HEAD~1`. An absolute-ms figure alone is not a regression detector — compare same-box A/B.

- [ ] **Step 9: commit**

```bash
git add lib/tir/perceus.ml lib/tir/perceus_core.ml CHANGELOG.md
git commit -m "refactor(tir): move the RC-insertion core to perceus_core.ml"
```

---

## Closing out

- [ ] `git mv` any covering todo into `specs/progress/`, or add
      `specs/progress/2026-08-27-lower-desugar-perceus-decomposition.md`.
- [ ] Update `specs/2026-08-25-file-decomposition-analysis.md`: finding 3 moves from
      "partly open" to closed, with the two declined clusters recorded as declined and why.
- [ ] Update the project layout in `CLAUDE.md` to name the three new modules.
- [ ] `scripts/check-docs.sh` must pass.
