# Toward a provable sandbox

Status: **design, not implemented.** Nothing in this document is built. It
exists to say precisely what the claim "provably sandboxed by the type system"
would require, what March already has, and which of it is worth building.

Companion to `specs/2026-08-03-forge-cap-audit-design.md` (artifact channel),
`specs/2026-08-04-path-scoped-capabilities-design.md`, and
`specs/progress/2026-08-04-cap-ceiling-strict.md` (the ceiling).

---

## 1. Where we actually are

`--cap-strict` gives a **mechanically checked ceiling**: every module's
emitted code stays within that module's own `needs`, verified against the TIR
the compiler is about to lower, and re-checkable from the artifact via
`forge cap inspect --strict`.

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
stdlib. `lib/effects/` is where this lives.

The migration cost is real and should not be understated: this is a breaking
change to the type of every stdlib function that touches IO. It is
plausibly a major-version event.

### R2. A single root, minted at the boundary

`main : Cap(IO) -> ()`, runtime as sole minter. Today's minting surface —
*any* declaring module's public functions — is right for user-defined proof
caps and wrong for IO: it would let any module mint what it needs. For IO the
minting surface must be exactly one place, and that place must not be
expressible in March.

### R3. Unforgeability, checked

A capability must not be constructible except by receipt. Concretely, `Cap(X)`
must be excluded from:

- any cast or reinterpretation (`Bytes` → `Cap`),
- `derive(FromJson)` / any deserialization producing one,
- default-value construction and zero-initialization,
- record/variant field positions reachable by a `from_json`-shaped function.

This is a real check, not a proof obligation — a walk over type declarations
and derive lists. It is cheap and should be built *before* the proof work,
because it is where a practical break would come from.

### R4. Monotone attenuation

`cap_narrow` must only move down the lattice. Provable from `Cap_lattice`, but
it must be *stated and pinned*: the subsumption direction was written
backwards twice during the sandbox work, and the second time it shipped. A
property test over the lattice (`∀ a b. narrow a b ⟹ subsumes a b`) belongs
next to the existing `test_cap_scope.ml` subsumption tests.

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
   `test/conformance/types/` with accept/reject pairs);
2. a differential oracle against a reference implementation of the calculus;
3. extraction of the checker from the mechanized development.

(1) is achievable now and worth doing regardless. (3) is the only one that
actually closes the gap.

### R8. The runtime escape hatches

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
| **0 — today** | shipped | "`needs` is a ceiling on every module, including dependencies that never opted in, verified against emitted code and re-checkable from the artifact" |
| **1 — unforgeable** | R3, R4 | "capabilities cannot be fabricated, only received and narrowed" |
| **2 — no ambient IO** | R1b, R2 | "a module can only perform IO with authority it was given" |
| **3 — compositional** | R5 | "…and that holds for higher-order and library code, checked per-definition rather than per-program" |
| **4 — proved** | R6, R7 | "provably capability-safe for the core language, modulo FFI, compiler correctness, and console egress" |
| **5 — unqualified** | R9 | not reachable |

Note stage 1 is **independent of everything else** and cheap. It is the only
one that closes a practical attack (fabricate a `Cap` via `from_json`) rather
than strengthening a claim.

No stage closes console egress (R8a). Every row above should be read as
"...for data the program does not print", and stage 5 does not fix it either
— verified compilation makes the compiler trustworthy, not stdout private.

---

## 4. Recommended sequencing

**Now — R3 + R4.** A type-declaration walk excluding `Cap(X)` from derive,
deserialization, and default-construction positions, plus a lattice property
test for attenuation monotonicity. Days, not weeks. Closes a real hole and
needs no language change. **Do this first regardless of whether the rest ever
happens.**

**Next — R8 audit.** Answer, with tests rather than reasoning: can a `Cap`
travel in an actor message? Does hot reload bypass the ceiling? These are
questions about the system as it exists, and the answers change what today's
claim may say. Cheap, and the results could invalidate stage-0 wording.

**Then — decide on R1b.** This is the fork. Effect rows over IO are a major
version and a stdlib-wide signature change. The honest framing for that
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

Paired, wherever the word "sandbox" appears, with the exclusion that is easiest
to forget and most likely to bite:

> Console output is not contained and cannot be. Every profile grants stdout,
> so a dependency that can print can exfiltrate through your CI logs without
> needing any other capability. What March gives you there is attribution —
> which module prints — not prevention.

Not defensible, and should not be said until stage 4:

> provably sandboxed by the type system

The gap between those two is this document.
