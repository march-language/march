`[P2]` - [x] **Usability pass over `stdlib/parse.march` and its docs. Done 2026-08-16.**

A read-and-probe pass over the `Parse` combinator library, driven by writing
programs the way a first-time user would rather than by reading the source
alone. Four findings, three fixed here, one surfaced for a decision.

## 1. `let*` was non-functional for every user-defined type (compiler bug)

**The most serious finding, and it was not specific to `Parse` at all.**
`let*` (shipped 2026-08-14) documents its extension point as "define
`flat_map(x : M(a), f : a -> M(b)) : M(b)` in a module named `M`". That did
not work for any type a user defines — nested in the same file *or* imported
via `MARCH_LIB_PATH`. The error told the reader to define exactly the function
they had already defined:

```
`let*` needs `Box.flat_map`, but it doesn't exist.
Define `flat_map(x : Box(a), f : a -> Box(b)) : Box(b)` in a module named
`Box` to make `let*` work with `Box`.
```

Root cause, `lib/typecheck/typecheck.ml`'s `ELetStar` case: it resolved
`flat_map` *only* through `resolve_qualified_var`, which requires
`Module_registry.ensure_loaded` to locate a **file** whose snake_case name
matches the module (`Option` → `option.march`). A user module is already bound
in `env.vars` under its qualified name but has no such file, so resolution
returned `None`. `let*` therefore worked for `Option`/`Result`/`List` and
nothing else — the feature was stdlib-only in practice while documenting
itself as general.

Fix: consult `lookup_var` (the current scope) first, falling back to
`resolve_qualified_var` only for not-yet-loaded stdlib modules. This also makes
`let*` agree with how an ordinary hand-written `Box.flat_map(...)` call already
resolved, which it previously did not.

Witness: `specs/lang/types/accept/t184_letstar_user_defined_type.march`
(watched RED, then GREEN; verified interpreted **and** `--compile --opt 2`,
plus the separate-file `MARCH_LIB_PATH` shape).

## 2. `Parse.label` had no documentation at all

`label`'s doc comment existed, but sat above the *private* `pfn skip_to`
rather than above `label` — `label` itself was declared last in the file,
after the rendering section, ~150 lines from its own prose. The generator
excludes private functions, so the text appeared **zero times** in
`docs/docs/stdlib/Parse.html`, and `label` was the module's only undocumented
public function. Confirmed mechanically, not by eye: a script pairing each
`fn` with the doc block immediately above it reported exactly one miss.

That it was `label` is the unlucky part — the combinator whose entire purpose
is making error messages readable was the one with no explanation.

Fix: moved `label` up beside `ctx` (the other message-shaping combinator),
directly under its own doc block, and added a `march>` example.

## 3. `run` silently accepts a valid prefix, with no short way to say "all of it"

`Parse.run(number(), "123xyz")` returns `Ok("123")` and discards `xyz`. The
module's own `eof` doc warned about precisely this hazard — "a grammar
silently accepts a valid prefix of invalid input" — but nothing in the API
made the safe form convenient, so every caller had to remember
`skip_then(p, eof())` unprompted. This is the standard way a combinator
grammar returns a confidently wrong answer.

Fix: added `Parse.run_all` (`run` + `eof`), cross-referenced from `run`, from
`eof`, and from the module header's function index, which now leads with
`run_all (whole input), run (prefix)`.

Deliberately **additive rather than a semantic change to `run`**: flipping
`run` to require `eof` would silently change behavior for existing callers.
Whether `run_all` should eventually become the default spelling is left open
rather than decided unilaterally.

Tests pin `run` and `run_all` as a **pair on the same input**, since a test of
`run_all` alone would still pass if it were quietly aliased back to `run`.
Proven non-vacuous by sabotage (assert the wrong column → named failure;
restore → green).

## 4. No narrative documentation (docs)

The library had a complete generated API reference and **no prose**: no
tutorial, no worked example, nothing on the error model that is its entire
reason for existing. `docs/` had guides for actors, capabilities, linear
types, pattern matching, property testing and refinement types, but nothing
for parsing.

Added `docs/parsing.md` (`nav_order: 18`). Every code sample in it was run
against the real compiler before being written down, including the exact
rendered diagnostics quoted. Covers: `run_all` vs `run` up front; the
byte-not-character model; building blocks and why `take_while1` beats
`many(byte_if(...))`; why recursive grammars need `delay` and that forgetting
it hangs at construction rather than failing to parse; `label`/`ctx`/`commit`
together, including the commit-placement trap where both spellings accept all
valid input and differ only on the malformed input where the message mattered;
multi-error collection with `recover`; and the `let*` limitation below.

## 5. Surfaced, NOT fixed: `Parse` vs `Parser` naming

With finding 1 fixed, `let*` still cannot be used with this library, because
the dispatch keys on the *type* name (`Parser`) while the module is named
`Parse`. Unblocking it means a rename, and both directions have a wart:

