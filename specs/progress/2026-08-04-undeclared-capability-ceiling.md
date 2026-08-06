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

---

## Resolved 2026-08-04 — `--cap-strict`

Option 2 (gate it), with two departures from the plan above, both of which
made it cheaper than costed here.

**A compiler flag, not a module-level `cap strict`.** `--cap-strict` is a
build gate. A module-level opt-in would have let a dependency decline the
property, which is backwards for the threat this exists to address — the
consumer, not the publisher, is the party who wants the ceiling.

**Checked against emitted code, not by promoting Check 1b.** This is why the
"20 stdlib modules" survey above turned out not to be on the critical path.
Attribution charges a stdlib-mediated call to the *calling* module, so
`needs IO.FileWrite` is demanded of the module that called `File.write`, and
nothing is asked of `file.march` itself. The 20 one-line additions were never
needed.

Promoting Check 1b would also have closed the smaller hole. Measured while
implementing: the direct-builtin route was a warning, but the **stdlib-mediated
route produced no diagnostic at all** — `mod M` calling `File.write` with no
`needs` typechecked silently at rc=0, because the import check walks `use`
declarations and stdlib modules are ambiently available without one. That is
the most common route in real code, and promoting Check 1b would have left it
open.

**What the declared set now guarantees.** With `--cap-strict`, a ceiling on
every module including dependencies that never opted in, verified against the
code the compiler emits and re-checkable from the artifact via
`forge cap inspect --strict`. Without it, unchanged: a floor for
capability-passing code, plus warnings.

The docs wording this file was filed against ("a floor that capability-passing
code cannot go under, not a ceiling on everything") remains correct for the
default build and should stay.

See `specs/progress/2026-08-04-cap-ceiling-strict.md` for the implementation,
and `specs/todos/2026-08-04-cap-ceiling-follow-ups.md` for what is still open
(no `--check` support, no migration autofix, no per-package roll-up).
