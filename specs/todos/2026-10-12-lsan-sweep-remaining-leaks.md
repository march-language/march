# `[P3]` Leaks the 2026-10-12 LSan sweep still reports in test/native

`scripts/native-sanitize-sweep.sh -l` (Linux arm64 Docker, `MARCH_SANITIZE=1
MARCH_DEBUG_RUNTIME=1`, `ASAN_OPTIONS=detect_leaks=1`, 1 and 14 schedulers)
over the test/native fixtures with a `.expected`. Fixtures with any LSan
report: 87 before the branch `group-o/asan-sweep`, 69 after its fixes (Float
boxes in reused cells, nested patterns, unused erased closure params, Map/Set
Float keys, `task_cancel_by_id`). Aggregate it yourself by re-running the
sweep and grouping each report's first non-allocator frames.

## Second pass (branch `group-x/lsan-leaks`)

Re-run on that base: 70 fixtures with a report (355 fixtures). Fixed, each
per call, not one-shot (see the `specs/progress/2026-10-12-*` files):

- an erased lambda parameter read through a field (`closure_bool_field`);
- the actor registry: name and actor borrowed, its Vault graveyard released
  (`proc_reclaim_kill_respawn`'s 1,500 names);
- the epoch-Cap builtins (`proc_reclaim_kill_respawn`'s caps,
  `cap_epoch_plane`);
- `a ++ b` as a scope's value blocked the aggregate drop
  (`tuple_destructure_rc`);
- file / dir builtins and `print_stderr` (the `IO.warn` line every
  `*_leak_probe` fixture reported).

After the fixes: 61 fixtures with a report without suppressions. The leak
pass now reads `scripts/lsan-suppressions.txt` (the not-a-bug entries below;
`-S` turns it off): 45 fixtures with a report (360 fixtures), 15 of them
in the excluded cluster / session / observe areas.

## Not bugs (suppressed in scripts/lsan-suppressions.txt)

- `march_ctor_table_ensure` (15 KiB per table) and `registry_init_once`
  strings: runtime caches that live for the process.
- `Bad_on_stop` / `Stuck_on_stop` / `Messy_on_stop` (`actor_on_stop_panic`,
  `actor_on_stop_deadline`, `actor_state_released`): the frames of an
  `on_stop` that panicked or was cut off by its deadline are abandoned by
  design, as for any panic.

## Not bugs (not suppressed: no name narrow enough)

- `try_call_err_message`: strings built by a thunk before it panics, and the
  `unreachable` message, abandoned with the panicking frame.
- `supervisor_init_arg_restart`: one init-argument string held by the respawn
  closure of a supervisor still alive at exit.
- `actor_registry_retire`: `march_vault_keys` cells of a list `main` still
  holds at exit.

## Filed separately

- `linear_map` (`Host_Step` / `Host_Open`): per message, see
  `2026-10-12-actor-handler-tuple-match-state-leak.md`.
- `close_returns_ok_atom`, `csv_niche_row` (`march_file_open` /
  `march_csv_open` cells): see `2026-10-12-file-csv-handle-cell-leak.md`.
- An erased record released by a generic dec leaks its heap fields: see
  `2026-10-12-erased-record-shallow-release.md`.

## Still open, not triaged further

- **`proc_reclaim_kill_respawn`**: `march_actor_reply` cells from
  `Worker_dispatch` and `march_actor_call` cells from `caller` (about 50 each
  over 1,500 rounds): replies to callers that timed out and exited, and calls
  whose callee died. Rate-limited by the race, not per call.
- **`module_unboxed_aggregate`**: `List.map$dps` / `List.fold_left` over an
  unboxed `P2` in `main` (2 cells).
- **`actor_inspect_state`**: a `Vault_inspect` cell per inspect (observe
  plane; excluded below).
- **`remote_schema`**: `JsonFrom$OldHit.from_json$own0` (cluster schema;
  excluded below).
- **One-shot in `march_main`**: `bytes_u8_bridge`, `closure_param_shadows_import`,
  `erased_render_show`, `erased_type_id`, `h_escape_ctx_builtin`,
  `h_sigil_adt_interp`, `h_sigil_safe_collision`, `h_trusted_context`,
  `html_safe_raw`, `record_pattern`, `record_pattern_partial`,
  `sha256_hex_string`, `to_string_structural`, `typed_array_scalar_repr`,
  `simd_to_string`, `qualified_type_name_render`, `let_tuple_destructure`,
  `float_consts_typed_array_slice`, `to_string_*`, `ffi_codec2`: a handful of
  objects allocated directly in `main` (a `NativeArray`, a `Bytes.from_hex`
  result, an `IOList.from_strings` list, `to_string` output). Two that looked
  one-shot (`closure_bool_field`, `tuple_destructure_rc`, and the `IO.warn`
  line) were per call in a loop, so each of these deserves a loop probe
  before it is written off.

## Excluded areas (not triaged here)

Cluster / session / NetKernel / control-plane / observe fixtures
(`*_loopback`, `cert_downgrade_after_restart`, `cluster_node_vaults_unnamed`,
`session_party_released`, `topology_place`, `node_discovery`,
`node_send_loopback`, `node_call_loopback`, `rpc_auto_enroll`,
`session_node_fan_loopback`, `remote_schema`, `actor_inspect_state`,
`actor_stash_become`, `recon_basic`) report the handshake and frame buffers
(`ClusterAuth.*`, `NetFrame.*`, `Bytes.concat`, `Msgpack`), `Random.warmup`
and `ClusterNode.start` state; see the existing cluster leak todos.
