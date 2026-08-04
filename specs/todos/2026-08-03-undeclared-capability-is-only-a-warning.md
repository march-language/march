# An undeclared capability builtin is a warning, not an error

Filed 2026-08-03 while writing `/docs/capability-audit/`, which forced the
question "what exactly does a declared capability set guarantee?"

## The gap

Two checks in `check_module_needs` (`lib/typecheck/typecheck.ml`) treat
undeclared capabilities differently:

| Check | Trigger | Severity |
|---|---|---|
| Check 1 | a `Cap(X)`-typed **value** used without a declared `needs` | `Err.error` |
| Check 1b | a capability **builtin called directly** in a body (`file_write(…)`) | `Err.warning_with_fix` |

Measured:

```march
mod Undeclared do
  fn sneaky(path : String) : Bool do
    match file_write(path, "data") do
      Ok(_) -> true
      Err(_) -> false
    end
  end
end
```

```
$ march --check undeclared.march
-- WARNING -- function body calls a builtin that requires `Cap(IO.FileWrite)`
              but `Undeclared` does not declare `needs IO.FileWrite`.
$ echo $?
0
```

It compiles. So a module's declared capability set is a hard lower bound only
for capability-passing code; for direct builtin calls it is advisory.

## Why it matters more than it used to

`forge audit` (and the `/docs/capability-audit/` page) rest on the declared set
being meaningful. The honest claim today is "a floor that capability-passing
code cannot go under, not a ceiling on everything", which is what the docs now
say — but the marketing-shaped version of this feature ("surfaced mechanically
by the type system, no heuristics") is stronger than the enforcement.

A dependency author who ignores one warning ships a package whose `forge audit`
row understates what it does. The warning is visible at build time, so this is
loud rather than silent — but nobody reads a dependency's build warnings.

## Options

1. **Promote Check 1b to an error.** Cleanest statement, and makes the declared
   set a true lower bound. Breaking: any existing module relying on the warning
   stops compiling, including possibly stdlib and demo code. Needs a survey of
   how many modules currently warn before this is costable.
2. **Gate it.** `cap strict` as a module-level opt-in (mirroring `cap verified`
   for refinements), or a `--deny-warnings`-style compiler flag, so a project
   can demand the stronger property without breaking everyone at once. This
   matches the precedent already set by `cap verified`.
3. **Leave it, and rely on `forge cap inspect`** for the binary-level check, since
   that reads emitted markers rather than declarations and therefore catches an
   undeclared direct call regardless.

Option 2 looks right, and it composes with 3: opt into strictness where it
matters, verify the artifact regardless.

## Measured: how much would option 1 break?

Checking each stdlib module on its own (`march --check stdlib/<m>.march`):

**20 of 112 stdlib modules currently trip Check 1b.**

```
audio          IO.Foreign            list           IO.Spawn
canvas         IO.Foreign(.Blocking) logger         IO.Clock
check          IO.Clock, IO.Process  parallel       IO.Spawn
config         IO.Mut, IO.Process    process        IO.Process
datetime       IO.Clock              random         IO.Clock
dns            IO.Network            seq            IO.FileRead
dom            IO.Foreign            socket         IO.NetConnect
env            IO.Process            task           IO.Spawn
file           IO.FileSystem         tls            IO.NetConnect
http_transport IO.NetConnect         uuid           IO.Clock
```

That is a bounded, mechanical list — every one looks like a module that should
simply declare the capability it obviously uses (`file` needs `IO.FileSystem`,
`socket` needs `IO.NetConnect`). None looks like a design problem; they look
like declarations nobody was forced to write.

So option 1 (promote to error) is more viable than expected: roughly 20
one-line `needs` additions in stdlib, plus whatever the demo apps and test
corpora turn up — the corpora are the real unknown, since
`specs/lang/types/accept/*` and the golden tests contain many small modules that
call builtins directly.

Suggested order: add the missing `needs` to those 20 first (harmless on its own,
and it makes stdlib self-describing for `forge audit`), then measure the
corpora, then decide between promoting the check and gating it behind
`cap strict`.

## ATTEMPTED 2026-08-04: "add the 20 needs" is NOT harmless — reverted

Added `needs <cap>` to all 20 modules and measured. The Check-1b warnings all
cleared and, for a QUALIFIED call (`DateTime.now()` from an outside module), the
capability did NOT cascade to the caller — so the "harmless" claim looked right.

Then the conformance corpus failed: `accept/t37_use_all_stdlib_module.march` and
`t38` broke with

```
module `Main` imports `List` which requires `Cap(IO.Spawn)`, but `IO.Spawn`
is not declared in `needs`.
```

**`needs` cascades through `use`/`import`, and module-level granularity
over-constrains.** `List` declares `needs IO.Spawn` only because of one niche
function, `List.pmap` (parallel map). But a module-level `needs` applies to the
whole module, so `use List.*` — even to reach `append`, `map`, `filter`, which
spawn nothing — now forces the importer to declare `IO.Spawn`. That is wrong:
using a data-structure module should not demand a concurrency capability.

The 20 split into two kinds, and they need different handling:

- **Whole-module-legitimate** (the module's purpose IS the capability): `task`,
  `parallel` (IO.Spawn), `file`, `seq` (IO.FileSystem/FileRead), `socket`,
  `tls`, `http_transport` (IO.NetConnect), `dns` (IO.Network), `process`, `env`
  (IO.Process), `audio`, `canvas`, `dom` (IO.Foreign). Declaring the cap here is
  arguably correct — a `use` of these modules SHOULD propagate the requirement.
- **Over-constrained** (the cap comes from a niche function): `list` (IO.Spawn,
  only `pmap`), and likely `datetime`/`uuid`/`random` (IO.Clock, only the
  wall-clock functions, not the pure formatting/parsing ones), `config`
  (IO.Mut/IO.Process, only the live-reload paths).

So the real fix is not 20 one-line edits. It is one of:

1. **Per-function / per-`needs`-scope capabilities** — declare the cap on the
   function that uses it (`List.pmap`), not the module, so `use List.*` only
   propagates IO.Spawn to code that actually calls `pmap`. This is the correct
   model but a language/typechecker change.
2. **Split the niche functions out** — move `List.pmap` to a `ListParallel`
   module, `DateTime.now` to a `Clock` module, etc., so each module's declared
   caps match what all its functions need. Mechanical but churny and changes the
   public API surface.
3. **Declare only the whole-module-legitimate set now** (the ~14 above), leave
   the over-constrained ~6 warning until option 1 or 2 lands.

This is a design decision for the plan owner, not a mechanical sweep — which is
why the attempt was reverted rather than forced. The Check-1b promotion decision
(the top of this file) depends on it: promoting Check 1b to an error is only
viable once the over-constraint is resolved, or every `use List.*` in the
ecosystem breaks.
