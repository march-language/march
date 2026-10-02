# `[P2]` Compiled-only SIGSEGV: `{ r with f: o.sub.f }` where `o` is a `List.find` result, inside a closure held in a record

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

**2026-10-02 (dd step 12b):** shape 2 pinned down. The over-release is in
`Control.serialize` itself: `"sig " ++ (if r.signature == "" do "-" else r.signature end)`
released `r.signature` while `r` still held it, and a later read of the release's
signature was a heap-use-after-free (ASAN, CI sanitize-gate). `serialize` was rewritten
so the field goes straight into `++`, and `test/native/control_serialize_twice` fails on
the old form. The compiler bug (an `if` branch returning a borrowed field projection that
a consuming builtin then takes) is still open.
