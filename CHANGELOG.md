# Changelog

All notable changes to March are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/); versions follow
[Semantic Versioning](https://semver.org/).

This file starts at the point March adopted a changelog (2026-07-21).
Implementer-level detail on every change (including everything that shipped
before this file existed) lives in `specs/progress/` and `specs/todos/`;
git log is authoritative for exact commits.

**Past releases.** Older releases live in one file each under [`changelog/`](changelog/):

- [0.5.0](changelog/0.5.0.md) - 2026-10-13
- [0.4.0](changelog/0.4.0.md) - 2026-09-10
- [0.3.0](changelog/0.3.0.md) - 2026-08-23
- [0.2.0](changelog/0.2.0.md) - 2026-07-23
- [0.1.1](changelog/0.1.1.md) - 2026-07-21

## [Unreleased]

### Added

- **Every compiler fix now has a tier, and `forge fix` applies only the safe ones.** In
  `march --check-json`, a fix's `applicability` is `machine-applicable`,
  `has-placeholders` or `maybe-incorrect`. Before printing a machine-applicable fix,
  `--check-json` applies it to a copy of the file and checks the copy. Unless its own
  error went away and nothing new appeared, the fix is printed as `maybe-incorrect`.
  `forge fix` applies only machine-applicable fixes, and the language server marks only
  those as the preferred quick fix, after re-checking each one on a copy of the buffer.
  The others are labelled "a guess: check it" or "fill in the placeholder".
- **`march --check` shows each fix under its error,** as the lines it changes
  (`4 - old`, `4 + new`), headed by its tier. Until now only `--check-json`, the editor
  and `forge fix` saw fixes.
- **More errors come with a fix:**
  - an unknown name, qualified name, constructor or record field, when the message
    suggests exactly one replacement (a guess when another candidate is as close);
  - a missing JSON codec: `derive Json for T` after `T`'s declaration;
  - a type annotation on `let?` / `let*`: it is removed;
  - a non-exhaustive `match`: the missing arm, with a `todo(...)` body to replace.

  In the error corpus, 138 of 414 programs now carry a fix (up from 123), and 132 of them
  have a machine-applicable one.
- **Record-typed variables in refinement predicates.** A lemma's theorem can read its record
  parameter's fields (`px(p) == p.x + p.y` over `p : Pt`), a precondition can name another
  parameter's field (`n : {Int | _ > p.x}`), a record passed to a record-refined parameter is
  checked (including a reflected call that returns one, `need_x(bump(p))`), and a return type
  can relate the result to a record parameter (`{Int | _ == p.x}`, `{Pt | _.x == p.y}`). A
  record literal in a predicate is typed by its field names when exactly one record has them,
  and reports print it as written instead of `<predicate>`.

- **Stdlib laws for `List.sum_int` and `List.product_int`, and a result type on `List.length`.**
  `List.sum_int_append(xs, ys)` proves `sum_int(append(xs, ys)) == sum_int(xs) + sum_int(ys)`,
  `List.sum_int_reverse(xs)` proves `sum_int(reverse(xs)) == sum_int(xs)`, and
  `product_int_append` / `product_int_reverse` do the same for products. `List.length(xs)` now
  has the proved type `{Int | _ == len(xs)}`. The loops of `length`, `sum_int`, `product_int`,
  `minimum_int` and `maximum_int` moved to private top-level functions so the laws can name
  them; what they compute is unchanged.

- **`Session.Theory`: what a protocol means, as March code, with proved laws.** A new stdlib
  module holds protocols (`SessionGlobal`) and each role's part (`SessionLocal`), projection, duality, and
  lemmas proved once: duality is an involution, and a two-role protocol's projections are
  dual. The compiler checks both of its own projectors against `Session.Theory.project` for
  every protocol you write, by running it in the interpreter: `march --check --guarantees`
  labels a protocol's projection `proved (spec) · validated (compiler)` when they agree, and
  `march --validate-projections FILE` lists every role. See the choreography chapter,
  "What is proved about a protocol".
- **`forge hot-reload check` / `march --check --guarantees` say what a build guarantees.**
  One block per actor and protocol, each line labelled `proved`, `violated`, `not proved`,
  `not checked`, `checked (compiler)` or `assumed`, with what it rests on: state refinements,
  `@invariant`, handler contracts, `migrate_state` (derived or written, against the deployed
  build when there is one), `migrate_msg`, protocol projection and deadlock freedom, and the
  runtime. It changes no verdict. Two gaps are labelled `not checked` rather than left
  silent: `@invariant` is not checked on `init` or handler results, and no proof covers a
  protocol's deadlock freedom. See docs/hot-code-reload.md, "What a build guarantees".
- **`--refine-infer` proposes a relation a function keeps from its argument to its result.**
  For `bump(a : Assoc(Int, Int)) : Assoc(Int, Int)`, which adds 1 to each value, a caller
  that needs `Assoc({x : Int | true}, {y : Int | y > x})` gets the type proposed on both the
  parameter and the result, checked as one step and written as two edits.
- **`--refine-infer-module M`** limits inference to one module (standard library or yours),
  with progress lines on stderr. `scripts/refine-infer-stdlib-sweep.sh` uses it to run
  inference over the whole standard library one module at a time, in parallel: 98 seconds
  instead of 48 minutes.
- **Adding a field to an actor's state no longer needs a `migrate_state`.** When a build
  knows the running version's schema (forge's `.schemas.json.prev`, or `--hcr-baseline`) and
  an actor's state only gained fields whose `init` values are constants, the compiler writes
  the migration: kept fields are copied, new ones take their `init` value. It is checked like
  a written one, including on the live state before `ACTIVATE`, and `forge deploy hot` says
  `migrate_state derived from the running version's state (adds history from init)`. A
  removed or retyped field, or an `init` value that reads an `init` parameter, still needs a
  written migration, and the refusal now says which. If a kept field's refinement was also
  tightened, the error points at that field with the running state that breaks it. See
  docs/hot-code-reload.md, "Derived migrations".
- **A failing test reads like a compile error.** A failed `assert`, `Check.all` property or
  panicking test body now prints a `-- TEST FAILURE --` report with the line under a caret,
  the same under `march test` and `forge test` (compiled). For `assert (a == b)` it labels
  both sides by their source text and marks the first difference: the element, field or
  argument, a list length mismatch, or a string's first differing character. A long value
  is elided to the path to the difference (`[…, 170, …]`). A failing property shows the run,
  the shrunk input by the property's parameter name (`xs = [0, 1]`; `a = 39`, `b = 11` for
  a `match`ed tuple), why it failed (with the inner assertion's report) and the seed to
  replay. Before, compiled tests printed only `assertion failed`. The `FAIL: "name"` lines,
  the summary lines and exit codes are unchanged.
- `march --why-copies FILE` lists each place in your code where a function builds a new copy
  of a list or tree instead of reusing it in place, because the value is still shared: used
  again afterwards, also passed to the enclosing call, or captured by a closure. Each is a
  `copy_shared` warning naming the call, the value and the reason, and when moving the later
  use above the call is safe (its only later use, no side effects), it carries that move as a
  fix for `forge fix`. `--why-copies-json` prints the same as NDJSON. Opt-in; stops before code
  generation. On a 200,000-element list, making the map the last use cut peak memory from 29 MB
  to 10 MB.

- **Protocol errors draw the conversation so far.** A role body that takes a step out of
  order (`protocol_step_order`), calls another role's step (`protocol_wrong_role`), uses a
  `Chan`/`MPST` channel at the wrong step (`session_state_mismatch`), or takes a step on a
  state it already closed (`linear_used_twice`) now shows the protocol's steps up to that
  point, with the role's own steps marked `done`, the step it must take next, and the one
  it tried; a `loop` is drawn as one round and a `choose` as the branch taken, naming the
  others. Long conversations keep three steps of context each way. `--check-json` carries
  the diagram as a note.
- **Refinement errors show the failing case and what it does.** A `refinement_violated`
  call now prints the solver's values (``for example, when `d` is `0` ``), labels where the
  failing value came from (the parameter or `let`, and the `if` condition the call sits
  behind), and words the guard over the call itself: `if d != 0 do safe_div(10, d) else …
  end`, with every parameter the precondition names read at the call (`i < len(items)`,
  not `_ < len(xs)`). A literal gets "`0` can never satisfy `b != 0`" instead of a generic
  note, and a pass-site error no longer prints the internal `(cb_x)`. When every argument
  is concrete and the callee needs no I/O, the call is run once in the interpreter, step
  limited, and a failure is reported in one line: ``running `safe_div(10, 0)` panics:
  division by zero``. A definite `return_refinement_violated` shows the run too (`but
  bad(-1) returns -1.`). None of this changes which programs are accepted.
- **A hot deploy checks an undecided migration on the live state before activating it.**
  A `--hot-reload` build carries, beside each `<actor>_migrate_state` whose actor has field
  refinements or an `@invariant`, a function that runs the migration and evaluates the new
  contract. Before `ACTIVATE`, the reload server runs it on a copy of every live actor's
  state. A failure refuses the deploy with the actor, its pid and the failing conjunct
  (`ERR migration_check Counter pid:0 @invariant: not_137(count)`), and nothing changes. So
  a migration accepted with `--accept-unproved` is still checked on the data it will meet.
  A converted message that fails the new handler's refinements is dropped, like a `None`.
  See docs/hot-code-reload.md, "Undecided migrations are checked on the live data".

- **Hot-reload migrations are checked on every build, with a counterexample.** When an
  obligation in an `<actor>_migrate_state` or `<actor>_migrate_msg` can't be proved, the
  compiler runs the migration on small old values. An input whose result the new actor
  rejects is now an error that names it: `but tally_migrate_msg(V1.Bump(0)) returns
  Some(Tally.Bump(0))`. Before, this was a "not verified" hint. When the project was
  hot-deployed before, the running version's state refinements
  (`.march/<name>_hot.so.schemas.json.prev`, or `--hcr-baseline <path>`) are assumed of
  `migrate_state`'s record parameter. A migration that is correct for the running version
  therefore proves, and an old message the running handler refused is never offered as a
  counterexample.
- **An actor's message can be qualified by its actor.** When two actors (or an actor and a
  variant) share a message name, `Counter.Tally(1)` (also `Counter_Msg.Tally(1)`, and
  `Outer.Counter.Tally(1)` for a nested actor) selects `Counter`'s message on both backends.
  A `migrate_msg` that keeps a message's name can now write `Some(Tally.Bump(n))`. The
  `ambiguous_constructor` and `send_wrong_actor` diagnostics suggest the qualified spelling
  instead of renaming a handler. A refined handler parameter is now checked at every
  construction of a shared message name, by its qualifier or its type.

- **More stdlib laws: `List.take_append`, `List.drop_append`, `List.nth_opt_append`, and
  result types on `Math.min_int`, `max_int` and `clamp_int`.** The three lemmas state what
  `take`, `drop` and `nth_opt` do on `append(xs, ys)` at `len(xs)` or an index inside `xs`;
  calling one proves what unfolding runs out of fuel on. `min_int(a, b)` now has the type
  `{Int | _ <= a && _ <= b && (_ == a || _ == b)}` (and dually `max_int`), and
  `clamp_int(x, low, high)` is within `[low, high]` when `low <= high`; the condition is in the
  result, so no existing call gains an obligation.

- **A refinement on a field of an anonymous-record parameter is now checked.** In
  `fn f(r : { v : {Int | _ > 0} })` the body may assume `r.v > 0`, and each caller must
  establish it. Before, the refinement was ignored on both sides. Likewise
  `fn f(r : {T | _.v > 0})` now gives its body the fact at a call's precondition, not only
  at its result.
- **A `--hot-reload` build rejects an `@invariant` the deploy gate can't read.** The error
  (`invariant_not_deploy_checkable`) points at the unsupported part. `--accept-unproved
  <Actor>.state` turns it into a warning and records the override in the patch. Before, the
  build printed a one-line warning and the actor could never be hot-deployed.
- **A hot deploy's `--accept-unproved` override is signed into the patch and audited.**
  forge builds the patch with it, the compiler writes the accepted laws into the actor's
  schema (`"accepted_unproved"`), and the reload server's audit line for the activation
  records them, so `audit.jsonl` shows which laws went out without a proof. forge refuses an
  override that a pre-built patch (`--so`) doesn't carry; rebuild it with
  `march --accept-unproved …`.
- **UDP in the standard library: `Udp`.** Datagram sockets built for packet rate. Every send
  and receive moves a batch per kernel crossing: on Linux `recvmmsg`/`sendmmsg` plus UDP GSO
  (up to 64 datagrams per transit) and opt-in GRO, elsewhere a nonblocking drain loop. On a
  Linux loopback that is about 2.9M datagrams/s at 64 bytes, and 3.4M/s at 1200 bytes with
  GRO. Waits park the task, not an OS thread. Sends wait for buffer space instead of
  dropping; `Udp.stats` reports the datagrams the kernel dropped. `open_sharded` spreads
  one port over several sockets (SO_REUSEPORT), and connected sockets report ICMP
  port-unreachable. IPv4 and IPv6. `bench/udp_flood.march` measures it. The module is
  `cap verified`: ports, batch sizes and shard counts are refined, so `Udp.open(h, 70000)` is
  a compile error, and the counts `send_batch` and `open_sharded` return are proved.

- **`--refine-infer` proposes lemma calls.** At a call the refinement checker could not finish
  because the proof needs more unfolding of a function, `march --check --refine-infer` and
  `forge refine --infer` look for a lemma, yours or the standard library's, whose theorem is
  about a call in the arguments. For `need_same(xs, List.reverse(List.reverse(xs)))` it proposes
  `List.reverse_reverse(xs)`. Every candidate is checked by checking the program again with the
  call in it, and `--refine-infer-apply` writes the call above the statement. When no lemma
  closes the call, it prints the lemma that would, for you to prove. `--refine-infer-kinds=lemma`
  selects this kind on its own; the JSON output gains `lemma_calls` and `lemma_none`.

- **Law coverage: which pure functions have laws, and how tightly.**
  `march --check --law-coverage FILE` lists a file's pure functions by whether a proved
  lemma's theorem calls them (unproved laws are shown apart, higher-order functions listed
  separately), and `--law-coverage-json` gives the same as JSON. `--law-strength` adds, for
  each covered function, the small edits to its body (return a parameter, swap arguments,
  change a literal or comparison, swap match arms, drop the recursive call) that every law
  covering it still accepts. `--law-coverage-all` reports every user file the check loaded,
  and `forge audit --laws [--strength]` runs it over a whole package at once.
- **`List` ships lemmas about its own functions.** `List.append_nil`, `append_assoc`,
  `len_append`, `reverse_append`, `reverse_reverse`, `len_reverse`, `len_take`, `len_drop`
  and `take_drop` can be called from any program to give the refinement checker that
  theorem as a fact, for example `len(append(a, b)) == len(a) + len(b)` after
  `List.len_append(a, b)`. They cost nothing at run time. They are proved once and recorded in
  `stdlib/lemmas.verified`, so a check does not prove them again. `List.filter` also gains a
  proved `len(_) <= len(xs)` contract.
- **Search laws by shape.** `forge search --law "f(f(x)) == x"` finds every lemma of that
  form, whatever its functions are called: a one-letter callee stands for any function and
  any other name for any term. `--law "f(x, Nil) == x"` finds right identities.

- **A refinement can say what each half of it means.** Write a message after a
  conjunct with `else`: `{Int | _ >= 0 else "index must not be negative" &&
  _ < len(xs) else "index must be less than the list's length"}`. A call that
  breaks a conjunct now leads with its message and names that conjunct alone
  (`argument `n` of `List.nth` does not satisfy precondition `_ >= 0``), and the hint for a
  call the checker cannot prove carries the message of the conjunct it could
  not establish. `else` binds tighter than `&&`; a conjunct without a message is
  reported as before. The stdlib's two-sided bounds carry messages: `List.nth`,
  `Array.get`/`set`, the `Simd` lane accessors, `DateTime.fixed_zone` and
  `fixed_zone_hm`, `Random.bernoulli`, and `Stats.percentile`/`quantile`.
- **z3 ships with the toolchain.** Every release archive includes z3 4.16.0 at
  `libexec/z3` (static on Linux), with its license in `licenses/`, so refinement types
  are checked on a fresh install with nothing else to install. March looks for z3 in
  `MARCH_Z3`, then next to the running `march` (through forge's `~/.march/current`
  symlink), then on `PATH`. The pinned version lives in `z3.version`.
- **A warning when refinements could not be checked.** A program with refinements of its
  own gets one `solver_unavailable` warning when no z3 can be used (none found,
  `MARCH_Z3` pointing nowhere, a z3 that fails `--version`, or one that crashes or stops
  answering mid-run), with how to fix it; the build still succeeds. Under `cap verified`
  the error now says the solver could not be run. Another z3 version is used with a
  `solver_version_mismatch` warning. Both have `march --explain` pages.
- **`--refine-rlimit N` and `[refine] rlimit = N` in `forge.toml`** raise the per-query
  solver limit for a project with a known-hard proof. forge passes the setting to every
  `march` it runs.
- **Interface laws.** An interface can declare laws, written as `@[lemma]` signatures
  with no body (`@[lemma] fn combine_assoc(x : a, y : a, z : a) : {Unit | ...}`). The
  checker checks each law for every `impl`, using that impl's methods (and the
  interface's defaults): a proved law is silent, a broken one is an error with a
  counterexample, and one it cannot prove is `lemma_unproved` and is tested by
  `forge test`. An impl can supply a proof as a `@[lemma]` with the law's name. Impls in
  other files and methods that take `Unit` are covered. `forge test` runs a proved law
  compiled too, through the real impl. Laws never run in your program.

- **Lemma rewrites in the editor.** When a proved `@[lemma]` states an equation
  `lhs == rhs`, the language server offers a code action that rewrites an expression of
  the shape `lhs` into `rhs`, named after the lemma ("Rewrite to `Cons(1, zs)` (by the
  proved lemma `cat_nil`)"). Unproved lemmas offer nothing. Lemmas of imported project
  files and of the stdlib (listed in `stdlib/lemmas.verified`) are offered too, with their
  module's functions qualified.

- **Refinement proofs take decided steps (fuel).** The checker now expands a
  reflected call that another call's definition produces when its branch is already
  decided (its argument is a constructor, or known to equal one), up to a per-function
  fuel, default 2. So `len(cat([1], [2])) == 2` and `rev(rev(xs)) == xs` (with its
  lemmas, no intermediate `assert`s) now prove. `@[reflect(fuel: N)]` sets the fuel
  from 1 to 8, and `@[reflect]` asserts a function is reflected: the new error
  `invalid_reflect` names why when it is not. Some calls that used to be skipped as
  `reflect-fuel` are now proved or, where the contract is really broken, reported as
  violations.
