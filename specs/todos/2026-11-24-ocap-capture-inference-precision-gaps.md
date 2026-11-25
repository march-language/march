`[P3]` Capture inference: what it does not track, and what it over-approximates (2026-11-24)

Capture inference (ocap phase 8a) answers `not tracked` (above every set) where it does not
model something, and is coarse in a few places. None of these is unsound; each costs
precision. `march --dump-captures FILE` prints the untracked spots of a file, and
`MARCH_CAPTURE_DEBUG=1` prints every one, the stdlib's included.

Not tracked:

- **A function value a builtin returns with no argument to account for it**: one read from a
  table opened by name (`Vault.open`, `Vault.whereis`), a received message. The design gives
  these the full set `IO` across nodes; within a node the table's element type could carry
  the set if the name were tied to its creation.
- **An authority check of a computed kind**: `Authority.check(kind, target)` with a `kind`
  that is not a string literal. Every stdlib entry point passes a literal.
- **A field read on a value whose declared type the pass cannot resolve**, mostly generated
  code with no source file.
- **A sigil, an atom holding a function value, a `let*` binder** (`ELetStar`: the binder's
  type is rebuilt only when it holds no function value).
- **The stdlib's lazy `Seq`**: its constructor takes a rank-2 fold function that March's
  types do not express (`stdlib/seq.march`), so calls through it are untracked.

Coarse:

- **Actors.** A message field and `state` are `IO` where they are used (design §9.1), so a
  function value that spawns an actor which calls a closure it was sent has `IO`.
- **Interface method calls** take the union over every impl of the method.
- **A local `let` does not generalise** (design §5): one local higher-order value has one set.
- **Method and limit scope arguments** (`methods(get)`, `max(n)`) are never inferred, and a
  literal target gives a scoped element only at the entry points the literal-target checks
  know (`@[net_dest]` functions, the path entries, the name-taking functions).
- **A `needs` clause on an impl method** narrows by kind only; a plain function's clause
  narrows with its scopes.
- **Two functions with one bare key** (a user function named like a prelude function, such as
  `compose`) share one entry in the reach tables the pass reads (`env.fn_row_bodies`), so
  their bodies are analysed as alternatives of one function. That is a property of the reach
  tables, not of this pass.
- **A user file in the editor**: see
  `2026-11-24-ocap-capture-pass-always-on-prerequisites.md` for the bodies the editor path
  does not hand the pass.

**Callback registries (2026-11-24, from the 8a review).** A function value registered with a
builtin and run later by another builtin is charged to the code that registers it, and the
builtin that runs it must be listed in `dispatching_builtins` (`lib/typecheck/capture.ml`) so
its caller is `not tracked`. Only `logger_dispatch` is listed. Not audited: signal watchers,
diagnostics observers (`diag_observe`), timers, HTTP server handlers, supervisor child specs.
Each one that runs a stored function value from a builtin, outside the registering call, needs
an entry, or better a rule derived from the builtin table. Until then a function value that
triggers one of them can have a set that is too small. The soundness oracle
(`MARCH_CAPTURE_ORACLE=1`) reports it when a program exercises it.
