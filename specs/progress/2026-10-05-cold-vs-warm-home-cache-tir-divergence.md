# Cold vs warm `$HOME` stdlib cache gave different TIR (and CAS key)

Observed 2026-10-05: for an UNCHANGED source, the post-TIR CAS key
(`MARCH_CASFLAGS ... src=`) depended on whether `~/.cache/march`'s stdlib tcenv
was cold or warm, so the first compile after a cold HOME missed the post-TIR
cache. The TIR itself differed, not just the key.

## Root cause

`get_stdlib_tc_env` (`bin/main.ml`) returned the LIVE `final_env` on a cold
run but a Marshal-decoded copy on a warm run. The live env and its `type_map`
share mutable tvar cells; the entry module's pass 2 linked
`Topology.actor_role`'s generic `Pid(a)` annotation to one concrete record
type. Lowering then saw `Pid({factor, ...})` (cold) vs `Pid('_N)` (warm), which
made mono emit an extra clone of `actor_role`/`offer_actor_role`, shifted the
global `Defun.lambda_counter` by 4 (`go$apply$1557` vs `1553`), and changed
every downstream per-SCC hash. Found by diffing `MARCH_DUMP_TXT=all` between
the two states: the first difference was the `tir-lower` signature of
`Topology.actor_role`.

## Fix

The four cache pieces are encoded once; the cold path now decodes those exact
bytes (the same `decode_pieces` the file reader uses) instead of using
`final_env`, so cold and warm start pass 2 from identical state.

## Tooling

- `MARCH_DEBUG_CASFLAGS` line now prints `src=<digest>`; `MARCH_DEBUG_CASFLAGS=2`
  also prints one `MARCH_SCC: <impl hash> <fn>` line per SCC of the post-TIR
  module, for diffing two compiles.

## Test

`test/test_topology_flag.ml` `test_cold_and_warm_home_emit_same_ir`: compiles
`examples/topology_app`-shaped actor-role fixture twice under a private HOME
(cold, then warm) and asserts byte-identical `--emit-llvm --opt 2` IR. RED on
the pre-fix compiler, GREEN after.
