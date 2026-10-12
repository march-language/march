# `[P3]` Leaks the 2026-10-12 LSan sweep still reports in test/native

`scripts/native-sanitize-sweep.sh -l` (Linux arm64 Docker, `MARCH_SANITIZE=1
MARCH_DEBUG_RUNTIME=1`, `ASAN_OPTIONS=detect_leaks=1`, 1 and 14 schedulers)
over the 342 test/native fixtures with a `.expected`. Fixtures with any LSan
report: 87 before the branch `group-o/asan-sweep`, 69 after its fixes (Float
boxes in reused cells, nested patterns, unused erased closure params, Map/Set
Float keys, `task_cancel_by_id`). What is left, grouped. Aggregate it yourself
by re-running the sweep and grouping each report's first non-allocator frames.

Most of these are ONE-SHOT (a few objects per run, not per iteration): every
candidate below that was re-measured in a `live_allocs()` loop inside an
ordinary function stayed flat. Fix the per-call ones first.

## Not bugs (leave alone)

- `march_ctor_table_ensure` (15 KiB per table) and `registry_init_once`
  strings: runtime caches that live for the process.
- `Bad_on_stop` / `Stuck_on_stop` (`actor_on_stop_panic`,
  `actor_on_stop_deadline`): the frames of an `on_stop` that panicked or was
  cut off by its deadline are abandoned by design, as for any panic.

## Probably per-call: worth a probe each

- **`proc_reclaim_kill_respawn`**: tens of KiB of `march_string_concat` in
  `round` and of `march_get_cap` results in its lambda, plus
  `march_actor_reply` / `march_actor_call` cells. Grows with the round count.
- **`actor_state_released`**: `Messy_on_stop` / `Messy_dispatch` cells and the
  `int_to_string` strings they hold (1.3 KiB each way).
- **`linear_map`**: the `Host` actor's `LinearMap` / `Map` nodes
  (`Host_Step`, `Host_Open`, `LinearMap.put/fill/vacate/take_slot`).
- **`module_unboxed_aggregate`**: `List.map$dps` / `List.fold_left` over an
  unboxed `P2` (see also 2026-10-12-unboxed-aggregate-closure-capture-leak.md).
- **`actor_inspect_state`**: a `Vault_inspect` cell per inspect.
- **`remote_schema`**: `JsonFrom$OldHit.from_json$own0`.
- **`close_returns_ok_atom`, `csv_niche_row`**: the `march_file_open` /
  `march_csv_open` handle cells after `file_close` / `csv_close`.

## One-shot, in `march_main`

`bytes_u8_bridge`, `closure_bool_field`, `erased_render_show`,
`erased_type_id`, `h_escape_ctx_builtin`, `h_sigil_adt_interp`,
`simd_vector_core`, `simd_vector_mem`, `simd_to_string`,
`qualified_type_name_render` and several `*_leak_probe` fixtures leak a
handful of objects allocated directly in `main` (a string from `++`, a
`NativeArray`, a `Bytes.from_hex` result, an `IOList.from_strings` list).
The same shapes inside a function loop are flat, so whatever `main` does
differently (its own last-use drops? the entry thunk?) is the thing to find.

## Excluded areas (not triaged here)

Cluster / session / NetKernel / control-plane fixtures (`*_loopback`,
`cert_downgrade_after_restart`, `cluster_node_vaults_unnamed`,
`session_party_released`, `topology_place`, `node_discovery`) report the
handshake and frame buffers (`ClusterAuth.*`, `NetFrame.*`, `Bytes.concat`)
and `ClusterNode.start` state; see the existing cluster leak todos.
