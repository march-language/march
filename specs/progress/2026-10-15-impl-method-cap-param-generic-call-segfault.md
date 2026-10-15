`[P1]` Compiled `--test` builds: an interface impl method reached through a generic receiver was called with one argument too few (#708)

Filed as march-language/march#708 (2026-09-29), found by conduit's test suite:
`impl Storage(FakeWorkflowStorage)`'s `event_append` read `DateTime.now()`, and
`Conduit.EventStore.append(storage, ...)` (a generic helper forwarding to
`Storage.event_append`) segfaulted in `march_string_concat` with `workflow_id`
null. The issue's standalone repro did not trigger because it was built without
`--test`.

## Cause

`lib/tir/cap_passing.ml` runs right after lowering, and only when capability
mocking is on (`--test`, or `MARCH_CAP_DISPATCH=1`). It gives every function that
transitively performs an interceptable operation an implicit capability
parameter, and threads it from callers found in the call graph. A call through
an interface from a still-generic receiver is a call head naming the METHOD
(`event_append`, or a module-qualified spelling); Mono resolves it to
`Storage$Fake.event_append` only later. So the impl was elaborated (it calls
`unix_time`, IO.Clock), the helper had no call edge to it and was not threaded,
and after Mono the helper called the impl without the capability: every
argument shifted by one register.

## Fix

`mark_iface_dispatch_targets` marks every impl that a method-named call head
could dispatch to as arity-frozen (`unsafe`), so it is not elaborated. Resolution
mirrors Mono's `iface_target` (exact name, then module-stripped suffixes,
`to_string` falling back to `show`). Cost: an operation inside such an impl runs
on the ambient capability, so `with_cap` does not intercept it there. That is the
pass's existing trade-off for any function whose arity cannot change, and is
listed with the other restrictions in the module header.

## Tests

`test/cap_mock/cap_mock_iface_generic.march` (compiled `--test`): generic helper,
interface default method, and a direct call. SIGSEGV (rc 139) with the marking
disabled, interpreter-identical output with it.