- `mod Parse` → `mod Parser` makes external type references read
  `Parser.Parser(a)`, and churns 243 call sites.
- Renaming the type `Parser` → `Parse` gives `Parse.Parse(a)` instead, but
  keeps every `Parse.foo(...)` call site working — strictly less churn.

Verified that `mod X do type X(a) = X(a) ... end` is legal, so either is
mechanically possible, and that the blast radius is small: the **only**
consumers of `Parse.` anywhere are its own two test files. Also verified that
with finding 1 fixed a module rename alone suffices — no file rename or
`stdlib_manifest.ml` change is needed, because the eager stdlib load registers
modules under their declared `mod` name.

Left for a decision rather than chosen here: it is a breaking API change, the
stutter is real in both directions, and the underlying tension is in `let*`'s
"module name == type name" convention itself, which forces stutter for any
module that both defines a type and its operations. Tracked in
`specs/todos/2026-08-14-letstar-repl-and-parse-module-gaps.md`.

## 6. Incidental fix: four dangling fixture references in `types/INDEX.md`

`specs/lang/types/INDEX.md` on `main` named `t180_letstar_option_chain`,
`t181_letstar_result_subsumes_letq`, `t182_letstar_no_flat_map` and
`t183_letstar_last_expr` — **none of which exist**. The actual files are
`t177`/`t178` (accept) and `t178`/`t179` (reject). The 2026-08-14 `let*` merge
renumbered the INDEX entries to dodge a numbering collision, but the
corresponding file renames did not survive the merge, leaving the table
pointing at nothing. Repointed the four rows at the real filenames.

`doc-lint` could not have caught this: Check C only compares *counts* of files
on disk against counts claimed in prose, and Check A validates compiler source
paths, not corpus fixture names. Worth noting as a gap — a whole-table
reference check is cheap (one shell loop) and would have caught it. Not added
here to avoid scope-creeping the lint into this pass.

A methodology note for whoever writes that check: a naive validator flags
`t174_fn_grant_violated_by_helper` too, but that reference is *correct* — the
prose explicitly says the file "was deleted alongside the ceiling it existed to
pin", which is exactly the documented-removal form `CLAUDE.md` asks for. Any
such check has to distinguish "referenced as existing" from "referenced as
removed", or it will train people to ignore it.

(An earlier draft of this note claimed `main` carried duplicate fixtures. It
does not — the duplicates were untracked debris in the author's own worktree,
left behind by a branch switch. Recorded because the distinction cost a
detour: `ls` showed both numberings, `git ls-tree origin/main` showed only one.
Check the tree, not the working directory.)

## Process failure worth recording: `march>` makes an example EXECUTABLE

The first push of this work added illustrative examples to the new `run`,
`run_all` and `label` docs written with a `march>` prefix. That prefix is not
decoration — `lib/doctest/doctest.ml` extracts those lines and `march test`
RUNS them, comparing output. The examples referenced a `digits()` helper that
exists only in the surrounding prose, so CI went red with eight
`FAIL: "doctest Parse.run_all (1)" — unbound variable: digits`.

Two things made it survive local verification:

1. **`scripts/run-tests.sh` has no doctest coverage at all.** It runs the five
   alcotest executables; doctests run from `march test` / CI's
   `scripts/check-stdlib-doctests.py`. A green full local suite says nothing
   about doctests — the same class of gap already recorded for
   `@types-check`/`@grammar-check`.
2. **CI's own `check-stdlib-doctests.py --check` SKIPS these**, reporting
   "non-primitive value (bare REPL rendering differs from the doc)" rather
   than failing, because `Result`/`ParseErr` do not render as a primitive. The
   failure surfaced only through `march test`, in the `test` job. So the
   dedicated doctest checker being green is *also* not sufficient evidence.

The reproducer that actually works is `march test stdlib/<module>.march`.

Fixed by dropping the `march>` prefix in favour of the plain indented
`expr -> result` form the module already used everywhere else (see
`then_commit`'s doc), which is illustrative rather than executed. That is the
right register for these three: their values are `Result(_, ParseErr)`, whose
REPL rendering is neither stable nor readable enough to assert on.

Note when sweeping: `march test` on a *single* stdlib file loads the whole
stdlib and runs every loaded module's doctests, so it reports pre-existing
failures from unrelated modules (`HashMap.put`, `RRB.fold` — examples needing
setup bindings). Verified against a pristine `origin/main` worktree that those
predate this change; only `stdlib/parse.march` was touched here.

## Verification

- `specs/lang/types/accept/t184_letstar_user_defined_type.march` — RED before,
  GREEN after; interpreted, `--compile --opt 2`, and imported-module shapes.
- Existing `let*` fixtures (t180–t183) unchanged: accepts still accept,
  rejects still reject with their original messages.
- `test/stdlib/test_parse.march` — 7 new tests across `run_all` and `label`,
  proven non-vacuous by sabotage.
- Full local suite, `scripts/run-tests.sh`.
