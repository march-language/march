# Changelog

All notable changes to March are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/); versions follow
[Semantic Versioning](https://semver.org/).

This file starts at the point March adopted a changelog (2026-07-21).
Implementer-level detail on every change — including everything that shipped
before this file existed — lives in `specs/progress/` and `specs/todos/`;
git log is authoritative for exact commits.

## [Unreleased]

### Added

- **Path-scoped capabilities: `needs IO.FileRead("/etc/myapp")`.** A module
  can narrow a filesystem capability to a directory subtree instead of
  declaring all-or-nothing access. A literal path outside the declared scope
  is a compile error; computed paths are left to runtime enforcement rather
  than guessed at. `--cap-sandbox` narrows the embedded sandbox profile to the
  declared scope for **writes** — reads are not narrowed on macOS, because the
  profile must already grant `file-read` unconditionally for the dynamic
  loader, so a scoped read rule would be decorative. Unscoped declarations are
  unchanged in meaning, so existing code keeps working. Note that scope
  matching happens after the kernel resolves symlinks: on macOS a scope of
  `/tmp/x` matches nothing, since `/tmp` is a symlink to `/private/tmp`.

### Changed

- **`forge cap audit` is now `forge cap inspect`.** Two commands named "audit"
  answered different questions at different granularities — `forge audit` reads
  dependency declarations from source, the other reads a built artifact — which
  is the kind of collision people get wrong under pressure. `inspect` is the
  right verb for reading facts off a thing that already exists, and matches the
  `docker inspect` precedent. No alias: the command is days old and unreleased.

### Fixed

- **A package's own constructor is no longer ambiguous against an unimported
  stdlib type.** Declaring `type Backend = StorageBacked | Custom(Int)` in
  `mod Pkg` and matching on `Custom` from `mod Pkg.Sub` failed with
  "ambiguous between multiple modules" whenever any stdlib type shared the
  constructor name — conduit's `RateLimiterBackend.Custom` against
  `Compress.Gzip.Level.Custom`, which made the whole package fail to
  typecheck. Locality now covers the package namespace rather than requiring
  an exact current-module match. Genuinely ambiguous references, where the
  current package owns none of the candidates, still error.

### Added

- **`forge audit --inferred`: infer each dependency's capability set from its
  code rather than its `needs` declarations.** Catches a capability builtin
  called directly in a body with no matching `needs` — which the compiler only
  warns about — at the cost of requiring each dependency to typecheck cleanly.
  Every capability report now states what it does NOT cover: source-level
  audits miss capabilities reached through stdlib or dependency functions,
  binary audits are a whole-program union that cannot attribute a capability to
  a specific dependency. The two are complementary, and neither is a complete
  account on its own.

- **`march caps <files...>`: a package's inferred capability set as JSON.**
  Loads the whole package the way `march check` does, so sibling and
  dependency imports resolve. Package-level rather than per-file because
  per-file does not work — most files in a real package reference siblings and
  fail standalone, and a union over whatever happened to typecheck
  *under*-reports, which for a capability record certifies a package as
  needing less than it does. A package that does not typecheck yields no set
  at all and a nonzero exit, rather than a partial one.
- **`/docs/capability-audit/` — a capability-audit guide written for a security
  audience.** Covers `forge audit` (dependency declarations, diffed against a
  baseline) and `forge cap inspect` (what a compiled artifact holds), what each
  proves, and a threat-model table of what neither covers. States plainly that
  an undeclared capability *builtin* is currently a compiler warning rather than
  an error, so a declared set is a floor for capability-passing code rather than
  a ceiling on all behaviour.

- **`forge audit` — capability diffing on dependency update.** Every March
  package declares the capabilities it needs and the compiler enforces those
  declarations, so the authority a dependency holds is readable from its source
  rather than guessed at. `forge audit` extracts the capability set of every
  transitive dependency and compares it against a recorded baseline:

  ```
  $ forge audit
    ! liba — now ALSO needs: IO.FileWrite, IO.NetConnect

  1 dependency is asking for capabilities it did not have.
  Review the change, then accept it with `forge audit --record`.
  ```

  Exits non-zero on that, so CI can gate a dependency update on it. A dependency
  that *stops* asking for a capability is reported but does not fail the audit —
  narrowing is the direction you want, and failing on it would train people to
  ignore the gate.

  The baseline lives in `forge.caps.lock` rather than in `forge.lock`, because
  `forge deps` rewrites the lockfile wholesale from resolution output and would
  silently erase a capability set recorded there — leaving a gate that compares
  nothing and reports success.

  Scope, stated plainly: this reports what a package's source *declares*. It is
  exactly as trustworthy as the compiler's enforcement of `needs`, which is
  strong for March code and says nothing about what an `extern` block's foreign
  code actually does — a package that grows an `extern` shows up as
  `IO.Foreign`.

- **`forge refine --postconditions`, `--apply`, and an editor action complete
  the postcondition half.** The compiler surface shipped previously; this adds
  the two surfaces people actually reach for. `--apply` rewrites the *return*
  annotation via a new `Refine_edit.splice_return`, which is a genuinely
  different scan from the parameter one — it must find the paren closing the
  parameter list (depth-tracked, so `Map(String, Int)` does not end it early)
  and stop at the `do` that opens the body. The editor gets a "Suggest a
  postcondition for `f`" action alongside the existing precondition one,
  sharing that same splice so the CLI and the editor produce identical bytes.

- **`march --cap-sandbox`: opt-in self-imposed capability sandbox.** Embeds a
  deny-default profile derived from the module's own inferred capabilities and
  applies it before any user code runs, so a binary deployed where forge is not
  the launcher (systemd, a container supervisor) still drops the privileges it
  never needed. Defense in depth rather than a new guarantee — whoever builds
  the binary chooses whether to compile it in, and the profile grants exactly
  what the program does, so it constrains escalation beyond the program's
  intended behaviour, not the behaviour itself. Off by default; default builds
  are unchanged. Implemented on both major platforms: macOS via a
  deny-default Seatbelt profile, Linux via an in-process seccomp-bpf filter
  installed unprivileged through `PR_SET_NO_NEW_PRIVS` — which matters
  because Linux is where servers actually run. Denied syscalls return
  `EPERM`, so a withheld capability surfaces as a March `Err` rather than a
  crash. `IO.Network`, `IO.Process` and `IO.FileWrite` are enforced;
  `IO.FileRead` is not, because seccomp filters syscall numbers and scalar
  arguments, never pointer contents, so it cannot tell which path is being
  opened (path scoping needs Landlock). Installation failure is fatal —
  running uncontained after being asked to contain is worse than not trying.

- **`forge cap run [--allow-only CAPS] BINARY`: run a compiled binary under an
  OS-enforced capability sandbox.** The policy is imposed from outside, so
  nothing in the binary is trusted — `--allow-only` lets you supply the policy
  for untrusted code, since a policy derived from the binary's own claim only
  defeats under-claiming. macOS uses `sandbox-exec` (SBPL), Linux uses
  bubblewrap. Which capabilities are genuinely enforceable was measured, not
  assumed: network, file-write and process-spawn are enforced, while
  `IO.FileRead`, `IO.Clock`, `IO.Spawn` and `IO.Random` are reported as
  **advisory** (denying them aborts the runtime — the loader must read system
  libraries, and clock/thread syscalls are indistinguishable from the GC and
  scheduler's own). Advisory capabilities are printed before the run so a clean
  run is never mistaken for full containment.

- **`forge cap inspect <binary>`: list the capabilities of a compiled March
  executable.** Executables are now linked with dead-strip (72–79% smaller),
  so unused capability runtime code is physically absent, and codegen embeds
  `__march_cap_*` marker symbols for the capabilities the emitted code
  actually references. The audit reads both channels, renders witnesses
  (which runtime entries back each cap), and gates CI with `--deny CAP` /
  `--allow-only CAPS` through the capability lattice (denying `IO` catches
  `IO.FileRead`). Foreign code (FFI) is reported as a scope limitation —
  analysis stops at the C boundary — and the gate fails closed on it unless
  `--allow-foreign` is passed; the same fail-closed rule applies to stripped
  or unstripped binaries (`--json` always includes a `coverage` field).
  `march caps <files...>` prints a package's inferred capability set as JSON.
- **`march --refine-suggest-post <fn>`: suggest a postcondition.** Where
  `--refine-suggest` proposes the parameter contract that discharges a
  function's own unproven obligations, this proposes the *return* contract that
  lets its **callers** discharge theirs — the other direction of the same
  propagation. Verified end to end: applying the suggestion takes the worked
  example from 1 proved / 1 skipped to 3 proved / 0 skipped.

  A postcondition discharges nothing in its own function, so two independent
  questions are both answered before anything is proposed: is the candidate
  *true* (asked of the checker's own postcondition oracle, not a second prover),
  and is it *useful* (does any caller's obligation actually become provable). A
  true-but-useless postcondition is not proposed — a sweep full of true
  irrelevancies is indistinguishable from a broken one. Outcomes stay
  distinguishable rather than collapsing into silence: `no-callers`,
  `no-debt`, `no-candidate` and `already-refined` are separate answers.
- **A missing capability now shows the call chain from `main` that forced it.**
  A capability is a property of a whole path, not of the single call that
  happens to need it — `needs` has to be threaded through every function in
  between — but the diagnostic named only the far end:

  ```
  call to `random_bytes` requires `needs IO.Random` — add `needs IO.Random` to module `CapErr`
  reached from `main`: main → issue → make_token
  ```

  The chain crosses module boundaries (a qualified `M.f` resolves to the simple
  name its definition declares) and terminates on recursive call graphs. It is
  omitted rather than guessed when there is nothing to say: a library with no
  `main`, a call sitting in `main` itself, or a callee reached only through a
  function value. Because the edges are syntactic, the chain is a witness rather
  than a proof — two modules defining the same function name share a node, so an
  unusual program can get a plausible sibling in the path.

- **An unverified refinement contract now says so, once per module.** March
  reports only definite failures — an obligation the solver cannot decide is
  accepted in silence, which is the right default (a false positive on correct
  code is the worse error) but leaves no way to tell "checked and fine" apart
  from "gave up". A single hint per module now names the first such contract
  and its reason, and points at `cap verified`, the existing opt-in that turns
  every unverifiable obligation into an error:

  ```
  precondition `_ != 0` on `safe_div` was NOT verified here
  (solver-undecided: the solver proved neither the predicate nor its negation).
  note: … add `cap verified` to this module to make every unverifiable
  obligation an error instead. `--refine-report` lists them all.
  ```

  Code the checker can discharge stays completely silent, a module with three
  undecidable calls still gets one hint, and inside `cap verified` the existing
  error is unchanged rather than joined by a hint.

- **Consuming-call inlay hints: the editor now marks which arguments a call
  takes ownership of (`⊗ consumed`).** Ownership transfer was previously
  invisible at the place it happens — you had to read the callee's signature,
  and often its body, to know whether passing a value ended its life. The hint
  is read off the compiler's own borrow inference (`Borrow.infer_module`), the
  same map Perceus consults when deciding which arguments need a reference-count
  bump, so it reports the decision the compiler actually made rather than a
  re-derivation of it. Two deliberate restrictions keep it a signal instead of
  decoration: only RC-tracked parameters qualify (the borrow map initialises
  non-borrow-eligible parameters to "not borrowed", so without this filter every
  `Int` argument would read as consumed), and only plain variable arguments are
  annotated (a temporary has no name to lose). The effect is that a borrowing
  call and a consuming call on the same variable look different one line apart.
  Also adds `march-lsp query inlay <file>`, which dumps the hints as JSON so
  they can be inspected without an editor.
- **The interpreter now suggests the working spelling when a call qualifies
  an interface method by its declaring module**, e.g. `Foo.speak(x)` when
  `Foo` declares `interface Speak(a) do fn speak : a -> String end`.
  Interface method names remain not module-qualifiable (a dispatch-side
  limitation, not a resolution bug — see
  `specs/progress/2026-08-03-interface-method-names-qualifiability-disposition.md`),
  but the `unbound variable: Foo.speak` error now names the interface and
  its declaring module and suggests the unqualified `speak(x)` call.

- `forge refine --fixpoint` (with `--apply`): repeat until a round applies
  nothing. A contract only becomes visible to a caller once the callee carries
  it, so each round propagates exactly one call hop. Bounded at 10 rounds, and
  hitting that bound is reported as its own outcome rather than passed off as
  convergence.

- **`forge refine <fn>`: suggest a refinement type.** Proposes the parameter
  refinement that discharges the obligations a function's body leaves
  unproven — `n : Int` → `n : {Int | _ > 0}` when `n` reaches a callee that
  requires a positive argument. Prints by default; `--apply` writes the
  annotation into the source, and `--all` sweeps the whole project. The
  editor gets the same thing as a "Suggest a refinement type for `f`" code
  action on the function's name.

  A suggestion is only made when the refinement checker itself proves the
  obligations under it: each candidate is hypothesised onto the signature and
  the real checker is re-run, so `march check` after `--apply` agrees with
  what was printed. Where several candidates work, the **weakest** is proposed
  — a divisor contract comes back as `_ != 0`, not `_ > 0`, so the suggestion
  does not silently reject callers the function would have accepted. Where
  nothing works, the command says so rather than going quiet: `no-debt`,
  `no-candidate`, and a partial discharge are distinct outcomes.

  It also declines to propose a contract that contradicts the function: a
  `_safe` wrapper handling `Nil -> Err(...)` is left alone, because forbidding
  the empty list would kill the branch the author wrote on purpose — while a
  branch that *panics* still gets the contract, since converting that panic to
  a compile error is the point. A sweep over all 112 stdlib modules is what
  found this; without the guard, three of its four suggestions were of that
  wrong shape.

  Also exposed on the compiler as `march --refine-suggest <fn>`,
  `--refine-suggest-all`, and `--refine-suggest-json`. Needs Z3, like the rest
  of refinement checking.

- `forge search --callers NAME`: reverse-reference search — find every
  resolved call, constructor use, or qualified type reference to a
  declaration, using the typechecker's own name resolution (not textual
  matching).

- **`derive Json for T` (record types) now also generates
  `from_json_events(events) : Result((T, List(JsonStream.Event)),
  Json.DecodeError)`, a second decoder that consumes `JsonStream`'s
  `Event` list directly instead of building a `JsonValue` tree first.**
  A record can now be decoded straight off the token stream — useful for
  a single huge top-level JSON object, where the existing tree-based
  `from_json` would otherwise have to materialize the whole thing as a
  `JsonValue` first. Generated as a small state machine: one `Option`
  slot per field, filled opportunistically as `EvKey` events arrive in
  whatever order the JSON object happens to use; a nested field whose
  type also derives Json recurses into its own `from_json_events`,
  composing the error path across the boundary exactly like the tree
  decoder does. Unknown fields (and duplicate keys, which keep
  first-occurrence-wins, matching the tree decoder) are skipped by
  consuming their WHOLE value — including nested containers — via
  explicit depth counting, so the event stream never desynchronizes.
  Scope: record types only; `TDVariant`/`TDAlias` are unchanged and do
  not get this second decoder.

- **`JsonStream.each_typed(path, cb)` decodes an NDJSON file straight to
  typed records via `derive Json`'s `from_json`, and attaches the
  decoding record's absolute byte offset to any failure.** A driver built
  on top of the existing (frozen) `JsonStream` tokenizer/event API,
  modeled on `each_value`: feeds the file to the tokenizer one line at a
  time (NDJSON is one record per line) so the byte offset just before
  each line is known, decodes each completed top-level value with the
  caller's bare `from_json`, and calls `cb(record)` per success. Returns
  `Ok(n)` with the record count, or the FIRST decode/tokenizer failure —
  `Json.DecodeError` — with `Json.decode_error_at` used to set its offset
  to that record's start, so `Json.decode_error_to_string(e)` names both
  the failing field and the byte offset, e.g. `"$.id (byte 9): expected
  Int"`. `test/stdlib/test_json_stream.march` (phase 1/2's tokenizer
  suite) is unchanged and stays green — `each_typed` does not touch
  `feed`/`finish`/`go` or any tokenizer internals.

### Documentation

- **The memory-model page no longer claims March is pauseless, and now
  documents drop cascades and cycles.** "No GC pauses" overstated the
  guarantee: March has no tracing collector and no collection stall, but
  freeing is inline work proportional to what died, so releasing a large
  structure walks it. The page now frames the property as *deterministic, not
  pauseless*, adds a **Drop cascades** section (destructuring vs. synthesized
  deep drop, why long spines don't overflow the stack, and how to schedule the
  cost out of a latency-critical path), and adds a **Cycles** section stating
  the real answer: there is no cycle collector, a cycle would leak silently,
  and the reason that is not a practical hazard is a design argument
  (immutability, linearity, no shared pointers across actors) rather than a
  mechanized proof. Same corrections applied to the README and docs index
  summaries.

### Changed

- **Refinement violations now name the offending parameter and callee, and
  underline that argument.** The message opened with a bare "argument does not
  satisfy precondition `_ != 0`" — on a call with several arguments that does
  not say which one, and since the predicate's binder is usually the anonymous
  `_`, nothing else in the message identified it either. It now reads
  ``argument `d` of `safe_div` ``, and a second labelled span underlines the
  argument itself rather than the whole call. The solver's counterexample
  (`e.g. n = -1`), which only appears when the failing model has a free
  variable, is unchanged.

- **Linearity errors now point at the earlier consumption site, not just the
  reuse.** "The linear value `token` is used more than once here" told you the
  value was already gone but not what took it, leaving the reader to find the
  first use by hand — which on a long function is the entire search. The
  diagnostic now carries a second labelled span: ``​`token` was already consumed
  here``. Attribution is path-correct: match arms are mutually exclusive, so
  consuming the same value once per arm stays legal, and a double-use inside one
  arm is labelled against that arm rather than a sibling that never ran.
- **`cap verified` now rejects an inert `interface`-signature refinement as an
  error instead of only warning.** A refinement written on an `interface`
  method's own signature (e.g. `fn run : a -> {Int | _ > 0} -> Int`) has
  always been inert — the refinement checker never reads a method
  declaration's type, so no call site is obliged and no body may assume it —
  and has warned about it since 2026-07-30. Under `cap verified`, whose whole
  promise is "if it compiles, it is proved," that silent-no-op shape is now a
  compile error instead, matching how the capability already escalates every
  other undischarged obligation. Outside `cap verified` the behavior is
  unchanged (still a warning). See
  `specs/progress/2026-08-03-cap-verified-interface-signature-decision.md`.

- **`derive Json`'s generated `from_json` now returns
  `Result(T, Json.DecodeError)` instead of `Result(T, String)` — a
  breaking change for any caller matching on the old bare-`String` error.**
  `Json.DecodeError(message, path, byte_offset)` carries a JSONPath-style
  path (`Json.JPathField`/`Json.JPathIndex` steps, e.g.
  `"$.users[3].id: expected Int"`) and an optional byte offset (`-1` when
  none applies), rendered via `Json.decode_error_to_string`. Every
  in-repo caller (`JsonStream.each_value`/`each_typed`,
  `test/stdlib/test_json_typed.march`) was migrated in the same set of
  commits that introduced the type. A bare `to_string(e)` still produces
  a readable message (e.g. `DecodeError("missing field",
  [JPathField("age")], -1)`), but code that expected a plain error string
  should switch to `Json.decode_error_to_string(e)`.

- `forge search --type` now performs structural type matching (exact arity,
  per-position argument types, canonical type variables) instead of
  substring matching. A leading `->` queries by return type alone, and now
  matches regardless of what letter that variable holds in an entry's full
  signature (e.g. `--type="-> Option(a)"` finds `Option.map`, whose full
  signature is `Option(a), (a -> b) -> Option(b)`). Malformed type queries
  are now reported as errors — including a hint that arguments are chained
  with `->`, not the `,` search results print them with — rather than
  silently returning loose matches. The on-disk search-index cache format
  bumped (version 3): a cache built before this rewrite is now correctly
  treated as stale and rebuilt, instead of `--type` silently returning no
  results forever.

### Changed

- **The event-loop HTTP server is now selectable at RUN TIME, not build time.**
  Both server implementations have always been compiled into every March
  binary (`march_http_evloop.c` is unconditionally in the runtime link), but
  reaching the faster one required recompiling your program with
  `MARCH_HTTP_EVLOOP=1` set at *build* time — so in practice the faster server
  was unreachable in every binary already shipped. `MARCH_HTTP_EVLOOP=1` is now
  read at startup and picks the implementation for that process.
  `-DMARCH_HTTP_USE_EVLOOP` still forces it on unconditionally, so existing
  build recipes are unaffected.

  This matters more than it sounds, because the event loop is **much** faster
  on Linux than the earlier macOS measurements suggested. Idle 4-vCPU Ubuntu
  24.04 (kernel 6.8, epoll), wrk `-c256`, order-swapped, one binary switching
  at runtime:

  | server | req/s | CPU-µs/req |
  |---|---:|---:|
  | thread pool (default) | 45,990 / 51,018 | 47.46 / 43.04 |
  | event loop | 76,488 / 80,416 | 27.35 / 24.76 |

  **+61% throughput, −42% CPU per request.** On macOS/kqueue the same
  comparison showed only 21% CPU and the event loop *losing* on req/s.

  It remains opt-in rather than the default because the constraint that made
  it opt-in is real: event-loop threads must not block, so a handler doing
  synchronous I/O — a blocking DB call — stalls every other connection on that
  thread. Enable it for I/O-light, high-concurrency workloads; leave it off if
  your handlers block.

### Fixed

- **`march-lsp` implements the pull diagnostics it advertises.** It declared
  `diagnosticProvider`, but `textDocument/diagnostic` reached no handler, so
  every pull failed with `TODO: handle this request` — invisible because the
  push path quietly carried the feature. Also lowers `workspaceDiagnostics` to
  `false`: that is a separate promise (`workspace/diagnostic`, over every file
  rather than the open ones) which is still unimplemented, and advertising it
  would recreate the same bug one level down.

- **`march-lsp` now exits when the client tells it to.** The server handled the
  `exit` notification and then went straight back to reading stdin, so it hung
  until the editor's timeout killed it — `Jsonrpc2.run`'s `?shutdown` predicate,
  which is what actually ends the loop, was never passed. Every existing
  protocol test ended by closing the pipes, which stops the server via EOF
  whether or not `exit` is honoured, so none of them could see it.

- **The stdlib load manifest is now guarded against going stale.** A file under
  `stdlib/` missing from `stdlib_file_list` is loaded for export shapes only —
  its body never goes through inference in its caller's context — so a generic
  `Option`/`Result` it exports silently produces a **wrong value** at a concrete
  niche-eligible call site: no diagnostic, compiled builds only, different
  garbage each run. That class had been point-fixed three times by hand-adding
  whichever files someone happened to notice. The manifest moved to
  `lib/modules/stdlib_manifest.ml` and two tests now hold the invariant: it is
  exhaustive over `stdlib/`, and every entry has a file behind it. Deliberately
  lazy modules go in an explicit allowlist.
- **The LSP's TIR pass is now idempotent — performance insights no longer
  duplicate.** Re-running it on an analysis it had already processed appended
  its perf insights to a list that already contained them, so a function could
  report "stack-allocates 2 values" twice. The pass now returns immediately when
  the analysis it is handed is already its own output.
- **A top-level `let`'s refined annotation is now checked, not silently
  ignored.** `let zs : {List(Int) | len(_) > 0} = []` at module scope
  previously produced zero obligations — the desugarer never normalized a
  qualified spelling in the annotation (`Desugar.desugar_ty` ran over a
  block-level `let`'s type but not a top-level one), and separately the
  checker's own top-level-`let` walk never invoked the annotation-vs-bound-expr
  check that a block-level `let` already gets. Both are fixed: the identical
  annotation on a `let` inside a function body and on a top-level `let` now
  behave the same way, including catching a genuine violation like the one
  above (`[]` does not satisfy `len(_) > 0`).

- **A qualified spelling inside a refinement predicate now enforces the
  contract**, e.g. `{List(Int) | List.length(_) > 0}` means exactly what
  `{List(Int) | len(_) > 0}` means (previously it parsed, typechecked, and
  silently enforced nothing — a warning added 2026-07-30 fixed the silence but
  not the capability gap). A narrow desugar slice now flattens a module-path
  call head found inside a `{T | …}` predicate the same way an ordinary call
  head is flattened, without running the full expression desugarer over the
  predicate. See
  `specs/progress/2026-08-03-refine-desugar-predicate-qualified-spelling.md`.

- **LSP semantic tokens: the `linear` and `affine` modifiers now follow the
  type system instead of use counts.** They were previously derived from how
  many times a name appeared — a binding mentioned exactly once was painted
  `linear`, one never mentioned was painted `affine` — so an ordinary
  `let x = 1` was highlighted in the editor as though the compiler had made a
  linearity guarantee about it. The modifier now comes from the three places
  the language actually states linearity: an explicit `linear` / `affine`
  qualifier, a `linear T` / `affine T` annotation, or a type declared
  `always_linear type`. Bindings whose linearity is only inferred are left
  uncolored rather than guessed at — under-reporting shows nothing, whereas
  over-reporting asserted a guarantee that was never made.
- **A `match` arm now knows what the earlier arms excluded.** In the safe-wrapper
  idiom — `match xs do Nil -> Err(…) | _ -> Ok(mean(xs)) end` — the `_` arm could
  not see that `Nil` had been ruled out, so a `len(_) > 0` precondition in it
  never discharged. Every such wrapper in a standard library carried permanent
  unprovable debt, and worse, `forge refine` could "fix" it by proposing
  `{List(a) | len(_) > 0}` — forbidding the exact input the function exists to
  accept. Reaching a later arm now contributes `not is_Ctor(s)` for each earlier
  arm whose failure is decided purely by the tag, and a tag test on a list is
  translated onto the same length symbol the obligation uses
  (`is_Nil(xs) <-> len(xs) = 0`).

  An earlier arm licenses nothing if it carries a guard or a refutable
  sub-pattern, since either can fail with the tag still matching. `stats.march`
  goes from 0 to 4 proved; the one function that still abstains is the one
  needing `len > 1`, which these facts genuinely do not give.

- **A match arm's excluded-constructor fact now reaches a user `@[measure]`,
  not only the built-in `len`.** The `len`/`List` case above is discharged by
  a hardcoded `is_Nil(xs) <-> len(xs) = 0` translation, which does not exist
  for a measure the author defines. `build_measure_preamble` now also emits a
  base-case linking axiom for any axiomatized measure whose base-case arm body
  is a literal — `(_ is Nil) x => size(x) = 0` — so the same exclusion fact
  connects for those too. A full stdlib `--refine-report` sweep is
  byte-identical before/after (no current stdlib measure has this shape), so
  this closes the general case ahead of the next measure that hits it rather
  than fixing an observed regression.

- **`Logger.random_hex` no longer drops the contract it forwards into.** A
  private wrapper passed its argument straight to `Crypto.random_hex`, whose
  parameter is `{Int | _ >= 0}`, without carrying that requirement — so every
  caller of the wrapper went unchecked. Found by `forge refine` sweeping the
  stdlib.


- **Every LSP command was dead code; `workspace/executeCommand` is now
  dispatched.** The handler sat in `on_unknown_request`, but linol routes that
  method as a *known* client request to `on_req_execute_command`, which the
  server never overrode — so linol's default returned `null` for all of them.
  The runnable code lenses shipped earlier (`march.runTest`, `march.debugTest`,
  `march.run`, `march.debug`) had therefore never worked: clicking "Run test"
  did nothing and said nothing. `march.suggestRefinement` now applies its edit
  through `workspace/applyEdit`, so it lands in the buffer rather than on disk.
  Found by driving the real binary over stdio, which is the only place a command
  is observable; guarded by a protocol-level regression test.

- **A builtin passed as a first-class value (e.g. `apply1(file_read, path)`)
  no longer SIGBUSes when compiled.** The codegen arm handling "builtin used
  as a value" emitted the raw C-extern address instead of wrapping it in a
  proper closure. Once that address was bound to a local, a later call
  through it dispatched as if it were a heap closure struct — reading
  garbage off the code address and jumping to it. Builtins used this way now
  get the same closure + trampoline treatment as ordinary top-level
  functions used as values, with the trampoline's argument/return coercions
  sourced from the builtin's own C signature. Interpreted execution was
  never affected.

- **Interpreted `extern` calls no longer crash when an `Int` argument is even
  and at least 4096.** The post-call cleanup in the interpreter's FFI bridge
  decided which arguments to release by looking at the marshalled bit pattern.
  `Int` arguments are marshalled untagged, so any even value at or above the
  runtime's `IS_HEAP_PTR` floor was indistinguishable from a pointer and got
  reference-count-decremented as though it were a heap object — dereferencing
  the integer and segfaulting. The bridge now tracks whether marshalling
  actually allocated each argument and drops only those. This mainly hit
  file-I/O externs, whose arguments are chunk sizes (`4096`, `65536`, …) and
  native handles cast to `Int`; an extern taking only `0`/`1` flags could
  never trip it. Because `forge test --coverage` runs on the interpreter, it
  showed up as coverage "breaking" on FFI file operations — but the crash was
  present with plain `MARCH_TEST_INTERPRETER=1` too and had nothing to do with
  coverage instrumentation.
- **A function's own parameter refinement no longer vanishes when it mentions
  another name.** `fn pick(n : Int, i : {Int | _ < n})` calling `at(n, i)` left
  its precondition unproven: the assumption-side resolver mapped every name that
  was not the refinement's own subject to nothing, and one such name discarded
  the entire predicate, so the verification condition consisted of its negated
  goal and nothing else. The identical fact arriving as a path guard
  (`if i < n do at(n, i)`) proved, which is what localised the defect to the
  channel rather than the solver. Cross-parameter and measure-bearing contracts —
  `{Int | _ >= 0 && _ < len(xs)}`, the canonical bounds contract — now forward
  through a call.

  Making those promises live exposed a shadowing hole in the same change: a
  promise mentioning a name that is later rebound (`let n = 0`) would attach the
  stale fact to the new binding and unsoundly discharge the call. Scope entries
  are now retired when their predicate mentions a rebound name, not only when
  their own name is rebound.

  Checked for the failure mode that matters: 0 refinement violations across all
  112 stdlib modules and 0 on a 43-file external project, so no correct code
  started failing.

- **Six stdlib modules (`ConsistentHash`, `WorkDispatch`, `RingBuf`,
  `Compress`, `DistLink`, `DistSupervisor`) no longer silently return garbage
  values from compiled programs.** Any stdlib module not registered in the
  compiler's eager-load list is typechecked for its export *shapes* only, not
  its body — so a generic `Option`/`Result`-returning function in that module
  (e.g. `ConsistentHash.get`) reached monomorphization with an unresolved
  call-site type and fell back to a boxed representation, while the caller
  (compiled at a concrete, niche-eligible type like `Option(Int)`) expected
  the unboxed niche encoding and read the discarded box's heap address as the
  payload — wrong value, no diagnostic, compiled only; the interpreter was
  unaffected. Same bug class as the pre-existing `Deque`/`ClusterLoad` fixes;
  these six were the remaining stdlib modules with the same shape. The
  general class of bug (a *future* stdlib module can reintroduce this by
  omission) remains open — see
  `specs/todos/2026-08-01-lazy-stdlib-loading-boxed-vs-niche-representation-mismatch.md`.
- **A local helper whose name collides with a top-level function no longer
  invents recursion.** The tail-call checker built its call graph by matching
  bare call names against the set of top-level function names, ignoring scope,
  so a call to a *local* helper with a colliding name forged a call-graph edge
  and fabricated a strongly-connected component. Because the entry module's
  declarations have the prelude spliced in, and prelude's `length`, `reverse`,
  `map` and friends are all written with a local `fn go` helper, any program
  with its own top-level `go` that called one of them was rejected with
  ``Function `go`: recursive call to `length` is not in tail position`` — for a
  `go` that is not recursive, against a `length` it does not call. Binders now
  shadow: an inner `fn`/`let` for the rest of its block, a `match` arm's
  pattern inside that arm, and `let?`'s pattern in its continuation — both in
  the call graph and in the tail-position check itself, so a local that shadows
  a member of a genuinely recursive group is no longer mistaken for it either.

  Relatedly, a name declared in an `extern` block is no longer treated as a
  call to a same-named ordinary function. An extern has no body, so it cannot
  recurse at all; declaring `extern fn length` and calling it reported the same
  bogus error.
- **`derive Json`'s generated `from_json` for enum and variant-with-args
  types now reports a JSONPath instead of one opaque
  `"invalid JSON for T"` error, and no longer panics on a nested-argument
  decode failure.** An unrecognized tag reports
  `Json.decode_error_to_string(e) == "$.tag: unknown variant \`X\`"`; a
  wrong-typed positional argument names its index, e.g.
  `"$[0]: expected Int"` (via a new `Json.JPathIndex` step, not
  `JPathField`); a missing tag or a non-object input reuse the same
  `"missing field"` / `"expected an object"` wording as the record decoder.
  An argument whose type is itself another `derive Json` type composes a
  path across the boundary the same way a nested record field does (via
  `Json.decode_error_under`). No wire-format change: the encoder/decoder
  both use a flat JSON object with a `"tag"` key plus positional
  string-numbered keys (`"0"`, `"1"`, ...) — there is no `"values"` array.
  The same pre-existing, separately-tracked `from_json` cross-type dispatch
  bug (recursive `from_json` calls resolve to whichever type derived `Json`
  most recently in the module) is unaffected by this change and remains
  open.
- **`derive Json`'s generated `from_json` for record types now reports a
  JSONPath instead of one opaque `"invalid JSON for T"` error, and no longer
  panics on a nested-record decode failure.** Each field is checked in turn,
  so a failure names exactly which field caused it — `Json.decode_error_to_string`
  renders it as e.g. `"$.age: missing field"` or `"$.name: expected String"` —
  and a field whose type is itself another `derive Json` record composes a
  path across the boundary (`"$.inner.id: expected Int"`). Unknown JSON fields
  continue to be ignored (unchanged). `Json.get_field(kvs, key)` was added to
  `stdlib/json.march` in support. A separate, pre-existing bug (recursive
  `from_json` calls resolve to whichever type derived `Json` most recently in
  the module, not necessarily the field's own type) is unaffected by this
  change and remains open.
- **`derive Json`'s `to_json` no longer misencodes a record whose field is
  itself another `derive Json` type.** `to_json(outer)` could panic with
  `record has no field '...'` when a record contained a field of another
  `derive Json`-derived type — the recursive encode call resolved back into
  the enclosing type's own encoder instead of the field's. Interpreter only;
  `from_json` is a separate, still-open issue.
- **A `use`-imported name in a nested module is no longer checked against an
  enclosing module's same-named function.** `resolve_call` (refinement
  checking) tried the lexical enclosing-module lookup before `use`-imported
  names, so a call inside a module that `use`-imports a name was rejected
  against an ENCLOSING function's contract — one the call never actually
  dispatches to at runtime. The lookup is now scope-aware: at each level of
  the enclosing-module walk, that level's own `use`s are consulted before
  falling outward, so a nested `use` correctly beats an enclosing definition
  while an outer module's `use` still loses to an inner module's own
  definition.
- **A refinement written in a `sig` or `extern` signature is no longer
  silent.** `sig Store do fn put : Int -> {Int | _ > 0} end`, and an `extern`
  function with a refined parameter or return type, both compiled with zero
  diagnostics while enforcing nothing — reading exactly like a working
  contract. Both now emit a warning naming the declaration and the spelling
  that does work. The two messages differ deliberately: a `sig` refinement is
  simply never read, and the remedy is the module's own `fn` definition; an
  `extern` refinement cannot be honoured *in principle*, because the callee is
  not March code, so the remedy is a March wrapper carrying the parameter
  refinement with the foreign result checked at run time. These shapes still
  compile — this makes the no-op audible, it does not make it an error.
- **A module member bound by a record-pattern `let` can now be referred to by
  its qualified name.** `let { port, host } = …` at the top of `mod Foo`
  bound `port` and `host`, but the desugarer's list of "names this module
  defines" skipped record patterns, so the bare spelling `port` resolved while
  the self-qualified `Foo.port` failed at run time with
  `unbound variable: Foo.port`. Record, atom, as- and or-patterns are all
  recognised now; the tuple form already worked.

- **The default HTTP server no longer strands connections past its worker
  count.** A pool worker owns a connection for that connection's entire
  keep-alive lifetime, so a *fixed* pool of N workers served at most N
  concurrent connections — every further connection was accepted by the
  kernel, showed the client a successful connect, and was then never read.
  With the default `ncpus*2` = 28 workers and 256 offered connections, 228 sat
  with unread bytes in `Recv-Q` indefinitely. The pool is now **elastic**: the
  worker count is a floor, and a worker about to park on a connection starts
  one more if it was the last idle one, up to `max_connections`. Measured at
  256 connections, order-swapped and repeated: **228 starved connections → 0**,
  and in-flight requests (throughput × latency) **27.7 → 253.7**. Reported
  average latency rises from 0.9 ms to 8.7 ms, which is the honest figure — the
  old number only averaged the 28 connections that were being served at all.

  `HttpServer.max_connections` now does something. It had been accepted and
  discarded (`(void)max_conns`), which is part of why the real limit was
  invisible; it is now the ceiling the pool grows to, defaulting to 1024.

  Servers with many mostly-idle keep-alive connections should still prefer the
  event loop (`MARCH_HTTP_EVLOOP=1`), which costs 15–17% less CPU per request
  and does not spend a thread per connection.

### Added

- **The compiled HTTP server is covered end-to-end by the test suite**
  (`test/test_http_native.ml`, carried by `run_stdlib.exe` and therefore by
  `dune runtest` and CI on both macOS and Linux). A total outage of the
  compiled server went unnoticed because the only end-to-end test of it,
  `test/test_http_native.sh`, was referenced by no dune rule and no CI
  workflow — and would have passed against two of the three defects anyway.
  The replacement compiles at `--opt 2` (every defect was compiled-only),
  makes ~65 requests against one process (one crashed on request 2), asserts
  on response *bodies* with two routes echoing request-derived data (one
  returned a well-formed `200` with an empty body), asserts the process is
  still alive and decodes `128 + signal` if not (one crash was silent), and
  covers the thread-pool and event-loop servers as equal peers. The only skip
  is clang genuinely absent; a broken server can never become a skip.

### Removed

- **`march_response_send_plaintext` is deleted.** It was a TechEmpower
  `/plaintext` fast path that hardcoded `Content-Length: 13` and the literal
  body `"Hello, World!"`, so reaching it required bypassing the user's March
  router entirely — the program nominally under benchmark would never have
  run. It had no callers and never had any. A general small-fixed-response
  path is separately not worth adding: the normal response builder is already
  zero-copy, with every iovec pointing at a March string or a static constant
  and one `snprintf` of Content-Length into thread-local scratch.

### Changed

- **The thread-pool HTTP server no longer pays for TCP corking on
  single-request batches.** `TCP_NOPUSH`/`TCP_CORK` were set and cleared around
  every response batch, but corking only earns its two `setsockopt` syscalls
  when the batch emits more than one `writev` — a single request is one
  `writev`, which the kernel already coalesces. Every non-pipelining client
  (browsers, curl, wrk — effectively all real traffic) took that path on every
  request. Measured on macOS/arm64: **−1.45 µs of ~32 µs CPU per request,
  −4.5%**, with `setsockopt` per request going 2.000 → 0.000. Throughput is
  unchanged, because on the measurement box the ~30k req/s ceiling is
  client/kernel-side rather than server-side.

- **The TFB HTTP benchmark harness measures the routes it claims to.**
  `bench/tfb/run.sh` drove wrk at `/plaintext` and `/json` while its March
  target was `examples/http_hello`, which routes only `GET /` — so both
  endpoints answered `404 Not Found` and every March number the harness printed
  was 404 throughput. There is now a real `bench/tfb/tfb_server.march` serving
  the same two routes as the Node and Python servers, the harness compiles it
  itself, and it aborts rather than reporting numbers if any server under test
  fails a route check. The `/json` body is serialized per request in all four
  servers (Node and Python previously wrote a buffer baked at startup, against
  March actually encoding), and all four now emit a byte-identical payload.
  The historical Run 1 / Run 2 comparison tables in `specs/benchmarks.md` are
  annotated as invalid rather than deleted; the Rust actix-web and FastAPI
  servers they reference have never existed in the repository, so those two
  comparisons cannot currently be reproduced.

### Fixed

- **The compiled HTTP server works again.** A compiled `HttpServer` panicked
  with `non-exhaustive pattern match` on the very first request, and once that
  was fixed it segfaulted on the second. Two outage-causing bugs, the second
  hidden behind the first, affecting both the default thread-pool server and
  the opt-in event-loop server (`MARCH_HTTP_EVLOOP=1`); a third latent
  representation bug was found and fixed alongside them. All were
  **compiled-only** — the interpreter was healthy throughout, which is why the
  interpreted `http_server` tests stayed green.

  1. `stdlib/websocket.march` re-declared `Conn`, `Header` and `Upgrade` as
     structural copies of the `HttpServer`/`Http` types, "mirroring" them
     because March has no imports. March has a single global type namespace, so
     these were always redundant; they became actively harmful once
     same-short-name types in different modules started receiving globally
     unique constructor tags. `HttpServer.Conn`'s tag moved off 0 while the C
     runtime's `march_conn_from_parsed` still wrote tag 0, so the value it
     handed to the pipeline matched no arm. The duplicates are removed, and
     `WebSocket.upgrade` now takes and returns the one true `HttpServer.Conn`
     rather than a same-shaped different type.
  2. `make_bool` in `runtime/march_http.c` heap-allocated a two-state object
     for `Conn`'s `halted` field, but a `Bool` field of a boxed ADT is a raw
     i64 0/1. This is a latent representation bug rather than a cause of the
     outage: `halted` is tested by its low bit and `march_alloc` is
     calloc-backed, so the pointer was always even and read as `false`. It is
     fixed because correctness should not rest on a pointer-parity
     coincidence, because any consumer treating the field as a real `Bool`
     would see a pointer, and because it allocated 16 bytes per request to
     carry one bit.
  3. The compiled apply-fn consumes one reference to a closure it is called
     with, but all three runtime call sites passed the server's single
     long-lived pipeline closure without bumping it first, on the assumption
     that holding it for the connection's lifetime was enough. Two requests
     dropped the refcount to zero, freeing the closure and its captured plug
     list; request three dereferenced freed memory.

  Note that `test/test_http_native.sh` — the only end-to-end test of the
  compiled HTTP server — is wired into neither dune nor CI, which is why a
  total outage of the built-in server went unnoticed.

### Added

- **JsonStream** — streaming JSON tokenizer: resumable chunk-fed parsing with
  bounded memory, depth/token limits, ndjson mode, and typed errors with
  absolute byte offsets. `max_token_bytes` now applies identically to number
  and string tokens (a degenerate `max_token_bytes = 0` previously accepted
  a 1-digit number while rejecting a 1-char string). New opt-in
  `JsonStream.with_raw_numbers(st)` emits the verbatim number lexeme
  (`EvNumRaw(String)`) instead of converting to `Float`, so integers above
  2^53 survive a round trip losslessly; the default mode is unchanged.
  **Performance:** string and number tokens are now sliced as whole runs
  instead of accumulated byte-by-byte, closing the gap to `Json.parse` to
  parity on string-heavy JSON (was ~55x slower); a residual ~3x gap remains
  on JSON with very short tokens (2-6 byte keys/values), which is a
  per-token overhead a future `feed_fold` API would address, not a scanning
  gap — no SIMD/C scanner was added, since the measurement showed one
  would not help.

- **`@[vectorize]` / `@[vectorize(warn)]` function attribute.** `NativeArray.map`/`map2`
  have had a silent auto-vectorization fast path for a while — whether it actually
  fires depends on how the callback closure is used, with no feedback if it doesn't.
  This attribute turns that into a checked compile-time contract: `@[vectorize]` on a
  function is a hard compile error if its `NativeArray.map`/`map2` calls wouldn't
  actually vectorize; `@[vectorize(warn)]` reports the same problem as a warning and
  lets the build continue. Two specific diagnoses are distinguished — a callback
  that isn't safe to inline because it's reused rather than passed directly to the
  map/map2 call, versus (for `Float` targets) a callback whose type is still generic
  rather than concretely `Float` — plus a hard error if the attribute is applied to
  a function that doesn't call `NativeArray.map`/`map2` at all. Fixed-width SIMD
  vector types (`f32x4`, etc.) remain a separate, future increment.

- **`cap verified`: an obligation the refinement checker cannot discharge is an
  error.** March's default stance is to report a refinement violation only when
  a precondition can *never* hold; anything the checker cannot decide is
  silence, so correct code is never rejected. A module that declares
  `cap verified` opts into the inverse: inside it, every skipped **precondition
  obligation at a call site** is reported, naming the precondition, the callee
  and the reason it could not be discharged (the predicate is outside the
  supported fragment, the argument did not reflect, a sort conflict, the float
  gate, or the solver not deciding). Strictly opt-in and scoped to the module
  that declares it — a `cap verified` module calling into an ordinary one does
  not make the callee's module strict, and nested modules do not inherit the
  capability. Modules that do not declare it behave exactly as before.

  `cap verified` now also escalates an undischarged **postcondition** (a
  function's own return-type refinement), not just a call-site precondition —
  the last place a fact was granted without obliging anyone. A return
  refinement the checker can neither prove nor refute is reported the same
  way a precondition is, naming the function, the predicate, and the reason;
  `@[trusted]` (see below) suppresses it there too. One limit worth knowing
  before relying on `cap verified`: a refinement written on an **`interface`
  method's signature** is not enforced at call sites (put it on the `impl`
  method's parameter, where it is — see the 2026-07-29 entries below), and an
  `impl` method's own parameter refinement is adopted only when its name
  unambiguously denotes one contract.

- **`@[trusted]`: a per-function escape hatch from `cap verified`.** `cap
  verified` used to be all-or-nothing — one obligation the checker could not
  discharge anywhere in the module forced dropping the capability entirely, or
  restating the fact with `assert`. Annotating a single function `@[trusted]`
  now accepts, as an assertion, any obligation *inside that function* the
  checker could not otherwise discharge — both a call-site precondition and
  the function's own return-type postcondition — without disarming
  `cap verified` for the rest of the module. It never suppresses a *definite violation* — a
  predicate the solver has proved can never hold is a bug in the annotation,
  not an incompleteness to wave through, so that case is still reported
  exactly as before — and it is scoped strictly to the annotated function: an
  ordinary sibling in the same `cap verified` module still escalates.
  `--refine-report`'s headline now has a fourth column, `N trusted`, counted
  separately from `proved` so a reader can tell how much of a module's
  "verification" is an assertion rather than a proof. Putting `@[trusted]` on
  a function in a module that does not declare `cap verified` warns, since the
  attribute would otherwise silently do nothing.

- **`--refine-report`: the checked fraction of your refinements is now a
  number.** `march --check --refine-report file.march` prints how many
  refinement obligations were proved, violated, and skipped — with each skip
  attributed to one of five reasons (unreflectable predicate, unreflectable
  subject, sort conflict, float-sort gate, solver undecided). Two slices are
  printed, "user code" and "user + stdlib", because the compiler prepends the
  whole standard library to every compilation. This exists because March reports
  a violation only when a predicate can *never* hold, which makes silence
  ambiguous between "proved" and "not checkable" — an ambiguity that let
  `{List(a) | len(_) > 0}` ship enforcing nothing while the suite stayed green.
  CI now ratchets in both directions — a ceiling on skips, read from the
  whole-program counts, *and* a floor on proofs, since a ceiling alone is
  satisfied by a checker that raises no obligations at all. The floor is read
  from the **user-code** slice of a fixture whose single obligation is actually
  *proved*, so it falls to zero the moment that proof stops happening; a
  whole-program proof count would not have moved. So a change that quietly stops
  checking things fails the build. Counts cover both precondition obligations
  raised at call sites and postcondition obligations (a function's own return
  refinement) — see the Fixed entry below.

- **A `List.length` guard now discharges a `len` refinement obligation.** The
  refinement checker treats `List.length` as an alias of the `len` measure, so
  an ordinary runtime guard — `if List.length(ys) > 0 do head(ys) else … end` —
  *proves* the precondition of `fn head(xs : {List(Int) | len(_) > 0})` instead
  of leaving it unprovable and silently skipped. A contradictory guard
  (`if List.length(ys) == 0 do head(ys)`) is now reported as a violation.
  Only the qualified `List.length` is aliased — a bare `length` is left alone —
  and only when it is the standard library's own, identified by the stdlib
  sources the compiler actually loaded (so it works the same from a repo
  checkout, an installed `share/march`, or a `MARCH_STDLIB` pointing anywhere).
  The alias is withdrawn for the whole module if anything could make that
  spelling denote a different function: a program defining its own
  `List.length` in any declaration form (a `fn`, a module-level `let`, an
  `extern` block, an interface or impl method) — including a program whose own
  entry module is *named* `List` — a vendored or forked `List`
  supplied through `MARCH_LIB_PATH`, or rebinding the name `List` via
  `alias`/`use`/`import`. In those cases the obligation
  goes back to being unprovable and silently skipped, which is the pre-existing
  behaviour; the alias never attaches `len`'s meaning to a function that is not
  the list's length.

- **A byte-length guard now discharges a `String` `len` refinement obligation.**
  The same treatment for strings: `String.byte_size` and the `string_byte_length`
  builtin are aliases of the `len` measure, so
  `if String.byte_size(t) > 0 do slug(t) else … end` *proves* the precondition of
  `fn slug(s : {String | len(_) > 0})`, and the contradictory `== 0` form is
  reported as a violation. `len` over a `String` is a **byte** count — `len("é")`
  is 2, not 1 — so only byte-valued spellings are aliased: `String.codepoint_count`
  and its legacy alias `grapheme_count` count codepoints and are deliberately left
  alone. `string_length` is left alone too, for a different reason: it is a byte
  length today (it lowers to `march_string_byte_length`, and `string_length("é")`
  is 2), but its *name* reads like a character count, so an alias written now
  would silently become unsound if the name were ever corrected to match. Use the
  unambiguous `String.byte_size` in a guard. The same shadowing rules apply: the alias is
  withdrawn for the whole module if a program defines its own `String.byte_size`
  (unless it is the standard library's own, by the identity above), rebinds
  `String` via `alias`/`use`, or binds the name `string_byte_length` itself —
  whether as a declaration, an import, a `let`, or a parameter. Also fixes a
  related gap: a guard mentioning a string length in a *path
  condition* reflected to a symbol unrelated to the one the contract used, so the
  two could never meet.

### Fixed

- **`char_from_int` now returns the same byte interpreted and compiled.** It is
  a byte constructor — the one-byte string `n & 0xFF` — which is what the
  compiled runtime always did, but the interpreter clamped to ASCII and returned
  the **empty string** for any `n > 127`, with no error. The same program
  therefore produced different output depending on how it was run, and anything
  built on a real byte silently lost data interpreted: `Uri.decode("caf%C3%A9")`
  returned `"caf"` in the interpreter and `"café"` compiled. Msgpack's raw-byte
  walk, `Http` header decoding and `Gen`'s char-list builder were affected the
  same way. Wraparound is part of the contract and matches the runtime: `256`
  yields byte 0, `-1` yields byte 255. `byte_to_char` is unchanged and still
  reports an out-of-range argument as an error — it builds the same byte, but
  its name promises one, so a value outside 0–255 there is a mistake worth
  hearing about.

  Known limitation: the JavaScript backend still implements `char_from_int` as
  `String.fromCodePoint(n)`, which differs above 255 and throws on a negative
  argument. Aligning it is a question about the JS UTF-16 string model rather
  than about this builtin, and is not addressed here.

  `Char.from_int` and `Char.to_int` were documented as converting "code points".
  They convert bytes, and now say so.
- **`examples/modules.march` runs again.** Its `pfn`-visibility demo used
  `mod Crypto`, which collided with stdlib's `mod Crypto` (`stdlib/crypto.march`)
  in March's flat, global module namespace — so calls like
  `remove_checksum(x)` resolved against the stdlib module instead of the
  file's own, and the example failed to typecheck (`Module 'Crypto' does not
  export 'remove_checksum'`) under both the interpreter and the
  interpreter-vs-compiled oracle sweep. Renamed the example's module to
  `SecretCode`; no compiler change, since the global-namespace behavior is
  by design (see `specs/lang` module system docs).
- **A nested constructor pattern over a type whose short name is shared with
  a stdlib type (e.g. `match rows do Cons(Row(fp), rest) -> ... end` where the
  user's own `Row` type collides by name with `DataFrame.Row`) no longer
  panics `non-exhaustive pattern match` when compiled.** It matched correctly
  interpreted; a destructured sub-pattern's erased type meant compiled codegen
  could pick the wrong same-named type's constructor tag.

- **`Json.parse` now accepts `\uXXXX` escapes.** The escape decoder handled
  only `\" \\ \/ \n \r \t \b \f` and rejected everything else, so
  `Json.parse("\"\\u0041\"")` failed with "unknown escape sequence" on input
  that is valid per RFC 8259 §7 — and that most serializers emit for any
  non-ASCII character. `\uXXXX` is now decoded and encoded as UTF-8, including
  surrogate pairs (`\uD83D\uDE00` → one astral code point). A surrogate that
  is not part of a well-formed pair, a `\u` with fewer than four hex digits,
  and a `\u` with a non-hex digit are all rejected with a message naming the
  problem.

- **A registry dependency now works for archive tasks, and brings its own
  dependencies with it.** Three gaps in `registry = "forge"` handling, all
  found while releasing scroll — which builds and tests green, then failed the
  moment its own `forge scroll.serve` task ran:

  - **Archive tasks saw no lib path for a registry dep.**
    `Archive_store.dep_lib_paths_for_archive` matched path and the three git
    forms then fell off a `| _ -> []`, so `RegistryDep` contributed nothing.
    `Cmd_build.dep_to_lib_paths` — which backs check/build/test — handled the
    same case, which is why a package could pass every check and still fail at
    run time with `Unknown module` for everything the dependency provides. The
    match is now exhaustive with no wildcard, so a future dep form is a compile
    error rather than a silently empty search path.

  - **`forge deps` did not fetch a registry package's own dependencies.**
    Resolution ran phase 1 (path/git, BFS) then phase 2 (registry, version
    solve) once each, and phase 2 only ever recursed into *registry* children —
    so registry → registry worked but registry → git/path did not, and a
    registry package's git dependency was never installed. The two phases now
    alternate to a joint fixpoint; the existing nearest-wins name dedup both
    preserves precedence and terminates the alternation.

  - **The CAS reused an install from the wrong source.**
    `~/.march/cas/deps/<name>` is keyed by dependency name only, and
    `install_dep` treated "directory exists" as "correctly installed" — so
    switching a dependency between registry and git reported `already
    installed` over the previous source's content and then failed with `fatal:
    not a git repository`. A git install is now reused only when its `origin`
    matches; otherwise it is re-installed. (Two projects wanting the same
    package at different revs still share one directory — fixing that means
    keying the path by source, tracked in
    `specs/plans/2026-07-30-forge-registry-dep-gaps.md`.)
- **A selector-less `use X.List` no longer withdraws the `List.length` measure
  alias when its target provably cannot provide a `length`.** The rebinding
  gate used to treat `use Extras.Deep.List` — anywhere in the compilation
  unit, including a `MARCH_LIB_PATH` dependency's internals — as a competitor
  purely because the path ends in `List`, silently turning every
  `{List(a) | len(_) > 0}` proof discharged by an ordinary
  `if List.length(ys) > 0` guard into a skip, program-wide (measured: one such
  `use` in a dependency flipped an entry program from `1 proved` to `1 skipped
  (alias-withdrawn)`). The use's target is now resolved and checked, the way
  glob imports already were: the alias survives only when every module the
  path could denote provably provides no member with the aliased name —
  re-exports (`use Y.{length}`), unenumerable globs inside the target, and
  unresolvable paths all still withdraw, as does `alias … as List` /
  `import X.{List}`. Same treatment for `String.byte_size`.

- **The `alias-withdrawn` explanation now follows a guard laundered through one
  `let`.** Under `cap verified`, `let n = List.length(ys)` followed by
  `if n > 0 do head(ys)` — where something in the compilation unit has
  withdrawn the `List.length` alias — used to report the generic
  `solver-undecided` text, pointing at z3 and advising the exact guard the
  author had already written. It now names the withdrawal and the binding that
  caused it, exactly as the direct `if List.length(ys) > 0` spelling already
  did. The verdict is unchanged (the obligation is still skipped); only the
  explanation improves. One `let` level only, and the attribution stays
  deliberately conservative: a guard laundered through a chain of `let`s, a
  guard on a different collection, or a guard whose laundering name (or
  collection) was rebound in between all keep the honest general message.

- **An `impl` method's refinement is no longer adopted when a `use` in the same
  module imports its name.** An `impl` method's parameter refinement becomes a
  contract every caller must satisfy only when the method name unambiguously
  denotes it. That test looked at sibling `fn`s and other `impl`s, but not at
  imports — so `use Other.{run}` beside `impl Runner(Box) do fn run(b, k :
  {Int | k != 0})` left `run` looking unambiguous — and depending on
  declaration order, a call the import resolves elsewhere was checked against a
  predicate it never touches (the false positive), or a call that really does
  reach the impl was checked correctly. Refinecheck cannot see that order
  distinction, so imports now compete for the name unconditionally: in the
  first ordering this removes a wrong rejection, in the second it trades a real
  check for silence — the deliberate direction, since a lost proof costs
  silence while a wrong fact rejects correct code. A glob (`use Other.*`, a bare `import Other`, or
  `import Other, except: […]`) names a module the checker cannot see at that
  point, so it withdraws every `impl` method contract in that module — the
  conservative direction, since the cost is silence rather than a wrongly
  rejected program. `use Other` with no selector binds the module, not a bare
  name, and withdraws nothing. Withdrawal is symmetric: a withdrawn contract
  cannot be assumed inside its own body either, so `cap no_panic` will ask such
  a body to prove a division safe some other way. Measured against the whole
  standard library and the typing corpus, this withdraws **zero** existing
  contracts.

- **A call that spells out the entry module's own name to reach an `extern`
  function now resolves.** `extern "libc": Cap(IO.FileSystem) do fn my_abs(x :
  Int) : Int = "labs" end` inside `mod Foo`, called as `Foo.my_abs(-7)`, failed
  with `unbound variable: Foo.my_abs` interpreted and `Undefined symbols:
  _Foo.my_abs` compiled, while the bare `my_abs(-7)` worked. March unwraps the
  entry file's own top-level module, and the pass that strips a redundant
  self-qualifying prefix knew only about `fn` and `let` members, so an `extern`
  member's self-qualified spelling never converged on its definition. `fn` and
  `let` members, nested-module references, and bare intra-module calls are
  unaffected.

  Known limitation, unchanged by this fix: an **interface method** name is not
  module-qualifiable at all — `Bar.greet(1)` does not resolve for any module,
  entry or nested. Call interface methods unqualified.

- **A refinement in an `interface` method signature no longer enforces nothing
  silently.** `interface Runner(a) do fn run : a -> {Int | _ > 0} -> Int end`
  parses and typechecks, and the predicate is never read: no call site is
  obliged by it, and no method body may assume it. Nor does it survive the
  front end — when a default method is injected into an `impl`, the synthesised
  function keeps no annotations from the signature. So it is a *missing* check
  rather than an unsound one, but a silent one, and the contract reads exactly
  like a working one. It now warns, naming the method and the spelling that
  works: the refinement belongs on the corresponding `impl` method's own
  signature, where a return refinement is always checked and a parameter
  refinement is enforced when the method name is unambiguous (exactly one
  `impl` defines it and no top-level `fn` shares the name). Following that
  advice needs no change to the interface — the typechecker accepts a refined
  `impl` parameter against a plain type in the signature. Making the interface
  signature itself enforce, so it obliges every call dispatched through the
  interface, remains open.

- **A qualified spelling inside a refinement predicate no longer enforces
  nothing silently.** `{List(Int) | List.length(_) > 0}` parses, typechecks,
  and checks nothing: the `List.length`→`len` alias keys on the dotted variable
  the *desugarer* produces, but refinement predicates are never run through the
  expression desugarer, so inside a predicate the name stays a field-access
  chain, the alias never fires, and the obligation is skipped — invisibly,
  since skipping is silence by default. The contract reads as working and does
  not work. It now warns, naming both the spelling found and the bare measure
  that does work (`len`); the same applies to `String.byte_size`. This is a
  warning rather than an error on purpose: the shape compiles today, so
  promoting it would break working builds, and the defect is the silence, not a
  missing capability — the bare spelling `len(_) > 0` has always enforced the
  contract. Desugaring predicates so the qualified spelling means what it reads
  as remains open.

- **`--refine-report` now counts return-type refinements, not just call-site
  preconditions.** A function's own return refinement (`fn mk() : {Int | _ > 0}
  do 100 end`) previously went through `check_post`, which discharged the
  obligation (proving it, reporting a violation, or silently giving up) without
  ever recording it — so `--refine-report` undercounted by every return
  refinement in the program, and a function whose *entire* contract was its
  return type was invisible to the report. `check_post` now files an obligation
  at every exit — proved, violated, or skipped with a reason (unreflectable
  predicate, sort conflict, float-sort gate, or solver-undecided) — tagged with
  a new `kind` (precondition vs. postcondition) so the two can be told apart;
  `--refine-report` prints a `by kind` breakdown line under each slice's
  headline. Behaviour-neutral: nothing newly errors, and `cap verified` still
  escalates only precondition obligations (postcondition escalation is a
  separate follow-up). `stdlib/list.march`'s `--refine-report` ceiling is
  unchanged at 28 skipped (it has no refined return types).

- **A refined annotation on a `let` is now checked against the expression it
  annotates, instead of being believed.** `let ys : {List(Int) | len(_) > 0} =
  []` used to compile: the annotation entered the refinement checker's scope
  unconditionally, so it became a *fact* about `ys`, and a later call needing a
  non-empty list was reported **proved** — off a premise nothing had
  established. `cap verified`, whose premise is "if it compiles, it is proved",
  accepted such a module. This was the one refined position in the language
  that obliged nobody; every other (a parameter at a call site, a return
  refinement, an `impl` method parameter) is checked somewhere.

  The obligation is the ordinary one, discharged by the same machinery that
  checks a call's argument against a parameter's precondition, and it keeps the
  same definite-failure stance: an annotation the checker can neither prove nor
  refute is **skipped**, never reported, so correct-but-undecidable code is not
  newly rejected. An unproven annotation does, however, now **grant no fact** —
  so `let ys : {List(Int) | len(_) > 0} = zs` for an opaque `zs` leaves both the
  annotation and any call relying on it skipped, rather than proving the call
  off an assumption the binding never established. All three spellings of the
  refined value behave alike (`_`, a declared binder, and the bound name
  itself); the bound-name spelling at `Int` was previously not resolved at all
  and is now checked too.

  **This can turn a program that compiled into one that does not** — namely any
  program carrying a `let` annotation that is actually false, which is the point.
  No such annotation exists anywhere in the stdlib or the conformance corpus, so
  nothing in-tree changed behaviour. Bracketed by
  `specs/lang/types/accept/t130_refine_let_annotation_checked_and_composes` and
  `specs/lang/types/reject/t131_refine_let_annotation_false`.
- **The `(`-led-statement fix now also applies after a literal.** The initial
  fix keyed the retag on a *value-ending* token — an identifier, a `)` or a
  `]` — but the call rule takes an `expr_field`, which a bare literal also
  reduces to, so `let _ = 1` followed by a line holding only `()` was still
  glued into `1()`. Unlike the identifier case this never reached the
  closure-ABI indirect call (a literal has no receiver to load a function
  pointer from): codegen emitted **invalid LLVM** — `declare ptr @<lit>()` —
  and clang rejected it with "expected function name", so the build failed
  with a diagnostic pointing at generated IR rather than at the offending
  source line. Interpreted, it raised `applied non-function value: 1`. The
  statement decision now uses a wider "ends an expression" predicate that
  includes `Int`/`Float`/`String`/`Bool`/atom literals; the narrower
  value-ending test still drives the curried-call guard's paren
  classification, so `f(1)(2)` diagnostics are unchanged.

- **A statement starting with `(` is no longer glued onto the previous line as
  a call.** A block line holding only `()` — or any parenthesised/tuple
  expression — following a line that ended in a value (an identifier, a `)`, a
  `]`) was parsed as that value's argument list. The common shape was a
  function that discards a parameter and returns unit:

  ```march
  fn f(a) do
    let _ = a
    ()          -- parsed as `let _ = a()`
  end
  ```

  which silently *invoked* the parameter. Interpreted this raised "applied
  non-function value"; compiled it was worse — codegen emitted the closure-ABI
  indirect call (load the function pointer from offset 16 of the receiver, then
  call through it), but the receiver was whatever value was passed in, so the
  binary jumped into a `String`'s character payload and died with
  `EXC_BAD_ACCESS` (exit 138) or `SIGSEGV` (exit 139) before running a line of
  user code. Both conditions were needed to trigger it, which is why it read as
  a codegen bug: without the discard there was no trailing identifier for the
  `(` to attach to, and with any other tail expression (`None`, `0`, a call)
  there was no leading `(` on the next line.

  The newline-separates-statements rule was already specified for the
  `f(1)`⏎`(g(2))` case; it now applies after *any* value-ending token. A call
  whose `(` is on the same line as its callee, and a call whose argument list
  spans several lines, are unaffected.
- **A capture-free closure used repeatedly in the REPL no longer leaks an
  allocation per use.** Passing a lambda that captures nothing — or a
  top-level function used as a value — to something that calls it (a
  higher-order function, `task_spawn`) allocated a fresh closure object on
  every materialization and never freed any of them, so a loop at the REPL
  prompt grew the live-object count in lockstep with its iteration count.
  Compiled programs were never affected: there, such a closure is a single
  immortal object shared by the whole program. Both capture-free shapes are
  now released, and compiled output is byte-for-byte unchanged.

- **`forge test` now resolves transitive dependencies.** `forge build` and
  `forge check` walk the dependency graph transitively — if your project depends
  on `B` and `B` depends on `C`, then `C`'s `lib/` is on `MARCH_LIB_PATH`.
  `forge test` built its own path from the *direct* deps only, so a test calling
  into a transitive dependency's module failed with "Unknown module ..." even
  though the identical call in `lib/` typechecked. `forge test` now uses the same
  transitive walk (with the same nearest-wins shadowing for same-named deps),
  applied to the test scope: `deps` + `dev-deps` + `test-deps`.

- **A refinement whose predicate measures the refined value itself is now
  enforced for user ADTs.** A contract like `{Tree | size(_) > 0}`, where `size`
  is a user `@[measure]` over `Tree`, checked *nothing*: the argument being
  passed was discarded and the predicate decided against an arbitrary tree
  instead, so `inner(Node(Leaf, 5, Leaf))` was not proved and `inner(Leaf)` — a
  real violation — was not reported. Both are now decided by the measure's own
  recursion axioms. The same measure applied to a *different* parameter
  (`{Int | _ < size(t)}`) worked all along, so the gap was invisible: a skip
  produces no diagnostic. Such contracts also now compose across a call
  boundary, like `len`-shaped list refinements: a caller whose parameter is
  `{Tree | size(_) > 0}` can pass that very tree on. Only the caller's own
  promise is loaded, so a weaker contract (`size(_) >= 0`) still does not
  discharge a stronger callee, and rebinding or shadowing the name retires the
  fact. Note this can turn a program that used to compile into one that does
  not: a call the checker previously skipped in this position is now decided, so
  a genuine violation like `inner(Leaf)` becomes a compile error.

- **A refined parameter's own constructor-tag promise now holds inside its own
  body.** A function whose parameter is `{Option(Int) | is_Some(_)}` could not
  pass that very value to another function requiring the same thing: the inner
  call's obligation was *skipped* rather than proved, because a caller-scope
  variable was always reflected as a fresh, unconstrained datatype value. The
  identically shaped *measure* contract (`{Tree | size(_) > 0}`) composed, so
  the difference was invisible — a skip produces no diagnostic. The caller's own
  tag promise is now loaded as an assumption over the same SMT term the
  obligation uses, for all **three spellings** of the refined value (`_`, a
  declared binder, the parameter's own name). Only the exact promised
  constructor is loaded: a caller promising `is_None(_)` still does not
  discharge a callee wanting `is_Some(_)` (the call stays skipped), and
  rebinding or shadowing the name retires the fact. As with the other
  composition fixes, a call the checker previously skipped in this position is
  now decided, so a genuine violation there becomes a compile error.

- **A refined list parameter's own promise now holds inside its own body.** A
  function whose parameter is `{List(Int) | len(_) > 0}` could not pass that very
  list to another function requiring the same thing: the inner call's obligation
  was *skipped* rather than proved, because a measure over a caller-scope
  variable was always reflected as a fresh unconstrained symbol. The identically
  shaped `Int` version composed all along, so the difference was invisible —
  a skip produces no diagnostic. The caller's own predicate is now loaded as an
  assumption over the same SMT symbol the obligation uses, so contracts compose
  across a call boundary for `len`-shaped list refinements the same way they
  already did for scalars. Only the *caller's* promise is loaded, so a weaker
  contract (`len(_) >= 0`) still does not discharge a stronger callee, and
  rebinding or shadowing the name retires the fact. All **three spellings** of
  the refined value compose identically — the anonymous `_`, a declared binder
  (`{v : List(Int) | len(v) > 0}`), and the parameter's own name
  (`{List(Int) | len(ys) > 0}`) — so renaming a binder cannot silently unwire a
  working contract.

  With the ADT-measure fix above and the constructor-tag fix below, this closes
  composition for every refinement shape: `Int`, `Float`, `Bool`, `String`
  `len`, record fields, the built-in list `len`, a user `@[measure]` over an
  ADT, and a constructor tag all compose. This is a distinct mechanism from a caller-established
  runtime **guard** (`if List.length(ys) > 0 do …`), which is unchanged: a guard
  is a test you write, a contract is a promise the caller already kept. It
  applies to **preconditions** only — a parameter's promise reaches calls in the
  body, not a refined return type. And a fact still does not survive a local
  `let` (`let u = 5` then `take_pos(u)` against `{Int | _ > 0}` is skipped), a
  pre-existing limitation for every type that this work does not change.
- **Capturing closures are no longer leaked, one allocation per
  materialization.** A lambda that captures a variable (`fn x -> x * k`)
  allocates a closure struct holding the captured values; nothing ever released
  it. The caller side deferred to the callee ("the callee consumes the closure")
  while the callee never dropped it, so a loop that built one closure per
  iteration leaked one allocation per iteration — measured at 4,000,000
  allocations and ~125 MB peak RSS for a 4M-iteration loop, against ~2.9 MB for
  the equivalent capture-free loop. The two sides now agree: `$clo` is pinned to
  the owned convention in the borrow map, so a caller increments when the closure
  is still live after a call and transfers its reference when it is not, and the
  apply function releases it. The same 4M loop now stays at the ~2.9 MB floor.
  Capture-free closures are unaffected — they were already routed to a single
  immortal global per site and are deliberately left alone.

  A **self-recursive** capturing closure no longer leaks either: its self-binding
  hands an alias a reference that used to be consumed only on the recursive
  path, so a base case that stopped using the alias dropped nothing. Fixed by
  releasing that reference explicitly wherever the self-binding goes dead,
  leaving the recursive path's existing transfer untouched.

  Not fixed: a genuinely capture-free closure (no captured variables at all)
  still leaks when materialized repeatedly from inside the REPL/JIT — natively
  such a closure is a single shared immortal object, but the REPL compiles each
  fragment as its own module and cannot safely share one.

- **REPL variable bindings (`let x = ...`, and the `v` last-expression-value
  binding) now correctly participate in reference counting.** Reading a
  heap-typed variable back from a later REPL line, or overwriting one,
  previously did no reference-count bookkeeping at all — a gap invisible
  until other fixes in this release started actually relying on it. Fixed;
  a plain `let`/`fn` at the REPL prompt is unaffected either way, since it
  gets a fresh slot per declaration, but repeatedly evaluating expressions
  (which reuses the `v` slot) is now correctly balanced.

  The ownership change above also required four fixes at the C-runtime
  boundary, since several places call a closure's apply function directly
  and did not agree with the new convention: `__try_call`/`__try_call_val`
  (used internally by `Check.try_prop` and directly callable) crashed
  intermittently on a single-capture callback; `NativeArray.map_int`/
  `map_float`/`map2` and `TypedArray.map`/`fold` crashed or corrupted results
  when passed a capturing closure; and a `Signal.watch` handler that captures
  a variable now survives being delivered more than once (it previously
  crashed reliably on the second delivery). All four are fixed and covered by
  new regression tests.

- **`cap no_panic` and `cap verified` now cover the whole module, not just its
  `fn`s.** Both passes walked only `fn` and nested `mod` declarations and
  ignored everything else, so a capability directive said nothing about code
  living in any other declaration form. A division by zero inside an `impl`
  method body passed `--check` with exit 0 and then panicked at run time with
  "division by zero"; the identical division inside a plain `fn` was correctly
  rejected. Obligations are now raised in `impl` method bodies, `interface`
  default method bodies, top-level `let` bindings, `actor` init/handler/
  `@invariant` expressions, `app` body and `on_start`/`on_stop` hooks, and
  `test` / `setup` / `setup_all` bodies (`describe` blocks recurse and inherit
  the enclosing module's capability). Both walks are now exhaustive over the
  declaration type with no wildcard, so a future declaration form is a compile
  error rather than a new silent hole.

  **This can newly fail a build that has no `cap` directive at all.** A
  *provably violated* obligation is reported regardless of any capability, so a
  call that definitely breaks a precondition — inside an `impl` method body or a
  top-level `let` — is now an error where it used to be silence. Those are true
  positives and the intended outcome, but they are a real behaviour change for
  ordinary modules, not just for capability-declaring ones. (The standard
  library is unchanged: its `--check` output is byte-identical before and
  after.) Witnessed by `specs/lang/types/{accept/t119,reject/t120}`.

- **A refinement on an `impl` method's parameter now obliges its callers — or
  binds nobody.** Widening the walk above created a subtler bug: the checker
  *assumed* an impl method's parameter refinements while walking its body, but
  the table of known contracts still recorded only `fn`s, so no caller was ever
  required to establish them. `fn run(b, k : {Int | k != 0})` made `m / k`
  provable inside a `cap no_panic` module while `run(Box(4), 0)` compiled
  cleanly and divided by zero at run time. Impl-method signatures are now
  registered, so the obligation lands on the call site. Registration is
  deliberately conservative — a method name is adopted only when no `fn` in the
  same module owns it and only one `impl` defines it, because a call resolved by
  name cannot tell two impls' contracts apart. When the name is ambiguous the
  refinement is stripped from the body as well, so it is never assumed by a body
  that no caller answers for. A refinement written in the **`interface`'s** own
  method signature is still not enforced at call sites; put it on the `impl`
  method's parameter.

- **A self-module-qualified call is checked wherever it appears.** `desugar`'s
  entry-module self-qualification stripper (`M.f(...)` → `f(...)` inside `mod M`)
  had its own wildcard and handled only `fn`, `let`, `actor` and `mod`, so
  `OuterB.g(-9)` written inside an `impl` method of entry module `OuterB`
  survived unstripped, resolved to nothing, and silently raised no obligation —
  while the identical call in a sibling `fn` was reported. That match is now
  exhaustive too, and also covers `interface` defaults, `app` hooks, `test`,
  `setup`/`setup_all`, `describe` and actor `@invariant` expressions.

- **The `List.length` / `String.byte_size` measure aliases were disabled for
  *every* March program, by one `import` in the standard library.** The gates
  that withdraw those aliases are unit-global, and a glob import (`import X`,
  `use X.*`) used to withdraw on its mere presence, on the reasoning that it
  might carry anything. But the compiler prepends the entire standard library to
  every compilation, and `stdlib/system.march` contains a single
  `import Process` — so every March program compiled since the feature shipped
  had the aliases withdrawn, and a `List.length` guard proved nothing anywhere.
  Nothing caught it: a withdrawn alias means the obligation is *skipped*, and a
  skip exits 0 exactly as a proof does, so the whole test suite stayed green
  while the feature was inert. A glob now resolves its target and withdraws only
  if that module actually provides a competing member (an unresolvable path
  still withdraws, and a real competitor reached through a glob is still caught).
  A second guard was added alongside it: a `use`/`alias` competes for the bare
  module name only when it is the *program's*, never the standard library's own
  — the same span exclusion the member-definition half always applied. The two
  are conjoined, so a glob withdraws only when it is your code *and* its target
  really carries a competitor. The blast radius is why the obligation *floor* in
  CI was moved onto a fixture whose count actually drops when this happens.

- **`cap verified`: a length guard that "silently stopped counting" now says so,
  instead of blaming the solver.** The `List.length` / `String.byte_size` /
  `string_byte_length` measure aliases are withdrawn for the whole compilation
  unit whenever anything in it could make the spelling denote something else —
  by design, since under the default stance the only cost is a missed proof. In
  a `cap verified` module a missed proof is an error, and it read
  `solver-undecided: the solver proved neither the predicate nor its negation`
  on code carrying exactly the guard the feature asks for. Both of its
  suggestions ("guard the call", "rewrite the predicate") were things the author
  had already done, because the real cause was a name binding somewhere else —
  a nested `mod Internal do mod List do fn length …` that is reachable only as
  `Q.Internal.List.length` and does not win at runtime, or an unrelated
  function's local `let string_byte_length = n + 1`, or, worst of all, a
  definition in a `MARCH_LIB_PATH` dependency the author never opened. Such a
  skip is now reported as `alias-withdrawn`, naming the spelling whose alias
  went and pointing at the binding that took it. Attribution asks for causal
  relevance, not mere presence: the predicate must use the affected measure,
  **and** a positive path condition must apply the withdrawn spelling to *this
  call's own argument*, **and** the spelling must measure the same kind of value
  (list spellings for a list, the byte-length spellings for a String). So a
  guard on a different list, a `List.length` guard in front of a `String`
  contract, a guard on the `else` side (which *disproves* the predicate and,
  without the shadowing binding, reports a genuine refinement violation), and an
  unguarded call all keep the plain `solver-undecided` message — in each case
  the binding you would be sent to rename is not why anything failed. Which
  obligations are suppressed is completely unchanged; only what the user is told
  changed. The reason also appears in `--refine-report`.

- **The optimizer's purity oracle no longer misjudges a monomorphized builtin
  call as pure.** Monomorphization rewrites calls to specialized names before
  optimization runs (e.g. `println` becomes `println$String`), and the purity
  check (used by `Inline`/`single_use_inline`/DCE/fusion) matched callee names
  with exact string equality against a bare-name impure-builtin list, so a
  specialized impure builtin like `println$String` was silently treated as
  pure. Fixed by stripping the specialization suffix before matching. No live
  miscompile was found or is claimed by this fix — it closes a latent
  correctness gap in the oracle (and a companion test-integrity gap where a
  native regression test passed regardless of whether the pass it targeted
  ran at all).

- **`cap no_panic`: an unreflectable divisor refinement is no longer accepted as
  a proof.** The division-safety check treated "this predicate is outside the
  checkable fragment" as a discharged obligation, which made a *meaningless*
  refinement more permissive than no refinement at all: `d : Int` correctly
  errored, while `d : {Int | is_prime(_)}` — a predicate the checker cannot
  reflect — passed having proved nothing. Such a divisor is now reported,
  failing closed exactly as the "solver unavailable or undecided" case already
  did. A path condition that genuinely proves the divisor non-zero (a `when
  d != 0` guard) still discharges the obligation. Only `cap no_panic` modules
  are affected; a refinement the checker *can* reflect is unchanged.

- **`cap no_panic`: a divisor refinement that *proves* the divisor non-zero is
  no longer rejected for being written unusually.** Closing the hole above
  over-corrected: the check reported anything its own reflection could not
  translate, and that reflection refused multiplication unless one factor was a
  literal. So `fn scale(d : {v : Int | v * v > 0})` — a predicate that is
  *exactly* `d != 0` over the integers, and that the solver decides instantly —
  was rejected with "outside the checkable fragment", even though the same
  program ran correctly without the capability. Such predicates are now sent to
  the solver rather than refused unread. The stance is unchanged: the checker
  tries harder to discharge, it does not accept what it cannot decide. A
  predicate that reflects but proves nothing (`v * v >= 0`, true of every
  integer) is still an error, as is one the solver cannot settle, and one it
  cannot reflect at all. Separately, a divisor guarded on the `else` side of a
  condition — `if d == 0 do 0 else 10 / d end` — is now recognised as safe;
  negated path conditions were previously dropped by the syntactic fallback
  while the solver route handled them. Witnessed by
  `specs/lang/types/{accept/t121,reject/t122}`.

- **`cap no_panic`: a guard or refinement no longer carries over to a *different*
  variable that happens to share its name.** The check identified the divisor by
  name alone, so rebinding that name inside the guarded branch left the outer
  fact in force. All four of these passed `--check` with exit 0 and then panicked
  at run time with "division by zero" — the failure the capability exists to
  prevent:

  ```march
  if d == 0 do 0 else (let d = 0; 10 / d) end     -- else side
  if d != 0 do (let d = 0; 10 / d) else 0 end     -- then side
  if d == 0 do 0 else ap(fn d -> 10 / d) end      -- lambda parameter
  if d == 0 do 0 else match o do Some(d) -> 10 / d ... end   -- match binder
  ```

  A name rebound by a `let`, a local `fn`, a lambda parameter, a `let?` pattern
  or a `match` pattern now retires everything known about the outer variable of
  that name — its guard, its refinement, and its `let` value. Correct programs
  are unaffected: `let d = 5` followed by `10 / d` is still accepted (the new
  binding replaces the old fact rather than merely erasing it), and a binder
  with a different name does not disturb the guard. Witnessed by
  `specs/lang/types/reject/t123` and the `divsafety-shadowing` test group.
- **A program that repeatedly passes a capture-free lambda (an anonymous
  function that reads no outer variables, e.g. `fn x -> x * 2`) as a value
  no longer grows memory without bound.** This extends the fix below for
  named functions to lambda expressions: such a lambda was allocated fresh
  on every materialization and never freed, even though its contents never
  change. It is now backed by a single shared object, the same way a named
  function value already is. The fix is not limited to anonymous lambda
  literals: any capture-free defunctionalized closure is covered, including
  local named helpers (e.g. the `go` accumulators `defun.ml` lifts out of
  `ELetRec`-bound local functions in stdlib code such as `List.map`), since
  they are lowered through the exact same closure-struct shape. Measured on
  a 4,000,000-iteration loop calling `apply_it(fn x -> x * 2, i)`:
  allocations for the materialization step went from 4,000,000 to 0 and
  peak memory from about 131.5 MB to about 3.0 MB, with identical program
  output before and after. Lambdas that capture a variable from the
  enclosing scope are unaffected by this fix and still leak — same open
  issue as the named-function capturing case below, tracked in
  `specs/todos.md`.
- **Calling a variable that holds a zero-argument function value (`let zf =
  answer; zf()`) is now a clear `--check` error instead of a runtime crash.**
  Assigning a top-level (or local) zero-arg function to a plain variable and
  then calling that variable used to typecheck silently and then crash with
  a segfault when compiled. It now reports `` `zf` is not a function — it
  has type `Int`. Remove the `()` and use `zf` directly.`` at compile time.
  The same fix also catches the more general `let x = 5; x()` case.
- **A closure or local function's parameter now shadows an imported function
  of the same name.** `import Logger` makes stdlib's `Logger.i` available as
  the bare name `i`; a nested `fn go(i, acc) do ... end` then compiled every
  use of its own `i` to that function's address instead of the parameter.
  Any binder whose name collided with an imported function was affected, so
  a program could silently pass a function where it meant a value — for
  example `Bytes.get(b, i)` receiving a code address as its index. This hit
  depot's Postgres wire decoder, whose `read_cstring` has exactly this
  shape, making every compiled database connection fail with
  `Bytes.get: index out of bounds`. Native backend only; the interpreter
  always resolved these correctly.

- **A program that repeatedly passes a named function as a value no longer
  grows memory without bound.** Materializing a top-level function as a
  first-class value (assigning it to a variable, passing it as a callback,
  storing it in a list or tuple) allocated a new heap object every time,
  even when the closure captured nothing — a real leak in any loop that
  repeatedly took a function value. Such closures are now backed by a
  single shared object per function instead of a fresh allocation each
  time. Measured on a 4,000,000-iteration loop: allocations for the
  materialization step went from 4,000,000 to 0 and peak memory from
  125.4 MB to 2.9 MB, with identical program output before and after.
  Closures that capture a variable (`fn x -> x * k` where `k` comes from
  the enclosing scope) are unaffected by this fix and still leak — tracked
  as a separate, open issue in `specs/todos.md`.

- **The REPL/JIT's precompiled stdlib prelude no longer emits the static
  closure globals above.** That optimization is intentionally gated off in
  REPL/JIT sessions (a REPL evaluation compiles and links a fresh module
  each time, so a global baked into one JIT'd fragment can't be safely
  shared or discarded across the session), but the JIT's stdlib-prelude
  precompilation path was missing the flag that opts a compiled fragment
  into that exclusion, so a handful of stdlib functions used as values
  (e.g. `Cluster.parse_addr`) picked up a static closure global anyway.

- **`String.to_uppercase` / `to_lowercase` no longer depend on the process
  locale.** They used C's `tolower`/`toupper`, which are locale-sensitive: under
  a single-byte locale (measured: `en_US.ISO8859-1` on macOS) `tolower` rewrites
  `0xC3`, the lead byte of every 2-byte UTF-8 sequence, silently corrupting the
  encoding. March never calls `setlocale`, but any linked library or embedding
  application can. Behaviour is now fixed regardless of locale, and the same
  change made them **~30× faster** (0.60s → 0.02s on `bench/string_case`).
  Scope is unchanged — ASCII only, non-ASCII bytes pass through untouched.

### Documentation

- **The refinement-types pages now state what is *not* checked, and two
  over-claims were corrected.** `specs/lang/refinement-types.md` gained an "Open
  holes" list and `docs/refinement-types.md` a `cap no_panic` section covering
  what that capability actually promises. Corrected: "every declaration form is
  covered" was true of *raising* obligations but read as "a refinement on an
  `impl` signature is enforced", which holds only when the method name
  unambiguously denotes one contract; and this changelog's claim that modules
  declaring no capability were unaffected was false, since a *provably violated*
  obligation is reported regardless of any capability. Both pages also quoted an
  `alias-withdrawn` diagnostic whose wording no longer matched the compiler's,
  found by re-running every published snippet. The residuals are now written
  down rather than left to inference: a refinement in an `interface`'s own
  signature is unenforced; the measure-alias gates are unit-global, so one
  competing binding anywhere — including in a `MARCH_LIB_PATH` dependency —
  disables the alias program-wide; postconditions are outside the obligation
  ledger, so `--refine-report` undercounts and `cap verified` silently permits an
  undischarged *return* refinement; and there is still no `@[trusted]` escape
  hatch.

- `stdlib/string.march` no longer claims the runtime has small-string
  optimisation. It had stated since 2026-03-19 that "strings of 15 bytes or
  fewer are stored inline without a heap allocation"; that was never true — every
  March string is a refcounted heap allocation with a 24-byte header. The header
  now also states plainly that `grapheme_count` counts *codepoints* despite its
  name, with the cases where the two differ.


### Changed

- The TIR optimizer folds a tuple element access to its source value when
  the tuple was just constructed (`let t = (a, b) in t.0` behaves like `a`
  at the compiler level), the same optimization already applied to record
  field access. Removes the tuple allocation wherever a tuple literal is
  immediately destructured (e.g. `let (a, b) = (x, y)`). No runtime speedup
  was measured — this reduces emitted allocations/struct loads, not
  benchmarked wall-clock time.
- **`Toml.parse` allocates ~10x fewer strings.** Same character-list-and-append
  pattern as `Json.parse` had, but worse — `Toml.parse` was allocating ~3.7
  heap strings per input byte, against JSON's 2.03 before its own rewrite. It
  is now a byte-index scanner, following the same template: bytes are
  inspected with `string_byte_at` (no allocation), tokens materialised with
  one `string_slice`. On a 340-byte document exercising tables, arrays, an
  inline table, and nested tables, compiled `--opt 2`: **allocs/byte 3.69 →
  0.37** (2,506,057 → 250,044 string allocations over 2,000 parses). Parsing
  is unchanged semantically; `TomlError` column numbers now count bytes
  rather than decoded characters, matching `Json.parse`'s precedent.

- **`Yaml.parse` allocates ~5.4x fewer strings** (5.56 → 1.02 allocs/byte,
  361-byte document, 2,000 iterations), **`Xml.parse` ~29x fewer** (2.92 →
  0.10 allocs/byte, 616-byte document), and **`Regex` compile/match ~19x
  fewer** (compile: 5.82 → ~0 allocs/pattern-byte; match: 1.215 → 0.064
  allocs/input-byte) — the same byte-index-scanner rewrite as `Json.parse`/
  `Toml.parse`, applied to the remaining pure-March parsers. `Uri.encode`/
  `decode`/`decode_query` (the only parts of `Uri` that had the per-byte
  pattern — `parse`/`to_string`/`merge` were already segment-based) go 4.0x
  fewer (2.96 → 0.73 allocs/byte). `Csv.read_all`/`each_row` were measured
  and left unchanged — already byte-at-a-time in the C runtime with no
  per-character March-level accumulation (0.106 allocs/byte). Parsing is
  unchanged semantically for all of these.

- **`Json.parse` allocates ~12x fewer strings and runs ~4.8x faster.** The
  parser used to begin with `string_split(src, "")`, exploding the document
  into one heap string per byte, so its cost scaled with the size of the input
  rather than with the number of strings in it — a 239-byte document holding
  ~20 strings cost 261 allocations per parse, 90% of them 7 bytes or smaller.
  It is now a byte-index scanner that inspects bytes with `string_byte_at` and
  takes one `string_slice` per token: **261 → 21 allocations per parse**, which
  is the number of strings the document actually contains. On a 1MB document
  holding 99,000 strings, one parse went from 1,100,041 string allocations to
  99,018 — allocation now tracks the document's string count rather than its
  byte size. `Json.to_string` got the same treatment (a string needing no
  escaping is now returned as-is, allocating nothing), taking a combined parse
  + serialize round trip from 486 to 58 allocations per iteration and 1.10s to
  0.24s over 20,000 iterations. Parsing is unchanged semantically; the only
  visible difference is that a non-ASCII character in an error message now
  prints correctly instead of as a single mangled byte.

- **String interpolation is ~1.45× faster** and allocates no intermediate list.
  `"a${x}b${y}c"` now desugars to a plain `++` chain at every length, which the
  compiler folds into three-way concats — where it previously switched to a
  `string_join` over a cons list past a size threshold. Measured at seven
  segments over 2M iterations: 519ms → 358ms, with the eight cons cells per
  interpolation dropping to zero.

- **…and interpolating a `String` no longer costs a refcount pair per operand**,
  which closes the rest of that gap. `"a${s}b"` goes through `to_string(s)`,
  which for a String resolves to an identity — but the identity call was only
  removed *after* reference counting had already bracketed it with an atomic
  increment/decrement, leaving the pair stranded around nothing. The call is now
  elided during lowering, so no pair is ever created, and interpolation compiles
  to exactly the same code as the equivalent hand-written `++` chain.
  Allocation counts are unchanged — this was refcount traffic, not allocation.


### Added

- **`string_byte_at(s, i)`** — reads the byte at a byte offset as `0..255`, or
  `-1` when out of range, allocating nothing. Before this, the only ways to
  look at one character of a string from March were `string_split(s, "")` and
  `string_slice(s, i, 1)`, both of which allocate a heap string per character
  inspected — so every hand-written scanner in the stdlib paid an allocation
  per input byte just to decide what the byte was.

- **`String.index_of_from(s, sub, start)`** — substring search from a byte
  offset, returning the index in `s`'s own coordinates so it can be fed
  straight back in when tokenizing. Without it, scanning for successive
  separators means slicing off the tail and searching again, which copies the
  remaining bytes at every step and makes a full tokenize O(n²).

- **`NativeArray.map2_int`/`map2_float`/`to_float_arr`** — a two-array
  zip-with primitive (`f(a_elem, b_elem) = out_elem`, panics on length
  mismatch) and Int→Float widening helper, for numeric ops over two
  `NativeArray`s at once. `DataFrame.col_add_col` (column-column arithmetic)
  now uses these instead of round-tripping through `List.zip`/`List.map`.

- **The docs site gained full-text search on ⌘K / Ctrl-K.** Every page on
  march-lang.org — the guides, the cookbook, and all 114 standard-library API
  pages — is now searchable from one box, opened with `⌘K`, `Ctrl+K`, `/`, or
  the Search button in the nav. Results are grouped by area (Guide, Cookbook,
  Stdlib) and include in-page heading links, so `↵` jumps straight to the
  relevant section rather than the top of the page. The index is built by
  [Pagefind](https://pagefind.app/) as a post-build step over the generated
  site, ships with it, and needs no search service at runtime.

  The same box also does **standard-library symbol lookup**, which previously
  worked only from inside the API reference itself. Typing a function or type
  name (`push`, `to_string`, `List.map`) puts a "Standard library" group above
  the prose results, each entry showing its kind and signature and linking
  directly to the definition's anchor — `Array.html#fn-push` rather than the
  top of the module page. Symbols are matched on name only, exactly or by
  prefix, so multi-word prose queries return prose results alone. The API
  reference pages keep their own `⌘K` for now.

  The index is committed at `docs/pagefind/` because march-lang.org is served
  by GitHub's own Jekyll running over `docs/`, which has no post-build hook —
  the same reason the generated stdlib API pages are committed. A CI check
  fails the build if a docs change lands without a regenerated index, since a
  stale index means the live search silently returns outdated results.

- **Session-type protocols gained a `stop` step to exit a `loop`.** A `loop
  do … end` protocol projects to the recursive µ-type `Rec X. S[X]` and,
  until now, had no way back out — every step inside the body, including
  every `choose` branch, looped back to the start, so a looping channel could
  only be abandoned, never actually `Chan.close`d. Writing `stop` inside a
  `loop` body (directly, or nested in a `choose` branch within one) exits the
  loop instead of repeating it, e.g.:
  ```march
  protocol Stream do
    loop do
      Prod -> Cons : Int
      choose by Cons:
        more -> Cons -> Prod : Bool
        done -> Cons -> Prod : Bool
                stop
      end
    end
  end
  ```
  `stop` is a contextual keyword (a plain identifier everywhere else, not
  reserved). `stop` written outside any `loop`, or steps written after a
  `stop`, are both compile errors.

- **`Bool` and `Float` refinement types are now enforced.** Both previously
  parsed and type-checked while checking nothing at all, so
  `fn needTrue(b : {Bool | _ == true})` accepted `needTrue(false)` and
  `fn sqrtish(x : {Float | _ >= 0.0})` accepted `sqrtish(0.0 -. 1.0)` in
  silence. `Bool` predicates now take the boolean operators against
  `true`/`false` (the bare-binder `{Bool | not _}` remains a parse error — write
  `{Bool | _ == false}`), and `Float` predicates take the comparisons `>= > <=
  < == !=` against float literals or another float value. Preconditions,
  postconditions, path-sensitive guards and postcondition propagation all work
  for both, and float literal arithmetic (`0.0 -. 1.0`) is constant-folded so a
  negative literal is recognised.

  Float obligations are discharged through Z3's **bit-precise IEEE-754
  FloatingPoint theory**, never by modelling floats as reals: over reals
  `not (x >= 0.0) && not (x <= 0.0)` is unsatisfiable, so a reals encoding would
  conclude the predicate can never hold and flag correct code, while over floats
  it is satisfiable (witness: `NaN`) and correctly stays silent. Equality is
  `fp.eq` rather than bitwise `=`, so `{Float | _ != 0.0}` rejects `-0.0` as
  well as `+0.0`. Symbolic float arithmetic in a predicate (`_ +. 1.0 > 0.0`),
  `Float` record fields and special-value predicates (`is_nan`) stay out of
  scope and are silently skipped rather than approximated.

- **Non-empty-collection preconditions, on 13 stdlib functions that panic on an
  empty argument.** `List.head`/`tail`/`last`/`minimum_int`/`maximum_int`, the
  `prelude` `head`/`tail`, `Stats.mean`/`min_val`/`max_val`, `Gen.element`/
  `one_of` and `Random.choice` now declare `{List(a) | len(_) > 0}`, so passing
  a literal empty list is a compile error instead of a runtime abort:
  ```march
  List.head([])       -- refinement violation: `len(_) > 0` cannot hold
  List.head([1, 2])   -- fine
  ```
  Each contract is derived from that function's own panic message, so none is
  stronger than the check the code already performed, and every `panic` remains
  as the runtime backstop for arguments the checker skips. A list whose contents
  the checker cannot see stays **unknown** and is skipped, never guessed. Note
  that an ordinary `List.length(xs) > 0` guard does not yet discharge the
  obligation — the runtime function and the `len` measure are not connected, so
  a guarded call is skipped rather than proved.

### Changed

- **Substring search is much faster.** `index_of`, `index_of_from`, `contains`,
  `split`, `replace` and `replace_all` now use a two-stage `memchr`+`memcmp`
  scan instead of testing every byte offset. Scanning a 1MB buffer for an absent
  needle went from ~809ms to ~21ms in `bench/string_scan` (roughly 0.5 GB/s to
  40 GB/s). `replace_all` additionally bulk-copies the spans between matches
  rather than one byte at a time.

- **Chained string concatenation allocates half as much.** `a ++ b ++ c` and
  longer chains are folded into three-way concats, so k parts cost
  `ceil((k-1)/2)` allocations instead of `k-1` and stop re-copying the growing
  prefix at every link. Measured 20% faster on a short-string building
  benchmark, with 23% less copying. Two-part `a ++ b` is unchanged.

- **`NativeArray.map2_int`/`map2_float` vectorize.** Extended the same
  compiler pass that lets `map_int`/`map_float` compile to real SIMD to also
  recognize `map2`'s two-array call shape — same eligibility bar, same
  boxing-free clone for a concrete-`Float` callback. Measured **~47x** on a
  5M-element benchmark (299 ms → 6.4 ms); previously slower than naive
  interpreted Python for the same operation, now beating hand-written OCaml.
  See `docs/simd-benchmarks.md`.

### Fixed

- **A measure over the refined value only worked under one of its three
  spellings.** In `{List(a) | len(_) > 0}` and `{v : List(a) | len(v) > 0}` the
  refined value reflected to a fresh unconstrained constant rather than to the
  call's actual argument, so the predicate was satisfiable at every call site,
  never a definite failure, and the contract silently checked nothing — while
  the third spelling, naming the parameter (`len(xs) > 0`), worked. Two
  consequences, both silent: the `_` form the documentation teaches gave no
  enforcement at all, and renaming a parameter unenforced a working contract
  with no diagnostic beyond an incidental unused-variable warning. All three
  spellings now resolve against the same actual, as the string and
  axiom-measure paths already did.

- **`Json.parse` rejected JSON numbers with a signed exponent.** `1e-5`,
  `2.5E+10` and `1e-308` all failed with `invalid number: 1e` — the number
  scanner accepted `+`/`-` only in the mantissa position, so it stopped at the
  sign after the exponent marker and handed a truncated `"1e"` to
  `string_to_float`. The scanner now follows RFC 8259's grammar
  (`["-"] int [frac] [exp]`), accepting a sign immediately after `e`/`E`.
  `1-2` still parses as `1` followed by a trailing-character error, as before.

- **`Json.parse` accepted number forms JSON does not allow.** Shape is now
  validated during the scan instead of being left to `string_to_float`
  (`strtod` / `float_of_string`), which is more permissive than JSON: `1.` and
  `01` previously parsed and are now rejected, joining `+1`, `Infinity`,
  `0x10` and `.5`. This is a behavior change for input that was never valid
  JSON — anything conforming to RFC 8259 parses as it did before.

- **A module-qualified constructor pattern could silently never match when
  compiled.** `match Json.parse(s) do Ok(Json.Array(_)) -> ... end` matched
  correctly interpreted but fell through to the catch-all arm in a compiled
  binary — no error, no warning, no crash, just the wrong branch. It affected
  any qualified pattern whose bare constructor name is declared by more than one
  module: in the standard library that is `Array` and `Null` (both
  `Json.JsonValue` and `Msgpack.Value` declare them), so `Json.Array(_)` and
  `Json.Null` were the visible casualties, while `Json.Object(_)` — a name
  unique to `JsonValue` — worked. Codegen identifies constructors by their
  *type* (`JsonValue.Array`), but the documented qualified-pattern syntax writes
  a *module* (`Json.Array`); when the two names differ the qualifier resolved to
  nothing and the pattern fell back to matching on the bare name, which then
  picked whichever module's constructor the compiler happened to enumerate
  first. The qualifier is now translated to its declaring type during lowering,
  so an explicitly qualified pattern resolves to exactly the constructor it
  names.

- **`Json.to_string` crashed on every JSON array and object under `--target js`.**
  It died with `TypeError: f._0 is not a function`, while the same program was
  correct interpreted and compiled native. The cause was not in `json.march`: a
  closure allocated inside a match arm whose scrutinee cell is dead gets
  rewritten by Perceus from `EAlloc` to `EReuse`, and the JS backend's `EReuse`
  and `EStackAlloc` cases were missing the rule `EAlloc` had — a closure's apply
  function lives in slot `_0` and must be emitted as the raw function, not as
  the `name$clo` wrapper *object*. Closure dispatch then did `f._0(f, x)` on a
  record instead of a function. This hit any lambda passed to a user-defined
  higher-order function from a reuse-eligible match arm, so `Json.to_string` was
  the symptom rather than the bug. The three allocation forms now share one
  emitter, so they cannot drift apart again.

- **`String.slice` returned the wrong text on the JS backend.** The JS runtime
  implemented `march_string_slice(s, start, len)` as `s.slice(start, len)`,
  treating the third argument as an END index rather than a LENGTH, so every
  slice with a non-zero start was wrong — `String.slice("abcdefgh", 5, 3)` gave
  `""` on JS against `"fgh"` interpreted and compiled. Negative arguments now
  clamp the way the C runtime clamps, instead of being read as offsets from the
  end of the string.

- **TIR pipeline stages are now inspectable as text.** `MARCH_DUMP_TXT=<stage>`
  prints the pretty-printed TIR at any pipeline checkpoint whose label contains
  the given substring (`all` for every stage). Previously only the very end of
  the pipeline was readable, via `--dump-tir`, which is too late to tell whether
  a pass created a construct or merely preserved one.

- **The SIMD Benchmarks results tables rendered as raw pipe characters.** The
  three tables under "Results" on
  [/docs/simd-benchmarks/](https://march-lang.org/docs/simd-benchmarks/) were
  wrapped in `<div style="overflow-x:auto">`. Kramdown does not parse markdown
  inside a raw HTML block unless the element carries `markdown="1"`, so each
  table was emitted verbatim as text. The wrapper was also redundant — the docs
  layout already sets `display:block; overflow-x:auto` on content tables, which
  is why the same page's other two tables were fine — so it is simply removed.

- **Discarding a container no longer leaks its contents.** March reclaimed an
  aggregate only by *destructuring* it; releasing one that was never pattern-
  matched freed the top cell alone and orphaned everything under it. This hit
  the ordinary way to consume a `String.split` result — passing it to a
  function that borrows it — so bulk text processing leaked in proportion to
  its input (a 60-iteration split/consume loop peaked at 585 MB, growing
  linearly; it now holds flat at 16 MB). It was never about how the container
  was traversed: a consumer that ignored its list argument entirely leaked
  just the same. Compiled targets only — the interpreter was unaffected.
  `bench/binary_trees.march` drops from 157 MB to 6 MB peak as a result.
- **A tail-recursive `Cons(_, t)` walk no longer strands a reference on every
  cell.** The self-TCO back-edge skipped *every* refcount op on a forwarded
  argument, to fix a use-after-free on a freshly allocated one. A list walk's
  tail is not freshly allocated — it is dup'd from the matched cell, and that
  dup's matching release was being skipped, leaving each cons cell pinned.

- **`DataFrame.eval_agg`'s `Min`/`Max`/`Std`/`Variance` no longer materialize
  a boxed `List(Float)` per call.** These aggregates previously converted the
  column's `NativeArray` into a linked list before folding over it, an O(n)
  allocation on top of the O(n) reduction that showed up as tens of
  milliseconds per call on large columns regardless of which aggregate ran.
  They now use dedicated native-array reduction builtins (mirroring `Sum`),
  bringing them roughly in line with the already-fast `Sum`/`Mean` path —
  60-80x faster at 500K rows in local measurement. `Median` still sorts and
  is unaffected by this fix.

- **Compiled string literals no longer leak once per evaluation.** A literal
  used as a direct operand — most commonly `acc ++ ", "` or `s ++ "\n"` inside
  a loop — allocated a fresh string every time it was evaluated, and nothing
  ever freed it, so ordinary string-building loops grew memory without bound
  (a 2M-iteration concat peaked at 64MB of RSS against 2.9MB for the same loop
  with both operands bound to variables). Each literal now allocates one shared
  string for the whole program, matching how the compiler's ownership analysis
  has always treated literals: as constants that no binding owns. Only the
  compiled backend was affected; the interpreter was always correct.
- **A bare `Bool` variable used as a guard no longer produces a malformed
  solver query.** `if j do … end` around a refined call reflected `j` as an
  integer constant and asserted it as a formula, which z3 rejects; the
  obligation was then silently undecidable. Such a variable is now declared at
  the `Bool` sort, and a Boolean-position well-sortedness guard drops anything
  that still is not a formula rather than emitting it.

- **The compiled-binary cache no longer serves a stale binary after a
  `runtime/*.c` edit.** The CAS key digested a runtime directory it resolved
  itself, searching the current directory *first*, while the compiler picks the
  sources it hands to clang exe-relative *first* ("independent of CWD"). Run
  from the repo root against `_build/default/bin/main.exe`, those are two
  different directories, so the key could be identical (or differ for reasons
  unrelated to what was built) while the compiled output differed — a runtime
  edit could print `compiled <out> (cached)` for a binary containing none of
  the new code. The driver now resolves the runtime directory once and
  registers it with the CAS, so the key always digests the sources actually
  compiled; `MARCH_RUNTIME_DIR` overrides the search, mirroring `MARCH_STDLIB`.
- **`MARCH_STRING_STATS=1`** — an opt-in profiling mode for compiled binaries.
  Set the environment variable and the program prints string-allocation
  statistics to stderr at exit: allocation count and bytes, a size histogram,
  bytes copied, frees, peak live bytes, and non-string heap allocations. Off by
  default and measured at −0.34% overhead when off. Intended for answering
  "where is this program's string cost going?" without a profiler.

- **String benchmark suite** — six benchmarks in `bench/` (`string_scan`,
  `string_case`, `string_split_large`, `string_slice_walk`,
  `string_small_churn`, `string_parallel_scan`), each isolating one cost, run
  by `bash bench/run_string_bench.sh` into `bench/STRING_RESULTS.md`. Documented
  in `specs/benchmarks.md`; findings in
  `specs/2026-07-26-string-performance-profile.md`.

### Changed

- String interpolation with many parts (`"${a}${b}${c}${d}"`) now desugars to
  a single `string_join` call over all parts instead of a left-deep chain of
  `++`, which re-copied the growing prefix on every append. This makes a
  k-part interpolation O(n) instead of O(k²) in total bytes copied, with no
  change in the resulting string value. Short interpolations (up to three
  segments, e.g. `"count: ${n}"`) keep the `++` chain, which measures faster
  at that size than materializing a list to join.
- Compiled `NativeArray.map_float` with a plain, concretely-typed
  callback (`fn x -> x *. 2.0 +. 1.0`, a captured scalar, or similar — no
  generic/unresolved types involved) no longer allocates at all for each
  element crossing the callback boundary, and the resulting loop can
  actually be vectorized by the backend compiler on suitable inputs. A
  callback whose type isn't fully known at this point still allocates one
  reusable cell per call (an earlier improvement over one per element) and
  is unaffected by this change. No observable behavior change either way.

- Compiled `NativeArray.map_float` now allocates one boxed-float cell per
  call and reuses it across all elements, instead of one per element. Cuts
  allocation traffic and GC pressure substantially for large arrays (a
  stress-test benchmark measured roughly 2x less wall-clock time); no
  observable behavior change.

- Native and WASM LLVM output now describes `march_alloc` as a fresh,
  non-null allocation whose argument is its allocation size, and marks
  generated closure ABI trampolines `alwaysinline`. This gives LLVM useful
  alias and call-boundary facts without changing TIR or ownership semantics.

- The TIR optimizer inlines a private top-level function's body at its call
  site when that function has exactly one direct, arity-correct reference
  anywhere in the module, even when the body is not pure. Ordinary pure-only
  inlining, the 50-node size limit, DCE-root/address-taken/hot-code-reload
  exclusions, and recursive-SCC detection (extended to cover bare/qualified
  name aliasing) all still apply; Perceus RC operations and their order are
  preserved unchanged. No runtime speedup was measured — this is a
  definition/call-site reduction in emitted LLVM, not a benchmarked
  optimization.

### Added

- **Refinement Tier 2: structural induction over recursive functions.** A
  relational postcondition on a structurally recursive function —
  `fn insert(t : Tree, x : Int) : {Tree | size(_) == size(t) + 1}` — is now
  *proven* at its definition and therefore propagates to call sites, instead of
  being silently skipped. Z3 still does no induction; the checker supplies the
  **induction hypothesis** at each self-recursive call whose argument is a
  proper component of the matched parameter, then discharges each `match` arm
  against the `@[measure]`'s recursion equations. Relational and closed
  predicates over a variant-ADT return both work, recursion may descend into
  any recursive component, and a growing accumulator parameter is fine.
  Unchanged and still silent: mutual recursion, the built-in `len` (declare a
  user `@[measure]` instead), a recursive call inside a lambda or behind a
  nested `match`, and any non-structural recursion — the hypothesis is gated by
  the same `structural_subvars` test that makes `@[measure]` axiomatisation
  sound, because an unsound hypothesis would manufacture false positives rather
  than merely fail to help. `Int`-returning postconditions are untouched. See
  `specs/lang/refinement-types.md` for the exact frontier, including the three
  stacked obstacles that still separate this from the stdlib HAMT.

- **Two higher-order refinement checks.** A call made *through* a refined
  function-typed parameter — `fn ap(f : ({Int | _ >= 0}) -> Int) : Int do
  f(-3) end` — is now rejected, and so is a call through a **local alias** of
  a named refined function — `let g = takepos  g(-3)`. Both previously fell
  through the checker's named-callee-only call resolution and were silently
  skipped. Single-argument callback types only; a callback parameter whose
  own declared type is unrefined is unaffected — see
  `specs/lang/refinement-types.md`'s Limitations section for the exact
  boundary.

- A **guard on a record field** now reaches the refinement checker. `if
  c.port >= 1 do serve(c)` discharges a `{v : Config | v.port >= 1}`
  precondition, and the contradictory `if c.port <= 0 do serve(c)` is reported
  as a definite failure. The variable needs no refinement of its own — a plain
  `c : Config` parameter works, since an unrefined record is modelled as an
  unconstrained value that the guard then decides. With no guard the call is
  still skipped. Field facts obey the same rebinding rule as tag and scalar
  facts: a `let`, `let?`, lambda parameter or `match` binder that rebinds the
  name retires the fact.

- An **unreflectable record field no longer hides its siblings** at a call
  site. `serve({ port: 0, name: n })` and `serve({ port: 0, history:
  Cons(1, Nil) })` used to be skipped whole, because a `String` field bound to a
  variable and a list literal with concrete elements cannot be placed at their
  declared SMT sorts. The offending field is now replaced by an unconstrained
  stand-in of the right sort, so `port` is checked and both calls are reported.
  Nothing may be concluded *about* the stand-in in either direction, and the
  return side keeps the conservative whole-record skip.

- Refinement checking now propagates **relational** return refinements — those
  that mention a parameter — by substituting the call's arguments for the
  callee's parameters. Given `fn below(n : Int) : {Int | _ < n}`, the call
  `takepos(below(0))` is a compile error because `_ < 0` can never satisfy
  `_ >= 0`, while `takepos(below(10))` stays silent. Arguments are matched
  positionally and substituted simultaneously, so `f(m, 1)` against
  `{Int | _ < n + m}` yields `_ < m + 1`, not `_ < 1 + 1`. As before, only a
  postcondition the definition side actually *proved* propagates, and
  instantiation is skipped entirely rather than done partially when an argument
  is missing, the predicate mentions an unknown name, or the callee takes a
  pattern parameter — correct code is still never flagged.

- As-patterns: `Some(x) as whole -> ...` binds a name to the entire matched
  value while the inner pattern continues to destructure it. Works in match
  arms, `let` bindings, and function parameters. `PatAs` had been implemented
  in the AST, interpreter, and typechecker since the beginning but had no
  grammar production.

- Record patterns: `match r do { x, y: b } -> ... end`, `let { x, y } = r`, and
  `fn area({ w, h })`. `{ x }` is shorthand for `{ x: x }`. `PatRecord` had
  existed in the AST and interpreter since the beginning but had no grammar
  production, and neither TIR lowering path handled it.

- Record patterns now take part in exhaustiveness and redundancy analysis.
  A match that handles only some values of a field — `match p do { code: 404 }
  -> ... end` — is reported non-exhaustive instead of typechecking clean and
  panicking at runtime, and a record arm already covered by an earlier one is
  reported unreachable. Previously the checker's internal pattern shape had no
  record case, so any arm containing a record pattern read as a wildcard.

- Record patterns nested inside a constructor payload may name a subset of the
  record's fields: `Some({ status: s })` against an `Option` of a two-field
  record now typechecks. The constructor's argument types were only linked to
  the scrutinee's payload *after* its sub-patterns were inferred, so a nested
  record pattern saw an unresolved type variable and fell back to requiring
  every field. The full-field form happened to unify anyway, which is why this
  went unnoticed.

- Record patterns in `let` and `let?` bindings may also name a subset of the
  record's fields — `let { code: c } = p` no longer requires naming every
  field of `p`. The binding's right-hand side supplies the expected type; it
  simply wasn't being passed to the pattern. Naming a field the record lacks
  now gives the same `unknown_record_field` error the `match` path gives,
  instead of a unification mismatch that leaked an internal type-variable
  name. A bare record pattern used directly as a function parameter stays
  closed — that position has no annotation to source a type from.

- Record patterns may mention a subset of a record's fields: `{ code: 404 }`
  matches any record with a `code` field equal to 404, whatever else it has.
  Naming a field the record does not have is a compile error.

- Or-patterns: `1 | 2 | 3 -> "small"` matches an arm against several
  alternatives. Alternatives may bind variables, provided every alternative
  binds the same names at the same types (`A(x) | B(x) -> x * 10`); they share
  one arm body which reaches those names as parameters, so `A(x) | B(y)` and a
  name bound at two different types are both compile errors. Exhaustiveness
  and redundancy checking see through or-patterns at any nesting depth.

- A refinement over a **record's fields** is now checked on **parameters**, not
  just return types. Given `fn serve(c : {v : Config | v.port >= 1})`, the call
  `serve({ port: 0 })` is a compile error. A record literal argument is a fact
  (fields are matched by name, so declaration order doesn't matter), and a
  variable holding a record-refined parameter carries its fields through, so
  forwarding to a same-shaped parameter verifies. An unrefined record, a record
  literal with an unknown field value, or a field outside the reflected
  fragment is skipped rather than guessed at — the definite-failure stance is
  unchanged, and correct code is never flagged.

- Refinement types now support `String`. `len` measures a String as well as a
  list, so `{String | len(_) > 0}` and `{String | _ != ""}` are checkable
  contracts and passing an empty string literal to a non-empty parameter is a
  compile error. `len` counts bytes, matching the `string_length` builtin.
  Which `len` applies is decided by the value's declared base type, so list and
  String uses coexist unambiguously. The encoding models `String` as an opaque
  sort and deliberately avoids SMT string theory, so there is no prefix/suffix/
  contains/regex reasoning, and an `s == ""` guard does not establish a length
  in the else-branch — see `specs/lang/refinement-types.md` for the full limits.

- Refinement checking now propagates a function's declared return refinement to
  its call sites, so passing a `{Int | _ < 0}` result into a `{Int | _ >= 0}`
  parameter is a compile error. Applies to both `takepos(neg())` and
  `let c = neg()` forms, and resolves across modules via `alias`/`use`.
  Only postconditions the definition side actually *proved* propagate — an
  unproven one stays legal but tells callers nothing, so a stale return
  refinement can never flag correct code. Postconditions that mention a
  parameter (relational) are not yet propagated.
- Refinement predicates can now constrain an ADT's **constructor tag**. Every
  constructor of every type — including the built-in `Option`, `Result` and
  `List` — gains an implicit `is_<Ctor>` tester, so `fn unwrap(o : {Option(Int)
  | is_Some(_)})` is a checkable contract: `unwrap(None)` is a compile error,
  and so is `unwrap(x)` written inside a `None ->` match arm, where the arm
  narrows the scrutinee's tag. Testers are exact-case (`is_some` is not
  `is_Some`). Narrowing is skipped for a non-variable scrutinee, for an `as`
  pattern, for an arm that rebinds the scrutinee's name, and for a constructor
  name shared by two ADTs — in each case the checker stays silent rather than
  guessing. A fact is recorded against a *name*, so any inner `let`, `let?`,
  lambda parameter or nested `match` binder that rebinds that name retires it.
- Refinement predicates that call an unknown function now produce a warning
  instead of being silently ignored. `{Int | totally_bogus_fn(_) > 0}` compiled
  clean and enforced nothing; it now says so. The supported vocabulary is the
  comparison/arithmetic/boolean operators, `len`, and `@[measure]` functions.

### Fixed

- `DataFrame`'s `Sum`/`Mean` aggregations (compiled builds) now compute
  directly over the column's underlying array instead of first converting
  the whole column to a list. Purely a missed-optimization fix — same
  results, less work per call. `Min`/`Max`/`Std`/`Variance`/`Median` are
  unaffected (no equivalent fast path yet).

- **Compiled `NativeArray.map_int`/`map_float` now inlines closures that
  capture a variable**, not just plain `fn x -> ...` lambdas — e.g.
  `fn x -> x +. f` or `fn x -> x *. f`, the exact shape
  `DataFrame`'s `col +. scalar` / `col *. scalar` use. Previously any
  captured variable disqualified the closure from the Phase 2 (P10)
  inlining optimization entirely, so this was a real, already-shipping
  workload getting none of the benefit. Purely a missed-optimization fix;
  behavior was already correct, just slower than it should have been.
- **Refinement checker no longer flags correct code when a local reuses a
  refined function's name.** A `let`, `let?`, lambda parameter, local-`fn`
  name or parameter, `match` arm binder, or function parameter that happened
  to share a name with a module-level refined function had its calls checked
  against that function's precondition — even though the local is what
  actually runs. `let takepos = fn n -> n` followed by `takepos(-3)` reported
  a bogus violation. Callee resolution now obeys the same shadow discipline as
  every other fact channel: a name an enclosing binder introduced never
  resolves to a global function.

- **`{T | size(_) < 0}` is now checked, like its named form `{v : T | size(v)
  < 0}`.** The anonymous binder — the spelling the reference teaches — was
  emitted verbatim as an SMT symbol when it appeared inside a measure
  application. `_` is a reserved SMT-LIB token, so the solver rejected the
  query and the predicate was silently never decided: the documented idiom
  checked nothing while the named spelling worked. Both spellings now reflect
  to one canonical symbol and produce identical verdicts.

- **Compiled `NativeArray.map_int`/`map_float` now inlines even when the
  mapped array is reused afterward.** The Phase 2 closure-inlining
  optimization (P10) silently never fired whenever code used the array
  again after mapping it — e.g. a self-recursive loop that maps `arr` and
  then passes `arr` on to its own tail call — because an unrelated Perceus
  reference-count operation sitting between the closure allocation and its
  alias binding made the pass bail out and fall back to the slower,
  unoptimized closure-call path. That "map an array you're about to use
  again" shape is extremely common, so this covered the large majority of
  real `map` call sites. Purely a missed-optimization fix; behavior was
  already correct, just slower than it should have been.

- `march --compile` no longer fails with "cannot find runtime/march_runtime.c"
  when invoked from a working directory other than the project root. Six
  independent lookups for files under `runtime/` were each missing an
  exe-relative candidate that resolves the actual dune build layout, so any
  invocation outside the repo root (or a `_build/default/bin/main.exe` build)
  fell through to a dead CWD-relative fallback.

- **The compiled-artifact cache could return a different program's binary.**
  It stored the *path* the compiler wrote to rather than the binary itself, so
  nothing owned that file. Compiling one program, then another to the same
  `-o` path, then the first again to a new path served the second program's
  binary — reported as `(cached)`, with no error:

      march --compile a.march -o /tmp/x    # cached: key(a) -> "/tmp/x"  (AAA)
      march --compile b.march -o /tmp/x    # cached: key(b) -> "/tmp/x"  (BBB)
      march --compile a.march -o /tmp/y    # -> BBB

  Reusing one `-o` across several sources is ordinary in build scripts and
  test harnesses, so this was reachable in normal use. Artifacts are now
  copied into the cache by content and served from there; deleting or
  overwriting a compiled output can no longer affect what the cache returns.
  Cache entries live in a new directory, so stale entries from the old scheme
  are ignored rather than misread.

- Refinement checking: a **named return binder** that collides with a parameter
  no longer misattributes the guards reaching a return. `fn f(v : Int, k : Int)
  : {v : Int | v > 0} do if v < 0 do k else 1 end end` was reported as a
  violation with the counterexample `k = -1` — the guard `v < 0` is about the
  *parameter*, but the path conditions were translated with the resolver in
  which `v` denotes the *return value*, so it became `k < 0`. Path conditions
  now resolve in the function body's namespace; only the return predicate reads
  the binder as the return value. The same conflation also suppressed genuine
  violations, which are now reported.

- `NativeArray.map_float` (compiled builds) no longer segfaults, and
  `NativeArray.map_int` (compiled builds) no longer silently returns wrong
  results. Both called a closure through the wrong calling convention — a
  native `int64_t`/`double` C signature instead of the tagged/boxed `ptr` ABI
  every March closure actually uses. Floats landed in the wrong CPU register
  class entirely (crash); ints happened to land in the right register but
  skipped the tag/untag step (wrong answer for every element).

- `NativeArray.sum_float` (compiled builds) now vectorizes. Strict IEEE 754
  float semantics were silently blocking clang's auto-vectorizer on this
  reduction loop — it emitted vector loads but scalar adds. Scoping float
  reassociation to just this loop (not a program-wide `-ffast-math`) restores
  SIMD summation; results match prior output to the last bit of rounding,
  roughly 3x less CPU time on large arrays.

- **`String.from_codepoint` and `String.to_codepoints` now work in compiled
  programs.** They were interpreter-only builtin wrappers — the underlying
  `string_from_codepoint`/`string_to_codepoints` have no native
  implementation — so *any* compiled program calling them failed at link time
  with `Undefined symbols: _string_from_codepoint`. Both are now pure-March
  UTF-8 codecs built on `Bytes` and the integer bitwise builtins: one
  definition for every backend, with no interpreter-vs-compiled divergence.
  Encoding rejects negative values, values above U+10FFFF, and UTF-16
  surrogates.

- **`IOList.to_string`/`byte_size`/`is_empty` no longer overflow the stack on
  deep segment trees.** All three walked the tree with non-tail recursion, so
  a deque of appends — `IOList.append(acc, x)` in a loop builds a left spine
  one level deeper per append — crashed with SIGBUS past roughly 15–20k
  depth, despite the module documenting flattening as stack-safe. Rewritten
  as tail-recursive explicit-worklist traversals that keep the frame stack on
  the heap, so depth and branching are bounded only by memory.
  `bench/iolist_template.march` and `bench/string_pipeline.march` both crashed
  on this and now run clean.

- **A `Deque` element popped in compiled code came back as a garbage
  pointer.** `deque.march` was missing from the compiler's eagerly-loaded
  stdlib list, so it loaded lazily — signatures only, no body typecheck. That
  left callers' bindings as unresolved type variables, monomorphization could
  not specialize the generic `pop_front : Deque(a) -> (Option(a), Deque(a))`,
  and the generic body's *boxed* `Some` was decoded by the concrete caller as
  a *niche* `Option(Int)` — yielding the box's heap address instead of the
  value. `bench/deque_ops.march` printed a pointer and then looped forever
  draining a deque whose elements never matched. Fixed by loading `Deque`
  eagerly; the underlying hazard — lazy loading changing representation
  decisions — is tracked separately.

- `NativeArray.map_int`/`map_float` (compiled builds) no longer allocate a
  closure or call it indirectly when the mapped function is a plain,
  non-capturing `fn x -> ...`: the compiler now calls it directly, which
  clang can then inline and, for arithmetic-heavy element functions,
  vectorize. A capturing closure is unaffected. Workloads whose map step is
  dominated by array read/write bandwidth (the common case) won't see a
  wall-clock difference — the win is in the per-element compute cost.

- `typed_array_map`/`typed_array_fold` (compiled builds) no longer segfault.
  `call_closure_1`/`call_closure_2` read a closure's function pointer at byte
  offset +8 of the closure object — the object's `tag` field (plus 4 bytes of
  padding), not the fn pointer, which actually lives at offset +16. This broke
  every DataFrame boolean-column negation/is-not-null check compiled (e.g.
  `typed_array_map(data, fn b -> !b)` in `stdlib/dataframe.march`). New
  regression test `test/native/typed_array_map_closure_abi.march`.
- Session types: steps that follow a `choose ... end` block are no longer
  dropped from every role's projection. Both roles previously lost the
  protocol's tail consistently enough that duality still passed and the
  trailing message went silently unenforced; in multi-party protocols a
  legal choice-then-message protocol could even be rejected with a spurious
  role-mismatch error. A program that closes a session channel instead of
  driving the post-choice steps is now correctly rejected.

- Session types: `loop do ... end` protocols now genuinely loop. The
  projection previously substituted the post-loop continuation into the
  recursion point, so a `loop` was silently one unrolled iteration — a
  second send/recv round was rejected with `` channel is at `End` ``. `loop`
  now projects to the standard recursive µ-type, so a channel may run the
  loop body any number of times. Since such a loop never exits, a protocol
  step written after a `loop` block is now a compile error instead of
  unreachable, silently-accepted dead code.

- Session types: `Chan.new` on a protocol with more than two roles is now a
  compile error instead of silently handing back the first two roles'
  (non-dual) endpoints as a pair. `Chan.new` is the binary-only channel
  constructor; `MPST.new` already existed for 3+-role protocols but nothing
  stopped `Chan.new` from being called on one too. The error names the
  protocol's actual role count and points at `MPST.new`.

- **Session types: an unrefined `Chan.offer` continuation is no longer a live
  soundness hole.** `match`-ing the label `Chan.offer` returns already refined
  the paired channel's type per arm, but only when such a `match` existed —
  driving the channel without one still typed it at the FIRST branch's
  continuation, an unsound guess whenever the branches continue differently.
  Interpreted, that guess could die with a dynamic type error; **compiled, it
  was silent type confusion** — a peer that chose the other branch and sent a
  `String` had that value's heap pointer read as an `Int`. A `Chan.offer`
  whose branches continue identically is unaffected and still needs no
  `match` to drive. `specs/lang/types/accept/t43_choose_offer_roundtrip.march`
  and `specs/lang/golden/g39_chan_choose_offer.march`, both of which relied on
  the old guess, are migrated to match on the label first (`g39`'s printed
  output is unchanged).

- **Session types: the `Chan.offer` fix above was also bypassable by
  unification** — an ordinary type annotation was enough. The compiler marks
  the exact channel `Chan.offer` hands back and rejects operations on it by
  identity, but unifying two channel types only compared their protocol
  states, never linked them. So `let ch : Chan(Role, Proto) = offered` — or an
  `if`/`match` join with another channel, a record field, or passing the
  channel to a function with an annotated parameter — produced a *different*,
  unmarked channel at the same state, and every later check passed. The
  annotation form typechecked clean and, compiled, printed the other branch's
  `String` payload as an `Int`. Unifying an unrefined `Chan.offer`
  continuation with any other channel type is now itself an error; only a
  `match` on the paired label can make the channel usable. Reported at the
  unification rather than propagating the mark, so the function-parameter form
  is caught at the call site, where the mistake is.

- **Lambda and nested-`fn` parameter type annotations are now enforced.** A
  parameter annotation on a `fn ... -> ...` lambda — or on a named `fn`
  declared inside a function body — was checked against nothing at all: the
  lambda's function type was built from fresh type variables that were never
  reconciled with the annotations, so the body was checked against the
  annotation while every call site checked its argument against the unrelated
  variable. `fn (x : String) -> ...` applied to `42` typechecked. For session
  types this was the last soundness hole *found* in the `Chan.offer` fixes
  above (the enforced routes are enumerated, not proved — see
  `specs/lang/session-types.md`):
  passing an unrefined continuation to `fn (c : Chan(Role, Proto)) -> ...`
  reached neither the per-operation check nor the unification check, and the
  compiled program read one branch's `String` payload as the other's `Int`.
  Both are now rejected. Top-level `fn` parameters were never affected. If
  this newly rejects code you had, the annotation and the actual argument type
  genuinely disagree — the annotation was simply not being checked before.

- **Session types: the `Chan.offer` fix above was itself bypassable by
  shadowing the offer's label variable.** Rebinding the label name
  (`let lbl = :ok`) after `let (lbl, ch) = Chan.offer(...)` left the OLD
  name→channel linkage reachable, so `match`-ing the shadowed name still
  refined (and un-marked) the original channel as if the peer had returned
  that label — reopening the identical type-confusion hole through a
  shadowed name instead of a missing `match`. Rebinding a name — via a plain
  `let`, a lambda/`fn` parameter, or a `match` pattern — now always retires
  any stale linkage for that name first.

- **Session types: `match`-ing the label `Chan.offer` returns now checks
  exhaustiveness against the protocol's actual branches, not the open `Atom`
  universe.** A `match` handling every branch the peer could choose used to
  warn `` missing case: _ `` anyway (`Atom` is open, so the checker could
  never see the label as fully covered) — and a `match` that genuinely
  omitted a branch produced the exact same warning, never an error. The one
  signal meant to catch "you forgot a protocol branch" was indistinguishable
  noise either way. Covering every branch (with or without a catch-all) is
  now silent; a missing branch with no catch-all is a compile error naming
  the branch. A `match` arm naming a label the protocol does *not* offer
  (`:okk` alongside `:ok`) used to be accepted in silence and could never be
  taken; it is now a warning naming the unknown label and the valid set —
  a warning, not an error, since a redundant arm is dead code rather than a
  soundness problem.

- Session types: driving an unrefined `Chan.offer` channel from inside a `_`
  catch-all arm no longer advises "Match on the label first", which read as
  plainly wrong to anyone who had just written a `match`. The message now
  explains the real problem: a catch-all does not identify which branch the
  peer chose, so every label needs its own arm.

- Session types: a `choose` branch that ends in a `loop` is now rejected when
  the protocol continues after the `choose`. Those trailing steps are
  projected into every branch, so in a branch that loops forever they can
  never run — the same unreachable-step defect already rejected when the
  steps are written directly after a `loop`, but reached through the
  post-`choose` tail instead.

- Session types: a protocol role that isn't also a declared type or actor no
  longer produces a "not a known actor or type" hint. Roles are their own
  namespace, so the hint was wrong by construction — it fired on the
  reference chapter's own `Echo` example, and the conformance corpus worked
  around it by declaring dummy `type` aliases for every role. Separately,
  `MPST.choose`/`MPST.offer` (multi-party branching, not yet implemented) no
  longer fall through to a misleading `` Unknown module `MPST` `` error;
  the diagnostic now names the real problem and lists the supported
  `Chan.*`/`MPST.*` operations.

- Refinement verdicts of `unknown` are no longer cached. An `unknown` is the
  absence of an answer, not an answer: the solver runs under a wall-clock
  timeout, so a loaded machine could turn a decidable check into `unknown` and
  the cache would freeze that accident into every later build. A malformed
  query also yields `unknown`, so caching one made a compiler bug's
  silently-unchecked result outlive the fix for that bug — which is how a warm
  cache masked two refinement regression tests. Caches written before this
  change self-heal, and real verdicts are still cached.

- **The `task_await` missed-wakeup deadlock is fixed** — fork-join workloads
  (`task_spawn` + `task_await`) hung roughly once every 20 runs, and the same
  race intermittently hung CI's test step. It was a memory-ordering bug, not a
  logic bug: the waiter's register-then-recheck and the completer's
  publish-then-read-waiter form a classic store-buffering (Dekker) pair, and
  release/acquire ordering does not prevent a store from being reordered after
  a later load of a different address. On Apple Silicon the compiler emits an
  RCpc acquire load (`ldapr`) that may complete before an earlier release
  store drains, so both sides could read stale values at once: the task
  completed, the completer saw no registered waiter and woke nobody, and the
  waiter — having read a stale "not done" — parked forever. Upgraded both
  sides of the pair to sequentially-consistent ordering (24 hangs/500 runs →
  1/1000), and closed the residual window — a wake arriving after the
  waiter's final recheck but before it finishes parking was dropped — with a
  wake-permit handshake in the scheduler (0 hangs/3000 runs). The
  `task_burst_await` regression test is back in the default test suite after
  being quarantined as un-runnably flaky; actor mailbox delivery never had
  either bug (its check-and-park runs under the mailbox lock).

- A single malformed verification condition no longer disables refinement
  checking for the rest of a compilation. z3 emits an `(error …)` line and then
  still answers the query, but that line was read as the verdict; the solver was
  killed, respawned, hit the same error, and z3 was then marked unavailable for
  the whole run — so every later call site was silently left unchecked with no
  diagnostic. Error lines are now skipped, and a query that produced one is
  reported as unproven rather than trusted.

- **A z3 error message spanning more than one line no longer shifts every later
  verdict by one.** The fix above skipped a single `(error …)` *line*, but a
  sort mismatch prints the offending term and then a second line naming the
  declaration it violates; the continuation stayed in the pipe and was consumed
  as the *next* query's answer. Under the definite-failure stance that is worse
  than an unchecked call — a later, unrelated, **correct** call inherits some
  other query's `unsat` and is reported as a violation. The whole error
  s-expression is now consumed, counting parens only outside its quoted
  message.

- **A record argument holding a list literal with concrete elements is now
  skipped instead of building a malformed query.** `{ history: Cons(1, Nil) }`
  puts a well-sorted `List` constructor at a `List` field, but the built-in
  `List` is generic so its element sort is opaque, and the integer `1` does not
  fit there. The field sort-check only looked at the top-level term, so the
  mismatch reached z3 — the exact multi-line error above. The check now
  recurses into a constructor's arguments.

- **A refinement path fact survived a rebinding of the name it was about**, so
  correct code could be flagged. After `if x < 0 do`, a `let x = 5` inside the
  branch left `x < 0` attached to the *new* `x`, and a call needing `{Int | _ >=
  0}` was reported as a definite violation. Facts are now retired by every
  binding construct that rebinds a name they mention — `let`, `let?`, lambda and
  local-`fn` parameters, and `match` arm binders — in both the call-site and the
  return-position checks.

- **Scalar tagging now carries `nsw`, letting LLVM fold the tag/untag round
  trip away entirely.** The `(v << 1) | 1` immediate-scalar tag was emitted
  as a plain `shl`, so LLVM could not assume the shift preserved the sign and
  a sign-truncating `sbfx` survived on every scalar round trip — and, worse,
  that residue blocked accumulator tail-recursion elimination on recursive
  functions whose result feeds the tag. With `shl nsw` (asserting exactly the
  63-bit-losslessness the tagging convention already assumes), `fib(40)`
  compiles to an accumulator loop with a single recursive call — with the
  preemption check still inside the loop — and drops from 465 ms to ~390 ms.
  Trade-off, made deliberately: an `Int` outside [-2^62, 2^62) passed through
  a generic/erased slot was *already* silently corrupted by the round trip;
  under `nsw` that same out-of-convention value is poison rather than a
  deterministic wrong value. The full differential-oracle sweep (141
  programs) is unchanged: 100 MATCH, 0 divergences.

- **Compiled code no longer pays a thread-local-storage resolver call on every
  function entry.** Each compiled function began by loading, decrementing and
  storing the `_Thread_local` scheduler reduction counter. Thread-local access
  is not a plain load on either supported platform: on Darwin/arm64 the symbol
  is a TLV descriptor and each access compiles to `adrp; ldr; blr` — an
  indirect call into the resolver — and on Linux/arm64 PIE it goes through a
  TLSDESC call. A non-inlinable call on every entry also forces a stack frame
  and register spills. Compiled code now reads a plain (non-thread-local)
  `march_preempt_request` flag instead, which the preemption handler sets once
  per quantum; the hot path is a single load and a predictable branch, and it
  is read-only, so the cache line stays shared across scheduler threads rather
  than ping-ponging on a per-call store.

  `fib(40)` 640 ms → 465 ms, `tree-transform` 852 ms → 579 ms, `binary-trees`
  177 ms → 165 ms. Preemption latency is unchanged in wall-clock terms (still
  driven by the 1 ms quantum); what is gone is the *count*-based trigger that
  also fired every 4000 calls, which on call-dense code fired within
  microseconds — far more often than the quantum required, for no benefit.
  Because the flag is process-wide rather than per-thread, a given scheduler
  thread is now preempted on average every (threads × quantum) rather than
  every quantum.

- **`MARCH_NUM_SCHEDULERS=1` had no timer preemption at all.**
  `march_sched_run`'s single-scheduler fast path returned without ever
  starting the preemption daemon, so in the configuration used for
  deterministic, race-free runs the *only* thing that ever preempted a
  CPU-bound green thread was the per-call reduction counter. A tail-recursive
  loop could otherwise monopolise the scheduler indefinitely. The daemon is
  now started (and stopped) on that path too. Found by a new starvation test
  that runs a CPU-bound task alongside a short one on a single scheduler
  thread — the only configuration in which such a test measures preemption
  rather than parallelism.

- **Perceus FBIP in-place reuse was silently disabled program-wide**, making
  every "functional but in-place" rewrite a heap free + fresh allocation
  instead. `bench/tree_transform.march` (the FBIP showcase) ran at 3842 ms
  against 513 ms in the last published benchmark table, and
  `bench/list_ops.march` at 143 ms against 68 ms.

  Cause: once `join_points` began lifting a `match`'s panic default arm into
  a `$jp_clo` closure, every real arm carried a `dec_rc $jp_clo` between its
  `let` chain and its tail allocation. `try_fbip_sink` only traversed `ELet`
  nodes, so the scrutinee's own `dec_rc` could never reach the allocation and
  no `EReuse` was ever produced. `try_fbip_sink` now also hops `ESeq` heads
  that are RC operations on a *different* variable — sound because RC ops
  neither read fields nor observe ordering, delaying a `dec` can only delay
  (never hasten) a free, and the aliasing corner is caught by `EReuse`'s
  runtime RC==1 uniqueness branch, which sends shared cells down the
  fresh-allocation path. A fail-loudly full-overwrite guard at the generic
  `EReuse` emission site rejects a reuse whose argument count doesn't match
  the resolved constructor's declared field count, which would otherwise leak
  the reused cell's stale trailing fields.

  After the fix: tree-transform 852 ms, list-ops 67 ms (the latter exactly
  matching the pre-regression figure). Note that `fib(40)` — which allocates
  nothing and is therefore unaffected by FBIP — remains ~2.2x slower than the
  same published table, an unrelated and still-open regression.

  This restores work that existed and was verified on the
  `docs/core-march-types-skeleton` line but never reached `main`; the TIR
  golden snapshot `fbip_dead_binding_reuse` had the starved `dec_rc` + `alloc`
  shape pinned in as its expected output, so the one test written to catch
  this regression was certifying it instead.

- `bench/run_benchmarks.sh` invoked `dune exec march` without `--root .`.
  Run from a git worktree (which lives under the parent checkout), dune
  resolved its root to the *parent* repository and benchmarked that
  compiler rather than the one under test — silently reporting the wrong
  binary's numbers, with no error.

### Fixed

- A record refinement whose record had a field of a non-`Int` type bound to a
  variable (e.g. `{ port: 8080, name: n }` where `name : String`) could
  silently disable refinement checking for the **rest of the file**. The
  reflection placed the variable at the wrong solver sort, the solver rejected
  the malformed query, and the error desynchronised the long-lived solver
  session, so every later check — including plain `Int` ones in unrelated
  functions — came back inconclusive and reported nothing. Such a record is now
  skipped instead of mis-reflected.

### Changed

- `dune runtest` no longer runs `test/test_properties.exe`. That one binary
  was ~86% of the suite's wall-clock (652s of 756s measured in CI) because its
  QCheck property groups push generated programs through the whole compiler
  pipeline hundreds of times each, and alcotest runs cases sequentially with
  no parallelism to offer. CI now runs it as its own parallel, sharded job.
  It is still built (so compile errors there still fail the build); run it
  locally with `dune build @test/property_tests`, or a subset with
  `./_build/default/test/test_properties.exe test '<group-regex>'`.

- `march --compile` no longer recompiles the whole C runtime from source on
  every invocation. The ~20 `runtime/*.c` files are now compiled once per
  (runtime-source, C-toolchain, compile-flags) combination, cached under
  `~/.march/cache/runtime-objs/`, and reused on subsequent builds — only the
  generated LLVM IR for your own program is compiled per invocation. Measured
  locally, this cuts the clang portion of a small program's build from ~1.5s
  to ~0.3s (a ~5x reduction on that step; ~45% off end-to-end, the remainder
  now being March's own frontend). The saving compounds anywhere many
  programs are compiled in sequence — test suites, the differential oracle,
  `forge build` over a multi-file project.

  The cache key covers the runtime sources' content, the C compiler's own
  version, and the full compile-flag string, so editing a runtime `.c`/`.h`,
  bumping clang, or switching optimization/sanitizer/debug flags each get
  their own object set rather than silently reusing a stale one. Builds that
  bake per-invocation defines into the runtime — cross-compilation,
  `--compile-so`, `--hot-reload` with `--signing-pubkey`, and
  `MARCH_HTTP_EVLOOP=1` — automatically fall back to the previous
  single-command compile. `MARCH_NO_RUNTIME_CACHE=1` forces that fallback.

### Fixed

- A record type-mismatch note stated its two sides backwards: a field present
  in the value you passed but absent from the expected type was reported as
  "present in the expected type but missing in the found type". The note now
  names the two sides in words, and the reverse case (a field the expected
  type requires but the value lacks) is reported too, where before it was
  silent.

- Unreachable match arms are now reported inside functions with a declared
  return type. `check_redundant_arms` ran only on the type-inference path, so
  any `match` in checking position — which is every `match` in a function with
  a return annotation, i.e. most of them — silently skipped the analysis.

### Documentation

- Migrated 14 language-reference chapters (Type System, Pattern Matching,
  Modules, Interfaces, Linear Types, Refinement Types, Capabilities, Safety
  by Construction, Memory Model, Actors, Parallel Collections, Supervision,
  Session Types, Clustering) from `specs/lang/` into real, styled pages on
  march-lang.org (`/docs/<topic>/`). These previously rendered as blank,
  unstyled `/<topic>.html` stub pages ("this topic has moved") that every
  site page linking to them — the homepage, the language tour, Getting
  Started, the stdlib guide, the FFI guide, and the "coming from X" guides —
  pointed at. Content was adapted for a general-programmer reader rather
  than copied verbatim: `specs/lang/` keeps the full conformance-ledger
  detail (source citations, golden-test IDs, dated findings) for compiler
  contributors, while the published pages state each caveat once, in plain
  language, without implementation citations.

- The session-types reference chapters (`specs/lang/session-types.md`,
  `specs/lang/core-march-types.md`, `specs/lang/core-march.md`) are
  reconciled with the correctness fixes above. Most notably, the claim that
  every `MPST.*` program segfaults compiled (exit 139) is corrected: a
  3-role and a 4-role protocol both compile, run, and print output
  identical to the interpreter, exit 0 — what remains genuinely
  unimplemented is multiparty `choose`/`offer`, and MPST still has no
  golden conformance witness. Also documented: `Chan.new(Proto)` returns
  its endpoint pair ordered by alphabetically-sorted role name (not
  declaration order), and `loop do ... end` projects to a genuine
  recursive session type and must be a protocol's last step.

## [0.2.0] - 2026-07-23

### Fixed

- A module could not reference a same-name-prefixed sibling module in a
  multi-file project — e.g. entry `mod MyApp` calling into a sibling
  `mod MyApp.Router` declared in its own file (the documented
  "one mod per file" multi-file convention), via `MyApp.Router.dispatch(...)`,
  `use MyApp.Router` + bare `Router.dispatch(...)`, or (previously the only
  working spelling) `alias MyApp.Router as R`. The first two failed with
  `Unknown module \`Router\`.` — the entry-module-self-qualification stripping
  pass matched by string prefix only, so `MyApp.Router.dispatch` (which
  merely starts with the entry's own name, `MyApp.`) was wrongly mangled to
  `Router.dispatch` as if `Router` were one of the entry's own members. A
  related gap in `use`/`alias` resolution (taking only the first segment of a
  dotted import path) and in `use`'s bare-name binding for dotted paths are
  also fixed. Referencing an unrelated-named sibling module always worked and
  still does.

- Fork-join workloads using `task_spawn`/`task_await`/`task_await_unwrap`
  under high task concurrency (thousands of simultaneously in-flight tasks)
  could hit a severe performance cliff — `bench/par_fib.march`
  (`par_fib(40, 20)`) went from a fraction of a second to 54+ minutes past a
  certain task-count threshold. An earlier pass bounded the worst case with
  a spin-then-sleep backoff (cutting wasted CPU) but the workload still
  didn't complete; `task_await` now parks the awaiting green thread and
  wakes it explicitly on completion (mirroring the existing actor-mailbox
  park/wake pattern), which eliminates both the wasted context-switch
  overhead and a LIFO dispatch-starvation interaction that was compounding
  it. The scheduler's separate internal wake-on-parked-proc spin also keeps
  its own generous-grace-period sleep fallback from the earlier pass, so
  neither wait can peg an OS thread at 100% CPU forever with no possibility
  of self-recovery. Compiled `--compile` programs only; the interpreter was
  unaffected.

- Compiled `Csv.read_all`/`Csv.each_row_with_header` could crash
  (nondeterministic SIGBUS/SIGSEGV) or silently return zero rows. A
  builtin-call argument coercion added to fix an unrelated tagging bug
  (`Some((top, _)) -> int_to_string(top)` printing `7` instead of `3`) was
  incorrectly tagging opaque native-pointer handles — Csv/File/Tcp handles
  are represented as plain `Int` in March's type system by convention, but
  are raw C pointers at runtime — whenever they were passed to a builtin
  whose C signature declares the parameter as `ptr`. Restricted the
  coercion to the direction it was actually meant for.

- Refinement checking's return-refinement propagation could false-positive
  through a `let? p = e` binding: the continuation after `let? c = ok5()`
  still saw an outer refined local named `c` instead of the newly-bound one,
  so a subsequent correct use of `c` could be wrongly flagged. `let?` now
  shadows its bound names before checking its continuation, matching every
  other binding construct (`let`, lambda params, `match` binders). Also
  reworded refinement counterexamples from `f() returns v` to
  `f() can return v` — the solver's model is a witness satisfying `f`'s
  postcondition, not necessarily `f`'s actual return value.

- The browser cookbook/playground REPL's bundled stdlib was missing
  `Vault` — the docs/cookbook/vault.md examples errored with `no member
  'new' in module 'Vault'` because `vault.march` wasn't in either
  `js/march_browser.ml`'s `browser_stdlib_files` load-list or
  `scripts/gen-browser-stdlib.py`'s `FILES` list used to generate
  `docs/assets/march_stdlib.js`. Added it to both and regenerated the
  bundled assets.

### Documentation

- The "sandboxed plugin runner" example in docs/cookbook/capabilities.md
  called a `sandbox_eval` function that never existed anywhere in the
  compiler or stdlib — it was illustrative pseudocode, so running the
  example in the cookbook REPL errored with `unbound variable:
  sandbox_eval`. Replaced it with a trivial inline stub so the snippet
  actually compiles and runs; the example's real point (the `PluginCap`
  gate) is unaffected.

- A qualified call to a real module's genuinely nonexistent member (e.g.
  `String.length(...)` — `String` has no `length`; the real API is
  `byte_size`/`codepoint_count`/`grapheme_count`) silently fell through to an
  unrelated same-named binding elsewhere (e.g. the prelude's generic
  `List.length`) instead of reporting "Module `String` does not export
  `length`". The EVar dot-suffix fallback — meant only to resolve
  multi-component local/app-module paths like `Conduit.Storage.workflow_load`
  down to `Storage.workflow_load` — didn't distinguish that case from a
  qualifier that is already a confirmed, loaded stdlib module. Now, once the
  qualifier's first component resolves to a real registered module, a missing
  member always reports the clean "does not export" diagnostic instead of
  falling through to the bare-name search.
- A user-defined interface impl with a compositional `when` constraint (e.g.
  `impl MyEq(Wrap(a)) when MyEq(a) do fn eq(w1, w2) do ... eq(x, y) ... end
  end` — the same shape as the stdlib's own `Eq(List(a)) when Eq(a)`) whose
  body recursively called its own method name on the constrained inner value
  dispatched incorrectly. Interpreted, the recursive call re-entered the SAME
  impl instead of the inner type's impl, producing a wrong answer (or a
  non-exhaustive-match panic). Compiled, it crashed with an internal compiler
  error ("has no runtime-tag rows") whenever the constrained type happened to
  share a method name with an unrelated interface. Both are fixed: the
  recursive call now dispatches by the runtime type of its own arguments on
  both backends, regardless of impl declaration order or nesting depth.
- `root_cap()` — calling the root capability like a function instead of
  referencing it bare (`root_cap`) — typechecked cleanly with `--check` and
  then crashed at runtime: `applied non-function value` interpreted, or an
  `Undefined symbols ... _root_cap` link error compiled. `root_cap` is a
  plain value, not a function; calling it with `()` is now rejected at
  check/compile time with a diagnostic explaining why.
- `File.read` and related I/O builtins (`file_write/append/delete/copy/rename/stat/open`,
  `Dir.list/mkdir/mkdir_p/rmdir/rm_rf`, `Csv.open`, and the TCP/TLS/HTTP/process
  builtins) had their `Result` error type registered as fully polymorphic, so a
  function declaring an incompatible error type (e.g. `Result(_, String)` for
  `File.read`, whose real error is `FileError`) typechecked with zero
  diagnostics and then panicked at runtime the moment the error value was used
  as the wrong type. These builtins' error types are now pinned to their real
  concrete type, so a mismatched declaration is now a compile-time error
  instead of a runtime panic.
- `Actor.call`'s reply value was silently corrupted when compiled: an `Int`
  (or `Bool`/`Unit`) reply came back as its raw tagged-immediate bit pattern
  instead of the real value (e.g. a handler replying with `5` was observed as
  `11` by the caller). `int_to_string`/`bool_to_string`/`float_to_string` are
  the only scalar-consuming builtins that had no dedicated argument coercion,
  so a value arriving through `Actor.call`'s necessarily type-erased reply
  channel was passed straight through with a declared-signature mismatch
  instead of being untagged first.
- The same underlying gap — builtin call arguments never coerced to the
  builtin's own declared native parameter type, only to a user-defined
  function's — also reached compiled output through an unrelated path: a
  scalar bound by a tuple or constructor pattern (e.g. `Some((top, rest)) ->
  int_to_string(top)`, or even a plain top-level `(top, rest) ->
  int_to_string(top)`) passed to any compiler builtin with a native scalar
  parameter (`math_sqrt`, `float_abs`, and ~50 more beyond the three fixed
  above) printed the raw internal tagged-integer encoding instead of the real
  value (`7` instead of `3` for the example above). Call-argument coercion
  now also derives each builtin's declared parameter types directly from its
  own preamble `declare` signature, so every builtin gets the same coercion
  user-defined functions already had — not just the three fixed individually
  above.
- `self()` inside an actor handler was typechecked as a plain `Int` instead
  of that actor's own `Pid`, so passing it anywhere a `Pid` was expected
  (`is_alive(self())`, a typed `Pid` message field) failed to typecheck with
  "expected `Pid` but got `Int`" even though it is a valid `Pid` at runtime.
  `self()` now resolves to the same `Pid[state]` type `spawn` produces for
  that actor.
- A general user interface implemented by two same-short-name types declared
  in different modules (e.g. `NA.Thing` and `NB.Thing` both `impl
  Speak(Thing)`) could have an ambiguous call site resolved, at compile time,
  to whichever impl happened to be declared first — a latent miscompile risk
  rather than an always-reproducing bug, since an unrelated dispatch guard
  happened to mask it for most call shapes. Interface dispatch on same-named
  colliding types is now always deferred to the collision-aware runtime
  dispatch added for this feature, with no first-match shortcut.
- An all-caps acronym stdlib module name (e.g. `RRB`, declared in
  `rrb_vec.march`) failed to resolve in a type annotation with "Unknown module
  `RRB`", even though its functions worked fine as values. The lazy
  qualified-name resolver guessed a module's filename by inserting `_` before
  every uppercase letter (`ConsistentHash` -> `consistent_hash.march`), which
  mangles an acronym into a filename that doesn't exist (`r_r_b.march`).
  Falls back to a lazily-built index of the stdlib directory keyed by each
  file's real declared module name when the naming-convention guess misses.
  Fixing this exposed a second, related bug: a qualified reference to an
  opaque type (`RRB.Vec(Int)`) failed to unify with real values of that type
  (`expected 'RRB.Vec(Int)' but got 'Vec(r3)'`) because the qualified name
  wasn't canonicalized to its bare form when the type's module was being
  loaded for the first time. Both are fixed together.
- `let x : T = e` type annotations silently accepted ANY resolution failure
  in `T` and fell back to inferring the type from `e` alone with zero
  diagnostics — e.g. `let e : Vec(Int) = "not a vec"` typechecked cleanly.
  This was meant to tolerate a phantom/typestate tag used in type position
  (`let h : Handle(Open) = ...`, where `Open` is a data constructor, not a
  type name) but was too broad, silently discarding genuinely broken
  annotations (an unresolvable module, a typo'd or renamed type) too.
  Narrowed to only tolerate the phantom-tag case (an unresolved name that IS
  a known data constructor); any other resolution failure now surfaces as a
  real diagnostic.
- An inline lambda passed directly as a call argument (e.g. `Dom.on_frame(fn _
  -> ...)`) failed to parse if its body had a plain statement (not a `let`
  binding) immediately followed by another expression — e.g. a function call
  followed by an `if`/`else` — even though the identical body worked fine as a
  named function or a lambda wrapped in `do...end`. Symptom: `I got stuck here`
  at the following token. Inline lambda call arguments now accept bare
  statements before the final expression, matching `do...end` block bodies.
- A linear or `always_linear`-typed value *acquired* through `let? p = e` or
  `with Ok(p) <- e do ... end` — rather than bound by a plain `let` or a
  function parameter — was never tracked as linear at all, so consuming it
  twice (e.g. passing the same handle to two separate calls, each behind its
  own `let?`) went completely undetected. The identical double-use was
  already correctly rejected when the value came from an ordinary `let` or a
  function parameter. Affects any code acquiring a linear resource through a
  Result-returning `let?`/`with` chain.
- A self-tail-recursive function forwarding a freshly-built value as its own
  next argument (e.g. an accumulator built via `String.join`/`String.split`)
  could silently corrupt that value in compiled programs — freed one
  instruction before it was reused for the next iteration. Symptom: wrong
  answers with no crash or error, e.g. `stdlib/toml.march`'s integer parsing
  (`Toml.get_int` on `"port = 9000"`) returned `9` instead of `9000` compiled
  while the interpreter was correct. Affects any compiled program using this
  accumulator-recursion shape over a value not extracted from an
  already-borrowed container (a list/tree traversal passing along an existing
  field, e.g. `Cons(_, t) -> go(t, ...)`, was unaffected).
- Interfaces implemented separately for two same-short-name types declared in
  different modules (e.g. two modules each with their own `impl Speak(Thing)`)
  now dispatch to the correct implementation at runtime, in both the
  interpreter and the native backend. Previously the wrong implementation's
  body could run silently: the interpreter took whichever impl was registered
  last regardless of the value's actual type, and native code could miscompile
  via colliding constructor tags or value representation. Built-in interfaces
  (`Eq`, `Ord`, `Show`, `Hash`) were already correct and are unaffected. (#57)
- `string_to_float` and `String.to_float` crashed (segfault) in compiled
  programs whenever the parsed `Float` was actually used — e.g.
  `match string_to_float(s) do Some(f) -> ... end`. Fine in the interpreter;
  native code stored the parsed value in a representation the rest of the
  compiler didn't expect. Affects any compiled program parsing floats from
  strings, including `stdlib/toml.march`'s float handling.
- `Html.raw(...)` content silently disappeared when interpolated into a `~H`
  sigil in compiled programs — e.g. `~H"<button>${Html.raw("hi")}</button>"`
  rendered `<button></button>`. Fine in the interpreter. Affects the
  documented layout/partial-nesting pattern
  (`~H"<body>${Html.raw(IOList.to_string(body))}</body>"`) as well.
- `Option.or_else` and `Option.unwrap_or_else` crashed at runtime
  (`arity mismatch: expected 0 args, got 1`) when called with a genuine
  zero-argument callback — `fn -> ...`, the natural spelling for their
  declared `() -> a` parameter. Both functions invoked the callback as
  `f(())` (passing an explicit unit value) instead of `f()`, which only
  matched a 1-arg-discard closure (`fn _ -> ...`). Fixed to call `f()`;
  affects both the interpreter and compiled programs.
- `pfn` (private function) visibility could be silently bypassed when a
  same-file nested module's private function shared its bare name with an
  unrelated global (e.g. a function named `hash`, colliding with the `Hash`
  interface's built-in method). The call typechecked without error, ran
  correctly in the interpreter, and produced a garbage value in compiled
  programs — a privacy violation that also corrupted the result, not just a
  missing diagnostic. Now correctly rejected at `--check` and `--compile`
  with the same "is private to module" error other privacy violations
  already produced.
- `RRB.push`/`Array.push` crashed compiled on the second `Float` element
  pushed (`RRB.push(RRB.push(RRB.empty(), 1.5), 2.5)`). A discarded
  (wildcard-matched) field of a list cell never got the special-casing a
  *named* field already had, so the compiler treated it as reference-counted
  even when the concrete element type (`Float`) doesn't need that — freeing
  memory that was never actually heap-allocated. (Reading a pushed `Float`
  back out — `Array.get`/`RRB.get` — had a separate, sibling bug; see below.)
- `task_spawn`/`Task.async` with a `Float`-returning callback, followed by
  `task_await_unwrap`/`Task.await_unwrap`/`Task.await`, failed to compile
  with an internal LLVM type error. Affects `Parallel.preduce`/`psum_float`,
  which spawn one task per worker chunk.
- A tail-recursive function combining a `Float` accumulator with a
  heap-value parameter (e.g. an `Array`/`List`) — the shape `RRB.fold`'s
  internal loop uses — returned a wrong answer or crashed
  (`RC underflow (rc was 0)`) in compiled programs, blocking
  `Parallel.preduce`/`psum_float`'s worked example
  (`docs/cookbook/parallel-data.md`) end-to-end even after the task-boundary
  fix above. Two independent causes: a constructor field discarded via a
  wildcard pattern (`Cons(_, t)`) kept an internal type placeholder that
  made the compiler treat an unboxed `Float` as a heap pointer needing
  reference counting, corrupting memory; and a value read out of a generic
  container field was passed to some function calls without converting it
  to that function's expected native representation, so the callee silently
  read `0.0` instead of the real value. Both fixed. Affects any compiled
  program building or reading a `List`/`Array` of `Float` through a generic
  helper (`Array.from_list`, `Array.get`, and therefore `RRB`'s `Float`
  operations) or wildcard-discarding an element of a `Float` container.
- `Dom.clone`, `Dom.first_child`, and `Dom.last_child` were declared as
  extern runtime builtins but never got a public stdlib wrapper, like every
  other DOM function — so they were unreachable from March code
  ("Module `Dom` does not export ...") despite being documented.
- `fn main(cap : Cap(IO)) : ()` — the documented pattern for receiving the
  initial IO capability — never actually worked: in the interpreter it
  silently no-oped (the program appeared to exit successfully having done
  nothing), and compiled programs crashed (SIGBUS) on startup. Both backends
  now run it correctly; any other `main` arity or parameter type is now
  rejected at compile time with a clear error instead of misbehaving.
- WebSocket connections in the interpreter (`forge run`, plain `march
  file.march`, and any tool built on it, including `forge scroll.serve`)
  disconnected almost immediately whenever the client went quiet — an open
  connection would flip to closed within milliseconds of the server having
  nothing to read, sometimes before the client's very first message was even
  processed. A raw handshake with no further traffic got an instant
  server-initiated close. The server's WebSocket handler was reading from a
  socket still configured for the (unrelated) HTTP accept loop's internal
  bookkeeping, which made an ordinary "no data yet" condition look
  indistinguishable from the client disconnecting. Compiled (`--compile`)
  WebSocket servers had a milder version of the same bug: an idle connection
  would be dropped after 10 seconds instead of staying open. Both are fixed;
  idle WebSocket connections now stay open as expected in both backends.
- `Vault.update` crashed (segfault) in compiled programs, for both an inline
  lambda and a named function callback — e.g.
  `Vault.update(store, "hits", fn n -> n + 1)`. Fine in the interpreter.
  Affects the documented atomic-update pattern and the rate-limiter cookbook
  example.
- Corrected stale claims and two tutorial code blocks in the top-level
  `README.md` that no longer matched the compiler: linear/affine types and
  `kill`/`is_alive` are fully supported (were marked "in progress" /
  "interpreter only"); the higher-order-function and actor examples now
  typecheck and run as written; the project-layout map now lists `stdlib/`,
  `forge/`, `lsp/`, and `test/`, previously omitted entirely.
- Corrected the `install.sh` `MARCH_VERSION` pin-example comment.
- Audited every March code example across the docs site (guides, the
  language tour, the cookbook, and the stdlib reference) against the current
  compiler and fixed everything that no longer typechecked, ran, or matched
  its claimed output — including a large number of stale API references in
  `docs/stdlib.md` (wrong module names, argument order, arity, or return
  types across `String`, `Math`, `JSON`, `HTTP`, `Vault`, `URI`, `Dom`, and
  more), the REPL transcript in `docs/getting-started.md` (real prompt is
  numbered, `= value` output by default), and dozens of smaller fixes across
  `docs/cookbook/*`. Several real compiler/stdlib bugs surfaced along the way
  (silent wrong answers and crashes, mostly compiled-only) that are outside a
  docs fix's scope and were filed separately rather than papered over in the
  docs.
- `docs/cookbook/linear-types.md`'s Typestate section and its "safe socket
  lifecycle" example — left unfixed by the docs audit above pending a design
  decision — didn't compile as written and were internally inconsistent
  (`via` transition functions shown returning `Result`/tuples, an acquisition
  function listed as a transition despite not taking a handle, a socket type
  missing its state parameter). Rewritten so each resource's lifecycle splits
  into an ordinary Result-returning acquisition function outside
  `transitions` plus pure `Handle -> Handle` transitions declared inside it,
  matching the working pattern in `specs/lang/capabilities.md`. Every code
  block was verified against the compiler, including that a wrong-order
  transition call is correctly rejected.
- Audited every March code example across `specs/lang/` (the authoritative
  language reference, ~341 code blocks across 21 files) against the current
  compiler, the same way as the docs/ sweep above. Several sections described
  an interface-dispatch architecture superseded by the impl-coherence and FQN
  dispatch-identity work that landed 2026-07-17 through 2026-07-21 (rewritten
  with live-verified current behavior); the Operator Reference table in
  `type-system.md` had `+ - * /` and the dotted `+. -. *. /.` operators
  backwards (the plain operators are the polymorphic Int/Float ones, not the
  dotted ones); several "known limitation" notes across `pattern-matching.md`
  and `session-types.md` described parser/linearity gaps already fixed. Around
  70 real example/prose bugs fixed in total. `specs/lang/grammar.md`'s
  `parser.mly`/`token_filter.ml` line citations have drifted (~15 of ~294
  fixed; the rest need a dedicated re-grep pass). Several real compiler bugs
  surfaced along the way and were filed separately, most notably a
  currently-live regression where compiled `Actor.call`/`Actor.reply` returns
  the raw tagged value instead of untagging it — it breaks an existing pinned
  golden test wired into `dune runtest`, just not caught because the fast
  test runner bypasses that lane.

## [0.1.1] - 2026-07-21

First tagged release.

### Added

- **Type system**: Hindley-Milner inference with bidirectional checking at
  function boundaries; algebraic data types and pattern matching; records
  with functional update (`{ r with field: value }`); polymorphic functions
  monomorphized at compile time; linear and affine types for ownership, safe
  mutation, and actor message-passing isolation; interfaces (`interface`/
  `impl`) with default methods and conditional impls (`when` constraints);
  type-level naturals for dimension-checked `Vector`/`Matrix`/`NDArray`;
  refinement types (`{T | predicate}`) with a Z3-backed verification bridge
  (in progress).
- **Memory management**: Perceus reference counting (deterministic, no GC
  pauses) with FBIP (Functional But In-Place) — pattern-matched values with
  a unique reference count are rewritten in place instead of freed and
  reallocated; escape analysis promotes allocations to the stack where
  possible; defunctionalization compiles closures to structs with no
  indirect-call overhead.
- **Concurrency**: actor model with share-nothing message passing, `spawn`,
  `send`, capability-secured references, location-transparent `Pid`;
  supervision trees and a distributed/clustering layer with node discovery;
  structured concurrency via `Task` (`async`/`await`/`race`/`any`/
  `all_settled`/`scope`, cancellation tokens); `Future` and `Stream`.
- **Backends**: native compilation via LLVM/clang, including cross-compilation
  to Linux (amd64/arm64) from any host via `zig cc`; `--target wasm64-wasi`
  for WebAssembly and a JS backend; a tree-walking interpreter and a
  JIT-backed REPL.
- **Tooling**: `forge` package manager and build tool (`new`, `build`, `run`,
  `test`, `deps`, `publish`, `watch`, `bench`, ...) with content-addressed
  dependency versioning; an LSP server (diagnostics, hover, goto-definition,
  completions, code actions); a 111-module standard library (collections,
  `BigInt`/`Decimal`/`Ratio`, HTTP client/server, JSON/MessagePack/TOML,
  crypto, DataFrame, distributed-OTP actors, and more); FFI for C interop,
  hot code reload, and a `--check-json` machine-readable diagnostics mode.

[Unreleased]: https://github.com/march-language/march/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/march-language/march/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/march-language/march/releases/tag/v0.1.1
