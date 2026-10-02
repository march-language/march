`[P2]` A cold `~/.cache/march` compiles the stdlib to different specializations than a warm one

Found 2026-10-01 while writing forge/test/test_hcr_manifest_diff.ml (the
hot-reload boundary fixes, specs/progress/2026-10-01-hcr-topology-app-functions-no-dispatch-slots.md).

The same source, the same compiler, the same `--topology` digest, compiled
twice in one fresh HOME: the first compile (cold `~/.cache/march`, which then
writes `stdlib_ast_*.bin` and `stdlib_tcenv_cli_*.bin`) and the second (warm)
emit different TIR. With examples/topology_app and
`--compile --compile-so --hot-reload TopologyApp`, the cold build's
`.hcr_manifest` has 13378 functions and the warm one 13376: cold keeps
`Topology.actor_role`, one more `$lam`, and an unspecialized
`Topology.offer_actor_role`; warm has
`Topology.offer_actor_role$String$TopoPlacement$...` instead. Every later
counter-numbered name shifts with it (`go$apply$5545` is
`BigInt.reverse$List_Int`'s helper in one and `...$List_String`'s in the other).
Reproduced with origin/main's compiler (078067811), so it predates the
boundary fixes.

Repro:

```
H=$(mktemp -d); mkdir -p $H/h $H/mh
cd examples/topology_app && forge build   # writes .forge/topology.json
for i in 1 2; do d=$(mktemp -d); (cd $d && env HOME=$H/h MARCH_HOME=$H/mh \
  march --compile --compile-so --hot-reload TopologyApp \
  --topology $OLDPWD/.forge/topology.json -o $d/p.so $OLDPWD/src/topology_app.march); \
  grep -vc '^#' $d/p.so.hcr_manifest; done          # 13378, then 13376
```

Why it matters: a hot deploy compares the patch's manifest with the base's.
When one of the two was built cold and the other warm, stdlib functions show
as changed; a stdlib function has no dispatch slot, so `forge deploy` plans a
restart (Deploy_plan.undeliverable), and `forge deploy hot` lists spurious
new functions. It also means the warm/cold state of a shared cache leaks into
codegen (compare specs/progress/2026-08-24-interp-perf-phase-3-startup-tcenv-cache.md,
which introduced the tcenv cache).

Likely place: whatever the cached stdlib typecheck env (`stdlib_tcenv_cli`)
round-trips differently from a fresh typecheck (a type the cache keeps
unsolved, or a type_map entry the fresh path has and the cache drops), so
mono sees a different type at `Topology.offer_actor_role`'s call site.

Acceptance: two compiles of the same input, one cold and one warm, produce
byte-identical `.hcr_manifest` function lists and `--emit-llvm` IR; drop the
warm-up compile in forge/test/test_hcr_manifest_diff.ml.
