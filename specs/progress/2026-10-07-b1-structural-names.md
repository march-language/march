# DONE 2026-10-07: B1, structural names for every compiler-minted symbol

Observability plan (`specs/plans/incremental-codegen-cas-plan.md`) §14. Item 6
of the 2026-10-07 serial follow-through.

## What landed

Every counter that reached a symbol (the §14 inventory) is replaced by a
name derived from where the thing is:

| Shape before | Generator | Shape now |
|---|---|---|
| `$lam<n>` (global lowering counter) | `Lower_expr` | `<host>$lam<k>`; nested `<host>$lam<k>$lam<j>`; inside a local `fn go`: `<host>$go$lam<k>` |
| `$jp<n>`, `$own_drop<n>`, `$respawn<n>` | `Lower_match`, `Lower_expr`, `Lower_actor` | `<host>$jp<k>` etc. (same mechanism) |
| `<lam>$apply$<n>`, `$Clo_<lam>$<n>` (`Defun.lambda_counter`, never reset) | `Defun` via `Tir_names` | `<lam>$apply$<k>_<host'>`, `$Clo_<lam>$<k>_<host'>`: `k` = ordinal among the top-level host's lambdas in defun's traversal order, `host'` = the host with `$` and `.` spelled `_` (`Tir_names.lam_uid` / `structural_tag`) |
| `$fused_<p>_<n>` (module-level counter) | `Fusion` | `$fused_<p>_<host'>_<k>`, host from `Provenance.current_host` |
| `g$hspec$<n>` (per-run counter) | `Hof_spec` | `g$hspec$<i>_<apply'>`: the parameter index and the specialised closure's apply symbol |
| `$V__<id>` (typechecker fresh-var id) | `Mono.mangle_name` | `$V_<position>`: first appearance in the specialisation's type-argument list |

- **Hosts.** `Lower_state.with_host` / `current_host` / `fresh_nested_name`:
  `lower_fn_def` sets the host to the module-qualified fn name
  (`List.map`), a lambda body is hosted by the lambda, a local `fn go` by
  `<host>$go`. Ordinals are per `(host, kind)` and reset per `lower_module`.
  The old `fresh_name` still ticks the shared temp counter for each nested
  mint, so `$t<n>` numbering is unchanged and every snapshot/IR diff of this
  change is symbol-only (locals never reach a symbol; `Serialize`
  alpha-normalises them).
- **The apply prefix is still the lambda's own name**: `Tir_names.apply_fn_base`
  splits at the first `$apply$`, which `Llvm_emit_call`'s self-tail-call
  recognition needs (§14). `lam_uid` is now a string with no `$`, so
  `Drop.apply_name_of_clo`'s "uid is everything after the last `$`" still
  holds for lowering names that contain `$`.
- **REPL/JIT**: each `lower_module` of a fragment runs under
  `Lower_state.set_fragment_scope "$repl<n>."` (a process-local sequence), so
  two fragments' `main$lam0` are distinct symbols in their two shared
  objects; the stdlib precompile passes `~fragment:false` so its names are the
  CLI's. The `.names` file's `lambda_counter=N` sentinel is gone (a stale line
  is ignored on read). `Defun.get/set_lambda_counter` are removed; the
  snapshot harness no longer resets anything before defun.
- **`hr_slot_hashes`**: the per-fn canon is now the CAS serializer's
  alpha-normalised encoding, with residual type-variable names renumbered
  by first appearance; the pretty-print regex that renumbered every
  `$<stem><digits>` token is retired. Nothing counter-shaped is left for it to
  find: `grep -E '\$(lam|jp|fused_[a-z]+_|respawn|own_drop)[0-9]+' *.ll`
  over the IR-oracle corpus matches nothing but `<host>$lam<k>` forms.
- `Provenance.current_host` is exported for `Fusion`.

## Acceptance (§14)

- `scripts/determinism-oracle.sh --corpus small`: DETERMINISTIC across 28
  programs × 4 conditions. Red-first: with main's `fresh_name` perturbed to
  fold the working directory into every temp name, the same run goes red
  (see the PR for the run).
- `scripts/ir-oracle.sh`: see the PR for the renames-only verdict (the manifest
  differs on every program with a lambda, as it must; the `.ll` texts are
  byte-identical after mapping both name shapes to placeholders by first
  appearance).
- `test/snapshots/`: 12 files. Seven are pure renames under the
  normalisation above (the renderer sorts by name, so renamed fns also
  move). The other five `lower/` files also shift local `$t`/`$f` numbers by
  one in some stdlib functions: that shift is **pre-existing on main**, whose
  own `run_snapshots.exe` fails three cases against the committed files
  (`tir_snapshots_lower` 10, 11, 17; a stdlib edit merged without a
  regeneration), so this regeneration carries that catch-up. The compiler's
  own `MARCH_DUMP_TXT=tir-lower` dump of the same program is identical to
  main's modulo names, all 3835 functions.
- `hr_slot_hashes`'s `counter_re` retired.
- The P2 repro (`specs/progress/2026-10-06-cold-stdlib-cache-changes-specializations.md`)
  was already fixed by 5864ef0d1; its "byte-identical `--emit-llvm`" acceptance
  is what the determinism oracle checks.

## Not done

- Test fn names (`Tir_names.test_fn_name <ordinal>`) keep their per-module
  ordinal: not in the §14 inventory, and a test's symbol is never a cache key.
