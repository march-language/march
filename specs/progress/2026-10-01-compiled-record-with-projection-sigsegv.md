# `[P2]` DONE Compiled-only SIGSEGV / stale field around a record update in the control wiring

Filed 2026-10-01 (dd step 12a); fixed 2026-10-03. The resolution is at the end; the
filing and the two earlier attempts are kept as they were.

Filed 2026-10-01 (dd step 12a). Two compiled-only misbehaviours in
`lib/desugar/control_wiring.march` (the control plane's generated wiring), both in code
that reads a field of a record found in another record's list and uses it to build a
record update; the interpreter is fine. Neither is minimised: the obvious standalone
shape (`let r = f()` then `{ r with detail: "" }` in a loop; a `with` whose new field is a
projection of a `List.find` result) runs correctly compiled. Both are worked around.

## 1. The leader's report merge

```march
-- in a closure stored in a record (Control.ControlOps.report), called from a
-- generated session role body
let l = ctl_leader_state()
let rep2 = if rep.detail != "" do rep else match List.find(l.obs, fn o -> o.report.node == rep.node) do
  Some(o) -> { rep with detail: o.report.detail }
  None -> rep
end end
ctl_put_leader(Control.leader_report(l, rep2, unix_time_ms()))
```

Both candidate nodes of `test/two_node/control_plane` died within seconds of starting:
`march: fatal SIGSEGV si_code=2 addr=0x11 pc=... fault outside its stack` (also
`addr=0xe4fec1f5a33cf9c4`: a freed or never-valid pointer). Moving the merge into
`Control.leader_report` (the same logic, as a top-level stdlib function with `prior`
bound first) runs correctly compiled and is covered by `test/stdlib/test_control.march`
("a report without detail keeps the detail last reported").

## 2. `ctl_release`: a stale field after handing the record over

`Control.leader_release(l, r)` followed by reads of `r.seq`, `Control.digest(r)` and
`Control.serialize(r)` gave a release whose `sig` line was `-` (the signature read back
empty) and so `RELEASE_COPY` on the standbys answered `ERR bad_signature`, while the same
document sent by hand verified. Reading everything needed out of `r` *before* the call
(`seq`, `digest`, `body`, the hashes) fixed it.

Probably the same class as
[../progress/2026-09-28-borrowed-field-outlives-owner.md](../progress/2026-09-28-borrowed-field-outlives-owner.md)
(a borrowed field projection outliving its consumed owner), with the owner consumed by a
call rather than a pattern match.

**Acceptance:** a `test/native` fixture with shape 1 (a record-held closure, a `List.find`
over a list of records, a `with` from the found record's field) runs compiled; shape 2's
reads after the consuming call give the same values as before it.

## 2026-10-02: not reproduced standalone

A standalone program with shape 1 — a `report : Report -> Report` closure held in
an `Ops` record, built in a function, called 4,000 times from a loop; inside it a
`List.find` over `leader_state().obs` by `o.report.node == rep.node`, then
`{ rep with detail: o.report.detail }` in the `Some` arm, then the result handed
to a `leader_report` that conses it onto the list and projected back out — runs
correctly compiled at `--opt 2`, every result identical to the interpreter and
`live_allocs()` flat. An ASAN build (`MARCH_SANITIZE=address`) could not be used
as a second witness: on this machine every sanitized binary, including a
ten-line one, spins forever at startup (30 CPU-minutes at 1.3 MB RSS), so that
is a separate problem with the sanitizer build and not evidence either way.

Two of the ingredients the control plane had and this shrink did not: the
closure is called from a generated session role body (an actor), and `rep`
arrives as a decoded message. The class the todo guessed at — a borrowed field
projection outliving its consumed owner — has since had one more instance fixed
(a pattern field read after the scrutinee's deep release, see
[../progress/2026-10-01-dead-join-point-closure-leaks-captures.md](../progress/2026-10-01-dead-join-point-closure-leaks-captures.md)),
so the next attempt should first re-run the original `test/two_node/control_plane`
shape with the workaround reverted on a compiler that has that fix.

**2026-10-02 (dd step 12b):** shape 2 pinned down. The over-release is in
`Control.serialize` itself: `"sig " ++ (if r.signature == "" do "-" else r.signature end)`
released `r.signature` while `r` still held it, and a later read of the release's
signature was a heap-use-after-free (ASAN, CI sanitize-gate). `serialize` was rewritten
so the field goes straight into `++`, and `test/native/control_serialize_twice` fails on
the old form. The compiler bug (an `if` branch returning a borrowed field projection that
a consuming builtin then takes) is still open.

## 2026-10-03: fixed (two different bugs)

### Shape 1 was a type error the driver threw away

Reverting the workaround (the merge back in the wiring's `report` closure) and running
`scripts/two-node.sh control_plane` on main reproduced it: `SIGSEGV addr=…0011` on both
candidates. The post-Perceus TIR of that closure has `rep : { detail : String }`, a
one-field record, not the 12-field `Control.AgentReport`. The lambda's parameter is
unannotated, its first use is `rep.detail`, and the checker typed it from that. It then
reported `expected AgentReport but got { detail : String }` at `fn rep ->` and at the
`leader_report(l, rep2, ..)` argument.

The driver dropped both errors. `bin/main.ml`'s `user_diag` keeps only the entry file,
user files and `<none>`; the wiring is parsed under the file tag `<control>`
(`Hot_reload.control_wiring_file`), so its diagnostics went the way of the stdlib's.
Compiled, `rep.node` read slot 1 of the one-field layout, `{ rep with detail: .. }`
built a one-field record that `leader_report` read past, and the drop was
`__drop$R1_detail$String`. The interpreter has no layouts, so it was fine. A standalone
shrink with the type in the same file is rejected by `--check`, which is why the
2026-10-02 attempt could not reproduce it (it annotated the parameter).

Fix: `user_diag` shows ERRORS spanned in `<control>` (warnings and hints there stay
hidden; the user cannot edit the wiring), rendered against the wiring's own text with a
note saying where they come from. Surfacing them showed two more live ones, on the
certificate-save error path (`"…" ++ e` with `e : FileError`, lines 372 and 376 of
`lib/desugar/control_wiring.march`), now `to_string(e)`. The rest of the generated
topology code (`<topology>`) stays filtered: surfacing it reports role-grant errors in
every function-role app (the body reaches `Topology.hook`'s IO), which are not the
author's to fix.

With the driver fix, the reverted shape 1 is a compile error naming the two spans, not a
crash. Test: `test/test_topology_flag.ml`, "the control plane's generated wiring
typechecks" (`--check` of an app with a `control` section; no `<control>` diagnostic).
RED with line 372 put back to `++ e`.

### Shape 2 was Perceus

`"sig " ++ (if r.signature == "" do "-" else r.signature end)` with `r` an owned
parameter. Post-Perceus TIR on main:

```
let $t = case .. of
  True() -> <drop r>; "-"
  _ -> r.signature          -- no inc_rc, and r is not dropped
in let $rc = ++("sig ", $t) in dec_rc $t; $rc
```

`dup_field_results` (`lib/tir/perceus.ml`) rewrites a result-position projection
`src.f` into `let $rc = src.f in $rc`, so the ELet rule borrows it and the tail return
dups it. It walked only the result positions of the function body; it did not enter a
let's bound value, so a branch whose result is the let's value kept the bare projection.
The binding was then an owned String aliasing the field, and its drop freed what `r`
held. Fix: `dup_field_values` finds the cases along a let's bound value's tail and
normalises their arms. A bare projection or a projection chain (`st.a.b` is
`let t = st.a in t.b`) on that tail is left alone: the ELet rule borrows those already,
and normalising them added an inc/dec pair per level of every nested field read.

That exposed a leak, on main in both this shape and the plain
`if r.f == "" do "-" else r.f end`. `insert_owned_aggregate_param_drops` gave up on a
parameter if ANY path released it (`releases_var` over the whole body, and
`used_only_as_field_source` counting the release as a use), so the first arm's release
left the second arm with none. It now tracks releases per path: the candidates are the
parameters only ever projected (releases allowed, `~releases_ok`); each tail drops the
ones not released on its own path; and when a let's bound value releases a candidate on
some path and nothing after it mentions a candidate, the drops go inside the bound value,
whose paths each know what they released. A release inside a non-tail subexpression
still counts for the rest of the path (conservative: a leak, never a double release).

Test: `test/native/record_branch_field_result.march`. On main it prints
`sig s7 | sig - | sig - | -` and both loops `flat: false`; on this branch the values
match the interpreter and both loops are flat. TIR snapshot
`test/snapshots/src/record_branch_field_result.march`. One existing perceus snapshot
moved (`record_field_tail_projection`): the same one `inc_rc` for the escaping
projection, placed by the earlier normalisation, plus renumbered temporaries.

The first version of the per-path drop double-released a destructured tuple parameter:
`fn (acc, pair) -> let (_, c) = pair ..` lowers to an alias `$p = pair` whose own
scope-end drop releases the cell, and the parameter drop released it again (ASAN
heap-use-after-free in `bench/hash_map_bench.march`). Through an alias a release counts
as a use again (`used_only_as_field_source ~releases_ok` drops the flag at the alias),
which is what main did for that shape.

### What else moved

Post-Perceus TIR, main against this branch, over every `bench/`, `examples/` and
`test/native/` program (numeric suffixes normalised): 15 programs differ. Apart from
this bug's own fixtures (`record_branch_field_result`, `control_serialize_twice`,
`record_field_tail_projection`), every difference is in
the stdlib's cluster, session and control code. Nearly every change is an added release
of a record parameter on a path that never released it (`ClusterAuth`'s handshake
checks dropped `peer` and `creds` on the error paths only; a decoded node message `d`
was dropped only on the unknown-type arm), i.e. a per-call leak gone. One is the bug
itself on main: `SessionNode`'s endpoint handler did
`let failed = if why == "" do state.failed else ..` and put `failed` into the new
state while the old `state` was deep-dropped later in the handler: the old state's drop
released the list the new state held. The rest are inlining decisions that moved with
function size (`ClusterNode.resend_fires` is no longer inlined).

### Not fixed here

The original shape 1, written with an annotated parameter, compiles and runs correctly
but leaks the report on the `Some` path: `rep` is consumed on other paths (returned,
captured by the `List.find` closure) and only read as the `with` base on that one, and
an aggregate with any consuming use has no drop on its read-only paths. A record handed
to a consuming call and then only read (`let a = f(r); .. r.x`) leaks the same way.
Filed as [../todos/2026-10-03-aggregate-read-only-path-never-dropped.md](../todos/2026-10-03-aggregate-read-only-path-never-dropped.md).
