# The three decomposition targets that remain worth doing

**Date:** 2026-08-27
**Measured at:** `f3c37fb6` (every number below carries the command that produced it)
**Follows:** `specs/progress/2026-08-26-compiler-file-decomposition-complete.md`
**Method inherited from:** `specs/2026-08-25-file-decomposition-analysis.md`

Phases 0–7 of `specs/plans/2026-08-19-compiler-file-decomposition.md` are done.
Three targets are left. They are **not** equal in value, and this plan says so
rather than pretending otherwise:

| | Target | Lines | Largest unit | Churn (commits/6mo) | Priority |
|---|---|---:|---|---:|---|
| **A** | `bin/main.ml` | 5,429 | `compile` 2,431 (45%) | **339** | lead with this |
| **B** | `lib/typecheck/typecheck.ml` | 8,272 | `infer_expr` group 2,215 (26%) | **388** | second |
| **C** | `lsp/lib/server.ml` | 1,556 | `dispatch_by_method` 644 (41%) | 33 | last, and optional |

C has one tenth the churn of A and B. It is in this plan because its
concentration is real and its extraction is unusually clean, not because it is
comparably urgent.

## The measurements, and how to re-derive them

```bash
wc -l bin/main.ml lib/typecheck/typecheck.ml lsp/lib/server.ml
#   5429 bin/main.ml
#   8272 lib/typecheck/typecheck.ml
#   1556 lsp/lib/server.ml

git log --oneline --since="6 months ago" -- bin/main.ml               | wc -l   # 339
git log --oneline --since="6 months ago" -- lib/typecheck/typecheck.ml | wc -l  # 388
git log --oneline --since="6 months ago" -- lsp/lib/server.ml          | wc -l  # 33
```

