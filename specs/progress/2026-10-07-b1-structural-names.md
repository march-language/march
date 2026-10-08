# DONE 2026-10-07: B1, structural names for every compiler-minted symbol

Observability plan (`specs/plans/incremental-codegen-cas-plan.md`) §14. Item 6
of the 2026-10-07 serial follow-through.

## What landed

Every counter that reached a symbol (the §14 inventory) is replaced by a
name derived from where the thing is. `host'` below is the host through
`Tir_names.structural_tag`, which spells `$` and `.` as `_`.

| Shape before | Generator | Shape now |
|---|---|---|
| `$lam<n>` (global lowering counter) | `Lower_expr` | `$lam<k>_<host'>`; nested `$lam<j>__lam<k>_<host'>`; inside a local `fn go`: `$lam<k>_<host'>_go` |
| `$jp<n>`, `$own_drop<n>`, `$respawn<n>` | `Lower_match`, `Lower_expr`, `Lower_actor` | `$jp<k>_<host'>` etc.; a respawn thunk is hosted by its actor's `_spawn` glue |
| `<lam>$apply$<n>`, `$Clo_<lam>$<n>` (`Defun.lambda_counter`, never reset) | `Defun` via `Tir_names` | `<lam>$apply$<k>_<host'>`, `$Clo_<lam>$<k>_<host'>`: `k` = ordinal among the top-level host's lambdas in defun's traversal order (`Tir_names.lam_uid`) |
| `$fused_<p>_<n>` (module-level counter) | `Fusion` | `$fused_<p>_<host'>_<k>`, host from `Provenance.current_host` |
| `g$hspec$<n>` (per-run counter) | `Hof_spec` | `g$hspec$<i>_<apply'>`: the parameter index and the specialised closure's apply symbol |
| `$V__<id>` (typechecker fresh-var id) | `Mono.mangle_name` | `$V_<position>`: first appearance in the specialisation's type-argument list |

- **Hosts.** `Lower_state.with_host` / `current_host` / `fresh_nested_name`:
  `lower_fn_def` sets the host to the module-qualified fn name (`List.map`),
  a lambda body is hosted by the lambda, a local `fn go` by `<host>$go`.
  Ordinals are per `(host, kind)` and reset per `lower_module`. Each nested
  mint still ticks the shared temp counter, so `$t<n>` numbering is as before.
- **A minted name keeps its leading `$` and contains no `.`.** Two rules read
  meaning from a name's shape: `Hot_reload.module_of_name` ("everything before
  the last `.`") decides capability attribution and which functions are
  hot-reload slots versus bare helpers, and about sixty other consumers take
  the text after the last `.` as a short name. The first cut named lambdas
  `Mod.f$lam0` with apply uids `…$apply$0.Mod.f`, and it broke three things.
  The entry thunk called a lambda, so the compiled pooled HTTP server
  segfaulted at startup. Stdlib lambdas' capability use was charged to the
  stdlib module ("module `NetKernel` uses `IO.Clock`"). And the embedded
  capability report of 9 corpus programs changed. Module-less names restore
  all three to main's behaviour, with no change to capability attribution.
  `-` was tried as the separator and is rewritten to `_` by
  `Llvm_ctx.llvm_name` but not at every reference, so the link failed; `_`
  is the one character left.
- **The apply prefix is still the lambda's own name**:
  `Tir_names.apply_fn_base` splits at the first `$apply$`, which
  `Llvm_emit_call`'s self-tail-call recognition needs (§14). `lam_uid` has no
  `$`, so `Drop.apply_name_of_clo`'s "uid is everything after the last `$`"
  still holds.
- **REPL/JIT**: each fragment's `lower_module` runs under
  `Lower_state.set_fragment_scope "$repl<n>."` (a process-local sequence), so
  two fragments' `main` lambdas are distinct symbols in their two shared
  objects. The stdlib precompile passes `~fragment:false`, so its names are
  the CLI's. The `.names` file's `lambda_counter=N` sentinel is gone (a stale
  line is ignored on read). `Defun.get/set_lambda_counter` are removed, and
  the snapshot harness no longer resets anything before defun.
- **`hr_slot_hashes`**: the per-fn canon is now the CAS serializer's
  alpha-normalised encoding, with residual type-variable names and the
  `V_<id>` of drop-glue names renumbered by first appearance. The
  pretty-print regex that renumbered every `$<stem><digits>` token is
  retired.
- **Not converted: drop glue.** `__drop$List_V_53272` (keyed by
  `Drop.mangle`) still carries a typechecker id. Canonicalising it would merge
  drop functions, which is not a rename. Filed as
  `specs/todos/2026-10-07-drop-glue-name-carries-tvar-id.md`. Test fn names
  (`Tir_names.test_fn_name <ordinal>`) keep their per-module ordinal; they are
  not in the §14 inventory.
- `Provenance.current_host` is exported for `Fusion`. The D24 respawn-thunk
  regex in `test/test_codegen.ml` and the `Tir_names` unit tests follow the
  new shapes.

## Acceptance (§14)

- **Determinism oracle** (`scripts/determinism-oracle.sh --corpus small`):
  DETERMINISTIC across 28 programs × 4 conditions. Red first: main's
  `fresh_name` perturbed to fold the working directory into every temp name
  makes the same run fail all 28.
- **`scripts/ir-oracle.sh`** against a baseline from main (d9fbbf179): 423 of
  431 programs change, as every program with a lambda must. All 423 are
  identical to main's `.ll` after mapping each name shape, local temp and SSA
  register number to a placeholder, and comparing the name-ordered
  `march_clo_drop_pairs` table as a set. Zero programs differ in their
  embedded capability report (`__march_capdecl_*` / `__march_capfrom_*`).
- **`test/snapshots/`** (12 files) regenerated on top of current main: symbol
  renames only (the renderer sorts by name, so renamed fns also move). The
  harness runs main's A1 verifier at every stage and main's A6 metrics pins;
  both pass unchanged (61 cases).
- `hr_slot_hashes`'s `counter_re` is retired.
- The P2 repro (`specs/progress/2026-10-06-cold-stdlib-cache-changes-specializations.md`)
  was already fixed by 5864ef0d1; its byte-identical `--emit-llvm` acceptance
  is what the determinism oracle checks.

## Tests

`run_codegen -q` (675), `run_compiler -q` (1290), `run_eval -q` (288),
`run_stdlib -q` (825, including the compiled HTTP end-to-end servers),
`run_errors` (277), `test_jit` (33), `test_lsp` (379), `test_deploy_plan`
(27), `run_snapshots` (61): all green.