- **Refinement proofs see through `List.filter` and `List.map` with a lambda.** A call
  of a function that takes a function, given a lambda or a reflected function's name,
  now has a definition of its own: the function's body with the lambda put in. So
  `fn pos(xs) = List.filter(xs, fn x -> x > 0)` is reflected, and
  `need_eq([1], List.filter([1], fn x -> x > 0))` proves. A lambda may read the
  caller's variables. `--reflect-report` lists the function taking functions as
  `specialised`, and `--reflect-parity` checks each such call against the
  interpreter. A `let`-bound lambda, a function parameter or a function returned by a
  call is not used this way.

- **Lemmas: `@[lemma]` proofs for refinement types.** A lemma states a theorem in its
  result type, `{Unit | P}`, and proves it with ordinary code: `match` and `if` for
  cases, a recursive call as the induction hypothesis, calls of other lemmas, and
  `assert` for intermediate steps. A proved lemma's theorem becomes a fact after each
  call, so `cat_nil(xs)` lets the checker know `cat(xs, Nil) == xs`. A lemma that does
  not prove gives no facts and draws `lemma_unproved`. Lemmas never run: every lemma
  and lemma call is removed before the program is built or interpreted, whether or not
  it was proved, so a program behaves exactly as it would without them. New
  diagnostics: `invalid_lemma`, `lemma_unproved`, `lemma_unproved_call`,
  `lemma_argument_impure`. The editor re-checks a file when a lemma it uses changes or
  stops proving, and shows a lemma's theorem on hover.

- **`forge test` tests lemmas.** Each project file with an `@[lemma]` is checked with
  the new `march --check --lemma-test`, which evaluates every lemma's theorem on
  generated inputs (boundary Ints and 100 draws from a fixed, printed seed). An unproved
  lemma becomes a property test: a false theorem prints a concrete counterexample and
  fails the run, and a true one reports "tested, not proved: N inputs". A proved lemma is
  checked again in the interpreter and in a compiled program; if it is false in either,
  that is a compiler or runtime bug, and the run fails.

- **Laws in `forge doc` and `forge search`.** A function's API page lists, under
  "Laws", the lemmas whose theorem calls it, with the theorem as written (march_doc).
  `forge search --law TEXT` finds lemmas by the text of their theorem or by a function
  they mention, and a name search for a function also finds the lemmas about it.

- **Parallel combinators reject closures that capture a native handle.** A
  lambda passed to `List.pmap`, `List.pfilter`, `List.preduce`, the
  `Parallel.*` family or `Task.async_stream` may no longer capture a
  `resource` value from an `extern` library, directly or inside a record,
  variant, list or tuple, since nothing says the C library is safe to call
  from several threads. The check follows the lambda through your own
  functions that pass it on, and reports at the function, naming the
  variable and the combinator (`portable_capture`). Create the handle inside
  the lambda, or use the sequential version. `task_spawn` and `Task.async`
  are unaffected.

### Changed

- **Int `/` and `%` are faster in compiled code.** The zero-divisor check is now a test in
  the generated code instead of a call into the runtime, so LLVM sees the division: a literal
  divisor becomes a multiply, and a divisor the code has already tested is not tested again.
  `bench/int_divmod.march` runs in 0.31 s instead of 0.56 s, `bench/index_loop.march` in
  0.49 s instead of 0.64 s. A zero divisor still panics with `division by zero` /
  `modulo by zero`.
- **A module that calls C without `needs IO.Foreign` no longer compiles.** `extern_needs_foreign`
  was a warning, so a dependency could reach C while `forge audit` and `forge.caps.lock` showed
  nothing for it. It is now an error with the same `needs IO.Foreign` fix (and
  `IO.Foreign.Blocking` for a `blocking fn`; `needs IO.Foreign` covers both). A module that
  already declares it is unaffected. Declaring only the block's own capability (`needs Ffi`,
  `needs LibC`) does not count: add `needs IO.Foreign` beside it. `Js.Dom`, `Js.Audio` and
  `Js.Canvas` now do.

- **Breaking:** the generated `@[endpoints]` entry points over a cluster node no longer take
  the root capability. `<P>_Run.cluster_<R>`, `offer_<R>`, `initiate_<R>`, `offer_hosted_<R>`
  and `cluster_hosted_<R>` take the node first: `Echo_Run.initiate_Client(node, body)`, where
  it was `(io, node, body)`. A role with a grant line (`role Ledger needs IO.FileWrite`) takes
  one capability per granted path after the node, which the caller supplies:
  `Checkout_Run.offer_Ledger(node, fw, 64, body)`. A caller holding `Cap(IO)` writes
  `cap_narrow(io)` there. To migrate, delete the first argument of each call, and add the
  granted capabilities after the node for a role that has a grant. A program that plays its
  roles over a cluster node therefore no longer needs `Cap(IO)` at all, and a topology pool
  derives the capabilities its code uses: the `ingress` pool of `examples/lab_app` went from
  `IO` to six narrow capabilities, none of them network or root. `run_<R>` and `host_<R>`,
  which open their own connections, are unchanged. The `SessionNode` functions under these
  (`run_cluster`, `offer_role`, `initiate`, `offer_hosted`, `start_offered_role` and the
  hosted forms) lose their `io` parameter the same way, and `ClusterNode.with_session(node,
  ops, body)` is the new operation they use.

- `Gen.one_of` shrinks toward its earlier alternatives (list the simplest generator first).
  The generated values are unchanged; only a failing property's shrunk counterexample can
  differ.

- Diagnostics: a `main` that performs IO without declaring a capability is now reported even
  when the program has another error, listed after that error, so both can be fixed in one pass.
  It used to stay hidden until the other error was fixed, then appear as a new error. The error
  corpus's fix check now accepts a program whose fixes clear every error that has one, when the
  errors left are the ones that offer no fix.

- Diagnostics: three errors now say exactly what to write. `role_grant_exceeded` gives the widened
  `role R needs ...` line and the body's new parameter list (each granted capability is one more
  body parameter, so adding to the grant alone left the program rejected). `division_by_zero` on a
  divisor that is not a parameter (a pattern binder or a `let`) suggests an `if d == 0 do ... else
  ... end` guard, which the checker accepts, instead of a parameter annotation that cannot apply.
  A step stranded after a `choose` branch that ends in a `loop` or `stop` (`protocol_invalid`)
  names the branches it can move into and how a several-step branch is laid out. New
  `march --explain` pages for `role_grant_exceeded` and `division_by_zero`.
- A run-time failure in an interpreted program (`march FILE`) is now reported in the
  compile-error style: what happened, the source line with a caret, then each call that led
  there as a labelled excerpt, innermost first. It replaces the `panic: ...` line and the
  numbered stack trace, for panics, `todo`, failed assertions and run-time errors such as
  division by zero. `MARCH_BACKTRACE=full` still adds the standard library's calls. The exit
  code is unchanged.
- A compiled program that stops on an unhandled panic or run-time error now prints a report in
  the same style in place of the single `panic: ...` line: what happened, the `panic` / `todo` /
  `unreachable` call's source line with a caret, then the functions it was reached through,
  each shown by its first line. A compiled program does not record the line of each call, and
  the report says so. Source lines are read from the path given at compile time; when the file
  is not there the report gives `file:line`. `MARCH_BACKTRACE=full` adds the standard library's
  functions. The exit code is unchanged. Scripts that matched `panic: ` in a compiled program's
  stderr need the new wording (`The program panicked: ...`).
- Diagnostics, four messages that cost a second round of fixing:
  - A syntax error in a program whose `main` prints with no `needs IO.Console` now says so in a
    note. The compiler cannot check capabilities until the program parses, so that error used
    to appear only after the syntax was fixed.
  - A protocol state that is never used says what its role must do next and which function
    takes that step; closing the conversation at the top of a protocol's `loop` says a
    repeating branch comes back there and how to go round again.
  - `may crash D` naming a role that is not in the protocol lists the protocol's roles, and a
    crash branch on a role not declared `may crash` says to remove the branch.
  - The guard a refinement error suggests for a `List` call uses `List.length(xs)`; it used
    to print `len(xs)`, the refinement measure, which is not a function.
- A failed `assert` outside a test prints its own report (the line and both operands), then
  what it was reached through. Interpreted, it used to print that report inside a second
  report's headline.
- An unsupervised actor whose handler fails under the interpreter is now reported: the actor,
  the message it was handling with its arguments, the failing line, and its state at the time.
  The interpreter used to drop such a crash without printing anything.

- Diagnostics: more choreography role-body mistakes are reported in protocol terms. A payload
  of the wrong type names the step and points at its line in the protocol. A body calling another
  role's functions says "`Fan_A.send_Number` is a step of role `A`, but `st` belongs to role `B`"
  (`protocol_wrong_role`) and names the step `B` takes instead. An offer with a branch callback
  left out lists the protocol's branches and the missing ones, and when the conversation ends
  after that branch, offers a fix that adds a callback closing it. A step on a state already
  closed reports only the reuse, saying the conversation was closed. Two steps one role takes
  under the same label are reported once per role, without follow-on errors from the generated
  code. 24 more protocol and session error codes have a `march --explain` page.

- Diagnostics: a session-channel call at the wrong step of its protocol reads in plain terms:
  "`Chan.send` can't send here: at this point the channel must receive an `Int`", with the steps
  left on the channel and a label on the protocol it follows, instead of "channel is at
  `Recv(Int, End)` but I expected `Send(T, ...)`". `march --explain session_state_mismatch` has a
  page.

- Diagnostics: linearity errors say where the value went. The label "`h` was already consumed
  here" now adds "in the `Some(v)` arm" or "in the `else` branch", plus "every arm consumes it" when
  all of them do. For a closure body it adds "inside a closure that can run more than once (each
  iteration consumes it)". A linear value consumed only on paths that end in `panic` is reported as
  "never used on a path that returns". A label points at the arm or branch that returns without
  consuming it. A value passed straight into an expression that failed to typecheck (`clsoe(c)`,
  `c.foo`) no longer gets a linearity error on top of the type error.
- Diagnostics: a choreography role body that takes a step out of order is reported in protocol
  terms (`protocol_step_order`): "Role `Cons` tries to choose `more` or `done` here, but at this
  point protocol `Stream` says it must receive an `Int` from `Prod`", with a label on that
  protocol step and the generated function that takes it, instead of a mismatch between two
  generated state names (`S_choose_more_done`, `S_recv_Msg_Prod_Cons_1`).

- Diagnostics: a protocol step that can never run, because it comes after a `loop`, is underlined
  itself, with a label on the loop, instead of the whole `protocol`. A receive from a role that
  `may crash` without an `or crash do ... end` branch now comes with a fix that inserts one, telling
  each remaining role from the detecting role.

- **`forge deploy hot` refuses a migration law it can't prove, instead of letting it through.**
  An unproved or unchecked law (a predicate the schema can't record, an `@invariant` outside
  the supported grammar, a baseline from a compiler older than the contract check) refuses the
  deploy, unless it is named with `--accept-unproved <Actor>.state`, `<Actor>.<Handler>` or
  `<Actor>`. A counterexample always refuses. A missing compiler (`MARCH_BIN`) is now a
  refusal, not a silent skip. An unsupported `@invariant` is recorded instead of dropped.

- Diagnostics: a call whose argument has the wrong type no longer makes every later use of its
  result fail too. `List.append([1, 2], ["a"])` reports `"a"` once; its result is no longer taken
  to be a `List(Int)` that the next line then misuses. A result the function declares outright,
  like `parse : String -> Option(Int)`, is kept, so its own checks still run.

