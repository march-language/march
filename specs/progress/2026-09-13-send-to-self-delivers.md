# `send(self, …)` inside an actor handler delivers, on both backends

**Landed 2026-09-13.** Filed 2026-09-12 as
`specs/todos/2026-09-12-send-to-self-does-not-deliver.md` (`[P1]`), found while
making `self` compile at all
(`specs/progress/2026-09-11-self-in-an-actor-handler-does-not-compile.md`).

## The defect

```march
on Tick() do
  if state.n > 0 do print_line("resumed via self")
  else
    let _ = send(self, Tick())
    print_line("re-sent to self")
  end
  { state with n: state.n + 1 }
end
```

| backend | before | after |
|---|---|---|
| interpreted | nothing at all, exit 0 | `re-sent to self`, `resumed via self` |
| compiled | `re-sent to self`, then nothing, exit 0 | same two lines |

The todo's guess was the mailbox push to a currently running proc. **It was
nothing of the kind: `self` was never bound.** The typechecker binds `self` as
a handler-scoped `Pid(state)` variable (`typecheck.ml`, the `DActor` arm), but
neither backend did:

- **Compiled.** `--emit-llvm` showed `call ptr @march_send(ptr
  @march_self$static_clo, …)`: the bare name fell through to the global `self`
  builtin and lowered to that builtin's static closure. `march_send` read the
  closure's word 3 as the alive flag, and the send returned `None`.
- **Interpreted.** The handler env held `state` and the params, so `self`
  resolved to the builtin's `VBuiltin` function value. `send` raised on a
  non-pid target, `run_scheduler` handed the exception to `crash_actor`, and an
  unsupervised crash is silent, so the handler stopped at the send with the
  process still exiting 0.

A send to a different actor worked because its pid came from a real binding.

`test/native/actor_self.march`, the golden that "pinned `self` as a value", was
green throughout: its helper received the closure and `let _ = p` cannot tell a
closure from a pid.

## What landed

- **Lowering** (`lib/tir/lower_actor.ml`): every handler body is wrapped in `let
  self = $actor`, which is the actor pointer and therefore the Pid at the ABI.
  `self` is registered in `_fn_param_types` for the body, the same shield the
  handler params use. A handler param named `self` shadows it, as in the
  typechecker.
- **Perceus** (`lib/tir/perceus_core.ml`): a binding that aliases the handler's
  `$actor` parameter is **borrowed**. The name is a new cross-pass contract,
  `Tir_names.actor_param`. `$actor` is `Lin`, so no RC op touches it, and the
  reference belongs to the scheduler that dispatched the handler.
- **`self()`** (`lower_expr.ml`, `eval.ml`): the typechecker accepts the call
  form as the same Pid (a zero-arg call of a value is the value), and the Phase
  4 actor tests use it. Inside a handler both backends now read it as the bound
  pid. Outside a handler it still reaches the `self` builtin (`march_self`).
- **Interpreter** (`lib/eval/eval.ml`, both handler-dispatch sites): `("self",
  VPid pid)` is bound after the params.

## The hazard the first cut introduced, and how it was caught

Bound as an ordinary owned `Pid` local, `self` was **dropped at every handler's
scope exit**, a net −1 on the actor record per handler. That is a premature free
of a live actor, the class `2026-08-14-actor-dispatch-rc-clobber-uaf.md` fixed
once already. The IR showed it before any test did: `note(self)` got an
`incrc_local`, the callee's drop, and then a second `decrc_local` of `self`.
Hence the borrowed classification.

## Identity (`self == spawn(...)`)

The todo recorded `self == p` as true compiled and false interpreted. `Pid`
implements no `Eq`, so well-typed code cannot ask. The observed divergence was
the builtin-vs-pid representation above. Interpreted `self` is now `VPid pid`,
the exact value `spawn` returns, and `test_compiler.ml` pins that equality from
OCaml. Compiled, `self` is the pointer `spawn` returned. The golden pins the
behavioural consequence: a send to `self` reaches the actor main spawned.

## Tests

- `test/native/actor_send_to_self.march` (+ `.expected`, `test/dune` rule),
  on a supervised child so its refcount exceeds 1:
  - a three-step self-driven state machine;
  - `self` and `self()` handed to a consuming callee;
  - an `ffi_test_actor_rc` check that handlers binding `self` leave the count
    unchanged.

  Verified red two ways:
  - with Perceus's borrowed rule removed: SIGBUS (exit 138) on 2 of 3 runs, and
    the refcount line flips;
  - with the lowering fix removed: `steps: 1`, no self-delivery.
- `test_compiler.ml` "self-send delivers (interp)": red without the `eval.ml`
  binding ("actor still alive" fails), green with it.
- `test_stdlib_suite.ml` "self inside handler" and "self-send from handler" use
  `self()`. They went red on the first cut, which is what surfaced the
  call-form arm above.
- `test/refine_audit/corpus.baseline`: +2 lines for the new fixture.

## Left open

Every `send` of a pid still live after the send leaks one reference, in `main`
as much as in a handler. Perceus dups a pid it believes `send` consumes, and
`march_send` never releases it. It is a leak, not a free, so the golden measures
the refcount only across handlers that do not send. Filed as
`specs/todos/2026-09-13-send-leaks-a-reference-to-a-live-pid.md`.
