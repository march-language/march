# Early DCE: prune unreachable functions right after Defun

**Landed** 2026-11-02.

## Why

Every program is lowered with the whole prepended stdlib (~6,700 functions after
Defun, ~9,000 after Drop), and the only top-level DCE ran after the Opt loop. So
Perceus, Drop, Escape, borrow inference and the Opt fixed point all ran over
thousands of functions the program never reaches, for the final DCE to keep
5 to 100 of them. Measured with `--timings` on three `test/native` fixtures, that
was ~40% of a small program's compile.

It was most of the macOS CI job's first 24 minutes: ~414 `test/native` fixture
compiles before any suite finishes (main run 41514275700, job 125524405921), and
it is in every suite that compiles a program.

## What changed

`Contract_pipeline.run` calls `Dce.prune_unreachable` right after Defun (the
precondition [Dce] documents; the REPL shell already prunes there,
`lib/jit/repl_jit.ml`). Its roots are the final DCE's (main, setup, migrate fns,
`tm_exports`, tests) plus the `extra_roots` and NoAlloc functions that the
pipeline pins after Escape, so it keeps a superset of what the final DCE keeps.
`tm_exports` is restored afterwards: other passes read it as an ABI fact.

It also roots every function a `remote_ref_hashes("Mod", "fn")` call names
(`Dce.remote_ref_targets`). The driver hashes every pre-opt function for that
constant fold, live or not, so a client and a server agree on a function only
the server calls; without the root, `native_rpc_hash_elim` folded to empty
hashes.

Skipped under hot reload, for JS, and when the optimizer is off. Switch:
`--disable-pass dce-early` / `MARCH_DISABLE_PASS=dce-early`.

| fixture | before | after | final fns |
|---|---|---|---|
| `actor_on_stop_deadline` | 3.5 s | 1.4 s | 36 / 36 |
| `array_trie_drop_leak_probe` | 3.8 s | 2.2 s | 110 / 110 |
| `mixed_tail_aggregate_drop` | 3.2 s | 1.7 s | 9 / 9 |

(wall, warm HOME cache, cold CAS, M-series Mac.)

## What the IR oracle showed

`scripts/oracle-base.sh ir` reports 513 programs CHANGED, because fresh-name
counters now run over fewer functions. Compared against the same compiler with
`dce-early` disabled, after replacing digits and sorting lines:

- 485 identical (2 byte-for-byte; the rest differ only in numbering and order);
- 1 real loss, the `remote_ref_hashes` one above, fixed;
- 29 differ in inlining: Opt's inliner counts call sites, and pruned stdlib
  callers no longer count, so some helpers are now inlined and others kept
  (e.g. `PeerRegistry.add` inlined, `NodeSend.encode_msg_schema` kept), and
  the strings those bodies use move with them. All but `bench_dataframe_bench`
  are `test/native` fixtures with golden output.
