# Self-recursive local closures: the back-edge is ours now, not LLVM's

Closes `specs/todos/2026-08-21-selfrec-closure-float-tail-call.md` (this file is
that item, moved). Filed 2026-08-21 as the residual PR #321 deliberately did not
take; fixed 2026-08-22.

## The shape

```march
let f = fn (x : Float) -> x +. 3.0
fn go(i : Int, acc : Float) : Float do
  if i <= 0 do acc else go(i - 1, f(acc)) end
end
```

Defun lifts `go` to `go$apply$N($clo, i, acc)` whose body opens with
`let go = $clo` — the lambda's own name rebound to the closure it was invoked
through — and compiles the recursive call as `ECallPtr(AVar go, args)`.

Two consequences, and they are the same defect seen from two sides:

1. **The stack safety was LLVM's, not ours.** `Llvm_tco` only recognises
   `EApp`-to-self, so this recursion got no back-edge from the compiler at all.
   It survived deep inputs only because LLVM's tail-call elimination turned the
   emitted self-call into a loop — an `-O2` optimization that dies the moment
   any instruction is emitted between the call and the return. PR #321 measured
   exactly that: a SIGBUS at 20,000 iterations on a shape that ran 1,000,000
   deep, which is why its call-site releases now exempt self-calls.
2. **The exempted edge leaked.** Crossing the erased ABI boxed the Float
   accumulator every iteration and dropped the box: 1 per iteration, unbounded.

## The fix — three lines of analysis, in `known_call.ml`

`Known_call` already rewrites `ECallPtr` → `EApp` for any variable it can prove
is bound to a specific closure allocation. It tracked only `ELet(v, EAlloc(...))`
bindings, and the self-binding is not one — but its apply function is known with
certainty, because it is *the one being traversed*. So the traversal now carries
the current function's `($clo parameter name, own name)` and treats
`let v = $clo` inside an apply fn as binding `v` to that apply fn.

Everything after that is existing machinery: the self-call becomes an ordinary
`EApp`-to-self, `Llvm_tco`'s self-TCO gives it a real back-edge that writes the
**native `double` parameter slot** and branches to the loop header, so nothing
is boxed and no frame is pushed. PR #321's self-call exemptions stay exactly as
they are — with a back-edge there is no call for them to guard.

Emitted IR for the back-edge, `go$apply$3621` (`--opt 2`):

```llvm
  %acc.addr = alloca double            ; native slot, unboxed in the prologue
  ...
  store double %ld88, ptr %acc.addr    ; back-edge writes the raw double
  call void @llvm.stackrestore(ptr %sp.save59)
  br label %tco_loop3
```

## Measurement (Darwin arm64, 1,000,000-deep `selfrec_leg`)

| build | `live_allocs()` delta | `--opt 2` | `--opt 0` |
|---|---|---|---|
| 8897bb1a | **1,000,001** | exit 0 | **exit 138 (SIGBUS)** |
| with this fix | **1** | exit 0 | exit 0 |

The `--opt 0` column is the load-bearing one: it is the direct evidence that the
stack property moved from LLVM's optimizer into the compiler. Also run at
10,000,000 deep, both `--opt` levels: correct value, delta 1.

## Guard

`test/native/native_float_box_abi_leak_probe.march`'s `selfrec_leg` moved
INSIDE the `live_allocs` measurement window. It was deliberately outside it
before, as a stack canary whose leak was expected. Now one leg asserts both
properties at once, which is the point: each is cheap to "fix" by breaking the
other, so a future change cannot trade them. A regression that restores the
erased edge shows up as ~n leaked objects; a regression that puts an
instruction back on the self-call path shows up as a SIGBUS, because 1,000,000
real frames do not fit on a green thread's stack. The dune rule's failure
message names both readings of the delta.

## Scope

Only the SELF-binding is resolved. Mutual recursion through closures is still
an unresolved `ECallPtr` with the same fragility (PR #321's exemption does not
cover it either, so it does not leak — it is at risk of losing TCE instead).
Left open deliberately: resolving it needs a fixpoint over the group rather than
a single "the function being traversed" answer.

The rewrite fires pre-Perceus only. After Perceus the binding has become
`let go = inc_rc $clo; $clo`, which the `EAtom` pattern does not match — so the
Opt loop's later `Known_call.run` calls leave it alone, and nothing depends on
them for this.

## Verification

* `native_float_box_abi_leak_probe` 1,000,001 → 1 with the leg inside the
  window; whole probe delta 1.
* TIR snapshots: no diff (the corpus has no local recursive closure), so this
  changed no IR shape the snapshot corpus covers — worth knowing, since the
  rewrite is a TIR-level one and a wider corpus would have shown it.
* `scripts/run-tests.sh` all five suites green; `dune build @runtest` green;
  the 71-program no-ASAN corpus sweep clean (the real ASAN gate is a SKIP on
  this Mac — see the sibling fold progress note for what that does and does not
  cover).
* Benchmarks, compiled `--opt 2`, interleaved before/after under load ~16:
  `list_ops` 0.107s → 0.100s, `tree_transform` 0.680s → 0.680s. Neither
  benchmark contains a self-recursive local closure, so this is a no-regression
  check, not a measurement of the change.
