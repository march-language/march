`[P2]` The entry module's top-level functions are never on the hot-reload boundary

Filed 2026-09-25 while closing `2026-09-25-hcr-dispatch-callee-only-rule.md`.

Lowering strips the entry module's name from every declaration in the entry
file, so with `--hot-reload UpgradeApp` a top-level `fn serve_one` in
`src/upgrade_app.march` is named `serve_one` (module `""`), which
`Hot_reload.is_reloadable` never matches; only the file's nested modules (now
carried as `includes`, see `hr_entry_nested` in bin/main.ml) and actor
handlers (included unconditionally) are on the boundary. A forge topology app
whose role bodies are top-level functions of the entry file therefore gets
"No hot-deployable changes detected" from `forge deploy hot` when it changes
one, which is silent-looking and wrong: nothing tells the user the body could
never have been deployed.

Two ways out, either of which needs care because `main` (and `<Mod>.main`)
must stay OFF the boundary (`is_entry_fn` in llvm_toplevel.ml: swapping the
running root frame corrupts the allocator):

1. Put bare-named non-`main` functions of the entry file on the boundary when
   the prefix names the entry module. The whole-program TIR has no record of
   which bare names came from the entry file versus lifted lambdas and actor
   handlers, so this needs a provenance mark from lowering.
2. Have forge (`forge new`, the topology gate) require role bodies in a lib
   module or a nested module, and say so when a body is a bare entry function.

Until then, `forge deploy hot` should at least say that a changed entry-module
function is not deployable rather than "no changes".

## Resolution (2026-10-01): option 1, by loader provenance

The entry file's own top-level functions are dispatch slots when the
`--hot-reload` prefix names the entry module (what forge passes).

- **Provenance, recorded by lowering.** `Lower.lower_module`'s pass 2 records
  every top-level `DFn` whose span lies in the entry file
  (`Lower_state._entry_file`) under its TIR name (after the builtin-shadow
  rename), except `main` and the compiler's `__`-named fns:
  `Hot_reload.note_entry_file_fn`, reset per `lower_module` like the actor
  provenance #727 added. A bare name alone says nothing (the prelude, lifted
  lambdas, join points, actor glue and the generated topology code are all
  bare), so this is a provenance mark, not a name rule.
- **One slot predicate.** `Hot_reload.is_slot_fn cfg n`: not a program entry
  (`is_program_entry`: `main`, `<Mod>.main`, moved here from llvm_toplevel and
  bin/main.ml, which each had a copy) and (under the prefix or an include, or
  a non-stdlib actor's dispatch, or `is_entry_file_slot`). The reload name
  table (`Llvm_toplevel.emit_module`'s `hr_names`) and the driver's slot-hash
  fold both use it. `is_entry_file_slot` needs the new config field
  `entry_top_level`, which bin/main.ml sets next to `hr_entry_nested` (the
  prefix equals the entry module's name).
- **The other boundary sites.** A call dispatches when `needs_dispatch` holds
  or the callee `is_entry_file_slot` (llvm_emit_call.ml); the inliners
  (`Inline.is_reloadable_name`, which single_use_inline also uses) and the
  static-closure path (llvm_emit.ml) use `Hot_reload.needs_dispatch_to`, so a
  small top-level fn is no longer inlined into `main` past its slot. The
  mutual-TCO wrappers (llvm_tco.ml) now keep a slot default-visible in a patch
  `.so`, as `vis_prefix` already did for plain fns.
- **What stays off.** `main` (the root frame). The generated topology `main`
  and the control-plane wiring spliced into a `[control]` app's entry module
  are parsed under `<topology>` and `<control>` (bin/topology_gen.ml), never
  the entry file, so they are never recorded; the wiring's actor
  (`CtlRespawner`) is recorded as the stdlib's
  (`Hot_reload.control_wiring_file`, `Lower.note_actor_provenance`). Same
  reasoning as #727 for stdlib actors: the control plane runs a deploy, a
  deploy must not swap or migrate it, and a change to it ships with the
  toolchain, which is a restart. Endpoint modules generated from a protocol
  (`Echo_Server`, ...) were already off (`hr_entry_nested` reads the parsed
  module). A polymorphic entry fn's specializations (`foo$Int`) are not
  recorded: they are bare non-slots, folded into their slotted callers' hashes
  and delivered with those callers' patches.

**Tests.** `forge test --upgrade-from` case "a patch to the entry module's own
top-level functions is hot deployed" (forge/test/test_upgrade_from.ml;
fixtures/upgrade/entry_v1 over v1, then live + entry_live): the role body
`serve_one` and its task fn `nested` live at the top of the entry module; the
new body spawns a task that reads the Vault the old hook made and starts a
session of its own, and the traffic must get the new body's answer (1111).
Red with `is_entry_file_slot` forced false: "No hot-deployable changes
detected", the traffic got 1002 (the old body). Also in-process
(test/test_hcr_stdlib_actors.ml: the slots are `Counter_dispatch`, `helper`,
`quiet`, not `main`, nor a `<control>` fn or actor; `main`'s call to `helper`
dispatches) and the predicates (test/test_hot_reload.ml), and the manifest of
a one-line edit to `nested` flags exactly `nested`
(forge/test/test_hcr_manifest_diff.ml).

**Cost.** A call to an entry-module function now goes through the dispatch
table, as a call to a nested module's function already did, except a
function's call to itself, which stays direct (added here after a recursive
`fib` measured 4.8x slower): measured in
[2026-10-01-hcr-topology-app-functions-no-dispatch-slots.md](2026-10-01-hcr-topology-app-functions-no-dispatch-slots.md),
nothing measurable left.
