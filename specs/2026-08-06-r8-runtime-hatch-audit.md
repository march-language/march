# R8 audit: the runtime escape hatches

Answers the R8 table in `specs/2026-08-04-provable-sandbox-design.md`, which
asked for these "with tests rather than reasoning". Every row below was probed
against the compiler at `40191c2a` (R4a). Findings are marked **measured**,
and the probes are reproducible from the snippets.

Three gaps were closed in the changes that produced this document; one
(hot-reload audit logging) is an existing todo this audit re-prioritises.

One finding in the first pass was **wrong and is corrected in place** (§2): I
measured `--check` exit codes through a pipe, which reports the pipe's status
rather than the compiler's, and initially named two routes that do not work.

---

## Summary

| hatch | R8's expectation | what is actually true |
|---|---|---|
| **Actors / messages** | "can a `Cap` travel in a message?" | Declaration side is **covered** — Check 1 reads actor handler signatures |
| **`get_cap` / Pid** | not in the table | Yielded `Cap(IO)` via `pid_of_int`'s free type var. **Fixed here** by splitting `Cap`/`ActorCap` |
| **Dynamic dispatch** | "covered if rows are on method signatures" | Was **not** covered — interface signatures and impl bodies were invisible. **Fixed here** |
| **Hot code reload** | "scope the claim to non-HCR builds, or re-check at load" | Better than assumed: a `--grant-cap` gate and a signed manifest exist. The **audit log** does not record capabilities |
| **FFI (`extern`)** | exclude; `IO.Foreign` marks it | Confirmed as designed |
| **Console egress** | cannot be closed | Unchanged (R8a) |

---

## 1. Actors and messages — covered

**Measured.** A capability in an actor handler signature is a use, and Check 1
reads it (the "H9 gap fix"). Under a covering `needs IO` it typechecks; under
`needs IO.Console` alone it errors:

```
`Cap(IO.FileWrite)` used in module `ActCapDeclared` but `IO.FileWrite` is not declared in `needs`.
```

So the answer to R8's question is: **yes, a `Cap` can travel in a message, and
the declaration discipline follows it.** No typing rule needs adding.

(Note on the probe: the actor form is `state { … }` *then* `init { … }`.
Omitting `state` produces a parse error on `init`, which is a reserved word —
this cost a previous attempt an inconclusive result.)

---

## 2. `get_cap` yielded IO authority — the significant finding

**Measured, and it is not in the R8 table at all.**

```march
mod PidOfInt do
  needs IO
  pfn wants_root(r : Cap(IO)) : Int do 1 end
  fn main() do                            -- NOTE: no parameter. No grant.
    match get_cap(pid_of_int(1)) do
      Some(c) -> println(int_to_string(wants_root(c)))
      None    -> println("none")
    end
  end
end
```

`--check` exit 0 before the fix. A module granted nothing obtains `Cap(IO)`
from an integer literal.

**Correction — the first version of this section named the wrong route, and
the way it went wrong is worth recording.** I originally reported
`get_cap(self())` and `get_cap(spawn(W))` as the vectors. Both are wrong:

- `spawn` returns `Pid[state]`, which **pins** `a` to the actor's state record,
  so the ordinary actor path was already safe — it fails with
  ``expected `IO` but got `{ n : Int }` ``.
- `self()` is not a `Pid` at all; it returns `Int`, so that probe never
  typechecked for an unrelated reason.

