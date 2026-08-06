# R8 audit: the runtime escape hatches

Answers the R8 table in `specs/2026-08-04-provable-sandbox-design.md`, which
asked for these "with tests rather than reasoning". Every row below was probed
against the compiler at `40191c2a` (R4a). Findings are marked **measured**,
and the probes are reproducible from the snippets.

Two gaps were closed in the same change that produced this document; two are
findings that need a decision rather than a patch.

---

## Summary

| hatch | R8's expectation | what is actually true |
|---|---|---|
| **Actors / messages** | "can a `Cap` travel in a message?" | Declaration side is **covered** — Check 1 reads actor handler signatures |
| **`get_cap` / Pid** | not in the table | **BYPASSES R2.** Two lines, no grant, yields `Cap(IO)` |
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

## 2. `get_cap` bypasses R2 — the significant finding

**Measured, and it is not in the R8 table at all.**

```march
mod PidRoot do
  needs IO
  pfn wants_root(r : Cap(IO)) : Int do 1 end
  fn main() do                          -- NOTE: no parameter. No grant.
    match get_cap(self()) do
      Some(c) -> println(int_to_string(wants_root(c)))
      None    -> println("none")
    end
  end
end
```

`--check` exit 0. No actor need be declared; `self()` suffices.

R2's entire content is that the root capability is *granted to `main`, not
taken*. Here it is taken, from a process id the module already has.

**Mechanism.** `get_cap : Pid(a) -> Option(Cap(a))` — `a` is unconstrained, so
it unifies with `IO` at the use site and `Cap(a)` becomes `Cap(IO)`. This is
the same shape as `from_json`'s free result variable that R3 closed: a
capability-producing builtin whose result type nothing pins.

**Not caused by R4a.** The probe never calls `cap_narrow`, and a pre-R4a
control accepted the equivalent program.

**Why this is worse than it looks.** It defeats R2 without needing `root_cap`,
so the R2 work bought less than its progress note claims. Any statement of the
form "a capability can only be received" is currently false, and §5 of the
sandbox design says exactly that.

**Not fixed here** — it needs a decision, not a patch. `get_cap`'s legitimate
purpose is process-capability retrieval (`Cap(state)`), and the options differ in
how much they break: constrain `a` to non-IO capabilities; gate `get_cap`
behind the same sweep machinery as `mint_cap`; or remove it. Filed as
`specs/todos/2026-08-06-get-cap-bypasses-the-root-grant.md`.

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

Nothing in §5 needs weakening for actors, dynamic dispatch, FFI or HCR.

**One sentence does need weakening, and it is the one R2 earned.** With
`get_cap` reachable, "a capability can only be received" is false: a module
with no grant can obtain `Cap(IO)` in two lines. Until that is decided, the
honest form is the pre-R2 one — a capability cannot be fabricated *from data* —
plus a note that process-capability retrieval is an open hole.

I have not edited §5 here, because the right wording depends on which fix
`get_cap` gets.
