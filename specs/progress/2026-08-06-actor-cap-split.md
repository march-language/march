# `Cap` split into IO authority and `ActorCap`

Landed 2026-08-06, out of the R8 audit
(`specs/2026-08-06-r8-runtime-hatch-audit.md`).

## The hole

A module granted nothing obtained the root capability:

```march
mod PidOfInt do
  needs IO
  pfn wants_root(r : Cap(IO)) : Int do 1 end
  fn main() do                            -- no parameter. No grant.
    match get_cap(pid_of_int(1)) do
      Some(c) -> println(int_to_string(wants_root(c)))
      None    -> println("none")
    end
  end
end
```

`--check` exit 0. This defeated R2, whose entire content is that the root
capability is *granted to `main`, not taken*.

## The cause was a conflation, not a missing check

`Cap` named two unrelated things that therefore unified:

| | IO capability | process capability |
|---|---|---|
| runtime value | `VUnit` — fully erased | `VCap(pid, epoch)` — epoch-validated |
| obtained from | `main`'s grant, then `cap_narrow` | `get_cap(pid)` |
| consumed by | nothing; compile-time only | `send_checked`, `revoke_cap`, `is_cap_valid` |
| governed by | `needs`, the lattice, R2/R3/R4 | actor liveness + a revocation table |

`get_cap : Pid(a) -> Option(Cap(a))`, so wherever `a` was free it bound to
`IO`.

## The fix

Process capabilities are `ActorCap(a)`. `get_cap`, `send_checked`,
`revoke_cap` and `is_cap_valid` move to it; `Cap`, the lattice, `needs`,
`cap_narrow` and R2/R3/R4 are untouched.

**Splitting rather than sweeping was deliberate.** A recorded-site sweep over
`get_cap` (the shape used for `mint_cap`, `cap_narrow` and the JSON builtins)
would have patched this one symptom and left the conflation to produce the
next one for any future builtin returning `Cap(a)`.

Two things fell out:

- **R3 extended to `ActorCap`.** Forging a `VCap(pid, epoch)` from JSON
  fabricates a send-capable reference to an arbitrary actor at an arbitrary
  epoch — the same class of hole as forging `Cap(IO)`, and outside the IO
  lattice entirely. `cap_in_solved_ty` now matches both constructors and
  returns the fully rendered type rather than a bare path, since two
  constructors can appear.
- **`needs` correctly stops seeing process capabilities.** A quiet bug fix: a
  process capability is not IO authority and never should have required a
  declaration. Now true by construction rather than by the accident of
  `caps_in_ty` not extracting a non-nullary argument.

Migration was two `.march` files (comments only — neither annotated the type),
zero stdlib, and one `ret_ty` in `lib/tir/llvm_builtins.ml`. Representation is
not keyed on the type name, so codegen needed nothing else.

## The correction, and why it is worth recording

**The first version of this finding named the wrong route, twice.** I reported
`get_cap(self())` and `get_cap(spawn(W))` as the vectors. Both are wrong:

- `spawn` returns `Pid[state]`, which **pins** `a` to the actor's state record.
  The ordinary actor path was always safe — it fails with
  ``expected `IO` but got `{ n : Int }` ``.
- `self()` is not a `Pid`; it returns `Int`, so that probe never typechecked
  for a reason unrelated to capabilities.

The cause was measuring `--check`'s exit code **through a pipe**:

```bash
$M --check f.march 2>&1 | head -6; echo "EXIT=$?"     # reports head's status
```

Every probe in the first pass read as exit 0. The audit's headline finding,
its filed todo and its commit message all asserted a bypass whose reproducer
did not work. It survived re-measurement only because a third route genuinely
exists — `pid_of_int : Int -> Pid(a)`, whose `a` is free, and which is
documented as unsafe precisely because it manufactures a `Pid` from an integer.

Two lessons, the second more useful than the first:

1. Never read an exit code through a pipe. This is already written down; it
   still happened, in a context where every probe was a one-liner and the
   pipe looked like formatting.
2. **A builtin with a free type variable in a capability position is a
   forge.** This is now the third instance — `from_json`'s result (R3),
   `cap_narrow`'s unpinned argument (R4a), `get_cap`'s `a` here. A fourth will
   look the same, and the cheap audit is to enumerate builtins whose result
   type contains a type variable the argument does not determine.

## Tests

`reject/t158_get_cap_is_not_io_authority` — the `pid_of_int` route, pinned at
the corrected vector rather than the one first reported.

`accept/t150_actor_cap_flow` — `get_cap` → `revoke_cap` → `is_cap_valid`,
declaring **no** `needs`. The feature is a real object-capability mechanism
with runtime machinery behind it; the fix was to stop it sharing a type with
IO authority, not to remove it.

Corpus 267 → **269**. compiler 786, eval 256, stdlib 833, doc-lint pass.