I believed otherwise because I measured `--check`'s exit code **through a
pipe** (`$M --check f.march | head; echo $?` reports `head`'s status, not the
compiler's). Every probe in the first pass read as exit 0. The finding
survived re-measurement only because a third route exists.

**The real vector** is `pid_of_int : Int -> Pid(a)`, whose `a` is free — it
exists so a supervisor can rebuild a `Pid` from a state field, and is
documented as unsafe. Free `a` plus a constructor shared with IO capabilities
is what turns an integer into root authority.

**Mechanism.** `Cap` named two unrelated things that therefore unified:

| | IO capability | process capability |
|---|---|---|
| runtime value | `VUnit`, fully erased | `VCap(pid, epoch)`, epoch-validated |
| obtained from | `main`'s grant, narrowed | `get_cap(pid)` |
| consumed by | nothing — compile-time only | `send_checked`, `revoke_cap`, `is_cap_valid` |
| governed by | `needs`, the lattice, R2/R3/R4 | actor liveness + revocation table |

**Not caused by R4a** — the probe never calls `cap_narrow`, and a pre-R4a
control accepts the equivalent program.

**Fixed 2026-08-06** by splitting the constructor: process capabilities are now
`ActorCap(a)`. A sweep over `get_cap`'s sites would have patched one symptom
and left the conflation to produce the next one for any future builtin
returning `Cap(a)`. Witnesses: `reject/t158`, `accept/t150`.

R3's unforgeability check was extended to `ActorCap` in the same change:
forging a `VCap(pid, epoch)` from JSON fabricates a send-capable reference to
an arbitrary actor at an arbitrary epoch, which the IO lattice does not cover.

`needs` now correctly ignores `ActorCap` — a process capability is not IO
authority and never should have required a declaration.

---

## 3. Dynamic dispatch — was open, closed here

R8 guessed this would be "covered by the type system if rows are on method
signatures". It was not covered at all, and the reason is a mistake in the R3
work rather than anything about rows.

When Check 1's decl walk was made exhaustive on 2026-08-05, `DInterface` and
`DImpl` were **enumerated under "names no capability position"**. That was an
explicit decision and it was wrong. Three positions were dark:

- an interface method **signature**,
- an impl method **signature**,
- an annotation inside an impl method **body**.

**Measured, and this contrast is the sharpest statement of it:** the identical
`file_read` call produces a warning in a plain `fn` body and **nothing at all**
in an `impl` method body. Impl bodies were darker than ordinary functions —
backwards, since an `impl` is exactly where a dependency's capability use is
least visible to a reader.

Fixed by adding `DInterface` and `DImpl` arms that walk method signatures,
default-method bodies, impl method signatures and bodies, and `impl_ty` itself
(`impl Grantor(Cap(IO))` is expressible). Witnesses: `reject/t156`,
`reject/t157`, `accept/t149`.

**The enumeration is why this was findable.** The arm names the constructors it
skips, so a wrong call is reviewable in the source rather than hidden behind
`| _ -> []`. That is the whole argument for banning the wildcard, and this is
the argument being cashed — a wildcard would have produced the identical
behaviour with nothing to read.

---

## 4. Hot code reload — better than R8 assumed, with one real gap

R8 said the claim "must be scoped to non-HCR builds, or reloaded code must be
re-checked against the original ceiling at load".

**Measured by reading the implementation:** there is more machinery than that
implies. `--hot-reload=<Prefix>` compiles boundary modules specially, deploys
carry a **signed `.hcr_manifest`**, and there is a client-side gate with
explicit `--grant-cap` flags for authorising a widening. So a reload is not an
unchecked authority injection.

**The gap is the audit trail, and it is already tracked.**
`write_audit_log` in `runtime/march_reload.c` writes one JSON line per
`ACTIVATE` with `ts/type/fn/impl_hash/signer/cas_hash/result` — **no capability
field**. So the log answers "who deployed what, when, and did it succeed" but
not "what capabilities did this deploy touch". A `--grant-cap`-authorised
widening is indistinguishable after the fact from an ordinary same-authority
redeploy, and there is no way to reconstruct a capability timeline from the log
alone — the granted set lives only in that deploy's manifest.

Already filed under
`specs/todos/2026-07-31-p2-runtime-hot-code-reloading.md`. This audit adds
nothing new; it confirms the item is the right one and raises its relevance,
because the sandbox claim depends on being able to answer "when did this system
last gain capability X".

**Disposition for the claim:** HCR does not need to be excluded outright, but
any published statement should say that reload-time capability changes are
authorised by signature and flag, and are **not** reconstructible from the
audit log until that field lands.

---

## 5. FFI — as designed

`extern` blocks declare `Cap(X)` and Check 5 treats that as a use; `IO.Foreign`
marks the coverage limitation and `forge cap inspect` reports it. No change.
The exclusion in R8 stands and is honest.

---

## 6. Console egress — unchanged

R8a is unaffected by anything here. Every profile grants stdout by
construction, because the sandbox needs it to report its own denials. No stage
closes it.

---

## What this changes about the claim

Nothing in §5 needs weakening. Actors, dynamic dispatch, FFI and HCR are all
either covered or honestly excluded, and the one hole that did contradict §5 —
`get_cap` yielding IO authority — is closed rather than outstanding.

The `pid_of_int` route is worth remembering as a shape rather than a bug:
**a builtin with a free type variable in a capability position is a forge.**
That is now the third instance (`from_json`'s result in R3, `cap_narrow`'s
unpinned argument in R4a, `get_cap`'s `a` here). A fourth will look the same.
