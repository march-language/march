# `[P2]` Hot reload: a topology app's own functions get no dispatch slot, and generated names renumber

Found by `forge deploy`'s end-to-end test (distributed-deploys build step 10b,
[../progress/2026-09-22-dd-step10-ssh-backend-and-plan.md](../progress/2026-09-22-dd-step10-ssh-backend-and-plan.md)).
Compiler side (bin/, lib/tir/); forge works around both and says so in `--plan`.

1. **No slots for the entry module's functions.** In a topology app the entry
   module's declarations reach TIR without the entry module's name
   (`Back.serve_one`, `Front.start`, `main`), so `--hot-reload <entry module>`
   (`Hot_reload.is_reloadable`, `under app_prefix`) covers none of them. A running
   `examples/topology_app` base answers `ABI_QUERY` with ten slots, all actor
   dispatchers. Either name them under the entry module, or let `--hot-reload` take
   several prefixes (`Hot_reload.config.includes` exists but has no flag).
2. **Generated names come from a global counter.** A one-token edit
   (`state.total + n` → `state.total + n + 1` in a handler) renumbers every later
   `$lam<n>`/`$jp<n>`, and every function that references one gets a new impl hash
   (`Front.count`, `Front.start` (a hook), `main`), although its code is unchanged.
   Two fresh builds of the same source are identical, so this is edit-driven, not
   nondeterminism. A handler's own body lives in `<Actor>_<Msg>` (e.g.
   `CounterActor_Deliver`), which has no slot; `<Actor>_dispatch` did not change.

Effect today: almost any edit to a topology app plans a restart (`Deploy_plan`
restarts when a changed function has no slot and no changed slotted caller). Hot
patches work for code under a pool-module prefix (`[hot-reload] module_prefix =
"Back"`) and edits that make no new generated names.

**Acceptance.** Editing a role body of `examples/topology_app` plans and deploys as a
hot patch (`forge/test/test_deploy_e2e.ml` without the `module_prefix` override).

## Resolution (2026-10-01)

