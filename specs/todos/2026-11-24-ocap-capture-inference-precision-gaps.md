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

## `mock` blocks and the Vault (after ocap phase 7 landed, 2026-11-25)

- **`mock` is not modelled.** Inside `mock SCOPE with HANDLER do ... end` an operation the
  entries cover runs a handler function instead, and a closure, task or actor created in the
  body keeps the mock. The pass does not model which operation reaches which handler field, so
  the enclosing function and every function value created in the body are "not tracked" (`?`).
  Sound, and only in test builds. Precise version: the handler record's held sets join the set
  of every function value created in the body, and of the enclosing function.
- **Every function that opens a Vault is now `?`.** `Vault.new`, `Vault.whereis` and the
  namespace reads call the private `table_name`, which reads a mock's handler with the builtin
  `mock_lookup` and may call its `open` hook. The pass sees a call through a function value of
  unknown origin, so `table_name` and every caller is not tracked (`test/captures/data.expected`:
  `main ... needs IO.Mut, ?`). In a build that is not a test build no mock exists and the extra
  `?` is pure imprecision. This must be fixed before 8b can reject anything that opens a table:
  either give `mock_lookup` a result whose set is the mock in force (empty outside test builds),
  or special-case the dispatch wrappers the way `logger_dispatch` is.

## After phase 8b (2026-11-25)

- **The Vault `?` did not have to be fixed for 8b.** `?` alone holds no tracked name, so a
  callback that opens a table is not rejected for it. It is still pure imprecision outside a
  test build.
- **A handle's set can show scopes it does not have.** A declared type that holds both a
  function value and a handle has one set (design §4.2), so reading the handle field gives a
  `File.Handle` whose set is the function's. Sound, and it prints oddly
  (`File.Handle needs IO.Console`).
- **Two handles to one table are unrelated values.** A function value put into a table through
  one `Vault.new("t")` and read through another is not marked as of unknown origin, because
  `vault_new` is listed as returning a fresh, empty container. The escape check does not depend
  on it (a handle put in a table is rejected at the store), but a capture set read from such a
  table can be too small. The soundness oracle reports it when a program exercises it.
- **Which builtins keep what they are handed.** A builtin handed a function value keeps it
  unless it is listed as running it before it returns (`runs_now_builtin`,
  `lib/typecheck/capture.ml`) or is a task spawn, so a builtin nobody listed is read the safe
  way. A builtin that keeps a bare handle still has to be listed (`retaining_builtin`: `own`,
  `register_resource`, the send builtins, `vault_*`, the watchers and logger builtins). The
  audit this file asks for above (timers, HTTP server handlers, supervisor child specs) decides
  what else belongs there.
- **A task that is never awaited escapes (soundness gap).** `File.with_open(p, fn h -> let _ =
  Task.async(fn () -> File.read_line(h)) 1)` is accepted: the task value holds the name, the
  value is dropped, and the task may still run after the callback returns. The design (§9.2)
  and the 8b plan allow `Task.async` inside the callback and catch a task that is returned or
  stored; nothing catches one that is dropped. Closing it means either rejecting every task
  that captures a scoped handle (the awaited case, which is correct, goes too) or tracking
  that a task is awaited before the callback returns. A decision for the user.
- **A resource made from a handle carries no name (soundness gap).** `Tls.connect(s, ctx,
  host)` inside `Socket.with_connection` returns a `TlsConn` built from the socket's file
  descriptor, an `Int`, so the name is gone and the connection can be returned. The same holds
  for anything that reads a handle's descriptor and builds another value from it.
- **`Seq` used on the handle inside the callback is rejected.** `Seq.to_list(Seq.map(xs, fn _
  -> File.read_line(h)))` and `Seq.fold` report "passed to code the compiler cannot follow",
  because `Seq` is not tracked (above). The lazy case is rightly rejected; the strict ones are
  correct programs. Workaround: `List` functions.
- **`scoped` before a type variable, a tuple or a parenthesised type is a syntax error**, not
  `scoped_misplaced`: the keyword is recognised only before an upper-case type name.
  `scoped Int -> b` is accepted and means nothing.
- **Messages.** A handle that reaches the result through an ordinary wrapper, a pipe or a
  function used as a value is described as "a value that holds it"; a callback bound with
  `let` first loses the handle's name ("The handle").
- **A bare `fn` typed at the REPL prompt is not checked for escapes**, like the other
  whole-program capability checks there; a `mod` is.
