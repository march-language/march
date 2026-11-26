# A local function's provenance is its own declaration's (2026-11-26)

First of two prerequisites for lowering stdlib function bodies on demand: emitted IR must not
depend on the order functions are lowered in. The second is
`2026-11-26-function-local-fresh-counters.md`.

## The bug

`Provenance.pending` (`lib/tir/provenance.ml`) maps a function's name to its source span. A
local named function (`fn go(...)` inside a body) keeps its source name in the TIR until Defun
lifts it, and lowering noted its span under that bare name. A program has many `go`s, the table
has one `go` key, and the last one lowered won. Defun then recorded every lifted
`go$apply$<k>_<host>` with that one span.

On any program that reaches the prelude's `length`, its `go` (`stdlib/prelude.march:184`) was
reported at `stdlib/shell_render.march:59`, the last `go` the stdlib lowers. The span reaches
three places: the fn-table row (file and line, read by crash backtraces), the line argument of
every `march_int_overflow` call inside the function, and `--debug-info`'s `DISubprogram`.

Two neighbours of the same shape, fixed with it:

- **Host.** `Provenance.nested_fn_hosts` mapped a nested function's name to its enclosing
  top-level function, again one entry per name, so every `go` was hosted by whichever function
  held the last `go` in `tm_fns`, and every mono clone's `$lam0_<host>` by the last clone.
  `Cap_attrib` charges a lifted function's capabilities to that host.
- **A bare top-level name.** A module function is noted under its bare name and renamed to
  `Mod.name` right after. A function that keeps the bare name (a prelude function, an
  entry-module function) and was lowered earlier sat on the same key: the note replaced its
  span, and the rename carried the entry away. The prelude's `reverse` and `map` had no span at
  all whenever a module with a `reverse` or `map` was lowered after them, so their fn-table rows
  were `null, null, 0`.

## The fix

- Lowering no longer notes a local named function under its name. `Provenance.note_local`
  stages it in the list of the top-level function whose body is being lowered.
  `Lower_state.with_fn_body` (or `enter_fn_body` / `leave_fn_body`) brackets the lowering of one
  top-level function's body and returns that list; the caller attaches it under the function's
  name (`Provenance.attach_locals`). Bracketed: `Lower_decls.lower_fn_def`, a module-level
  let's zero-arg function (both copies), an actor's handlers and its spawn glue, a test body,
  `setup` and `setup_all`. `Provenance.rename` moves the list with the function, and
  `Provenance.record ~from` hands a clone (Mono, TRMC) its original's.
- Defun's `collect_lambdas` already walks one top-level host at a time. It now keeps the host
  on each lambda (`lam_host`) and, for a name lowering did not mint (no leading `$`), its
  ordinal among the host's locals of that source name (`lam_local_k`). `lift_lambda` records
  the apply function with `Provenance.local_span ~host name k` and that host.
  `nested_fn_hosts` is gone.
- `Lower_decls.uniquify_fn` renames a local that shadows to `go$sh<n>`; `local_span` reads
  that as `go`. Its `Provenance.rename` call is removed: it could only ever move a top-level
  function's entry. TRMC puts a `go$dps` helper beside a modulo-cons `go`; it is the same
  declaration, counted separately from the `go`s (the k-th `go$dps` is the host's k-th `go`).
- A note (`note_span`, `attach_locals`) that lands on an occupied key sets the occupant aside,
  and the `rename` that moves the newcomer away puts it back.

When a host has no list (a function a pass built from nothing, such as a fused helper, or the
initialiser of an entry-module `let`, which is folded into the functions that use it), a local
function has no span of its own and reports its host's, as a lambda without one does. That
answer does not depend on lowering order either.

## Tests

`test/test_provenance.ml` (suite `provenance` in `run_codegen`), red before the fix:

- "local fns: own host and declaration line": four `go`s, two in different functions and two
  in the arms of one `if`. Before: all four `("both", 23)`.
- "local fns: span independent of declaration order": the two hosts declared in the other
  order.
- "a bare-named fn keeps its span past a later module fn of that name": `count` then
  `Inner.count`, each with a local `go`.
- "local fns: a TRMC $dps helper keeps its declaration's line": `go` and `go$dps` in two hosts.
- "local fns: overflow site carries the local fn's line": the `march_int_overflow` line
  argument inside each emitted `go$apply$…`.

## What moved in the emitted IR

`scripts/ir-oracle.sh baseline` with the commit before this one and with this one (532
programs emit, 30 skip, the same on both sides), compared with `scripts/ir-canon-diff.sh`:
368 programs are byte-identical and 164 differ. Every differing line is one of three kinds:

| lines | what |
|---|---|
| 1,748 added, 1,748 removed | fn-table rows: the file and line of a lifted local function (3 of them, the prelude's `unwrap_or`, had `null, null, 0` and now have a location) |
| 614 added, 614 removed | the file and line arguments of `march_int_overflow` calls inside those functions |
| 567 added, 781 removed | the file-name string constants those rows and calls point at |

With those three masked, all 164 are identical: no function body, callee or constant moved.

A script that reads every fn-table row of a lifted local named function
(`<name>$apply$<k>_<host>`, `$dps` helpers included) and checks it against the source: before,
1,588 of 1,879 rows named the wrong file or a line that does not declare `fn <name>`; after,
none do. The 3 remaining rows without a location are mutual-TCO combined functions
(`__mutco_…`), which the emitter builds and which had none before either.

`run_snapshots` is unchanged (TIR carries no spans).