Group-aware concentration (a col-0 `and` **continues** a group — this is the
2026-08-26 correction to the analysis document's appendix scan):

```bash
python3 - bin/main.ml lib/typecheck/typecheck.ml lsp/lib/server.ml <<'PY'
import re,sys
for p in sys.argv[1:]:
    lines=open(p,errors='ignore').read().split('\n')
    starts=[i for i,l in enumerate(lines) if re.match(r'^(let|type|module|external)\s',l)]
    ends=starts[1:]+[len(lines)]
    best=max((e-s,s+1,e,lines[s][:60]) for s,e in zip(starts,ends))
    print(f"{p}: total={len(lines)} largest_group={best[0]} ({100*best[0]//len(lines)}%) "
          f"lines {best[1]}-{best[2]}  :: {best[3]}")
PY
# bin/main.ml:                 largest_group=2431 (44%) lines 2404-4834 :: let compile filename =
# lib/typecheck/typecheck.ml:  largest_group=2215 (26%) lines 1447-3661 :: let rec infer_expr env ...
# lsp/lib/server.ml:           largest_group=1313 (84%) lines  245-1557 :: let semantic_tokens_data ...
```

> **Correction — the scan is wrong about `server.ml`, and this plan does not
> repeat it.** The 1,313-line figure is a scan artefact: `class march_server =`
> (`lsp/lib/server.ml:368`) does not begin with `let|type|module|external`, so
> the scan glues everything from `semantic_tokens_data` to EOF into one bucket.
> `semantic_tokens_data` is really **118 lines** (`:245–362`). The true
> concentration is the method `dispatch_by_method` — **644 lines**, `:912–1555`,
> 41% of the file. See Target C. Any future run of that scan should treat a col-0
> `class` as a boundary too.

---

## Which oracle covers what — decide this before writing a task, not after

| Target | `ir-oracle` | `types-oracle` | `refine-oracle` | Direct substitute |
|---|---|---|---|---|
| A: `compile` front end + TIR pipeline + `--emit-llvm` | **yes, directly** | yes (the `--check`/`--emit-core-ast` arms) | yes | — |
| A: the `if !do_compile` native block | **structurally no** | no | no | the 15 alcotest modules that shell out with `--compile` |
| A: interpreter / `--jit` / `--check-migration` arms | no | no | no | `scripts/run-tests.sh` full (`eval`, `test_jit`) |
| B: `typecheck.ml` | yes (secondary) | **yes, directly** | yes | — |
| C: `lsp/lib/server.ml` | **blind** | **blind** | **blind** | `lsp/test/test_jsonrpc.ml` — and it covers only 16 of 22 dispatch branches |

`ir-oracle` cannot see the native block by construction, and the script says so
itself (`scripts/ir-oracle.sh:4–9`): `--emit-llvm` writes the `.ll` and exits in
the **`else`** branch of `if !do_compile`, precisely so a warm CAS cannot
short-circuit it. The consequence for this plan is that the single largest
extraction available in `bin/main.ml` is also the one no oracle watches. That is
why Task A5 is gated and why it is named the riskiest task in this plan.

Which alcotest modules do cover it:

```bash
grep -rl -- '--compile' test/*.ml | wc -l   # 15
```

— `test_codegen`, `test_cas`, `test_hot_reload`, `test_cap_*`, `test_oracle`,
`test_ir_verify`, `test_stdlib_suite`, … Several of their cases are `Slow`-tagged,
so **`scripts/run-tests.sh -q` is not a verification of Task A5**; the full run is.

Standing rules from the last project, unchanged and non-negotiable:

- Prove every oracle goes **RED** on a deliberate perturbation before trusting a
  GREEN, in this worktree, this session.
- Run oracles under a private `HOME` (`~/.cache/march` is shared across worktrees
  and its cached spans carry the populating worktree's absolute paths), and
  `mkdir -p "$HOME/.cache"` inside it — see
  `specs/todos/2026-08-26-stdlib-cache-mkdir-not-recursive.md`.
- Re-derive every band by **grep anchor** at the start of each task. The line
  numbers in this document were true at `f3c37fb6` and will not be true after
  the task before them lands.
- Machine-check verbatim-ness: read the moved region back out of the destination
  and require byte-for-byte equality with the original. That proves motion
  fidelity, not band correctness.

---

# Target A — `bin/main.ml`

## Was Phase 5 right?

Phase 5 declined to split `bin/main.ml`, arguing that "linear driver code is the
friendliest shape to work in". **Half right, and the wrong half was load-bearing.**

The evidence against deference:

```bash
git log --since="6 months ago" -U0 --no-color -p -- bin/main.ml \
  | grep '^@@' | sed 's/^@@[^@]*@@ *//' | cut -c1-40 | sort | uniq -c | sort -rn | head -5
#   478 let compile filename =
#    64 let () =
#    53 let ensure_runtime_so () =
#    50 let run_test_cmd args =
#    47 let load_stdlib () =
#  (983 hunks total: `... | grep -c '^@@'`)
```

**478 of 983 hunks in six months — 49% — land inside one 2,431-line function.**
Git's OCaml funcname context makes this cheap and exact. It is the strongest
single number in this plan.

I could **not** determine reliably *where inside* `compile` those hunks land. The
obvious follow-up (bucketing hunk line numbers by sub-region) is defeated by
drift: over the last 60 days, 109 of 177 in-`compile` hunk offsets fall outside
today's `compile` at all, because the decomposition project itself moved the file
by thousands of lines. Do not put a sub-region churn table in a future plan
without re-deriving it against a stable baseline.

So the honest conclusion is narrower than "Phase 5 was wrong":

> **The linear pass sequence should stay linear. Everything in `compile` that is
> not the pass sequence should leave.**

`compile`'s actual shape is a 604-line prelude followed by a five-arm cascade:

```bash
awk 'NR>=2404 && NR<=4834 && /^  else if|^  else begin/ {printf "%5d: %s\n", NR, $0}' bin/main.ml
```

| Region | Lines | Count | Character |
|---|---|---:|---|
| prelude (parse → desugar → resolve → stdlib inject → typecheck → diagnostics) | `2404–3007` | 604 | pipeline |
| `--check` arm | `3008–3032` | 25 | pipeline |
| `--check-migration` arm | `3033–3098` | 66 | **a separate tool** |
| `compile_mode` arm | `3099–4663` | 1,565 | — |
| &nbsp;&nbsp;· TIR pass sequence | `3101–3679` | 579 | **pipeline — keep** |
| &nbsp;&nbsp;· native emit + clang + link + CAS, and its `--emit-llvm`-only `else` tail (`4571–4628`) | `3684–4628` | 945 | **build plumbing** |
| `jit_run` arm | `4664–4714` | 51 | pipeline |
| interpreter arm | `4715–4834` | 120 | pipeline |

Type inference sequencing and `clang -O2 … -lm` do not belong in the same
function. That is the case for extraction, and it does not require conceding
that the pass sequence should be broken up.

## What binds, and what does not

`bin/` is a dune `(executable (name main))` with no `modules` field, so sibling
modules in `bin/` are automatically part of the executable — `bin/version.ml`
(generated by `bin/dune`) already proves the pattern. Extractions therefore go to
new `bin/*.ml` files, not to a library.

The one structural obstacle: 38 top-level flag `ref`s (`bin/main.ml:1065–1606`)
sit *below* the helper bands and *above* `compile`, so any extraction out of
`compile` into a `bin/` module would otherwise need them as parameters.

```bash
grep -n "^let [a-z_0-9]* *\(: [^=]*\)\?= ref " bin/main.ml | wc -l   # 39
#   (38 flags + `caps_env` at :4835, which is not a flag and stays)
```

Every one has a literal or library-constant RHS — none references a `main.ml`
local — so they hoist as a block with no reordering.

Band dependency scan (`scratchpad/dep.py`, reproduced in the appendix):

```
B1 diag helpers        10-257    : 0 external main.ml deps
B2 stdlib/runtime disc 258-520   : 0 external main.ml deps
B3 link flags + so     782-1058  : 2 (runtime_dir :370, find_runtime_file :391 — both in B2)
B1+B2+B3 combined                : 0
B4 schema migration    2115-2265 + 3033-3098 : 3, all flags
B5 emit_core_ast       2794-2932 : 1, a flag
B6 subcommands         1797-2114 + 5058-5158 : 16  ← the messy one
```

(The scan also reports `compile` as a "dep" of B1+B2+B3; that is a false positive
from the word `compile` inside string literals. Verified by reading the hits.)

## Tasks

### Task A1: `bin/toolchain.ml` — host/stdlib/runtime discovery and link flags

**Kind: code motion.** Oracles byte-identical.

**Files:** create `bin/toolchain.ml` (~1,050 lines); modify `bin/main.ml`.

**No prerequisites.** This band uses zero flags and zero other `main.ml` names,
which makes it the safest available and therefore the one to land first.

Bands, by anchor (re-derive; do not trust the numbers):

```bash
F=bin/main.ml
grep -n '^let severity_word'       $F   #  10  ─┐ B1 diagnostics + prelude-collision
grep -n '^let b64_decode_pubkey'   $F   # 208   │
grep -n '^let resolve_exe_path'    $F   # 258  ─┼ B2 stdlib/runtime discovery
grep -n '^let load_stdlib '        $F   # 504   │
grep -n '^let stdlib_span_files'   $F   # 563  ─┘ (B2 ends at 520; 521-781 STAYS)
grep -n '^let blake3_link_flags'   $F   # 782  ─┐ B3 link flags + ensure_runtime_so
grep -n '^let contains_substring'  $F   #1059  ─┘ (B3 ends at 1058)
```

Note the gap: `stdlib_span_files` / `stdlib_module_names` / `get_stdlib_tc_env`
(`521–781`) sit **between** B2 and B3 and **stay** in `main.ml` — they depend on
B2 (which will precede them as a module) and nothing in B3 depends on them, so
removing B2 and B3 around them preserves ordering. Verify that claim by grep
before moving, not by reading this sentence.

- [x] **Step 1** — cut B1, B2, B3 (in that order) into `bin/toolchain.ml`.
- [x] **Step 2** — add `open Toolchain` at the top of `bin/main.ml`. Use `open`,
  not `include`: nothing outside the executable consumes `Main`, so re-export is
  not needed, and `open` keeps every existing call site (`ensure_runtime_so ()`,
  `find_stdlib_dir ()`, …) unchanged — a zero-rename diff.
- [x] **Step 3** — machine-check verbatim-ness of all three bands.
- [x] **Step 4** — verify:

```bash
dune build --root . bin/main.exe
scripts/ir-oracle.sh check /tmp/ir-base-<slug>
scripts/types-oracle.sh check /tmp/ty-base-<slug>
scripts/run-tests.sh                       # full, not -q
```

```bash
git add bin/toolchain.ml bin/main.ml
git commit -m "refactor(main): move host/stdlib/runtime discovery and link flags to toolchain.ml"
```

**Done means:** `wc -l bin/main.ml` ≈ **4,390**, all three oracles byte-identical,
full suite matching the pre-task baseline.

---

### Task A2: `bin/flags.ml` — the 38 command-line flag cells

**Kind: code motion.** Oracles byte-identical. **Enabler for A3–A5.**

**Files:** create `bin/flags.ml` (~45 lines); modify `bin/main.ml`.

This buys ~45 lines on its own. Its value is that it is the precondition for
every later extraction out of `compile`: a `bin/*.ml` module cannot see
`main.ml`'s refs, so without it A3/A4/A5 each become a 15-argument function.

- [x] **Step 1** — move exactly the lines matched by

```bash
grep -n "^let [a-z_0-9]* *\(: [^=]*\)\?= ref " bin/main.ml
```

  **minus** `caps_env` (`:4835` — not a flag, and it is defined after `compile`
  on purpose), carrying each line's trailing comment. Preserve declaration order.
- [x] **Step 2** — `open Flags` in `bin/main.ml`, above the first use. Zero
  renames: `!do_compile` continues to resolve.
- [x] **Step 3** — confirm `refine_suggest_budget`'s RHS
  (`March_refinecheck.Precond_infer.default_budget`) still resolves; it is the
  only non-literal initialiser.
- [x] **Step 4** — verify as Task A1.

```bash
git add bin/flags.ml bin/main.ml
git commit -m "refactor(main): hoist the command-line flag cells to flags.ml"
```

**Done means:** `wc -l bin/main.ml` ≈ **4,345**, oracles byte-identical.

---

### Task A3: `bin/schema_migration.ml` — the `--check-migration` tool

**Kind: code motion.** **Depends on A2.**

**Files:** create `bin/schema_migration.ml` (~220 lines); modify `bin/main.ml`.

`--check-migration` is a standalone actor-schema diffing tool that happens to be
reachable through `compile`'s cascade. It shares nothing with the compile
pipeline but the parsed AST.

Two bands:

```bash
F=bin/main.ml
grep -n '^let parse_pred'                     $F   # 2115 ┐ helpers
grep -n '^let internal_compiler_error_exit'   $F   # 2266 ┘ (band ends 2265)
grep -n 'else if !check_migration then begin' $F   # 3033 ┐ the arm
grep -n 'else if compile_mode then begin'     $F   # 3099 ┘ (band ends 3098)
```

Its only external needs are the three flags `check_migration`, `prior_schema_path`,
`new_schema_path` (satisfied by A2) plus `desugared` and `filename`, which become
the extracted entry point's two parameters.

- [x] **Step 1** — move the helper band, then the arm body, into
  `Schema_migration.run ~filename ~desugared`.
- [x] **Step 2** — the arm in `compile` becomes
  `else if !check_migration then Schema_migration.run ~filename ~desugared`.
- [x] **Step 3** — verify as A1, **plus** an explicit end-to-end run of the
  subcommand on the fixture the test suite uses, since no oracle exercises this
  arm:

```bash
grep -rn 'check-migration' test/ scripts/ | head
# run whatever that finds, before and after, and diff the output
```

  If that grep returns nothing, say so in the commit message: this arm is then
  covered by neither an oracle nor a test, and A3 must be reviewed by reading the
  diff rather than by a green run.

```bash
git add bin/schema_migration.ml bin/main.ml
git commit -m "refactor(main): move the --check-migration tool out of compile"
```

**Done means:** `wc -l bin/main.ml` ≈ **4,130**, `compile` ≈ **2,365**.

---

### Task A4: `bin/emit_core_ast.ml` — the `--emit-core-ast` JSON writer

**Kind: code motion.** **Depends on A2.**

**Files:** create `bin/emit_core_ast.ml` (~145 lines); modify `bin/main.ml`.

```bash
F=bin/main.ml
grep -n 'if !emit_core_ast_file <> None then begin' $F   # 2794 (band ends at its `end;` — 2932)
```

139 lines of pure serialisation ending in `exit`. Inputs: `filename`,
`user_files`, `user_ast`, `type_map`, `diags`, `is_user_file`, and the four
`has_*_errors` booleans — pass the four as one `~rejected:bool`, computed at the
call site exactly as `verdict` computes it today.

**This band is directly oracle-covered**: `types-oracle` Tier 1 *is*
`--emit-core-ast` over ~600 fixtures. A byte-identical Tier 1 is a strong proof
for this task specifically.

- [x] Steps as A3; verification as A1.

```bash
git add bin/emit_core_ast.ml bin/main.ml
git commit -m "refactor(main): move the --emit-core-ast writer out of compile"
```

**Done means:** `wc -l bin/main.ml` ≈ **3,990**, `compile` ≈ **2,225**,
`types-oracle` Tier 1 byte-identical.

---

### Task A5 *(gated stretch)*: `bin/emit_native.ml` — LLVM emit, clang, link, CAS

**Kind: code motion**, and **the riskiest task in this plan.**

**Files:** create `bin/emit_native.ml` (~950 lines); modify `bin/main.ml`.

**Do not start unless A1–A4 have landed on `main` and you can land A5 the same
day.** Nothing after it depends on it.

```bash
F=bin/main.ml
grep -n 'if !do_compile then begin' $F   # 3684 — band start
grep -n 'wrote %s' $F                    # 4627 — inside the --emit-llvm tail
# The band is the WHOLE if/else: 3684 through the `end` that closes the
# --emit-llvm-only `else` (4628), one line before the enclosing `end` at 4629.
# Re-derive both by reading, not by trusting these numbers.
```

945 lines (`3684–4628`), covering **both** arms: `Llvm_emit.emit_module`, the
runtime `.c` compilation, the clang and linker invocations, the CAS artifact
store, the JS/WASM target branches, the `.schemas.json` emission, and the
`--emit-llvm`-only `else` tail (`4571–4628`) that writes the `.ll` and returns.
Move the whole `if/else` — the two arms share the hot-reload/RPC hash setup and
splitting them duplicates it.

**Why it is the riskiest:**

1. `ir-oracle` sees only **58** of the 945 lines. `scripts/ir-oracle.sh:4–9`
   documents that `--emit-llvm` exits in the `else` tail, deliberately, so the
   CAS cannot short-circuit the oracle — which means the oracle exercises the
   tail and *never* the 887-line `if !do_compile` arm where clang, the linker and
   the CAS store live. A green `ir-oracle` after A5 proves the tail moved
   correctly and says nothing about the rest.
2. It contains the CAS cache key. `specs/progress/…` records that codegen flags
   omitted from `cas_flags` produce a silently stale binary; the failure mode is
   a *correct-looking* compile that returns yesterday's answer.
3. Its only verification is the full alcotest run, and the native cases inside it
   are `Slow`-tagged — `run-tests.sh -q` gives a vacuous green.
4. It has the widest input surface in the plan:

```
actor_compat_map, actor_invariant_map, actor_schemas, basename, cap_attrib,
cap_decls, ll_file, pre_opt_tir, rpc_impl_hashes, source_cas_state, src,
src_hash, stamp, stdlib_decls, target, tir, ty_to_schema_str, user_ast
```

  (18 names, derived by intersecting the band's identifiers with `compile`'s
  prelude bindings; see appendix.) Pass them as **one record type declared in
  `bin/emit_native.ml`**, not as 18 labelled arguments — a labelled-argument list
  that long is where an argument gets silently swapped.

- [ ] **Step 1** — declare `type inputs = { … }` in `bin/emit_native.ml` with all
  18 fields, then `let run (i : inputs) : unit`.
- [ ] **Step 2** — move the band verbatim into `run`, adding `i.` prefixes as the
  *only* edit. Machine-check verbatim-ness after stripping the `i.` prefixes.
- [ ] **Step 3** — verify:

```bash
dune build --root . bin/main.exe
scripts/ir-oracle.sh check /tmp/ir-base-<slug>    # necessary, NOT sufficient
scripts/types-oracle.sh check /tmp/ty-base-<slug>
scripts/run-tests.sh                              # FULL. -q does not cover this.
```

- [ ] **Step 4 — the substitute for the missing oracle.** Before/after, on a
  cleared CAS, compile three programs at two opt levels and diff the *emitted
  `.ll`* and the *program output*, not the binaries (two fresh Mach-O binaries
  always differ — random `LC_UUID`):

```bash
rm -rf .march/cas/artifacts-v2
for f in bench/binary_trees.march bench/list_ops.march bench/tree_transform.march; do
  for o in 0 2; do
    ./_build/default/bin/main.exe --compile --opt $o "$f" -o /tmp/a-<slug> > /tmp/log-<slug> 2>&1
    /tmp/a-<slug> > "/tmp/out-$(basename $f)-$o-<slug>"
  done
done
```

  Then re-run with a **warm** CAS and confirm the second run is a cache hit
  (`ls .march/cas/artifacts-v2 | wc -l` unchanged) with identical output. A moved
  CAS key that stopped hashing a flag shows up here and nowhere else.

```bash
git add bin/emit_native.ml bin/main.ml
git commit -m "refactor(main): move native emit, link and CAS store to emit_native.ml"
```

**Done means:** `wc -l bin/main.ml` ≈ **3,050**, `compile` ≈ **1,280**,
oracles byte-identical, full suite green, and the warm/cold CAS check above
passing with identical program output.

---

### Explicitly not doing: the TIR pass sequence (`3101–3679`)

**Leave this alone.** It is 579 lines of `let tir = Pass.run tir in` threaded
through fifteen passes, interleaved with the `snap_tir` instrumentation and the
`--dump-phases` collection. Extracting it would trade a readable linear sequence
for a function with ~8 inputs and ~5 outputs, and this *is* the "linear driver
code" Phase 5 was defending. Phase 5's argument is correct here and wrong about
the 945-line clang/CAS block; the distinction is the point.

### Explicitly not doing: `run_test_cmd` / `run_fmt` / `analyze_gc_trace`

**Leave for now.** 419 lines across three subcommands, but the band pulls in
**16** other `main.ml` names (`severity_word`, `check_no_prelude_collision`,
`load_stdlib`, `stdlib_span_files`, `setup_interpreter_ffi`, `print_refine_report`,
`resolve_imports`, `fmt_file`, `march_files_in`, …). After A1 lands, several of
those live in `Toolchain` and the count drops — **re-measure then**. Do not
attempt it at the current dependency count.

---

# Target B — `lib/typecheck/typecheck.ml`: Phase 6 tasks 6.7 and 6.8, revisited

Phase 6 stopped at 8,272 lines with two stretch tasks unattempted. Both are
still worth doing, but **not in the shape Phase 6 described**, and the stated
blocker turns out not to exist.

## Current section map (re-derived)

```bash
grep -n '^(\* =\|^   §' lib/typecheck/typecheck.ml
```

| § | Lines | Count |
|---|---|---:|
| §1 Unification | `76–502` | 427 |
| §2 Surface-type → internal-type | `503–862` | 360 |
| §3 Linearity | `863–1045` | 183 |
| §4 Pattern inference | `1046–1433` | 388 |
| §5 Expression checking (`infer_expr` group) | `1434–3655` | 2,222 |
| §6 Declaration checking | `3656–4577` | 922 |
| §7 "Session type projection and duality" | `4584–6931` | 2,348 |
| §8 Module entry point | `6940–8272` | 1,333 |

**§7's header is stale** — Task 6.9 renumbered the headers but §7 now covers a
grab-bag: session projection, declaration reordering, panic-surface tables, four
module-capability checkers, and `check_decl` (1,247 lines) which stays.

```bash
awk 'NR>=4584 && NR<=6931' lib/typecheck/typecheck.ml | grep -n '^\(let\|and\)' \
  | awk -F: '{print $1+4583": "$0}' | cut -d: -f1,3-
```

## The module-initialisation-order hazard — it is void, and here is the proof

Phase 6 gated 6.7 on this: the band contains two forward-hook installations, and
"no oracle in this plan would catch [a reordering], because the corpus never
exercises init-time ordering." That is still true of the oracles. It is not true
of the hazard.

**First: the entire init-order surface of `lib/typecheck/` is two lines.**

```bash
grep -n '^let () =' lib/typecheck/*.ml
# lib/typecheck/typecheck.ml:745:let () = inject_iface_exports_ref := (fun mod_name exports env ->
# lib/typecheck/typecheck.ml:841:let () = expand_record_ref := (fun env ty ->
```

Eight modules, two top-level effects, both of them the hooks in question. This is
small enough to reason about exhaustively rather than to fear.

**Second: `inject_iface_exports_ref` has no reader at all.**

```bash
grep -rn 'inject_iface_exports' lib/ lsp/ bin/ forge/ test/
# 4 hits: the declaration (typecheck_env.ml:1073), the installation
# (typecheck.ml:745) and two comments. No dereference anywhere in the tree.
```

An installation nobody reads cannot have an ordering regression. It arrived in a
2026-04-10 WIP commit (`d95631a6`) and a read site was never added — filed as
`specs/todos/2026-08-27-inject-iface-exports-hook-has-no-reader.md`. **Do not fix
it as part of this plan**; the point here is only that it neutralises half the
hazard.

**Third: `expand_record_ref` moves as a closed unit.** Its declaration
(`typecheck.ml:316`), its single read site (`:425`, inside `unify`) and its
installation (`:841`) are **all three inside the 6.7 band** (`76–862`). Moving the
band moves all three together, in order, into a module that initialises before
`Typecheck` — so the install still precedes every possible read, strictly more
safely than today.

```bash
grep -n 'expand_record_ref' lib/typecheck/*.ml
# typecheck.ml:316 (decl), :425 (the only read, in unify), :841 (install)
```

**Fourth, the standing check that substitutes for the missing oracle.** Assert
the property directly, before and after every Target B task:

```bash
grep -n '^let () =' lib/typecheck/*.ml | wc -l    # must stay 2
grep -c 'expand_record_ref' lib/typecheck/typecheck_unify.ml   # must be 3 after B3
```

If a future task ever makes the first number grow, this argument expires and the
hazard is live again. Say so in that task.

**Fifth: the band has no downward dependency.** A scan of the `76–862` band
against every top-level name defined below it in `typecheck.ml` returns two hits
(`register_impl_shape`, `prebind_fn_scheme`), and reading both shows they are
mentions inside multi-line doc comments (`:415`, `:514`), not calls.

## Tasks

Phase 6 sequenced 6.8 *after* 6.7 because 6.8 needed `surface_ty`. That is true
of only one fifth of 6.8's band. Splitting 6.8 first gives two zero-dependency
tasks that can land before the risky one — a strictly better order.

Per-band dependency scan (identifiers vs. top-level names above and below;
comment-stripped):

| Band | Lines | Count | Deps *below* | Deps on `typecheck.ml` locals *above* |
|---|---|---:|---|---|
| B1 decl reordering | `4809–5287` | 479 | **none** | **none** |
| B2 module-cap checkers | `5288–5678` | 391 | **none** | **none** |
| B3 §1+§2 unify/surface | `76–862` | 787 | none (2 comment hits) | none |
| B4 session projection | `4592–4808` | 217 | **none** | `surface_ty`, `session_ty_equal`, `session_ty_exact_equal` — all in B3 |

### Task B1: `typecheck_reorder.ml` — declaration dependency ordering

**Kind: code motion.** `types-oracle` byte-identical. **No prerequisites.**

**Files:** create `lib/typecheck/typecheck_reorder.ml` (~480 lines); modify
`lib/typecheck/typecheck.ml`.

```bash
F=lib/typecheck/typecheck.ml
grep -n '^let dependency_order_dfn_run' $F   # 4809
grep -n '^let panic_surface_direct'     $F   # 5288  (band ends 5287)
```

Carries `dependency_order_dfn_run`, `module_refs_in_decls`,
`unqualified_module_deps`, `dependency_order_dmod_run`, `reorder_decls`.

- [ ] **Step 1** — cut the band; `include Typecheck_reorder` at the band's former
  position. **`include`, not `open`** — consumers reach these through `let open`
  and through the `Tc.` / `TC.` / `T.` aliases that no grep can see, and only
  `include` re-exports them as part of `Typecheck`'s surface.
- [ ] **Step 2** — `typecheck.mli` must **not** change. If the build asks you to
  edit it, something was copied instead of re-exported.
- [ ] **Step 3** — machine-check verbatim-ness.
- [ ] **Step 4** — verify:

```bash
dune build --root . bin/main.exe
dune build @check
scripts/types-oracle.sh check /tmp/ty-base-<slug>
scripts/ir-oracle.sh check    /tmp/ir-base-<slug>
scripts/run-tests.sh
scripts/run-tests.sh lsp       # the LSP reaches Typecheck through module aliases
grep -n '^let () =' lib/typecheck/*.ml | wc -l   # 2
```

```bash
git add lib/typecheck/typecheck_reorder.ml lib/typecheck/typecheck.ml
git commit -m "refactor(typecheck): move declaration dependency ordering to typecheck_reorder.ml"
```

**Done means:** `wc -l lib/typecheck/typecheck.ml` ≈ **7,795**, oracles
byte-identical, `typecheck.mli` unmodified.

---

### Task B2: `typecheck_modcaps.ml` — the module-level capability checkers

**Kind: code motion.** **No prerequisites** (independent of B1; either order).

**Files:** create `lib/typecheck/typecheck_modcaps.ml` (~395 lines); modify
`lib/typecheck/typecheck.ml`.

```bash
F=lib/typecheck/typecheck.ml
grep -n '^let panic_surface_direct' $F   # 5288
grep -n '^let rec check_decl'       $F   # 5679  (band ends 5678)
```

Carries the four panic-surface `StringSet`s, `proof_based_panic_surface`,
`panic_surface_suggestion`, `span_within`, `check_no_panic_module`,
`is_nondeterministic_cap`, `check_pure_module`, `check_no_extern_module`,
`check_deterministic_module` and their suggestion strings. Mostly tables — the
low-risk half of Target B.

`refine_oracle` matters here as well as `types-oracle`: `check_no_panic_module`
interacts with the `cap no_panic` / panic-surface-by-proof pipeline.

- [ ] Steps as B1, plus `scripts/refine-oracle.sh check`.

```bash
git add lib/typecheck/typecheck_modcaps.ml lib/typecheck/typecheck.ml
git commit -m "refactor(typecheck): move the module-capability checkers to typecheck_modcaps.ml"
```

**Done means:** ≈ **7,405** after B1 and B2 both land; three oracles
byte-identical.

---

### Task B3: `typecheck_unify.ml` — §1 unification + §2 surface-type conversion

**Kind: code motion.** This is Phase 6's Task 6.7, de-gated by the argument above.

**Files:** create `lib/typecheck/typecheck_unify.ml` (~790 lines); modify
`lib/typecheck/typecheck.ml`.

```bash
F=lib/typecheck/typecheck.ml
grep -n '§1  Unification'  $F   # 76-78  (header comment; band starts at 76)
grep -n '§3  Linearity'    $F   # 863    (band ends 862)
```

The band spans §1 and §2 as a unit: `pp_ty` helpers, `session_ty_equal`,
`session_ty_exact_equal`, `expand_record_ref`, `unify`, `report_mismatch`,
`surface_ty`, `expand_record`, `instantiate_ctor`, and **both** hook
installations (`:745`, `:841`).

- [ ] **Step 1** — cut `76–862` into `lib/typecheck/typecheck_unify.ml`.
- [ ] **Step 2** — `include Typecheck_unify` at the band's former position, i.e.
  immediately **after** `include Typecheck_builtins` (`:75`) and before §3. The
  band consumes names from `Typecheck_types`, `Typecheck_env` and
  `Typecheck_builtins`, so `typecheck_unify.ml` opens with the same three
  `include`s, in the same order.
- [ ] **Step 3 — the written init-order check.** Record in the commit message,
  as prose, that (a) `grep -n '^let () =' lib/typecheck/*.ml` returns exactly two
  hits and both moved together, (b) `grep -rn 'inject_iface_exports' lib/ lsp/
  bin/ forge/ test/` still shows no dereference, and (c)
  `expand_record_ref`'s declaration, single read site and installation are all
  three inside `typecheck_unify.ml`. If (b) has changed since this plan was
  written — someone finished the todo — **stop**: the hazard is live again and
  needs a real init-order test before B3 can proceed.
- [ ] **Step 4** — machine-check verbatim-ness; `typecheck.mli` must not change.
- [ ] **Step 5** — verify as B1, **plus** the shared-mutable-cell probe from
  Phase 6 Task 6.3: `bin/main.ml` marshals `Typecheck._counter` and
  `._record_names` into the stdlib typecheck-env cache, so a duplicated cell
  reproduces the cross-run nondeterminism documented in
  `specs/progress/2026-08-24-interp-perf-phase-3-startup-tcenv-cache.md`. Nothing
  in this band declares those cells, but run the probe anyway — it is two lines
  and it is the failure this library has actually had.

```bash
git add lib/typecheck/typecheck_unify.ml lib/typecheck/typecheck.ml
git commit -m "refactor(typecheck): move unification and surface-type conversion to typecheck_unify.ml"
```

**Done means:** ≈ **6,615** after B1–B3, three oracles byte-identical,
`typecheck.mli` unmodified, the three init-order facts recorded in the commit.

---

### Task B4: `typecheck_session.ml` — session projection and duality

**Kind: code motion.** **Depends on B3** (`surface_ty`, `session_ty_equal`,
`session_ty_exact_equal`).

**Files:** create `lib/typecheck/typecheck_session.ml` (~220 lines); modify
`lib/typecheck/typecheck.ml`.

```bash
F=lib/typecheck/typecheck.ml
grep -n '^let rec project_steps'             $F   # 4592
grep -n '^let dependency_order_dfn_run'      $F   # 4809  (band ends 4808; gone after B1)
```

`project_steps`, `subst_svar`, `dual_session_ty`, `project_protocol`.

- [ ] Steps as B1. Run `scripts/run-tests.sh` in **full** — session types have
  their own suites and several are `Slow`.

```bash
git add lib/typecheck/typecheck_session.ml lib/typecheck/typecheck.ml
git commit -m "refactor(typecheck): move session-type projection to typecheck_session.ml"
```

**Done means:** `wc -l lib/typecheck/typecheck.ml` ≈ **6,400**.

---

### Task B5: fix the §7 header

**Kind: semantic change** to comments only — no executable line moves, so all
three oracles must still be byte-identical; the diff to review is the prose.

After B1, B2 and B4, what remains under "§7 Session type projection and duality"
is `check_decl` and `warn_unused_imports`. Retitle it, and add the `include`
pointer comments for the four new modules in the house style already used for
`Typecheck_types` / `Typecheck_env` / `Typecheck_builtins` / `Typecheck_caps` /
`Typecheck_tailcall` (`typecheck.ml:47–75`, `:4578–4583`, `:6932–6938`).

Also update `typecheck.mli`'s section docstring to say where things now live —
**but not in this plan's scope if another agent is mid-flight on `.mli` files
across `lib/typecheck/`. Check first.**

**Done means:** every `§` header names what is actually under it, and `git diff`
touches only comments.

---

### Explicitly not doing (unchanged from Phase 6, and still right)

- **`infer_expr`'s recursion group** — 2,215 lines, 14 mutually recursive
  functions, `:1447–3661`. It is one unit; moving it moves a quarter of the file
  into a module that must then `include` back almost everything. Phase 6's
  reasoning holds.
- **`check_decl`** (`:5679–6925`, 1,247 lines) and **§8 the module entry point**
  — both call into the inference group.

---

# Target C — `lsp/lib/server.ml`

**Lowest priority of the three: 33 commits in six months against 339 and 388.**
Land A and B first. C is here because the extraction is unusually clean, not
because anyone is suffering.

## What is actually in the file

The 84% concentration figure in the analysis document is an artefact (see the
correction at the top of this plan). The real shape:

| Region | Lines | Count |
|---|---|---:|
| caches, settings, versions, workspace index, code-action glue | `1–244` | 244 |
| `semantic_tokens_data` | `245–362` | 118 |
| `class march_server` | `368–1556` | 1,189 |
| &nbsp;&nbsp;· 22 small config/notification/request methods | `373–911` | 539 |
| &nbsp;&nbsp;· **`method private dispatch_by_method`** | `912–1555` | **644** |

```bash
python3 - <<'PY'
import re
L=open('lsp/lib/server.ml',errors='ignore').read().split('\n')
ms=[(i,l.strip()[:60]) for i,l in enumerate(L,1) if re.match(r'^    method',l)]
ms.append((1556,'<end of class>'))
for (a,n),(b,_) in zip(ms,ms[1:]): print(f"{b-a:6}  {a}-{b-1}  {n}")
PY
```

`dispatch_by_method` is a 22-branch `if meth = "…" then … else if …` chain
handling the LSP methods `linol` does not model, each branch 11–50 lines of
"parse params → call `Analysis` → build Yojson".

**The decisive property:**

```bash
awk 'NR>=912 && NR<=1555' lsp/lib/server.ml | grep -c 'self#\|super#'   # 0
```

The 644-line method uses **no** `self` and **no** `super`. It closes over
`params` and four local helpers (`get_td_uri`, `get_position`, `json_range`,
`json_ints`, `:915–963`). It is a free function wearing a method's clothes.

Its only file-level dependencies are eight names from `1–362`:

```
get_analysis, next_result_id, project_root, sem_tokens_cache,
semantic_tokens_data, token_delta, workspace_index, workspace_index_full
```

— which is why the state layer must move first.

## What verifies it — nothing automatic, and that is the whole problem

**No oracle covers `lsp/`.** CLAUDE.md says so explicitly for `ir-oracle`, and
`types-oracle` and `refine-oracle` drive the `march` binary, not `march-lsp`.

The one real check is `lsp/test/test_jsonrpc.ml` (843 lines), which drives a real
`march-lsp` process over stdio. It covers **16 of the 22** dispatch branches:

```bash
grep -o '"[a-zA-Z]*/[a-zA-Z]*"' lsp/test/test_jsonrpc.ml | sort -u
awk 'NR>=912 && NR<=1555' lsp/lib/server.ml | grep 'meth = "'
```

Uncovered branches (~187 of the 644 lines):

- `textDocument/semanticTokens/full` (`:964–974`)
- `textDocument/semanticTokens/full/delta` (`:975–1004`)
- `textDocument/prepareRename` (`:1057–1070`)
- `callHierarchy/incomingCalls` + `callHierarchy/outgoingCalls` (`:1359–1407`)
- `workspace/diagnostic` (`:1471–1490`)
- `completionItem/resolve` (`:1491–1524`)
- `textDocument/onTypeFormatting` (`:1525–1553`)

`test_jsonrpc` also needs `lsp/bin/main.exe` built or all 22 of its cases die
with `Unix.ENOENT`, and it is cwd-sensitive — run from the repo root.

### Task C1: extend `test_jsonrpc` to the six uncovered dispatch branches

**Kind: semantic change** — it adds tests, moves no product code. The diff to
review is the six new cases and the fact that they pass **before** any
refactoring. **Strict prerequisite for C2 and C3.**

**Files:** modify `lsp/test/test_jsonrpc.ml`.

- [ ] **Step 1** — add one request/response case per branch above, following the
  existing cases' shape. For `semanticTokens/full/delta`, the case must send a
  `full` request first so `sem_tokens_cache` and `next_result_id` are populated —
  the delta path is the only branch with cross-request state, and it is exactly
  the one an extraction can break silently.
- [ ] **Step 2** — verify the new cases **fail** if the branch is deliberately
  broken (comment out its body, confirm RED, restore). A test that passes against
  a broken branch is the LSP equivalent of the dead oracle this project already
  shipped once.

```bash
dune build lsp/bin/main.exe lsp/test/test_jsonrpc.exe
scripts/run-tests.sh jsonrpc lsp
```

```bash
git add lsp/test/test_jsonrpc.ml
git commit -m "test(lsp): cover the six unexercised dispatch_by_method branches"
```

**Done means:** all 22 branches have at least one end-to-end case, and each of
the six new ones was shown RED against a deliberately broken branch.

---

### Task C2: `lsp/lib/server_state.ml` — caches, settings, index, semantic tokens

**Kind: code motion.** **Depends on C1.**

**Files:** create `lsp/lib/server_state.ml` (~365 lines); modify
`lsp/lib/server.ml`.

Band: `lsp/lib/server.ml:8–362` (everything after the module aliases at `:3–6`,
through the end of `semantic_tokens_data`). Both the class and the dispatch chain
consume it, so it must become the layer beneath both.

```bash
F=lsp/lib/server.ml
grep -n '^let doc_cache'            $F   #  12
grep -n '^let semantic_tokens_data' $F   # 245  (band ends 362)
```

The module aliases (`Lsp`, `S`, `Pos`, `Jsonrpc`, `:3–6`) are **duplicated**, not
moved — both files need them.

- [ ] **Step 1** — move `12–362`; keep declaration order (the caches are mutable
  globals and `versions = make_version_table ()` is an initialiser).
- [ ] **Step 2** — `open Server_state` in `server.ml`. `open`, not `include`:
  `lsp/lib/` is a library, but nothing outside `Server` consumes these names —
  confirm with `grep -rn 'Server\.' lsp/ | grep -v _build` before choosing, and if
  that grep is non-empty, use `include`.
- [ ] **Step 3** — machine-check verbatim-ness.
- [ ] **Step 4** — verify. **Do not report an oracle here; there isn't one.**

```bash
dune build lsp/bin/main.exe lsp/lib/
scripts/run-tests.sh lsp jsonrpc incremental utf16 query_cli   # from the repo root
```

```bash
git add lsp/lib/server_state.ml lsp/lib/server.ml
git commit -m "refactor(lsp): move server caches, settings and semantic tokens to server_state.ml"
```

**Done means:** `wc -l lsp/lib/server.ml` ≈ **1,200**, all five LSP suites green.

---

### Task C3: `lsp/lib/server_dispatch.ml` — the 22-branch method dispatch

**Kind: code motion.** **Depends on C1 and C2.**

**Files:** create `lsp/lib/server_dispatch.ml` (~650 lines); modify
`lsp/lib/server.ml`.

- [ ] **Step 1** — move `912–1555`'s body into
  `let dispatch ~meth ~params = …`, keeping the four local helpers as
  module-level `let`s at the top of the new file and the `if/else if` chain
  verbatim below them.
- [ ] **Step 2** — the method collapses to:

```ocaml
method private dispatch_by_method ~notify_back:(_notify_back : _) meth params =
  ignore _notify_back;
  Server_dispatch.dispatch ~meth ~params
```

- [ ] **Step 3 — preserve branch order literally.** The chain is `if/else if`, so
  order is semantics: `textDocument/semanticTokens/full` must stay ahead of
  `.../full/delta` and `callHierarchy/incomingCalls` ahead of the shared
  `incomingCalls || outgoingCalls` arm. **No oracle and no test sees arm order** —
  the last project skipped a whole task for exactly this reason. Verify by
  diffing the extracted branch-name sequence against the original:

```bash
git show HEAD:lsp/lib/server.ml | awk 'NR>=912 && NR<=1555' | grep -o 'meth = "[^"]*"' > /tmp/before-<slug>
grep -o 'meth = "[^"]*"' lsp/lib/server_dispatch.ml > /tmp/after-<slug>
diff /tmp/before-<slug> /tmp/after-<slug>    # must be empty
```

- [ ] **Step 4** — verify as C2.

```bash
git add lsp/lib/server_dispatch.ml lsp/lib/server.ml
git commit -m "refactor(lsp): move dispatch_by_method to server_dispatch.ml"
```

**Done means:** `wc -l lsp/lib/server.ml` ≈ **560**, `class march_server`
≈ 550 lines of small methods, the branch-order diff empty, all five LSP suites
green.

---

# Summary

| Target | Tasks | Lines before → after | Verified by |
|---|---:|---|---|
| A `bin/main.ml` | 5 (A5 gated) | 5,429 → **≈3,990** (A1–A4), **≈3,050** with A5; `compile` 2,431 → **≈1,280** | `ir-oracle` + `types-oracle` for A1–A4; for A5 the full alcotest suite plus a cold/warm CAS output check — no oracle reaches it |
| B `typecheck.ml` | 5 (B5 comments) | 8,272 → **≈6,400** | `types-oracle` (direct), `refine-oracle` for B2, `ir-oracle` secondary; init-order asserted by a two-line grep, not by an oracle |
| C `lsp/lib/server.ml` | 3 (C1 is tests) | 1,556 → **≈560** | no oracle exists; `lsp/test/test_jsonrpc.ml` after C1 extends it to all 22 branches, plus an explicit branch-order diff |

**Riskiest task: A5** (`bin/emit_native.ml`). It is the largest single move in the
plan (945 lines, 18 inputs), it is the one region `ir-oracle` cannot see *by
design*, it contains the CAS cache key whose historic failure mode is a
correct-looking binary carrying yesterday's answer, and its only automatic
verification is `Slow`-tagged so a `-q` run gives a vacuous green. Everything
else in the plan is either oracle-covered or small.

**Left alone, deliberately:**

- `bin/main.ml`'s **TIR pass sequence** (`3101–3679`, 579 lines). Phase 5's
  "linear driver code is friendliest" is correct about *this* — it is 15
  `let tir = Pass.run tir in` lines and it should stay one readable sequence.
  Phase 5 was wrong only in extending that argument to the 945-line clang/link/CAS
  block sitting beside it.
- `bin/main.ml`'s **subcommands** (`run_test_cmd`, `run_fmt`, `analyze_gc_trace`,
  419 lines) — 16 external dependencies today. Re-measure after A1; do not attempt
  at the current count.
- `typecheck.ml`'s **`infer_expr` recursion group** (2,215 lines), **`check_decl`**
  (1,247) and **§8** — Phase 6's refusals, re-verified and still correct.
- The **`inject_iface_exports_ref` hook** — filed as
  `specs/todos/2026-08-27-inject-iface-exports-hook-has-no-reader.md`, not fixed
  here. Deleting it inside a refactor would erase the breadcrumb for an unfinished
  feature; finishing it is a semantic change that has no business in a code-motion
  plan.

## What I could not determine

- **Where inside `compile` the 478 hunks land.** Line-offset bucketing is
  defeated by six months of drift (109 of 177 recent in-`compile` offsets fall
  outside today's `compile`). The 49%-of-hunks figure is solid; any finer
  breakdown is not, and no future plan should assert one without a fresh baseline.
- **Whether `--check-migration` has any test coverage at all.** Task A3 Step 3
  makes finding out a required step rather than an assumption.
- **Whether the dead `inject_iface_exports_ref` hook has a user-visible
  consequence.** The todo says so explicitly: no fixture was written, and the
  suspected symptom (cross-module qualified interface-method references failing to
  resolve) is unreproduced.

## Appendix — the band dependency scan

```python
# scratchpad/dep.py — external-dependency scan for a set of line bands.
# Reports which top-level names defined OUTSIDE the band are referenced INSIDE
# it, with comments stripped (single- and multi-line).  Two caveats, both hit
# in practice while writing this plan:
#   * identifiers inside string literals produce false positives (`compile`
#     showed up as a "dependency" of a band that only prints "march: compile…");
#   * it cannot see a band's dependency on an ALREADY-EXTRACTED sibling module.
#     A zero here is not a completeness proof.  `dune build @check` is.
import re
L = open('bin/main.ml', errors='ignore').read().split('\n')
top = {}
for i, l in enumerate(L, 1):
    m = re.match(r"^let\s+(?:rec\s+)?([a-z_][A-Za-z0-9_']*)", l)
    if m: top.setdefault(m.group(1), i)

def uses(a, z):
    s, incom = set(), False
    for l in L[a-1:z]:
        t = re.sub(r'\(\*.*?\*\)', '', l)
        if incom:
            if '*)' in t: incom = False; t = t.split('*)', 1)[1]
            else: continue
        if '(*' in t: t = t.split('(*', 1)[0]; incom = True
        for m in re.finditer(r"(?<![A-Za-z0-9_.'])([a-z_][A-Za-z0-9_']*)", t):
            s.add(m.group(1))
    return s

for name, rs in {"B1+B2+B3": [(10,257),(258,520),(782,1058)],
                 "A3 schema": [(2115,2265),(3033,3098)],
                 "A4 core-ast": [(2794,2932)],
                 "A5 native": [(3684,4628)]}.items():
    inside = {m.group(1) for a, z in rs for l in L[a-1:z]
              if (m := re.match(r"^let\s+(?:rec\s+)?([a-z_][A-Za-z0-9_']*)", l))}
    u = set().union(*(uses(a, z) for a, z in rs))
    print(name, sorted((top[k], k) for k in top if k in u and k not in inside))
```

The same script parameterised on `lib/typecheck/typecheck.ml` produced Target B's
dependency table, and on `lsp/lib/server.ml` the eight-name list in Target C.
