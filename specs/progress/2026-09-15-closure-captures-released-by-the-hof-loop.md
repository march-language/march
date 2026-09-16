# A capturing lambda passed to map/filter is released with its captures

**Landed 2026-09-15.** Item 2 of
`specs/todos/2026-09-06-closure-capture-release-widening.md`, and the first of
the two leftovers named in
`specs/progress/2026-09-14-closure-calls-consume-their-arguments.md`. Item 3
(the outer release) was built, measured, and BACKED OUT — see below; it stays
open with what the attempt established.

## The defect

```march
List.map([int_to_string(n), "ab"], fn s -> string_length(s) + k)   -- 1 object per call
```

Measured on `origin/main` ed7af146c, Darwin arm64, `--compile --opt 2`: `map`
and `filter` over a capturing lambda leaked exactly one object per call — the
lambda's environment, and with it everything the lambda captured.

`List.map`/`List.filter` build an internal `go` closure over the callback and
call it recursively. Perceus binds `$clo` to a local alias with a dup
(`let go = inc_rc $clo; $clo`), hands `go` down the recursion, and splices its
`dec_rc $clo` after the capture-read prefix.
`Drop.rewrite_apply_clo_drop` rewrote *that* release into `march_decrc_freed`
and hung the capture releases off it — but with the dup outstanding it never
reaches zero, so those releases never fired. The release that does reach zero
is the last iteration's `dec_rc go`, and it was shallow.

The gate was not the problem: `go`'s closure type already qualified as owning
its captures. Only the release keyed on was wrong.

## What landed

`lib/tir/drop.ml`, `rewrite_apply_clo_drop`: the `$clo` SELF-ALIAS's release is
rewritten the same way as `$clo`'s own. Both become `march_decrc_freed`, and
only one of them can reach zero, so exactly one guard fires.

## Item 3, built and backed out: the outer release of a closure value

`List.fold_left` ends with `dec_rc f` — a bare release of a closure value,
whose TIR type is a function type naming no layout. `Drop`'s module doc has
this as the open case, resolvable with "a runtime table keyed by the code
pointer in field 0". That was built: a `__drop_clo$<Clo>` per closure type, a
pointer-keyed runtime table registered by a module constructor, and
`march_drop_closure` at the release site. It made the fold case flat (3 objects
per call to 0) and was clean on the whole ASAN corpus and both local suites.

**It is a use-after-free, and CI caught it** (run 35055097342, the
`two-node[skew]` scenario; reproduced 3/3 locally, and under ASAN in the
container):

```
WRITE of size 8 ... in march_incrc
    Map.node_fold ... SwimDriver.alive_others ... SwimDriver.pick_helpers
freed by ... march_drop_closure ... go$apply$4072
previously allocated by ... march_string_from_chars, Msgpack.decode_str_body
```

A node id decoded off the wire, still owned by the members `Map`, was released
by the deep drop of a closure that had captured it. **The gate is per closure
TYPE and asks whether the environment escapes; it does not ask whether each
CAPTURE was an ownership transfer at that site.** Perceus emits no RC op when
it captures a borrowed alias (a field of a live record, an entry the map still
owns), so such an environment does not own that capture and must not release
it. The apply-function side survives this because it only releases when its own
release of the environment reached zero AND the captures were transferred in;
the outer table applies the same per-type verdict to a site it cannot see.

What a sound version needs: a per-SITE, per-CAPTURE answer — register a closure
type only if every allocation site of it demonstrably took its own reference to
every capture that needs one (an `inc_rc` immediately before the alloc, or a
capture whose last use is the alloc). That is recorded in the todo.

## Verification

- `test/native/closure_capture_hof_loop_probe.march`: 4 legs — `map` and
  `filter` over a capturing lambda, a closure inside a constructor, and one
  whose capture is read on every call (an over-eager release shows up as a
  wrong number, not a leak). Flat over 5,000 iterations; golden matches the
  interpreter. Red before the fix on the two HOF legs, 1 object per call.
- `two-node[skew]` 3/3 and every other two-node scenario green (`stall` flaked
  once with a SIGPIPE, then 4/4 on both this branch and `main`).
- ASAN (linux/arm64 container): `sanitize.sh` 47 golden + 25 native clean, plus
  the leak/closure/actor probes and `node_discovery` 3 runs each.
- Full `@test/runtest` and `scripts/run-tests.sh` green; benchmarks neutral
  (`list_ops` 0.069 s, `tree_transform` 0.648 s vs 0.655 s, `binary_trees`
  0.225 s vs 0.224 s), outputs byte-identical.
