# `[P2]` Diagnostics inside generated (`derive` / `@[endpoints]`) code are dropped at the CLI

Found 2026-09-13 while building the event-shaped endpoint API. A generator
bug that produced `The linear value `ep` is used more than once` inside a
generated `await_*` function was reported by the endpoint unit harness
(`test/test_endpoints.ml`, which typechecks with the stdlib prepended) and by
nothing else: `march --check` on `test/session/stream_actor_events.march`
printed no diagnostic and exited 0, and the program compiled and ran.

## Cause

`Desugar_derive.respan_derived_decl` gives every span inside a generated
declaration a synthetic span whose `file` is `"<none>"`. `bin/main.ml`'s
`is_user_file` counts a diagnostic as the user's when its file is the entry
file, `""`, `"<unknown>"`, or a `MARCH_LIB_PATH` file; `"<none>"` is none of
those, so every diagnostic raised inside generated code is filtered out with
the stdlib's. The exit code follows the filtered set. Measured with the
generator as first written (the double use present): `--check` on the fixture
printed nothing and exited 0; the harness reported the error twice.

The `derive` expansions have the same file tag, so a bug in a derived `Json`
codec is equally invisible at the CLI.

## What to build

- Treat `"<none>"` as a user file in `is_user_file` (all five copies in
  `bin/main.ml`), or better, give synthetic spans the generating
  declaration's file so the diagnostic also says which `derive`/`protocol`
  produced it.
- Then decide how to render a diagnostic whose span is synthetic (line
  numbers are a counter, not source lines): print the generating
  declaration's span with a "in code generated for `X`" note.
- Witness: the perturbation above as a unit test on the driver path, or a
  `test/native` fixture that a deliberately broken generator would fail.

---

## What shipped (2026-09-13)

`bin/main.ml`: one predicate, `user_diag_file`, for "a diagnostic the user
should see", which admits the synthetic file tag; and one renderer,
`render_user_diag`, which renders a synthetic-span diagnostic without an
excerpt (its line number is a counter) and appends "in code generated for
this file by a `derive` or `@[endpoints]` declaration". Used by the two
diagnostic filters (test runner and main pipeline) and the four print sites.
The refinement report/audit "user slice" predicates are left alone: they
count obligations, and stdlib-generated code carries the same tag.

**Turning the filter on surfaced three things in the tree at once**, all
previously invisible, measured with `types-oracle` over 679 fixtures:

1. **Every monitor program had a hidden ERROR.** The builtin `Down`
   constructor's payload is typed as the surface type `Pid(a)`, and the bare
   name `Pid` in scope is the stdlib's `Global_pid.Pid` RECORD (arity 0), a
   flat-namespace collision: "`Pid` expects 0 type argument(s) but got 1", at
   a dummy span, on every program that matches a `Down`. The program still
   worked because `surface_ty` returns `TCon("Pid", [a])` after reporting.
   The same collision meant a user could not write `p : Pid(Int)` at all.
   Fix: `surface_ty` treats the one-argument `Pid(...)` as the actor pid
   builtin and skips the record's arity check. `Pid` with no arguments still
   means the record — untouched, pre-existing.
2. **`derive Eq` on a single-constructor type emitted an unreachable
   `_ -> false` arm** (a "pattern can never be reached" warning in generated
   code, now visible in four native fixtures). The arm is omitted when the
   type has one constructor.
3. **`@[endpoints]` emitted the same unreachable catch-all** in the transport
   handler and in `resume` when a state's arms already cover every message
   constructor (a two-message protocol). Omitted when they do.

4. **Hints in generated code are dropped, deliberately.** The interpreter /
   compiled parity harness captures stderr, and `derive Eq` on a type whose
   constructor name the stdlib also uses (`Inner`) produced "Constructor
   `Inner` is defined by multiple types … use a qualified form" inside the
   derived method on every run. A hint asks for an edit the user cannot make
   there. Errors and warnings from generated code are kept (`user_diag`).

After those, no in-tree program produces a diagnostic inside generated code,
so there is no natural regression witness for the filter itself; the witness
that found the bug (the `ep` double use) was a generator error that has since
been fixed. The three CLI tests in `test/test_endpoints.ml` pin the three
generator fixes through the real driver, each proved to fail with its fix
reverted. `types-oracle`: the one fixture whose diagnostics differ from the
pre-change baseline is `reject/t189` (a program that forges
`Stream_Prod.Secret`), which additionally reports "I cannot find `Secret`"
from inside the generated module; its expected rejection is unchanged.

Gates: `@types-check --force` green; `scripts/run-tests.sh -q` 3243 OK with
one `Killed: 9` at load 13 (`march_atomshow`, correct output; green alone);
`dune build @test/runtest` likewise one SIGKILLed native golden
(`builtin_borrow_leak_probe`), matching its expected output when rebuilt alone.

Not done: giving synthetic spans the generating declaration's real file and
span, so the diagnostic can point at the `derive`/`protocol` line. The
`"<none>"` tag is load-bearing for coverage and LSP filters, so that needs
its own change.