- Diagnostics: a type mismatch inside a constructor or a list, tuple or record literal now points
  at the part that is wrong (`[1, 2, "three"]` underlines `"three"`, `Ok(string_to_int(s))`
  underlines `string_to_int(s)`) and names the path to it ("In a list element of the `ports`
  field of …"), instead of underlining the whole literal with "Argument to constructor `Cons`".

- Diagnostics: a lambda whose result is wrong is blamed at its body, not at the call it is passed
  to. `List.map(xs, fn x -> x + 1)` where a `List(String)` is expected now underlines `x + 1`
  and says `List.map`'s `b` is this function's result; a record or tuple result narrows to its
  wrong field or component.

- Diagnostics: an `if` or `match do` whose type is known (a declared return type, an annotated
  `let`, a parameter) blames the branch that disagrees with it. `if n >= 0 do "positive" else -1
  end` in a function returning `Int` now underlines `"positive"` ("In the `if` branch.") instead
  of the whole `if`, followed by a second error blaming `-1` for not matching it. An `else if`
  chain reads as one `if`, and a `match do` arm that disagrees with the first arm is underlined
  itself, with the two types the right way round. An operand of a binary operator is named as
  one ("This is the left side of `++`, which joins two `String`s.", "This is the right side of
  `+`, and both sides of `+` must have the same type.") instead of "argument #1 of a function
  call", with the other operand as the origin, and is reported before a mismatch on the whole
  expression that starts at the same place.

- Diagnostics: a type mismatch deep inside two types now reports the whole pair, with a note
  that prints the provided type and puts a caret under each part that differs, instead of
  naming only the innermost pair. Passing a `Result(List(Int), String)` for a
  `Result(List(String), String)` used to say "expected `String` but got `Int`" and suggest
  `int_to_string`; it now says "expected `Result(List(String), String)` but got
  `Result(List(Int), String)`" and marks the `Int`. Long types hide the parts that match
  (`{ ports : List(Int), … }`).

- **Refinement verdicts no longer depend on machine load.** Each z3 query runs under a
  fixed resource limit (`rlimit`: 3,000,000 steps, about four times the costliest proof in the
  corpus and stdlib, and 50,000 for stage-2 reflection queries) instead of a 3-second wall-clock
  timeout, after a reset, so the same query gets the same answer on every machine and
  platform. A 60-second backstop only catches a z3 that has stopped responding.
- **Refinement caches are keyed by the z3 version, the limits and the platform.** A z3
  upgrade or a new limit never replays an old verdict; entries written before this change
  are not used. An `unknown` from the limit is now cached like any other answer; a query
  z3 rejects never is.
- **CI uses the pinned z3 on every platform** (built from source and cached) instead of
  the package manager's, and a new `refine-agreement` job requires every refinement
  verdict to be the same on darwin-arm64, linux-x86_64 and linux-aarch64.
- Diagnostics: a rendered diagnostic's header names its category instead of a bare `ERROR`:
  `-- TYPE MISMATCH ----`, `-- CAPABILITY ----`, `-- PROTOCOL ----`, and for a warning or hint
  `-- WARNING: UNUSED ----` / `-- HINT: REFINEMENT ----`. `--check-json` objects gain a
  `category` field (existing fields unchanged). Errors found while expanding `derive`,
  `satisfy`, `@[endpoints]` and `@[remote]`, and the compiled backend's "interpreter-only"
  rejections, are no longer raw `file:line:col: error:` lines: they render like every other
  diagnostic (source excerpt, caret, code) and appear in `--check-json`. Messages follow one house
  style (backticks, capitalised, full sentences), checked by the error corpus; e.g. a handler that
  returns the wrong type now says "The handler for `Poke` in actor `A` must return the actor's
  new state, a `{ n : Int }`, but returns `Int`."
- Diagnostics: "did you mean" suggestions for an unknown constructor, actor message, variable or
  record field are ranked by type. A candidate that fits what the position needs (the actor of
  the pid in `send`, the annotated type, the field type) is shown alone, ahead of a closer
  spelling that doesn't: `send(a, Pokee(1))` now suggests only `Poke`, "a message of actor
  `A`", not `Post` and `Pong` from the HTTP modules. Stdlib constructors are offered only when
  nothing in your own code is in range, compiler-generated names (session states such as
  `S_end`) are never offered, and a misspelled record field gets a suggestion.
- Diagnostics: when no name is a spelling of an unknown function, the functions in scope that
  take the call's arguments are listed: `List.fodl(xs, 0, fn (a, b) -> a + b)` offers
  `List.fold_left` and `List.fold_right` with their signatures. A call whose arguments fit in
  another order says so, with the reordered call as a fix (`List.map(fn x -> x * 2, xs)`).
  A mismatch between two plain types with no hand-written hint names an in-scope conversion
  (`Use bool_to_string(x)…`, or your own `celsius_to_fahrenheit`). A call that fails
  `List.head`'s or `List.nth`'s precondition suggests `head_opt` / `nth_opt` with the `match`
  it needs. Suggestions never change type inference.
- Diagnostics: follow-on errors are dropped when another error already explains them: the type
  mismatch after a callback-arity error, "unused variable `x`" next to a misspelled use of `x`,
  `cap_grant` while the program has other errors, `cap_ceiling` alongside the matching
  `cap_needs`, duplicate reports, and the type and constructor errors that follow from an invalid
  protocol. The editor (LSP) drops the same ones.
- Diagnostics: a capability grant error (`cap_grant_exceeded`) now points at the call that needs
  the capability and labels each call on the way from `main`, instead of naming the chain in prose.
- Diagnostics: capability errors say what is wrong in capability terms. Passing one capability
  where another is needed (`Cap(IO.Console)` to a `Cap(IO.FileRead)` parameter) is a new
  `cap_mismatch` error ("`read` needs file-read access, but `c` is the console capability"),
  not a type mismatch, with one line placing the two in the lattice and a fix: `cap_narrow(c)`
  when the capability contains the one needed, otherwise a new `main` parameter passed to the
  call. A missing `needs` names the code and what it does ("the `Inc` handler of actor `Counter`
  prints", "the body of role `Cons` writes a file") and points at that call. One missing
  authority is one error: the `needs` error, `main`'s missing or too-narrow grant and the
  capability mismatch for the same capability merge, and the merged fix carries every edit
  (`--check-json` fixes may now be `{"kind":"multi","edits":[…]}`; `forge fix` and the editor
  apply them). `cap_grant_exceeded` and `role_grant_exceeded` gain fixes that add the capability.
- Diagnostics: `missing_impl` points at the operator or call that needs the implementation (`a < b`,
  `same(x, y)`) instead of the enclosing function, labels a generic function's `when Eq(a)` bound,
  and, for a type declared in the file, offers `derive Eq for T` (also `Ord`, `Show`, `Hash`) as a
  machine fix.
- Diagnostics: actor errors name actors, not their state records or generated message types:
  `send_wrong_actor` says "this pid is an actor `B`" and lists `B`'s messages; a wrong message
  payload says it is a message of actor `A` and points at the handler's parameter; a misspelt field
  in `{ state with … }` says it is `A`'s state and suggests the field (with a fix); a handler that
  does not return the state is reported in plain words, pointing at what it returns. A constructor
  shared by an actor message and another type no longer suggests the uncallable `A_Msg.X` spelling.
- Diagnostics: the rest of the actor checks follow the same style. `send_wrong_actor` says where
  the pid was spawned ("this pid is an actor `B` (spawned on line 24)") and labels that `spawn`.
  A missing codec for an `@[remote]` handler's payload is reported once, at the handler's
  annotation (`on Bump(h : Hit)`), instead of twice with no excerpt. `remote_actor_unroutable`
  points at the actor's name and labels each handler with why a remote message cannot reach it.
  `pid_serialize` names and labels the field holding the pid. A second handler for one message
  labels the first. A misspelt actor in `spawn` or in a supervise block reads "I don't know an
  actor called `Countr`. Did you mean `Counter`?", and a misspelt `strategy` lists the three it
  can be.
- Diagnostics: a missing JSON codec for `Node.send` / `Node.enqueue` gives its advice ("Add
  `derive Json for Ping` next to its declaration.") as a note, like the `@[remote]` case. A
  `migrate_state` / `migrate_msg` that does IO names the actor it migrates ("`counter_migrate_state`
  migrates actor `Counter`'s state, and `migrate_state` must be IO-free, …") and moves its advice
  to a note. A `spawn` whose argument count does not match the actor's `init` labels the `init`.
- Diagnostics: `role_grant_exceeded` points at the use and labels the callback and each call on
  the way, like `cap_grant_exceeded`; in a `cap no_panic` module, a panic reached through several
  of its functions is reported once, at the panic, with a label on each caller.
- Diagnostics: `overlapping_impl` no longer prints a garbage position (`<none>:29:266475457`) for a
  generated implementation, and is dropped when `json_derive_name_collision` already explains it.

### Documentation

- The Error Messages tour shows two more examples: a protocol step stranded after a `choose`
  branch that loops forever, and a division by a value from a pattern. The role-grant example
  explains its new help, and the error reference lists `protocol_invalid`,
  `protocol_same_participants`, `role_grant_exceeded` and `division_by_zero`.

- **The Type System chapter is restructured for first readers** ([Type System](docs/types.md)),
  like Pattern Matching, Interfaces and Capabilities: a plain opener, a which-type-do-I-need
  table, a how-it-fits table, a grouped index, everyday types before the advanced ones, and
  See also in place of Next Steps. It no longer says recursive functions need annotations;
  inference handles them.
- **Five more pages get the same first-reader layout:** [Module System](docs/modules.md),
  [Sigils & Templating](docs/sigils.md), [Foreign Function Interface](docs/ffi.md),
  [Stdlib Guide](docs/stdlib.md) and [Property Testing](docs/property-testing.md). Each
  has a plain opener, a which-form table, a how-it-fits table linking the related
  chapters, a grouped index with everyday sections first, Errors you'll see linking the
  Error Messages tour and `--explain` pages where they apply, and See also in place of
  Next Steps. Bodies are kept; the FFI page's first example now grants `main` the
  capabilities it uses, so it type-checks, and the Modules page no longer describes
  compiler internals or shows a stale error for a `ptype` constructor.
- **Removed pages.** The four 1.0 claim pages (`claim-deploys`, `claim-capabilities`,
  `claim-performance`, `claim-refinements`), the 0.3.0, 0.4.0 and 0.5.0 upgrade guides, and
  the Findings list on the [Multi-host Lab](docs/lab.md) page. Links to them are gone; the
  docs index links the 0.6.0 upgrade guide.
- **A scrolling explainer for distributed March**
  ([From a Protocol to a Cluster](docs/protocol-to-cluster.md)). It follows the lab app's
  16-line `Order` protocol a few lines at a time, then through the compiler (what the
  declaration rules out, and the five modules, 15 linear state types and 152 functions
  generated from it), into the Ledger actor, and onto a four-machine cluster that loses
  hosts and recovers. Each section has a pinned figure that changes as you scroll; the
  cluster and the actor are simulations, labelled as such. Every number, excerpt and
  compiler message on the page is generated by `scripts/gen-explainer-data.py` from the
  real compiler, and doc-lint fails if the lab app changes without a regeneration. A
  section on deploying to the running cluster is still to come.
- **A second scrolling explainer, on what a deploy is allowed to do**
  ([What a Deploy Is Allowed to Do](docs/deploy-authority.md)). It follows one dependency
  update to the lab app, a library that starts opening a socket, past each check that asks
  what code can reach: a module's `needs` lines, the grant on `main`, `forge deps` against
  the committed capability file, the capabilities the compiler derives for each pool of a
  topology, the generated firewall, `forge deploy hot`'s widening gate, and the node's own
  policy. The pinned figures are one square per module of the program, and an animated
  topology: roles placed on machines from the file, sessions flowing, a machine stopped,
  and a patch stopped at each gate. The topology is a simulation, labelled as one. Every
  count and tool message is generated by `scripts/gen-authority-data.py` from the real
  compiler and forge; the page says which one line it quotes from the reference instead.
- **A third scrolling explainer, on what one owner is worth**
  ([What One Owner Is Worth](docs/one-owner.md)). One 31-cell tree, transformed by
  ordinary functional code, followed four times through the question "is anyone else
  holding this?": reused in place with zero allocation when `inc_leaves(t)` is the last
  use; copied cell for cell when the old tree is read again, or kept in a Vault
  (`--why-copies` finds no copy there and the run copies anyway); its two halves
  rewritten on two tasks with no lock. Then the same question as a type: `linear` (exactly
  once) and `affine` (at most once), with the compiler's refusals for a second use and a
  forgotten value. Then the contract that keeps a function allocation-free: `@[no_alloc]`,
  its `transient` form, the boxed-aggregate case, the limit that a contract is about the
  function's own code and not its callers, and the designed, unshipped `@[alloc_bound(N)]`.
  The pinned figures are the heap (cells with their counts, a cursor walking them, a copy
  tree growing beside), a token moving through a linear function, and an allocation
  ledger. Every count comes from the runtime's own allocation trace and every message from
  the compiler, by `scripts/gen-ownership-data.py`.
- A new Error Messages tour (`/docs/error-messages/`): 34 real compiler errors, from syntax
  slips through types, capabilities, linearity, actors, session channels, protocols and
  refinements, each with what `march --check` prints today. An error playground on the page
  comes loaded with 26 of them: edit one and check it again in the browser. The live compiler
  bundle gains `marchCheck`, which prints a program's diagnostics as `march --check` does,
  without the refinement checks (they need z3).
- The language chapters now point at the Error Messages tour. Types, Capabilities, Linear Types,
  Actors, Session Types, Choreography and Refinement Types each end with an "Errors you'll see"
  list linking to the tour examples for that area, and each `/docs/errors/<code>/` page that
  has an example on the tour links to it under "See it in the error tour". Every tour example
  has its own anchor (`/docs/error-messages/#counterexample`).
- The Refinement Types chapter (`/docs/refinement-types/`) drops its dated "What's new" box. Its
  "When to use refinements" table now points at refinement messages, reflection, lemmas,
  relational element refinements, abstract refinements, fold invariants, termination (`cap total`)
  and `--refine-infer`, and "On this page" lists those sections too.
- A new Lemmas guide (`specs/lang/lemmas.md`, `/docs/lemmas/` on the site): writing `@[lemma]` proofs by induction,
  `assert` steps and fuel, using lemmas with refinements, and what `forge test`, `forge doc`,
  `forge search --law` and the editor do with them.
- `march --explain` pages for `cap_grant_exceeded`, `cap_ceiling`, `cap_widen`, `cap_deserialize`,
  `proof_cap_return`, `proof_cap_mint_private`, `io_not_allowed`, `send_wrong_actor`,
  `actor_handler_state_type` and `codec_missing`.
- `march --explain` pages for `spawn_not_actor` and `supervise_field_missing`.

- **Native compiles are about 45% faster for small programs.** Code the program
  cannot reach (most of the prepended stdlib) is now dropped right after
  defunctionalization instead of after the optimizer, so Perceus, drop, escape
  and the optimizer no longer run over ~9,000 unused functions. Programs are
  the same apart from some inlining choices, which now count only reachable
  callers. `--disable-pass dce-early` turns it off.
- **`--hot-reload` builds are about twice as fast.** A hot-reload server build
  now links the precompiled C runtime (only the four files that read its
  signing key and HCR identity are compiled per build), builds its HCR
  manifest once instead of twice, reuses typecheck's role-capability solve,
  and the refcount-inlining rewrite no longer allocates per character. The
  emitted program is unchanged.

### Fixed

- **Compiled `x +. 0.0` keeps the sign of zero right** (#1185). The optimizer rewrote
  `x +. 0.0` and `0.0 +. x` to `x`, so native and JS builds returned `-0.0` for
  `-0.0 +. 0.0`, where IEEE 754 (and the interpreter) give `+0.0`. The rewrite now fires
  only for `-0.0`, the real additive identity; `x -. 0.0` still simplifies and
  `x -. -0.0` no longer does.
- **`install.sh` verifies checksums with Apple's `/sbin/sha256sum`** (#1182). With it first
  on `PATH`, the `curl | sh` install failed at "Verifying checksum" on macOS, because
  Apple's `sha256sum -c` prints usage when the checklist comes on stdin without a `-`
  operand. The installer now passes `-`.
- **Compiled `==` and `!=` on records compare the right fields** ([#1171](https://github.com/march-language/march/issues/1171)).
  Every record type shared one native equality helper, built for whichever record was
  compared first, so another record type got wrong answers, read past the end of the record,
  or crashed with SIGSEGV. This also reached `eq()` on records nested in a record or a `List`.
  Each record type now gets its own helper. Tuples of different nested shapes, such as
  `((Int, Int), Int, Int)` and `((Int, Int, Int), Int)`, no longer share one either.
- **A module on `MARCH_LIB_PATH` is no longer loaded just because it declares a type or
  constructor with the same name as one your code uses from its own module.** A module
  that used its own `type Tally` pulled in every other lib-path module declaring a
  `Tally`, even ones nothing referenced, and an error in any of them failed the build
  (`--check`, `--compile` and the interpreter alike). A bare name used without being
  defined in the same module still loads the modules that define it (#1183).
- **`<`, `<=`, `>`, `>=` on a type with an `Ord` impl now use it in compiled code**
  (#1172). On an enum, record, payload ADT, newtype or unboxed ADT with a derived or
  hand-written `Ord`, and in generic `when Ord(a)` code, the operators mean
  `compare(a, b) <op> 0` on native and `--target js`, as they already did in the
  interpreter. Before, native strict comparisons were always false and `<=`/`>=`
  always true, a single-field newtype compared its raw payload, an all-scalar ADT
  such as `Pair(Int, Int)` failed the native build, and JS compared the objects.
  `compare` on `Int`, `Float` and `String` (and so a derived `Ord` over such
  fields) now also builds on `--target js`.

- **A line starting with `(` after a record, a `do ... end` block or an interpolated
  string is now a new statement** (#1179), as it already was after an identifier, `)`,
  `]` or a literal. Before, `let r = { x: 1 }` followed by a `(r.x + 1)` line parsed as
  a call on the record (`not_a_function`, then `unbound_variable` for `r`), and
  `let g = do ... end` followed by a `("x")` line silently called `g`.
- **`march fmt` and `forge format` no longer replace code with `...`** (#1174). A `match`
  or `match do` in a list, tuple, record, call argument, operand or string interpolation,
  a multi-statement lambda that is not the last argument, and an `if` with a
  multi-statement branch inside another expression were written out as `...`,
  `match ...` or `match do ... end`. They are now printed in full.
- **The formatter keeps the parentheses the grammar needs** (#1175). It dropped them
  around `if`, `match`, `fn` and `|>` operands, a called `(if ...)` or `(fn ...)`, the
  operand of `-` or `!`, and a comparison inside a comparison. The output either did
  not parse or meant something else: `1 + (3 |> double)` became `1 + 3 |> double`.
- **`march fmt`, `forge format` and the language server refuse output that changes the
  program.** The formatted text is parsed again and compared with the input. If it does
  not parse, or parses to a different program, the file is left unchanged and `march
  fmt` exits 1 with a message. The check found more formatter bugs, now fixed: UTF-8
  and `${` in strings, `\r` in multi-line strings, float literals with more than 12
  digits, default argument values, `resource`, `opaque type`, `blocking` and `raises`
  extern functions, `linear let`, `p as a as b`, an interface's `requires`, `use A`
  (printed as `import A`), and multi-line sigils, whose content was re-indented. Actor
  declarations with `supervise`, `mailbox`, `@compat`, `@invariant` or `@[remote]` are
  still not printed in full, so such files are now refused instead of losing those parts.
- Protocol `@[endpoints]` choices named `cancel` or `drain` no longer collide with
  generated failure-handler parameters; their offer functions typecheck normally.
- The two-node test harness now fails when a started node has no expected-output
  file, instead of silently reporting success.

- Functions over `Float`, `String`, records and tuples can now be used in proofs. Float
  operations stay unknown to the checker (nothing is concluded from NaN or `-0.0`); a string
  is known by its byte length, and distinct literals are distinct values; record field access,
  literals, updates and patterns, and tuple construction and patterns, all translate.
- **`--refine-infer` no longer skips programs that `--check` accepts.** A record named like a
  standard-library one (`type NodeInfo`, `type Member`) left a type error inside the
  standard library that `--check` never shows, and inference then printed only "skipped,
  the program has errors". Inference now stops on the errors `--check` stops on, and a skip
  names the first errors it stopped on.
- **`forge refine --infer` prints each proposal once.** When the project does not check as
  one unit, forge checks each file on its own and infers once over the files that check.
  Before, it inferred once per file and printed the same proposals for every file (30 times
  on a 31-file project).
- **Less `--refine-infer` noise.** A recursive group with nothing to infer near it is no longer
  noted `scc-unsupported`, and a field test such as `_.step != 0` is no longer tried on an
  `Int` or `List` value.
- **Two compiles of one project no longer risk a torn refinement verdict.** The verdict cache
  under `.march/cas/vc` wrote each entry in place, so a `march --check` reading an entry
  while another process wrote it could see half a counterexample. Entries are now written
  to a temporary file and renamed into place.
- **Compiled property tests that return `false` now fail.** `Check.all` in a compiled test
  (what `forge test` runs) treated a property that returned `false` as passing. Only a
  property that panicked or failed an `assert` was caught. Under `march test` it already
  failed. A compiled suite with such a property used to pass and now fails.
- **More function bodies can be used in proofs.** A `match` used as a value (an argument or an
  operand) is now unfolded. A divisor shown non-zero only by arithmetic, such as
  `b : {Int | b * b > 0}`, now counts. A step through `if pos(n) do … end`, where `pos` is your
  own function, is taken when the facts decide `pos(n)`.

- **The interpreter no longer runs another actor's message.** A variant, or another
  actor's message of the same name, sent to an actor ran that actor's handler under
  `march file.march`, while compiled code dropped it. The interpreter now drops it too,
  so a refined handler parameter holds in the handler body even when another actor or a
  type shares the message's name. Also, a dropped message no longer ends
  `run_until_idle()` early with later messages still queued.

- **An actor handler's fresh state literal uses its parameter refinements.** With
  `state { count : {Int | _ >= 0} }` and `on Bump(n : {Int | _ > 0})`, the result
  `{ count: state.count + n }` stayed unverified because the check at the handler's tail ran
  without `n > 0`. It now proves.
- **Lemmas can use functions that divide by a parameter, or that recurse by a metric.** A
  function with `a / b` or `a % b` is now unfolded in proofs when its own parameter refinements
  or conditions show `b` non-zero (`b : {Int | _ != 0}`, or `if b == 0 do 0 else a / b end`). A
  recursive function certified by `@[decreases]` is unfolded too.
- **`forge test` / `--lemma-test` decide theorems that use `len`.** They were `not-tested`
  with "unbound variable: len"; `len` now means a list's length or a string's byte length in
  the interpreter and in the compiled check.

- **A refined `Int` result now uses the facts before it.** `fn grow(n : {Int | _ >= 0}) :
  {Int | _ >= n}` used to stay unverified when its body was `let r = n + n` then `r`, or a
  lemma call `twice_grows(n)` then `twice(n)`, or `assert n >= 0` then `n + n`. The same facts
  already proved a call's precondition. The result is now checked with them, and a contract
  proved this way is a fact at the function's callers. Other refined result types don't use
  these facts yet.
- **Compiled test builds no longer crash on an actor whose handlers use a capability.** In a
  `--test` build (`forge test` compiled), an actor where one handler performs mockable IO and
  others don't could abort after a couple of messages with "RC underflow" or a SIGBUS. depot's
  connection `Pool` did, so every conduit test that reached Postgres crashed the run. Release
  builds were not affected.
- **`spawn` of something that is not an actor, and a supervise child line naming no actor or a
  missing state field, are compile errors.** `spawn(helper)` for a function, or `spawn(Job)` for
  a type's constructor, passed the checker and failed when compiled ("`helper_spawn` is not a
  function in scope") or at run time; a constructor with arguments was reported as a
  constructor-arity error. They are now `spawn_not_actor`, saying what the name is. A supervise
  block's `Wroker w` (no such actor) or `Worker wx` (no field `wx` in the supervisor's state)
  stopped the compiler with an internal error; the second is now `supervise_field_missing`, with
  a did-you-mean and a fix.
- **A lemma call gives its fact from anywhere it always runs.** A named `let u = l(..)`, a
  statement of a nested block, a tuple element or an earlier call's argument, or an `if`
  condition now give the theorem to what follows, as a call on its own line does. A call in a
  branch, a lambda, or on the right of `&&`/`||` still gives nothing outside it.
- **A user function or constructor named like a stdlib one works in a theorem.** A lemma
  about your own `fn unwrap` (the prelude has one) or over your own `Reply` constructor
  (`Channel.HandleResult` has one) was `unreflectable-predicate`; the call now resolves to
  your declaration, as the typechecker does. A user type named like a stdlib type (`Tree`)
  still can't be used, and the warning still says to rename it.
- **A reflected function whose `let` branches unfolds.** `let b = match l do ... end` (or an
  `if`) inside a function a theorem calls used to leave the function without equations; its
  body now unfolds once per case.
- **A lemma can use a hypothesis that calls your own function.** `fn h(g : {G | okz(_)}) :
  {Unit | okz(g)}` was `lemma_unproved`: a refined parameter whose predicate calls a reflected
  function was never assumed. It is now, in the theorem and for the recursive calls of an
  inductive proof, and a callee's `okz(_)` precondition reads the same as `okz(g)`.
- **`Random.range` (and so `Gen.int`) works for any span.** A range wider than the largest Int,
  such as `Gen.int(-4611686018427387903, 4611686018427387903)`, panicked with "attempt to
  subtract with overflow" since Int arithmetic began checking for overflow. A range wider
  than 2^52 never panicked but only produced values in its bottom 2^52. Both now draw
  uniformly over the whole span. Spans up to 2^52 give the same values for the same seed as before.
- **A hot deploy can no longer tighten an actor's contract unproved.** A state field's
  refinement, a handler parameter's and the `@invariant` were not part of the deploy schema
  (the refinements were erased, and an `@invariant` was only checked against a
  `migrate_state`). So a deploy that only strengthened one went through unchecked, and the
  new handlers' proofs rested on a fact the live actors didn't meet: a division "proved" safe
  by `count >= 1` could divide a live `count: 0`. The schema now records them, and
  `forge deploy hot` proves the running version's contracts imply the new ones, for the state
  (through `migrate_state`, or as it is when the fields are unchanged) and for each handler
  parameter. The `migrate_state` check itself now proves a correct migration and refutes a
  wrong one with a counterexample; before, it did neither, because the synthesised state type
  was ambiguous with the actor's own.

- A type variable in an error message no longer changes letter depending on whether the
  compiler's cache is warm (`Pid(b)` on a first run, `Pid(a)` after); each check now letters its
  variables from `a`.

- **Refinement proofs know that `x / -1` wraps at the smallest `Int`.** `-4611686018427387904 / -1`
  returns `-4611686018427387904` (the one place Int arithmetic still wraps), but the checker
  read it as `4611686018427387904`, so `need_pos(x / -1)` with `x < 0` (directly or through a
  reflected function) could be proved. The checker now reads `/` exactly as the program runs
  it. The reference explains why the other Int operators need no such care: since 0.7.0 they
  panic on overflow instead of returning a wrong value. A zero-argument function used as a
  constant in a predicate (`_ > limit()`) whose arithmetic overflows is no longer folded to
  the wrapped number: calling it panics, so it is not a constant.
- **Default methods work for an impl in another file.** When an `impl` lives in a
  different file from its interface, a method it takes from the interface's default was
  unbound at run time ("unbound variable: twice"). Defaults are now added once the whole
  program is loaded.
- **`use M.*` used only for an interface is no longer "unused".** An import whose only use
  is an `impl` of one of its interfaces, or a `when M(a)` constraint, drew
  `unused_import`. An import of an interface-only module that nothing uses is now
  reported.
- **A clearer warning when a type's name clashes with the stdlib's.** A function over a
  type such as `Tree`, which the stdlib's `OrderedMap` also declares, cannot be used in a
  refinement or lemma. The warning now says that and asks you to rename the type, instead
  of "not a measure or known predicate".
- **A refinement proof no longer reads `let k = f(k)` as an equation about the new `k`.**
  A `let` whose right-hand side used the name it rebinds (`let k = gt5(k)`, or a lambda
  reading `k`) gave the checker the fact `k == gt5(k)` about the new `k`, which could prove
  a false precondition. Such a `let` now gives no fact about the call.

- **A false lemma is an error, not a warning.** A lemma whose theorem is false at some
  input, such as `{Unit | n + n >= n}` at `n = -1`, was reported only as
  `lemma_unproved` unless the theorem was false at every input. The checker now runs the
  theorem on the solver's counterexample and, when it is false there, reports
  `refinement_violated` with that input.

- **`march test` with several files no longer leaks Vault state between them.** Named
  Vaults (and the Config values stored in them) lived for the whole process, so when one
  `march test` run covered several files, the stdlib's own `Vault` and `Config` doctests,
  which run once per file, saw counters and keys from the previous file and failed
  (`forge test --coverage` in a project with several test files). Each file now starts from
  a fresh interpreter runtime.

- **No more false refinement violations for container elements and passed functions.**
  When an element refinement could not be translated for the solver (for example one that
  calls an `@[opaque]` function), or when a proof stopped at a reflected call it did not
  expand, the checker could report `refinement_violated` with a made-up element value for a
  program that cannot fail. These are now reported as unverified (a skip), not violations.
- `march --check` no longer accepts a misspelled module whose member names a builtin
  (`Lsit.length(xs)`): it reports "Unknown module `Lsit`. Did you mean `List`?" instead of
  failing at run time.
- Diagnostics: the `List.filter(fn (x, y) -> …)` hint suggests a one-parameter function instead of
  a curried one; an infinite-type error no longer stacks contradictory notes; refinement errors on
  callbacks no longer show `$cb_arg`, and their guard suggestion uses the real argument.
- Diagnostics: a diagnostic's hints no longer repeat or contradict each other. A "consider
  narrowing `Cap(IO)`" hint no longer sits on an error at the same place (it contradicted
  `cap_needs`' "add `needs IO`"). An unproved lemma call is one warning, not a warning plus a hint
  saying the same thing. `send_wrong_actor` no longer restates its qualify-it advice as a note.
  `termination_unproved` no longer suggests the same exit twice, and names your own variable, not `n`.
- A parameter that only its refinement mentions (`fn f(t : {Tree | size(t) < 1})`) is no longer
  reported as unused, with a fix that broke the refinement.

- **`--target js` byte strings are fast in Safari.** Each byte access on a long string
  (`byte_at`, `byte_length`, `slice`) looked up its cached byte view by comparing strings
  with `===`, which JavaScriptCore does in time linear in the string's length, even for a
  string and itself. A game decoding a 3.5 MB world file never finished loading in
  Safari. The cache is now a `Map` keyed by the string, holding at most one string of
  each length so older V8 (which hashes long strings by length) doesn't compare them
  either.

### Documentation

- **Lemmas as a contract for changes.** The refinement-types chapter and the
  `march-lang`, `march-test` and `forge-search` agent skills explain how to state a law
  as a lemma in a `cap verified` module, where an unproved lemma is a build error, so a
  change that breaks the law fails the build.

## [0.7.0] - 2026-11-02

### Breaking changes

- **`Show`, `Eq`, `Ord` and `Hash` impls may not perform I/O.** The four built-in
  interfaces are bounded by `needs ()`, so a hand-written `show`, `eq`, `compare` or `hash`
  that prints, logs, reads the clock or reaches any other capability is rejected at the
  impl (`cap_bound`). Derived impls are unaffected, and no impl in the stdlib was. Move
  such work out of the impl.

- **Hot-reload ABI v5 requires a rebuilt base binary.** Per-frame routing and
  closure lifetime hooks are incompatible with older running servers. Forge
  refuses the patch before upload and explains the one-time restart requirement.

- **Int `+`, `-`, `*` and unary `-` panic on overflow instead of wrapping.** A result
  outside the 63-bit range [-2^62, 2^62) is now a runtime panic, `attempt to add with
  overflow` (or `subtract`/`multiply`/`negate`), with the same message in the
  interpreter, compiled code and `--target js`. Before, `int_max_value() + 1` was
  `int_min_value()`. A program that relied on wrapping (a hash, checksum or random-number
  mixer) must switch to the new `int_wrapping_add` / `int_wrapping_sub` /
  `int_wrapping_mul`. Derived `Hash` instances, the SIMD vector `Hash` impls and
  `Msgpack`'s int64 decoder already use them, so their results are unchanged. `/`,
  `int_abs`, `int_pow` and `int_shl` still wrap. The trap closes the refinement checker's
  overflow hole: it reasons about unbounded integers, so `x + 1 > x` "proved" even
  where `x + 1` wrapped negative. Measured cost, compiled `--opt 2`: see
  `specs/progress/2026-10-30-int-overflow-trap.md` (design decision 2026-09-29,
  `specs/plans/2026-09-28-road-to-1.0.md`).

- **`cap no_panic` now proves Int `+`, `-`, `*` and unary `-` cannot overflow.** Since
  those operators panic on overflow they are panic sites, and a `cap no_panic` module must
  show each one stays in [-2^62, 2^62) from refinements, guards and `let` values in scope
  (new error code `int_overflow`, with a value the checker could not rule out). Every Int
  the program holds counts as in range, so `x - 1` under `x >= 0` and `x + 1` under
  `x < n` pass; a bare `x + 1` on an unrefined `x` is now an error. Spell intended or
  externally bounded arithmetic with `int_wrapping_add` / `int_wrapping_sub` /
  `int_wrapping_mul`. Float arithmetic is not checked. The stdlib's one `cap no_panic`
  module, `JsonStream`, now spells its byte-offset and depth arithmetic that way (same
  results for any real input).

### Added

- **Per-function capability bounds.** A function header may declare `needs IO.Console`
  (or `needs ()`, the empty bound) after its return type. Everything the function reaches
  must be covered by the bound (`cap_bound`, naming the path), and the bound must lie
  within the module's `needs` (`cap_bound_needs`). Callers are unaffected; a callback the
  function is handed is charged to whoever supplies it, and a call to a function value
  taken from a record, list or ref is refused under a bound narrower than `IO`. Impl
  methods take bounds too. See the capabilities reference, "Per-function bounds".

- **Capability bounds on interface methods.** An interface method signature may declare
  `needs …` after its type (`fn get : a -> Int needs IO.FileRead`). Every impl of the
  method, in any module, and the interface's default body are checked against it
  (`cap_bound`, naming the interface); an impl may declare a narrower bound of its own but
  not a wider one (`cap_bound_iface`). The bound is never part of the method's type, so
  callers and `when` constraints declare nothing new. See the interfaces reference,
  "Capability bounds on methods".

- **`--reflection-parity`: check the refinement checker's reading of your functions.**
  `forge test --reflection-parity` (or `march --check --reflect-parity`) runs every
  reflected function both by its logic definition and in the interpreter, on generated
  inputs including the largest and smallest `Int`; a disagreement or a panic inside the
  function's domain fails the run, and boundary overflow is reported `overflow?`. A
  reflected function the net cannot compare is listed `not-compared` with the reason, and
  a file whose ordinary check fails is reported as a check failure, not a parity failure.
  A run that compared no input at all says `parity: NOTHING COMPARED`, and
  `forge test --reflection-parity` fails on it.
- **Logic hashes in `--dump-impl-hashes`.** A fourth column gives each reflected
  function's logic hash (`-` when not reflected); every solver query that used a
  definition names the hash in its cache key. `--reflect-deps` prints the hashes (and a
  contract hash for every function a file reaches in other files), and the language
  server (opt-in, `MARCH_LSP_REFINE=1`) uses them to re-check open files when a
  definition, a refinement contract or the reflectability of a function they rely on
  changes in another file.
- **A parameter refinement may call a reflected function** (`fn f(n : {Int | is_small(_)})`),
  and the function is still reflected.

- **Hot deploys report their running schema baseline.** Hot-reload binaries embed
  deterministic schemas and manifests, and the owner-only `SCHEMAS` query reports
  each actor's latest activated schema and release. `forge deploy hot` uses that
  baseline for the first deploy and warns when local `.prev` data is stale. Older
  servers require a saved baseline or explicit `--old-schemas`.
- **Hot reload retains routing versions for running frames and escaping closures.**
  Nested calls keep a compatible ABI through a coordinated upgrade. Actor mailbox
  boundaries admit new work to the new version; a nonreturning old frame can keep
  old versions alive and block further deployment when the version limit is reached.
  This requires HCR ABI v5 and a rebuilt base binary.

- **`String.fold_split` and `String.fold_split_ranges`: walk the fields of `split`
  without building the list.** `fold_split` hands each field to a callback, one at a
  time; `fold_split_ranges` hands over byte ranges and allocates nothing. On a
  150,000-field buffer, `fold_split` uses 4 MB where `split` uses 25 MB, and
  `fold_split_ranges` is also about 3x faster.
- **Refinement predicates can use your own functions.** A function that terminates
  structurally, has no effects, cannot fail and calls only such functions is *reflected*
  automatically: its body becomes its meaning in the logic. `if is_small(n) do
  need_small(n) end` now proves when `is_small(n)` is `n < 10`; a predicate may call a
  reflected function (`{Int | _ < inc(3)}`), and so may an argument or a `let` (`need(inc(1))`).
  Each call's definition is used once, at its arguments; an obligation that needs a second
  step is reported unverified with the new reason `reflect-fuel` (`reflect-budget` when a
  query has more than 32 reflected calls). A proof that used a definition says so in
  `--refine-report-sites=all` (`uses: is_small`). The standard library is reflected under
  the same rules. Phase 1a of `specs/2026-10-29-refinement-reflection-design.md`; see
  "Reflection: your functions in predicates" in the refinement-types reference.
- **`@[opaque]`** keeps a function's body out of the logic, so callers see only its
  declared contract. With `@[measure]` it is the error `reflect_conflict`; on a function
  that would not be reflected anyway it warns (`attribute_no_effect`).
- **`predicate_eq_structural` warning.** `==` in a refinement is structural equality; a
  predicate that uses it at a type with a hand-written `Eq` now says so.
- **The JS target (`--target js`) runs real programs: tail calls, native arrays,
  binary strings.** Self and mutual tail calls compile to loops, so deep recursion no
  longer overflows the stack. `NativeI32Arr`/`NativeU8Arr`/`NativeIntArr` are typed
  arrays with the native wrap and bounds behaviour (`set` updates in place, since RC
  is erased on JS). A `String` holding binary data keeps its exact bytes, and
  `byte_at`/`byte_length`/`slice`/`index_of` agree with native in O(1) per byte
  (`march_bytes_to_string` builds such strings from JS externs). `process_argv` returns
  Node's arguments. `march --target js -o dir/x.mjs` copies every module the output
  imports, including relative-path extern modules, into `dir/`. forge.toml
  `[package] js_entrypoint` names a separate entry file for `--target js` builds. See
  "Byte Strings" and "Int on the JS target" in
  `docs/specs/2026-06-21-march-js-backend-design.md`.
- **`--js-int-check`** (forge: `MARCH_JS_INT_CHECK=1 forge build --target js`) makes an
  Int `+ - *` result or literal outside ±(2^53 − 1) throw on the JS target, naming the
  function, to find code that needs more than 53 bits. Without it, Int `+ - *` keep the
  63-bit overflow check every backend has.
- **`int_wrapping_add(a, b)`, `int_wrapping_sub(a, b)`, `int_wrapping_mul(a, b)`:**
  explicit modulo-2^63 Int arithmetic, for code where overflow is intended (hashes,
  checksums, RNGs). `int_wrapping_add(int_max_value(), 1) == int_min_value()`.
- **`march --check --reflect-report`: which functions a predicate will be able to use.**
  One line per function of your code: `reflected`, or `no` with the first rule that
  blocks it and where (`R3:calls println (app.march:14:5)`, `R6:calls mid, which is not
  reflected`, `R4:division by b not proved`, …). This is phase 0 of refinement reflection
  (`specs/2026-10-29-refinement-reflection-design.md`): the report only, nothing uses
  reflection yet and no verdict changes. See "Which functions are reflected" in the
  refinement-types reference.
- **`--refine-report-sites=all`: every refinement obligation, any verdict.** One line per
  obligation (`proved`, `skip`, `violated`, `trusted`), with its site, kind, callee and
  predicate. The bare `--refine-report-sites` still lists only skips, unchanged.
- **`scripts/refine-oracle.sh monotone <dir>`.** A refinement-checker gate that allows
  proofs to be gained but never lost: it compares every obligation's verdict, by site,
  against a baseline over `test/native` and `stdlib`, fails on any proved obligation that
  is no longer proved or any site that appears or disappears, and lists new proofs, new
  violations and withdrawn violations for review.

- **`int_div_floor(a, b)` and `int_mod_floor(a, b)`: floor division and modulo.** The
  quotient rounds toward negative infinity and the remainder takes the divisor's sign, so
  `int_div_floor(-1, 86400)` is `-1` and `int_mod_floor(-1, 86400)` is `86399` (truncating
  `/` gives `0` and `-1`). A zero divisor panics like the other division builtins. In
  compiled code a positive literal divisor is emitted inline, not as a runtime call, so
  LLVM can strength-reduce it. `DateTime.from_timestamp` now uses them (design:
  `specs/2026-10-29-floor-division-and-const-divisors-design.md`).

- **`march --check --termination-report FILE`** prints one line per recursive function
  in your code, with how it recurses: structurally on a component, on an `Int` metric
  that a guard bounds (`fib`) or does not (`down(n - 1)` with an `n == 0` exit),
  lexicographically, through a lambda or a function value, or with no metric at all
  (`spin(n)`). It is a report only and changes no verdict. It is the first step of
  termination checking (`specs/2026-10-26-termination-checking-design.md`).
- **`@[decreases(e, ...)]`: a termination metric for a recursive function.** The checker
  proves with the solver that the metric stays at least 0 and falls at every recursive
  call (several components are compared left to right, as for Ackermann's
  `@[decreases(m, n)]`). An annotated function whose metric is not shown to fall gets a
  `termination_unproved` warning with a counterexample (`down(n - 1)` with an `n == 0`
  exit: `e.g. n = -1`), an error in a `cap verified` module. Unannotated recursion is
  never warned about; `--termination-report` checks it too, with the first `Int`
  parameter as the default metric (`fib` is `cert=metric`). A metric outside the
  fragment (a local, a `Float`, a bare list) is an `invalid_decreases` error.
  `--refine-report`'s `by kind:` line counts `termination` obligations when there are
  any. A proved metric licenses the induction hypothesis (next entry).
- **`march --refine-infer` (and `forge refine --infer`) now also proposes
  `@[decreases(...)]`** for a recursive function the checker could not show to
  terminate. It tries at most 8 candidate metrics per cycle (each `Int` parameter,
  `b - i` for a counter climbing to a bound, `len(xs)`, and pairs of those), and
  proposes one only when every recursive call proves it decreases:
  `fn up(n : Int) : Int do if n >= 100 do 0 else up(n + 1) end end` gets
  `@[decreases(100 - n)]`. `--refine-infer-apply` writes the attribute in front of the
  `fn` and re-checks; a metric for a local `fn` is shown but not written.
  `--termination-report` lists what the search found (`infer` lines), and an editor
  quick fix adds the metric a `termination_unproved` diagnostic names. A plain
  `--check` never searches.
- **An unknown function attribute is warned about** (`unknown_attribute`), with a
  did-you-mean: `@[decrease(n)]` used to be ignored in silence.
- **Refinements: a recursive function's return refinement can now use itself at its
  recursive calls (the induction hypothesis), when its recursion is proved to
  terminate.** `fn sum_to(n : {Int | _ >= 0}) : {Int | _ >= 0}` with body
  `if n == 0 do 0 else n + sum_to(n - 1) end` is proved, and so is a caller's
  `need_nn(sum_to(k))`; both used to be skipped. The hypothesis needs a `structural` or
  `metric` certificate for the cycle and for every recursive function it calls, and a
  recursive call whose preconditions are all proved. A cycle of several functions is
  accepted all together or not at all. A function that may never return
  (`fn loopy(x : Int) : {Int | _ < 0} do loopy(x) end`) gets no hypothesis, so its
  contract stays unproved. That includes a function that calls a diverging one through
  an `alias`, a `use` or `import`, an interface method's `impl` (including one a
  builtin runs: string interpolation `"${e}"`, `to_string` and `println` run `Show`,
  `to_json`/`from_json` the Json codecs, `own` the `Drop` impl) or a top-level `let`
  lambda, and one that calls a name the checker cannot resolve (listed on the
  `--termination-report`'s new `unresolved:` line). A `match` on a parameter after
  `let xs = Cons(0, xs)` (or any other rebinding of it) is not structural recursion. Data type returns (`{List(Int) | len(_) == n}`), element
  returns (`List({Int | _ > 0})`) and a local `fn`'s element return use it at a call to
  themselves. Separately, a call inside arithmetic in a return expression
  (`1 + len2(t)`) now carries the callee's proved contract, as a bare call or a
  `let`-bound one already did.
- **Refinements: a definer passed through to `Map.filter` proves its return.**
  `fn mfilt(m, keep : k -> v -> Bool[p], cmp) : Map(k[p], v[p]) do Map.filter(m, keep,
  cmp) end` is proved, and so are its callers' demands. The callee's `p` and the
  caller's `p` were confused because they are spelled the same.
- **Refinements: a two-argument lambda may capture the caller's variables.**
  `filt(a, fn (k, v) -> v > k + n)` gives a relation over the caller's `n`, read with
  `n`'s own refinement, as a one-argument lambda already could. A captured name that
  equals a parameter of the callee, or a slot binder, stays the caller's.
- **Refinements: a return that is a `let`-bound call is proved from the callee's
  return.** `let r = a(x)` then `r` (or `r + 1`) now proves `b`'s `{Int | _ > 0}`
  when `a`'s return is proved or `@[assume]`d, as the bare tail `a(x)` already did.
  Chains of such `let`s work. An unproved return, the function's own, or a cycle's
  is never used, and a binding is dropped when its name or a name its call mentions
  is rebound before the return.
- **Refinements: `--refine-infer` / `forge refine --infer` propose this month's
  shapes.** Inference now proposes the contracts the checker learned to prove in
  October:
  - a return relating the result to a parameter (`inc(x : Int) : {Int | _ > x}`, read
    off the body's tail);
  - two-argument abstract refinements (`keep : k -> v -> Bool[p]` with
    `Assoc(k[p], v[p])`);
  - a relation between two container slots that a caller demands
    (`Assoc({x : Int | true}, {y : Int | y > x})`);
  - each key and value slot of a `Map` (`Map(String, {Int | _ > 0})`);
  - `Deque.Deque(a[p])` for a filtering wrapper;
  - fold accumulators with a parameter or `0 - 1` initial value, or in a `fold_right`
    step.

  Fixed on the way, all inside inference:
  - every applied abstract (`Bool[p]`) proposal failed its own re-check and was
    reverted (exit 3);
  - relational candidates were never ordered weakest-first;
  - a slot's trivial `true` goal could make a vacuous proposal look useful.
  Plain `--check` is unchanged.
- **Refinements: `SortedSet.fold` and `OrderedMap.fold` carry accumulator invariants.**
  The parametricity check now matches a record-typed parameter (`{cmp: …, tree: …}`)
  field by field, so `need_nn(OrderedMap.fold(m, 0, fn (a, _k, _v) -> a + 1))` is proved
  (it was a `parametric-source-unproved` skip), as is a user fold over a record
  parameter. `OrderedMap.filter` still carries no entry fact: its public type is an
  anonymous record, which has no element slots.
- **Refinements: `Map`'s own functions keep a refined map's facts.** `Map.insert`,
  `get`, `get_or`, `remove`, `keys`, `values`, `merge`, `map_values` and `singleton`
  are annotated with their generic types, and an opaque container (`ptype` /
  `opaque type`) whose representation hides its parameters now counts as a source for
  the parametric element rule. So `need_vals(Map.insert(m, "b", 5, cmp))` with `m :
  Map(String, {Int | _ > 0})` is proved, `Map.insert(m, "b", 0, cmp)` is a skip, and
  `one_pos(Map.get(m, "a", cmp))` is proved. Nothing new is assumed: the bodies are
  checked parametric. A too-weak declared map through these functions is now reported
  like a too-weak list through `List.reverse` (a violation). `Map.empty()` is not a
  source yet.
- **Refinements: `HashMap.filter` keeps what its predicate says.** It is now
  `@[assume] fn filter(m : HashMap(k, v), pred : k -> v -> Bool[p]) : HashMap(k[p],
  v[p])`, the `Map.filter` recipe: `need_vals(HashMap.filter(m, fn _k -> fn v -> v >
  0))` against `HashMap(String, {Int | _ > 0})` is proved, as are key demands and a
  key/value relation; a weaker lambda is an `abstract-refinement-too-weak` skip. The
  entry fact is assumed (one `trusted` postcondition), and property tests in
  `test/stdlib/test_hash_map.march` check it at run time.
- **Refinements: `Map.filter` keeps what its predicate says.** `Map.filter(m, pred,
  cmp)` is now `pred : k -> v -> Bool[p]` returning `{Map(k[p], v[p]) | subset(keys(_),
  keys(m))}`, so `need_vals(Map.filter(m, fn _k -> fn v -> v > 0, cmp))` against
  `Map(String, {Int | _ > 0})` is proved, as are a key demand and a relation between
  key and value (`fn k -> fn v -> v > k` into `Map({x : Int | true}, {y : Int | y >
  x})`); a weaker lambda is an `abstract-refinement-too-weak` skip. The entry fact is
  ASSUMED, like every other `Map` contract: `@[assume]` on a function whose return
  has element refinements now assumes them (one `trusted` postcondition per entry in
  `--refine-report`, accepted under `cap verified`), and a property test in
  `test/stdlib/test_map.march` checks it at run time. The input map's own element
  facts are not carried through, and `Map`'s other functions (`insert`, `remove`,
  `get`, `merge`, `map_values`), `HashMap.filter` and `OrderedMap.filter` carry no
  element fact yet.
- **Refinements: two-argument abstract refinements.** A callback of two arguments
  can define an abstract refinement `p` of two, and the return can relate two
  sibling slots through it:
  `fn filt(a : Assoc(k, v), keep : k -> v -> Bool[p]) : Assoc(k[p], v[p])`, the
  shorthand for
  `keep : ({x : k | true}) -> ({y : v | true}) -> {Bool | _ == p(x, y)}` returning
  `Assoc({x : k | true}, {y : v | p(x, y)})` (both spellings are accepted; with a
  one-argument `p`, `Assoc(k[p], k[p])` is still two separate slot facts).
  The body proves the return (`keep(k, v)` is `p(k, v)`); at a call `p` is what the
  passed lambda, `let`-bound lambda, named predicate, or a callback parameter that
  itself defines a two-argument `p` computes, so
  `need_pos(filt(a, fn (_k, v) -> v > 0))` and
  `need_arel(filt(a, fn (k, v) -> v > k))` are proved and a weaker lambda is an
  `abstract-refinement-too-weak` skip. A parameter can carry the relation too, read
  at the call's actuals when it also names another parameter of the callee. A
  callback chain ending in a concrete `{Bool | _ == e}` is not a contract (nothing
  checks the callable passed for it yet), and a lambda that binds one name twice
  (`fn (x, x) -> …`, `fn k -> fn k -> …`) instantiates nothing.
  Malformed signatures are `abstract_refinement_misuse` errors: `p` applied to
  only some of the callback's arguments, `p` on a single slot (`Assoc(k, v[p])`,
  fix `Assoc(k[p], v[p])`; this includes `List(Int[p])` under
  `Int -> Int -> Bool[p]`, which used to apply `p` to the last argument only and
  was silently inert), one argument at two types, a container that is not
  entry-shaped, or one `p` at two arities. `(a, a) -> Bool[p]` stays a parse
  error, whose message now says the tuple is ONE argument and writes
  `a -> a -> Bool[p]`. See "Two arguments" under abstract refinements in the
  refinement types reference.
- **Refinements: relational element refinements.** A slot predicate may name a
  sibling slot's binder, relating the two components of every entry:
  `Assoc({x : Int | true}, {y : Int | y > x})` reads "each entry's value exceeds
  its key". A construction owes the relation once per entry
  (`need_arel(ACons(5, 2, ANil))` is a violation naming the entry `(5, 2)`), a
  `match` gives its binders the relation (`ACons(k, v, _) -> need_gt(k, v)` is
  proved), and a declared relation implies a demand on fewer slots
  (`Assoc({x : Int | x > 0}, {y : Int | y > x})` meets `Assoc(Int, {Int | _ > 0})`).
  Before, the sibling name was a free variable, which gave false violations
  (that projection, with `x = -1`) and undecided skips. A relation the checker
  cannot hold per entry (a constructor carrying one of the related values without
  the other, a container-typed slot, a slot inside a nested container) is warned
  `refinement_unchecked` and ignored. A relation does not flow through a
  polymorphic call (a recorded skip). See "Relational element refinements" in the
  refinement types reference.
- **`march --refine-infer` proposes every refinement the checker can verify,
  module-wide.** Beyond the sign contracts `--refine-suggest-all` proposes, it
  finds element refinements (`xs : List({Int | _ > 0})`, element and tuple
  returns), relational preconditions (`i : {Int | _ < n}`, taken from the demand a
  callee makes), abstract refinements for `filter`-shaped helpers
  (`pred : a -> Bool[p]` with `List(a[p])`, `Option(a[p])` or `partition`'s pair)
  and fold accumulator invariants. Candidates are mined from the program, every
  proposal is proved by the real checker and must help some caller, and a
  precondition that would break an existing caller is refused with that call.
  `--refine-infer-json` emits JSON v1. `--refine-infer-apply` writes the
  proposals, re-checks, and reverts everything (exit 3) if the result differs
  from the prediction; `--refine-infer-diff` previews them; `forge refine --infer
  [--diff|--apply]` runs it over the whole project as one checked unit, so a caller
  in another file counts, passes `--apply-public` / `--allow-caller-violations`
  through, and names every file it could not infer for (`--fixpoint` is now an
  alias). The editor offers
  "Infer refinements for `f`" / "in this file" with identical edits, and
  `--refine-report --refine-infer` adds the if-applied ledger line.
- **TLS uses post-quantum key exchange by default.** Every client and server context
  offers the hybrid X25519MLKEM768 first (classical X25519 / P-256 / P-384 / P-521 after
  it), so sessions with a peer that supports it are safe from record-now, decrypt-later
  attacks. Needs OpenSSL 3.5+ linked; an older OpenSSL keeps its default groups and
  handshakes still succeed. New: `Tls.negotiated_group(conn)`, `Tls.is_post_quantum(conn)`,
  `Tls.post_quantum_available()`, and `Tls.set_groups(ctx, groups)` to override the list
  (e.g. require post-quantum).
- **Post-quantum cryptography: `MlKem` (ML-KEM-768, FIPS 203) and `MlDsa` (ML-DSA-65,
  FIPS 204).** `MlKem.keypair()`, `encapsulate(pk)` -> `(ciphertext, shared_secret)` and
  `decapsulate(sk, ct)` give two parties a 32-byte secret no quantum computer is known to
  recover; `MlDsa.keypair()`, `sign(sk, msg)` (hedged), `sign_deterministic` and
  `verify(pk, msg, sig)` sign and check. Seeded variants (`keypair_from_seed`,
  `encapsulate_with_coins`) reproduce published vectors. Backed by the vendored, portable-C
  mlkem-native / mldsa-native (no OpenSSL needed); the compiled and interpreted backends run
  the same code, and the outputs match OpenSSL's byte for byte.
- `march --compile --static` builds a self-contained executable: on Linux a fully
  static binary that runs in a `scratch` image (musl hosts such as Alpine; refused on
  glibc), on macOS one that loads nothing outside `/usr/lib` and `/System`. A missing
  static library is an error naming the package to install, and the compiler checks
  the finished binary before keeping it. See "Static binaries" in the tooling docs,
  including how a static binary finds TLS certificates.
- **Refinements: a lambda passed for an abstract refinement may now have a real
  body.** `List.filter(ys, fn y -> is_pos(y) && y < 100)`, an `if` or a `match`
  on a Bool, `fn y -> gt(y, 0)` (a several-parameter helper with a proved
  `{Bool | _ == e}` return, its arguments substituted) and calls to `let`-bound
  lambdas are read as the exact predicate they compute, so
  `sum_pos(List.filter(ys, fn y -> is_pos(y) && y < 100))` is proved where it was
  an `abstract-refinement-uninstantiated` skip. A too-weak skip now prints what
  the lambda was read as (`` `fn y -> is_pos(y) || y < 100` (read as
  `y > 0 || y < 100`) ``), and a declined body names the construct it could not
  read. A helper with refined parameters is inlined only where those are proved
  at the call (`fn y -> y > 0 && weird(y)` is read; `fn y -> weird(y)` is not).
- **Refinements: every parameter of a multi-parameter lambda now gets its element
  fact.** `List.zip_with(xs, ys, fn (x, y) -> need_pos(x) + need_pos(y))` with
  both lists `List({Int | _ > 0})` is proved, as are
  `sum_pos(List.zip_with(xs, ys, fn (x, y) -> x + y))`,
  `List.fold_left(xs, 0, fn (acc, x) -> acc + need_pos(x))` and
  `List.sort_by(xs, fn (a, b) -> need_pos(a) < need_pos(b))`; before, only a
  one-parameter lambda received one and each of these was a skip (an error
  under `cap verified`). A fold's accumulator still gets no fact, a lambda with
  a refinement-annotated parameter gets none, and a fact naming one of the
  lambda's own parameters is not given.
- **Refinements: an abstract refinement may be negated and combined in an element
  slot.** `fn rej(xs : List(a), pred : a -> Bool[p]) : List({a | !p(_)})` (also
  spelled `not(p(_))`) is accepted where it was a hard
  `abstract_refinement_misuse` error, its body is checked, and
  `sum_nonpos(rej(ys, fn y -> y > 0))` is proved. A slot may combine `p(_)` with
  `&&`, `||`, `!` and ordinary predicates (`{String | p(_) && len(_) > 0}`), sit at
  a concrete base (`List(Int[p])` for `f : Int -> Bool[p]`), and an accumulator
  helper's own `acc : List(a[p])` parameter is now checked inside the definition
  that declares `p`.
- **Refinements: a scalar demand on a call that returns one of its own inputs is
  now checked through the callee's arguments.** `need_pos(Option.unwrap_or(o, 1))`
  with `o : Option({Int | _ > 0})` is proved: by parametricity the result is
  either an element of `o` or the default, and both are positive. The same holds
  for a nested call, `Option.unwrap_or_else(o, fn () -> 1)`, an element of a
  list literal, `List.fold_left(xs, 1, fn (acc, x) -> x)`, an annotated `let`,
  `need_pos(List.head(xs) + 1)` and a return tail
  (`fn f(o) : {Int | _ > 0} do Option.unwrap_or(o, 1) end`); each was an
  `unreflectable-subject` skip (an error under `cap verified`). An argument that
  fails the demand (`Option.unwrap_or(o, 0)`) is a `parametric-source-unproved`
  skip, never a violation, since whether it is returned depends on the data. A
  fold's accumulator still gets no fact, and a demand that names another
  parameter (`_ < len(xs)`) is not traced.
- **Refinements: a local `fn` with a container return now lends it to its later
  calls.** Inside a block, `fn two(n : {Int | _ > 0}) : List({Int | _ > 0}) do
  [n, n + 1] end` followed by `sum_pos(two(k))` is proved, as is a `let ys =
  two(k)` used later and a top-level function whose tail is the local's call:
  once every tail of the local is proved, its declared element refinement is a
  fact at each later call in the block (the same rule a top-level function
  follows). A local that is not proved, is shadowed by another of the same name,
  or whose return names a captured variable lends nothing. A local's scalar
  return tail (`fn f(p) : {Int | _ > 0} do Option.unwrap_or(p, 1) end`) is now
  checked through its sources, as a top-level one's is.
- **Refinements: `List.partition` carries its predicate into both halves.** It
  now declares `(List(a[p]), List({a | !p(_)}))`, proved on its own definition
  side, so after `let (pos, neg) = List.partition(ys, fn y -> y > 0)` both
  `sum_pos(pos)` and `sum_nonpos(neg)` are proved (a single-arm tuple `match`
  works the same way); before, each was an `unreflectable-subject` skip, an
  error under `cap verified`. Any function may declare a tuple of element-refined
  containers as its return: every tail is now checked component by component
  (such a return used to be accepted and never checked), and a destructured call
  to it carries each component's fact. Only `let`/single-arm `match`
  destructuring carries a component; `partition`'s behaviour is unchanged.
- **Refinements: a demand on a fold's result is checked as the accumulator's
  invariant.** `need_nn(List.fold_left(ys, 0, fn (acc, _x) -> acc + 1))` is
  proved: the initial value meets `_ >= 0`, and the step, assuming it of `acc`,
  keeps it. The same holds at a return tail (a running maximum
  `: {Int | _ >= 0}`), for `List.fold_right`, the curried `Enum.fold`,
  `Enum.reduce` (its elements are the base), a step using a refined capture or
  the element's own refinement, and any user-written function generic in its
  return variable with a callback that consumes it; each was a
  `parametric-source-unproved` skip (an error under `cap verified`). A failing
  half is a skip, never a violation, with its own reason:
  `accumulator-base-unproved` (`0` for `_ > 0`) or `accumulator-step-unproved`
  (`acc - x` for `_ >= 0`). A callee that can make a value of the variable
  itself, or is `@[trusted]`/`@[assume]` or an `impl` method, gets nothing. A
  relational return (`: {Int | _ >= lo}`) is not traced yet.
- **Refinements: a bare `filter(...)` and the `Enum`/`Iterable`/`Range` filters
  carry their predicate.** `Prelude.filter` (what a bare `filter` is),
  `Enum.filter`, `Enum.take_while` and `Iterable.filter` now declare
  `List(a[p])`, `Enum.find` and `Iterable.find` declare `Option(a[p])`, and
  `Range.filter` declares `f : Int -> Bool[p]` returning `List(Int[p])`, each
  proved on its own definition side. So `sum_pos(filter(ys, fn y -> y > 0))`
  and `one_pos(Enum.find(ys, fn y -> y > 0))` are proved where each was a
  `parametric-source-unproved` skip (an error under `cap verified`). The four
  rewritten filters keep their order and results; they now share
  `List.filter`'s single-pass body and run about 35% faster compiled.
- **Refinements: list-building fold accumulators.** An element demand on a
  fold's result is now the accumulator's invariant too:
  `sum_pos(List.fold_left(pos, [], fn (acc, x) -> Cons(x, acc)))` is proved
  (the initial `[]` meets `List({Int | _ > 0})`, and the step, assuming `acc`
  does, conses a positive `x` onto it), as are `List.fold_right`, the curried
  `Enum.fold`, a nested fold and a declared `List({Int | _ > 0})` return; each
  was an `unreflectable-subject` skip (an error under `cap verified`). It is not
  specific to folds: any call whose declared return is a bare type variable
  (`fn pick(c, x : b, y : b) : b`) is checked through its sources when its
  value must meet an element refinement. A step pushing an unrefined element
  is an `accumulator-step-unproved` skip, an initial list that fails it an
  `accumulator-base-unproved` skip. A curried step's inner parameter
  (`fn a -> fn x -> …`) now gets its element refinement while the step is
  checked, so `need_pos(Enum.fold(pos, 1, fn a -> fn x -> a + x))` is proved.
- **Refinements: an annotated fold accumulator is checked, assumed and
  carried.** `List.fold_left(ys, 1, fn (acc : {Int | _ > 0}, _x) -> acc + 1)`
  states the invariant: the annotation is now an obligation of its own (the
  initial value must meet it, and the step must keep it given an accumulator
  that does), and when it holds `acc` assumes it inside the step and the call's
  result carries it, so `let s = List.fold_left(…)` then `need_pos(s)` is
  proved with no demand on the call. Before, the annotation was silently
  neither checked nor assumed. A failing initial value or step is an
  `accumulator-base-unproved` / `accumulator-step-unproved` skip (never a
  violation; an error under `cap verified`), and the annotation is then not
  assumed. A `cap verified` module with an annotated accumulator that does not
  hold, and no demand on the fold, used to be accepted and is now rejected.
  Same parametricity gates as the demand rule; a one-parameter lambda keeps
  the pass-site check, and an annotation on the element parameter is still
  neither checked nor assumed.
- **Refinements: element refinements see into `List(a)` (and other container)
  constructor fields, and `Deque.filter` carries its predicate.** In
  `type Dq(a) = Dq(Int, List(a), List(a))`, `Dq(1, [0 - 1], [])` against
  `Dq({Int | _ > 0})` is now a refinement violation (it was an
  `unreflectable-subject` skip), a positive construction is proved, and
  `match d do Dq(_, f, b) -> …` gives `f` and `b` the element refinement. The
  same holds for a field `Option(a)`, `Result(a, Int)` or any other variant
  type whose arguments are bare parameters. `Deque.filter` now declares
  `pred : a -> Bool[p]` and returns `Deque(a[p])`, so
  `sum_pos(Deque.to_list(Deque.filter(d, fn y -> y > 0)))` is proved where it was
  a `parametric-source-unproved` skip. It filters the deque's two lists in
  place instead of rebuilding it from a list: same elements, same order, about
  2x faster compiled. A field that holds a parameter any other way
  (`List(List(a))`, `List((k, v))`, `Int -> a`) is still a recorded skip.
- **Refinements: a container return that names a parameter is a fact at the
  call.** `fn below(n : Int) : List({Int | _ < n})`, once its tails are proved,
  carries `_ < 10` at `below(10)` and `_ < k` at `below(k)`, so
  `sum_small(below(10))` (or `let ys = below(k)` with `k : {Int | _ <= 10}`) is
  proved, and `sum_lt5(below(10))` is a violation; before, every such call was an
  `unreflectable-subject` skip, an error under `cap verified`. Only variables,
  literals and linear arithmetic over them are substituted, and a stored fact is
  dropped when a name it mentions is rebound. A recursive call is read at its own
  arguments (`clamp(t, n)` inside `fn clamp(xs, n) : List({Int | _ <= n})`), and
  tuple components and block-level `fn`s whose return names only their own
  parameters work the same way. A call whose fact names a caller variable that
  nothing constrains (`sum_small(below(n))`, `n : Int`) is a skip, not a
  violation.
- **Refinements: the collection folds carry the accumulator invariant.** A
  demand on the result of `Map.fold`, `Set.fold`, `HashMap.fold`,
  `Array.fold_left`, `RRB.fold`, `RRB.fold_left`, `Deque.fold_left` or
  `Deque.fold_right` is now checked as the accumulator's invariant, as for
  `List.fold_left`: `need_nn(Map.fold(m, 0, fn (acc, _k, _v) -> acc + 1))` is
  proved (it was an `unreflectable-subject` or `parametric-source-unproved`
  skip, an error under `cap verified`), and a step that can break the demand is
  an `accumulator-step-unproved` skip. `NativeArray`'s and `Seq`'s folds stay
  skips, as do `SortedSet.fold` and `OrderedMap.fold` for now (their record-typed
  collection parameter is not yet seen through).
- **Refinements: `Hamt.fold`, `Enum.scan` and `Queue` now carry what the checker
  can prove through them.** Their signatures were unannotated, so no demand
  could pass through them; they now declare the types they already had.
  `need_nn(Hamt.fold(h, 0, fn acc -> fn _k -> fn _v -> acc + 1))` and
  `sum_nn(Enum.scan(ys, 0, fn acc -> fn _x -> acc + 1))` are proved as
  accumulator invariants, and a queue built from a refined list keeps its
  elements' refinement through `to_list`, `peek_front`, `peek_back`,
  `push_back` and `push_front` (`sum_pos(Queue.to_list(Queue.from_list(pos)))`
  is proved). Each was a skip before (an error under `cap verified`). Not yet:
  a parameter typed `Queue.Queue({Int | _ > 0})` or `Deque.Deque(…)` gives no
  element fact.

### Changed

- **Hot reload refuses a patch that changes a reflected function's body when a proof used
  it**: a caller's precondition was discharged by unfolding that body. Redeploy with a
  restart, or mark the function `@[opaque]`. A reflected function no proof unfolded can
  still be hot-patched.

- **`@[measure]` now insists on reflection, and follows calls.** A `@[measure]` that is not
  reflected is the error `invalid_measure`, naming the first reason, including through a
  function it calls (a measure whose `Nil` arm calls a function that prints, panics or
  loops was accepted before). Measures with several parameters, or with a `Bool` or list
  result, are now accepted and reflected; one-parameter `Int` and set measures keep their
  axioms exactly as before. A Bool measure discharges (it used to skip every use).

- **JS output computes compound values as statements.** A `let` bound to a match or a
  let chain, and a match arm that binds, used to become an immediately invoked closure
  per expression; they are now plain statements assigning the result. Herald's renderer
  runs about 3× faster on the JS target (Eclipse: ~90 ms to ~29 ms a frame).

- **Termination: `@[diverges]`, actor handlers and `cap total`.** Mark a function meant
  to run for ever `@[diverges]` (an accept loop, a frame reader, a ticker): it files no
  termination obligation, never gets the induction hypothesis, and neither does a cycle
  that reaches it; `--termination-report` lists it as `cert=diverges` and lists the
  callers that may diverge through it, which do not have to repeat the attribute.
  `@[diverges]` together with `@[decreases]` or `@[measure]`, or a measure calling a
  `@[diverges]` function, is a `diverges_conflict` error. The report also names an actor
  handler that may not return for a message (`handler Counter.Spin may not return`);
  `send(self(), …)` is not recursion. A module that declares the new `cap total` must
  prove every function terminates (`main` and `@[diverges]` functions exempt): anything
  else is a `termination_unproved` error, including a function in a recursive cycle with
  a `@[diverges]` one that is not marked itself, and a call on a known type
  (`"${Box(n)}"`, `show(Box(n))`) whose `impl` may not terminate. The standard library's 23 event loops
  (`ClusterNode`, `NetKernel`, `NodeCall`, `PeerReader`, `Csv`, `File`, `SessionNode`,
  `Topology`, …) carry `@[diverges]`, and a test keeps new ones from landing unmarked.
  `termination_unproved` on an `n == 0` exit with a negative counterexample now notes
  the `n <= 0` repair, which the editor offers when asked (it changes what the program
  does, so it is not a machine fix and `forge fix` never applies it), plus "mark
  `@[diverges]`".

- **Refinements: the `@[measure]` termination check now covers mutual recursion.** Two
  measures that call each other in a cycle, `ma(Z) -> mb(Z) -> ma(Z) + 1`, were accepted,
  because only a measure's calls to itself were checked. They are now `invalid_measure`
  unless every call in the cycle passes a component of a parameter of one type, or of
  types defined in terms of each other.
  `--termination-report` gains a certificate column (`cert=structural` or
  `cert=unproved:<reason>`), and it lists a function that calls a value of a non-positive
  type such as `type Fix = Fix(Fix -> Int)`.
- A parameter list or pattern that binds the same name twice is now a compile
  error (`duplicate_binder`): `fn (a, a) -> …`, `fn two(a, a)`, a multi-head clause
  such as `fn pick(0, a, a)`, and patterns like `(a, a)` or `Pair(x, x)`. Such
  programs used to be accepted, and the interpreter and compiled code disagreed
  about which value the name meant (`fn (a, a) -> a` applied to `(1, 2)` gave `1`
  interpreted and `2` compiled). Rename one binder or use `_`; to match equal values,
  bind two names and compare them in a `when` guard. Shadowing across scopes
  (`fn a -> fn a -> a`, a match arm rebinding a parameter) is unchanged.
  `march --explain duplicate_binder` has the details.
- A compiled program that uses `Compress.Zstd` or `Compress.Brotli` on a build host
  without that library now fails to compile with a message naming the package to
  install, instead of building a binary whose codec returns `Err("... not available")`
  at run time. Each codec is linked only when the program uses it, so a gzip program
  loads zlib alone.
- A compiled program now loads OpenSSL only when it uses TLS, and zlib/zstd/brotli
  only when it uses `Compress`: a hello-world depends on libc alone, where it used to
  need six libraries. `--hot-reload` builds still link the whole runtime.
- `SessionNode.run_cluster` and `SessionNode.run_cluster_hosted` take a `fingerprint`
  argument after `session` (the generated `cluster_<Role>` runners pass the
  protocol's); pass `""` to check nothing.
- **Stdlib: the collection folds declare their types.** `Map.fold(m : Map(k, v),
  acc : b, f : b -> k -> v -> b) : b`, likewise `HashMap.fold`; `Set.fold(s :
  Set(a), acc : b, f : b -> a -> b) : b`; `Array.fold_left(v : PVec(a), acc : b,
  f : b -> a -> b) : b`; and the callback of `RRB.fold` / `RRB.fold_left` (`f : b
  -> a -> b`), `Deque.fold_left` (`f : b -> a -> b`) and `Deque.fold_right` (`f :
  a -> b -> b`), which were unannotated. These are the types the folds already
  inferred, so well-typed callers are unaffected and nothing runs differently.

### Fixed

- **An impl method in a nested module was charged nothing for the helpers it calls.**
  The capability checks (the module ceiling, `main`'s grant, per-function bounds) resolved
  a local reference from an impl method or interface default body against the wrong
  scope, so in `mod B`, an `impl Show(T)` whose `show` called a `pfn log` that prints was
  not charged `log`'s `IO.Console`. It is now.

- **A type of yours with a constructor named like another type's no longer breaks
  refinement checking of that other type.** Declaring, say, `type Mb = Some(Int) |
  None` used to make the refinement checker model every built-in `Option` value with
  an `Int` payload, so checks involving `Option` were skipped, and the standard
  `Option` functions were never unfolded in such a program. Each type now keeps its
  own constructors; a `Some(…)`, a `match` arm or an `is_Some(x)` refers to the
  constructor of the type the checker knows the value has, and is skipped (never
  guessed) when that type is not known. Because the typechecker currently treats two
  types of the same name in different modules as one type, the checker also skips
  constructor facts about any type whose name another module (or a built-in type)
  shares; several such facts used to be "proved" although the program could violate
  them at run time.
- **A `refinement_unverified` hint re-labelled `reflect-fuel` or `reflect-budget` now
  names that reason** instead of the first attempt's.
- **`cap no_panic` accepted a division by a `let` that rebinds its own name.** In
  `let d = d - 1` followed by `10 / d`, the checker read the binding as the equation
  `d = d - 1`, which no integer satisfies, so `d != 0` was vacuously proved and the
  division by zero at `d = 1` went unreported. A `let` whose right-hand side names
  the variable it binds, or names a variable rebound later, is no longer used as an
  equation.

- **The refinement checker sent `-2^62` to Z3 as `+2^62`.** An Int literal equal to
  `int_min_value()` was printed `(- -4611686018427387904)`, because negating it in the
  compiler wrapped back to itself; Z3 read that as 2^62. Any VC mentioning the literal
  got the wrong number, which could make its assumptions contradictory and its goal
  vacuously proved.

- Generated topology offers select the accepting work's compatible version before
  creating a session endpoint. Saved user closures and running sessions retain their
  original versions; incompatible captured layouts produce a restart diagnostic.
- `--compile-so` again writes and restores manifest/schema sidecars when used without
  `--hot-reload`, including Forge's entry-file discovery builds.
- Hot-deploy restart replay preserves complete migration chains and their helper
  versions, so baseline-initialized actors can cross multiple state changes safely.
  An invalid saved dependency refuses its batch and dependent suffix. Signed rollback
  with a reverse state migration is covered by an end-to-end continuity test.
- A migrated actor's graceful shutdown uses its current-version `on_stop`, including
  callback-only hot patches. A state-changing activation without a compatible
  replacement callback is refused.
- Sandboxed hot-reload builds diagnose a missing `IO.FileWrite` grant. Reload storage
  remains subject to the existing OS filter; read-only queries remain available.
- Hot-deploy persistence failures detected before publication leave code and schemas
  unchanged. An unexpected persistence commit failure after publication stops the
  process with a diagnostic rather than acknowledging an undurable deployment.

- In the interpreter (and so in `march test` and the REPL), `String.split` with a
  repeating multi-byte separator returned the wrong fields: `String.split(",,,,",
  ",,")` gave `["", ",,"]` instead of `["", "", ""]`, which compiled code already
  returned.
- **`println` and `print` write a string's bytes on the JS target.** Under Node a string
  holding binary data (raw bytes) printed each byte's UTF-8 encoding; it now writes the
  bytes, as natively. `march_string_bytes(s)` (exported by `march_runtime.mjs`) gives an
  extern a String's bytes as a `Uint8Array`.
- **Matching a tuple of strings against literals works on the JS target.** A tuple
  field's type is erased there, so `match (model, view) do ("bulwark", 0) -> … end`
  switched on the string's (absent) constructor tag and never matched.
- **On the JS target a `let` local named like a module function is the local.** It was
  emitted as that function's closure (`{ o with x: px }` stored a closure when the module
  also had `fn px`).
- **Bytes built from byte values are those bytes on the JS target.** `Bytes.from_list` and
  `Bytes.from_hex` with bytes ≥ 0x80 (via `byte_to_char`) gave each byte's UTF-8 encoding,
  shifting every later byte offset (Herald's font data drew glyphs a pixel off).
- **`let x = match t do (a, _) -> a end` on a tuple works on the JS target.** The
  compiler's non-exhaustive default was emitted after the tuple's one branch and
  overwrote `x` with a "non-exhaustive pattern match" throw.
- **A JS build ignores another module's `main`.** `--target js` now emits only what the
  entry's own `main` reaches, so a library module with its own `main` (a game's desktop
  entry beside its browser one) no longer fails the build with "extern ... cannot be
  called on the JavaScript target".
- **A module with JS-module externs compiles natively.** An `extern "./x.mjs"` block gave
  its functions native symbols like `./x.mjs_fn`, so any native build that loaded the
  module (say, a library's browser backend) failed in clang even when nothing called them.
- Every `march --compile` on a musl host (Alpine) failed since 2026-10-12: the
  runtime's scheduler included `<execinfo.h>`, which musl does not have. It is now
  guarded as the rest of the runtime guards it (no symbolised fatal-fault frames on
  musl).
- **A record or variant whose only refinements are on container elements is now
  checked when it is built.** With `type Box = { n : Int, xs : List({Int | _ > 0}) }`,
  `{ n: 10, xs: [0 - 5] }` was accepted with no obligation at all, even under
  `cap verified`, because a constructor was only checked when some field had a
  refinement of its own (`n : {Int | _ > 0}`). A record literal, a `{ r with … }`
  update and a variant application such as `W([0 - 5])` for
  `type W = W(List({Int | _ > 0}))` now check every element slot (`List`, `Option`,
  `Map` values, nested lists). A bad element is a refinement violation, or a recorded
  skip (an error under `cap verified`) where the checker cannot decide it, such as a
  value passed through a generic call like `Map.singleton`. A slot that names another
  field (`xs : List({Int | _ < n})`) stays a recorded skip. The same holds for an
  actor message: `on Push(xs : List({Int | _ > 0}))` let the handler body rely on
  `xs`'s elements while `Push([0 - 1])` was never checked; that construction is now
  a violation. An actor `init` state literal whose field set another record shares
  now has its element slots checked as well.

- **`List.range_step` with a zero step no longer hangs.** `List.range_step(5, 0, 0)`
  recursed on the same value forever (interpreted and compiled); with `start <= stop`
  it returned `[]`. `step` is now `{Int | _ != 0}`, so a literal zero is a compile-time
  refinement error, and a zero the checker cannot see panics with
  `List.range_step: step must be non-zero`, as `Range.new_step` already did.

- **`Range.to_list` and `Range.each` with a zero step no longer hang.** A range is a
  plain record, so `{start: 5, stop: 0, step: 0}` bypassed `Range.new_step`'s check and
  the walk never advanced. Every Range function that walks a range (`to_list`, `each`,
  `map`, `filter`, `reduce`, `reverse`, `all`, `any`, `sum`) now takes
  `{v : IntRange | v.step != 0}` (`Range.IntRange` is the new name for the
  `{start, stop, step}` record; records are structural, so literals still fit), and
  `to_list`/`each` panic with `Range.to_list: step must be non-zero` /
  `Range.each: step must be non-zero` for a zero the checker cannot see.
  `Range.new` and `Range.new_step` return that refined type, so
  `Range.to_list(Range.new_step(3, 0, -1))` is proved.

- **`Control.chunks` with a size of 0 or less no longer hangs.** `Control.chunks(hex, 0)`
  never advanced its offset and a negative size walked it backwards, both forever.
  `size` is now `{Int | _ > 0}` (as `List.chunks` already was), and a size the checker
  cannot see panics with `Control.chunks: size must be positive`. This includes an
  empty artifact with a size of 0, which used to come back as one empty chunk.

- **`List.chunks` with a size of 0 or less no longer hangs.** It already had
  `size : {Int | _ > 0}`, so a literal 0 was a compile-time error, but a size the checker
  could not see made `split_at(lst, 0)` return the same list forever. It now panics with
  `List.chunks: size must be positive`, including on an empty list.

- **`Duration.format` of the smallest Int no longer recurses forever.** A negative
  duration was formatted as `"-" ++ format(Duration(-ms))`, and `-ms` of the smallest
  Int is itself, so it looped interpreted and overflowed the stack (SIGBUS) compiled.
  It now splits the value into seconds and milliseconds before negating, so every
  Int formats exactly: `Duration.milliseconds(-4611686018427387904)` is
  `"-7625142226 weeks, 1 day, 15 hours, 36 minutes, 27 seconds, 904 milliseconds"`.
  Output for every other value is unchanged.

- **Refinements: a value-creating function used as a value no longer counts as
  parametric (a false proof).** The check that a generic function cannot make a value
  of its type variable looked only at what it CALLS, so a function that creates one
  (an interface method `fn dflt : Int -> t`, a decoder, an extern) went unnoticed when
  it was passed as an argument, `let`-bound, or stored in a record. For example,
  `fn sneak(xs : List(v), _d : v) : List(v) do Cons(apply1(dflt, 1), xs) end` was proved
  to keep a `List({Int | _ > 0})` positive while running it put `-5` in the list. Every
  name a body mentions is now checked. No standard-library or test-corpus proof was
  lost.
- **Refinements: a `let`-bound list literal keeps its length.** `let t = [1, 2, 3]`
  then `List.head(t)` or `Stats.mean(t)` was an `unconstrained-subject` skip while
  `List.head([1, 2, 3])` proved; the binding now records `len(t) == 3` (any
  Cons/Nil chain ending in `Nil`, `[]` included), retired when `t` is rebound. This
  was half the user-code skips in a 67-program corpus sweep
  (`examples/stats_basic.march`).
- **Refinements: `Cons(h, t)` is known to be one longer than `t`.** `need_ne(Cons(x,
  t))`, `let ys = Cons(x, t)` then `need_ne(ys)`, and `List.nth`'s own recursive call
  `nth(t, n - 1)` inside a `Cons(h, t)` arm were skipped; `len`'s defining equation
  now applies at call arguments, `let`s and `match` arms, and all three prove. The
  one skip inside `stdlib/list.march` is gone.
- **Refinements: an `elts && len` list return is lent whole.** A function proved to
  return `{List(a) | subset(elts(_), elts(xs)) && len(_) == len(xs)}` gave a direct
  caller neither half: the call site translated the conjunction for one measure and
  dropped all of it. Each proved conjunct is now lent on its own.
- **Refinements: `List.length(e)` as an argument or a `let` means `len(e)`.** The
  `len` alias worked in guards only, so `need_nn(List.length(xs))` was
  `unreflectable-subject`, and `let n = List.length(xs)` then `if i >= 0 && i < n do
  List.nth(xs, i)` was a `partial-conjunct` skip. Both prove now, under the alias's
  existing gate (the stdlib's own `List.length`, not withdrawn).
- **`String.slice` with a negative start no longer reads out of bounds in wasm-compiled programs.**
  The wasm runtime's `march_string_slice` did not clamp a negative `start` and read before
  the string's buffer; it now clamps exactly like the native runtime and the interpreter
  (negative start -> 0, start past the end -> empty, negative length -> 0, over-long length
  stops at the end).

- **Refinements: a module-qualified container keeps its element fact.** `d :
  Deque.Deque({Int | _ > 0})` and `q : Queue.Queue({Int | _ > 0})` were no element
  source, so `sum_pos(Deque.to_list(d))` and `sum_pos(Queue.to_list(q))` were
  `parametric-source-unproved` skips, and so was `sum_pos(Deque.to_list(dfilter(d,
  fn y -> y > 0)))` for a user `dfilter : … -> Deque.Deque(a[p])`. A qualified name
  `M.T` now resolves to its declaration when exactly one module declares `T` and `M`
  names it; all three are proved. An ambiguous `T` is still unknown (a skip).
- **Refinements: a recursive local `fn` proves its element return through its own
  self-call.** `find_index`'s shape, a local `go(lst, i : {Int | _ >= 0}) :
  Option({Int | _ >= 0})` whose tails are `None`, `Some(i)` and `go(t, i + 1)`, was
  three `unreflectable-subject` skips (`return of go`, `return of` the enclosing
  function, and the `Some(i) -> need_nn(i)` use). A self-call with a structural
  argument (`t` from `Cons(h, t)` of `lst`) now carries the declared return, the rule
  a top-level function already had, and only after the local's return is proved with
  it, so a `Some(0 - 1)` tail is still a violation and lends nothing. The same holds
  for a recursive local returning `List({…})`. `--refine-infer` now proposes the
  `Option` return.
- **Refinements: a `List.filter` lambda may capture the caller's variables.**
  `fn small(xs : List(Int), n : Int) : List({Int | _ < n}) do List.filter(xs, fn y
  -> y < n) end` was an `abstract-refinement-uninstantiated` skip at its return, and
  `small(ys, 10)` an `unreflectable-subject` skip at the call. Both are proved now,
  and so is `sum_lt10(List.filter(xs, fn y -> y < k))` with `k : {Int | _ <= 10}`.
  An abstract refinement's lambda may mention a local of the call (a parameter,
  `let`, lambda parameter or `match` binder); the element fact names it and is
  read in the caller's scope. A module-level name is still declined, and so is a
  `let`-bound lambda or result whose captured variable is rebound before its use.
  A capture over an unconstrained variable (`fn y -> y > m`, `m : Int`) is now a
  `solver-undecided` skip instead of `abstract-refinement-uninstantiated`.
  `--refine-infer` now proposes the `small` return.
- **Refinements: a length contract on a list return is now checked whatever the body
  looks like.** `fn f(xs : List(Int)) : {List(Int) | len(_) == len(xs) + 5} do xs end`
  used to pass with no error and no obligation in `--refine-report`: only a body that
  was a constructor or one `match` on a parameter was checked. A bare variable, a
  `let`, an `if`, a call or a `match` on anything else is now checked tail by tail, so
  that false contract is reported (`but f([]) returns [].`) and the true
  `len(_) == len(xs)` is proved. A mixed `elts(_) == elts(xs) && len(_) == len(xs)`
  contract now proves too, where it used to be undecided. A list or datatype return
  contract the checker cannot prove is a recorded skip, and inside `cap verified` it is
  now an error (it used to pass silently there). A refined return the checker does not
  model at all, such as a guarded clause, is a recorded skip instead of nothing.
- **Refinements: return contracts compose through calls.** A return whose tail is a
  call now uses the callee's proved (or `@[assume]`d) return:
  `fn b(x : {Int | _ > 0}) : {Int | _ > 0} do a(x) end` proves from `a`'s
  `{Int | _ > 0}`, through any number of hops. It was an `unreflectable-subject` skip
  before. A function never uses its own unproved return this way, so self-recursive and
  mutually recursive tails stay skipped. A relational return lent at a call
  (`inc(x) : {Int | _ > x}`) now brings the caller's facts about its arguments with it,
  so `need_pos(inc(n))` with `n : {Int | _ >= 0}` is proved (it was
  `solver-undecided`). **Soundness:** a named return binder (`{r : Int | r > x}`) is now
  renamed apart before the arguments are substituted. Before, `inc(r)` with a caller
  variable `r` read `r > r`, and that false assumption "proved" any demand on the call.
  `--refine-infer` now proposes returns along such a chain (`a` and `b` both get
  `{Int | _ > 0}`). Its probes also lend only proved returns, as the real check does,
  so `--refine-infer-apply` no longer fails its re-check ("did not match the
  prediction") on a program with an unproved declared return. A parameter refinement that
  names an unrefined sibling (`k : {Int | _ > x}`) no longer sends z3 a malformed query
  when a return is checked. That return used to be skipped silently; it is now decided.
- **`--refine-infer` no longer proposes a precondition that only makes the demanding
  branch dead.** In `if j >= n do v else Array.set(v, j, …) end`, `n : {Int | _ <= j}`
  "proved" the `Array.set` index by making the `else` unreachable. A precondition
  whose closed sites are closed only that way is now rejected as `vacuous-branch`
  (printed by `--refine-infer`, `rejected[].reason` in `--refine-infer-json`). A
  precondition that genuinely proves a site still counts every site it closes. On
  `test/native` the one accepted proposal (this one) is gone. A plain `--check` is
  unchanged.
- **Refinements: a lambda or helper that binds one name twice is no longer read as a
  predicate.** `let h = fn (a, a) -> a > 0` then `List.filter(xs, fn y -> h(y, 1))`
  was read as `y > 0`, and a function `two(a : Int, a : Int) : {Bool | _ == (a >
  0)}` lent `two(y, 1) == (y > 0)` at a call; which argument the body's `a` names
  differs between the interpreter (the first) and compiled code (the last), so both
  are now declined (`abstract-refinement-uninstantiated`, or no postcondition fact).
- **`--refine-suggest-all` no longer proposes a precondition that breaks a caller.** The
  suggester re-checked only the target function, so for `go(n : Int) = need_pos(n)` with
  `caller() = go(0 - 5)` it proposed `n : {Int | _ > 0}` and reported "discharges all", although
  applying it turns `caller` into a refinement violation. Probes now include every caller in the
  unit; such a proposal is reported as `refused (caller-violation)` with the call it would break.
  A hypothesis is also judged site by site (it must prove something, break nothing and create no
  violation), and one that makes the parameters unsatisfiable is rejected.
- The in-browser REPL (stdlib "Try it" pages, playground, landing page) now runs a
  pasted doc transcript one `march> ` line at a time and ignores the expected-output
  lines between them. Pasting a transcript whole used to evaluate it as one block and
  print the value of its last line, the transcript's own expected output, which on
  Sort.html made `Sort.heapsort_by` look as if it dropped the largest element.
- `march --compile` no longer serves a cached binary that was linked under a different
  host library probe: whether the build host has OpenSSL, zstd or brotli decides what
  the binary links and whether its zstd/brotli codecs work, and is now part of the
  build cache key.
- A hot deploy that changed an actor's state no longer hands an actor spawned by
  not-yet-redeployed code (such as a closure `main` built) an old-layout state to run
  the new handlers on, which read garbage fields and could crash: the state is now
  migrated from the version of the code that built it before the actor's first
  message.
- On macOS, `forge deploy hot` now finds a patch's `migrate_state`: it looked for the
  `__migrate_<Actor>` symbol with `nm -D`, which lists nothing for a Mach-O library,
  so every deploy that changed an actor's state was refused as missing its migration.
- Two nodes built from different versions of a protocol no longer form a session
  through `<P>_Run.cluster_<Role>` and find the skew mid-session: each role registers
  its protocol fingerprint beside its endpoint, and a peer with a different one, or
  none (a node built before the check), is refused with `Err(Connect(...))` before the
  session forms, as the direct runner already refused it at the hello.
- `--hot-reload` programs built with `--cap-sandbox` now keep their reload and observe
  sockets when they withhold `IO.NetListen`: the reload server's listener is bound
  before the sandbox is installed instead of racing it on its own thread, and the
  observe socket starts before the install instead of after it (where its bind was
  always refused). An over-long reload socket path is now refused instead of silently
  truncated.
- **Refinements: a correct call under a condition the checker cannot read is no
  longer a violation.** With `k : {Int | _ <= 100}` and
  `xs : List({Int | _ < k})`, `if small(k) do need_lt5(xs) else 0 end` (where
  `small(k)` is `k < 5`) was reported violated with the example `k = 6`, a value
  that never reaches the call; so were a call inside a `Some(3) ->` arm, after an
  arm whose failure the checker does not record, and in a later `match do` cond
  arm. These are now skips, as the same call with a plain `Int` argument already
  was. An `Int` literal arm (`3 ->`) now records that the scrutinee is 3 (and,
  past an unguarded one, that it is not), so such a call can be proved. The
  same false violation through a `Bool` local (`let ok = k < 5; if ok do …`) is
  fixed too: such a local is read as its comparison in a guard (so the call,
  and the plain `Int` twin `if ok do n5(k)`, are now proved), and a local the
  checker cannot pin down (`let ok = small(k)`) makes the call a skip.
- **Refinements: a pattern binder spelled like a name its element refinement
  mentions no longer proves anything.** With `xs : List({Int | _ < n})`,
  `match xs do Cons(n, _) -> need_neg(n)` gave the new `n` the fact `n < n`, a
  contradiction, so `need_neg(n)` was proved (and accepted under `cap verified`)
  although `g(5, [3])` passes 3. `let n = hd(xs)` through a parametric head had
  the same hole. Such a binder now gets no fact from the slot.

- **Refinements: a local `fn`'s container return is checked.** A block-level
  `fn bad(n : Int) : List({Int | _ > 0}) do [n, 0] end` filed no obligation for
  its tails, so it was accepted silently, even under `cap verified`, although
  `bad(5)` returns a list holding 0. Every tail element is now an obligation, as
  for a top-level function: the `0` is a violation. `--refine-audit` already
  called this position enforced; it now is.
- **Refinements: a recursive combinator that recurses with a DIFFERENT
  predicate no longer proves its abstract element return.**
  `fn filt(xs, pred : a -> Bool[p]) : List(a[p])` whose body recursed as
  `filt(t, fn y -> true)` (or passed a swapped or rebound callback) had its
  return proved by the structural induction hypothesis, so a caller's
  `sum_pos(filt(ys, fn y -> y > 0))` was reported proved while the result could
  hold `-3`. The hypothesis now applies only when every predicate position of
  the recursive call receives the function's own, unshadowed parameter (an
  alias such as `let q = pred` is declined too). The hole predates the tuple
  returns above for single-container returns; the tuple form had it from the
  start.
- **Refinements: an interface method's result no longer counts as parametric.**
  `fn pick(o : Option(a), d : a) : a` returning `dflt(1)`, where the only impl of
  `dflt : Int -> t` is written at `Int` and returns -5, was accepted as generic
  in `a`, so `need_pos(pick(o, 1))` was proved (and `cap verified` compiled it)
  although `pick(Some(3), 1)` returns -5; the element rule had the same hole
  (`sum_pos(mk(pos))` with `mk` consing `dflt(1)`). A call to an interface
  method whose result mentions a type variable, including a non-creating
  `t -> t` and one adopted from a single `impl`, now makes the caller
  non-parametric: those demands are skips.
- **Refinements: a callback parameter's own refinement annotation is no longer
  assumed when a demand on the call's result is checked.**
  `need_pos(List.fold_left(pos, 1, fn (acc : {Int | _ > 100}, x) -> acc - 50))`
  was proved from the unchecked annotation (`List.fold_left([5], 1, …)` is
  -49); it is now a skip.
- **Refinements: a named function passed as a callback lends its declared
  return only when its own preconditions are met.** With
  `fn dec2(a : {Int | _ > 100}, _x : Int) : {Int | _ > 0} do a - 50 end`,
  `need_pos(List.fold_left(ys, 1, dec2))` was proved (and `cap verified`
  compiled it) although `List.fold_left([5], 1, dec2)` is -49: `dec2`'s return
  holds only when `a > 100`, and nothing checked what `fold_left` passes it.
  The same held for an element position (`fn g(_a : Int, x : {Int | _ > 0})`
  over an unrefined list), for `List.map` with a named function, and for a
  callback parameter passed on. A refined parameter of the named function must
  now follow from what the callee guarantees at that position (the demand on
  the accumulator, or the list's element refinement); otherwise the demand is
  a skip naming the unmet precondition.
- **Refinements: a recursive helper's element return is no longer trusted when
  its own recursive call skips a precondition.** A helper such as
  `pfn go(lst, acc : List({Int | _ > 0})) : List({Int | _ > 0})` that recursed
  as `go(t, Cons(f(h), acc))` with an unproved push recorded only a skip at that
  push, yet its return (by structural induction) and every caller's demand were
  reported proved. The induction now needs every element precondition of the
  recursive call PROVED; a skip or a violation there leaves the return unproved
  and its callers unproved with it. The same held for an abstract slot
  (`acc : List(a[p])`, pushing without testing `pred`, or pushing an element of
  another list): such a push is now an `unconstrained-subject` skip (or, on the
  branch where `pred` rejected the element, a violation) and lends nothing.
- **Refinements: a caller's own abstract refinement is no longer mistaken for the
  callee's.** A caller declaring its own `p` that passed a list to a callee slot
  such as `xs : List({Int | p(_) == false})` had the callee's `p` read as its
  own, so the call was reported proved whatever predicate it passed; a slot shape
  not read at a call is now an `abstract-refinement-uninstantiated` skip, and a
  `!p(_)` slot is instantiated with the callee's predicate.
- **Refinements: a return value bound inside a `match` arm or `let` under a
  parameter's name no longer proves a false return contract.** In
  `fn g(n : {Int | _ < 0}, p : Option(Int)) : {Int | _ > 0}` with the arm
  `Some(n) -> if n > 5 do 0 - 7 else 1 end`, the checker read the parameter's
  `n < 0` and the arm's guard `n > 5` as facts about one `n`, and the
  contradiction "proved" the `-7` tail, so `cap verified` accepted it
  (`g(0 - 1, Some(10))` returns -7). `Some(n) -> n` with a refined parameter `n`
  was proved the same way. The inner binding is now kept apart: the first is a
  violation, the second a skip. The same fix covers a lambda's tail inside a
  demanded call, a function passed where a container return is expected, and a
  lambda inside the returned call that captures the inner binding
  (`Some(n) -> ap(1, fn z -> n)`).
- **Refinements: a container that hides a type parameter inside another type no
  longer passes element checks vacuously.** For `type Wrap(k, v) = Wrap(List((k, v)))`,
  `fn mk() : Wrap(Int, {Int | _ > 0}) do Wrap([(1, 0 - 5)]) end` was counted
  *proved* and `need(Wrap([(1, 0 - 5)]))` filed no obligation at all. Such a
  construction is now a recorded `unreflectable-subject` skip naming the
  constructor and the hiding type (an error under `cap verified`), and the
  function's element return is no longer trusted at its call sites.
  The same applies to a self-reference whose type arguments are permuted or
  nested (`type T(a, b) = … | N(T(b, a))`). A `match` binder at such a field no
  longer inherits the outer container's element facts, which had produced a
  false proof.
- **Element refinements that name a parameter no longer prove false contracts.**
  A slot like `xs : List({Int | _ < n})` was read in whatever scope it reached,
  so the refinement checker proved calls and functions that break it, and
  `cap verified` compiled them: `need_lt(ys, 10)` was proved from a caller's
  unrelated `let n = 1000`; a return tail under `let n = 100` was checked
  against the local `n`; `xs`'s fact survived `let n = 0`; `List.map(xs, fn n ->
  …)` gave the lambda's `n` a fact about itself; and a demand was read under a
  lambda parameter of the same name. The slot is now read at the call's
  arguments (`need_lt(ys, 10)` demands `_ < 10`, so a correct
  `need_lt(ys, 200)` with `ys : List({Int | _ < 5})` is no longer a false
  violation; a demand naming a caller variable no fact constrains, such as
  `need_lt(ys, k)` after `k`'s fact was retired, is a skip rather than a
  violation), and each of the other shapes is a recorded skip. Two related
  shapes are skips too: a record field's or an expected codomain's element
  refinement naming another field or parameter, and a lambda return expression
  that mentions a name bound inside the lambda (`fn y -> let k = 0 - 5; k`
  was proved against a caller's `k : {Int | _ > 0}`).

### Documentation

- **The compatibility policy now says the in-memory layout of values, strings
  included, is not part of the 1.0 promise.** C code reaches strings only through
  `march_ffi.h` (`march_slice`, `march_str_new`), and a check keeps that header from
  exposing the string struct, so short strings can later be stored inline without
  breaking anyone.
- **What March 1.0 will promise, in writing.** New pages: [Compatibility &
  Deprecation](docs/compatibility.md) (what a 1.x release keeps working, including the
  cluster control plane's release format and messages; `@[deprecated]` and stdlib
  stability tiers are marked as planned), [Supported Platforms](docs/platforms.md)
  (tier 1: darwin-arm64, linux-x86_64, linux-aarch64; Intel macOS is tier 2; Windows,
  WASM and JS are tier 3), and one claim page each for
  [deploys](docs/claim-deploys.md), [capabilities](docs/claim-capabilities.md),
  [performance](docs/claim-performance.md) and
  [refinement types](docs/claim-refinements.md), each with its assumptions, what it does
  not claim, and which CI checks defend it and which are still planned. A new
  [Capability Threat Model](docs/capability-threat-model.md) replaces three pages that
  disagreed: `docs/capability-audit.md` no longer says an undeclared builtin call is only a
  warning (it has been an error since 2026-08-06), and the provable-sandbox design notes
  that per-function grants were removed on 2026-08-13.

- **Every public stdlib function is documented, and about 1,500 doc examples have a Try it
  button.** 468 undocumented public functions now have docs, and 1,240 more functions gained
  `march>` examples that are checked natively and in the browser REPL. 87 modules (was 32)
  opt into Try it. Functions that do IO, use the network or actors, or live in modules the
  browser cannot load get plain usage snippets instead. Several wrong docs were corrected
  along the way, such as the stability claims for the sorts.

- **An upgrade guide for 0.6.0.** `docs/upgrading-to-0-6-0.md` covers the two
  security fixes, the `send_wrong_actor` check and the RFC 3986 `Uri` changes. The
  landing page and the toolchain examples now name v0.6.0.

- **The refinement-types page makes the October features easy to find.** It has a dated
  "What's new" box, contents entries for relational element refinements, one- and
  two-argument abstract refinements, fold accumulator invariants and module-wide
  inference (`march --refine-infer` / `forge refine --infer`), a table of the new surface
  forms under Syntax, and a Limitations list of the known gaps (for example `Map`'s
  other functions and `HashMap.filter` carry no element fact yet). The skip-reason table
  now lists all sixteen reasons, and the page says that `fn (a, a) -> …` is a
  `duplicate_binder` type error. The relational element refinements section and the
  two-argument abstract refinements part are rewritten around one running example, with
  checked examples for building, matching and projecting an entry.

## [0.6.0] - 2026-10-17

### Highlights

0.6.0 is a short release: two security fixes and two small breaking changes,
three days after 0.5.0. Read **Security** and **Breaking changes**
before upgrading. Every change is listed in full in the sections after them.

- **Better crash reports.** In a compiled program, the crash report now gives
  the file and line of the `panic` that caused it. Each backtrace frame names
  the function as written in the source, on Linux as well as macOS.
  `Diagnostics.observe_crashes` lets a program see every crash that nothing
  else handles.
- **The in-browser REPL can use the whole standard library.** It also handles
  deep recursion, and it downloads a tenth as much as before. 249 runnable
  "Try it" examples on the stdlib pages are checked in CI against the native
  REPL and the browser REPL.
- **The release archives can compile programs again.** The v0.5.0 archives
  were missing the vendored C libraries.

### Security

- **`Uri.merge_strict` rejected too few `..` segments.** A reference such as
  `../../../etc/passwd` merged against a base path `/a/b/c` was accepted. If
  you use `merge_strict` to check untrusted relative references, upgrade.
- **`HttpTransport.request` checks the certificate on `https://` URLs.** The
  simple request functions used to reject `https://` URLs or risk sending them
  over a plain socket. They now use TLS with SNI and verify the certificate.

### Breaking changes

- **Sending one actor's message to another actor's pid is a compile error**
  (`send_wrong_actor`) when the pid's state type is a different record from the
  state of the actor that owns the message. Code that compiled under 0.5.0 and
  dropped the message silently at run time is now rejected. Send it to the
  right pid. Two actors that share a handler name are caught by the same check.
  Rename one of the handlers.
- **`Uri.parse` and `Uri.merge` follow RFC 3986 for relative references.** A
  string without a scheme is now read as a path unless it starts with `//`, so
  `Uri.parse("../d")` no longer has host `..`. Merging keeps the leading `/`.
  Code that relied on the old results gets different values.

### Known issues

The four known issues listed for 0.5.0 are still open:

- **Each hot deploy keeps one patch `.so` mapped until the node restarts.**
- **A coordinated type-signature change can still reach a running caller.**
  Restart for signature changes.
  (`specs/todos/2026-10-13-hcr-coordinated-sig-change-running-caller-frame.md`)
- **Two nested types with the same short name are one type to the checker.**
  Give the types distinct names.
  (`specs/todos/2026-10-13-same-short-name-nested-types-unify.md`)
- **A function from another module used as a value fails to compile.** Wrap it
  in a lambda (`fn xs -> List.length(xs)`).
  (`specs/todos/2026-10-13-other-module-fn-as-value-undefined-symbol.md`)

### Added

- **Compiled crash reports say where the panic was called, and name every frame.**
  A `Diagnostics` crash report's `location` is now the exact file and line of the
  `panic`, `todo` or `unreachable` call in compiled programs, as it already was
  interpreted. Compiled backtrace frames now give each function's source name (no
  more `$lam0__…`), file and definition line, on Linux as well as macOS: the
  compiler records the program's functions in a small table instead of relying on
  the symbols the executable exports.

- **"Try it" on 33 stdlib pages, and documentation examples are now checked.**
  String, Json, Uri, Crypto, Regex, Task, Vault and 12 more modules have runnable
  examples (249 "Try it" examples in all, up from 107), and every one is verified
  against both the native REPL and the in-browser REPL in CI, so a documented result
  that drifts from the real one fails the build. Converting them corrected dozens of
  wrong examples (for instance `String.split(s, "")` splits into bytes, not "returns
  the whole string"). Actor's module example is now a complete program you can run.
  The browser REPL now accepts `|>` pipes and a `main` that takes `Cap(IO)`.

- **`Diagnostics`: observe crashes the runtime owns.** `Diagnostics.observe_crashes`
  registers a callback that receives a `CrashReport` (kind, message, backtrace, the
  failing actor, and context) for every panic nothing handles, in an actor or in
  `main`, before the supervisor restarts the actor or the process exits.
  `Diagnostics.with_context` attaches request or job metadata that the report
  carries even though the panic unwound past it. Observers run in registration
  order. One that panics is skipped without changing the outcome, and a panic caught
  by `__try_call` or a test is not reported. Interpreted backtraces have file and
  line; compiled ones name the functions on macOS (Linux needs a later change), with
  no line yet. It is vendor-neutral: an error-service integration such as Sentry
  is a package built on top.

- **"Try it" on the stdlib API reference.** On march-lang.org/docs/stdlib, the
  examples of the modules that opt in (`-- doc: try` in the module header, or a
  ```` ```march try ```` fence) have a **Try it** button that opens a REPL sidebar and runs
  the example, one result per line as in the docs. The REPL loads on the first click,
  so the pages stay fast. 107 examples across 14 modules (List, Option, Http, Path,
  HashMap, ...) to start. `forge doc --try-it` generates the same buttons.

- **The in-browser REPL can use the whole standard library, and reports what it
  can't do.** Modules load the first time you use them, so `HashMap`, `Uri`, `Csv`
  and about a hundred others now work on the playground and cookbook pages (197 of
  the 210 stdlib doc examples run in the browser, up from 63) without slowing startup.
  Modules that need a file system, sockets, processes or the cluster runtime say so
  instead of failing obscurely. The browser REPL's `Int` is 32-bit, so a result that
  would overflow it is reported, where it used to silently give a wrong answer
  (`65536 * 65536` was `0`).

- **The in-browser REPL can clear the screen without forgetting your definitions.**
  Every REPL on the site (playground, landing page, cookbook sidebar) has a **clear**
  button, `:clear` and Ctrl+L, which wipe the screen and keep what you defined, next to
  **reset**, which also forgets it. The cookbook sidebar previously had neither.

### Changed
- **The stdlib API reference loads much faster.** Every page inlined a sidebar listing
  all 2,964 entries of every module, and fetched the whole search index on load, so a
  page was about 400 KB plus a 424 KB index download. The sidebar now lists the modules
  and expands only the one you are reading, and the search index loads when you first
  open search: a page is now 60-95 KB (8.3 MB for all 133 pages, down from 50.5 MB).

- A compiled program whose scheduler is about to resume a corrupt or freed
  green-thread context now stops with a `march_sched[BUG]: dispatch of pid N
  ... with a context it did not save` line (the pid, the saved stack pointer
  and the stack bounds) and aborts. Before, that switch blocked SIGSEGV
  through the garbage signal mask and then faulted, so the process died with
  only the shell's `Segmentation fault (core dumped)` and no `march: fatal`
  line, which is all one CI crash of `native_run_until_idle_ping_pong` left.

### Fixed

- **`HttpTransport.request` now sends HTTPS over verified TLS.** The convenience
  request APIs no longer reject `https://` URLs or risk sending them over a plain
  socket: they establish TLS with SNI and certificate verification, then issue the
  HTTP/1.1 request. The lower-level APIs that take a raw file descriptor still
  reject HTTPS, because a descriptor alone does not establish a TLS session.

- **Sending one actor's message to another actor's pid is a compile error when the
  types show it.** `send` didn't relate the message to the target, so
  `send(logger_pid, Increment(1))` compiled and the message was silently dropped at run
  time. When the pid's state type is a different record from the message's actor's
  state, it is now rejected (`send_wrong_actor`). Two actors whose state records have
  the same shape still can't be told apart, since a pid's type is its actor's state.
  The same error catches two actors sharing a handler name, where a bare name picks
  one of them and compiled and interpreted code used to disagree.
- **`forge test` no longer segfaults calling an interface impl through a generic
  helper.** Under `--test`, an `impl` method that read the clock, the console or any
  other mockable operation was compiled with a hidden capability parameter, but a
  call reaching it through the interface from generic code didn't pass one, so every
  argument shifted by one (#708). Such impls are now compiled without the hidden
  parameter; an operation inside one runs on the real capability rather than a
  `with_cap` mock.
- **A session that forms just as a peer node dies no longer outlives it.** For a
  moment after a node's connection closed, the cluster node still handed out that
  connection to sessions being set up. A session that linked to it in that window
  never heard that the node was gone and waited for that link's end for ever,
  so a SIGTERM drain on its node ran to its hard deadline and exited 1. A dead
  connection is now no longer handed out from the moment it closes.

- **`march --jit` names the program's own atoms.** `to_string(:zz)` printed
  `:<atom>` under `--jit` (both the ORC and clang backends) for any atom the stdlib
  does not itself use; it now prints `:zz`, as the interpreter and `--compile` do.

- **Security: `Uri.merge_strict` now rejects every path traversal above the root.**
  The guard was off by one: the empty segment before a path's leading `/` absorbed one
  `..`, so against a base path `/a/b/c` the reference `../../../etc/passwd` was accepted
  as `Ok(...)` with path `etc/passwd`, and only four `..` were rejected. Any `..` with
  nothing left to remove is now an `Err`, including one in an absolute-path reference
  (`/../etc/passwd`). If you used `merge_strict` to vet untrusted relative references,
  upgrade.
- **`Uri.merge` keeps the leading `/` (RFC 3986 §5.2.4).** Surplus `..` segments turned
  the path relative, so `../../../x` against `https://example.com/a/b/c` gave
  `"https://example.comx"`; it now gives `"https://example.com/x"`. Merging also follows
  §5.2 in the remaining cases: dot segments are removed from absolute-path and
  network-path references too, a base with an empty path merges as `/` + the reference,
  and a fragment-only reference keeps the base query.
- **`Uri.parse` reads relative references per RFC 3986 §4.2.** A scheme-less string not
  starting with `/` was split as `host/path` (`Uri.parse("../d")` had host `..`), and
  `//other.com/x` put everything in the path. Now only `//` introduces an authority:
  `../d` and `a/b` are paths, `//other.com/x` has host `other.com` and path `/x`, and
  `Uri.to_string` writes such a reference back with its `//`. A `://` inside a path or
  query (`/go?to=http://x`) no longer makes a scheme.
- **The in-browser REPL no longer runs out of stack.** On the playground, cookbook and
  "Try it" pages, `List.map` over more than about 200 elements, or a recursive function
  a few hundred calls deep, failed with "Maximum call stack size exceeded". The
  interpreter is now compiled so that recursion depth is limited by memory: a
  100,000-element list or 100,000-deep recursion works. Call-heavy code runs about a
  third slower, and the download is about 10% smaller. Also, defining a function after
  `main` no longer runs `main` again.

- **`march repl` no longer crashes on an atom inside a value.** `Err(:invalid)`,
  `Some(:a)`, `[:a, :b]`, `(:a, 1)` and `UUID.parse("not-a-uuid")` killed the REPL with a
  segmentation fault; they now print. A `None` inside a list or tuple prints as `None`
  instead of `null`. Compiled programs had a related bug: an `Option(Atom)` built from a
  literal atom (`Some(:a)`) did not match its own atom (`x == :a` was `false`) and printed
  as `Some(:<atom>)`. Both are fixed.

- **`march repl` prints negative numbers inside lists, options and tuples correctly.**
  The native REPL showed `[-1, 2]` as `[9223372036854775807, 2]` (and likewise
  `Some(-1)`, `(-1, 2)`, `NativeArray.to_list_i32(...)` with a negative element). Only
  the printed result was wrong; the values themselves, `--compile` and the interpreter
  were always right.

- **The in-browser REPL downloads a tenth as much, and the Tetris playground compiles
  again.** The REPL on the playground, cookbook and landing pages loaded a 19.7 MB
  development build (2.1 MB compressed); it is now a 1.9 MB release build (408 KB
  compressed). Editing the Tetris playground and pressing Run had failed on every
  program since at least July; it compiles and runs again. Both are now rebuilt
  automatically after every compiler or stdlib change, which also fixes `Json` in the
  REPL (`unbound variable: string_byte_at`).

- **A topology app under continuous session traffic stops on Ctrl-C/SIGTERM.**
  A node whose hook tasks kept starting sessions (an `initiate_<Role>` loop) never
  drained: each new session kept the count above zero, so every drain ran to its
  `[drain] hard_ms` (120 s by default) and exited 1, and under `forge run
  --processes` the pools after it then waited their own turn. A draining node now
  starts no new session (`initiate_<Role>` returns `Err(Left("draining"))`); a
  session whose initiating node died while it formed now gives up once the cluster
  declares that node dead instead of holding its slot for 30 s; and a second
  SIGTERM or SIGINT to a draining node stops it at once, as documented, instead of
  being ignored.
- **The release archives include the vendored C libraries, so a prebuilt
  `march` can compile programs again.** The v0.5.0 archives bundled
  `runtime/*.c` and `*.h` but not `runtime/third_party/` (BLAKE3 and mimalloc,
  vendored since 0.4.0), so every `march --compile` from a prebuilt toolchain
  failed with `'third_party/blake3/blake3.h' file not found`. The packaging now
  copies the directory, and the release build compiles and runs a program with
  each packaged archive before publishing. The v0.5.0 archives were rebuilt
  and replaced; reinstall with `forge toolchain install v0.5.0`.

### Documentation

- **Overstated claims on the landing page and in the docs are corrected.** The
  tree-transform benchmark showed numbers no recorded run produced (Rust 9977 ms,
  "19x faster than Rust"); it now shows the `bench/RESULTS.md` medians (March 579 ms,
  OCaml 3670, Rust 4902, Elixir 2369) and says the other languages allocate a fresh
  tree each pass. The README's FBIP table and its "7x faster than C" claim (no C
  program is benchmarked) are replaced the same way. The landing page no longer calls
  actors "typed" or says shared mutable state is a compile error, since `send` does not
  check a message against the target actor. The hot-reload page gains a "Current limitations" section listing the open issues,
  and the memory-model chapter describes the march-lean oracle instead of calling it
  "not started".
- **`Actor.call`'s timeout under the interpreter is described accurately.** The actors chapter said the timeout is real on both backends. Compiled, the caller stops waiting at `timeout_ms`; under the interpreter the handler runs to completion first and a late reply is then discarded and reported as `Err`, so a slow handler still blocks the caller for its full duration. The chapter now says so, in the call section and in the list of backend differences.

- **The stdlib API reference has syntax highlighting, and Http is documented.**
  Code examples on march-lang.org/docs/stdlib/ were plain monochrome text: the
  generator only coloured fences tagged with a language, and the pages shipped
  no highlight colours. Examples are now highlighted as March in both themes.
  The paragraphs after the first in many doc comments no longer render as code
  blocks, and the comment above a `type` now appears as its description. Every
  `Http` function and type has a description, and its examples are now run in CI.

[Unreleased]: https://github.com/march-language/march/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/march-language/march/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/march-language/march/releases/tag/v0.1.1
