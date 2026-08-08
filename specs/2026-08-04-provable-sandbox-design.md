# Toward a provable sandbox

Status: **mostly design. R2, R3 and R4 are built (2026-08-05); R1 and R5–R9
are not.** This page exists to say precisely what the claim "provably sandboxed by
the type system" would require, what March already has, and which of it is
worth building.

Stage 1 of §3 — "capabilities cannot be fabricated, only received and
narrowed" — is earned, and with R2 it is earned in the strong sense: there is
no ambient capability to pick up either. Nothing above it is. In particular
**built-in IO is still ambient** (§1, R1), which is the load-bearing gap and is
untouched by what shipped — a module still performs IO holding nothing.

Companion to `specs/2026-08-03-forge-cap-audit-design.md` (artifact channel),
`specs/2026-08-04-path-scoped-capabilities-design.md`,
`specs/progress/2026-08-04-cap-ceiling-strict.md` (the ceiling), and
`specs/2026-08-05-cap-unforgeability-design.md` + `specs/progress/2026-08-05-cap-unforgeability.md`
(R3/R4 as built).

---

## 1. Where we actually are

`--cap-strict` gives a **mechanically checked ceiling**: every module's
emitted code stays within that module's own `needs`, verified against the TIR
the compiler is about to lower, and re-checkable from the artifact via
`forge cap inspect --strict`. **Since 2026-08-08 the ceiling is the DEFAULT**
(`--no-cap-strict` opts out) — see
`specs/progress/2026-08-08-cap-strict-default.md` for the two false-positive
fixes that unblocked it and the repo-wide migration.

That is a *whole-program static analysis*. It is not a type-system theorem,
and the difference is not pedantic:

| | ceiling check (today) | type-system proof |
|---|---|---|
| what it examines | the whole program, after monomorphization | each definition, compositionally |
| when it fails | at build time, on the complete program | at definition time, locally |
| a library alone | cannot be checked — no program to analyse | checkable in isolation |
| new caller | must re-run the whole analysis | cannot invalidate what typechecked |
| basis | an algorithm we believe is right | a theorem, if proved |

The practical consequence: today a library author cannot know their library is
capability-clean. Only the final application build finds out. A type system
would make it a property of the library's *interface*.

### What March already has

More than one might expect. `Check 6` in `lib/typecheck/typecheck.ml` already
enforces genuine capability discipline for **user-declared proof caps**:

> A function cannot return a proof cap unless it received it as a parameter,
> except for public functions of the declaring module — those are the minting
> surface.

That is no-authority-from-nothing, in the type system, today. There is also a
capability lattice with subsumption (`lib/caps/cap_lattice.ml`), attenuation
(`cap_narrow`), path scoping, and an `lib/effects/` module.

### The one thing that is missing

**Built-in IO is ambient.** Any module can write `file_read(p)` with no token
in scope. `needs` is a declaration reconciled against a separate analysis —
which is exactly why `--cap-strict` could be implemented as a pass over TIR
rather than as a typing rule.

So the gap in a sentence:

> March has capability-safe machinery and does not point it at IO.

Everything below is downstream of closing that.

---

## 2. What the claim would require

### R1. No ambient authority (load-bearing)

`file_read` must be uncallable without evidence of `Cap(IO.FileRead)`. Two
formulations:

**R1a — explicit tokens.** `file_read : Cap(IO.FileRead) -> String -> Result(...)`.
Honest and simple. It also means every stdlib function touching IO grows a
parameter and every caller threads it. This is where capability languages
die: `List.map` over an effectful function needs the token, so `map` needs it,
so everything needs it.

**R1b — effect rows, inferred.** `read_config : () -> Config ! {IO.FileRead}`,
where the row is inferred and written only at boundaries. `main` is the sole
place a row is discharged against a granted capability set.

**Recommendation: R1b.** R1a is unadoptable for a language with a 112-module
stdlib.

**There is no substrate for this today, and the directory name is misleading.**
`lib/effects/effects.ml` is 22 lines: a call-site hook that delegates to
`Typecheck.check_module` so capability enforcement runs on both the eval and
compile paths. It contains no effect representation, no rows, and no
inference. R1b starts from zero regardless of where it eventually lives.

The migration cost is real and should not be understated: this is a breaking
change to the type of every stdlib function that touches IO. It is
plausibly a major-version event.