1. **Slots.** Point 1 was half fixed on 2026-09-25 (`hr_entry_nested`: the
   entry file's nested modules, `Back.*` and `Front.*`, are includes); the
   entry module's own top-level functions are slots now too
   ([2026-10-01-hcr-entry-module-top-level-fns-outside-boundary.md](2026-10-01-hcr-entry-module-top-level-fns-outside-boundary.md)).
   A running examples/topology_app base answers with 13 slots: `Back.start`,
   `Back.serve_one`, `Back.scale` (the e2e test's helper), the four generated
   `Back.topology_*_CounterActor` forwarders, the five `Front.*` fns and
   `CounterActor_dispatch`. No `[hot-reload] module_prefix` is needed.
2. **Renumbering.** #663 canonicalised only the hashes it FOLDED into a slot;
   every function's own hash was still the CAS's `hash_fn_def`, which
   serialises the counter names it references. Now `hr_slot_hashes`
   (bin/main.ml, one function for the `--compile` and `--emit-llvm` paths; the
   latter had no fold at all) gives every function a canonical own hash: the
   pretty-printed definition with each counter-generated token (`$lam<n>`,
   `$jp<n>`, `$t<n>`, the inliner's `_i<n>`, and an unsolved type variable
   `'_<n>`, which is how `main` still differed after the `$`-names were
   handled) replaced by its order of first appearance in that definition, so
   two distinct temporaries stay distinct. Then slots fold their bare
   helpers in as before.
3. **Closures.** A changed lifted lambda had no `callers:` in the manifest (a
   closure is built from an atom, never called by name), so
   `Deploy_plan.undeliverable` saw a changed function with no slotted caller
   and planned a restart for any edit inside a role body's closure, although
   the slot that builds the closure folds it in and changes with it. The
   manifest writer now records the function that builds a closure as the
   lambda's caller, for unslotted bare callees only (a slot's `callers:` is
   signed into ACTIVATE and capped).

**Acceptance met.** forge/test/test_deploy_e2e.ml without the `module_prefix`
override: an edit inside `Back.serve_one`'s closure plans `hot patch`
(`changed:` lists the lambda and `Back.serve_one` only) and deploys
(`activated: Back.serve_one`); then the `Back.scale` edit, as before. With
origin/main's compiler the same test plans a restart and flags `Front.count`,
`Front.echo`, `Front.run`, `Front.start` and `main`. The test now grants
`Session.Live` in its copy's pool caps: the node policy refused the role-body
patch (`ERR cap_policy Session.Live`), a forge policy gap filed as
specs/todos/2026-10-01-role-body-hot-patch-needs-session-live-in-policy.md.

**Other tests.** forge/test/test_hcr_manifest_diff.ml (v1/v2 manifests,
forge's own `Deploy_plan.fn_diff` and `undeliverable`): a handler edit
(`state.total + n` -> `+ n + 1`) flags exactly `CounterActor_Deliver` and
`CounterActor_dispatch`; a closure edit flags exactly `Back.serve_one` (plus
its lambda, deliverable through it); an entry-module edit flags exactly that
function. Red with origin/main's compiler (`Front.*` and `main` flagged), and
red with only the closure-caller edge reverted (the lambda undeliverable).
The `forge test --upgrade-from` entry-module case also asserts that `start`,
whose lambda an edit to `serve_one` renumbers, is not activated: red with the
canonicalisation reverted ("start was activated").

**Found on the way, filed.** A cold `~/.cache/march` specializes the stdlib
differently from a warm one (13378 vs 13376 functions for topology_app, on
origin/main too): specs/todos/2026-10-01-cold-stdlib-cache-changes-specializations.md.
The manifest-diff test warms the cache first.

## The boundary cost, measured again

Many more functions are slots now (every function written in the entry file
under `--hot-reload <EntryModule>`), so G1's measurement
([2026-09-23-hot-reload-boundary-cost.md](2026-09-23-hot-reload-boundary-cost.md))
was repeated with its method: each binary built with `--compile --opt 2` from a
fresh directory with a fresh HOME, each executed once before timing, five
interleaved rounds, a Python runner gating every round on the 1-minute load
average (<= 8; the actual load was 2.6-5.3 throughout). Variants: `plain`
(no `--hot-reload`), `hrmain` (origin/main 078067811's compiler) and `hrfix`
(this branch), with G1's prefixes (`ListOps`, `Ops`, `Game`) plus `Fib` and
`MutualRecursion`, both entry modules. Compiled dispatch-call sites
(`otool -tv | grep -c 'bl.*_march_dispatch_enter'`), main / fix: list_ops 3 / 13,
fib 3 / 4, list_ops_nested 13 / 13, actor_ping 8 / 8, mutual_recursion 3 / 6.

**First run: a recursive entry fn paid ~5 ns per call.** `fib` (non-tail
self-recursion, ~331M calls) under `--hot-reload Fib`: plain 0.418 s, hrmain
0.418 s, hrfix **2.016 s (+383 %)**; user time 0.378 -> 1.858 s. Every recursive
call went through `march_dispatch_enter_unit`. The hot_reload.ml comment said
intra-SCC calls stay direct, but nothing implemented it, and before this
change a bare entry fn was never a slot, so nothing measured it (a nested
module's recursive fn always paid it).

**Fix: a self-call stays direct** (llvm_emit_call.ml, `Llvm_ctx.hr_cur_fn`,
set by `Llvm_toplevel.emit_fn` only while it emits that function's own body).
A running invocation finishes on the version it started on, which is what a
self-TAIL-call (a loop) always did. Mutual recursion between two slots still
dispatches. Test: test/test_hcr_stdlib_actors.ml (`depth` calls itself
directly and dispatches nowhere; red with the rule removed).

Second run, the final compiler (wall seconds, median of five `[min-max]`, the
percentage against `plain`):

| benchmark | plain | hrmain | hrfix |
|---|---:|---:|---:|
| `list_ops` | 0.057 [0.055-0.063] | 0.059 (+2.7 %) [0.056-0.060] | 0.058 (+0.7 %) [0.056-0.063] |
| `list_ops_nested` | 0.080 [0.071-0.081] | 0.077 (-4.2 %) [0.076-0.079] | 0.075 (-5.9 %) [0.075-0.076] |
| `actor_ping` | 1.051 [1.049-1.069] | 1.093 (+4.0 %) [1.089-1.100] | 1.091 (+3.8 %) [1.087-1.092] |
| `fib` | 0.392 [0.388-0.392] | 0.395 (+0.7 %) [0.390-0.397] | 0.393 (+0.4 %) [0.388-0.394] |
| `mutual_recursion` | 0.020 [0.018-0.024] | 0.019 (-7.3 %) [0.017-0.021] | 0.018 (-9.4 %) [0.018-0.021] |

hrfix versus hrmain is within the run-to-run spread everywhere: making the
entry module's functions slots costs nothing measurable on these programs.
`list_ops`' helpers are self-tail-recursive (loops), so its ten new sites are
the calls between helpers, a handful per run, like list_ops_nested's in G1.
Aside: G1's anomaly (plain `actor_ping` 2.7x slower than `--hot-reload`) is
gone on today's main; plain is now the fastest by about 4 %.
