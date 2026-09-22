# Two `@[endpoints]` protocols in one module broke the first one's sends — FIXED

**Filed:** 2026-09-21 (as `specs/todos/2026-09-21-endpoints-two-protocols-one-module.md`),
found while writing `test/session/in_process.march` for `Session.in_process()`.
**Fixed:** 2026-09-22. Pre-existing on `main` (`8b04cd168`); independent of the transport.

## Repro

`test/session/stream_endpoints.march` unchanged (it passed), plus a second
protocol in the same module, before the `Marker` type:

```march
  @[endpoints]
  protocol Other do
    A -> B : Int
    B -> A : String
  end
```

`Other` is never used.

## The two backends DISAGREED — which the original todo did not know

The todo recorded only the interpreted symptom and noted "also check compiled,
which was not run". Run on a fresh build of `main`, the backends disagree, and
that disagreement is the most useful fact about the bug:

- **Interpreted** — silent wrong behaviour, exit 1 only because the wrong
  branch happened to fall off the end of a match:

  ```
  Prod sends Item(1)
  panic: match failure — Non-exhaustive pattern match: no branch matched the value Msg_Prod_Cons_1(1).
    [0] Stream_Prod.send_Msg_Prod_Cons_1()
  ```

  The send's `to_json` dispatched into the OTHER protocol's derived impl, which
  has no such constructor. Nothing diagnosed the misdispatch itself.

- **Compiled** (`--compile --opt 0`) — refuses to build, exit 1, with an
  accurate diagnostic:

  ```
  error: ambiguous interface-method call to `JsonFrom$Msg.from_json`: 3 implementations are
  in scope (JsonFrom$Marker.from_json, JsonFrom$Other_Msg.Msg.from_json,
  JsonFrom$Stream_Msg.Msg.from_json) and the call site's types do not determine which one
  applies.
  ```

`--check` was exit 0 in both cases, before and after the fix: the bug lived
entirely past the typechecker.

## Cause

Every protocol generated a `<P>_Msg` module whose message type was declared as
a bare `Msg`, deriving `Json` inside that module (`msg_module`,
`lib/desugar/desugar_endpoints.ml`). Impl dispatch for the derived codec keys on
the type's **SHORT name** in both backends, so two protocols in one module
produced two impls whose dispatch key was `Msg`:

- the compiled path has an ambiguity check and refuses (the diagnostic above);
- the interpreter has no such check — Json is explicitly excluded from the
  type-DISPATCHER routing added by the FQN impl-dispatch identity work
  (`specs/plans/archive/2026-07-20-fqn-impl-dispatch-identity.md`), whose
  `iface_method_tbl` gate reads `not is_type_dispatched_iface && not is_json` —
  so it took the name-bound path and silently ran the other protocol's body.

## Fix (generator-level)

`msg_module` now names the message type after its protocol: `<P>_Message`
instead of `Msg`. The collision is removed at the source, so both backends are
fixed by one change and no dispatch machinery moves.

The rename is **internal**: nothing outside `msg_module` spelled the type.
Role modules reach the message only through `<P>_Msg.<Ctor>` (module-qualified,
unaffected) and `<P>_Msg.{encode,decode,try_decode}`; no `.march` fixture, no
`docs/` page and no `specs/lang/` page named it. Verified by grep over
`*.march`, `*.md` and `*.ml`.

## What was rejected, and why

- **Interpreter dispatch (Layer 1b: qualify the `iface_method_tbl` key and the
  runtime type name by declaring module, collision-conditional), or lifting the
  `not is_json` gate.** This is the general remedy for the underlying hazard and
  remains the right long-term answer, but it is a much larger change than this
  bug needs, and it touches both `DImpl` eval paths (`eval_decl` AND
  `make_recursive_env`) plus the lockstep `ctor_type_tbl` / `record_type_tbl` /
  `ffi_type_decl_tbl` writes. The generated names were collidable for no reason;
  fixing the generator is the proportionate fix.
- **A native "Layer 2" flag-day** (global ctor tags, qualified impl symbols) was
  out of scope by construction and is not needed here.

## The residual hazard, made loud and pinned

The general short-name limitation is untouched: a user's own two same-short-name
`Json`-deriving types still misdispatch interpreted and are still refused
compiled. That is the FQN work's open ground, not this fix's.

What this fix *does* add is one reserved name per protocol: `<P>_Message`. A
user type called `Stream_Message` deriving the same interface the generated
codec derives is now an **overlapping implementation** — a loud typecheck error,
exit 1 on both backends. That is the trade being made deliberately: a loud
rejection replaces a silent misdispatch. Pinned by `reject/t292` and documented
in `specs/lang/choreography.md` / `docs/choreography.md` ("Names `P` reserves").

## Witnesses

- `test/session/in_process.march` + `.expected` — **the regression detector**.
  Two `@[endpoints]` protocols in one module (`Stream` and `Logging`), each
  running its own sessions, run on **both backends** against one golden
  (`test/dune` diffs `in_process.out` and `in_process_interp.out` against the
  same `.expected`). A compiled-only rule would have seen only half of this bug.
  Control: with `lib/desugar/desugar_endpoints.ml` reverted to `origin/main` and
  the compiler rebuilt, this fixture fails interpreted with the match failure
  and fails compiled with the ambiguity error; with the fix, both backends emit
  the golden byte for byte.
- This file was **two** files until now: `in_process.march` and
  `in_process_logging.march` were split one protocol per file solely because of
  this bug. They are recombined; `in_process_logging.{march,expected}` and its
  `test/dune` rules are deleted, and the golden is the concatenation of the two
  old ones, unchanged line for line.
- `specs/lang/types/accept/t291_endpoints_two_protocols_one_module.march` — two
  protocols in one module, both used, `--check` exit 0. Honestly labelled in its
  own header and in the INDEX row: `--check` was green before AND after, so this
  is a well-typedness witness, not a regression detector.
- `specs/lang/types/reject/t292_endpoints_message_type_name_reserved.march` — the
  reserved-name cost. This one does move: it is accepted pre-fix and rejected
  post-fix.
- `test/test_endpoints.ml` — three generator-shape cases: the message type is
  `<P>_Message` and not a bare `Msg`; two protocols generate two distinct
  message type names with no shared short name; and the pair typechecks together.

## Acceptance (from the original todo)

> Two `@[endpoints]` protocols in one module each run their own session, on both
> backends; a fixture in `test/session/` pins it.

Met. Both backends run both protocols and agree, byte for byte, with one golden.