### R2. A single root, minted at the boundary — **SHIPPED 2026-08-05**

`main : Cap(IO) -> ()`, runtime as sole minter. Today's minting surface —
*any* declaring module's public functions — is right for user-defined proof
caps and wrong for IO: it would let any module mint what it needs. For IO the
minting surface must be exactly one place, and that place must not be
expressible in March.

**Built 2026-08-05** — `specs/progress/2026-08-05-cap-root-granted-not-taken.md`.
`root_cap` can no longer be referenced from ordinary code; the root is granted
to `main`'s parameter. Two scoped exemptions remain and are documented there:
`test`/`describe`/`setup` bodies and the REPL, neither of which has an entry
point to be granted from, and neither of which can reach production code.

It turned out much smaller than this section implies, because **the boundary
already existed**: `main` could already take a `Cap(IO)`, `check_main_signature`
already enforced the shape, and the runtime already passed the erased root.
There was no minting machinery to build — capabilities are erased, so the whole
gate is compile-time. R2 reduced to making one name unavailable.

What follows was the finding that prompted it.

**Measured 2026-08-05, and it is worse than "the minting surface is too
wide": there is no minting step to gate.** `root_cap` is an ordinary global of
type `Cap(IO)`, in scope in every module. A module declaring **no `needs` at
all** can write `let x = root_cap` and hold the root capability; the only
diagnostic such a program gets is about its `println`. Narrowing from there to
any descendant is then free and legitimate, since `cap_narrow` demands exactly
the parent it now has.

Two consequences worth being explicit about:

- **This bounds what R3 earned.** Stage 1's claim has to be stated as "a
  capability cannot be fabricated from data", not "a capability can only be
  received" — see §5. Nothing was received here.
- **R2 was the cheapest item that materially strengthened the claim**, and
  unlike R1b it was not a language-wide signature change.

R2 shipped; R1 did not. So the caveat stands and is now the live one: **R2
moved the root but left `file_read(p)` working regardless.** A program can
still do everything it could before without ever holding a capability. R2 and
R1 may not be separable in practice even though this page lists them apart —
that is the real sequencing question for whoever takes R1.

### R3. Unforgeability, checked — **SHIPPED 2026-08-05**

A capability must not be constructible except by receipt. Concretely, `Cap(X)`
must be excluded from:

- any cast or reinterpretation (`Bytes` → `Cap`),
- `derive(FromJson)` / any deserialization producing one,
- default-value construction and zero-initialization,
- record/variant field positions reachable by a `from_json`-shaped function.

This is a real check, not a proof obligation. It is cheap and should be built
*before* the proof work, because it is where a practical break would come from.

**Built 2026-08-05** — `specs/2026-08-05-cap-unforgeability-design.md` and
`specs/progress/2026-08-05-cap-unforgeability.md`. Three corrections to what
this section says above, each found by implementing it:

- **It was two vectors, not four.** March has no `unsafe_cast`/`transmute`/
  coercion builtin and no default-value construction, so the first and third
  bullets had nothing to close. The live hole was
  `to_json`/`from_json`/`from_json_events` — the only three builtins typed
  `poly2 (fun a b -> TArrow (a, b))`, i.e. fully unconstrained — plus
  `derive Json` over a cap-bearing type.
- **"A walk over type declarations and derive lists" is right for the derive
  half and wrong for the other.** The call-site half cannot be a walk at all:
  `from_json`'s result type is a bare unification variable at the application
  site, pinned only by later unification, so the check must be a *deferred
  end-of-module sweep* plus a value restriction. Implemented as a walk it
  compiles, runs, reports nothing, and passes every test that annotates the
  type inline.
- **There was a second hole this section does not mention.** `needs` was
  reconciled against function SIGNATURES only, so a capability named in a type
  declaration (`type Handle = { tok : Cap(IO.FileWrite) }`) or a `let`
  annotation escaped it entirely. Unlike the
  deserialization hole it needed no unimplemented feature to reach — `root_cap`
  is ambient (cf. R2), so a console-only module could take the root, narrow it,
  and bind the result without ever putting a capability in a signature.

Stage 1 of §3 is therefore earned. R4 was pinned alongside it.

### R4. Monotone attenuation — already sound, **PINNED 2026-08-05**

Measured 2026-08-05, both directions:

| | result |
|---|---|
| `Cap(IO.Console)` → `Cap(IO.FileWrite)` (widen) | **rejected**: ``expected `IO` but got `IO.Console` `` |
| `Cap(IO)` → `Cap(IO.FileWrite)` (narrow) | accepted, rc=0 |

So attenuation is monotone today. This item is "pin existing behaviour", not
"fix a hole" — but it is still worth doing, because the subsumption direction
was written backwards twice during the sandbox work and shipped once.

Correcting where the enforcement lives, since it is not where you would guess:

- **Compile time is the whole story.** `cap_narrow` is typed such that
  narrowing to `Cap(IO.FileWrite)` demands the *parent* `Cap(IO)` at the
  argument, which is what produces the error above. The lattice is enforced
  structurally through unification, not by a separate lattice call.
- **The runtime is deliberate erasure, not a gap.** `march_cap_narrow` in
  `runtime/march_runtime.c` is literally `return cap;`, and `eval.ml` documents
  why: capabilities are opaque unit sentinels and `mint_cap` is "a no-op alias
  of cap_narrow" at runtime because the gating is a compile-time check. Do not
  "fix" the identity function.
- **The gating that does exist** is `check_mint_cap_sites` in
  `lib/typecheck/typecheck.ml`, plus `cap_narrow_factory_fns` and
  `mint_cap_sites` in the env. It enforces that `mint_cap` appears only in a
  public function of the proof cap's declaring module, and that `mint_cap` is
  refused for IO caps ("that's `cap_narrow`'s job").

The test was therefore an accept/reject pair over `cap_narrow` in both lattice
directions — not a property test over a runtime function that does nothing.
Shipped 2026-08-05 in `test/test_cap_unforgeable.ml` (alongside R3) rather
than in `test_cap_scope.ml`, because that file tests the pure `Cap_scope`
functions and these need real programs typechecked. No production change was
required, exactly as this section predicted.

### R4a. Attenuation does not CHAIN — **FIXED 2026-08-06**

Measured 2026-08-05, and it is a gap in the ocap story rather than in the
lattice. `cap_narrow` is typed `Cap(IO) -> Cap(a)`: its argument is *literally
the root*. So a holder of anything narrower cannot attenuate further —

```march
pfn attenuate(fs : Cap(IO.FileSystem)) : Cap(IO.FileRead) do
  cap_narrow(fs)                    -- expected `IO` but got `IO.FileSystem`
end
```

R4 says attenuation is monotone, and it is. What it does not say is that
attenuation is only available **to whoever holds the root**. Delegation with
attenuation at each hop — hand a subsystem `Cap(IO.FileSystem)`, let it hand a
helper `Cap(IO.FileRead)` — is the core object-capability discipline and is
*not expressible in March today*. Every narrowing must be performed up at
`main` and the already-narrowed values threaded down.

The same applies to `mint_cap : Cap(IO) -> Cap(a)`: minting even a *proof* cap
consumes the root, so a module that mints must be handed root authority.

This mattered for sequencing: R2 makes `main` the sole source, and R1 would
make every IO call need a token — the two together make "least privilege
threaded down" the normal way to write March, and that idiom was exactly the
one this typing prevented.

**Fixed 2026-08-06** — `specs/progress/2026-08-06-cap-narrow-chains.md`.
`cap_narrow` is now typed `Cap(a) -> Cap(b)` with subsumption enforced by
`check_cap_narrow_sites`, a deferred sweep over recorded application sites.

The tradeoff is worth stating because it is a real weakening, accepted
deliberately. Monotonicity used to be enforced **structurally through
unification** — the argument type literally was `Cap(IO)`, so a widen failed
to unify and there was nothing to bypass. It now lives in a post-pass, which
is weaker *in kind*: an application site the sweep fails to record is a
silently permitted widen. HM unification cannot express a subtyping relation,
so there was no way to have both chaining and structural enforcement; the
mitigation is that `reject/t153`–`t155` are the load-bearing witnesses rather
than decorative ones, and that every site is recorded at a single place.

Two scoping decisions in the sweep:

- **Proof caps are left alone** on either side. They are not in the IO lattice
  and have their own discipline (`mint_cap`'s gate, Check 6).
  `cap_narrow(root) : Cap(Db.Migrated)` typechecks today and is governed on the
  way out; making subsumption reject it here would have changed proof-cap
  semantics under cover of an IO change.
- **An unpinned side is silent.** A `cap_narrow` whose result is never pinned
  to a concrete capability is a result never *used* as one, so no authority is
  exercised. (Failing closed was proposed and was wrong — it would reject
  ordinary code that narrows into a polymorphic position.)

One knock-on, recorded because it looks like a regression and is not:
`reject/t143` (R3's deferred-zonk witness) now reports `Cap(_)` rather than
`Cap(IO)`. `cap_narrow` no longer pins its argument to the root, so nothing in
that program determines *which* capability is being forged — only that one is.
R3 still rejects it because `cap_in_solved_ty` reports an unpinned capability
argument as `_` rather than skipping it. Had it skipped, R4a would have
silently reopened R3's hole and the corpus would have gone green doing it.

### R5. Effect polymorphism that survives higher-order code

`map : (a -> b ! e) -> List(a) -> List(b) ! e`. Without row polymorphism you
either cannot write HOFs over effectful functions or you have a hole exactly
where one was already found: `apply1(file_read, p)` handed the capability out
as a value and the TIR analysis lost it until the atom scan was added.

This is the hardest *type-system* work in the list, and the main reason R1b is
a research-adjacent project rather than an afternoon.

### R6. A soundness theorem

A core calculus (λ-calculus + rows + a capability lattice + an IO-labelled
operational semantics), and:

> **Theorem (capability safety).** If `⊢ p : τ ! ε` and `p` steps to a
> configuration performing IO action `a`, then `label(a) ∈ ε`, and every
> capability in `ε` is subsumed by one reachable from `main`'s argument.

Standard preservation + progress, with the effect row as the invariant.
March has no formal semantics today, so this starts from zero. Written is a
real milestone; mechanized (Rocq/Lean) is what "provably" normally means to
the people who ask for it.

### R7. Evidence the implementation matches the calculus

The theorem is about a paper language; the checker is OCaml. Bridging options,
cheapest first:

1. a conformance corpus pinning every typing rule (March has the machinery —
   `specs/lang/types/{accept,reject}/`, driven by the CI-only `@types-check`
   alias, which asserts diagnostic *text* and not merely accept/reject);
2. a differential oracle against a reference implementation of the calculus;
3. extraction of the checker from the mechanized development.

(1) is achievable now and worth doing regardless. (3) is the only one that
actually closes the gap.

### R8. The runtime escape hatches — **AUDITED 2026-08-06**

Answered with probes rather than reasoning; see
`specs/2026-08-06-r8-runtime-hatch-audit.md`. Results against the table below:

- **Actors / messages** — a `Cap` CAN travel in a message, and the declaration
  discipline follows it (Check 1 reads actor handler signatures). No typing
  rule needed.
- **Dynamic dispatch** — was NOT covered, for a reason unrelated to rows:
  interface method signatures and impl method bodies were invisible to Check 1.
  Fixed 2026-08-06.
- **Hot code reload** — better than this row assumes. A signed `.hcr_manifest`
  and an explicit `--grant-cap` gate exist, so a reload is not unchecked
  authority injection. The real gap is the audit log, which records no
  capability field, so a granted widening is not reconstructible after the
  fact.
- **FFI** — confirmed as designed.
- **A hatch this table does not list, now closed:** `get_cap` returned
  `Option(Cap(a))`, sharing the `Cap` constructor with IO capabilities, so a
  FREE `a` unified with `IO` and handed root authority to a module granted
  nothing. The reachable route is `pid_of_int : Int -> Pid(a)` (`spawn` pins
  `a` to the actor's state type, so the ordinary actor path was already safe).
  Fixed by splitting the constructor — process capabilities are `ActorCap(a)`.
  §5 stands unchanged as a result.



Each is invisible to any source-level theorem, and each must be either closed
or explicitly excluded from the claim:

| hatch | why it breaks the claim | disposition |
|---|---|---|
| **FFI** (`extern`) | C code performs IO with no token | exclude; `IO.Foreign` already marks it and `forge cap inspect` reports it as a coverage limitation |
| **Hot code reload** | injects authority *after* the proof was discharged | the claim must be scoped to non-HCR builds, or reloaded code must be re-checked against the original ceiling at load |
| **Actors / messages** | can a `Cap` travel in a message? | if yes, message types join the effect discipline; if no, that is a typing rule to add and test |
| **`march_env`, raises** | env-routed error paths cross the boundary | audit |
| **Dynamic dispatch** | interface method resolved at runtime | covered by the type system if rows are on method signatures |
| **Console egress** | stdout is a live exfiltration channel that every profile grants | cannot be closed — see R8a |

### R8a. Console egress is the hatch that never closes

Every other row above can, in principle, be shut. This one cannot, and any
claim containing the word "sandboxed" has to say so.

**It is granted unconditionally, by construction.** `Cap_sandbox.enforceability`
classifies `IO.Console` as `Advisory "stdout/stderr are required to report
violations"`, and `sbpl_baseline` allows `file-write-data` to `/dev/stdout`,
`/dev/stderr` and `/dev/tty` *before* any capability-derived rule is added.
`--cap-sandbox`'s self-imposed profile does the same. The sandbox needs stdout
to report its own denials, so a profile that denied console could not tell you
it had denied anything.

**It needs no other capability.** Code with no filesystem and no network access
can still exfiltrate anything it can read, because stdout is not a void — it
lands in CI logs (public, on public repositories), in log aggregators that
index and retain, and in whatever pipeline the operator built. The attacker
borrows the operator's plumbing rather than opening a channel of their own.

**It is the last channel open in exactly the scenario capabilities are for.**
Run untrusted code with everything else denied and stdout is what remains,
because a program that cannot say anything is useless. That makes it the
highest-value target precisely in the configuration meant to be safest.

Secondary consequences of the same grant: log injection (forged lines,
newline-smuggled timestamps) to hide activity or poison downstream alerting;
ANSI sequences that overwrite already-printed output so what a terminal showed
is not what was emitted; and corruption of programs whose stdout *is* their
interface, where a dependency printing does not merely add noise but alters
what the consumer parses.

**What can be done instead.** Nothing at runtime — so the whole defense is
static, which inverts the usual reasoning. Because console can never be gated,
the declare-and-diff channel is not a weaker substitute for enforcement here;
it is the only control that exists. Concretely:

- per-module attribution names *which* module prints, and an unexpected
  `println` in a JSON parser or a date formatter is exactly the shape of a
  data-exfil backdoor, where the same call in a logging library is expected;
- `--cap-strict` fails a build where a dependency prints without declaring it;
- `forge audit` diffs the appearance of `IO.Console` on a dependency bump.

This is why `IO.Console` must stay a real capability in the ceiling rather than
be waved through as ceremony. The temptation to exempt it is strong — it is the
most common builtin in the language and the warning is noisy — and it is
exactly backwards: unenforceable is an argument for caring *more* about the
static channel, not less.

### R9. The compiler

**This is the requirement people skip, and it is the one this codebase has the
most evidence for.**

A type-system proof is a theorem about *source*, discharged by ~40k lines of
OCaml plus LLVM. `specs/progress/` documents a long list of compiled-only
miscompiles: `let x = x + 5` producing wrong values compiled but correct
interpreted; constructor tag collisions across modules; RC use-after-frees;
a mono/defunctionalization bug that hijacked `show` dispatch. None of these
would be caught by a source-level soundness theorem, and a capability check is
not structurally safer than any of them.

So the unqualified claim requires **verified compilation** — CompCert/CakeML
territory. No language in March's class has it, and March will not.

**This is the strongest argument for keeping the artifact channel.** A proof
assumes the compiler is correct; reading capabilities off the linked binary
assumes nothing about it. For supply chain — where the threat model includes
the build — the artifact channel is the load-bearing one, and the proof is the
complement. Two independent channels that must agree is a better practical
guarantee than one proof that trusts the toolchain.

### R10. Scope statement

"Sandboxed" conventionally excludes covert channels — timing, memory pressure,
scheduling, cache. Any published claim must say so explicitly rather than
leave it implied.

Console egress (R8a) is a separate and more serious exclusion, and must not be
folded into that sentence. A covert channel is low-bandwidth and requires
effort to exploit; stdout is an *overt*, high-bandwidth, universally granted
channel that carries whatever the program chooses to print. A reader who sees
"excludes covert channels" will not infer "and also anything the program
prints reaches your CI logs." Say it separately.

---

## 3. Claims earnable in order

Each row is honestly defensible once the requirements are met, and each is a
shippable increment.

| stage | requirements | claim |
|---|---|---|
| **0** | **shipped** | "`needs` is a ceiling on every module, including dependencies that never opted in, verified against emitted code and re-checkable from the artifact" |
| **1 — unforgeable** | R3, R4 — **shipped 2026-08-05** | "capabilities cannot be fabricated, only received and narrowed" |
| **2 — no ambient IO** | R1b, R2 | "a module can only perform IO with authority it was given" |
| **3 — compositional** | R5 | "…and that holds for higher-order and library code, checked per-definition rather than per-program" |
| **4 — proved** | R6, R7 | "provably capability-safe for the core language, modulo FFI, compiler correctness, and console egress" |
| **5 — unqualified** | R9 | not reachable |

Stage 1 was **independent of everything else** and cheap. It is the only
one that closes a practical attack (fabricate a `Cap` via `from_json`) rather
than strengthening a claim.

No stage closes console egress (R8a). Every row above should be read as
"...for data the program does not print", and stage 5 does not fix it either
— verified compilation makes the compiler trustworthy, not stdout private.

---

## 4. Recommended sequencing

**~~Now~~ DONE 2026-08-05 — R3, plus R4 as a regression pin.** R3 was the only
item on this page that closed a live hole. It cost days, not weeks, and no
language change, as estimated. R4 rode along and needed no fix — attenuation
was already monotone (measured — see R4), so it took an accept/reject pair
pinning both lattice directions.

Both were self-contained: neither depended on R1b, and neither is wasted if the
effect-row work never happens.

Two things the estimate got wrong, worth carrying into the next item:

- the scope was **half** what this page described (two of R3's four bullets had
  no vector in the language) but the *mechanism* was harder — a deferred sweep
  with a value restriction, not the walk this page assumed;
- auditing R3 turned up an unrelated second hole (signature-only `needs`
  coverage) that was cheaper to exploit than the one being closed. Expect the
  same when R8 is audited: **the finding is often adjacent to the thing you
  went looking at, not inside it.**

**Next — R8 audit.** Answer, with tests rather than reasoning: can a `Cap`
travel in an actor message? Does hot reload bypass the ceiling? These are
questions about the system as it exists, and the answers change what today's
claim may say. Cheap, and the results could invalidate stage-0 wording.

**Then — decide on R1b.** This is the fork, and it is a from-scratch build:
`lib/effects/` is a 22-line delegation shim, not a foundation. Effect rows
over IO are a major version and a stdlib-wide signature change. The honest
framing for that
decision is: it converts a *whole-program build gate* into a *per-definition
property*, which is what lets library authors ship a capability-clean library
without seeing the application. That is the real user-facing win — bigger than
the word "provably".

**Only then — R6/R7.** A proof over a calculus that does not match the
implemented language is an academic artifact, not an assurance. R1b must land
first, and the conformance corpus (R7.1) should be grown alongside it, not
retrofitted.

**Never — R9.** Say so plainly, and keep the artifact channel as the answer to
"why should I believe your compiler?"

---

## 5. What to say in the meantime

Defensible today:

> March is the only language where "what can this touch?" is written in the
> module, checked against the code the compiler actually emits, enforced as a
> hard ceiling on every dependency — including ones that never opted in — and
> readable back off the compiled binary.

Newly defensible as of 2026-08-05 (stage 1, R3/R4):

> A capability in March can only be received. It cannot be deserialized,
> derived, or cast into existence, and there is no ambient one to pick up —
> the root is granted to `main` and threaded from there.

R3 closed the fabrication-from-data route; R2 closed the ambient-root route.
With both shipped, "can only be received" is now literally true **of the
capability value**, which is what makes this sentence sayable at all — before
R2 it was not, because the root was a global in scope everywhere.

One qualifier still has to travel with it, and it is the one a reader will
otherwise supply wrongly: this says a module cannot obtain a capability it was
not given. It does **not** say a module needs one to perform IO. Built-in IO
is still ambient (R1), so `file_read(p)` compiles with no capability in scope.
"Capabilities are unforgeable" and "authority is required to act" are different
claims, and March currently has the first.

Paired, wherever the word "sandbox" appears, with the exclusion that is easiest
to forget and most likely to bite:

> Console output is not contained and cannot be. Every profile grants stdout,
> so a dependency that can print can exfiltrate through your CI logs without
> needing any other capability. What March gives you there is attribution —
> which module prints — not prevention.

Not defensible, and should not be said until stage 4:

> provably sandboxed by the type system

The gap between those two is this document.
