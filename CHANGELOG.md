# Changelog

All notable changes to March are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/); versions follow
[Semantic Versioning](https://semver.org/).

This file starts at the point March adopted a changelog (2026-07-21).
Implementer-level detail on every change (including everything that shipped
before this file existed) lives in `specs/progress/` and `specs/todos/`;
git log is authoritative for exact commits.

## [Unreleased]

### Added

- **Mock an IO effect in a test.** `with_cap(mock, fn _ -> code_under_test())`
  swaps a capability's implementation for a lexical region, and the code under
  test needs no capability parameter and names no capability — in a `--test`
  build the compiler threads one in and routes the operation through the
  capability's dictionary. An IO capability's dictionary shape is derived from
  the compiler's own tables (`march --emit-io-ops`), so there is nothing to
  hand-write: start from `cap_ops_empty(c)` and override the one operation you
  care about. Release builds are untouched. Console, clock, randomness,
  filesystem and network are fully mockable; `IO.Mut` is not (every `vault_*`
  is polymorphic, and a dictionary field would need rank-2 types), and
  operations inside actor handlers are not reached.

- `forge run FILE` runs a single `.march` file, interpreted or (with
  `--compiled`) through the LLVM pipeline. A file inside a project still
  resolves that project's modules and FFI shims. Arguments after `--` reach the
  program as `System.argv()`; the compiler gained `march --args` to make that
  work for interpreted runs too.

### Fixed

- The formatter no longer deletes compiler attributes. `format.ml` never read
  `fn_attrs`, so every `@[...]` was silently dropped — and that is not
  cosmetic: `@[no_warn_recursion]` suppresses a hard error, so format-on-save
  turned a compiling file into one that no longer builds.

- A non-tail recursive call is no longer reported twice. The typechecker's
  tail-call checker already reports every one of them, and the LSP emitted its
  own `perf/non-tail-call` diagnostic at the same span, so the editor showed
  two near-identical messages in one hover. The compiler's is kept — it is the
  authority on error-vs-warning and it honours `@[no_warn_recursion]`.

- Both non-tail-recursion hints now mention `@[no_warn_recursion]` as the
  option when the depth is bounded and the stack use is acceptable.

- `forge build` and `forge test` no longer share a compilation-cache entry.
  `--test` emits a different program (a test-runner entry point) but was absent
  from the cache key, so whichever ran first won: `forge build` could hand you
  the test runner, or `forge test` the plain binary.
- Completions now offer what you defined in the file you are editing before
  anything from the standard library. Ranking was by category alone — locals,
  keywords, values, types, constructors — so every stdlib function outranked
  your own types and constructors, and typing `B` in a module declaring
  `BTree`/`Branch` offered all of `Base64` and `BigInt` first. Ranking is now
  by origin first, then category.

- Typing in the editor no longer silently rewrites the same identifier
  elsewhere in the file. The LSP answered `textDocument/linkedEditingRange`
  with a symbol's definition *and every use*, but that request is not a
  query: the editor applies each keystroke to all returned ranges at once,
  with no prompt. Putting the cursor on a variable therefore turned ordinary
  typing into an un-asked-for rename, and ranges that were even slightly out
  of date landed mid-token and ate neighbouring characters (`Some(a)`
  becoming `Somea)`). Only genuine open/close pairs — `~H` sigil tags — are
  linked now; renaming a symbol remains `textDocument/rename`, which is
  explicit and already supported.

- The "cannot access field" diagnostic (accessing `.field` on an
  `Option`/`Result` value directly, before unwrapping it) now says how to fix
  it instead of only naming the type. It names the variable the reader
  actually wrote (`` `l` may be `None` ``) rather than "this expression", and
  the suggested `match l do Some(x) -> x.value  None -> ... end` /
  `Option.map(l, fn x -> x.value)` is copy-pasteable as-is rather than an
  `<expr>` template to re-instantiate by hand. It also explains *why* — the
  value may be absent — rather than restating that the type is not a record.

- Diagnostics no longer show an inference-internal fresh-type-variable name
  for an unresolved `Option`/`Result` payload. `Option(l2)` — meaningless to
  the reader, and different from run to run — now prints as `Option(_)`.

- Editor diagnostics no longer hide their notes. The LSP put a diagnostic's
  notes after a newline, and editors that render only the first line of the
  message in the hover popover — where diagnostics are actually read — showed
  the note nowhere except the separate, rarely-open project-diagnostics
  panel, so guidance like the unwrap hint above was invisible in practice.
  Notes are now flattened onto one line for LSP clients; the CLI keeps its
  indented multi-line layout.

- The LSP could publish the exact same diagnostics twice for one edit,
  showing as the same message stacked twice in the editor (e.g. hovering a
  line with a type error). The TIR-pass phase of `did_change`/`did_open`
  skips re-running when the source already has errors — correctly, since
  the TIR pipeline can't run on broken input — but returns the SAME
  `Analysis.t` it was given rather than a new one, and the calling code
  published its diagnostics again regardless, republishing the identical
  list already sent moments earlier. Now skipped whenever the TIR pass was
  a no-op.

- Typechecking a self-referential record type used without an annotation
  (e.g. a multi-head function whose only parameter is a record pattern
  destructuring `type Tree = { left : Option(Tree), ... }`) no longer hangs
  the compiler at 100% CPU. Expanding the record's fields for type inference
  recursed into itself with no base case — `Tree`'s `left` field mentions
  `Option(Tree)`, which requires expanding `Tree` again, forever. A guard now
  stops re-expanding a record already being expanded on the current path.

- The resulting "expected `Tree` but got `a`" style message — for the same
  self-referential-type case, when it doesn't hang — pointed at the wrong
  line and gave no indication of what was actually wrong (an internal,
  unresolved type-variable name like `a` or `y55` leaking into the text).
  This is an occurs-check failure (the type would have to contain itself),
  not an ordinary mismatch; it's now reported as such, with a hint to add an
  explicit type annotation naming the recursive type.

- The LSP's completion-resolve request (`completionItem/resolve`, which
  computes the auto-import edit for an accepted completion) could insert
  that edit at the wrong place in the buffer if it fired against a document
  version that had since changed underneath it — the import's insertion
  point is the file's first declaration line, not the cursor, so a stale
  computation landed text on an unrelated line while the user kept typing
  elsewhere. It now checks the document version and refuses to answer once
  the buffer has moved on, instead of answering against stale state.

- The LSP's diagnostic messages could show an internal, ever-growing
  fresh-type-variable name (`y55`, `b53`, …) for an unresolved type,
  instead of a short, stable one (`a`, `b`, …). The display-name counter
  backing these was never reset for the server's lifetime, so it climbed
  for as long as the process stayed open — a one-shot compiler run never
  hit this since it exits after a single pass. It's now reset once per
  analysis, so names stay small and predictable.

- `--fmt` (and the LSP's formatting request) no longer corrupts record
  patterns whose binder differs from the field name, e.g.
  `{ left: l, right: r }`. It reprinted them using record-construction
  syntax (`{ left = l, right = r }`), which the parser rejects — every
  reformat of such a pattern broke the file. Record-literal shorthand fields
  (`{ x, y }`, where the binder matches the field name) were unaffected.
- The non-tail-recursion warning no longer promises a loop that does not
  happen. It used to end "when the recursive call is the direct argument of a
  constructor, the compiler turns it into a loop" — but tail-recursion-modulo-cons
  is off by default, so code written in exactly that shape still overflowed the
  stack on deep input. The warning now says deep input can overflow, and
  describes TRMC as the opt-in it is (`--trmc`).

- ARM Linux (`linux-aarch64`) has a working release artifact for the first
  time. Every v0.2.0 and v0.3.0 ARM archive shipped with an empty `bin/` and no
  compiler at all. Three defects were stacked behind one another: git refusing
  the bind-mounted checkout inside the Alpine build container
  (`safe.directory`), the LLVM 19/20 guard bug noted below, and libblake3 built
  without `blake3_neon.c` on aarch64, which links but leaves
  `blake3_hash_many_neon` undefined in every executable that uses it.

### Changed

- The `linux-aarch64` release leg builds on a native arm64 runner
  (`ubuntu-24.04-arm`) instead of QEMU emulation on an x86_64 host. It still
  builds inside Alpine, which is what makes the artifact musl. Building the
  OCaml 5.3.0 switch alone took 52 minutes under emulation; the entire leg now
  takes under 5 minutes.

### Added

- Capabilities can now carry a **runtime dictionary** — a record of the
  operations they authorize — so a capability's implementation can be swapped at
  a binding site. Declare one with `proof cap Live with Ops`, attach with
  `cap_impl(cap, dict)`, and read it back with `cap_dict(cap)`, which yields an
  `Option` whose `None` is "no dictionary, use the ambient implementation" —
  what every capability written so far does. `cap_narrow` carries a dictionary
  across attenuation. Supplying a dictionary is gated exactly like `mint_cap`
  (a public function of the declaring module), because deciding what a
  capability *does* is at least as much authority as minting one.
  Works on both backends, with compiled/interpreted parity pinned by a native
  golden; the compiled representation costs nothing, since `Option`'s niche
  encoding makes `cap_dict` the identity function. Mocking an *IO* capability is
  not yet reachable — IO builtins do not take their capability as an argument,
  so a dictionary attached to one would never be consulted.

- Refinement failures now come with concrete, interpreter-validated
  counterexamples rendered in source terms. A return contract violated for
  some input reports the executed failing call — `but clamp(0) returns -1.` —
  with the witness shrunk to a canonical small value; call-site precondition
  errors show validated source-syntax examples (`(e.g. ys = [])` instead of
  `len(ys) = 0`); `cap no_panic` division errors name the concrete admissible
  zero divisor (`(e.g. d = 0)`); and contracts outside the solver's fragment
  (`x * y`) are probed with a small input battery, so `fn scale(x, y): {Int |
  _ > 100}` reports `but scale(1, 1) returns 1.` instead of staying silent.
  Every reported witness was actually executed and observed to fail, and must
  satisfy the parameters' own refinements — spurious solver models are
  rejected, never shown.

### Fixed

- The REPL JIT now compiles against LLVM 19 and 20. `jit_orc_stubs.c` guarded
  its ThreadSafeContext API choice on `LLVM_MAJOR_VERSION >= 19`, but the C API
  actually swapped `LLVMOrcThreadSafeContextGetContext` for
  `LLVMOrcCreateNewThreadSafeContextFromLLVMContext` in LLVM **21** — so a build
  against 19 or 20 took the newer branch and died with "implicit declaration of
  `LLVMOrcCreateNewThreadSafeContextFromLLVMContext`". Building against LLVM 18
  or 21+ was unaffected, which is why it went unnoticed.

- `forge interactive` (and `march repl` / a bare `march` REPL) now build and load
  the `forge.toml` `[ffi]` shim, so a project whose dependencies declare native
  FFI sources no longer fails at the first extern call with "symbol not found for
  interpreter FFI". This is the REPL sibling of the `forge run` fix.

### Changed

- A function whose declared return refinement is violated for **some**
  admissible input is now a compile **error** when the violation is confirmed
  by execution (previously: silent outside `cap verified`, "cannot verify"
  inside it). Code like `fn f(n : Int) : {Int | _ >= 0} do n end` no longer
  compiles. `@[trusted]` continues to rescue unproven-but-unrefuted
  contracts; it does not suppress a witness-confirmed violation.

- `lib/typecheck/typecheck.ml` is 1,824 lines smaller (8,272 -> 6,448):
  unification and surface-type conversion, session-type projection, declaration
  dependency ordering, and the module-level `cap` checkers (`no_panic`, `pure`,
  `no_extern`, `deterministic`) now live in four new modules beside it. No
  behavior change -- the typecheck, IR and refinement oracles match to the byte
  across 601 fixtures, 241 programs and 298 fixtures respectively, and
  `typecheck.mli`, the public contract, is unchanged.

- Removed three uncalled `lib/tir` values (`emit_main_wrapper`, `target_arch`,
  `reserved_ctor_tag_limit`) left over from an earlier `.mli`-only pass that
  could not edit `.ml` files. No behavior change -- the IR oracle is
  an exact byte match across 241 programs.

- `bin/main.ml` is 1,231 lines smaller (5,429 -> 4,198): host/stdlib/runtime
  discovery and link flags, the command-line flag cells, the `--check-migration`
  tool and the `--emit-core-ast` writer now live in their own `bin/` modules. No
  behavior change -- the IR and typecheck oracles match to the byte across 240
  programs and 600 fixtures.

- Codegen builtin dispatch names a closed variant (`Builtin_name.t`) rather than
  comparing raw strings, so a typo in an emitter guard is a compile error, and a
  builtin added to the variant without an emission arm is caught by a
  non-exhaustive-match error instead of silently falling through to the generic
  application path and emitting plausible-but-wrong code.

### Added

- `march --jit file.march` runs a whole program through the in-process ORC JIT: near-compiled speed without the clang/link step (experimental; actors fall back to the interpreter); programs that read command-line arguments see an empty argv under --jit.

### Fixed

- REPL (JIT, the default): a stdlib constructor evaluated as the FIRST variant
  of its type, so `match Logger.Warn do Logger.Debug -> 0 | Logger.Info -> 1 |
  Logger.Warn -> 2 | ... end` answered `0`, and `Http.Post` matched the
  `Http.Get` arm. A wrong answer, not just the `= #<tag:0>` rendering it was
  reported as. The prelude's constructor numbering is now cached alongside the
  compiled prelude and loaded on the warm-cache startup path (and kept on the
  cold one), so REPL expressions are compiled with the same tags the prelude
  was. `MARCH_REPL_INTERP=1` was always correct.

- REPL (JIT): stdlib ADT values printed as `#<tag:N>` instead of their
  constructor name; `Http.Post` now prints `Post`. A type declared inside a
  module is registered under its qualified name but referred to by its bare
  one; the printer now resolves the two when the bare name is unambiguous.

- The stdlib AST and typecheck-env caches silently disabled themselves on any
  machine (or under any `HOME` override) where `~/.cache` did not already exist:
  `Unix.mkdir` is not recursive and only `EEXIST` was caught, so `ENOENT` on the
  missing parent escaped and every invocation re-parsed and re-typechecked the
  stdlib while printing a `[warn] could not save the stdlib typecheck cache`
  line ahead of its own output. All four cache-directory sites now share one
  recursive `mkdir_p`.

- Compiled code: a top-level function with a name that collides with a compiler
  builtin the code generator dispatches specially (`int_mod`, `int_not`,
  `int_and`, `int_abs`, `record_get`, `vault_*`, `chan_*`, …) was never called:
  every call site compiled into the builtin instead, while the interpreter ran
  the user's function. Shadowing such a name is a supported feature, and it now
  behaves the same compiled as interpreted.
- macOS: the REPL / `--jit` stdlib prelude cache could never be reused across
  sessions, so every start silently paid a full stdlib precompile (~9.5s) instead
  of a ~0.01s cache hit. Cached `.so`s are built at a pid-suffixed `.tmp` path and
  renamed into place, and the macOS linker marked that now-dead path as the
  library's install name, so the prelude recorded an unloadable dependency on the
  runtime `.so`. They are now linked with `-install_name` pointing at the path the
  file actually lands at.
- `--jit`: a whole-program run now prunes functions unreachable from `main`
  before emitting code, as the ahead-of-time pipeline already did. Without it,
  only calling one function of a stdlib module dragged in every other
  function of that module, and a program using `JsonStream` failed to start
  with "Symbols not found: [ _from_json ]".
- `--jit` and the REPL JIT: mutually tail-recursive functions are now compiled
  into a loop, as they already were when compiled ahead of time. Previously a
  JIT fragment emitted each function separately, so a mutual tail-call cycle
  became real native recursion and burned one stack frame per iteration;
  enough iterations exhausted the green thread's stack and killed the process
  with a bare exit 138 and no output. Reached by any code shaped like
  `JsonStream`'s byte-at-a-time tokenizer.
- `--jit` and the REPL JIT: when the cached stdlib prelude could not be loaded,
  the compiler printed "stdlib cache load failed …, recompiling" and then did
  not recompile, silently continuing with no prelude. That produced untyped
  stdlib signatures and miscompiled code (a crash, not just a slowdown). The
  fallback now really does recompile.
- `--jit` and the REPL JIT: the stdlib prelude cache is now keyed on the
  compiler as well as on the stdlib source, so upgrading the compiler no longer
  reuses a prelude built by the previous one.
- `march --jit --debug` (and `--jit --debug-tui`) no longer silently drops the time-travel debugger and JIT-compiles instead; it now falls back to the interpreter with a notice, the same as the existing actor and stdlib-shadowing fallbacks.
- REPL JIT: referencing the same top-level function as a value across multiple lines no longer fails with "duplicate definition of symbol '<fn>$clo_wrap'" (ORC backend).
- JIT REPL (both backends): defining a function that calls a previously
  REPL-defined function (`fn f(x) do x + 1 end` then `fn g(x) do f(x) end`)
  failed with an invalid-IR "redefinition of function" error and the new
  function was lost ("I cannot find `g`"). Calls to prior REPL bindings
  (`fn`s and `let`-bound lambdas alike) now dispatch through the binding's
  persistent slot, so they also follow the slot's current value rather than
  pinning the version seen at definition time.

- REPL, experimental ORC JIT backend (`MARCH_JIT_BACKEND=orc`): defining a
  second function in a session crashed the process with SIGSEGV. Each `fn`
  fragment re-emitted its prior-binding slot loaders with external linkage,
  colliding in ORC's single shared JITDylib with the real definition of the
  same name; and the ORC binding double-freed the module on the add-module
  error path, turning that recoverable error into a hard crash. The default
  clang backend was unaffected; each REPL/JIT session owns its own LLJIT
  instance (multiple sessions per process no longer collide).
  clang backend was unaffected.

- REPL: redefining a `fn` at the prompt now takes effect under both JIT
  backends (clang and ORC), matching interpreter mode's rebinding: the new
  body was previously silently ignored and calls kept answering with the
  first definition. `:reset` scroll-replay of unchanged cells still skips
  recompilation.
  recompilation. Combined with the slot-routed call fix above, this matches
  interpreter mode exactly: a direct call gets the new body, while a function
  defined earlier keeps calling the definition it was compiled against.

### Changed

- Interpreter: variable lookup no longer scans the builtin environment per reference (monomorphic comparison + hashed global scope). Interpreted programs run ~11x faster (fib(25): 16.6 s -> 1.5 s); REPL interpreter-mode lookups stay fast across prompts.
- REPL: expressions now compile in-process through LLVM ORC when libLLVM is installed (~200x lower per-line compile latency, whole-session ~3x); set MARCH_JIT_BACKEND=clang to restore the previous clang-subprocess backend. Unrecognized MARCH_JIT_BACKEND values fall back to clang as before.
- `march file.march` reuses the cached stdlib type environment; interpreted startup drops from ~1.0-1.2 s to ~0.28-0.36 s on a warm cache.

### Fixed

- **A function with a lambda in its body miscompiled when its name collided
  with a stdlib higher-order function's parameter.** `fn f(xs) do List.map(xs,
  fn y -> y + 1) end` segfaulted when compiled and failed at the REPL with
  `symbol not found in flat namespace '_f'` (losing the binding); renaming `f`
  to anything else worked. `List.map`'s own parameter is named `f`, and
  defunctionalization mistook it for the user's top-level function, so the
  lambda that closes over it captured no variables and called the wrong code.
- **REPL: defining a function with a lambda that calls the function being defined.**
  `fn g(n) do ... List.map([n], fn y -> g(y - 1)) ... end` failed at the prompt
  with `symbol not found in flat namespace '_g'`. The lifted lambda was
  compiled into a separate fragment loaded before `g` itself; it now shares one
  fragment with the function it belongs to.
- **REPL: a constructor of a type declared at the prompt evaluated as the
  type's FIRST variant.** With `type Color = Red | Green | Blue`, both `Green`
  and `Blue` answered `Red`; and, because the same wrong constructor tag
  reached pattern matching, `match Blue do Red -> 1 Green -> 2 Blue -> 3 end`
  answered `1`. A type declared at the prompt was registered with the REPL's
  JIT for pretty-printing only, never as an input to code generation, so every
  constructor of it was compiled with tag 0. `MARCH_REPL_INTERP=1` was
  unaffected.
- **REPL: values of Option-shaped and single-constructor types printed as raw
  words.** `Some(1)` displayed as `3`, `None` as `null`, and `Some("hi")` took
  the REPL down; a user `type T = X(Int) | Y` showed `X(7)` as `15` and `Y` as
  `null`. These representations are not heap cells (the value IS the payload
  word), and the REPL's printer was reading them as though they were.
  Constructor payloads of ordinary types now also print at their declared type
  rather than assuming every field is a tagged scalar (`P1(7)` was showing as
  `P1(3)`).
- **The REPL now actually caches its stdlib typecheck env.** Saving it had been
  failing on every start since the cache was introduced: the env contains an
  import-tracker closure that `Marshal` will not write, and the failure was
  swallowed, so each REPL launch re-typechecked the whole stdlib and left a
  zero-byte `stdlib_tcenv_*.tmp` file behind in `~/.cache/march` (1,132 of them
  had accumulated on one machine). Start-up now hits the cache on the second and
  later launches, a save that fails reports it on stderr instead of degrading
  silently, and both the REPL and the CLI sweep stale staging files left by
  processes that crashed mid-write.

## [0.3.0] - 2026-08-23

### Added

- **`Socket.set_recv_timeout(fd, ms)`** bounds every subsequent blocking read
  on a descriptor (`SO_RCVTIMEO`). Unlike a per-call deadline this is a
  persistent property of the fd, and that is the point: it is the only
  mechanism that reaches reads made through OpenSSL, so a TLS client can call
  it before `Tls.connect` to bound both the handshake and every later
  `Tls.read` against a peer that goes silent. On timeout, close the connection:
  a deadline firing part-way through a TLS record leaves the session
  unusable, so the read must not be retried.
- **`SocketError.RecvTimeout(Int)` and `SocketError.SocketOptionFailed(String)`.**
  "The peer went quiet" and "the read failed" are different facts and only one
  of them is worth retrying, so a timeout is now its own variant containing the
  deadline that expired, rather than a generic `RecvFailed`.
- **`tcp_recv_timeout` and `tls_read_timeout` builtins, with
  `Socket.recv_deadline` and `Tls.read_timeout` over them.** The same reads as
  the deadline mechanisms above, reporting an expired deadline as `Ok(None)`
  rather than an `Err`: the absence of an event rather than a kind of failure,
  for callers that would otherwise match a sentinel string. `tls_read_timeout`
  bounds a TLS read without touching `SO_RCVTIMEO`: it reads non-blocking and
  waits on `WANT_READ`/`WANT_WRITE`, so it handles a record that needs several
  socket reads, and leaves no lasting property on the fd.

### Fixed

- **An un-annotated `let d = record_get(r, k)` no longer compares false against
  a concrete `Some(<float>)` when compiled.** `record_get`'s result type determines
  its runtime representation at the call site: `Option(Float)` asks the runtime
  for a boxed `Some` cell, an unresolved `Option(_)` asks for the erased niche
  encoding; but a `let` with no annotation generalized the binding, so every
  USE instantiated a fresh payload var and the binding's own type, the one
  codegen reads, stayed unbound. The call site emitted the erased encoding while
  `Some(0.5)` on the other side of `==` was boxed, and the comparison answered
  `false` (interpreted said `true`). A `record_get` application is expansive and
  now contains the same value restriction as `cap_narrow`, `mint_cap` and
  `from_json`. Consequence, and it is a real one: a single `record_get` result
  can no longer be used at two different payload types; that typechecked
  at all only because the erasure hid the contradiction, since one stored field
  has one representation.

- **`unix_time_ms`, `string_to_codepoints` and `string_from_codepoint` now
  link when compiled.** All three typechecked and lowered to LLVM and then failed
  at LINK time with a bare C symbol name and no March span: they were
  registered in the typechecker's builtin table and absent from codegen's.
  They worked interpreted throughout, which is why no test caught it. Each now
  has a `march_*` runtime symbol on both the native and JS backends. An audit
  of all 531 builtin-table names turned up three more with no backing
  (`worker`, `dynamic_supervisor`, `from_json_events`); those need design
  decisions rather than table entries and are logged in `specs/todos/`.
  `march_unix_time_ms` reads the clock in integer nanoseconds rather than
  round-tripping through a double, which would lose sub-millisecond resolution
  as the epoch grows.

- **A compiled `println` is now one write syscall instead of two, so a line no
  longer tears when threads print concurrently.** `march_println` has emitted
  the payload and its newline in a single `writev(2)` since 2026-07, but
  compiled code never reached it. `println` is the polymorphic prelude wrapper,
  a module-level `fn` shadows the builtin of the same name, and the wrapper's
  body was `print(show(x))` followed by `print("\n")`: two `write(2)` calls with
  an arbitrary gap between them. (`@march_println` is declared in all 130
  committed `.ll` goldens and called in none of them.) With four green threads
  on eight scheduler threads printing 1200 lines, every run tore: 444 lines
  damaged in the recorded case. The wrapper now makes a single call, and
  `march_println` takes a lock across the `writev` so the guarantee also applies
  across OS threads rather than only against green threads sharing one. Halving
  the syscall count also makes output about twice as fast (300k lines to a file:
  2.41s to 1.23s median); the lock is free single-threaded and costs ~5% under
  four-way contention.

- **A compiled `spawn` + `await` no longer leaks two heap objects per task.**
  The 48-byte Task handle was never released: `task_spawn` hands back a
  reference the compiler already treats as consumed by `await`, and neither
  `task_await` nor `task_await_unwrap` released it; and `task_await_unwrap`
  additionally allocated an `Ok` wrapper it immediately discarded. Independent
  of result type, so any loop that awaits tasks (job queue, supervisor,
  request-per-task server) grew without bound: 10,000 spawn+awaits leaked
  20,000 objects, now 0. Awaiting one task twice is still correct: the
  release is per-await, matching the reference the compiler duplicates for
  every earlier use.
- **A compiled `Float` held in a generic slot no longer leaks its box.** A
  `Float` crossing into a type-erased slot is heap-boxed, and two places gave
  the box no owner: the `match` merge, which allocates one box per evaluation
  and could only free it when no arm looked like it returned a pointer (a
  never-reached "non-exhaustive match" arm was enough to defeat that), and the
  destructure of a boxed field such as `Some(x)` on an `Option(Float)`, which
  bound the box and then read through it, never releasing it. A
  20,000-iteration `Option(Float)` loop leaked 30,000 allocations and now
  leaks none; the same fix covers `Option(Option(Float))` and any generic
  constructor with a `Float` field. Reading a shared value is unaffected: the
  release happens only where the containing cell is actually freed.
- **A fold with a String, List or record accumulator no longer leaks one object
  per element.** The runtime's fold helpers release the previous accumulator
  only when they still own it, and until now the only case they could prove was
  a Float (its box contains a tag saying the callee just allocated it). Both
  shapes are ordinary March and the runtime sees the same closure for each:
  `fn (acc, x) -> Cons(x, acc)` takes the caller's reference and must not be
  released, `fn (acc, x) -> string_concat(acc, s)` does not and leaks without a
  release. Borrow inference already knows which, so the compiler now stamps
  that one bit into the closure object and the helpers read it back. Measured
  over 1,000,000 elements with a String accumulator: 1,000,018 live objects
  leaked, now 20. A closure built by a path that does not stamp (REPL/JIT,
  hot reload) keeps the old behaviour rather than risking a double free.
- **A self-recursive local function no longer leaks a Float box per iteration,
  and no longer depends on LLVM's optimizer to avoid a stack overflow.** The
  recursive call in `fn go(i, acc) do ... go(i - 1, f(acc)) end` went through
  the closure it was invoked with, which our own tail-call optimization did not
  recognise: it became a loop only if LLVM's tail-call elimination happened to
  fire, and every Float argument crossing that erased edge was boxed and
  dropped. The call is now resolved to a direct self-call, so it gets a real
  back-edge writing a native `double` slot. Measured at 1,000,000 deep:
  1,000,001 leaked boxes, now 1; and the same program, compiled `--opt 0`,
  went from SIGBUS to running clean at 10,000,000 deep.
- **`record_get(r, k) == Some(<float>)` is no longer always false when
  compiled.** The two sides differed on which type determines a constructor
  field's slot. Construction takes the field types as DECLARED on the ctor:
  `Option(a)`'s `Some(a)` is the type var `a`, so the slot is `ptr` and a Float
  payload is boxed into a `march_alloc_float` cell on the way in; while the
  generated equality function substituted the instantiation (`a := Float`)
  first and so loaded that slot as a raw `double`, comparing the two box
  *pointers*. Two equal floats in distinct boxes therefore always compared
  unequal, silently (correct interpreted, no crash). The eq function now picks
  the slot from the declared type, exactly as construction does, and unboxes
  before comparing when the declared field is generic. A field declared
  concrete `Float` keeps its inline-double slot, so the ABI pinned by
  `test/native/float_generic_field_abi` is unchanged; Int/Bool are untouched
  because their generic-slot form is the low-bit tag, which is a bijection.
  An un-annotated `let d = record_get(...)` was still mismatching for the same
  family of reason; that is fixed below.

- **Compiled closure calls no longer leak two heap boxes per call when a `Float`
  crosses the closure boundary.** Closure dispatch erases every argument and
  result to a uniform pointer, so a `Float` argument was boxed at the call site
  and a `Float` result boxed on return, and neither ~32-byte box got
  released. Any higher-order code over Floats paid it on every single call (a
  comparator passed to sort, a callback, `List.map` over Floats), unbounded, so
  a long-running server leaked without bound (measured: 7.2M leaked objects
  over a 5.1M-call probe; a small constant after). The call site now releases
  both boxes, with an alias guard for erased callees that return their argument
  unchanged and an exemption for recursive self-calls, the latter preserving
  the tail-call elimination that keeps deep local-fn recursion from
  overflowing the stack. The interpreter was never affected. Guarded by a
  `live_allocs()` probe in `@runtest`. Awaiting a Float-returning task still
  leaks its one result box per await (tracked, blocked on task-object
  lifetime); an erased self-recursive Float accumulator still leaks on its
  back-edge (tracked).
- **`Socket.recv_timeout` ignored its timeout argument entirely.** The
  parameter was `_timeout_ms` and the body was a byte-level copy of the untimed
  `recv/2` above it, so a caller who asked to be protected against a silent
  peer was not: the call simply blocked indefinitely. It now honours the deadline
  (`poll` then `recv`, leaving no lasting property on the fd) and reports
  `Err(RecvTimeout(ms))` when it expires. `tcp_recv_all` contained the same dead
  `timeout_ms` parameter and now enforces it as a total deadline across the
  whole read.
- **Read deadlines on sockets were silently defeated by scheduler preemption.**
  `SIGUSR1` is installed with `SA_RESTART`, so an interrupted `recv()` is
  restarted by the kernel, and a restarted `recv()` restarts its `SO_RCVTIMEO`
  timer from zero. With preemption firing every ~1ms, a deadline measured in
  hundreds of ms could never accumulate: `setsockopt` succeeded, `getsockopt`
  read the value back correctly, and the read still blocked indefinitely.
  `tcp_recv_chunk`, `tcp_recv_all` and every TLS entry point
  (`SSL_read`/`SSL_write`/`SSL_connect`/`SSL_accept`) now mask the preemption
  signal for the duration of the call, as `tcp_send_all` and `tcp_recv_exact`
  already did. This is what made a March HTTPS client wedge permanently when a
  provider accepted the connection and then sent no data.

- **`tcp_connect` reported a connection that had succeeded as
  "Socket is already connected".** An interrupted `connect()` was retried on the
  same fd (`do { connect } while (errno == EINTR)`), but POSIX completes an
  interrupted `connect()` asynchronously in the kernel: the retry reports the
  in-flight attempt as `EALREADY`/`EISCONN` instead of redoing it, so a
  successful connection surfaced as `Err`. It read as a concurrency bug even
  though the function keeps no shared state: preemption delivers `SIGUSR1` to
  every scheduler thread each millisecond, so a process making one outbound
  request almost never took a signal inside `connect()` while a process making
  several took them constantly: a single HTTPS client worked, four concurrent
  ones failed immediately. `connect()` is now issued once, with `EINTR` (and
  `EINPROGRESS`) recovered by waiting for writability and reading `SO_ERROR`.
  The `EINTR` retries on `recv`/`send`/`writev` are correct and unchanged.
- **`Vault.get` mis-decoded a `Vault(Option(_))`, `Vault(Float)` or `Vault(Unit)`
  entry when compiled.** The runtime always hands back the niche encoding of
  `Option` (`None` = null, `Some(v)` = `v`), because a vault handle's element
  type is a phantom the C runtime never sees; but the compiled call site decodes
  by the static type, which is the BOXED encoding for any element that is not
  niche-safe. A present entry's payload was therefore read as a constructor cell:
  the tag load landed inside the payload's own heap layout, matched no arm, and
  fell through to `panic: non-exhaustive pattern match` (a SIGSEGV for the `Unit`
  element). `Vault.get` now re-encodes at the call site, which is the one place
  that knows both sides. `Vault(Int)` / `Vault(String)` and every other
  niche-safe element type are untouched. The interpreter was correct throughout.

- **A `Float` read out of a dynamically-shaped `Record` segfaulted when
  compiled.** Three bugs, one repro. `record_get`'s boxed `Option(Float)` cell
  stored the raw IEEE-754 bits where the compiler's own decode calls
  `march_unbox_float` on the field, so it dereferenced the double's bit pattern as
  a heap address. An erased read (and `record_values` / `record_entries`, where the
  element types are always erased) passed those raw bits out into a uniform slot
  instead of a boxed `Float`. And `to_string`/`println` on a value with a type the
  compiler cannot know (`record_get(r, k)` is `Option('a)` with no way to pin
  `'a`, and a dangling type variable defaults to `String`) treated it as a string
  pointer. Erased values now cross that boundary in the accurate uniform
  representation, and the erased `show` classifies it at runtime rather than
  assuming. `println(record_get(r, "y"))` prints `Some(0.5)` compiled, matching
  the interpreter; storing `0.0` in an erased slot also no longer reads back as
  `None`. Concrete monomorphic `Float` fields keep their inline-`double` ABI;
  no part of the field-slot type rules changed.

- **`to_string` on an erased value crashed for short strings.** The type-erased
  formatter never recognised March's inline (small-string) representation (a
  string of 7 bytes or fewer is a value, not an address) and dereferenced it. It
  also dereferenced any other non-heap word instead of printing it.
- **A Float-returning `Task` was unusable when compiled.** Two independent
  bugs: `task_await`'s codegen decoded the Float box sitting in the `Ok`
  payload and stored the raw `double` bits back into the field, so the `Ok(v)`
  destructure decoded it a second time and dereferenced the IEEE-754 bit
  pattern as an address: **any** Float-returning task segfaulted with no
  output at every `--opt` level. Underneath that, a zero-arg lambda's closure
  was typed as its own return type rather than `() -> ret`, so the
  `Task.async(fn () -> 1.5)` spelling did not even compile (clang rejected the
  emitted IR with `'%ldN' defined with type 'double' but expected 'i64'`). The
  interpreter was correct throughout, so `Task.async` / `Task.await` /
  `Task.await_unwrap` / `Task.await_many` / `Task.async_stream` on a Float all
  worked in the REPL and failed natively. The zero-arg-lambda mistyping applied
  to every result type, not just Float: an `Int` thunk was mistyped identically
  and only persisted because i64 and ptr share a register.

- **`typed_array_*` returned corrupt values for scalar elements when compiled.**
  The family threads a truly generic `'a` through a uniform erased slot, so a
  scalar element has to arrive boxed (an `Int` tagged, a `Float` boxed); but
  `typed_array_create` / `set` / `fold` stored the raw bits instead, and the
  conditional untag on the way back out then corrupted every ODD value:
  `typed_array_create(3, 7)` followed by `get(0)` returned `3`. Because
  `get`/`map`/`filter` only read back what those three stored, every operation in
  the family was affected at once, and an even-valued element persisted untouched,
  which is why it looked half-working. A `Float` element went beyond wrong: the
  raw double bits reached `march_unbox_float` as a pointer and segfaulted. The
  interpreter was correct throughout.


### Fixed

- **Compiled `NativeArray.get_*` / `set_*` now bounds-check, as the docs and the
  interpreter always promised.** Every element accessor was a raw load/store at
  `arr + header + i * sizeof(elem)` with no range test, so an out-of-range index
  from ordinary safe March code read or wrote arbitrary heap memory; `set` worst
  of all, since both its in-place fast path and its copy path stored at the
  unchecked offset. `stdlib/native_array.march` has always documented "Panics if
  out of bounds" and the interpreter has always honoured it, so this was also an
  interpreter/compiled divergence, and one the differential oracle could not see
  because it only compares programs that stay in range. All ten accessors (five
  element widths × get/set) now panic with the interpreter's exact message. The
  bulk map/fold paths are intentionally unguarded (they derive indices from a
  length they just read, so they are in range by construction), which is why the
  cost is ~1% on a pure-indexing loop and no measurable cost on bulk numeric work.

### Added

- **The AddressSanitizer CI gate now covers the SIMD, narrow-width `NativeArray`
  (`f32`/`i32`/`u8`) and array-backed `Bytes` lowerings**, which no sanitizer had
  compiled before. `specs/lang/golden/sanitize.sh` swept only
  `specs/lang/golden/*.march`, and that corpus contains zero SIMD/NativeArray/Bytes
  programs, so every raw-memory path in that area sat outside the project's only
  ASAN gate while `dune runtest` exercised it uninstrumented on both OSes. The
  script now sweeps a second corpus: 24 curated, by-name `test/native/*.march`
  fixtures, kept separate in the output so a failure names the corpus it came from.
  Programs were added by name rather than moved into `specs/lang/golden/` because
  that directory is also the cross-compile oracle corpus and has a doc-lint-pinned
  count. The gate also now reports how many programs it actually swept and fails
  if that number is zero: it exits 0 without running anything on a Mac with
  CrowdStrike Falcon, so a green exit code by itself was never evidence it ran.

- **`Actor.send_after(pid, msg, delay_ms)` / `Actor.cancel_timer(ref)`: schedule a
  message for delayed delivery to an actor, with cancellation.** Previously an actor
  that wanted to poll, retry, time something out, or tick had to burn a green thread
  in a yield loop; the scheduler already had a timer heap backing `Actor.call`
  deadlines and supervisor restart backoff, but no API surfaced it to March code.
  `send_after` returns an opaque `TimerRef`; `cancel_timer` is safe to call at any
  time, including after the timer already fired or was already cancelled (both are
  no-ops). A cancelled or dead-target timer's message is disposed with no leak; see
  `specs/progress/2026-08-12-language-level-timers.md` for the RC design and a
  pre-existing scheduler-callback registration bug this also fixed along the way.

- **The capability limit now runs under `march --check` / `--check-json`, not only
  `--compile`.** A module with a `needs` manifest that is disproved by a stdlib-MEDIATED call
  (`File.read(p)` rather than the builtin `file_read(p)`, the idiomatic way to do IO) was
  caught only at `--compile` time by the TIR-side limit; `--check` exited 0. A sound
  typecheck-side limit now closes that gap without lowering: it attributes a capability to
  a module only through a clear `module.fn → stdlib… → builtin` chain (matching
  `--compile`'s attribution), so it can only under-report, never break a build `--compile`
  accepts. `--compile`'s limit remains the complete check. The violation contains a
  machine-applicable `needs` fix, so `forge fix` and the LSP can now apply it; previously the
  limit's fix payload reached neither, because `forge fix`'s only input is `--check-json`
  and the limit never ran there.


### Fixed

- **A module-qualified construction of a collision-set constructor no longer
  resolves to the WRONG type's constructor.** Writing `Ast.Asc` as an
  expression, when another module (e.g. stdlib `DataFrame`) declares a
  same-named constructor on a same-short-named type and the collision is
  public + impl-bearing, keyed the construction BARE (`SortDir.Asc`) while
  the pattern side (fixed 2026-07-27) keyed it fully qualified
  (`Ast.SortDir.Asc`); codegen's suffix resolver then gave the constructed
  value the OTHER type's runtime tag, so every match on it failed open to
  the default arm at runtime (compiled only; the interpreter was correct).
  Found via depot: 16+ ORDER BY/GROUP BY/WHERE tests panicked
  "non-exhaustive pattern match" the moment any file pulling stdlib
  DataFrame joined the whole-program build. The expression side now
  re-expands a written module qualifier through the same
  narrow-collision table the pattern side uses, so both sides agree on the
  qualified key. See `lib/tir/lower.ml` (ECon).

- **A non-`String` `Vault` key no longer crashes, and a key stored by
  `Vault.set` can now actually be read back by `Vault.get`.** Two bugs.
  `vault_key_cstr` assumed every key was a `march_string *` and dereferenced
  it unconditionally, so any Int/Bool/Atom key read the tag word as a length
  and the payload as a data pointer: SIGSEGV/SIGBUS on the first Int key,
  even though `stdlib/vault.march` documents Int/String/Bool/Atom keys. It now
  dispatches on the uniform representation (tagged scalar → `"i:<decimal>"`,
  matching the interpreter's form; string → its raw bytes, unchanged, so
  `Vault.keys()` still returns real Strings; boxed Float → its bits), and
  panics with an actionable message for a Tuple/Ctor key rather than folding
  every value of one ctor onto a single bucket: a heap cell contains no arity,
  so there is no structure to walk. Separately, only the *write* builtins coerced
  the key to `ptr`; `vault_get`/`drop`/`update`/`incr` and the `ns_*` trio fell
  through to the general call path and passed the key with its natural LLVM
  type, so an Int key arrived at `march_vault_get` raw while `march_vault_set`
  had stored it tagged; the two hashed different strings and the value was
  unreachable. Both sides now agree, and Int keys round-trip identically
  compiled and interpreted.

- **Security: `~H` no longer renders an interpolated value as executable
  JavaScript, and its URL-attribute list no longer misses live vectors.** Found
  and fixed pre-release; no tagged version shipped it. Three bugs, all in the
  context table rather than in any escaper:
  `<script>var x = ${p}</script>` and `<button onclick="n = ${p}">` gave every
  script context the JS *string* escaper, which only stops a value ENDING a
  string literal; at an expression position there is no literal, so
  `alert(document.cookie)` passed through as code (and, in the other direction,
  valid arithmetic came out a syntax error). `xlink:href`, `object data` and
  `ping` were absent from the URL-attribute list, so they fell through to plain
  attribute escaping and passed `javascript:` untouched. `srcdoc` was correctly
  entity-escaped as an attribute, but browsers HTML-decode it and parse the
  result as a document, so the escaping is undone before the markup is read.
  The table now models JS positions properly (string literal, expression,
  comment, regex literal, template literal), with a new JS-expression escaper
  that renders a value as an inert quoted string rather than as code;
  `xlink:href`, `data`, `ping`, `manifest` and `longdesc` are classified as
  URLs; and `srcdoc`, `srcset`, JS comments, regex and template literals are
  compile errors that say why. `Html.trust_js` still inserts trusted JS
  verbatim. **Note for template authors:** a hole at a JS expression position
  now renders as a JS string, so `<script>var n = ${count}</script>` yields
  `'42'`, not `42`; put the value in a quoted JS string, or use
  `Html.trust_js`, if you need its JS type. See
  `specs/progress/2026-08-20-h-sigil-js-and-url-attr-xss.md`.

- **Fold operations no longer leak the accumulator chain (~32 B/element, unbounded).** Every
  `NativeArray.fold_*` / `typed_array_fold` runtime helper passed the accumulator through
  the loop in its boxed form and never released the previous one, so a fold with a `Float`
  accumulator (summing, averaging, dot products) leaked one heap object per element:
  measured `live_allocs()` delta 4,000,007 over two 2,000,000-element fold runs, now 9 (a
  constant, verified identical at 500k/2M/8M elements). All five fold bodies are fixed,
  including the shared `march_typed_array_fold` root the others were copied from. The
  release is intentionally guarded rather than unconditional: an apply fn returns a
  *borrowed* alias when it passes a `ptr` parameter straight through, so releasing every
  previous accumulator would free live array elements. Fold calls with an `Int` accumulator were
  never affected. See `specs/progress/2026-08-20-fold-accumulator-chain-leak-fix.md`; the
  residual for non-`Float` heap accumulators is tracked in `specs/todos/`.

- **A message arriving while an actor was already being woken no longer kills
  that actor.** `march_sched_send` pushes under the mailbox lock but wakes after
  releasing it, so two senders racing one receiver could issue two wakes for
  messages the receiver drained as a single batch; the second wake then landed
  after it had re-parked, resuming it with a validly empty mailbox. The
  untimed receive reported that as "no message", which the actor dispatch loop
  reads as "I was killed": it exited and ran the death path on an actor where the
  `$alive` word was still 1. A later `Actor.call` on that pid then failed with
  `actor not alive`: no crash, no diagnostic, exit code 0. A blocking receive
  now re-parks on a wake it cannot attribute to a message, and "no message" is
  reserved for a real stop request (shutdown, or actor death). Only reachable
  compiled, with more than one scheduler thread; a bounded mailbox under the
  `block` policy made it far likelier, because releasing blocked senders wakes
  the whole herd at once, which is exactly the burst of concurrent senders the
  race needs. Measured at ~4% of runs of `bench/actors/fanin_flood.march`, one
  of the `scripts/actor-load.sh` gates. Note this broke the guarantee
  `Actor.set_queue_limit`'s own documentation makes for policy 3, that no
  request or reply is at any point silently discarded. See
  `specs/progress/2026-08-19-fanin-blocked-mailbox-spurious-actor-death.md`.

- **An actor message-handler binder now shadows a same-named top-level function
  when compiled.** A handler param with a name matching ANY top-level function
  linked into the program (no `import` of that module required) was silently
  discarded, and the bare reference in the handler body resolved to the FUNCTION
  instead, emitting its raw code address where the bound value belonged. Found in
  the wild as `on Deliver(session_id, kind, text, approved)` colliding with stdlib
  `HttpServer.text`: the compiled server passed the function's address as the
  message text, and refcounting that code address wrote into read-only `__TEXT`:
  SIGBUS, exit 138, presenting misleadingly as "the actor spawned in this handler
  never starts". Params that happened not to collide worked only by name
  coincidence with the TIR param var. The interpreter was always correct, so this
  was compiled-only. `lower_fn_def` already registered a function's params in the
  local-name scope that `resolve_use_alias` consults before rewriting a bare name
  into a qualified global; `lower_handler` now does the same for `ah_params`.

- **`forge` no longer pairs one install's compiler with another install's stdlib.**
  `forge` set `MARCH_STDLIB` from its OWN executable location
  (`<forge>/../share/march`) while running the `march` chosen by toolchain
  resolution (`~/.march/current/bin/march`). When the two live in different
  prefixes (an opam-installed `forge` driving a pinned toolchain), every forge
  subprocess typechecked a newer compiler against an older stdlib. The symptom is
  a flood of type errors in source that is actually correct: a pre-`Vault(v)`
  stdlib under a post-`Vault(v)` compiler produced 47 bogus "expected `Int` but
  got …" Vault errors in one project, while the identical files checked clean
  under a direct `march --check`. The stdlib is now derived from the resolved
  toolchain (`versions/<tag>/stdlib`), and when a toolchain is resolved but ships
  no `stdlib/`, `MARCH_STDLIB` is left unset so the compiler resolves its own
  exe-relative stdlib rather than falling back to forge's prefix. `forge notebook`
  had a second copy of the same guess and now shares the fixed resolver; its
  `march` lookup is toolchain-aware for the same reason.

- Fixed a data race in the capability-revocation plane: an actor's `epoch`
  field (backing `march_get_cap`/`march_is_cap_valid`/`march_send_checked`)
  was written by a supervisor's restart without any lock or atomic and read
  as a plain field on an arbitrary sender's thread, the same unsynchronized
  plain-write/plain-read shape as the previously-fixed `pid_index` race. A
  sender holding a `Cap` captured before a supervised restart could race the
  epoch comparison against the respawn's write, with no ordering guarantee
  between the two. `epoch` is now `_Atomic`, release-stored on write and
  acquire-loaded on every cross-thread read.

- `march_actor_broadcast_migrate` no longer leaks its malloc'd migrate-control
  message when a target actor's green thread dies between the broadcast's
  snapshot and send phases. The send's delivery-status return value
  (`MARCH_SEND_DEAD`) was previously ignored; it is now checked, and the
  message is `free()`'d on that path instead of being abandoned. Bounded
  (at most `MARCH_MIGRATE_SNAPSHOT` = 2048 matched actors per broadcast call)
  but real prior to this fix.

- **`forge run` now passes `forge.toml`'s `[ffi]` sources to the compiler, so an app
  that uses FFI can be run interpreted.** Previously the interpreted path built its
  `march` command line with no `--ffi-c` flags at all, so the compiler built no shim
  `.so` and every `extern` call failed at runtime with "symbol not found for
  interpreter FFI (build the runtime, or run with `--compile`)": an app declaring
  `[ffi]` sources could only be run with `--compile`. `forge build` and `forge test`
  already threaded these flags through; `forge run` now matches them. Note that FFI
  arguments of function type (callbacks/upcalls) still require `--compile`, and a
  project declaring only `[ffi.rust]` (no C sources) is still interpreter-unsupported.

- Two actors with the same name in different modules no longer share one capability
  closure. Handler closures were keyed by the actor's bare `<Actor>_<Msg>` name, so
  `Safe.Worker` and `Danger.Worker` collided on `Worker_Go` and their capabilities were
  merged: spawning either one was charged the union of both, rejecting valid code with a
  chain that pointed at the wrong actor. Handler and actor keys are now qualified by the
  declaring module. The over-approximation was sound (it could only over-charge, never mask
  a leak), so this is a false-positive fix, not a security fix.

- **`Vault.ns_get` on a namespace that was never written now correctly
  returns `None` instead of `Some(<garbage>)` in compiled binaries.** The
  namespace-missing path hand-built a boxed "Option" (a non-NULL allocation
  with a tag word of 0), but Option is niche-encoded everywhere else in the
  runtime: `None` is the NULL pointer itself. The non-NULL stand-in decoded
  as `Some` of an uninitialized pointer, so destructuring it could hang or
  crash. The tree-walking interpreter uses a separate code path and was
  unaffected.
- The whole-program capability grant now bounds actor message handlers. A handler's body
  was invisible to `main`'s grant reachability walk, so a program granted only
  `Cap(IO.Console)` could `file_write` inside an actor handler, and it compiled, ran, and
  wrote the file. The grant now follows `spawn(Actor)` edges into the actor's handlers, so a
  handler's IO counts against the grant the moment the actor is spawned. A defined-but-never-
  spawned actor stays free, like any other dead code. The manifest (`needs`) side already
  tracked handlers; only the grant did not.

- **`forge publish`'s semver-bump enforcement actually runs now.** Its API-surface extractor
  scanned source text for `pub fn ... -> T`, a syntax March doesn't have (no `pub` keyword;
  return types are `: T`, not `-> T`), so it silently read an empty public surface for every
  real package. With both the old and new surface empty, the diff was always empty and the
  gate always said "Ok": a breaking change could be published under a patch bump with no
  warning. Bounded in practice by a separate pre-1.0 exemption, but a live landmine for the
  first package to reach 1.0.0. The extractor now reads the public surface off the real AST
  (same parser `forge cap` already uses), so it also sees multi-head clauses, default
  arguments, and signatures wrapped across lines that a line scanner never could.

### Added

- **`let*` now works at the REPL prompt.** `let* x = e` binds through the
  value's own `flat_map`, so `Option`, `Result`, `List` and your own types all
  work interactively, not just inside a function. There is no continuation at
  a prompt, so it binds the **first** value the expression yields: for
  `Option`/`Result` that is simply "unwrap"; for a list it is the first
  element. A value that yields no element (`None`, `Err`, `[]`) binds no name and
  tells you so instead of silently leaving the name undefined. Works in the
  terminal REPL, the TUI and the browser REPL.

- **`Parse.run_all`**: run a parser and require it to consume the *whole*
  input. `Parse.run` succeeds on a valid PREFIX and silently discards the rest
  (`run(number(), "123xyz")` is `Ok("123")`), which is the usual way a
  combinator grammar returns a wrong answer with no warning. `run_all` is `run` plus
  `eof`, so the same call reports `1:4: I was expecting end of input`. `run` is
  still the right choice when a leftover tail is meaningful.
- **A parsing guide**, [docs/parsing.md](https://march-lang.org/docs/parsing/):
  the `Parse` library had a complete API reference but no narrative
  introduction. Covers the building blocks, why recursive grammars need
  `delay`, how `label`/`ctx`/`commit` combine to produce good diagnostics
  (including the commit-placement trap, where both spellings accept all valid
  input and only differ on the malformed input where the message was important), and
  collecting every error in one pass with `recover`.

- **New `AhoCorasick` stdlib module** for multi-pattern string search: build an automaton
  once from a list of literal patterns (`AhoCorasick.build`), then find every match of any
  of them in a haystack in a single linear pass (`find_all` / `find_first` / `matches`),
  in `O(haystack + total pattern length)` time regardless of how many patterns there are:
  independent of the pattern count, unlike calling `String.index_of` once per pattern.
  Overlapping matches and patterns that are prefixes of one another are both reported
  correctly (e.g. patterns `"he"` and `"she"` both match inside `"ushers"`). Useful for
  March-written lexers/tokenizers doing keyword dispatch, and any "find any of these N
  literal strings" search.
- An unrecognized capability in `needs` is now an error with a did-you-mean suggestion
  (`needs IO.FileWrit` → `needs IO.FileWrite`). Typos previously produced only a misleading
  "declared but no function requires it; remove the unused declaration" warning.

### Fixed

- **`let*` now works with user-defined types, not just `Option`/`Result`/`List`.**
  Its documented extension point ("define `flat_map` in a module named after
  the type") was non-functional for any type you defined yourself, whether in
  the same file or imported: resolution went exclusively through the stdlib
  module loader, which finds a module only if a *file* of the matching
  snake_case name exists. A user module is already bound in scope but has no
  such file, so `let*` reported that `Box.flat_map` did not exist while telling
  the reader to define exactly the function they had already defined.
  Resolution now consults the current scope first, matching how an ordinary
  `Box.flat_map(...)` call already resolved.
- **`Parse.label` is documented again.** Its doc comment had been written but
  sat above a *private* helper rather than above `label` itself, so it was
  dropped from the generated reference entirely and `label` (the combinator
  with the single job of making error messages readable) was the module's only
  undocumented public function.

### Changed

- **BREAKING: the parser combinator module is now `Parser`, not `Parse`.**
  `Parse.lit(...)` becomes `Parser.lit(...)`, and the type is
  `Parser.Parser(a)`. This is what makes `let*` usable with parsers: `let*`
  finds a type's `flat_map` in the module named after the type, and the type
  has always been `Parser`, so the sugar did not work with the one library that provided
  the motivating example it was built from. Context-sensitive grammars now
  read as ordinary code:
  ```march
  pfn counted() : Parser.Parser(List(String)) do
    let* n = digit()                      -- a leading digit says how many follow
    Parser.repeat(Parser.lit("x"), n - 48)
  end
  ```
  Migration is a rename: `Parse.` → `Parser.`. No code outside the library's
  own tests used it.

- A partial-grant error (e.g. `main` granted `Cap(IO.Console)` but the program reaches
  `IO.Spawn`) now suggests the precise least-privilege fix (add a `Cap(IO.Spawn)` parameter
  to `main`) before the broad `Cap(IO)` escape hatch, matching the no-grant diagnostic's
  suggested-signature help. It previously offered only "widen the grant (e.g. `Cap(IO)`)",
  steering users to the widest grant against the system's own least-privilege ethos.
- **`String.index_of`/`index_of_from`/`contains` (and everything else that shares
  `march_memmem` in `runtime/march_runtime.c`) now scan for the needle's first byte with a
  hand-written SIMD kernel** instead of delegating to libc `memchr`: SSE2 on x86-64 (the ABI
  baseline, no `-msse4.2`/`-mavx` flag needed) and NEON on AArch64 (the ABI baseline on both
  CI platforms, macOS arm64 and Linux arm64), each unrolled to 64 bytes per iteration with a
  cheap "any lane matched" reduction before paying for exact-position extraction, falling back
  to plain `memchr` on any other target. Measured ~30% faster than the previous `memchr`-based
  implementation on a 32MB-haystack/absent-needle benchmark on Apple Silicon. Purely a
  performance change: matching contract (empty-needle, negative/out-of-range `start`
  clamping, overlapping-match resume-at-hit+1, embedded-NUL handling) is unchanged and pinned
  by `test/native/string_search_edge_cases.march`.

- **Local actor monitors now deliver reason-carrying `Down(ref, target_pid, reason)` messages** (`Normal`, `Killed`, or `Crash(String)`) through the control plane, so the notification bypasses mailbox limits and is not lost behind a full bounded queue. Interpreter and compiled backends now have the same local monitor payload and reason semantics.
- A `Cap(X)` parameter on a non-`main` function is no longer a limit on everything that
  function transitively reaches. Taking one capability parameter used to oblige a function
  to take parameters for every other capability it reached, forcing callers to thread
  capabilities through the call graph. Capabilities are module-scoped: `needs`, the module
  limit, and `main`'s grant are the checks. `main`'s grant is unchanged.
- **`Actor.register(pid, name)` / `Actor.unregister(name)` / `Actor.whereis(name)` / `Actor.registered()`**: a named process registry over the runtime's `march_actor_*` C API. `register` fails (returns `false`) if the name is already held by a live actor, or if `pid` is dead; a stale entry left by a dead actor is silently reusable. `whereis` re-checks liveness at lookup time, so a name with a crashed actor behind it resolves to `None` even before any restart-carry-forward cleanup runs. No capability is required: the registry table is owned by the runtime, so no March-level naming call happens. These four operations behave identically in the compiled and interpreted backends, and so does keeping a name across a supervisor **restart** (below). For a hot lookup, resolve a name once and cache the `Pid`, re-resolving on `None`: repeated lookups of the *same* name contend on the reference count of the single stored value, and `send` itself takes no registry lock.
- **A registered name now persists across a supervisor restart.** `do_actor_death` snapshots a supervised actor's registered names onto its (never-freed) meta immediately before `registry_retire_actor` wipes them, and `march_respawn_child` re-registers each saved name on the replacement child, including across the up-to-~3.2s exponential-backoff delay a repeat crash can take. A holder outside the supervision tree that only knew the name, never any specific Pid, keeps resolving to whichever incarnation is currently alive. If a different live actor claims the same name during the restart window, the carried-forward registration is dropped for that name rather than stealing it back: the name validly belongs to its new, live owner. Unsupervised actors are unaffected: their names are simply dropped on death, as before. The interpreter now does the same thing, so this is backend parity rather than a compiled-only feature: `crash_actor` stashes a supervised actor's `named_registry` names before retiring them and `spawn_child_actor` re-establishes them on the replacement, under the same first-live-claim-wins rule. That includes a live sibling killed by a `one_for_all` / `rest_for_one` batch restart: those strategies clear the sibling's supervisor field before crashing it, so they capture its names explicitly rather than relying on that field as a gate. `test/native/actor_registry_restart.march` and `actor_registry_restart_batch.march` now run interpreted as well as compiled and diff against the same expected output.

### Changed

- **Vault table handles are now typed: `Vault(v)`, phantom in the type of the values the table stores.** `Vault.new`/`Vault.open` hand back a `Vault(v)`; `set`/`set_ttl`/`put_new`/`get`/`get_or`/`has`/`update`/`drop`/`all` all speak the same `v`, so storing an `Int` and reading it back as a `Pid` is now a type error instead of a value reinterpreted at the wrong type (which the runtime then dereferenced as an actor record on the next `send`). `Vault.update`'s callback is `(v) -> v`; `Vault.incr` requires a `Vault(Int)` and `Vault.push_capped` a `Vault(List(e))`, matching what the C runtime actually reads and writes; `Vault.keys` is now `List(String)` rather than a caller-chosen key type, because keys are stringified on insert.

  Handles do not let-generalize (a Vault is a process-global mutable cell, i.e. exactly ML's `ref []` case), so the element type is fixed where the handle is bound and every later use is checked against it. Two doors stay element-erased on purpose and are documented as such: `new`/`open`/`whereis` mint a handle from a *name*, so they choose `v` rather than check it (a name-keyed global table cannot do better), and `ns_set`/`ns_get`/`ns_drop` take a namespace string with no handle to carry `v`. Writing a return annotation (`fn table() : Vault(v)`) is the explicit opt-out; `Config`, which is a heterogeneous store by design, uses it and stays as erased as it was.

  Compatibility: code that keeps one element type per table needs no change. Code that stored several unrelated types in one table under a single bound handle now needs either separate tables or the explicit `: Vault(v)` annotation. No behaviour changes at runtime (no representation, layout, or codegen change), and the runtime-owned `$actor_registry` table, which C reads and writes directly without passing through the typechecker, is untouched.
- Vault reads no longer serialise against each other: `get`/`size`/`keys` take a shared, striped reader-count lock (`set`/`set_ttl`/`put_new`/`incr`/`push_capped`/`drop` still take it exclusively). Concurrent reads of *distinct* keys now scale close to linearly with thread count; concurrent reads of the *same* key are still bounded by reference-count contention on that key's one shared value, an orthogonal cost the lock change doesn't touch.
- **`vault_get`/`vault_size`/`vault_keys` no longer require `needs IO.Mut`.** A Vault table is in-memory, so a lookup contains no ambient authority; only naming a table (`vault_new`/`vault_whereis`, mints a handle from a string) and mutating one (`vault_set`/`vault_set_ttl`/`vault_drop`/`vault_update`/`vault_put_new`/`vault_incr`/`vault_push_capped`) still do. Source-compatible: an existing module that declared `needs IO.Mut` only to read now over-declares (harmless; the checked stdlib contained no such module). Accepted trade-off: a reader of shared mutable state is now non-deterministic without saying so in its `needs`; authority remains auditable at the boundary, since some module still had to name/write the table under a declared capability.
- Missing `needs` declarations are now reported as one aggregated error per module listing
  every missing capability, with a single fix that inserts them all, instead of one error
  per offending call site.
- A `--cap-strict` capability limit violation is now reported as an ordinary diagnostic
  (file, line, source excerpt, and a machine-applicable `FInsert` fix that inserts the missing
  `needs` line) instead of a bespoke `-- CAPABILITY CEILING --` block with none of those. It
  will become visible to the LSP and applicable by `forge fix` once the limit also runs under
  `--check` (`forge fix`'s only input is `march --check-json`, which today exits before this
  diagnostic is built at all, so the fix has no consumer yet; see
  `specs/todos/2026-08-14-cap-ceiling-under-check-needs-body-only-closure.md`).
  `march --check` still does not run the limit (it does not lower to TIR, which the check
  currently requires); a module with a `needs` manifest disproved only by a stdlib-mediated
  call (`File.read` rather than `file_read`) is still caught only by `march --compile`.
- A grant violation now names the chain of the user's own functions that reaches the
  capability, instead of only the stdlib function that owns it.

### Removed

- **The unreachable `link` builtin is gone.** The interpreter contained a `link`
  builtin and `ai_links` crash-propagation infrastructure that the typechecker never
  exposed, so no March program could call it: `link(a, b)` failed with "I cannot
  find `link`". Rather than finish it, March commits to monitors plus supervisors
  as its fault model (see the actors chapter): a monitor's `Down(ref, pid, reason)`
  now contains `Normal`/`Killed`/`Crash(msg)`, which is what a link's exit signal
  would have told a peer, without bidirectional coupling or a `trap_exit` escape
  hatch. No program can regress, because none could reach it.

- **The compiled/LLVM backend's identical unreachable `link`/`unlink` builtin is
  also gone**, finishing the removal above (that pass was interpreter-only). The
  `march_link`/`march_unlink` runtime functions, their builtin-table entries, and
  the forward declarations every compiled module's prelude contained are all
  deleted. Worth recording: the two backends' `link` never actually agreed even
  before removal: the interpreter did real bidirectional crash propagation,
  while the compiled backend implemented `link` as two one-way `monitor` calls
  that only queued a `Down` message and never crashed the peer. So there was no
  "restore it" path without designing fresh semantics from scratch; this
  reinforces that removing `link` entirely, rather than exposing it as-is, was
  correct.

### Fixed

- **A delayed supervisor restart (a repeat crash backed off by exponential backoff, up to
  ~3.2s before jitter) re-validated its supervisor with an address-based liveness probe**,
  not an incarnation-precise one. If the supervisor crashed and the March allocator gave its
  address to an unrelated new actor within that backoff window, the restart could run its
  bookkeeping (child array, restart budget) against that unrelated actor's metadata instead
  of silently no-oping. The recheck is now keyed off the supervisor's `pid_index` (per-spawn,
  never reused) rather than its raw heap address, so a resolved match proves it is still the
  original incarnation. Timing (when a restart fires) is unchanged; only which supervisor a
  delayed restart validates against is affected.

- **An actor's cleanup callbacks (registered via `register_resource`) were linked onto
  and taken back off the actor's cleanup list with no lock held**, unlike the equivalent
  monitor list. A cleanup callback registered concurrently with that actor's death could
  race the death path's walk-and-free: a node the registering thread just linked could be
  freed out from under it, or dropped entirely, either leaking whatever OS resource the
  callback was meant to release or crashing on the freed node. Both sides now detach/link
  under the same lock the monitor list already uses; the cleanup closures themselves still
  run lock-free, since they are arbitrary March code that can re-enter the runtime.

- **Two children of a compiled `one_for_all`/`rest_for_one` supervisor crashing for the
  first time at the same moment on different scheduler threads could run two restart
  strategies concurrently** against the same supervisor's child array. A first crash
  claimed no marker (only repeat, backed-off crashes did), so both threads saw "no restart
  pending" and both proceeded. A synchronous batch restart now claims an in-flight marker
  in the same critical section that determines it is not skipping, and keeps it until the
  strategy has fully returned; a sibling that crashes during that window is absorbed into
  the in-flight restart (widening its child-index range) instead of starting a competing
  one. Interpreted programs were never affected.

- Fixed an internal compiler error (`Invalid_argument("List.nth")`) on the most common
  project shape: a `MARCH_LIB_PATH` dependency (any file loaded via `use`/import from a
  separate `.march` file) that violates the `--cap-strict` limit but declares no `needs`
  of its own. Such a module is synthesized with a placeholder span, and the fix-indent
  helper indexed a negative line number into the wrong file's source. It now falls back to
  the dependency's own first real declaration for the diagnostic span, and, if no real
  span can be found at all, to the pre-existing bespoke `-- CAPABILITY CEILING --`
  rendering rather than crashing or pointing at unrelated code.
- An unknown capability in `needs` (`needs Network`) no longer also produces a contradictory
  "declares `needs Network` but no function requires it; remove the unused capability
  declaration" warning on the same line. The two diagnostics gave opposite advice (fix the
  name vs. delete the line); the unused-capability check now skips any capability path the
  unknown-capability check already rejected.
- The aggregated missing-`needs` error no longer proposes a fix that overlaps a capability
  `Cap(X)` signature parameter is separately demanding. `fn main(cap : Cap(IO))` calling
  `println`/`unix_time`/`random_bytes` used to get both "add `needs IO`" (from the `Cap(IO)`
  parameter) and "add `needs IO.Clock`, `needs IO.Console`, `needs IO.Random`" (from the
  body scan); `forge fix` applying both wrote four `needs` lines where one suffices. The
  aggregation now drops any capability already subsumed by a capability Check 1 demands.

- Capability parameters no longer trigger "Unused variable" warnings. A capability value is
  a runtime-erased grant token and is normally never referenced in the body.
- `fn main(cap : Cap(IO))` no longer emits the "narrow to least-privilege" hint. That is the
  documented entry-point convention; the hint still fires on non-`main` functions.

- `forge new` now scaffolds capability-correct projects. The generated `app`/`tool` entry
  point and test module declared no `needs` and took no grant, so a freshly created project
  failed `forge build` with two capability errors.

- `forge fix` now applies capability fixes. It previously would not run whenever any
  error-severity diagnostic contained a machine-applicable fix, which is exactly what the
  missing-`needs` and missing-grant errors emit, so the fix those errors advertised could
  never be applied.
- **A `panic()` inside a hot-reload actor's message handler no longer pins its
  code version indefinitely.** A hot-reload dispatch is bracketed by
  `march_dispatch_enter`/`march_dispatch_leave`, with a reference count that stops a
  concurrent publish from unloading code that is currently executing. The crash
  trap's `longjmp` jumped over the `leave`, so every crash left that version's
  count permanently above zero and its ring slot unreclaimable: a crash-looping
  supervised actor burned one slot per crash. The crash path now releases the pin
  before running the death/restart sequence.

- **Fixed a use-after-free that could crash any multi-scheduler program where actors are reachable from more than one owner**: a monitor, a `Pid` stored in a `Vault` table, a `Pid` passed to another actor, or (most visibly, and how this was found) an actor registered under a name, since `Actor.register` makes the registry a second owner. The bug long predates the registry; the registry is simply the easiest way to give an actor a second owner. If a concurrent program of yours has at any point "flaked mysteriously" with a `SIGBUS` or an RC underflow, it is worth re-checking against this fix rather than assuming it was unrelated. While an actor's green thread ran a message handler, the runtime overwrote that actor's refcount word with `1` and restored it afterwards, a leftover from before codegen learned to update actor structs in place unconditionally. The forced `1` was visible to every other thread, so a concurrent drop of a `Pid` observed "last reference" and freed an actor record that still had live owners; the registry was then left pointing at freed memory, and the next lookup or death-cleanup read a garbage refcount (`march: RC underflow (rc was -6899412650951359789)`, `SIGBUS`, or `SIGTRAP`). Concurrent *increments* during the same window were silently lost. Single-scheduler runs were never affected. The spawn-and-kill churn scenario failed on 6 of 30 runs before the fix and 0 of 60 after.
- **A killed actor's registered names are now reclaimed, not left occupying the registry indefinitely.** `do_actor_death` (and the interpreter's matching `crash_actor` path) now retires all of the dying actor's names (dropping the forward-table entry and the per-actor reverse index) before any monitor `Down` notification is delivered, so a watcher woken by the death can never observe a name still mapped to the dead incarnation. Previously only the runtime's own `$alive`-flag re-check kept `whereis`/`registered` correct at lookup time; the table entry itself, and the interpreter's `named_registry` map, held on to the name indefinitely unless a later registration happened to overwrite it. `Actor.registered()` in the interpreter no longer lists a name after its actor is killed.
- **A top-level function in your program can no longer silently replace a
  name the March Prelude relies on internally.** `println` calls `print` and
  `show` unqualified (also `panic`, `reverse`, and `to_string`, each called
  from inside another Prelude function's own body), and all of them sat in a
  flat, unprotected namespace shared with your program's own entry-module
  declarations. A private helper named `print` or `show` (or any of the
  others Prelude actually calls internally) silently took over that name for
  the *whole program*, including inside Prelude's own code, with no error at
  any compiler stage. Depending on how the two definitions' types happened to
  line up this surfaced as a misattributed runtime arity error, a **compiled
  SIGBUS with no diagnostic**, or a **fully silent no-op**: `println`
  printing no output at all, with no error and no crash. Now rejected as a
  compile error naming the colliding function and why it matters, across
  `march file.march`, `march --check`, `march --compile`, `march check`, and
  `march dap`. Shadowing a Prelude/builtin name Prelude never calls
  internally (`head`, `map`, `unwrap`, `file_read`, and most of the rest)
  remains legal and unaffected; that's a documented, separately-tested
  feature, not part of this bug. **The editor (LSP) now reports this the
  same way `march --compile`/`--check` do**: previously the language
  server's own independent analysis pipeline didn't run this check, so a
  colliding function showed no squiggle at all until you actually compiled.
- **`simd_leak_probe`'s CI leak guard no longer false-positives on Linux.**
  The guard for the per-call SIMD vector temp-box leak
  (`test/native/simd_leak_probe.march`) enforced an absolute peak-RSS
  threshold (< 32 MB) calibrated on macOS's ~2.7 MB healthy baseline; Linux's
  ~122 MB process baseline made that threshold unreachable, so the guard
  went RED on a healthy binary (measured 128,761,856 B) the first time CI's
  ubuntu leg ran it. Converted to the same fix already applied to the
  sibling `native_arr_fold_leak_probe` guard: assert a `live_allocs()`
  delta instead of RSS, which counts leaked `march_simd_alloc` cells
  directly and needs no platform calibration. Healthy delta is now ~1
  object (threshold `< 1000`); a regression adds exactly 2,000,000,
  confirmed by reverting the caller-side release in
  `lib/tir/llvm_emit.ml` and remeasuring.

- **`Regex` no longer has a denial-of-service on adversarial input.** The
  engine matched by backtracking, so repeated quantifiers over one character
  class followed by a byte that never matches cost O(n^k): the pattern
  `a*a*a*a*b` against 80 bytes of `a` took **5.7 seconds** compiled at
  `--opt 2`, and the cost is reachable from a pattern in a config file plus a
  short user-supplied string. (Note this is *polynomial*, not the exponential
  of the classic `(a+)+$`; that pattern is not expressible here, since the
  engine has neither groups nor alternation.) `matches`, `matches_opts`,
  `find`, `find_all`, `replace`, `replace_all` and `split` now all simulate
  the set of reachable NFA states instead, which is linear in the input and
  cannot blow up: the same 80-byte case is now 0.0004s, and 2000 bytes takes
  0.0096s. Behaviour is unchanged: the new engine is verified to return the
  same booleans *and* the same matched substrings as the old one across the
  supported syntax, and `matches_backtracking`/`find_backtracking` are
  retained so that comparison has something to compare against.

- **`if` and `match do` now treat their branches as mutually exclusive for
  linear values, the way `match` arms already did.** Consuming the same
  linear or affine value once in each branch is legal (at most one branch
  runs), but only `match` implemented the rule; `if`/`else` and
  `match do cond ->` checked their branches against one shared use-flag, so
  the second branch saw the first's consumption and reported a spurious
  "used more than once". This was most visible with session-typed channels,
  where branching on a protocol decision (`Chan.choose` in each arm) is the
  normal shape. A value consumed in the CONDITION still counts on every path,
  so a real double-use is unaffected.
- **A record field passed to a refined parameter is now checked instead of
  silently skipped.** `takepos(a.rem)` reflected the field access through a
  resolver that always declined, so the obligation came out "unreflectable"
  and, since March reports only definite failures, was accepted in silence;
  the workaround was to bind the field to a local first. The guard and the
  goal now meet on the same symbol, so `if a.rem >= 0 do takepos(a.rem)`
  proves, while an unguarded call, or one guarded on a *sibling* field, is
  still reported.
- **`match cond do true -> … false -> … end` now establishes the same path
  facts as the equivalent `if`.** Match narrowing fired only for
  constructor patterns over a variable scrutinee, so a Bool-literal arm
  contributed no facts and an obligation the `if` spelling discharges came
  back solver-undecided. The `true` arm learns the scrutinee is true, the
  `false` arm (and a `_` fallback after a Bool-literal arm) learns its
  negation. An earlier arm containing a guard still licenses no facts.

### Changed

- **BREAKING: a program that performs IO must declare the grant it performs
  it under.** `fn main()` with no capability parameter is now granted
  *no authority*, so reaching any capability from it is a compile error naming the
  exact grant the program needs; previously a parameterless `main` was
  ambient and could do anything. This is what makes "a March program cannot
  perform IO without declaring its authority" true rather than
  aspirational; before it, the accurate claim was only "a program that *states*
  its grant cannot exceed it".
  A `main` that performs no IO is unaffected. Migration is one line and you do
  not have to write it: the error prints the exact signature, and contains a
  machine-applicable fix, so `forge fix` rewrites `fn main()` into
  `fn main(_cap_console : Cap(IO.Console))` for you. The grant is not a
  suggestion: it is the set of capabilities the compiler already proved the
  program reaches. (Sandbox ladder R1 stage D.)
- **`main` may now hold several capabilities**, e.g.
  `fn main(cap_console : Cap(IO.Console), cap_spawn : Cap(IO.Spawn))`; the
  grant is their union. Previously it could hold exactly one, so a program
  needing two narrow capabilities had to widen to `Cap(IO)`. Shipped
  alongside the change above intentionally: without it, requiring a grant
  would have pushed roughly a third of real programs to the root capability
  and earned a weaker guarantee than the ambient default it replaced.
  Relatedly, `IO.Foreign` under a narrow grant is now an error only when the
  grant does not cover it: an explicit `Cap(IO.Foreign)` parameter is an
  accurate grant of the unbounded thing.

### Added

- **`let* p = e1; e2`: generalized monadic-bind sugar.** Generalizes `let?`
  (propagation for `Result` only) to any type `M` with a same-named module
  exporting `flat_map(x : M(a), f : a -> M(b)) : M(b)`; works today with
  `Option`, `Result`, and `List`, and with any user-defined type following
  the same convention:
  ```march
  fn compute(a : Int, b : Int, c : Int) : Option(Int) do
    let* x = safe_div(a, b)
    let* y = safe_div(x, c)
    Some(y + 1)
  end
  ```
  A type with no matching `flat_map` is a clear compile error naming
  exactly what's missing, not a crash. Known gap: `stdlib/parse.march`'s
  `Parser` type lives in a module named `Parse`, not `Parser`, so `let*`
  doesn't (yet) work with it; logged as a follow-up. See
  `specs/lang/let-star-generalized-bind.md`.
- **`Bytes.to_u8_arr` / `Bytes.from_u8_arr`**: an O(n)-copy bridge between
  `Bytes` and `NativeU8Arr`, so byte data from files, sockets, or
  `Bytes.from_hex` can reach the SIMD byte scanner (`Simd.load_u8x16` /
  `eq_u8x16` / `first_set_u8x16`), previously reachable only from
  hand-built `NativeU8Arr` literals. High bytes (0x80-0xFF) round-trip as
  128-255, never negative.
- **`NativeArray.fold_int` / `fold_float` now work under `--compile`, and
  `NativeArray.fold_f32` / `fold_i32` / `fold_u8` are new**: `fold_int` and
  `fold_float` previously typechecked and evaluated interpreted only; a
  compiled program calling either failed to link (no C runtime symbol). All
  five widths now fold via a `call_closure_2`-based loop mirroring
  `TypedArray.fold`'s RC discipline. Also fixes a memory leak this same
  change introduced during development and caught before merge: the
  generic accumulator crossing the closure boundary needed the compiled
  call site to box/tag a literal initial value (e.g. `fold_int(arr, 3, ...)`)
  the same way `RingBuf.push` already does for its erased element, and the
  float-family fold helpers needed to release the per-element box they allocate
  each iteration (confirmed safe, not a use-after-free, by inspecting the
  compiled closure's `-emit-llvm` output, which always allocates a fresh box
  when storing an element rather than aliasing the one passed in); that
  release is pinned by `test/native/native_arr_fold_leak_probe.march`, a
  live-object-count guard, since an output diff cannot see a leak.
  **A second, separate leak remains open:** `fold_float` / `fold_f32` with a
  `Float` **accumulator** leak a further ~32 B per element, because each
  iteration's accumulator box is never released: 5M elements cost 193.6 MB
  of peak RSS against 40.4 MB for the `fold_int` control. Results are
  correct; only memory residency is affected, and fold calls with an `Int`
  accumulator (`fold_int`/`fold_i32`/`fold_u8`) are unaffected. The bug is
  inherited from `TypedArray.fold`, not new to these helpers. See
  `docs/simd-vectorization.md`'s "Known limitations" and
  `specs/todos/2026-08-13-native-array-fold-accumulator-chain-leak.md`.
- **Runtime enforcement tests for `--cap-sandbox`**: compiled fixtures now
  verify that a withheld capability's syscall is actually denied at runtime
  (Linux seccomp-bpf, macOS Seatbelt), not just that the embedded policy
  strings agree between builders.
- **Exponential supervisor restart backoff with jitter (runtime-internal)**:
  a supervised child that crashes repeatedly no longer gets respawned
  immediately every time: from the second consecutive crash of the same
  child slot onward, the restart is delayed by
  `25 << min(streak-1, 7)` ms: 50, 100, 200, ... capped at 3200ms
  pre-jitter (the shift saturates at 7), `±25%` jitter on top (observed
  max ~4000ms) (streak resets once
  the child lasts a full `supervisor_window_secs` window), running on a
  dedicated green thread so the crashing actor's own scheduler thread is
  never blocked. The first crash of a slot still restarts synchronously
  with zero delay, matching prior behavior exactly. `MARCH_SUP_TRACE=1`
  prints `march: supervisor backoff child=<idx> streak=<n> delay_ms=<d>` to
  stderr for observability. Also fixes a related scheduler gap:
  `march_sched_wait_idle` (`run_until_idle()`) could return "idle" while a
  green thread was still waiting on a real timer (only actor-mailbox waits
  were recognized as busy), which the new delayed-restart thread exposed.
- **Bounded actor mailboxes with overflow policies (runtime-internal)**:
  `march_sched_set_mbox_limit(proc, limit, policy)` caps a process's mailbox
  at `limit` messages under `MARCH_MBOX_DROP_NEW` (reject the incoming
  message) or `MARCH_MBOX_DROP_OLD` (evict the oldest queued message); the
  default remains `MARCH_MBOX_UNBOUNDED` (`limit == 0`), so no existing
  program's behavior changes. `march_sched_send` now returns
  `MARCH_SEND_OK`/`MARCH_SEND_DEAD`/`MARCH_SEND_DROPPED` instead of a bare
  0/-1; every dropped message bumps `MARCH_STAT_MSGS_DROPPED` (visible via
  `Scheduler.dropped_messages()`, Task 6) and is given to a disposer hook
  registered via `march_sched_set_msg_dtor` (a real March-value dtor lands in
  Task 14; until then dropped messages are leaked-with-count).
  `MARCH_MBOX_BLOCK` (Task 8) parks a green-thread sender until the target's
  mailbox drains below the low-water mark (`limit/2`), guaranteeing delivery
  (`MARCH_SEND_OK`) unless the target dies while blocked (`MARCH_SEND_DEAD`);
  a foreign-thread sender sleep-polls instead of parking. No stdlib/language
  surface yet; this is the C substrate a later task will expose.
- **`Actor.set_queue_limit(pid, limit, policy)`**: the March-facing surface
  for bounded mailboxes: bind a mailbox capacity and overflow policy
  (`0` unbounded, `1` drop_new, `2` drop_old, `3` block_sender) to a running
  actor. Backed by a new `actor_set_mailbox_limit` builtin and the
  `march_actor_set_mbox_limit` runtime bridge (pid → green thread →
  `march_sched_set_mbox_limit`); dropped messages are counted in
  `Scheduler.dropped_messages()`. The interpreter supports drop_new/drop_old
  at its own mailbox enqueue point but treats block (`3`) as unbounded: its
  single-threaded eager scheduler cannot park a sender without deadlocking.
  Under a drop policy, a dropped `Actor.call` request or reply looks
  the same as a lost reply at the caller (surfaces as a timeout);
  callers relying on `Actor.call` against a bounded actor should prefer the
  block policy.
- **`Scheduler` stdlib module + `sched_stat` builtin**: runtime observability
  for the actor/task scheduler: `Scheduler.live_procs()`, `total_spawned()`,
  `runq_depth()`, `dropped_messages()`, and a raw `stat(i : Int) : Int`
  escape hatch. Backed by `march_sched_stat(which)` in the C runtime, which
  reads `g_live_procs`/`g_next_pid`/a new `g_runq_len` counter/the Task 2
  timer heap length directly; indices 3-5 (stack-alloc failures, dropped
  messages, recycled stacks) are reserved for later tasks and read 0 until
  wired up. This is the load-shedding substrate: a supervisor or ingress
  actor can poll these counters to decide when to shed. The interpreter
  reports the subset meaningful without the C scheduler (live/spawned actor
  counts); unknown indices read 0 on both backends.
- Scheduler timers: green threads can park with a deadline (runtime-internal;
  enables Actor.call deadline waits and supervisor backoff).
- **Capability grants now compose per function, not just per program.**
  Any function that takes a concrete capability parameter is checked against
  it: `fn log(cap : Cap(IO.Console), msg : String)` may reach no capability beyond
  the console, transitively, through helpers and the stdlib alike; and,
  unlike the whole-program grant, it is checked wherever the function is
  declared, so a library's bound applies without the application opting in.
  Rows are inferred; no annotation is written in source and no printed type
  changes. A higher-order function that invokes a callback it was GIVEN still
  certifies (the supplier of the callback is charged for it), while a
  function that invokes a value with no traceable origin is turned down under a
  narrow grant rather than certified, the same stance already taken on
  `IO.Foreign`. Violations name the chain that reaches the capability.
  (Sandbox ladder R1 stage C.)
- **New `Simd` module: explicit 128-bit SIMD vector types `F32x4`,
  `F64x2`, `I32x4`, `I64x2`, `U8x16`**, with 127 lane-wise operations
  (splat/make/extract/replace/load/store, compare/bitwise/select/scan,
  plus arithmetic on the float and int families: add/sub/mul/(div for
  floats)/min/max/(fma/sqrt for floats)/(shl/shr for ints)/sum/hmin/hmax)
  via `Simd.<op>_<type>`, e.g. `Simd.add_f32x4`, `Simd.load_u8x16`. Lane
  get/set indices are refinement-typed to the type's lane count, and an
  index the refinement checker cannot decide is bounds-checked at run time
  (`load`/`store` against the array length, `extract`/`replace` against the
  lane count) rather than silently producing garbage. `select`, `any`,
  `all`, and `first_set` all read a lane's **high bit**, identically
  interpreted and compiled: the canonical all-ones masks `eq`/`lt`/`gt`
  produce are unaffected; a hand-rolled non-canonical mask follows the
  high-bit rule.
  `F32x4`/`F64x2` arithmetic is bit-exact single/double precision (verified
  against the true-f32-vs-double-then-round distinction) and `fma` is a
  true fused multiply-add on both paths, interpreted and compiled (see the
  Fixed entry below for the single-rounding fix this required);
  `min`/`max`/`hmin`/`hmax` on floats use minNum/maxNum
  semantics; integer arithmetic wraps mod 2^w. Each type implements
  `Show`/`Eq`/`Hash` (lane-wise; a NaN lane is unequal to itself, matching
  IEEE 754). Width is fixed at 128 bits on every target: identical
  semantics everywhere, a stable interpreter/native parity surface, and a
  NEON/SSE2/WASM-SIMD baseline that every target it runs on supports without
  runtime feature detection; a portable/scalable width is a possible future
  layer on top, not a redesign of this one.

  `--compile` lowers every op, including `load`/`store` (bounds-checked,
  with an FBIP copy-on-write store matching `NativeArray`'s in-place-vs-copy
  contract), to native LLVM vector instructions/intrinsics, and a straight-
  line kernel or a self-tail-recursive accumulator loop keeps the vector in
  a register for the whole loop body (zero `march_simd_alloc` calls,
  confirmed via `--emit-llvm` and pinned by fixtures). On a 16MB `u8`
  delimiter scan this measured **~11.5x** faster than a scalar March byte
  loop; holding the loop shape constant, a `Simd` accumulator loop measured
  **4.0x** faster than the equivalent scalar-element March loop. That said,
  for a simple elementwise-then-reduce shape, composing `NativeArray`'s
  `map2_f32` + `sum_f32` (2.55 ms at N=5M) currently beats a hand-written
  `Simd` accumulator loop for the same computation (10.0 ms, ~3.9x): the gap is
  general March index-loop overhead (per-iteration preemption check, a
  stack save/restore, RC bookkeeping, an unhoisted length call; tracked in
  `specs/todos/2026-08-11-march-index-loop-per-iteration-overhead.md`), not
  a cost of SIMD itself. Use `NativeArray.map`/`map2`/`sum` for simple
  elementwise pipelines; reach for `Simd` when you need cross-lane structure
  (scanning, masks, `select`, or a fused multi-op kernel) or byte-level
  scanning specifically. `DataFrame`'s `Min`/`Max` intentionally stayed on
  the existing C reduction rather than migrating to `Simd`: a probe measured
  it ~8.2x slower, for the same index-loop-overhead reason, plus the 2-lane
  width of `i64x2`/`f64x2` caps the limit even after that overhead is
  fixed (see `bench/RESULTS.md`'s simd-kernels section).

  Known limitations: mutual-recursion accumulator groups still box the
  vector on every call (correct, just not accelerated; see the Fixed entry
  below for the self-tail-recursive case, which *is* accelerated and does
  not have this box; pinned by `test/native/simd_mutual_tco.march`);
  `i64x2` lane values beyond ±2^62 lose their top bit
  under the **interpreter only** (OCaml's 63-bit boxed int), a parity edge
  confined to that range; and `==`/`show` under a polymorphic/erased-type-
  variable context fall back to the generic runtime helpers rather than the
  static `Eq`/`Show` impl (lane-wise comparison, NaN lanes unequal), the
  same caveat `NativeArray` already has. The `Simd` module is not supported
  on the JavaScript target (fixed 128-bit SIMD has no JS lowering);
  compiling a `Simd.*` call with `--target js` now fails with a message
  naming the builtin, rather than emitting a call that throws
  `ReferenceError` at runtime.
- **`NativeArray` gained narrow element widths: f32, i32, u8**, both
  interpreted and compiled (`--compile`), with `NativeF32Arr`/`NativeI32Arr`/
  `NativeU8Arr`, e.g. `NativeArray.make_u8`/`set_i32`/`sum_f32`/`map2_i32`,
  plus 8 conversions like `NativeArray.int_to_u8_arr`. Integer stores wrap mod
  2^w two's-complement, float stores round to nearest-even binary32, and
  loads widen exactly; operations never trap. `map_f32`/`map2_f32`/`sum_f32`
  get the same inline-loop vectorization treatment as the existing f64 path
  (confirmed `<4 x float>` NEON codegen); halving the element width to f32
  measured ~2.0-2.4x faster than f64 at N=5M (sum 0.49ms vs 1.19ms, map
  2.27ms vs 4.54ms, map2 2.67ms vs 6.40ms; see `bench/RESULTS.md`).
  `fold_i32`/`fold_u8`/`fold_f32` do not exist yet (interpreted or compiled);
  they'll be added once the existing `fold_int`/`fold_float` compiled-
  linkage gap closes.
- **`main`'s capability parameter is now the program's grant: the first
  check that answers no rather than "declare it".**
  `fn main(cap : Cap(IO.Console))` makes a machine-checked claim: the whole
  program (every helper, stdlib call, and dependency `main` reaches)
  touches no capability beyond the console, and a truthful `needs` manifest does
  not raise that limit. A parameterless `main` stays ambient (no existing
  program breaks); `Cap(IO)` is the full grant, as before. `IO.Foreign` is
  an error under any narrow grant, since linked C cannot be bounded by the
  lattice. The violation error names the capability and a
  reachable-from-`main` function that uses it. Enforced identically by
  `march --check`, the interpreter, and the compiler. (Sandbox ladder R1
  stages A+B; per-function grants are future work.)
- **`peak_rss_bytes` builtin**: process self-inspection returning peak
  resident set size in bytes on both macOS and Linux (`getrusage`'s
  `ru_maxrss` is bytes on macOS, kilobytes on Linux; normalized to bytes at
  the C boundary). **Compiled builds only** report a true RSS: the
  interpreter has no `getrusage` binding and returns a `Gc.quick_stat`
  `top_heap_words` approximation of the *interpreter's own* OCaml heap, which
  is not comparable in magnitude to the compiled figure. Only the ordering
  (a later call >= an earlier one) agrees across the two paths; never assert
  equal raw numbers. Ambient, no capability grant required: it performs no
  IO and observes no state outside the process. `System.mem_peak_bytes()` is
  the stdlib wrapper (named to avoid shadowing the builtin it calls). The
  SIMD-vector-temp-box leak guard (`test/native/simd_leak_probe.march`,
  `test/dune`) now uses it to measure its own RSS from inside the process,
  replacing a Darwin-only `/usr/bin/time -l` check; the guard runs on both
  CI legs for the first time.
- **FFI extern binding a C symbol the runtime preamble already declares no
  longer fails to compile.** An `extern` with a C name matching a preamble
  declare (e.g. `fn live_allocs(): Int = "march_live_allocs"`) emitted a
  second `declare` for the same symbol, which LLVM rejects entirely as
  `invalid redefinition of function`: the whole module failed to build. The
  extern's declare is now suppressed when the preamble already emitted one.
  The skip set is computed from the preamble text actually emitted for the
  current target, so a native-only symbol is still declared normally when
  compiling to WASM. Surfaced by adding `live_allocs` as a builtin, which
  moved `march_live_allocs` into the preamble while `test/native/ffi_leak.march`
  and `ffi_resource.march` were already binding it as an extern.
- **`live_allocs` builtin**: process self-inspection returning the net count
  of live March heap objects (every `march_alloc` increments, every
  free-on-refcount-zero decrements; an always-on relaxed atomic, not gated
  behind a stats flag). Like `peak_rss_bytes` it is ambient and needs no
  capability grant: it reads one process-local counter and observes no state
  outside the process. **Compiled builds only** report a real count: the
  tree-walking interpreter allocates no March heap objects at all (its values
  are OCaml values under the OCaml GC), so it returns a constant `0` rather
  than an approximation that could be mistaken for a measurement; never
  assert on it from an interpreted test. Because a leak is exactly "allocated
  and never freed", this measures leaks directly and exactly, with no
  allocator, page-rounding, or OS-baseline noise, which makes it portable
  where an absolute RSS threshold is not. The fold per-element-float-box leak
  guard (`test/native/native_arr_fold_leak_probe.march`, `test/dune`) now
  gates on it instead of peak RSS, after the RSS band, calibrated on macOS,
  reported a false leak on CI's Linux leg, where the process baseline by itself
  is ~122 MB.

### Documentation

- **Capability enforcement assurance-tier table, and an OS-primitive-by-capability
  reference, added to the Capabilities and Capability Enforcement pages.** A
  quick-reference table (type system → `forge cap inspect` → `--cap-sandbox` →
  `forge cap run` → `forge cap run --allow-only`) makes the assurance/effort
  tradeoff legible at a glance, backed by a full capability-to-OS-primitive
  mapping for both `--cap-sandbox` (seccomp-bpf/Seatbelt) and `forge cap run`
  (bubblewrap/sandbox-exec). Also documents two platform asymmetries verified
  against real running binaries: macOS's `IO.Network` gates `bind`/`connect`
  but not `socket()` creation, and macOS's `IO.Process` gates `fork` but not
  `exec`; both differ from Linux, which is stricter on each.

### Changed

- **Mailbox node allocation moved outside the mbox spinlock.** `march_sched_send`
  now allocates the mailbox node before acquiring the lock and reuses it across
  retry loops (BLOCK policy), reducing contention on the spinlock hot path.
  Nodes are freed on paths that do not enqueue (early DEAD return, DROP_NEW
  policy, dead-during-registration race), matching mbox_pop's existing free
  discipline.
- **The structural-recursion warning no longer prescribes an accumulator for
  constructor-wrapped recursion.** For a body like `Succ(bump(k))`, TRMC
  compiles the recursion into a loop, so the old "uses O(depth) stack space"
  phrasing was misleading. The warning now states the stack cost *may* apply and
  that a recursive call in direct constructor-argument position becomes a loop.
  The arithmetic variant (`1 + f(n - 1)`), which TRMC cannot transform, still
  recommends an accumulator parameter. Detection is unchanged.
- **The capability limit is now on by default.** `march --compile` fails the
  build if any module's emitted code uses a capability that module does not
  declare in `needs`, including a stdlib-mediated use (`File.read`), which no
  other check sees, and including dependencies that never opted in.
  `--no-cap-strict` opts out; `--cap-strict` is still accepted as an explicit
  spelling of the default. **This is a breaking change** for code written
  before it: the fix is one `needs` line per named module, and the error names
  the module and the capability.
- **`march_send`/`Actor.call`/`mailbox_size` no longer take the global
  actor-table mutex on their hot path.** The actor-table hash chain is never
  unlinked or freed (metas live for the process lifetime), so `find_meta`
  now walks it lock-free (acquire-loading the bucket head and following
  `tbl_next`, paired with a release-store publish at insertion) instead of
  holding `g_tbl_mu` for the lookup. Combined with the `green_thread`
  atomicity fix above, per-message sends no longer contend with concurrent
  spawns/lookups on other actors.
- **`find_meta_by_pid_index` (supervisor-restart Pid→actor lookup) is now
  O(1) instead of O(total actors spawned so far).** A new insert-only
  `pid_index -> meta` side table (same lock-free-read discipline as the
  actor-pointer table above) replaces the old full scan of every actor-table
  bucket taken under the global table lock. Also closes a pre-existing,
  formally-racy plain (non-atomic, unlocked) write to `meta->pid_index` in
  `march_spawn` against unsynchronized cross-thread reads in
  `march_get_cap`, `march_send_checked`, and Pid `Show` formatting:
  `pid_index` is now `_Atomic`. The new side table correctly handles
  actor heap-address reuse (a dead actor's freed address given to a new
  actor, likely under kill/respawn churn): `march_spawn` detects when
  `find_or_create_meta` returned an already-linked (stale) meta and
  allocates a fresh one for the new incarnation rather than re-linking the
  stale one, which would have corrupted the insert-only side table's
  chains.

### Fixed

- **`Simd.fma_f32x4` now gives the same answer interpreted and compiled.** The
  compiled path emits `llvm.fma.v4f32` (one binary32 rounding) while the
  interpreter computed a binary64 fused multiply-add and then narrowed it, two
  roundings, which really did differ in the last ulp: about 1 random binary32
  triple in 20 million, and *systematically* whenever `a * b` lands exactly on
  a binary32 midpoint (e.g. `24929.0 * 673.0 = 2^24 + 1` with any tiny positive
  `c`, where the compiled path gave `16777218` and the interpreter `16777216`).
  The interpreter now emulates a real single-rounded binary32 fused
  multiply-add, so both backends run the same operation by construction. Boundary
  triples are pinned as tests and the two paths are fuzzed against each other
  over 400,000 boundary-heavy lanes.
- **Calling a SIMD kernel no longer leaks 32 bytes per call.** A
  self-tail-recursive function with a SIMD-vector parameter keeps that
  parameter in a native vector register, so the compiler boxes the argument at
  the call site and unboxes it once on entry, and no code released that
  box. One 32-byte cell leaked per *invocation*, unbounded: a server calling a
  vector kernel per request grew without limit (measured 64 MB over 2,000,000
  calls; now 2.7 MB, guarded by an RSS assertion in the test suite). The call
  site now releases the box it created, but only for callees where analysis
  shows the entry prologue cannot retain it. Vector arguments to any other function
  (where the callee may store the vector into a list, record, or closure that
  then owns it) are intentionally left untouched; those shapes still leak one box
  per call and are tracked separately.
- **Compiled `to_string(x)` inside a generic function printed `#<tag:N>`
  garbage for non-primitive `x` (Lists, records, user ADTs) instead of the
  real value**, diverging from the interpreter. `to_string` on a concretely-
  typed argument already dispatched to the matching `Show` implementation;
  a `to_string` call inside a still-generic function (argument type an
  unresolved type variable at that function's own lowering time) stayed a
  bare runtime fallback that only understands a handful of primitive
  representations, and was never revisited once monomorphization later
  specialized the function to a concrete type. Hit any generic helper where the
  body called `to_string` on its parameter, most visibly
  `examples/csv_example.march`'s per-row callback.
- **Killing (or crashing) a busy actor no longer leaks its queued mailbox.**
  Undelivered messages sitting in a dead process's mailbox were never
  disposed: `sched_loop`'s `PROC_DEAD` reap branch freed the mailbox
  *nodes* but not the message payloads they pointed at, so every message
  still in flight to an actor that crashed before receiving it leaked for the
  life of the program. The reap branch now drains the mailbox and disposes
  each message via the same disposer hook Task 7 introduced for
  overflow-dropped messages (`march_sched_set_msg_dtor`); the runtime
  registers a real dtor (`free()` for the malloc'd hot-reload migrate
  message, `march_decrc` for everything else) at scheduler init. To keep
  this safe under a dtor that itself calls back into the scheduler (e.g. an
  FFI resource cleanup that sends a message), both this reap-time drain and
  `MARCH_MBOX_DROP_OLD`'s existing evicted-message dispose now collect the
  message(s) under the mailbox lock and only invoke the dtor after releasing
  it; `march_sched_set_msg_dtor`'s contract now states explicitly that the
  dtor may re-enter scheduler send/recv paths and is never called with any
  scheduler lock held.
- **Supervisor restart-budget windows are now immune to wall-clock steps.**
  `march_restart_budget_ok` timestamped each restart with `gettimeofday`
  (wall-clock), so an NTP correction or manual clock change could jump the
  window backward (restart budget never refills) or forward (recent
  restarts silently age out of the window early, letting a crash loop
  through the budget meant to stop it). It now uses `march_now_ms()`
  (`CLOCK_MONOTONIC`), which cannot be stepped by wall-clock adjustments.
- **The process registry no longer has a fixed 65536-pid lifetime cliff, and
  a green thread that fails to spawn now warns visibly instead of dropping
  an actor's messages silently.** `march_sched_find`, `wake_idle_daemons`,
  and `march_sched_wait_idle` used a fixed-size `g_proc_registry[65536]`
  array: once a program had spawned 65536 procs (over its lifetime, not
  concurrently), any later pid silently fell off the registry: `find`
  returned `NULL` for a live proc, and the idle-detection walkers never saw
  it, so `wait_idle`/daemon-wake logic could go blind for long-running or
  high-churn programs. The registry is now a single header-prefixed
  allocation behind one atomic pointer (`{cap; slots[cap]}`) that doubles
  under a lock when a pid outgrows it; unlocked readers (`march_sched_find`
  and the `MARCH_DEBUG` SIGSEGV-handler stack walker, which runs in signal
  context and cannot take a lock) load the pointer once and bound every
  access by that snapshot's own embedded `cap`, so a growth racing a reader
  is safe: the reader just doesn't see the newest pids yet. Old arrays are
  intentionally leaked on growth (same discipline as retired procs), and
  since capacity doubles, growth produces O(log N) leaked arrays total, not
  one per pid. A failed growth allocation now aborts with a visible
  `march_sched: out of memory (registry alloc)` message instead of the old
  fixed-size array's silent pid-lifetime cliff. Separately, `march_spawn`
  now emits a one-shot stderr warning (pointing at `Scheduler.stat(3)`) when
  the green thread's stack allocation or `getcontext` fails, instead of
  silently returning an actor that drops
  every message sent to it; both failure paths now also bump
  `MARCH_STAT_STACK_FAIL`.
- **A burst of >4096 spawns or yields from one scheduler thread silently
  dropped runnable green threads (local-deque overflow); spawn-churn
  workloads no longer deadlock.** `march_deque_push`'s bounded-capacity
  return value (-1 when the owner's Chase-Lev local deque is at
  `MARCH_DEQUE_CAPACITY`, 4096) was ignored at both call sites in
  `march_scheduler.c` (spawn-from-scheduler-thread, and the yield-repush
  path); the dropped proc stayed `RUNNABLE` and counted in `g_live_procs`
  but was never queued anywhere, so it was never dispatched and the
  scheduler could never reach quiescence: every worker thread eventually
  idle-parks indefinitely. Both sites now overflow to the (unbounded) global
  run queue instead of dropping the proc.
- **Dead green-thread stacks are recycled instead of leaked; spawn-churn
  workloads no longer exhaust address space.** Every dead proc used to leak
  its ~1MiB+guard mmap stack reservation indefinitely; dying procs now return
  their reservation to a free-list that new spawns draw from first, capping
  live reservations near the concurrency level instead of growing 1:1 with
  total-procs-ever-spawned. Disabled under ASan builds (which keep leaking,
  as before) since ASan's fake-stack fiber tracking assumes a stack address
  range is never reused by a different fiber.
- **An actor's `green_thread` field was written at spawn without holding the
  actor-table lock, racing any concurrent reader (`march_send`,
  `march_actor_call`, `mailbox_size`, `set_mbox_limit`).** The field is now
  `_Atomic`, written with a release store at spawn and at green-thread exit,
  and read with an acquire load everywhere, closing a pre-existing data
  race rather than introducing a new lock.
- **`mailbox_size` on compiled binaries returned only the monitor Down
  count, not the actual mailbox depth; the two backends now agree.**
- Actor.call with a timeout no longer busy-polls the scheduler while
  waiting: N pending callers no longer steal CPU from the actor they are
  waiting on.
- **A late reply from a timed-out `Actor.call` could be delivered as the
  answer to a later, unrelated call on the same green thread.** Replies are
  now wrapped in a runtime envelope containing the correlation id of the call
  they belong to; a reply with an id that doesn't match the call currently waiting
  is discarded instead of being given back as that call's result.
- **String literals now carry their full source span.** A string literal's AST
  span collapsed to a single column (the closing quote), so anything that
  sliced source text by span got a lone `"` back whenever the expression was
  or contained a string. `forge refactor bundle` hit this (rewriting
  `f("x", 1)` produced a corrupted `a = "`), and diagnostics pointing at a
  string literal underlined just the quote. The lexer hands off from the main
  token rule to a recursive `read_string` sub-rule, and each re-entry reset
  ocamllex's lexeme start; the opening position is now recorded on handoff and
  restored when the token is produced, for plain and triple-quoted literals
  and for interpolation starts.

- **Compiled `if`/`match` expressions returning `Float` no longer leak a heap
  box on every evaluation.** The result-merge path for case/match codegen
  boxes each branch's value into a uniform pointer slot; for `Float` branches
  this is a real heap allocation (`march_alloc_float`), and no code freed it
  after unboxing: any `if`/`match` producing a `Float`, called in a hot loop
  or recursive helper, leaked ~32 bytes per call (measured: a Float
  accumulator called 20M times peaked at ~645MB RSS instead of a flat
  ~1.9MB). Fixed for the case/match merge path; two related sites (closure/
  Task-trampoline float returns, apply-wrapper float params) remain open;
  see `specs/todos/2026-08-12-float-boxing-trampoline-apply-wrapper-leak.md`.
- **Compiled `==` on a variant/tuple/record field of a type with no `type`
  declaration now compares by content, not by pointer.** A ctor field typed
  as a compiler-builtin type constructor (e.g. `Task`, `Pid`, `WorkPool`),
  or, on branches containing SIMD vector types, `F32x4`/`F64x2`/`I32x4`/
  `I64x2`/`U8x16`, has no derivable structural-equality function, and the
  codegen fell back to raw pointer identity instead of the runtime
  polymorphic comparator, so two distinct-but-content-identical values for
  such a field compared unequal. Now falls back to `march_poly_eq`, matching
  the existing generic (`TVar`) field arm.

- **Compiled `!=` on NaN floats now matches the interpreter.** The native
  backend lowered float `!=` to LLVM `fcmp one` (ordered-and-not-equal),
  which per IEEE 754 is `false` whenever either operand is NaN, but the
  interpreter implements `!=` via OCaml's polymorphic `<>`, under which
  `nan <> nan` is `true`. `nan != nan` printed `false` compiled and `true`
  interpreted. Now uses `fcmp une` (unordered-or-not-equal), matching `<>`
  semantics on both backends.

- **JS backend: `==`/`!=` on a non-primitive operand now compares
  by structure.** A bare `==`/`!=` where either side is an ADT/tuple/record
  (or an erased type variable that may hold one) lowered to JavaScript `===`,
  i.e. reference equality, so `x == Some(Ctor)` on two distinct-but-equal heap
  values was always `false`. Such comparisons now go through a deep structural
  equality helper (matching the native backend); primitive-vs-primitive
  comparisons still use fast `===`/`!==`.
- **JS backend: a multi-head function with a literal-integer argument pattern
  no longer infinite-loops.** `fn f(xs, 0) … / fn f(xs, n) …` compiled with
  `--target js` emitted a `switch` on a value with a tag of `undefined`, so the
  base case was dead and the function recursed indefinitely. The literal-tag case
  now lowers the same way the native backend does.
- **Scheduler busy-spins back off instead of pegging a core.** Three
  unbounded scheduler spin-waits (`march_sched_wake`'s parked-process wait,
  `task_wait_done`'s in-scheduler branch, and `march_sched_wait_idle`) now spin
  briefly and then sleep, so a stalled wait under heavy host oversubscription no
  longer keeps a CPU at ~100%. Wait-forever semantics are unchanged.
- **A function or `let` named after a capability-bearing builtin (`file_read`,
  `random_bytes`, `dns_resolve`, …) no longer falsely requires that
  capability.** Every capability scan matched a call by NAME only, with no
  awareness that a module-level declaration shadows a builtin of the same
  name; and shadowing wins real name resolution, so the program never
  touched the capability it was accused of needing. Since the capability
  limit's severity flip this was a hard, default-on compile error with no
  workaround short of renaming the function; it is now silent, and an
  actual (unshadowed) builtin call is still caught correctly. The inferred
  capability set (`march caps`, feeding `forge audit --inferred` and the
  `--cap-sandbox` profile) had the identical bug in the opposite direction
  (silently over-reporting a capability never used), also fixed.
- **A missing-capability violation no longer prints two overlapping
  diagnostics at the same source location.** Both the typechecker's own
  `needs`-coverage check and the separate capability-inference pass anchor
  at the exact call site and were repeating each other's "add `needs X`"
  sentence almost verbatim. The hint now shows only what the error doesn't
  already say (the call chain from `main` down to the offending call) and
  is omitted entirely when there is no chain to show (a library with no
  `main`, or a violation already inside `main`).

- **A natively compiled program opening a nonexistent file no longer misreads
  the error value's representation.** `file_open`'s `Err` case is typed
  `Result(Int, FileError)`, and the interpreter builds a real `FileError` ADT
  value (`NotFound(path)`, `Permission(path)`, `IoError(msg)`), but the
  compiled runtime's `march_file_open` returned a bare string pointer instead
  of a tagged `FileError` cell: compiled code matching or inspecting the
  `Err` payload would read a string header as if it were an ADT cell. Fixed
  by building a real, correctly-tagged `FileError` cell in the C runtime.
- **A bare `from_json` call with a single `derive Json` in scope now compiles
  natively.** `from_json` dispatches on its result type (its argument is
  always a `JsonValue`), which monomorphization's first-argument interface
  dispatch could never resolve: a minimal `derive Json for T` +
  `from_json(v)` program failed to link with `Undefined symbols: _from_json`.
  When exactly one implementation exists and its parameter type matches the
  call's argument type, the call is unambiguous and now resolves to it.
- **An unresolvable interface-method call (e.g. bare `from_json` with several
  `derive Json` in the same module) is now a clean compile error instead of an
  internal compiler error or a linker error.** `--compile` on such a program
  (e.g. `test/stdlib/test_json_typed.march`) previously crashed with an ICE
  (exit 3) or a raw `_from_json` linker failure; it now reports "ambiguous
  interface-method call", names the candidate implementations, explains that
  the dispatch position is not concrete at the call site, and exits 1.

- **An `impl` method that performs IO no longer trips the capability limit
  with an unfixable synthetic module name.** Attribution derived the owner of
  `Save$Thing.persist` from the name and reported `module `Save$Thing` uses
  `IO.FileWrite``, a "module" no `needs` line can declare for, so a
  correctly-declared program was rejected. The owner is now the module that
  declared the impl.

- **The `--cap-sandbox` profile now grants capabilities used from a
  module-level `let`, a nested module, or an `impl` method.** The grant set
  collected `fn` declarations only, so a program where the only write lived in
  one of those shapes embedded a pure program's profile and was denied at
  runtime by its own sandbox.

- **A nested module's capability use is now attributed to that module, not
  the program's entry module.** Two gaps compounded: an actor handler's
  synthesized function name is bare (`Weeble_Zorp`), and the prelude's
  wrappers (`println` et al.) are unwrapped into the entry module; both made
  attribution resolve the owner to the entry module, so `needs IO.Console` on
  the module that actually did the printing could not satisfy the capability
  limit, while a declaration on the entry module masked the true owner.
  Lowering now records each handler's declaring module, and attribution sees
  through prelude wrappers to the calling module.

- **The unused-capability warning no longer contradicts the capability
  limit.** A module reaching a capability only through a stdlib wrapper
  (`Parallel.pmap` → `IO.Spawn`) was told by the limit to add the `needs`
  line and then by the unused-`needs` warning to remove that same line, with
  an autofix that re-broke the build. The warning now consults the transitive
  capability closure (the same analysis import checking uses), so a
  stdlib-mediated use counts as a use. A `needs` that no code requires still
  warns.

- **The "cannot be attributed" limit error no longer claims a cause it
  cannot know.** It claimed the capability was "reached only through indirect
  calls", wrong in every diagnosed case to date. It now states what is known,
  and advises reporting the diagnostic if adding the `needs` line does not
  resolve it, since that indicates an attribution gap in the compiler.

- **A module with no entry point is no longer charged capability violations
  for the entire standard library.** A file with no `fn main` (a library, or a
  test-only file) drew up to 17 limit violations naming stdlib modules
  (`Socket` uses `IO.NetConnect`, …) that its code never reached: with no
  roots, dead-code elimination kept everything, and the limit read the
  unpruned result as "used". The limit now roots reachability at the
  functions the file itself declares. A main-less module that truly
  reaches a capability is still charged for it.

- **A capability appearing only in a type signature no longer trips the
  limit.** `fn main(cap : Cap(IO))`, the documented entry-point shape, was
  reported as "`IO` is used but cannot be attributed to any module", a
  violation no `needs` line could fix. Capabilities are erased, so a
  signature-only capability corresponds to no emitted operation; the limit
  now judges emitted code only. (`--cap-sandbox` still counts signature
  capabilities when building its profile, where receiving one by parameter
  rightly widens what the process may do.)
- **Nested `derive Json` types now compile natively.** Calling `to_json`/
  `from_json` on a record type that nests another `derive Json` record (e.g.
  `type Outer = {label: String, inner: Inner}`) previously failed to link
  (and, after the from_json fix above, failed with a spurious "ambiguous
  interface-method call") in the compiled/LLVM backend, even though the call
  was never actually ambiguous and worked fine interpreted. The compiler's
  record-to-type-name lookup used for interface dispatch now also indexes
  each record type's deep-normalized (fully structural) shape, not just its
  declared shape, so a record literal's fully structural type at the call
  site resolves correctly.

- **`try_finally` now has a native implementation, so compiled programs using
  fd-streaming file I/O link and run.** It was a typecheck+interpreter builtin
  only; any natively compiled program that reached it (`File.with_lines`,
  `File.with_chunks`, `Logger`'s context stack, or a direct call) failed at
  link time with `Undefined symbols: "_try_finally"` (first seen via
  `examples/read_file.march`). The native version preserves the interpreter's
  contract: cleanup runs even when the action panics (the panic is re-raised
  after cleanup; a panic inside cleanup itself is swallowed).

- **`file_read_line` / `file_read_chunk` no longer misread every compiled
  result.** The C runtime returned `Ok`/`Err` Result cells while the March
  type is `Option(String)` (niche-encoded: `None` is NULL, `Some`'s payload is
  the value itself), so a compiled read-to-EOF loop never saw EOF
  (`File.with_lines` spun indefinitely) and any use of the "line" crashed. Both now
  return the string directly or NULL, matching the interpreter. This was
  unreachable before the `try_finally` fix above; no fd-based program could link.

- **A bare constructor pattern on a value of a known type is no longer reported
  as ambiguous against a same-named stdlib constructor.** Matching `Defs.make(n)`
  (of type `Defs.Thing`) with a bare `Bar(_)` arm errored with "Constructor `Bar`
  is ambiguous between `Defs.Bar` / `Plot.Bar`" even though the scrutinee type
  uniquely identifies `Defs.Bar`: the resolver picked the right constructor but
  the ambiguity *diagnostic* was computed from the bare name only. The diagnostic
  now defers to a unique expected-type resolution; real ambiguity (an untyped
  scrutinee) still errors.

- **The runtime-object cache now invalidates when a system library's headers
  change even if their path does not.** A `brew upgrade openssl@3` (or a CI
  base-image bump) that left the `-I` path, `-D` defines and `clang --version`
  unchanged could serve a stale `.o`. The cache key now fingerprints the resolved
  `openssl`/`zlib`/`zstd`/`brotli`/`blake3` headers themselves.
- **`--cap-strict` no longer rejects correct programs that call `task_spawn`,
  `unix_time_ms`, `uuid_v7`, or the `Signal` builtins.** These are lowered
  through a trampoline rather than a named C symbol, and the capability
  limit looked them up by C symbol only, so `IO.Spawn`, `IO.Clock` and
  `IO.Signal` uses could not be charged to the calling module even when it
  declared them. The reported reason ("reached only through indirect calls")
  was itself wrong; the calls were direct. Attribution now consults the same
  March-name table the typechecker uses.

- **Actor messages can no longer carry a `NativeIntArr`/`NativeFloatArr` (the types
  backing the `NativeArray` stdlib module)**: the same "must be owned by a single
  actor" restriction `RingBuf` already had.

- **Actor messages can no longer carry a `RingBuf` (or other single-owner mutable-buffer
  type); this restriction was previously a no-op.** The check was invoked on a
  constructor application's overall type, which never varies by payload for an actor
  message; it now runs on the payload's own instantiated type at the moment the message
  is constructed, so it correctly applies through `send`, `send_checked`, `Actor.cast`,
  and `Actor.call` alike.

- **`~H` no longer emits two CSRF tokens when a form already interpolates one.**
  The desugar injects a hidden `_csrf_token` input after a mutating `<form>`
  whenever a `conn` binding is in scope. If the author also wrote
  `${CSRF.tag(conn)}`, both were emitted, silently, because `CSRF.tag` returns
  `IOList` and passes through unescaped. With `CSRF.tag_string`, which returns
  `String`, the contextual escaper treated it as untrusted text and rendered a
  visible chunk of escaped markup onto the page.

  Injection is now skipped for a form that already contains an explicit token,
  and a **warning** points out that the explicit call is redundant.

  Detection is scoped **per form**, not per template: a template with two forms
  where only one contains an explicit token keeps injection on the other. A
  template-wide check would have turned a cosmetic duplicate into an
  unprotected form.

- **Desugar diagnostics are labelled by their actual severity.** Both printers
  in `bin/main.ml` hardcoded `error:`, which was harmless only while the desugar
  emitted only errors. The warning above is the first exception, and a
  warning printed as `error:` misleads people and any tooling that greps the
  output. The exit decision is unchanged: it still keys off `has_errors`.

- **`~xml`, `~toml` and `~yaml` allowed an interpolated value to change the
  parsed structure; interpolation into them is now a compile error.** These
  sigils hand their handler a single already-concatenated string which the
  handler then *parses*, so a hole was spliced into the source text before
  parsing. Measured before the fix:

  ```march
  let evil = "</name><admin>true</admin><name>"
  ~xml"<user><name>${evil}</name></user>"
  -- <user><name/><admin>true</admin><name/></user>   3 children, not 1
  ```

  `~toml"name = \"${v}\""` and `~yaml"name: ${v}"` likewise injected entire new
  keys.

  `~H` is unaffected and keeps its interpolation: it must emit *text*, so it
  escapes per parse context. These sigils produce a *structure*, where the sound
  fix is supplying values as data rather than as source text (the
  parameterisation analogue), not a second family of escapers. YAML in
  particular cannot be made safe by escaping in any way worth trusting.

  Sigils without interpolation are unchanged. No breakage is known: across
  the compiler, bastion, forgepm, conduit, depot and march_doc there are six
  uses of these sigils, all in the compiler's own tests, and none with a hole.

- **`forge audit`, `forge licenses`, and `forge tree` now find git/registry
  dependencies that `forge deps` actually installed.** All three reimplemented
  their own dependency-directory lookup as `<project_root>/.march/cas/deps/<name>`,
  but `forge deps` installs git and registry dependencies under
  `$HOME/.march/cas/deps/<name>`, a global, cross-project location. A
  just-installed git or registry dependency was therefore always reported as
  "not installed" (`forge audit`), with blank version/license (`forge
  licenses`), or as a childless leaf (`forge tree`). Path dependencies were
  unaffected. Fixed by routing all three through the same `Project.dep_root_dir`
  resolver `forge deps` already uses.

### Documentation

- **`Set.fold`'s doc comment now matches its actual (uncurried) callback
  convention.** It claimed the callback is curried (`f(acc)(elem)`); the
  implementation has always called it uncurried (`f(acc, elem)`), same as
  `Map.fold`/`Hamt.fold`/`Enum.fold`.

### Changed

- **BREAKING: a module that calls a capability builtin directly must now
  declare it.** This was a warning; it is an error.

  ```march
  mod MyApp do
    needs IO.Console      -- now required
    fn main() do
      println("hi")
    end
  end
  ```

  The error names the capability and contains a machine-applicable fix, so
  `forge fix` inserts the line for you.

  Why now: `needs` was a hard floor for capability-*passing* code and only
  advisory for a direct builtin call, which is the code most likely to abuse
  it. Making it an error was previously blocked on granularity, because
  capability propagation worked at module granularity and contracting `List`
  (its `pmap` calls `task_spawn`) would have forced `needs IO.Spawn` on
  every module importing `List` to call `map`. Per-function transitive closure
  fixed that, so the severity could follow.

  **What it does and does not guarantee.** It catches a *direct* call:
  `file_read(p)`. It does *not* catch the same operation through a stdlib
  wrapper (`File.read(p)`), which stays silent under `--check`. The complete
  check remains `--cap-strict`, which works on emitted code and cannot be
  evaded by re-routing through a helper. So `needs` is now a mandatory,
  mechanically-verified manifest of the builtins a module calls directly; it
  is not on its own proof that a module cannot reach a capability.

  Note also what has *not* changed: `needs` is still a self-declaration. Any
  module may write any `needs` line, and IO builtins take no capability
  argument. This makes you *declare* what you touch; it does not make anyone
  *grant* it.

  Two things intentionally left untouched: an `extern` block implying `IO.Foreign`
  is still a warning, and the declared-but-unused warning is unchanged.

### Added

- **`tcp_local_port(fd) : Result(Int, String)`**: returns a socket's local
  (bound) port, i.e. the OS-assigned one after `tcp_listen(0)`. Lets a program
  bind an ephemeral port and hand it to an in-process client, so concurrent
  runs on a shared host never collide on a fixed port. Requires `IO.NetListen`,
  like `tcp_listen`/`tcp_accept`.

- **Process capabilities have their own type: `ActorCap(a)`.** `get_cap`,
  `send_checked`, `revoke_cap` and `is_cap_valid` now take and return
  `ActorCap` rather than `Cap`.

  They are different things that happened to share a type constructor. An IO
  capability is erased at runtime and governed by `needs` and the capability
  lattice; a process capability is a real, epoch-validated reference to a live
  actor, governed by actor liveness and revocation. Because they shared `Cap`,
  they unified, and `get_cap` applied to a `Pid` with a type parameter that was not
  pinned (via `pid_of_int`) produced `Cap(IO)`, handing the root capability to
  a module that was granted no capability.

  If you use these builtins, change the annotation to `ActorCap`; no other code
  changes. `ActorCap` is intentionally invisible to `needs`: a process
  capability is not IO authority and never required a declaration.

- **Capabilities can now be attenuated at any level, not just from the root.**
  `cap_narrow` was typed `Cap(IO) -> Cap(a)`, so its argument was literally the
  root capability: a holder of `Cap(IO.FileSystem)` could not narrow to
  `Cap(IO.FileRead)`, and every attenuation had to happen in `main` with the
  narrowed values threaded down.

  It is now `Cap(a) -> Cap(b)`, and the compiler checks that the source
  capability subsumes the target. Widening (`IO.Console` → `IO.FileWrite`) and
  lateral moves between siblings (`IO.FileRead` → `IO.FileWrite`) are still
  errors: the message names both capabilities and states which is not below the
  other.

  This makes delegation-with-attenuation writable: hand a subsystem
  `Cap(IO.FileSystem)`, let it hand a helper `Cap(IO.FileRead)`.

- **Context-indexed trust for `~H`: `Html.TrustedHtml` / `TrustedAttr` /
  `TrustedUrl` / `TrustedCss` / `TrustedJs`.** `Html.Safe` marks a string as
  trusted but not trusted *where*, so a value trusted anywhere was trusted
  everywhere. These types name the context the trust applies to, and trust does
  not travel between them:

  ```march
  let h = Html.trust_html("<b>hi</b>")
  ~H"<p>${h}</p>"                -- <p><b>hi</b></p>        verbatim
  ~H"<a href=\"${h}\">x</a>"      -- &lt;b&gt;hi&lt;/b&gt;   escaped
  ```

  Constructors `Html.trust_html` / `trust_attr` / `trust_url` / `trust_css` /
  `trust_js`, with matching `untrust_*`. Prefer `~H` itself, which needs no
  trust at all; reach for these only when a string truly is markup, a URL,
  CSS or JS from a source you control.

  Resolved **entirely at compile time**: the emitter matches the static type
  against the escaper id the `~H` desugar already folded, so a mismatch costs
  zero at runtime: it simply escapes. That is why these are separate types
  rather than one type containing a context tag; a tag would be runtime data and
  could not be resolved statically.

  `Html.Safe` and `Html.raw` are unchanged and keep working (they are treated
  as HTML trust) but are now documented as deprecated in favour of the
  context-indexed types.


### Fixed

- **`Html.tag` had three injection holes; it now validates names and escapes
  values by context.** `Html.tag` composes markup outside the `~H` sigil, so it
  never reached the contextual analysis added for `~H`. Measured before the fix:

  | call | emitted |
  |---|---|
  | `Html.tag("div onload=alert(1)", …)` | `<div onload=alert(1)>`: element name concatenated raw |
  | `Html.tag("div", [("onerror", "alert(1)")], …)` | `<div onerror="alert(1)">`: entity-encoding has no effect on `onerror` |
  | `Html.tag("a", [("href", "javascript:alert(1)")], …)` | the URL verbatim |

  Attribute **values** are now escaped for the context their name implies: url
  attributes get the scheme allowlist, `style` gets CSS declaration escaping,
  everything else attribute escaping. Element and attribute **names** are
  validated and an invalid one **panics**: escaping cannot help there, since
  `onerror` has no character to escape, so a name built from untrusted input is
  a programming error rather than a data condition. Event-handler attributes
  (`on*`) are always an error: their value is JavaScript, and `Html.tag` has
  no way to know whether the caller meant that.

  Reachable but unreached: the only call site in the ecosystem passes literals.

  `Html.tag` and `Html.escape_attr` are now documented as **deprecated** in
  favour of `~H`, which gets the same analysis at compile time and needs no
  runtime checks. Neither is removed; `bastion` is published at 0.2.3.


### Changed

- **A capability reached through a module-level `let`, an interface or `impl`
  method, or a default argument is now attributed to the function that reaches
  it.** The per-function capability record covered `fn` signatures/bodies, actor
  handlers and `extern` blocks only, so a function where the sole impure act was to
  read a module-level `let` that prints contained an empty capability set; and an
  importer that referenced only that function was not asked to declare the
  capability, where the older module-granular rule would have. All four forms
  are now recorded, including default-argument expressions (evaluated at every
  call site that omits the parameter) on both the desugared and undesugared
  paths. This can newly require a `needs` declaration on code that
  under-declares today; measured over `stdlib/*.march`, `test/native/*.march`
  and `bench/*.march` (277 files), diagnostics match to the byte, and `march
  caps`, `--cap-sandbox` and the hot-deploy manifest are unchanged on that
  corpus. An `impl` method is keyed by its `Iface$Ty.method` mangling and an
  interface default body by `Iface$default.method`, and the bare method name
  contains dispatch edges only when the module declares no plain function of that
  name, so a `fn` that happens to share a method's name can never be credited
  with that method's capabilities.

- **Importing a module no longer requires declaring capabilities used only by
  functions you don't reference.** `import M` / `use M` used to force *every*
  capability `M` declares onto the importer, so importing a library for one pure
  function cost you its impure siblings' capabilities: importing `List` to call
  `map` would have required `needs IO.Spawn` on account of `List.pmap`. Propagation
  is now demand-driven: you inherit the capabilities of the functions you
  actually reference, computed per import site over the transitive reference
  graph (a function passed as a *value* counts, and a capability reached only
  through a private helper counts). The result is always a subset of what was
  required before, so no program that compiles today can start failing; the error
  message and its caret are unchanged, only the set of required capabilities
  narrowed. An import into a cyclic module group falls back conservatively to
  the old whole-module set.

- **`~H` now escapes by HTML parse context, not with one escaper everywhere.**
  Previously every interpolation was HTML entity-encoded regardless of where it
  landed, which is correct in element content and wrong everywhere else. The
  desugarer now walks a template's literal chunks through a context automaton at
  compile time and gives each hole the escaper its position calls for.

  **This changes rendered output.** Measured across bastion and forgepm (121
  templates, 253 interpolations), 40 holes change:

  | context | before | now |
  |---|---|---|
  | element content (213 holes) | entity-encoded | unchanged |
  | attribute value (17) | entity-encoded | + backtick |
  | URL component (14) | entity-encoded | percent-encoded |
  | `style` attribute (7) | entity-encoded | CSS declaration/value escape |
  | start of `href`/`src` (2) | entity-encoded | **URL scheme allowlist** |

  The last row closes a real hole: `~H"<a href=\"${url}\">"` accepted
  `javascript:alert(1)`, since entity-encoding does not touch a scheme. Such
  URLs now render as `about:invalid#zSoyz`.

  An **unquoted attribute value** receiving an interpolation is now quoted
  automatically (`<div class=${x}>` emits `<div class="…">`), so a value
  containing a space can no longer start a new attribute.

  Interpolations that no escaping can make safe are now **compile errors**
  rather than silently-wrong output: an attribute name, an element name, the
  interior of a comment, and a template that ends mid-tag or mid-attribute.
  No code in bastion or forgepm hits any of these.

  Escaping tables live in `specs/security/html-contexts.tbl` and are documented
  in `specs/security/README.md`.

- **Breaking: the three JS-only stdlib modules are now namespaced under `Js.`.**
  `mod Audio`, `mod Canvas`, `mod Dom` are `mod Js.Audio`, `mod Js.Canvas`,
  `mod Js.Dom`: these are the only stdlib modules that panic at runtime when
  called from a native build, and the shared prefix puts that constraint at
  every call site instead of only in a doc comment. Filenames
  (`stdlib/{audio,canvas,dom}.march`) are unchanged. No back-compat aliasing
  exists for module names, so every caller (`Audio.beep(...)` →
  `Js.Audio.beep(...)`, etc.) must update in lockstep. See
  `specs/progress/2026-08-05-js-namespace-audio-canvas-dom.md`.
- **`cap no_panic` now consults a call's actual refinement contract instead of
  banning it by name.** A partial stdlib or prelude function that declares a
  refinement precondition (`unwrap`, `expect`, `head`, `tail`, `last`,
  `List.nth`/`head`/`last`/`tail`/`maximum_int`/`minimum_int`,
  `Option.unwrap`/`expect`, `Result.unwrap`/`expect`/`unwrap_err`,
  `Random.normal`/`exponential`/`bernoulli`/`choice`/`choice_weighted`,
  `DateTime.fixed_zone`/`fixed_zone_hm`,
  `Stats.mean`/`min_val`/`max_val`/`percentile`/`quantile`/`quantiles`/
  `five_number_summary`/`variance`/`mode`/`covariance`/`correlation`/
  `linear_regression`) is
  no longer rejected on sight inside a `cap no_panic` module. The call is
  checked against its contract, by the same solver and the same verdicts that
  discharge division safety, so a call the solver shows safe compiles clean:
  `if List.length(xs) > 0 do List.tail(xs) else xs end` is now accepted where
  it used to be an error. Anything short of a proof (refuted, undecided, or
  no obligation recorded at all) is still an error, because `cap no_panic` is
  a guarantee; an `@[trusted]` assertion does not count as a proof here. Names
  with no contract (`panic`, `panic_`, `todo_`, `unreachable_`, `Array.get`,
  `Array.set`, `Array.pop`) are still banned unconditionally.
- **`Stats.covariance`, `Stats.correlation` and `Stats.linear_regression` now
  declare their two structural preconditions.** `xs : {List(Float) | len(_) >= 2}`
  and `ys : {List(Float) | len(_) == len(xs)}`; the second refines one
  parameter by referencing a *sibling* parameter's measure, the same shape
  `List.nth`'s `n : {Int | _ >= 0 && _ < len(xs)}` already used. A call where the compiler can
  relate the lengths is now proved at compile time rather than
  checked by a runtime `panic`. `Stats.correlation`'s zero-standard-deviation
  panic and `Stats.linear_regression`'s zero-variance panic depend on the
  values in the lists rather than their shape and remain runtime-only.
- **`cap no_panic` no longer reports transitive blame for those
  contract-covered names.** An unprovable `List.tail(xs)` inside a helper used
  to produce one error at the helper *and* one at every local caller of it; it
  now produces exactly one error, at the real call site. If an error looks like
  it "moved" from a caller to the callee, this is why. `panic`/`panic_`/
  `todo_`/`unreachable_` and `Array.get`/`Array.set`/`Array.pop` keep their
  transitive blame unchanged.
- **`cap no_panic` now reports one error per offending call site, not one per
  function.** A function containing two unprovable `List.tail` calls reports
  two errors where it used to report one. No new program is rejected (the same
  function already failed), but you now see every offending call at once.
- **`march check` and `march caps` stay conservative for the contracted
  names.** Proving a call safe needs the refinement checker, and those two
  commands are a package-level typecheck-only pass that does not run it (nor
  does the LSP). They keep banning the contracted names by name, transitive
  blame included, so a guarded `List.tail` that `march --check` accepts is
  still reported by `march check`. This is the pre-existing behavior preserved;
  no program that passed `march check` before fails it now. Use `march --check` for
  the proof-based answer.

### Removed

- **`demo_app/perihelion`, `demo_app/dom_demo`, and `demo_app/canvas_demo`.**
  Along with the live `docs/perihelion.html` page, its checked-in compiled
  assets (`docs/assets/perihelion/`), the CI workflow that regenerated them
  (`gen-perihelion-assets.yml`), and the now-dead `build-dom-demo` slash
  command. `demo_app/tetris` and `demo_app/tetris_logic` are unaffected and
  updated for the `Js.*` rename above.

### Fixed

- **`--refine-suggest*` silently changed `cap no_panic`'s verdict, in both
  directions.** The refinement *suggestion* printers work by re-checking your
  program with a speculative contract spliced into one signature, and they ran
  in between the pass that records each call site's verdict and the pass that
  reads it, so `cap no_panic` was assessed against a hypothesis rather than
  against your code. Adding `--refine-suggest-all` (or `--refine-suggest`,
  `--refine-suggest-post`, `--refine-suggest-post-all`, or running
  `forge refine`, which shells out to `march --check --refine-suggest-json`)
  could make an unguarded `List.tail` inside a `cap no_panic` module compile
  clean (a capability that promises no panics, voided by a diagnostic-only
  flag) and could equally make a correctly guarded call fail. `march test`
  was unaffected, so the two pipelines differed. The consumer passes now run
  before the printers, and the suggestion probes no longer disturb the verdict
  index at all, so a `--refine-suggest*` run reports exactly what the same
  command without the flag reports.

- **A `@[measure]` that silently proved no fact now reports it.** A measure with a
  value that is a constructor field read (`PVec(n,_,_,_) -> n`, how a
  count-carrying container like `Array` writes `length`) is accepted, passes
  the soundness gate, and generates a correct axiom, yet can never discharge
  anything: the refinement checker erases non-datatype constructor fields at
  call sites, so the measure applied to a literal evaluates to an unknown.
  Every symptom of a working measure was present and contracts using it simply
  never fired. This is now a warning at the measure's definition. It is
  advisory only (no verdict, error, or accepted program changes) and it
  intentionally under-reports rather than risk a false positive: only a bare
  field read is flagged, so `-> n + 0` (equally inert) stays silent.

- **`cap no_panic` compiled clean for `Array.pop`, which can truly panic.**
  `Array.pop` panics on an empty vector (`Array.pop: empty vector`), but it was
  on neither `cap no_panic`'s syntactic ban list nor its contract-covered set,
  so a module declaring `cap no_panic` could call it and pass: the capability
  promising no panics while admitting a call that can panic. It is now banned
  by name, with a suggestion to check `Array.length(v) > 0` first, joining
  `Array.get` and `Array.set`. If you were calling `Array.pop` inside a
  `cap no_panic` module, that module now fails to compile; guard the call and
  use the length check, or drop the capability. Found while gating a bounds
  contract for the `Array` accessors; that contract is NOT shipped, because
  `Array.length` is a scalar constructor-field read and the refinement
  checker's call-site reflection erases such fields, leaving the measure unable
  to prove anything (`specs/todos/2026-08-05-measure-over-scalar-ctor-field.md`).

- **`cap no_panic`'s syntactic ban list had fallen out of sync with the real stdlib.**
  An audit found three problems in `panic_surface_stdlib`
  (`lib/typecheck/typecheck.ml`), the name list `cap no_panic` uses to reject
  calls to functions that can panic. Most seriously: **twelve public stdlib
  functions that carry a real refinement precondition and panic when it's
  violated (`List.tail`, `List.maximum_int`, `List.minimum_int`,
  `Random.normal`, `Random.exponential`, `Random.bernoulli`, `Random.choice`,
  `DateTime.fixed_zone`, `DateTime.fixed_zone_hm`, `Stats.mean`,
  `Stats.min_val`, `Stats.max_val`) were absent from the list under any
  spelling, so a `cap no_panic` module could call one of them unguarded and
  compile clean today (`exit 0`, only a silent hint). All twelve are now
  banned. Also fixed: `String.slice_bytes` was banned despite its own
  docstring stating it never panics (`start`/`len` are clamped); removed, so
  a `cap no_panic` module can now call it. And seven entries
  (`List.hd`/`List.tl`/`List.min_elt`/`List.max_elt`/`String.nth`/
  `NativeArray.get`/`NativeArray.set`) named functions that don't exist under
  those names anywhere in the stdlib; removed as harmless drift. This is a
  syntactic-only fix (no new mechanism). A properly *guarded* call to one of
  the twelve is accepted, but by the proof-based check described under
  **Changed** above, not by this list.

- **`--cap-strict` rejected programs that use no capability at all.** `mod M do
  fn main() do () end end` failed with `` `IO.Console` is used but cannot be
  attributed to any module``, and declaring the capability could not help (an
  unattributed capability has no owner to check a declaration against, by
  design). The module's own capability set was computed from the decl list
  *after* the stdlib prepend, so the prelude's top-level `println`/`debug`
  counted as functions the user's file declares and their `IO.Console` was
  credited to the user's module. In practice `--cap-strict` only passed if the
  program itself called `println`. Stdlib-declared functions are now excluded by
  span, the same gate the typechecker already uses; a real undeclared console
  use is still reported. The `--cap-sandbox` profile is unaffected (it derives
  its grants from FileWrite/Network/Process only).

- **`--cap-strict` falsely rejected modules nested two or more levels deep.** A
  module like `mod App do mod Inner do mod Deep do needs IO.FileWrite` was
  reported as "uses `IO.FileWrite` but does not declare `needs IO.FileWrite`"
  even though it declared exactly that. The typechecker recorded each module's
  declared `needs` under its BARE name, while the limit check matches emitted
  code against the fully-qualified owner (`Inner.Deep`), and an entry recorded
  inside an enclosing `mod` was dropped at that boundary before the check could
  see it. At one level of nesting the bare and qualified spellings coincide, so
  only depth >= 2 was affected. Declarations are now keyed by qualified path
  (bare name kept as an alias for `use` lookups) and propagate outward; a
  doubly-nested module that omits its `needs` is still reported, under its
  qualified name.

- **`~H` misread non-IOList ADTs as IOLists: unescaped output and a SIGSEGV.**
  `march_html_auto_escape` ended by assuming any constructor with `tag >= 0` was
  an `IOList` and flattening it verbatim. Constructor tags are numbered per type
  from 0, so every ADT aliased `IOList`'s `Empty|Str|Segments`: a tag-1
  constructor had its `String` field emitted **raw and unescaped**, a tag-2
  constructor crashed walking field 0 as a cons list, and a tag-0 constructor
  rendered empty. The widest case needed no custom type at all: `Cons` is tag 1
  with the element in field 0, so interpolating a plain `List(String)` emitted
  its head element raw and unescaped. `Option`/`Result` were not exempt: only `Some(x)` is
  niche-optimised, so `Err("<b>")` leaked its payload unescaped and `Ok(...)`
  was silently dropped. `Html.raw` content was also discarded whenever another
  module declared a type named `Safe`. The interpreter was correct throughout;
  this was compiled-only. The escaper now dispatches on the argument's static
  type in `llvm_emit` rather than guessing from a heap tag. A hole with a type still
  unresolved (a value reaching it through a closure stored in a container) is
  stringified rather than flattened, since no runtime information can tell an
  `IOList` from an ADT there; that makes a real `IOList` partial at such a
  hole render `#<tag:N>` instead of its markup, which is a real but narrow
  regression accepted over leaving an XSS and a crash in place.

  Note one visible consequence: a user ADT interpolated into `~H` now renders as
  `#<tag:N>` compiled, where the interpreter renders `Point(1, 2)`. That is a
  pre-existing gap in compiled `to_string` (it has no constructor-name
  metadata), now reachable from templates; tracked in
  `specs/todos/2026-08-05-compiled-to-string-adt-ctor-names.md`.

### Added

- **The root capability is granted to `main`, not taken.** `root_cap` can no
  longer be referenced from ordinary code. Declare `fn main(cap : Cap(IO))` to
  receive it and thread it to whatever needs it, narrowing with `cap_narrow`
  along the way.

  `root_cap` was an ordinary global of type `Cap(IO)` in scope in every module,
  so a module declaring **no `needs` at all** could hold the root capability
  and narrow it to any descendant, validly, because `cap_narrow` demands
  exactly the parent it now had. That is authority out of thin air.

  `main` taking a `Cap(IO)` already worked and is unchanged; only the ambient
  global is gone. Two contexts keep it, both scoped intentionally: `test` /
  `describe` / `setup` bodies, which have no `main` to be granted from and
  would otherwise make capability behaviour untestable, and the REPL. Both are
  ambient authority in a place that cannot reach production code: a
  dependency's test blocks do not run in a consumer's build.

- **Capabilities are unforgeable: they can be received and narrowed, never
  constructed.** `Cap(X)` may no longer appear in the result of `from_json` or
  `from_json_events`, in the argument of `to_json`, or anywhere in a type that
  `derive Json` generates a codec for. This is a hard error, not gated on
  `--cap-strict`.

  Previously `from_json` was typed with no constraint on what it produced, so
  `let forged : Cap(IO) = from_json("{}")` typechecked (`--cap-strict`
  included) and fabricated root authority from a string literal. It failed at
  run time only because `from_json`'s return-type dispatch is unimplemented,
  which is an open item to build.

  Both directions are turned down together: encoding a capability leaks no authority at
  run time, but it manufactures the wire value a decoder would consume, and
  `derive Json` generates both directions from one declaration.

  One consequence worth knowing: a single `from_json` application can no longer
  be used at two different result types. Decoding one string as two unrelated
  types was already meaningless, since `from_json` dispatches on a single
  determinable target type.

- **`needs` now covers type declarations and `let` annotations.** A capability
  named in a record field, a variant argument, or a `let` type annotation
  counts toward that module's `needs`, including when it is nested inside a
  container such as `List(Cap(X))`.

  Previously `needs` was checked against function signatures only, so
  `type Handle = { tok : Cap(IO.FileWrite) }` in a module declaring just
  `needs IO.Console` typechecked clean. A module could name a
  capability it never declared. These positions also count as *uses*, so
  adding the missing declaration does not then report it as unused.

- **`forge cap inspect --strict`** re-checks the capability limit on a
  binary you did not build. Binaries now carry each module's *declared* needs
  alongside its measured use, so the two can be compared without the source.
  Fails closed on a binary that contains no attribution rather than reporting a
  clean limit for one where the limit cannot be read.

- **`--cap-strict`: `needs` as a hard limit.** Opt-in build gate: every
  module's emitted code must stay within that module's own `needs`
  declarations, or the build fails naming the module.

  This closes a gap that was wider than the known one. `needs` was documented
  as a floor that capability-passing code could not go under, with direct
  builtin calls a warning rather than an error. Measured, a *stdlib-mediated*
  call (`File.write(…)`) produced **no diagnostic at all** (not even the
  warning), because the import check walks `use` declarations and stdlib
  modules are ambiently available without one. That is the most common route
  in real code.

  The check runs against emitted code rather than as another source-level
  walk, so every route (direct builtin, stdlib wrapper, builtin passed as a
  value) collapses into one rule that re-routing through a helper cannot
  evade. It applies per-module, so **a dependency that declares
  `needs IO.Console` and reads `/etc/passwd` fails the build**, without that
  dependency having opted in to anything.

  A capability that cannot be attributed to any module fails the check rather
  than passing it. `IO.Foreign` is excluded (extern blocks are already an
  error when undeclared), and FFI remains outside what any of this can see.

- **`forge cap inspect` now names WHICH module uses each capability.** The
  report gained an "Attributed to" section: `IO.FileRead   Conduit.Store`
  instead of only "this binary reads files". This is what makes it possible to
  ask whether a capability came from your code or from a dependency; the
  whole-program union could never distinguish them.

  Attribution is computed before inlining, which is the only point where it is
  correct: by codegen time a small dependency function has been folded into
  its caller, so attributing there credits the dependency's IO to the
  application, a false clean bill for the dependency. A capability reached
  through a stdlib wrapper is attributed to the module that called the
  wrapper, not to the wrapper, so `File.read` does not become the answer for
  every dependency in the program.

  A capability reached only through an indirect (closure) call has no
  statically known callee and is reported as *unattributed* rather than
  silently omitted. Also available as `attribution` in `--json` output.

- **Steady-state runtime demo (`bench/steady_state_ring.march` +
  `bench/run_steady_state.sh`).** An in-process, sustained request loop that
  measures March's two headline runtime claims together: **flat RSS under load**
  (RC reclaims per-op transients, so resident memory stays ~2–3 MB across
  millions of ops; no GC heap grows) and **bounded tail latency** (the
  preemptive green-thread scheduler keeps p50/p90/p99 near-constant at single-µs
  even while CPU-bound siblings oversubscribe every scheduler thread; the extreme
  p99.9 tail grows bounded, not unbounded, with contention). The hot request
  kernel is placed under `cap no_alloc` so zero steady-state allocation is
  compiler-enforced. Runner emits a latency histogram (p50/p90/p99/p99.9/max),
  an external RSS-over-time trace, and machine-readable JSONL; committed laptop
  (arm64) results under `bench/results/`. See
  `specs/2026-08-04-steady-state-tail-latency-demo.md`.

- **Path-scoped capabilities: `needs IO.FileRead("/etc/myapp")`.** A module
  can narrow a filesystem capability to a directory subtree instead of
  declaring all-or-nothing access. A literal path outside the declared scope
  is a compile error; computed paths are left to runtime enforcement rather
  than guessed at. `--cap-sandbox` narrows the embedded sandbox profile to the
  declared scope for **writes**; reads are not narrowed on macOS, because the
  profile must already grant `file-read` unconditionally for the dynamic
  loader, so a scoped read rule would be decorative. Unscoped declarations are
  unchanged in meaning, so existing code keeps working. Note that scope
  matching happens after the kernel resolves symlinks: on macOS a scope of
  `/tmp/x` matches no path, since `/tmp` is a symlink to `/private/tmp`.

- **`forge refine` now suggests the fix for a `cap no_panic` division.** The compiler's
  own error already states *"annotate the divisor parameter with `{v : Int | v != 0}`"*,
  but `--refine-suggest-all` printed `no suggestions` for exactly that case: the one a
  user is most likely to hit first. Division safety is a separate pass from the
  refinement checker, so its obligations reached neither the ledger the suggester counts
  nor the probe it re-runs; both are now wired, and `--refine-report` gained a `division`
  counter. Suggestions stay weakest-first (`_ != 0`, not `_ > 0`), and a division that is
  already safe (refined, or guarded by `if d != 0`) still draws no diagnostic.

- **Fifteen protocol-level LSP correctness tests.** The 2026-08-03 capability repair
  proved each feature *answers*; no test proved any of them answers *correctly*, and the
  existing per-feature tests exercise the analysis layer, which was never the broken
  part. `references`, `documentHighlight`, `documentSymbol`, `workspace/symbol`,
  `formatting`, `signatureHelp`, `prepareCallHierarchy`, `selectionRange`, `definition`,
  `foldingRange` and `rename` now have assertions on exact positions, each with a reject
  case where the correct answer is an empty result. The `formatting` edit is
  checked to match `march fmt` to the byte, so the two cannot drift.

### Changed

- **`List.nth` now contains a bounds contract:
  `n : {Int | _ >= 0 && _ < len(xs)}`.** `nth` panics on an out-of-range index
  and, unlike its siblings `head`/`last`/`unwrap`/`expect`, contained no contract
  at all, so an index the checker could show out of range compiled in silence. It is now a
  compile error: `List.nth([1, 2, 3], 7)` and `List.nth([1, 2, 3], -1)` are
  reported. This can turn previously-silent code into an error, which is why it
  is listed here and not under Fixed. In the default mode an index the checker
  cannot bound stays skipped and silent, as March reports only definite
  failures; but under `cap verified` (where the assumption is that every obligation
  is discharged) such an index is now a hard error where it previously compiled
  clean. That is in-kind with all 13 pre-existing stdlib contracts rather than
  novel, and no stdlib module or sampled project uses `cap verified`. A
  blast-radius
  sweep taken before the change (all 112 stdlib modules plus the `forgepm`,
  `bastion`, `conduit` and `depot` projects) found **zero** new violations and
  only new skips. `List.nth_opt` remains the unconditional alternative.

- **`forge cap audit` is now `forge cap inspect`.** Two commands named "audit"
  answered different questions at different granularities (`forge audit` reads
  dependency declarations from source, the other reads a built artifact), which
  is the kind of collision people get wrong under pressure. `inspect` is the
  right verb for reading facts off a thing that already exists, and follows the
  `docker inspect` example. No alias: the command is days old and unreleased.

### Fixed

- **Capability warnings were silently discarded in the entry module.**
  `prelude.march` is unwrapped into global scope, so its declarations ride in
  the *entry module's* declaration list. The body-scan check keeps one span
  per capability and keeps the first, so a capability prelude also used got a
  prelude span, which the driver then filtered out as stdlib-internal. The
  warning was generated and thrown away.

  Visible symptom: `println` at the top level of a program produced no "does
  not declare `needs IO.Console`" warning, while `file_exists` in the same
  module did, purely because prelude calls `println` and never calls
  `file_exists`. The same code inside a nested module or an actor handler
  warned correctly, which is why the existing enforcement tests passed.

  In practice this hid only `IO.Console`, since `println`/`print` are the
  only capability-bearing builtins prelude calls; the filesystem, network and
  process warnings were never affected. The mechanism was general, though, and
  any future prelude addition would have silently suppressed a real one.

  **This is a visible change:** a program that prints at the top level without
  `needs IO.Console` now gets the warning it should always have had.

- **`RingBuf` gained a compiled backend.** The `ring_buf_*` builtins existed
  only in the interpreter, so any program using `RingBuf` failed to link under
  `march --compile` (`Undefined symbols: _ring_buf_make …`). RingBuf now has a
  full native backend (a resource-cell-backed circular buffer with a destructor that
  releases live elements on drop), matching the interpreter's semantics for
  `make`/`push`/`pop`/`get`/`peek_*`/`size`/`cap`/`clear`/`to_list`, including
  wraparound eviction and element reference counting for heap-typed elements.
- **`NativeArray.set_int` / `set_float` no longer leak (or churn) a copy per
  call when the array is uniquely owned.** The C runtime's
  `native_int_arr_set` / `native_float_arr_set` are passed their array under
  the owned/consumed convention, but all they did was allocate a fresh backing
  array, `memcpy` into it, and return it, without releasing the consumed
  input. A hot loop threading the result forward (last-use, RC=1) leaked one
  copy per op: a 2M-op `set_int` loop on an 8-element array ramped to ~190 MB
  RSS (linear in ops) while the same loop without it held ~2.7 MB flat. They
  now reuse the backing array in place when it is uniquely owned (rc == 1),
  O(1) and flat RSS, and preserve copy-on-write (allocate, copy, then release
  the consumed reference) only when the array is shared (rc > 1), so an aliased
  array is never mutated out from under its alias. This is the same FBIP
  in-place-at-unique-ownership story March already applies to ADT reuse.
  Compiled-only (the interpreter uses a different NativeArray backend).
- **A skipped obligation no longer blames a withdrawn `List.length`/
  `String.byte_size` alias unless the guard would actually have discharged
  it.** `if List.length(ys) >= 0 do head(ys) …` used to report `reason:
  alias-withdrawn` (sending the author to rename an unrelated competing
  `List.length` definition) even though `len(ys) >= 0` is a tautology that
  proves no fact about the goal `len(ys) > 0`: the call is skipped whether or
  not the alias was withdrawn. The attribution now requires the guard's own
  comparison to syntactically entail the obligation's predicate (an
  interval-subset check over `==`/`<`/`<=`/`>`/`>=`; `!=` is not a convex
  interval, so it never entails anything by this check); where entailment
  can't be decided, the accurate `solver-undecided` message is kept instead.
  The verdict is unaffected (still `Skipped` either way); only the reason
  string changes.

- **A refined ADT return on a constructor-literal body is now actually
  checked.** `fn push(t : Tree, x : Int) : {Tree | size(_) == size(t) + 1} do
  Node(t, x, Leaf) end` (the simplest possible case, needing no induction at
  all) was never attempted: the postcondition prover recognised exactly one
  body shape, a top-level `match` on a parameter, and everything else fell
  through silently. A intentionally *wrong* postcondition on such a body
  reported `0 proved, 0 violated, 0 skipped` in `--refine-report`: not
  undecided, simply never looked at. Constructor-literal bodies are now
  discharged against the measure's recursion equations, and, unlike the
  `match` shape, record their verdict in the obligation ledger, so the report
  can tell "attempted and proved" from "never attempted". A proved
  postcondition also propagates to call sites, as with the `match` shape.

- **A CLOSED measure postcondition on a plain multi-constructor ADT now
  composes through an unannotated `let`.** `fn grow(t : Tree) : {Tree |
  size(_) > 0} do … end` followed by `let r = grow(t); needs_nonempty(r)`
  used to skip the second call: `scope_add_binding` seeded a refined-local
  scope entry for a scalar- or record-sorted postcondition only, so a plain
  variant ADT (`Tree`, `List(a)`) fell into the catch-all and the fact
  vanished, even though the identically-annotated spelling (`let r : {Tree |
  size(_) > 0} = grow(t)`) already worked. Only the CLOSED case (the
  postcondition mentions no parameter besides the refined value itself) is
  covered; see the next entry for the relational case.

- **A RELATIONAL measure postcondition now composes through an unannotated
  `let` too.** `fn push(t : Tree, x : Int) : {Tree | size(_) == size(t) + 1}`
  followed by `let r = push(t, 5); needs_bigger(t, r)` used to skip the second
  call. The attached promise mentions the caller's *other* variable `t`, and
  the fact loader accepted only names denoting the promised value itself, so
  `size(t)` failed to translate and, by the usual "untranslatable predicate
  stays unasserted" rule, the whole promise was dropped in silence. A
  caller-scope name under a measure now resolves to the same SMT term the goal
  side builds for it (never a fresh constant, which would make such a contract
  trivially satisfiable and enforce no constraint). A name rebound to a new value
  between the `let` and the call still retires the whole fact rather
  than being re-read at its new value, and a name that cannot be resolved
  still drops the promise silently.

- **`cap no_panic` no longer rejects a division guarded by a boolean
  condition.** `if p > 0 && d > 0 do n / d else 0 end` was reported as a
  possible division by zero, as was every other guard containing `&&` or `||`,
  including `if d <= 0 || d > 1000 do 0 else n / d end`, a disjunction over
  the divisor itself. Only a single, atomic comparison was understood, so the
  most idiomatic safe spelling was rejected. Guards are now read through `&&`,
  `||` and `not`: a conjunctive fact is discharged by either side, a
  disjunctive one only when both sides prove the divisor non-zero
  independently. Guards that truly fail to rule out zero still error.

- **A package's own constructor is no longer ambiguous against an unimported
  stdlib type.** Declaring `type Backend = StorageBacked | Custom(Int)` in
  `mod Pkg` and matching on `Custom` from `mod Pkg.Sub` failed with
  "ambiguous between multiple modules" whenever any stdlib type shared the
  constructor name: conduit's `RateLimiterBackend.Custom` against
  `Compress.Gzip.Level.Custom`, which made the whole package fail to
  typecheck. Locality now covers the package namespace rather than requiring
  an exact current-module match. Truly ambiguous references, where the
  current package owns none of the candidates, still error.

### Documentation

- **OS-level capability enforcement is now documented.** The capabilities guide
  gains an "OS-level enforcement" section covering `forge cap run` (an
  externally imposed sandbox) and `--cap-sandbox` (a deny-default profile a
  binary installs on itself at startup: macOS Seatbelt / Linux seccomp-bpf,
  fail-closed), with the accurate defense-in-depth framing and the per-platform
  advisory caveats. The capability-audit and tooling pages cross-link to it and
  distinguish *reading* a binary's authority (`forge cap inspect`) from
  *enforcing* it, and the `forge cap` tooling reference now lists the
  `coverage`, `inspect`, and `run` subcommands alongside `query`.

### Added

- **`forge audit --inferred`: infer each dependency's capability set from its
  code rather than its `needs` declarations.** Catches a capability builtin
  called directly in a body with no matching `needs` (which the compiler only
  warns about), at the cost of requiring each dependency to typecheck cleanly.
  Every capability report now states what it does NOT cover: source-level
  audits miss capabilities reached through stdlib or dependency functions,
  binary audits are a whole-program union that cannot attribute a capability to
  a specific dependency. The two are complementary, and neither is a complete
  account on its own.

- **`march caps <files...>`: a package's inferred capability set as JSON.**
  Loads the whole package the way `march check` does, so sibling and
  dependency imports resolve. Package-level rather than per-file because
  per-file does not work: most files in a real package reference siblings and
  fail standalone, and a union over whatever happened to typecheck
  *under*-reports, which for a capability record certifies a package as
  needing less than it does. A package that does not typecheck yields no set
  at all and a nonzero exit, rather than a partial one.
- **`/docs/capability-audit/`: a capability-audit guide written for a security
  audience.** Covers `forge audit` (dependency declarations, diffed against a
  baseline) and `forge cap inspect` (what a compiled artifact contains), what each
  proves, and a threat-model table of what neither covers. States clearly that
  an undeclared capability *builtin* is currently a compiler warning rather than
  an error, so a declared set is a floor for capability-passing code rather than
  a limit on all behaviour.

- **`forge audit`: capability diffing on dependency update.** Every March
  package declares the capabilities it needs and the compiler enforces those
  declarations, so the authority a dependency has is readable from its source
  rather than guessed at. `forge audit` extracts the capability set of every
  transitive dependency and compares it against a recorded baseline:

  ```
  $ forge audit
    ! liba — now ALSO needs: IO.FileWrite, IO.NetConnect

  1 dependency is asking for capabilities it did not have.
  Review the change, then accept it with `forge audit --record`.
  ```

  Exits non-zero on that, so CI can gate a dependency update on it. A dependency
  that *stops* asking for a capability is reported but does not fail the audit:
  narrowing is the direction you want, and failing on it would train people to
  ignore the gate.

  The baseline lives in `forge.caps.lock` rather than in `forge.lock`, because
  `forge deps` rewrites the lockfile wholesale from resolution output and would
  silently erase a capability set recorded there, leaving a gate that compares
  zero entries and reports success.

  Scope, stated clearly: this reports what a package's source *declares*. It is
  exactly as trustworthy as the compiler's enforcement of `needs`, which is
  strong for March code and makes no claim about what an `extern` block's foreign
  code actually does: a package that grows an `extern` shows up as
  `IO.Foreign`.

- **`forge refine --postconditions`, `--apply`, and an editor action complete
  the postcondition side.** The compiler surface shipped previously; this adds
  the two surfaces people actually reach for. `--apply` rewrites the *return*
  annotation via a new `Refine_edit.splice_return`, which is a truly
  different scan from the parameter one: it must find the paren closing the
  parameter list (depth-tracked, so `Map(String, Int)` does not end it early)
  and stop at the `do` that opens the body. The editor gets a "Suggest a
  postcondition for `f`" action alongside the existing precondition one,
  sharing that same splice so the CLI and the editor produce identical bytes.

- **`march --cap-sandbox`: opt-in self-imposed capability sandbox.** Embeds a
  deny-default profile derived from the module's own inferred capabilities and
  applies it before any user code runs, so a binary deployed where forge is not
  the launcher (systemd, a container supervisor) still drops the privileges it
  never needed. Defense in depth rather than a new guarantee: the person building
  the binary chooses whether to compile it in, and the profile grants exactly
  what the program does, so it constrains escalation beyond the program's
  intended behaviour, not the behaviour itself. Off by default; default builds
  are unchanged. Implemented on both major platforms: macOS via a
  deny-default Seatbelt profile, Linux via an in-process seccomp-bpf filter
  installed unprivileged through `PR_SET_NO_NEW_PRIVS`, which matters
  because Linux is where servers actually run. Denied syscalls return
  `EPERM`, so a withheld capability surfaces as a March `Err` rather than a
  crash. `IO.Network`, `IO.Process` and `IO.FileWrite` are enforced;
  `IO.FileRead` is not, because seccomp filters syscall numbers and scalar
  arguments, never pointer contents, so it cannot tell which path is being
  opened (path scoping needs Landlock). Installation failure is fatal:
  running uncontained after being asked to contain is a poorer outcome than not trying.

- **`forge cap run [--allow-only CAPS] BINARY`: run a compiled binary under an
  OS-enforced capability sandbox.** The policy is imposed from outside, so
  no part of the binary is trusted; `--allow-only` lets you supply the policy
  for untrusted code, since a policy derived from the binary's own claim only
  defeats under-claiming. macOS uses `sandbox-exec` (SBPL), Linux uses
  bubblewrap. Which capabilities are truly enforceable was measured, not
  assumed: network, file-write and process-spawn are enforced, while
  `IO.FileRead`, `IO.Clock`, `IO.Spawn` and `IO.Random` are reported as
  **advisory** (denying them aborts the runtime: the loader must read system
  libraries, and clock/thread syscalls cannot be told from the GC and
  scheduler's own). Advisory capabilities are printed before the run so a clean
  run is never mistaken for full containment.

- **`forge cap inspect <binary>`: list the capabilities of a compiled March
  executable.** Executables are now linked with dead-strip (72–79% smaller),
  so unused capability runtime code is physically absent, and codegen embeds
  `__march_cap_*` marker symbols for the capabilities the emitted code
  actually references. The audit reads both channels, renders witnesses
  (which runtime entries back each cap), and gates CI with `--deny CAP` /
  `--allow-only CAPS` through the capability lattice (denying `IO` catches
  `IO.FileRead`). Foreign code (FFI) is reported as a scope limitation
  (analysis stops at the C boundary) and the gate fails closed on it unless
  `--allow-foreign` is passed; the same fail-closed rule applies to stripped
  or unstripped binaries (`--json` always includes a `coverage` field).
  `march caps <files...>` prints a package's inferred capability set as JSON.
- **`march --refine-suggest-post <fn>`: suggest a postcondition.** Where
  `--refine-suggest` proposes the parameter contract that discharges a
  function's own unproven obligations, this proposes the *return* contract that
  lets its **callers** discharge theirs, the other direction of the same
  propagation. Verified end to end: applying the suggestion takes the worked
  example from 1 proved / 1 skipped to 3 proved / 0 skipped.

  A postcondition discharges no obligation in its own function, so two independent
  questions are both answered before anything is proposed: is the candidate
  *true* (asked of the checker's own postcondition oracle, not a second prover),
  and is it *useful* (does any caller's obligation actually become provable). A
  true-but-useless postcondition is not proposed: a sweep full of true
  irrelevancies looks the same as a broken one. Outcomes stay
  distinguishable rather than collapsing into silence: `no-callers`,
  `no-debt`, `no-candidate` and `already-refined` are separate answers.
- **A missing capability now shows the call chain from `main` that forced it.**
  A capability is a property of a whole path, not of the single call that
  happens to need it (`needs` has to be threaded through every function in
  between), but the diagnostic named only the far end:

  ```
  call to `random_bytes` requires `needs IO.Random` — add `needs IO.Random` to module `CapErr`
  reached from `main`: main → issue → make_token
  ```

  The chain crosses module boundaries (a qualified `M.f` resolves to the simple
  name its definition declares) and terminates on recursive call graphs. It is
  omitted rather than guessed when there is no chain to show: a library with no
  `main`, a call sitting in `main` itself, or a callee reached only through a
  function value. Because the edges are syntactic, the chain is a witness rather
  than a proof: two modules defining the same function name share a node, so an
  unusual program can get a plausible sibling in the path.

- **An unverified refinement contract now reports it, once per module.** March
  reports only definite failures: an obligation the solver cannot decide is
  accepted in silence, which is the right default (a false positive on correct
  code is the costlier error) but leaves no way to tell "checked and fine" apart
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
  invisible at the place it happens: you had to read the callee's signature,
  and often its body, to know whether passing a value ended its life. The hint
  is read off the compiler's own borrow inference (`Borrow.infer_module`), the
  same map Perceus consults when deciding which arguments need a reference-count
  bump, so it reports the decision the compiler actually made rather than a
  re-derivation of it. Two intentional restrictions keep it a signal instead of
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
  limitation, not a resolution bug; see
  `specs/progress/2026-08-03-interface-method-names-qualifiability-disposition.md`),
  but the `unbound variable: Foo.speak` error now names the interface and
  its declaring module and suggests the unqualified `speak(x)` call.

- `forge refine --fixpoint` (with `--apply`): repeat until a round applies
  no edit. A contract only becomes visible to a caller once the callee contains
  it, so each round propagates exactly one call hop. Bounded at 10 rounds, and
  hitting that bound is reported as its own outcome rather than passed off as
  convergence.

- **`forge refine <fn>`: suggest a refinement type.** Proposes the parameter
  refinement that discharges the obligations a function's body leaves
  unproven: `n : Int` → `n : {Int | _ > 0}` when `n` reaches a callee that
  requires a positive argument. Prints by default; `--apply` writes the
  annotation into the source, and `--all` sweeps the whole project. The
  editor gets the same thing as a "Suggest a refinement type for `f`" code
  action on the function's name.

  A suggestion is only made when the refinement checker itself proves the
  obligations under it: each candidate is hypothesised onto the signature and
  the real checker is re-run, so `march check` after `--apply` agrees with
  what was printed. Where several candidates work, the **weakest** is proposed:
  a divisor contract comes back as `_ != 0`, not `_ > 0`, so the suggestion
  does not silently reject callers the function would have accepted. Where
  no approach works, the command reports it rather than going quiet: `no-debt`,
  `no-candidate`, and a partial discharge are distinct outcomes.

  It also declines to propose a contract that contradicts the function: a
  `_safe` wrapper handling `Nil -> Err(...)` is left untouched, because forbidding
  the empty list would kill the branch the author wrote on purpose, while a
  branch that *panics* still gets the contract, since converting that panic to
  a compile error is the point. A sweep over all 112 stdlib modules is what
  found this; without the guard, three of its four suggestions were of that
  wrong shape.

  Also exposed on the compiler as `march --refine-suggest <fn>`,
  `--refine-suggest-all`, and `--refine-suggest-json`. Needs Z3, like the rest
  of refinement checking.

- `forge search --callers NAME`: reverse-reference search that finds every
  resolved call, constructor use, or qualified type reference to a
  declaration, using the typechecker's own name resolution (not textual
  matching).

- **`derive Json for T` (record types) now also generates
  `from_json_events(events) : Result((T, List(JsonStream.Event)),
  Json.DecodeError)`, a second decoder that consumes `JsonStream`'s
  `Event` list directly instead of building a `JsonValue` tree first.**
  A record can now be decoded straight off the token stream, useful for
  a single huge top-level JSON object, where the existing tree-based
  `from_json` would otherwise have to materialize the whole thing as a
  `JsonValue` first. Generated as a small state machine: one `Option`
  slot per field, filled opportunistically as `EvKey` events arrive in
  whatever order the JSON object happens to use; a nested field with a
  type that also derives Json recurses into its own `from_json_events`,
  composing the error path across the boundary exactly like the tree
  decoder does. Unknown fields (and duplicate keys, which keep
  first-occurrence-wins, matching the tree decoder) are skipped by
  consuming their WHOLE value (including nested containers) via
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
  `Ok(n)` with the record count, or the FIRST decode/tokenizer failure
  (`Json.DecodeError`), with `Json.decode_error_at` used to set its offset
  to that record's start, so `Json.decode_error_to_string(e)` names both
  the failing field and the byte offset, e.g. `"$.id (byte 9): expected
  Int"`. `test/stdlib/test_json_stream.march` (phase 1/2's tokenizer
  suite) is unchanged and stays green: `each_typed` does not touch
  `feed`/`finish`/`go` or any tokenizer internals.

### Documentation

- **The memory-model page no longer claims March is pauseless, and now
  documents drop cascades and cycles.** "No GC pauses" overstated the
  guarantee: March has no tracing collector and no collection stall, but
  freeing is inline work proportional to what crashed, so releasing a large
  structure walks it. The page now frames the property as *deterministic, not
  pauseless*, adds a **Drop cascades** section (destructuring vs. synthesized
  deep drop, why long spines don't overflow the stack, and how to schedule the
  cost out of a latency-critical path), and adds a **Cycles** section stating
  the real answer: there is no cycle collector, a cycle would leak silently,
  and the reason that is not a practical hazard is a design argument
  (immutability, linearity, no shared pointers across actors) rather than a
  mechanized proof. Same corrections applied to the README and docs index
  summaries.

### Added

- **The LSP merges a run of imports, or a run of capability declarations, into a
  single range.** A block of eight imports collapses to one line instead of
  needing eight chevrons, matching the runs `march fmt` now keeps tight.
  Import runs carry the standard LSP `imports` fold kind, so editor commands
  like "fold all imports" reach them; capability runs use `region`. Runs are
  *maximal and consecutive*: imports split by a function are two runs, and
  neither one swallows the function between them. A lone import offers no
  fold, since there is no run to collapse. The server also now emits the
  standard `region` and `comment` kinds where they apply, instead of tagging
  every range `Other`.

### Changed

- **`march fmt` keeps a run of imports, or a run of capability declarations,
  tight.** Every top-level declaration used to be separated by a blank line,
  which turned a block of eight imports into eight paragraphs. A run of
  `import`/`alias`, or a run of `needs`/`cap`/`proof cap`, is now emitted with
  no blank lines inside it; the blank line at the boundary of the run, and
  between everything else, is unchanged. Imports and capabilities count as
  different runs, so the two blocks stay separated from each other.

- **Refinement violations now name the offending parameter and callee, and
  underline that argument.** The message opened with a bare "argument does not
  satisfy precondition `_ != 0`"; on a call with several arguments that does
  not say which one, and since the predicate's binder is usually the anonymous
  `_`, no other part of the message identified it either. It now reads
  ``argument `d` of `safe_div` ``, and a second labelled span underlines the
  argument itself rather than the whole call. The solver's counterexample
  (`e.g. n = -1`), which only appears when the failing model has a free
  variable, is unchanged.

- **Linearity errors now point at the earlier consumption site, not just the
  reuse.** "The linear value `token` is used more than once here" told you the
  value was already gone but not what took it, leaving the reader to find the
  first use by hand, which on a long function is the entire search. The
  diagnostic now contains a second labelled span: ``​`token` was already consumed
  here``. Attribution is path-correct: match arms are mutually exclusive, so
  consuming the same value once per arm stays legal, and a double-use inside one
  arm is labelled against that arm rather than a sibling that never ran.
- **`cap verified` now rejects an inert `interface`-signature refinement as an
  error instead of only warning.** A refinement written on an `interface`
  method's own signature (e.g. `fn run : a -> {Int | _ > 0} -> Int`) has
  always been inert (the refinement checker never reads a method
  declaration's type, so no call site is obliged and no body may assume it)
  and has warned about it since 2026-07-30. Under `cap verified`, with its whole
  promise of "if it compiles, it is proved," that silent-no-op shape is now a
  compile error instead, matching how the capability already escalates every
  other undischarged obligation. Outside `cap verified` the behavior is
  unchanged (still a warning). See
  `specs/progress/2026-08-03-cap-verified-interface-signature-decision.md`.

- **`derive Json`'s generated `from_json` now returns
  `Result(T, Json.DecodeError)` instead of `Result(T, String)`, a
  breaking change for any caller matching on the old bare-`String` error.**
  `Json.DecodeError(message, path, byte_offset)` contains a JSONPath-style
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
  substring matching. A leading `->` queries by return type only, and now
  matches regardless of what letter that variable uses in an entry's full
  signature (e.g. `--type="-> Option(a)"` finds `Option.map`; its full
  signature is `Option(a), (a -> b) -> Option(b)`). Malformed type queries
  are now reported as errors (including a hint that arguments are chained
  with `->`, not the `,` search results print them with) rather than
  silently returning loose matches. The on-disk search-index cache format
  bumped (version 3): a cache built before this rewrite is now correctly
  treated as stale and rebuilt, instead of `--type` silently returning no
  results indefinitely.

### Changed

- **The event-loop HTTP server is now selectable at RUN TIME, not build time.**
  Both server implementations have always been compiled into every March
  binary (`march_http_evloop.c` is unconditionally in the runtime link), but
  reaching the faster one required recompiling your program with
  `MARCH_HTTP_EVLOOP=1` set at *build* time, so in practice the faster server
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
  synchronous I/O (a blocking DB call) stalls every other connection on that
  thread. Enable it for I/O-light, high-concurrency workloads; leave it off if
  your handlers block.

### Fixed

- **Syntax highlighting broke on any file using a dotted module name.** The
  tree-sitter grammar accepted only a single-segment `mod Name do`, so
  `mod Mgrep.Search.Stream do` failed at line 1 and every construct after it
  was highlighted as an error. Six constructs the compiler has long accepted
  were missing from the grammar entirely: dotted module names, `import` /
  `alias` / `needs` / `cap` declarations, `pfn` and `ptype`, refinement types
  (`{ Int | _ > 0 }`, including the binder form), qualified type paths
  (`A.B.Mode`), and qualified calls (`A.B.C.go(x)`). Across a 199-file corpus
  of stdlib and real projects, files containing a parse error drop from 188 to
  150 with no file regressing. The remaining gaps are tracked in
  `specs/todos/2026-08-04-tree-sitter-grammar-drift.md`.

- **`march fmt` re-emitted `cap no_panic` as `opts no_panic`.** There is no
  `opts` keyword in March, so formatting any file with a capability
  declaration produced a file that no longer parsed, and `fmt` was therefore
  not idempotent on it.

- **~20 advertised LSP capabilities were dead code; all now answer.** References,
  rename, formatting, semantic tokens, folding ranges, signature help, call
  hierarchy, type definition, workspace symbol, document highlight, selection
  range, code lens and inline values each had a handler written as a
  method-string branch in `on_unknown_request`, where a request the library
  successfully *decoded* never arrives. Every one of them returned
  `TODO: handle this request` to the editor. The handler bodies were correct
  throughout; only the wiring was wrong, which is why reading the file showed a
  complete-looking implementation of every feature.

  Repaired by one generic bridge that recovers a decoded request's wire form,
  routes it to the existing dispatcher, and types the result back, rather than
  rewriting twenty handlers. A new protocol-level test drives every advertised
  capability and fails if any returns an error; its absence is what let these
  die unannounced.

  Each revived capability was then verified semantically against a fixture with
  known answers: `references` finds the declaration and both uses, `rename`
  produces three edits, `callHierarchy` finds the caller, `signatureHelp` reports
  `double(Int)`, rather than only checking that a reply arrived.

- **A file with no project root no longer hangs the language server.** Opening
  a `.march` file with no `forge.toml` above it made the workspace index walk
  the entire filesystem, so find-references and workspace-symbol never returned:
  impossible to tell, from the editor, from a server still thinking. The walk
  is now bounded (and warns when it truncates, since a silently partial index
  makes "not found" and "not indexed" look identical), and roots that are
  clearly not projects are turned down entirely.

- **Document symbols no longer describe the whole prelude.** The same leak as
  semantic tokens, in a different handler: `documentSymbol` folded the whole
  analysis, so a one-function file reported 6936 symbols containing line numbers
  from other files, and the editor's outline and breadcrumbs are built from
  that response. Found by running the server against a real 603-file project.

- **Semantic tokens no longer describe the whole prelude.** The builder traversed
  the entire analysis, which has the prelude injected, so it emitted a token per
  stdlib definition at line numbers from another file: 6949 tokens reaching line
  3512 for a 15-line document. Now filtered to the open document (15 tokens).
  Found only once the request became reachable: it had been wrong for exactly
  as long as it had been dead.

- **`march-lsp` implements the pull diagnostics it advertises.** It declared
  `diagnosticProvider`, but `textDocument/diagnostic` reached no handler, so
  every pull failed with `TODO: handle this request`, invisible because the
  push path covered the feature anyway. Also lowers `workspaceDiagnostics` to
  `false`: that is a separate promise (`workspace/diagnostic`, over every file
  rather than the open ones) which is still unimplemented, and advertising it
  would recreate the same bug one level down.

- **`march-lsp` now exits when the client tells it to.** The server handled the
  `exit` notification and then went straight back to reading stdin, so it hung
  until the editor's timeout killed it: `Jsonrpc2.run`'s `?shutdown` predicate,
  which is what actually ends the loop, was never passed. Every existing
  protocol test ended by closing the pipes, which stops the server via EOF
  whether or not `exit` is honoured, so none of them could see it.

- **The stdlib load manifest is now guarded against going stale.** A file under
  `stdlib/` missing from `stdlib_file_list` is loaded for export shapes only
  (its body never goes through inference in its caller's context), so a generic
  `Option`/`Result` it exports silently produces a **wrong value** at a concrete
  niche-eligible call site: no diagnostic, compiled builds only, different
  garbage each run. That class had been point-fixed three times by hand-adding
  whichever files someone happened to notice. The manifest moved to
  `lib/modules/stdlib_manifest.ml` and two tests now hold the invariant: it is
  exhaustive over `stdlib/`, and every entry has a file behind it. Intentionally
  lazy modules go in an explicit allowlist.
- **The LSP's TIR pass is now idempotent; performance insights no longer
  duplicate.** Re-running it on an analysis it had already processed appended
  its perf insights to a list that already contained them, so a function could
  report "stack-allocates 2 values" twice. The pass now returns immediately when
  the analysis it is given is already its own output.
- **A top-level `let`'s refined annotation is now checked, not silently
  ignored.** `let zs : {List(Int) | len(_) > 0} = []` at module scope
  previously produced zero obligations: the desugarer never normalized a
  qualified spelling in the annotation (`Desugar.desugar_ty` ran over a
  block-level `let`'s type but not a top-level one), and separately the
  checker's own top-level-`let` walk never invoked the annotation-vs-bound-expr
  check that a block-level `let` already gets. Both are fixed: the identical
  annotation on a `let` inside a function body and on a top-level `let` now
  behave the same way, including catching a real violation like the one
  above (`[]` does not satisfy `len(_) > 0`).

- **A qualified spelling inside a refinement predicate now enforces the
  contract**, e.g. `{List(Int) | List.length(_) > 0}` means exactly what
  `{List(Int) | len(_) > 0}` means (previously it parsed, typechecked, and
  silently enforced no rule; a warning added 2026-07-30 fixed the silence but
  not the capability gap). A narrow desugar slice now flattens a module-path
  call head found inside a `{T | …}` predicate the same way an ordinary call
  head is flattened, without running the full expression desugarer over the
  predicate. See
  `specs/progress/2026-08-03-refine-desugar-predicate-qualified-spelling.md`.

- **LSP semantic tokens: the `linear` and `affine` modifiers now follow the
  type system instead of use counts.** They were previously derived from how
  many times a name appeared (a binding mentioned exactly once was painted
  `linear`, one never mentioned was painted `affine`), so an ordinary
  `let x = 1` was highlighted in the editor as though the compiler had made a
  linearity guarantee about it. The modifier now comes from the three places
  the language actually states linearity: an explicit `linear` / `affine`
  qualifier, a `linear T` / `affine T` annotation, or a type declared
  `always_linear type`. Bindings where linearity is only inferred are left
  uncolored rather than guessed at: under-reporting shows no guarantee, whereas
  over-reporting claimed one that was never made.
- **A `match` arm now knows what the earlier arms excluded.** In the safe-wrapper
  idiom, `match xs do Nil -> Err(…) | _ -> Ok(mean(xs)) end`, the `_` arm could
  not see that `Nil` had been ruled out, so a `len(_) > 0` precondition in it
  never discharged. Every such wrapper in a standard library contained permanent
  unprovable debt, and, more damaging, `forge refine` could "fix" it by proposing
  `{List(a) | len(_) > 0}`, forbidding the exact input the function exists to
  accept. Reaching a later arm now contributes `not is_Ctor(s)` for each earlier
  arm where failure is decided purely by the tag, and a tag test on a list is
  translated onto the same length symbol the obligation uses
  (`is_Nil(xs) <-> len(xs) = 0`).

  An earlier arm licenses no facts if it contains a guard or a refutable
  sub-pattern, since either can fail with the tag still matching. `stats.march`
  goes from 0 to 4 proved; the one function that still abstains is the one
  needing `len > 1`, which these facts truly do not give.

- **A match arm's excluded-constructor fact now reaches a user `@[measure]`,
  not only the built-in `len`.** The `len`/`List` case above is discharged by
  a hardcoded `is_Nil(xs) <-> len(xs) = 0` translation, which does not exist
  for a measure the author defines. `build_measure_preamble` now also emits a
  base-case linking axiom for any axiomatized measure with a base-case arm body
  that is a literal, `(_ is Nil) x => size(x) = 0`, so the same exclusion fact
  connects for those too. A full stdlib `--refine-report` sweep output matches
  to the byte before/after (no current stdlib measure has this shape), so
  this closes the general case ahead of the next measure that hits it rather
  than fixing an observed regression.

- **`Logger.random_hex` no longer drops the contract it forwards into.** A
  private wrapper passed its argument straight to `Crypto.random_hex` (its
  parameter is `{Int | _ >= 0}`), without containing that requirement, so every
  caller of the wrapper went unchecked. Found by `forge refine` sweeping the
  stdlib.


- **Every LSP command was dead code; `workspace/executeCommand` is now
  dispatched.** The handler sat in `on_unknown_request`, but linol routes that
  method as a *known* client request to `on_req_execute_command`, which the
  server never overrode, so linol's default returned `null` for all of them.
  The runnable code lenses shipped earlier (`march.runTest`, `march.debugTest`,
  `march.run`, `march.debug`) had therefore never worked: clicking "Run test"
  had no effect and printed no message. `march.suggestRefinement` now applies its edit
  through `workspace/applyEdit`, so it lands in the buffer rather than on disk.
  Found by driving the real binary over stdio, which is the only place a command
  is observable; guarded by a protocol-level regression test.

- **A builtin passed as a first-class value (e.g. `apply1(file_read, path)`)
  no longer SIGBUSes when compiled.** The codegen arm handling "builtin used
  as a value" emitted the raw C-extern address instead of wrapping it in a
  proper closure. Once that address was bound to a local, a later call
  through it dispatched as if it were a heap closure struct, reading
  garbage off the code address and jumping to it. Builtins used this way now
  get the same closure + trampoline treatment as ordinary top-level
  functions used as values, with the trampoline's argument/return coercions
  sourced from the builtin's own C signature. Interpreted execution was
  never affected.

- **Interpreted `extern` calls no longer crash when an `Int` argument is even
  and at least 4096.** The post-call cleanup in the interpreter's FFI bridge
  decided which arguments to release by looking at the marshalled bit pattern.
  `Int` arguments are marshalled untagged, so any even value at or above the
  runtime's `IS_HEAP_PTR` floor looked the same as a pointer and got
  reference-count-decremented as though it were a heap object, dereferencing
  the integer and segfaulting. The bridge now tracks whether marshalling
  actually allocated each argument and drops only those. This mainly hit
  file-I/O externs, with arguments that are chunk sizes (`4096`, `65536`, …) and
  native handles cast to `Int`; an extern taking only `0`/`1` flags could
  never trip it. Because `forge test --coverage` runs on the interpreter, it
  showed up as coverage "breaking" on FFI file operations, but the crash was
  present with plain `MARCH_TEST_INTERPRETER=1` too and was unrelated to
  coverage instrumentation.
- **A function's own parameter refinement no longer vanishes when it mentions
  another name.** `fn pick(n : Int, i : {Int | _ < n})` calling `at(n, i)` left
  its precondition unproven: the assumption-side resolver mapped every name that
  was not the refinement's own subject to no value at all, and one such name discarded
  the entire predicate, so the verification condition consisted of its negated
  goal and no other clause. The identical fact arriving as a path guard
  (`if i < n do at(n, i)`) proved, which is what localised the bug to the
  channel rather than the solver. Cross-parameter and measure-bearing contracts
  (`{Int | _ >= 0 && _ < len(xs)}`, the canonical bounds contract) now forward
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
  its body, so a generic `Option`/`Result`-returning function in that module
  (e.g. `ConsistentHash.get`) reached monomorphization with an unresolved
  call-site type and fell back to a boxed representation, while the caller
  (compiled at a concrete, niche-eligible type like `Option(Int)`) expected
  the unboxed niche encoding and read the discarded box's heap address as the
  payload: wrong value, no diagnostic, compiled only; the interpreter was
  unaffected. Same bug class as the pre-existing `Deque`/`ClusterLoad` fixes;
  these six were the remaining stdlib modules with the same shape. The
  general class of bug (a *future* stdlib module can reintroduce this by
  omission) remains open; see
  `specs/todos/2026-08-01-lazy-stdlib-loading-boxed-vs-niche-representation-mismatch.md`.
- **A local helper with a name that collides with a top-level function no longer
  invents recursion.** The tail-call checker built its call graph by matching
  bare call names against the set of top-level function names, ignoring scope,
  so a call to a *local* helper with a colliding name forged a call-graph edge
  and fabricated a strongly-connected component. Because the entry module's
  declarations have the prelude spliced in, and prelude's `length`, `reverse`,
  `map` and friends are all written with a local `fn go` helper, any program
  with its own top-level `go` that called one of them was rejected with
  ``Function `go`: recursive call to `length` is not in tail position``, for a
  `go` that is not recursive, against a `length` it does not call. Binders now
  shadow: an inner `fn`/`let` for the rest of its block, a `match` arm's
  pattern inside that arm, and `let?`'s pattern in its continuation, both in
  the call graph and in the tail-position check itself, so a local that shadows
  a member of a truly recursive group is no longer mistaken for it either.

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
  An argument with a type that is itself another `derive Json` type composes a
  path across the boundary the same way a nested record field does (via
  `Json.decode_error_under`). No wire-format change: the encoder/decoder
  both use a flat JSON object with a `"tag"` key plus positional
  string-numbered keys (`"0"`, `"1"`, ...); there is no `"values"` array.
  The same pre-existing, separately-tracked `from_json` cross-type dispatch
  bug (recursive `from_json` calls resolve to whichever type derived `Json`
  most recently in the module) is unaffected by this change and remains
  open.
- **`derive Json`'s generated `from_json` for record types now reports a
  JSONPath instead of one opaque `"invalid JSON for T"` error, and no longer
  panics on a nested-record decode failure.** Each field is checked in turn,
  so a failure names exactly which field caused it (`Json.decode_error_to_string`
  renders it as e.g. `"$.age: missing field"` or `"$.name: expected String"`)
  and a field with a type that is itself another `derive Json` record composes a
  path across the boundary (`"$.inner.id: expected Int"`). Unknown JSON fields
  continue to be ignored (unchanged). `Json.get_field(kvs, key)` was added to
  `stdlib/json.march` in support. A separate, pre-existing bug (recursive
  `from_json` calls resolve to whichever type derived `Json` most recently in
  the module, not necessarily the field's own type) is unaffected by this
  change and remains open.
- **`derive Json`'s `to_json` no longer misencodes a record with a field that is
  itself another `derive Json` type.** `to_json(outer)` could panic with
  `record has no field '...'` when a record contained a field of another
  `derive Json`-derived type: the recursive encode call resolved back into
  the enclosing type's own encoder instead of the field's. Interpreter only;
  `from_json` is a separate, still-open issue.
- **A `use`-imported name in a nested module is no longer checked against an
  enclosing module's same-named function.** `resolve_call` (refinement
  checking) tried the lexical enclosing-module lookup before `use`-imported
  names, so a call inside a module that `use`-imports a name was rejected
  against an ENCLOSING function's contract, one the call never actually
  dispatches to at runtime. The lookup is now scope-aware: at each level of
  the enclosing-module walk, that level's own `use`s are consulted before
  falling outward, so a nested `use` correctly beats an enclosing definition
  while an outer module's `use` still loses to an inner module's own
  definition.
- **A refinement written in a `sig` or `extern` signature is no longer
  silent.** `sig Store do fn put : Int -> {Int | _ > 0} end`, and an `extern`
  function with a refined parameter or return type, both compiled with zero
  diagnostics while enforcing no constraint, reading exactly like a working
  contract. Both now emit a warning naming the declaration and the spelling
  that does work. The two messages differ intentionally: a `sig` refinement is
  simply never read, and the fix is the module's own `fn` definition; an
  `extern` refinement cannot be honoured *in principle*, because the callee is
  not March code, so the fix is a March wrapper containing the parameter
  refinement with the foreign result checked at run time. These shapes still
  compile: this makes the no-op audible, it does not make it an error.
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
  concurrent connections; every further connection was accepted by the
  kernel, showed the client a successful connect, and was then never read.
  With the default `ncpus*2` = 28 workers and 256 offered connections, 228 sat
  with unread bytes in `Recv-Q` indefinitely. The pool is now **elastic**: the
  worker count is a floor, and a worker about to park on a connection starts
  one more if it was the last idle one, up to `max_connections`. Measured at
  256 connections, order-swapped and repeated: **228 starved connections → 0**,
  and in-flight requests (throughput × latency) **27.7 → 253.7**. Reported
  average latency rises from 0.9 ms to 8.7 ms, which is the accurate figure: the
  old number only averaged the 28 connections that were being served at all.

  `HttpServer.max_connections` now does something. It had been accepted and
  discarded (`(void)max_conns`), which is part of why the real limit was
  invisible; it is now the limit the pool grows to, defaulting to 1024.

  Servers with many mostly-idle keep-alive connections should still prefer the
  event loop (`MARCH_HTTP_EVLOOP=1`), which costs 15–17% less CPU per request
  and does not spend a thread per connection.

### Added

- **The compiled HTTP server is covered end-to-end by the test suite**
  (`test/test_http_native.ml`, run by `run_stdlib.exe` and therefore by
  `dune runtest` and CI on both macOS and Linux). A total outage of the
  compiled server went unnoticed because the only end-to-end test of it,
  `test/test_http_native.sh`, was referenced by no dune rule and no CI
  workflow, and would have passed against two of the three bugs anyway.
  The replacement compiles at `--opt 2` (every bug was compiled-only),
  makes ~65 requests against one process (one crashed on request 2), checks
  response *bodies* with two routes echoing request-derived data (one
  returned a well-formed `200` with an empty body), checks the process is
  still alive and decodes `128 + signal` if not (one crash was silent), and
  covers the thread-pool and event-loop servers as equal peers. The only skip
  is clang truly absent; a broken server can never become a skip.

### Removed

- **`march_response_send_plaintext` is deleted.** It was a TechEmpower
  `/plaintext` fast path that hardcoded `Content-Length: 13` and the literal
  body `"Hello, World!"`, so reaching it required bypassing the user's March
  router entirely; the program nominally under benchmark would never have
  run. It had no callers and never had any. A general small-fixed-response
  path is separately not worth adding: the normal response builder is already
  zero-copy, with every iovec pointing at a March string or a static constant
  and one `snprintf` of Content-Length into thread-local scratch.

### Changed

- **The thread-pool HTTP server no longer pays for TCP corking on
  single-request batches.** `TCP_NOPUSH`/`TCP_CORK` were set and cleared around
  every response batch, but corking only earns its two `setsockopt` syscalls
  when the batch emits more than one `writev`; a single request is one
  `writev`, which the kernel already coalesces. Every non-pipelining client
  (browsers, curl, wrk: effectively all real traffic) took that path on every
  request. Measured on macOS/arm64: **−1.45 µs of ~32 µs CPU per request,
  −4.5%**, with `setsockopt` per request going 2.000 → 0.000. Throughput is
  unchanged, because on the measurement box the ~30k req/s limit is
  client/kernel-side rather than server-side.

- **The TFB HTTP benchmark harness measures the routes it claims to.**
  `bench/tfb/run.sh` drove wrk at `/plaintext` and `/json` while its March
  target was `examples/http_hello`, which routes only `GET /`, so both
  endpoints answered `404 Not Found` and every March number the harness printed
  was 404 throughput. There is now a real `bench/tfb/tfb_server.march` serving
  the same two routes as the Node and Python servers, the harness compiles it
  itself, and it aborts rather than reporting numbers if any server under test
  fails a route check. The `/json` body is serialized per request in all four
  servers (Node and Python previously wrote a buffer baked at startup, against
  March actually encoding), and all four now emit the same payload byte for byte.
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
  **compiled-only**: the interpreter was healthy throughout, which is why the
  interpreted `http_server` tests stayed green.

  1. `stdlib/websocket.march` re-declared `Conn`, `Header` and `Upgrade` as
     structural copies of the `HttpServer`/`Http` types, "mirroring" them
     because March has no imports. March has a single global type namespace, so
     these were always redundant; they became actively harmful once
     same-short-name types in different modules started receiving globally
     unique constructor tags. `HttpServer.Conn`'s tag moved off 0 while the C
     runtime's `march_conn_from_parsed` still wrote tag 0, so the value it
     given to the pipeline matched no arm. The duplicates are removed, and
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

  Note that `test/test_http_native.sh` (the only end-to-end test of the
  compiled HTTP server) is wired into neither dune nor CI, which is why a
  total outage of the built-in server went unnoticed.

### Added

- **JsonStream**: streaming JSON tokenizer: resumable chunk-fed parsing with
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
  gap; no SIMD/C scanner was added, since the measurement showed one
  would not help.

- **`@[vectorize]` / `@[vectorize(warn)]` function attribute.** `NativeArray.map`/`map2`
  have had a silent auto-vectorization fast path for a while: whether it actually
  fires depends on how the callback closure is used, with no feedback if it doesn't.
  This attribute turns that into a checked compile-time contract: `@[vectorize]` on a
  function is a hard compile error if its `NativeArray.map`/`map2` calls wouldn't
  actually vectorize; `@[vectorize(warn)]` reports the same problem as a warning and
  lets the build continue. Two specific diagnoses are distinguished: a callback
  that isn't safe to inline because it's reused rather than passed directly to the
  map/map2 call, versus (for `Float` targets) a callback with a type still generic
  rather than concretely `Float`, plus a hard error if the attribute is applied to
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
  that declares it: a `cap verified` module calling into an ordinary one does
  not make the callee's module strict, and nested modules do not inherit the
  capability. Modules that do not declare it behave exactly as before.

  `cap verified` now also escalates an undischarged **postcondition** (a
  function's own return-type refinement), not just a call-site precondition:
  the last place a fact was granted without obliging anyone. A return
  refinement the checker can neither prove nor refute is reported the same
  way a precondition is, naming the function, the predicate, and the reason;
  `@[trusted]` (see below) suppresses it there too. One limit worth knowing
  before relying on `cap verified`: a refinement written on an **`interface`
  method's signature** is not enforced at call sites (put it on the `impl`
  method's parameter, where it is; see the 2026-07-29 entries below), and an
  `impl` method's own parameter refinement is adopted only when its name
  unambiguously denotes one contract.

- **`@[trusted]`: a per-function escape hatch from `cap verified`.** `cap
  verified` used to be all-or-nothing: one obligation the checker could not
  discharge anywhere in the module forced dropping the capability entirely, or
  restating the fact with `assert`. Annotating a single function `@[trusted]`
  now accepts, as an assertion, any obligation *inside that function* the
  checker could not otherwise discharge (both a call-site precondition and
  the function's own return-type postcondition) without disarming
  `cap verified` for the rest of the module. It never suppresses a *definite violation*: a
  predicate the solver has proved can never hold is a bug in the annotation,
  not an incompleteness to wave through, so that case is still reported
  exactly as before, and it is scoped strictly to the annotated function: an
  ordinary sibling in the same `cap verified` module still escalates.
  `--refine-report`'s headline now has a fourth column, `N trusted`, counted
  separately from `proved` so a reader can tell how much of a module's
  "verification" is an assertion rather than a proof. Putting `@[trusted]` on
  a function in a module that does not declare `cap verified` warns, since the
  attribute would otherwise silently have no effect.

- **`--refine-report`: the checked fraction of your refinements is now a
  number.** `march --check --refine-report file.march` prints how many
  refinement obligations were proved, violated, and skipped, with each skip
  attributed to one of five reasons (unreflectable predicate, unreflectable
  subject, sort conflict, float-sort gate, solver undecided). Two slices are
  printed, "user code" and "user + stdlib", because the compiler prepends the
  whole standard library to every compilation. This exists because March reports
  a violation only when a predicate can *never* hold, which makes silence
  ambiguous between "proved" and "not checkable", an ambiguity that let
  `{List(a) | len(_) > 0}` ship enforcing no constraint while the suite stayed green.
  CI now ratchets in both directions: a limit on skips, read from the
  whole-program counts, *and* a floor on proofs, since a limit by itself is
  satisfied by a checker that raises no obligations at all. The floor is read
  from the **user-code** slice of a fixture where the single obligation is actually
  *proved*, so it falls to zero the moment that proof stops happening; a
  whole-program proof count would not have moved. So a change that stops
  checking things, with no visible sign, fails the build. Counts cover both precondition obligations
  raised at call sites and postcondition obligations (a function's own return
  refinement); see the Fixed entry below.

- **A `List.length` guard now discharges a `len` refinement obligation.** The
  refinement checker treats `List.length` as an alias of the `len` measure, so
  an ordinary runtime guard (`if List.length(ys) > 0 do head(ys) else … end`)
  *proves* the precondition of `fn head(xs : {List(Int) | len(_) > 0})` instead
  of leaving it unprovable and silently skipped. A contradictory guard
  (`if List.length(ys) == 0 do head(ys)`) is now reported as a violation.
  Only the qualified `List.length` is aliased (a bare `length` is left untouched)
  and only when it is the standard library's own, identified by the stdlib
  sources the compiler actually loaded (so it works the same from a repo
  checkout, an installed `share/march`, or a `MARCH_STDLIB` pointing anywhere).
  The alias is withdrawn for the whole module if anything could make that
  spelling denote a different function: a program defining its own
  `List.length` in any declaration form (a `fn`, a module-level `let`, an
  `extern` block, an interface or impl method), including a program where the
  entry module itself is *named* `List`, a vendored or forked `List`
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
  reported as a violation. `len` over a `String` is a **byte** count (`len("é")`
  is 2, not 1), so only byte-valued spellings are aliased: `String.codepoint_count`
  and its legacy alias `grapheme_count` count codepoints and are intentionally left
  as-is. `string_length` is left untouched too, for a different reason: it is a byte
  length today (it lowers to `march_string_byte_length`, and `string_length("é")`
  is 2), but its *name* reads like a character count, so an alias written now
  would silently become unsound if the name were one day corrected to match. Use the
  unambiguous `String.byte_size` in a guard. The same shadowing rules apply: the alias is
  withdrawn for the whole module if a program defines its own `String.byte_size`
  (unless it is the standard library's own, by the identity above), rebinds
  `String` via `alias`/`use`, or binds the name `string_byte_length` itself,
  whether as a declaration, an import, a `let`, or a parameter. Also fixes a
  related gap: a guard mentioning a string length in a *path
  condition* reflected to a symbol unrelated to the one the contract used, so the
  two could never meet.

### Fixed

- **`char_from_int` now returns the same byte interpreted and compiled.** It is
  a byte constructor, the one-byte string `n & 0xFF`, which is what the
  compiled runtime always did, but the interpreter clamped to ASCII and returned
  the **empty string** for any `n > 127`, with no error. The same program
  therefore produced different output depending on how it was run, and anything
  built on a real byte silently lost data interpreted: `Uri.decode("caf%C3%A9")`
  returned `"caf"` in the interpreter and `"café"` compiled. Msgpack's raw-byte
  walk, `Http` header decoding and `Gen`'s char-list builder were affected the
  same way. Wraparound is part of the contract and matches the runtime: `256`
  yields byte 0, `-1` yields byte 255. `byte_to_char` is unchanged and still
  reports an out-of-range argument as an error: it builds the same byte, but
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
  in March's flat, global module namespace, so calls like
  `remove_checksum(x)` resolved against the stdlib module instead of the
  file's own, and the example failed to typecheck (`Module 'Crypto' does not
  export 'remove_checksum'`) under both the interpreter and the
  interpreter-vs-compiled oracle sweep. Renamed the example's module to
  `SecretCode`; no compiler change, since the global-namespace behavior is
  by design (see `specs/lang` module system docs).
- **A nested constructor pattern over a type with a short name shared with
  a stdlib type (e.g. `match rows do Cons(Row(fp), rest) -> ... end` where the
  user's own `Row` type collides by name with `DataFrame.Row`) no longer
  panics `non-exhaustive pattern match` when compiled.** It matched correctly
  interpreted; a destructured sub-pattern's erased type meant compiled codegen
  could pick the wrong same-named type's constructor tag.

- **`Json.parse` now accepts `\uXXXX` escapes.** The escape decoder handled
  only `\" \\ \/ \n \r \t \b \f` and rejected everything else, so
  `Json.parse("\"\\u0041\"")` failed with "unknown escape sequence" on input
  that is valid per RFC 8259 §7, and that most serializers emit for any
  non-ASCII character. `\uXXXX` is now decoded and encoded as UTF-8, including
  surrogate pairs (`\uD83D\uDE00` → one astral code point). A surrogate that
  is not part of a well-formed pair, a `\u` with fewer than four hex digits,
  and a `\u` with a non-hex digit are all rejected with a message naming the
  problem.

- **A registry dependency now works for archive tasks, and brings its own
  dependencies with it.** Three gaps in `registry = "forge"` handling, all
  found while releasing scroll, which builds and tests green, then failed the
  moment its own `forge scroll.serve` task ran:

  - **Archive tasks saw no lib path for a registry dep.**
    `Archive_store.dep_lib_paths_for_archive` matched path and the three git
    forms then fell off a `| _ -> []`, so `RegistryDep` contributed no paths.
    `Cmd_build.dep_to_lib_paths` (which backs check/build/test) handled the
    same case, which is why a package could pass every check and still fail at
    run time with `Unknown module` for everything the dependency provides. The
    match is now exhaustive with no wildcard, so a future dep form is a compile
    error rather than a silently empty search path.

  - **`forge deps` did not fetch a registry package's own dependencies.**
    Resolution ran phase 1 (path/git, BFS) then phase 2 (registry, version
    solve) once each, and phase 2 recursed only into *registry* children,
    so registry → registry worked but registry → git/path did not, and a
    registry package's git dependency was never installed. The two phases now
    alternate to a joint fixpoint; the existing nearest-wins name dedup both
    preserves precedence and terminates the alternation.

  - **The CAS reused an install from the wrong source.**
    `~/.march/cas/deps/<name>` is keyed by dependency name only, and
    `install_dep` treated "directory exists" as "correctly installed", so
    switching a dependency between registry and git reported `already
    installed` over the previous source's content and then failed with `fatal:
    not a git repository`. A git install is now reused only when its `origin`
    matches; otherwise it is re-installed. (Two projects wanting the same
    package at different revs still share one directory; fixing that means
    keying the path by source, tracked in
    `specs/plans/2026-07-30-forge-registry-dep-gaps.md`.)
- **A selector-less `use X.List` no longer withdraws the `List.length` measure
  alias when its target cannot possibly provide a `length`.** The rebinding
  gate used to treat `use Extras.Deep.List` (anywhere in the compilation
  unit, including a `MARCH_LIB_PATH` dependency's internals) as a competitor
  purely because the path ends in `List`, silently turning every
  `{List(a) | len(_) > 0}` proof discharged by an ordinary
  `if List.length(ys) > 0` guard into a skip, program-wide (measured: one such
  `use` in a dependency flipped an entry program from `1 proved` to `1 skipped
  (alias-withdrawn)`). The use's target is now resolved and checked, the way
  glob imports already were: the alias persists only when every module the
  path could denote is shown to provide no member with the aliased name;
  re-exports (`use Y.{length}`), unenumerable globs inside the target, and
  unresolvable paths all still withdraw, as does `alias … as List` /
  `import X.{List}`. Same treatment for `String.byte_size`.

- **The `alias-withdrawn` explanation now follows a guard laundered through one
  `let`.** Under `cap verified`, `let n = List.length(ys)` followed by
  `if n > 0 do head(ys)` (where something in the compilation unit has
  withdrawn the `List.length` alias) used to report the generic
  `solver-undecided` text, pointing at z3 and advising the exact guard the
  author had already written. It now names the withdrawal and the binding that
  caused it, exactly as the direct `if List.length(ys) > 0` spelling already
  did. The verdict is unchanged (the obligation is still skipped); only the
  explanation improves. One `let` level only, and the attribution stays
  intentionally conservative: a guard laundered through a chain of `let`s, a
  guard on a different collection, or a guard where the laundering name (or
  collection) was rebound in between all keep the accurate general message.

- **An `impl` method's refinement is no longer adopted when a `use` in the same
  module imports its name.** An `impl` method's parameter refinement becomes a
  contract every caller must satisfy only when the method name unambiguously
  denotes it. That test looked at sibling `fn`s and other `impl`s, but not at
  imports, so `use Other.{run}` beside `impl Runner(Box) do fn run(b, k :
  {Int | k != 0})` left `run` looking unambiguous, and depending on
  declaration order, a call the import resolves elsewhere was checked against a
  predicate it never touches (the false positive), or a call that really does
  reach the impl was checked correctly. Refinecheck cannot see that order
  distinction, so imports now compete for the name unconditionally: in the
  first ordering this removes a wrong rejection, in the second it trades a real
  check for silence: the intentional direction, since a lost proof costs
  silence while a wrong fact rejects correct code. A glob (`use Other.*`, a bare `import Other`, or
  `import Other, except: […]`) names a module the checker cannot see at that
  point, so it withdraws every `impl` method contract in that module, the
  conservative direction, since the cost is silence rather than a wrongly
  rejected program. `use Other` with no selector binds the module, not a bare
  name, and withdraws no contract. Withdrawal is symmetric: a withdrawn contract
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
  module-qualifiable at all: `Bar.greet(1)` does not resolve for any module,
  entry or nested. Call interface methods unqualified.

- **A refinement in an `interface` method signature no longer goes silently
  unenforced.** `interface Runner(a) do fn run : a -> {Int | _ > 0} -> Int end`
  parses and typechecks, and the predicate is never read: no call site is
  obliged by it, and no method body may assume it. Nor does it survive the
  front end; when a default method is injected into an `impl`, the synthesised
  function keeps no annotations from the signature. So it is a *missing* check
  rather than an unsound one, but a silent one, and the contract reads exactly
  like a working one. It now warns, naming the method and the spelling that
  works: the refinement belongs on the corresponding `impl` method's own
  signature, where a return refinement is always checked and a parameter
  refinement is enforced when the method name is unambiguous (exactly one
  `impl` defines it and no top-level `fn` shares the name). Following that
  advice needs no change to the interface: the typechecker accepts a refined
  `impl` parameter against a plain type in the signature. Making the interface
  signature itself enforce, so it obliges every call dispatched through the
  interface, remains open.

- **A qualified spelling inside a refinement predicate no longer goes
  silently unenforced.** `{List(Int) | List.length(_) > 0}` parses, typechecks,
  and checks no constraint: the `List.length`→`len` alias keys on the dotted variable
  the *desugarer* produces, but refinement predicates are never run through the
  expression desugarer, so inside a predicate the name stays a field-access
  chain, the alias never fires, and the obligation is skipped, invisibly,
  since skipping is silence by default. The contract reads as working and does
  not work. It now warns, naming both the spelling found and the bare measure
  that does work (`len`); the same applies to `String.byte_size`. This is a
  warning rather than an error on purpose: the shape compiles today, so
  promoting it would break working builds, and the bug is the silence, not a
  missing capability; the bare spelling `len(_) > 0` has always enforced the
  contract. Desugaring predicates so the qualified spelling means what it reads
  as remains open.

- **`--refine-report` now counts return-type refinements, not just call-site
  preconditions.** A function's own return refinement (`fn mk() : {Int | _ > 0}
  do 100 end`) previously went through `check_post`, which discharged the
  obligation (proving it, reporting a violation, or silently giving up) without
  recording it anywhere, so `--refine-report` undercounted by every return
  refinement in the program, and a function with its *entire* contract in its
  return type was invisible to the report. `check_post` now files an obligation
  at every exit (proved, violated, or skipped with a reason: unreflectable
  predicate, sort conflict, float-sort gate, or solver-undecided), tagged with
  a new `kind` (precondition vs. postcondition) so the two can be told apart;
  `--refine-report` prints a `by kind` breakdown line under each slice's
  headline. Behaviour-neutral: no program newly errors, and `cap verified` still
  escalates only precondition obligations (postcondition escalation is a
  separate follow-up). `stdlib/list.march`'s `--refine-report` limit is
  unchanged at 28 skipped (it has no refined return types).

- **A refined annotation on a `let` is now checked against the expression it
  annotates, instead of being believed.** `let ys : {List(Int) | len(_) > 0} =
  []` used to compile: the annotation entered the refinement checker's scope
  unconditionally, so it became a *fact* about `ys`, and a later call needing a
  non-empty list was reported **proved**, off an assumption no proof had
  established. `cap verified`, with its assumption "if it compiles, it is proved",
  accepted such a module. This was the one refined position in the language
  that obliged no one; every other (a parameter at a call site, a return
  refinement, an `impl` method parameter) is checked somewhere.

  The obligation is the ordinary one, discharged by the same infrastructure that
  checks a call's argument against a parameter's precondition, and it keeps the
  same definite-failure stance: an annotation the checker can neither prove nor
  refute is **skipped**, never reported, so correct-but-undecidable code is not
  newly rejected. An unproven annotation does, however, now **grant no fact**:
  so `let ys : {List(Int) | len(_) > 0} = zs` for an opaque `zs` leaves both the
  annotation and any call relying on it skipped, rather than proving the call
  off an assumption the binding never established. All three spellings of the
  refined value behave alike (`_`, a declared binder, and the bound name
  itself); the bound-name spelling at `Int` was previously not resolved at all
  and is now checked too.

  **This can turn a program that compiled into one that does not**, namely any
  program containing a `let` annotation that is actually false, which is the point.
  No such annotation exists anywhere in the stdlib or the conformance corpus, so
  no in-tree code changed behaviour. Bracketed by
  `specs/lang/types/accept/t130_refine_let_annotation_checked_and_composes` and
  `specs/lang/types/reject/t131_refine_let_annotation_false`.
- **The `(`-led-statement fix now also applies after a literal.** The initial
  fix keyed the retag on a *value-ending* token (an identifier, a `)` or a
  `]`), but the call rule takes an `expr_field`, which a bare literal also
  reduces to, so `let _ = 1` followed by a line holding only `()` was still
  glued into `1()`. Unlike the identifier case this never reached the
  closure-ABI indirect call (a literal has no receiver to load a function
  pointer from): codegen emitted **invalid LLVM** (`declare ptr @<lit>()`)
  and clang rejected it with "expected function name", so the build failed
  with a diagnostic pointing at generated IR rather than at the offending
  source line. Interpreted, it raised `applied non-function value: 1`. The
  statement decision now uses a wider "ends an expression" predicate that
  includes `Int`/`Float`/`String`/`Bool`/atom literals; the narrower
  value-ending test still drives the curried-call guard's paren
  classification, so `f(1)(2)` diagnostics are unchanged.

- **A statement starting with `(` is no longer glued onto the previous line as
  a call.** A block line holding only `()`, or any parenthesised/tuple
  expression, following a line that ended in a value (an identifier, a `)`, a
  `]`) was parsed as that value's argument list. The common shape was a
  function that discards a parameter and returns unit:

  ```march
  fn f(a) do
    let _ = a
    ()          -- parsed as `let _ = a()`
  end
  ```

  which silently *invoked* the parameter. Interpreted this raised "applied
  non-function value"; compiled it went further wrong: codegen emitted the closure-ABI
  indirect call (load the function pointer from offset 16 of the receiver, then
  call through it), but the receiver was whatever value was passed in, so the
  binary jumped into a `String`'s character payload and crashed with
  `EXC_BAD_ACCESS` (exit 138) or `SIGSEGV` (exit 139) before running a line of
  user code. Both conditions were needed to trigger it, which is why it read as
  a codegen bug: without the discard there was no trailing identifier for the
  `(` to attach to, and with any other tail expression (`None`, `0`, a call)
  there was no leading `(` on the next line.

  The newline-separates-statements rule was already specified for the
  `f(1)`⏎`(g(2))` case; it now applies after *any* value-ending token. A call
  with its `(` on the same line as its callee, and a call with an argument list
  spanning several lines, are unaffected.
- **A capture-free closure used repeatedly in the REPL no longer leaks an
  allocation per use.** Passing a lambda that captures no variables, or a
  top-level function used as a value, to something that calls it (a
  higher-order function, `task_spawn`) allocated a fresh closure object on
  every materialization and never freed any of them, so a loop at the REPL
  prompt grew the live-object count in lockstep with its iteration count.
  Compiled programs were never affected: there, such a closure is a single
  immortal object shared by the whole program. Both capture-free shapes are
  now released, and compiled output is unchanged down to the byte.

- **`forge test` now resolves transitive dependencies.** `forge build` and
  `forge check` walk the dependency graph transitively: if your project depends
  on `B` and `B` depends on `C`, then `C`'s `lib/` is on `MARCH_LIB_PATH`.
  `forge test` built its own path from the *direct* deps only, so a test calling
  into a transitive dependency's module failed with "Unknown module ..." even
  though the identical call in `lib/` typechecked. `forge test` now uses the same
  transitive walk (with the same nearest-wins shadowing for same-named deps),
  applied to the test scope: `deps` + `dev-deps` + `test-deps`.

- **A refinement with a predicate that measures the refined value itself is now
  enforced for user ADTs.** A contract like `{Tree | size(_) > 0}`, where `size`
  is a user `@[measure]` over `Tree`, checked *no property*: the argument being
  passed was discarded and the predicate decided against an arbitrary tree
  instead, so `inner(Node(Leaf, 5, Leaf))` was not proved and `inner(Leaf)` (a
  real violation) was not reported. Both are now decided by the measure's own
  recursion axioms. The same measure applied to a *different* parameter
  (`{Int | _ < size(t)}`) worked all along, so the gap was invisible: a skip
  produces no diagnostic. Such contracts also now compose across a call
  boundary, like `len`-shaped list refinements: a caller with a parameter typed
  `{Tree | size(_) > 0}` can pass that very tree on. Only the caller's own
  promise is loaded, so a weaker contract (`size(_) >= 0`) still does not
  discharge a stronger callee, and rebinding or shadowing the name retires the
  fact. Note this can turn a program that used to compile into one that does
  not: a call the checker previously skipped in this position is now decided, so
  a real violation like `inner(Leaf)` becomes a compile error.

- **A refined parameter's own constructor-tag promise now applies inside its own
  body.** A function with a parameter typed `{Option(Int) | is_Some(_)}` could not
  pass that very value to another function requiring the same thing: the inner
  call's obligation was *skipped* rather than proved, because a caller-scope
  variable was always reflected as a fresh, unconstrained datatype value. The
  identically shaped *measure* contract (`{Tree | size(_) > 0}`) composed, so
  the difference was invisible: a skip produces no diagnostic. The caller's own
  tag promise is now loaded as an assumption over the same SMT term the
  obligation uses, for all **three spellings** of the refined value (`_`, a
  declared binder, the parameter's own name). Only the exact promised
  constructor is loaded: a caller promising `is_None(_)` still does not
  discharge a callee wanting `is_Some(_)` (the call stays skipped), and
  rebinding or shadowing the name retires the fact. As with the other
  composition fixes, a call the checker previously skipped in this position is
  now decided, so a real violation there becomes a compile error.

- **A refined list parameter's own promise now applies inside its own body.** A
  function with a parameter typed `{List(Int) | len(_) > 0}` could not pass that very
  list to another function requiring the same thing: the inner call's obligation
  was *skipped* rather than proved, because a measure over a caller-scope
  variable was always reflected as a fresh unconstrained symbol. The identically
  shaped `Int` version composed all along, so the difference was invisible:
  a skip produces no diagnostic. The caller's own predicate is now loaded as an
  assumption over the same SMT symbol the obligation uses, so contracts compose
  across a call boundary for `len`-shaped list refinements the same way they
  already did for scalars. Only the *caller's* promise is loaded, so a weaker
  contract (`len(_) >= 0`) still does not discharge a stronger callee, and
  rebinding or shadowing the name retires the fact. All **three spellings** of
  the refined value compose identically: the anonymous `_`, a declared binder
  (`{v : List(Int) | len(v) > 0}`), and the parameter's own name
  (`{List(Int) | len(ys) > 0}`), so renaming a binder cannot silently unwire a
  working contract.

  With the ADT-measure fix above and the constructor-tag fix below, this closes
  composition for every refinement shape: `Int`, `Float`, `Bool`, `String`
  `len`, record fields, the built-in list `len`, a user `@[measure]` over an
  ADT, and a constructor tag all compose. This is a distinct mechanism from a caller-established
  runtime **guard** (`if List.length(ys) > 0 do …`), which is unchanged: a guard
  is a test you write, a contract is a promise the caller already kept. It
  applies to **preconditions** only: a parameter's promise reaches calls in the
  body, not a refined return type. And a fact still does not survive a local
  `let` (`let u = 5` then `take_pos(u)` against `{Int | _ > 0}` is skipped), a
  pre-existing limitation for every type that this work does not change.
- **Capturing closures are no longer leaked, one allocation per
  materialization.** A lambda that captures a variable (`fn x -> x * k`)
  allocates a closure struct holding the captured values; no code released
  it. The caller side deferred to the callee ("the callee consumes the closure")
  while the callee never dropped it, so a loop that built one closure per
  iteration leaked one allocation per iteration: measured at 4,000,000
  allocations and ~125 MB peak RSS for a 4M-iteration loop, against ~2.9 MB for
  the equivalent capture-free loop. The two sides now agree: `$clo` is pinned to
  the owned convention in the borrow map, so a caller increments when the closure
  is still live after a call and transfers its reference when it is not, and the
  apply function releases it. The same 4M loop now stays at the ~2.9 MB floor.
  Capture-free closures are unaffected: they were already routed to a single
  immortal global per site and are intentionally left untouched.

  A **self-recursive** capturing closure no longer leaks either: its self-binding
  hands an alias a reference that used to be consumed only on the recursive
  path, so a base case that stopped using the alias dropped no reference. Fixed by
  releasing that reference explicitly wherever the self-binding goes dead,
  leaving the recursive path's existing transfer untouched.

  Not fixed: a truly capture-free closure (no captured variables at all)
  still leaks when materialized repeatedly from inside the REPL/JIT; natively
  such a closure is a single shared immortal object, but the REPL compiles each
  fragment as its own module and cannot safely share one.

- **REPL variable bindings (`let x = ...`, and the `v` last-expression-value
  binding) now correctly participate in reference counting.** Reading a
  heap-typed variable back from a later REPL line, or overwriting one,
  previously did no reference-count bookkeeping at all, a gap invisible
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
  a variable now handles being delivered more than once (it previously
  crashed reliably on the second delivery). All four are fixed and covered by
  new regression tests.

- **`cap no_panic` and `cap verified` now cover the whole module, not just its
  `fn`s.** Both passes traversed only `fn` and nested `mod` declarations and
  ignored everything else, so a capability directive made no claim about code
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

  **This can newly fail a build that has no `cap` directive at all.** An
  obligation *shown violated* is reported regardless of any capability, so a
  call that definitely breaks a precondition (inside an `impl` method body or a
  top-level `let`) is now an error where it used to be silence. Those are true
  positives and the intended outcome, but they are a real behaviour change for
  ordinary modules, not just for capability-declaring ones. (The standard
  library is unchanged: its `--check` output matches to the byte before and
  after.) Witnessed by `specs/lang/types/{accept/t119,reject/t120}`.

- **A refinement on an `impl` method's parameter now obliges its callers, or
  binds no one.** Widening the walk above created a subtler bug: the checker
  *assumed* an impl method's parameter refinements while walking its body, but
  the table of known contracts still recorded only `fn`s, so no caller was at any point
  required to establish them. `fn run(b, k : {Int | k != 0})` made `m / k`
  provable inside a `cap no_panic` module while `run(Box(4), 0)` compiled
  cleanly and divided by zero at run time. Impl-method signatures are now
  registered, so the obligation lands on the call site. Registration is
  intentionally conservative: a method name is adopted only when no `fn` in the
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
  persisted unstripped, resolved to no target, and silently raised no obligation,
  while the identical call in a sibling `fn` was reported. That match is now
  exhaustive too, and also covers `interface` defaults, `app` hooks, `test`,
  `setup`/`setup_all`, `describe` and actor `@invariant` expressions.

- **The `List.length` / `String.byte_size` measure aliases were disabled for
  *every* March program, by one `import` in the standard library.** The gates
  that withdraw those aliases are unit-global, and a glob import (`import X`,
  `use X.*`) used to withdraw on its mere presence, on the reasoning that it
  might carry anything. But the compiler prepends the entire standard library to
  every compilation, and `stdlib/system.march` contains a single
  `import Process`, so every March program compiled since the feature shipped
  had the aliases withdrawn, and a `List.length` guard proved no fact anywhere.
  No check caught it: a withdrawn alias means the obligation is *skipped*, and a
  skip exits 0 exactly as a proof does, so the whole test suite stayed green
  while the feature was inert. A glob now resolves its target and withdraws only
  if that module actually provides a competing member (an unresolvable path
  still withdraws, and a real competitor reached through a glob is still caught).
  A second guard was added alongside it: a `use`/`alias` competes for the bare
  module name only when it is the *program's*, never the standard library's own,
  the same span exclusion the member-definition side always applied. The two
  are conjoined, so a glob withdraws only when it is your code *and* its target
  really contains a competitor. The blast radius is why the obligation *floor* in
  CI was moved onto a fixture with a count that actually drops when this happens.

- **`cap verified`: a length guard that "silently stopped counting" now reports it,
  instead of blaming the solver.** The `List.length` / `String.byte_size` /
  `string_byte_length` measure aliases are withdrawn for the whole compilation
  unit whenever anything in it could make the spelling denote something else,
  by design, since under the default stance the only cost is a missed proof. In
  a `cap verified` module a missed proof is an error, and it read
  `solver-undecided: the solver proved neither the predicate nor its negation`
  on code containing exactly the guard the feature asks for. Both of its
  suggestions ("guard the call", "rewrite the predicate") were things the author
  had already done, because the real cause was a name binding somewhere else,
  a nested `mod Internal do mod List do fn length …` that is reachable only as
  `Q.Internal.List.length` and does not win at runtime, or an unrelated
  function's local `let string_byte_length = n + 1`, or, worst of all, a
  definition in a `MARCH_LIB_PATH` dependency the author never opened. Such a
  skip is now reported as `alias-withdrawn`, naming the spelling that lost its
  alias and pointing at the binding that took it. Attribution asks for causal
  relevance, not mere presence: the predicate must use the affected measure,
  **and** a positive path condition must apply the withdrawn spelling to *this
  call's own argument*, **and** the spelling must measure the same kind of value
  (list spellings for a list, the byte-length spellings for a String). So a
  guard on a different list, a `List.length` guard in front of a `String`
  contract, a guard on the `else` side (which *disproves* the predicate and,
  without the shadowing binding, reports a real refinement violation), and an
  unguarded call all keep the plain `solver-undecided` message: in each case
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
  miscompile was found or is claimed by this fix: it closes a latent
  correctness gap in the oracle (and a companion test-integrity gap where a
  native regression test passed regardless of whether the pass it targeted
  ran at all).

- **`cap no_panic`: an unreflectable divisor refinement is no longer accepted as
  a proof.** The division-safety check treated "this predicate is outside the
  checkable fragment" as a discharged obligation, which made a *meaningless*
  refinement more permissive than no refinement at all: `d : Int` correctly
  errored, while `d : {Int | is_prime(_)}` (a predicate the checker cannot
  reflect) passed having proved no fact. Such a divisor is now reported,
  failing closed exactly as the "solver unavailable or undecided" case already
  did. A path condition that truly proves the divisor non-zero (a `when
  d != 0` guard) still discharges the obligation. Only `cap no_panic` modules
  are affected; a refinement the checker *can* reflect is unchanged.

- **`cap no_panic`: a divisor refinement that *proves* the divisor non-zero is
  no longer rejected for being written unusually.** Closing the hole above
  over-corrected: the check reported anything its own reflection could not
  translate, and that reflection turned down multiplication unless one factor was a
  literal. So `fn scale(d : {v : Int | v * v > 0})` (a predicate that is
  *exactly* `d != 0` over the integers, and that the solver determines instantly)
  was rejected with "outside the checkable fragment", even though the same
  program ran correctly without the capability. Such predicates are now sent to
  the solver rather than turned down unread. The stance is unchanged: the checker
  tries harder to discharge, it does not accept what it cannot decide. A
  predicate that reflects but proves no fact (`v * v >= 0`, true of every
  integer) is still an error, as is one the solver cannot settle, and one it
  cannot reflect at all. Separately, a divisor guarded on the `else` side of a
  condition (`if d == 0 do 0 else 10 / d end`) is now recognised as safe;
  negated path conditions were previously dropped by the syntactic fallback
  while the solver route handled them. Witnessed by
  `specs/lang/types/{accept/t121,reject/t122}`.

- **`cap no_panic`: a guard or refinement no longer contains over to a *different*
  variable that happens to share its name.** The check identified the divisor by
  name only, so rebinding that name inside the guarded branch left the outer
  fact in force. All four of these passed `--check` with exit 0 and then panicked
  at run time with "division by zero": the failure the capability exists to
  prevent:

  ```march
  if d == 0 do 0 else (let d = 0; 10 / d) end     -- else side
  if d != 0 do (let d = 0; 10 / d) else 0 end     -- then side
  if d == 0 do 0 else ap(fn d -> 10 / d) end      -- lambda parameter
  if d == 0 do 0 else match o do Some(d) -> 10 / d ... end   -- match binder
  ```

  A name rebound by a `let`, a local `fn`, a lambda parameter, a `let?` pattern
  or a `match` pattern now retires everything known about the outer variable of
  that name: its guard, its refinement, and its `let` value. Correct programs
  are unaffected: `let d = 5` followed by `10 / d` is still accepted (the new
  binding replaces the old fact rather than only erasing it), and a binder
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
  enclosing scope are unaffected by this fix and still leak; same open
  issue as the named-function capturing case below, tracked in
  `specs/todos.md`.
- **Calling a variable that contains a zero-argument function value (`let zf =
  answer; zf()`) is now a clear `--check` error instead of a runtime crash.**
  Assigning a top-level (or local) zero-arg function to a plain variable and
  then calling that variable used to typecheck silently and then crash with
  a segfault when compiled. It now reports `` `zf` is not a function; it
  has type `Int`. Remove the `()` and use `zf` directly.`` at compile time.
  The same fix also catches the more general `let x = 5; x()` case.
- **A closure or local function's parameter now shadows an imported function
  of the same name.** `import Logger` makes stdlib's `Logger.i` available as
  the bare name `i`; a nested `fn go(i, acc) do ... end` then compiled every
  use of its own `i` to that function's address instead of the parameter.
  Any binder with a name that collided with an imported function was affected, so
  a program could silently pass a function where it meant a value, for
  example `Bytes.get(b, i)` receiving a code address as its index. This hit
  depot's Postgres wire decoder (its `read_cstring` has exactly this
  shape), making every compiled database connection fail with
  `Bytes.get: index out of bounds`. Native backend only; the interpreter
  always resolved these correctly.

- **A program that repeatedly passes a named function as a value no longer
  grows memory without bound.** Materializing a top-level function as a
  first-class value (assigning it to a variable, passing it as a callback,
  storing it in a list or tuple) allocated a new heap object every time,
  even when the closure captured no variables, a real leak in any loop that
  repeatedly took a function value. Such closures are now backed by a
  single shared object per function instead of a fresh allocation each
  time. Measured on a 4,000,000-iteration loop: allocations for the
  materialization step went from 4,000,000 to 0 and peak memory from
  125.4 MB to 2.9 MB, with identical program output before and after.
  Closures that capture a variable (`fn x -> x * k` where `k` comes from
  the enclosing scope) are unaffected by this fix and still leak; tracked
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
  Scope is unchanged: ASCII only, non-ASCII bytes pass through untouched.

### Documentation

- **The refinement-types pages now state what is *not* checked, and two
  over-claims were corrected.** `specs/lang/refinement-types.md` gained an "Open
  holes" list and `docs/refinement-types.md` a `cap no_panic` section covering
  what that capability actually promises. Corrected: "every declaration form is
  covered" was true of *raising* obligations but read as "a refinement on an
  `impl` signature is enforced", which is true only when the method name
  unambiguously denotes one contract; and this changelog's claim that modules
  declaring no capability were unaffected was false, since an obligation *shown
  violated* is reported regardless of any capability. Both pages also quoted an
  `alias-withdrawn` diagnostic with wording that no longer matched the compiler's,
  found by re-running every published snippet. The residuals are now written
  down rather than left to inference: a refinement in an `interface`'s own
  signature is unenforced; the measure-alias gates are unit-global, so one
  competing binding anywhere (including in a `MARCH_LIB_PATH` dependency)
  disables the alias program-wide; postconditions are outside the obligation
  ledger, so `--refine-report` undercounts and `cap verified` silently permits an
  undischarged *return* refinement; and there is still no `@[trusted]` escape
  hatch.

- `stdlib/string.march` no longer claims the runtime has small-string
  optimisation. It had stated since 2026-03-19 that "strings of 15 bytes or
  fewer are stored inline without a heap allocation"; that was never true: every
  March string is a refcounted heap allocation with a 24-byte header. The header
  now also states clearly that `grapheme_count` counts *codepoints* despite its
  name, with the cases where the two differ.


### Changed

- The TIR optimizer reduces a tuple element access to its source value when
  the tuple was just constructed (`let t = (a, b) in t.0` behaves like `a`
  at the compiler level), the same optimization already applied to record
  field access. Removes the tuple allocation wherever a tuple literal is
  immediately destructured (e.g. `let (a, b) = (x, y)`). No runtime speedup
  was measured; this reduces emitted allocations/struct loads, not
  benchmarked wall-clock time.
- **`Toml.parse` allocates ~10x fewer strings.** Same character-list-and-append
  pattern as `Json.parse` had, but heavier: `Toml.parse` was allocating ~3.7
  heap strings per input byte, against JSON's 2.03 before its own rewrite. It
  is now a byte-index scanner, following the same template: bytes are
  inspected with `string_byte_at` (no allocation), tokens materialised with
  one `string_slice`. On a 340-byte document exercising tables, arrays, an
  inline table, and nested tables, compiled `--opt 2`: **allocs/byte 3.69 →
  0.37** (2,506,057 → 250,044 string allocations over 2,000 parses). Parsing
  is unchanged semantically; `TomlError` column numbers now count bytes
  rather than decoded characters, matching `Json.parse`'s existing behaviour.

- **`Yaml.parse` allocates ~5.4x fewer strings** (5.56 → 1.02 allocs/byte,
  361-byte document, 2,000 iterations), **`Xml.parse` ~29x fewer** (2.92 →
  0.10 allocs/byte, 616-byte document), and **`Regex` compile/match ~19x
  fewer** (compile: 5.82 → ~0 allocs/pattern-byte; match: 1.215 → 0.064
  allocs/input-byte): the same byte-index-scanner rewrite as `Json.parse`/
  `Toml.parse`, applied to the remaining pure-March parsers. `Uri.encode`/
  `decode`/`decode_query` (the only parts of `Uri` that had the per-byte
  pattern; `parse`/`to_string`/`merge` were already segment-based) go 4.0x
  fewer (2.96 → 0.73 allocs/byte). `Csv.read_all`/`each_row` were measured
  and left unchanged: already byte-at-a-time in the C runtime with no
  per-character March-level accumulation (0.106 allocs/byte). Parsing is
  unchanged semantically for all of these.

- **`Json.parse` allocates ~12x fewer strings and runs ~4.8x faster.** The
  parser used to begin with `string_split(src, "")`, exploding the document
  into one heap string per byte, so its cost scaled with the size of the input
  rather than with the number of strings in it: a 239-byte document holding
  ~20 strings cost 261 allocations per parse, 90% of them 7 bytes or smaller.
  It is now a byte-index scanner that inspects bytes with `string_byte_at` and
  takes one `string_slice` per token: **261 → 21 allocations per parse**, which
  is the number of strings the document actually contains. On a 1MB document
  holding 99,000 strings, one parse went from 1,100,041 string allocations to
  99,018; allocation now tracks the document's string count rather than its
  byte size. `Json.to_string` got the same treatment (a string needing no
  escaping is now returned as-is, allocating zero bytes), taking a combined parse
  + serialize round trip from 486 to 58 allocations per iteration and 1.10s to
  0.24s over 20,000 iterations. Parsing is unchanged semantically; the only
  visible difference is that a non-ASCII character in an error message now
  prints correctly instead of as a single mangled byte.

- **String interpolation is ~1.45× faster** and allocates no intermediate list.
  `"a${x}b${y}c"` now desugars to a plain `++` chain at every length, which the
  compiler merges into three-way concats, where it previously switched to a
  `string_join` over a cons list past a size threshold. Measured at seven
  segments over 2M iterations: 519ms → 358ms, with the eight cons cells per
  interpolation dropping to zero.

- **…and interpolating a `String` no longer costs a refcount pair per operand**,
  which closes the rest of that gap. `"a${s}b"` goes through `to_string(s)`,
  which for a String resolves to an identity, but the identity call was only
  removed *after* reference counting had already bracketed it with an atomic
  increment/decrement, leaving the pair stranded with no referent. The call is now
  elided during lowering, so no pair is created at all, and interpolation compiles
  to exactly the same code as the equivalent hand-written `++` chain.
  Allocation counts are unchanged: this was refcount traffic, not allocation.


### Added

- **`string_byte_at(s, i)`**: reads the byte at a byte offset as `0..255`, or
  `-1` when out of range, allocating zero bytes. Before this, the only ways to
  look at one character of a string from March were `string_split(s, "")` and
  `string_slice(s, i, 1)`, both of which allocate a heap string per character
  inspected, so every hand-written scanner in the stdlib paid an allocation
  per input byte just to decide what the byte was.

- **`String.index_of_from(s, sub, start)`**: substring search from a byte
  offset, returning the index in `s`'s own coordinates so it can be fed
  straight back in when tokenizing. Without it, scanning for successive
  separators means slicing off the tail and searching again, which copies the
  remaining bytes at every step and makes a full tokenize O(n²).

- **`NativeArray.map2_int`/`map2_float`/`to_float_arr`**: a two-array
  zip-with primitive (`f(a_elem, b_elem) = out_elem`, panics on length
  mismatch) and Int→Float widening helper, for numeric ops over two
  `NativeArray`s at once. `DataFrame.col_add_col` (column-column arithmetic)
  now uses these instead of round-tripping through `List.zip`/`List.map`.

- **The docs site gained full-text search on ⌘K / Ctrl-K.** Every page on
  march-lang.org, the guides, the cookbook, and all 114 standard-library API
  pages, is now searchable from one box, opened with `⌘K`, `Ctrl+K`, `/`, or
  the Search button in the nav. Results are grouped by area (Guide, Cookbook,
  Stdlib) and include in-page heading links, so `↵` jumps straight to the
  relevant section rather than the top of the page. The index is built by
  [Pagefind](https://pagefind.app/) as a post-build step over the generated
  site, ships with it, and needs no search service at runtime.

  The same box also does **standard-library symbol lookup**, which previously
  worked only from inside the API reference itself. Typing a function or type
  name (`push`, `to_string`, `List.map`) puts a "Standard library" group above
  the prose results, each entry showing its kind and signature and linking
  directly to the definition's anchor (`Array.html#fn-push` rather than the
  top of the module page). Symbols are matched on name only, exactly or by
  prefix, so multi-word prose queries return only prose results. The API
  reference pages keep their own `⌘K` for now.

  The index is committed at `docs/pagefind/` because march-lang.org is served
  by GitHub's own Jekyll running over `docs/`, which has no post-build hook,
  the same reason the generated stdlib API pages are committed. A CI check
  fails the build if a docs change lands without a regenerated index, since a
  stale index means the live search silently returns outdated results.

- **Session-type protocols gained a `stop` step to exit a `loop`.** A `loop
  do … end` protocol projects to the recursive µ-type `Rec X. S[X]` and,
  until now, had no way back out: every step inside the body, including
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
  parsed and type-checked while checking no constraint at all, so
  `fn needTrue(b : {Bool | _ == true})` accepted `needTrue(false)` and
  `fn sqrtish(x : {Float | _ >= 0.0})` accepted `sqrtish(0.0 -. 1.0)` in
  silence. `Bool` predicates now take the boolean operators against
  `true`/`false` (the bare-binder `{Bool | not _}` remains a parse error; write
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
  as the runtime safety net for arguments the checker skips. A list with contents
  the checker cannot see stays **unknown** and is skipped, never guessed. Note
  that an ordinary `List.length(xs) > 0` guard does not yet discharge the
  obligation: the runtime function and the `len` measure are not connected, so
  a guarded call is skipped rather than proved.

### Changed

- **Substring search is much faster.** `index_of`, `index_of_from`, `contains`,
  `split`, `replace` and `replace_all` now use a two-stage `memchr`+`memcmp`
  scan instead of testing every byte offset. Scanning a 1MB buffer for an absent
  needle went from ~809ms to ~21ms in `bench/string_scan` (roughly 0.5 GB/s to
  40 GB/s). `replace_all` additionally bulk-copies the spans between matches
  rather than one byte at a time.

- **Chained string concatenation allocates 50% as much.** `a ++ b ++ c` and
  longer chains are folded into three-way concats, so k parts cost
  `ceil((k-1)/2)` allocations instead of `k-1` and stop re-copying the growing
  prefix at every link. Measured 20% faster on a short-string building
  benchmark, with 23% less copying. Two-part `a ++ b` is unchanged.

- **`NativeArray.map2_int`/`map2_float` vectorize.** Extended the same
  compiler pass that lets `map_int`/`map_float` compile to real SIMD to also
  recognize `map2`'s two-array call shape: same eligibility bar, same
  boxing-free clone for a concrete-`Float` callback. Measured **~47x** on a
  5M-element benchmark (299 ms → 6.4 ms); previously slower than naive
  interpreted Python for the same operation, now beating hand-written OCaml.
  See `docs/simd-benchmarks.md`.

### Fixed

- **A measure over the refined value only worked under one of its three
  spellings.** In `{List(a) | len(_) > 0}` and `{v : List(a) | len(v) > 0}` the
  refined value reflected to a fresh unconstrained constant rather than to the
  call's actual argument, so the predicate was satisfiable at every call site,
  never a definite failure, and the contract silently checked no constraint, while
  the third spelling, naming the parameter (`len(xs) > 0`), worked. Two
  consequences, both silent: the `_` form the documentation teaches gave no
  enforcement at all, and renaming a parameter unenforced a working contract
  with no diagnostic beyond an incidental unused-variable warning. All three
  spellings now resolve against the same actual, as the string and
  axiom-measure paths already did.

- **`Json.parse` rejected JSON numbers with a signed exponent.** `1e-5`,
  `2.5E+10` and `1e-308` all failed with `invalid number: 1e`: the number
  scanner accepted `+`/`-` only in the mantissa position, so it stopped at the
  sign after the exponent marker and passed a truncated `"1e"` to
  `string_to_float`. The scanner now follows RFC 8259's grammar
  (`["-"] int [frac] [exp]`), accepting a sign immediately after `e`/`E`.
  `1-2` still parses as `1` followed by a trailing-character error, as before.

- **`Json.parse` accepted number forms JSON does not allow.** Shape is now
  validated during the scan instead of being left to `string_to_float`
  (`strtod` / `float_of_string`), which is more permissive than JSON: `1.` and
  `01` previously parsed and are now rejected, joining `+1`, `Infinity`,
  `0x10` and `.5`. This is a behavior change for input that was never valid
  JSON; anything conforming to RFC 8259 parses as it did before.

- **A module-qualified constructor pattern could silently never match when
  compiled.** `match Json.parse(s) do Ok(Json.Array(_)) -> ... end` matched
  correctly interpreted but fell through to the catch-all arm in a compiled
  binary, no error, no warning, no crash, just the wrong branch. It affected
  any qualified pattern with a bare constructor name declared by more than one
  module: in the standard library that is `Array` and `Null` (both
  `Json.JsonValue` and `Msgpack.Value` declare them), so `Json.Array(_)` and
  `Json.Null` were the visible casualties, while `Json.Object(_)` (a name
  unique to `JsonValue`) worked. Codegen identifies constructors by their
  *type* (`JsonValue.Array`), but the documented qualified-pattern syntax writes
  a *module* (`Json.Array`); when the two names differ the qualifier resolved to
  no module and the pattern fell back to matching on the bare name, which then
  picked whichever module's constructor the compiler happened to enumerate
  first. The qualifier is now translated to its declaring type during lowering,
  so an explicitly qualified pattern resolves to exactly the constructor it
  names.

- **`Json.to_string` crashed on every JSON array and object under `--target js`.**
  It crashed with `TypeError: f._0 is not a function`, while the same program was
  correct interpreted and compiled native. The cause was not in `json.march`: a
  closure allocated inside a match arm where the scrutinee cell is dead gets
  rewritten by Perceus from `EAlloc` to `EReuse`, and the JS backend's `EReuse`
  and `EStackAlloc` cases were missing the rule `EAlloc` had: a closure's apply
  function lives in slot `_0` and must be emitted as the raw function, not as
  the `name$clo` wrapper *object*. Closure dispatch then did `f._0(f, x)` on a
  record instead of a function. This hit any lambda passed to a user-defined
  higher-order function from a reuse-eligible match arm, so `Json.to_string` was
  the symptom rather than the bug. The three allocation forms now share one
  emitter, so they cannot drift apart again.

- **`String.slice` returned the wrong text on the JS backend.** The JS runtime
  implemented `march_string_slice(s, start, len)` as `s.slice(start, len)`,
  treating the third argument as an END index rather than a LENGTH, so every
  slice with a non-zero start was wrong: `String.slice("abcdefgh", 5, 3)` gave
  `""` on JS against `"fgh"` interpreted and compiled. Negative arguments now
  clamp the way the C runtime clamps, instead of being read as offsets from the
  end of the string.

- **TIR pipeline stages are now inspectable as text.** `MARCH_DUMP_TXT=<stage>`
  prints the pretty-printed TIR at any pipeline checkpoint with a label containing
  the given substring (`all` for every stage). Previously only the very end of
  the pipeline was readable, via `--dump-tir`, which is too late to tell whether
  a pass created a construct or only preserved one.

- **The SIMD Benchmarks results tables rendered as raw pipe characters.** The
  three tables under "Results" on
  [/docs/simd-benchmarks/](https://march-lang.org/docs/simd-benchmarks/) were
  wrapped in `<div style="overflow-x:auto">`. Kramdown does not parse markdown
  inside a raw HTML block unless the element contains `markdown="1"`, so each
  table was emitted verbatim as text. The wrapper was also redundant: the docs
  layout already sets `display:block; overflow-x:auto` on content tables, which
  is why the same page's other two tables were fine, so it is simply removed.

- **Discarding a container no longer leaks its contents.** March reclaimed an
  aggregate only by *destructuring* it; releasing one that was never pattern-
  matched freed only the top cell and orphaned everything under it. This hit
  the ordinary way to consume a `String.split` result, passing it to a
  function that borrows it, so bulk text processing leaked in proportion to
  its input (a 60-iteration split/consume loop peaked at 585 MB, growing
  linearly; it now sits flat at 16 MB). It was never about how the container
  was traversed: a consumer that ignored its list argument entirely leaked
  just the same. Compiled targets only; the interpreter was unaffected.
  `bench/binary_trees.march` drops from 157 MB to 6 MB peak as a result.
- **A tail-recursive `Cons(_, t)` walk no longer strands a reference on every
  cell.** The self-TCO back-edge skipped *every* refcount op on a forwarded
  argument, to fix a use-after-free on a freshly allocated one. A list walk's
  tail is not freshly allocated: it is dup'd from the matched cell, and that
  dup's matching release was being skipped, leaving each cons cell pinned.

- **`DataFrame.eval_agg`'s `Min`/`Max`/`Std`/`Variance` no longer materialize
  a boxed `List(Float)` per call.** These aggregates previously converted the
  column's `NativeArray` into a linked list before folding over it, an O(n)
  allocation on top of the O(n) reduction that showed up as tens of
  milliseconds per call on large columns regardless of which aggregate ran.
  They now use dedicated native-array reduction builtins (mirroring `Sum`),
  bringing them roughly in line with the already-fast `Sum`/`Mean` path:
  60-80x faster at 500K rows in local measurement. `Median` still sorts and
  is unaffected by this fix.

- **Compiled string literals no longer leak once per evaluation.** A literal
  used as a direct operand (most commonly `acc ++ ", "` or `s ++ "\n"` inside
  a loop) allocated a fresh string every time it was evaluated, and no code
  freed it, at any point, so ordinary string-building loops grew memory without bound
  (a 2M-iteration concat peaked at 64MB of RSS against 2.9MB for the same loop
  with both operands bound to variables). Each literal now allocates one shared
  string for the whole program, matching how the compiler's ownership analysis
  has always treated literals: as constants that no binding owns. Only the
  compiled backend was affected; the interpreter was always correct.
- **A bare `Bool` variable used as a guard no longer produces a malformed
  solver query.** `if j do … end` around a refined call reflected `j` as an
  integer constant and passed it to z3 as a formula, which z3 rejects; the
  obligation was then silently undecidable. Such a variable is now declared at
  the `Bool` sort, and a Boolean-position well-sortedness guard drops anything
  that still is not a formula rather than emitting it.

- **The compiled-binary cache no longer serves a stale binary after a
  `runtime/*.c` edit.** The CAS key digested a runtime directory it resolved
  itself, searching the current directory *first*, while the compiler picks the
  sources it hands to clang exe-relative *first* ("independent of CWD"). Run
  from the repo root against `_build/default/bin/main.exe`, those are two
  different directories, so the key could be identical (or differ for reasons
  unrelated to what was built) while the compiled output differed: a runtime
  edit could print `compiled <out> (cached)` for a binary containing none of
  the new code. The driver now resolves the runtime directory once and
  registers it with the CAS, so the key always digests the sources actually
  compiled; `MARCH_RUNTIME_DIR` overrides the search, mirroring `MARCH_STDLIB`.
- **`MARCH_STRING_STATS=1`**: an opt-in profiling mode for compiled binaries.
  Set the environment variable and the program prints string-allocation
  statistics to stderr at exit: allocation count and bytes, a size histogram,
  bytes copied, frees, peak live bytes, and non-string heap allocations. Off by
  default and measured at −0.34% overhead when off. Intended for answering
  "where is this program's string cost going?" without a profiler.

- **String benchmark suite**: six benchmarks in `bench/` (`string_scan`,
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
  callback (`fn x -> x *. 2.0 +. 1.0`, a captured scalar, or similar, no
  generic/unresolved types involved) no longer allocates at all for each
  element crossing the callback boundary, and the resulting loop can
  actually be vectorized by the backend compiler on suitable inputs. A
  callback with a type not fully known at this point still allocates one
  reusable cell per call (an earlier improvement over one per element) and
  is unaffected by this change. No observable behavior change either way.

- Compiled `NativeArray.map_float` now allocates one boxed-float cell per
  call and reuses it across all elements, instead of one per element. Cuts
  allocation traffic and GC pressure substantially for large arrays (a
  stress-test benchmark measured roughly 2x less wall-clock time); no
  observable behavior change.

- Native and WASM LLVM output now describes `march_alloc` as a fresh,
  non-null allocation with its allocation size as the argument, and marks
  generated closure ABI trampolines `alwaysinline`. This gives LLVM useful
  alias and call-boundary facts without changing TIR or ownership semantics.

- The TIR optimizer inlines a private top-level function's body at its call
  site when that function has exactly one direct, arity-correct reference
  anywhere in the module, even when the body is not pure. Ordinary pure-only
  inlining, the 50-node size limit, DCE-root/address-taken/hot-code-reload
  exclusions, and recursive-SCC detection (extended to cover bare/qualified
  name aliasing) all still apply; Perceus RC operations and their order are
  preserved unchanged. No runtime speedup was measured: this is a
  definition/call-site reduction in emitted LLVM, not a benchmarked
  optimization.

### Added

- **Refinement Tier 2: structural induction over recursive functions.** A
  relational postcondition on a function that recurses over its own structure,
  `fn insert(t : Tree, x : Int) : {Tree | size(_) == size(t) + 1}`, is now
  *proven* at its definition and therefore propagates to call sites, instead of
  being silently skipped. Z3 still does no induction; the checker supplies the
  **induction hypothesis** at each self-recursive call with an argument that is a
  proper component of the matched parameter, then discharges each `match` arm
  against the `@[measure]`'s recursion equations. Relational and closed
  predicates over a variant-ADT return both work, recursion may descend into
  any recursive component, and a growing accumulator parameter is fine.
  Unchanged and still silent: mutual recursion, the built-in `len` (declare a
  user `@[measure]` instead), a recursive call inside a lambda or behind a
  nested `match`, and any non-structural recursion; the hypothesis is gated by
  the same `structural_subvars` test that makes `@[measure]` axiomatisation
  sound, because an unsound hypothesis would manufacture false positives rather
  than only fail to help. `Int`-returning postconditions are untouched. See
  `specs/lang/refinement-types.md` for the exact frontier, including the three
  stacked obstacles that still separate this from the stdlib HAMT.

- **Two higher-order refinement checks.** A call made *through* a refined
  function-typed parameter (`fn ap(f : ({Int | _ >= 0}) -> Int) : Int do
  f(-3) end`) is now rejected, and so is a call through a **local alias** of
  a named refined function (`let g = takepos  g(-3)`). Both previously fell
  through the checker's named-callee-only call resolution and were silently
  skipped. Single-argument callback types only; a callback parameter with its
  own declared type unrefined is unaffected; see
  `specs/lang/refinement-types.md`'s Limitations section for the exact
  boundary.

- A **guard on a record field** now reaches the refinement checker. `if
  c.port >= 1 do serve(c)` discharges a `{v : Config | v.port >= 1}`
  precondition, and the contradictory `if c.port <= 0 do serve(c)` is reported
  as a definite failure. The variable needs no refinement of its own: a plain
  `c : Config` parameter works, since an unrefined record is modelled as an
  unconstrained value that the guard then determines. With no guard the call is
  still skipped. Field facts obey the same rebinding rule as tag and scalar
  facts: a `let`, `let?`, lambda parameter or `match` binder that rebinds the
  name retires the fact.

- An **unreflectable record field no longer hides its siblings** at a call
  site. `serve({ port: 0, name: n })` and `serve({ port: 0, history:
  Cons(1, Nil) })` used to be skipped whole, because a `String` field bound to a
  variable and a list literal with concrete elements cannot be placed at their
  declared SMT sorts. The offending field is now replaced by an unconstrained
  stand-in of the right sort, so `port` is checked and both calls are reported.
  No fact may be concluded *about* the stand-in in either direction, and the
  return side keeps the conservative whole-record skip.

- Refinement checking now propagates **relational** return refinements (those
  that mention a parameter) by substituting the call's arguments for the
  callee's parameters. Given `fn below(n : Int) : {Int | _ < n}`, the call
  `takepos(below(0))` is a compile error because `_ < 0` can never satisfy
  `_ >= 0`, while `takepos(below(10))` stays silent. Arguments are matched
  positionally and substituted simultaneously, so `f(m, 1)` against
  `{Int | _ < n + m}` yields `_ < m + 1`, not `_ < 1 + 1`. As before, only a
  postcondition the definition side actually *proved* propagates, and
  instantiation is skipped entirely rather than done partially when an argument
  is missing, the predicate mentions an unknown name, or the callee takes a
  pattern parameter; correct code is still never flagged.

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
  A match that handles only some values of a field (`match p do { code: 404 }
  -> ... end`) is reported non-exhaustive instead of typechecking clean and
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
  record's fields: `let { code: c } = p` no longer requires naming every
  field of `p`. The binding's right-hand side supplies the expected type; it
  simply wasn't being passed to the pattern. Naming a field the record lacks
  now gives the same `unknown_record_field` error the `match` path gives,
  instead of a unification mismatch that leaked an internal type-variable
  name. A bare record pattern used directly as a function parameter stays
  closed: that position has no annotation to source a type from.

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
  variable holding a record-refined parameter contains its fields through, so
  forwarding to a same-shaped parameter verifies. An unrefined record, a record
  literal with an unknown field value, or a field outside the reflected
  fragment is skipped rather than guessed at: the definite-failure stance is
  unchanged, and correct code is never flagged.

- Refinement types now support `String`. `len` measures a String as well as a
  list, so `{String | len(_) > 0}` and `{String | _ != ""}` are checkable
  contracts and passing an empty string literal to a non-empty parameter is a
  compile error. `len` counts bytes, matching the `string_length` builtin.
  Which `len` applies is decided by the value's declared base type, so list and
  String uses coexist unambiguously. The encoding models `String` as an opaque
  sort and intentionally avoids SMT string theory, so there is no prefix/suffix/
  contains/regex reasoning, and an `s == ""` guard does not establish a length
  in the else-branch; see `specs/lang/refinement-types.md` for the full limits.

- Refinement checking now propagates a function's declared return refinement to
  its call sites, so passing a `{Int | _ < 0}` result into a `{Int | _ >= 0}`
  parameter is a compile error. Applies to both `takepos(neg())` and
  `let c = neg()` forms, and resolves across modules via `alias`/`use`.
  Only postconditions the definition side actually *proved* propagate; an
  unproven one stays legal but gives callers no information, so a stale return
  refinement can never flag correct code. Postconditions that mention a
  parameter (relational) are not yet propagated.
- Refinement predicates can now constrain an ADT's **constructor tag**. Every
  constructor of every type, including the built-in `Option`, `Result` and
  `List`, gains an implicit `is_<Ctor>` tester, so `fn unwrap(o : {Option(Int)
  | is_Some(_)})` is a checkable contract: `unwrap(None)` is a compile error,
  and so is `unwrap(x)` written inside a `None ->` match arm, where the arm
  narrows the scrutinee's tag. Testers are exact-case (`is_some` is not
  `is_Some`). Narrowing is skipped for a non-variable scrutinee, for an `as`
  pattern, for an arm that rebinds the scrutinee's name, and for a constructor
  name shared by two ADTs; in each case the checker stays silent rather than
  guessing. A fact is recorded against a *name*, so any inner `let`, `let?`,
  lambda parameter or nested `match` binder that rebinds that name retires it.
- Refinement predicates that call an unknown function now produce a warning
  instead of being silently ignored. `{Int | totally_bogus_fn(_) > 0}` compiled
  clean and enforced no rule; it now reports that. The supported vocabulary is the
  comparison/arithmetic/boolean operators, `len`, and `@[measure]` functions.

### Fixed

- `DataFrame`'s `Sum`/`Mean` aggregations (compiled builds) now compute
  directly over the column's underlying array instead of first converting
  the whole column to a list. Purely a missed-optimization fix: same
  results, less work per call. `Min`/`Max`/`Std`/`Variance`/`Median` are
  unaffected (no equivalent fast path yet).

- **Compiled `NativeArray.map_int`/`map_float` now inlines closures that
  capture a variable**, not just plain `fn x -> ...` lambdas, e.g.
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
  against that function's precondition, even though the local is what
  actually runs. `let takepos = fn n -> n` followed by `takepos(-3)` reported
  a bogus violation. Callee resolution now obeys the same shadow discipline as
  every other fact channel: a name an enclosing binder introduced never
  resolves to a global function.

- **`{T | size(_) < 0}` is now checked, like its named form `{v : T | size(v)
  < 0}`.** The anonymous binder (the spelling the reference teaches) was
  emitted verbatim as an SMT symbol when it appeared inside a measure
  application. `_` is a reserved SMT-LIB token, so the solver rejected the
  query and the predicate was silently never decided: the documented idiom
  checked no constraint while the named spelling worked. Both spellings now reflect
  to one canonical symbol and produce identical verdicts.

- **Compiled `NativeArray.map_int`/`map_float` now inlines even when the
  mapped array is reused afterward.** The Phase 2 closure-inlining
  optimization (P10) silently never fired whenever code used the array
  again after mapping it (e.g. a self-recursive loop that maps `arr` and
  then passes `arr` on to its own tail call) because an unrelated Perceus
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
  no record owned that file. Compiling one program, then another to the same
  `-o` path, then the first again to a new path served the second program's
  binary, reported as `(cached)`, with no error:

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
  violation with the counterexample `k = -1`, the guard `v < 0` is about the
  *parameter*, but the path conditions were translated with the resolver in
  which `v` denotes the *return value*, so it became `k < 0`. Path conditions
  now resolve in the function body's namespace; only the return predicate reads
  the binder as the return value. The same conflation also suppressed real
  violations, which are now reported.

- `NativeArray.map_float` (compiled builds) no longer segfaults, and
  `NativeArray.map_int` (compiled builds) no longer silently returns wrong
  results. Both called a closure through the wrong calling convention: a
  native `int64_t`/`double` C signature instead of the tagged/boxed `ptr` ABI
  every March closure actually uses. Floats landed in the wrong CPU register
  class entirely (crash); ints happened to land in the right register but
  skipped the tag/untag step (wrong answer for every element).

- `NativeArray.sum_float` (compiled builds) now vectorizes. Strict IEEE 754
  float semantics were silently blocking clang's auto-vectorizer on this
  reduction loop: it emitted vector loads but scalar adds. Scoping float
  reassociation to just this loop (not a program-wide `-ffast-math`) restores
  SIMD summation; results match prior output to the last bit of rounding,
  roughly 3x less CPU time on large arrays.

- **`String.from_codepoint` and `String.to_codepoints` now work in compiled
  programs.** They were interpreter-only builtin wrappers (the underlying
  `string_from_codepoint`/`string_to_codepoints` have no native
  implementation), so *any* compiled program calling them failed at link time
  with `Undefined symbols: _string_from_codepoint`. Both are now pure-March
  UTF-8 codecs built on `Bytes` and the integer bitwise builtins: one
  definition for every backend, with no interpreter-vs-compiled divergence.
  Encoding rejects negative values, values above U+10FFFF, and UTF-16
  surrogates.

- **`IOList.to_string`/`byte_size`/`is_empty` no longer overflow the stack on
  deep segment trees.** All three traversed the tree with non-tail recursion, so
  a deque of appends: `IOList.append(acc, x)` in a loop builds a left spine
  one level deeper per append, crashed with SIGBUS past roughly 15–20k
  depth, despite the module documenting flattening as stack-safe. Rewritten
  as tail-recursive explicit-worklist traversals that keep the frame stack on
  the heap, so depth and branching are bounded only by memory.
  `bench/iolist_template.march` and `bench/string_pipeline.march` both crashed
  on this and now run clean.

- **A `Deque` element popped in compiled code came back as a garbage
  pointer.** `deque.march` was missing from the compiler's eagerly-loaded
  stdlib list, so it loaded lazily: signatures only, no body typecheck. That
  left callers' bindings as unresolved type variables, monomorphization could
  not specialize the generic `pop_front : Deque(a) -> (Option(a), Deque(a))`,
  and the generic body's *boxed* `Some` was decoded by the concrete caller as
  a *niche* `Option(Int)`, yielding the box's heap address instead of the
  value. `bench/deque_ops.march` printed a pointer and then looped indefinitely
  draining a deque with elements that never matched. Fixed by loading `Deque`
  eagerly; the underlying hazard (lazy loading changing representation
  decisions) is tracked separately.

- `NativeArray.map_int`/`map_float` (compiled builds) no longer allocate a
  closure or call it indirectly when the mapped function is a plain,
  non-capturing `fn x -> ...`: the compiler now calls it directly, which
  clang can then inline and, for arithmetic-heavy element functions,
  vectorize. A capturing closure is unaffected. Workloads with a map step
  dominated by array read/write bandwidth (the common case) won't see a
  wall-clock difference: the win is in the per-element compute cost.

- `typed_array_map`/`typed_array_fold` (compiled builds) no longer segfault.
  `call_closure_1`/`call_closure_2` read a closure's function pointer at byte
  offset +8 of the closure object: the object's `tag` field (plus 4 bytes of
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

- Session types: `loop do ... end` protocols now truly loop. The
  projection previously substituted the post-loop continuation into the
  recursion point, so a `loop` was silently one unrolled iteration: a
  second send/recv round was rejected with `` channel is at `End` ``. `loop`
  now projects to the standard recursive µ-type, so a channel may run the
  loop body any number of times. Since such a loop never exits, a protocol
  step written after a `loop` block is now a compile error instead of
  unreachable, silently-accepted dead code.

- Session types: `Chan.new` on a protocol with more than two roles is now a
  compile error instead of silently handing back the first two roles'
  (non-dual) endpoints as a pair. `Chan.new` is the binary-only channel
  constructor; `MPST.new` already existed for 3+-role protocols but no check
  stopped `Chan.new` from being called on one too. The error names the
  protocol's actual role count and points at `MPST.new`.

- **Session types: an unrefined `Chan.offer` continuation is no longer a live
  soundness hole.** `match`-ing the label `Chan.offer` returns already refined
  the paired channel's type per arm, but only when such a `match` existed:
  driving the channel without one still typed it at the FIRST branch's
  continuation, an unsound guess whenever the branches continue differently.
  Interpreted, that guess could die with a dynamic type error; **compiled, it
  was silent type confusion**: a peer that chose the other branch and sent a
  `String` had that value's heap pointer read as an `Int`. A `Chan.offer`
  with branches that continue identically is unaffected and still needs no
  `match` to drive. `specs/lang/types/accept/t43_choose_offer_roundtrip.march`
  and `specs/lang/golden/g39_chan_choose_offer.march`, both of which relied on
  the old guess, are migrated to match on the label first (`g39`'s printed
  output is unchanged).

- **Session types: the `Chan.offer` fix above was also bypassable by
  unification**: an ordinary type annotation was enough. The compiler marks
  the exact channel `Chan.offer` hands back and rejects operations on it by
  identity, but unifying two channel types only compared their protocol
  states, never linked them. So `let ch : Chan(Role, Proto) = offered`, or an
  `if`/`match` join with another channel, a record field, or passing the
  channel to a function with an annotated parameter, produced a *different*,
  unmarked channel at the same state, and every later check passed. The
  annotation form typechecked clean and, compiled, printed the other branch's
  `String` payload as an `Int`. Unifying an unrefined `Chan.offer`
  continuation with any other channel type is now itself an error; only a
  `match` on the paired label can make the channel usable. Reported at the
  unification rather than propagating the mark, so the function-parameter form
  is caught at the call site, where the mistake is.

- **Lambda and nested-`fn` parameter type annotations are now enforced.** A
  parameter annotation on a `fn ... -> ...` lambda, or on a named `fn`
  declared inside a function body, was checked against no expected type at all: the
  lambda's function type was built from fresh type variables that were never
  reconciled with the annotations, so the body was checked against the
  annotation while every call site checked its argument against the unrelated
  variable. `fn (x : String) -> ...` applied to `42` typechecked. For session
  types this was the last soundness hole *found* in the `Chan.offer` fixes
  above (the enforced routes are enumerated, not proved; see
  `specs/lang/session-types.md`):
  passing an unrefined continuation to `fn (c : Chan(Role, Proto)) -> ...`
  reached neither the per-operation check nor the unification check, and the
  compiled program read one branch's `String` payload as the other's `Int`.
  Both are now rejected. Top-level `fn` parameters were never affected. If
  this newly rejects code you had, the annotation and the actual argument type
  truly disagree; the annotation was simply not being checked before.

- **Session types: the `Chan.offer` fix above was itself bypassable by
  shadowing the offer's label variable.** Rebinding the label name
  (`let lbl = :ok`) after `let (lbl, ch) = Chan.offer(...)` left the OLD
  name→channel linkage reachable, so `match`-ing the shadowed name still
  refined (and un-marked) the original channel as if the peer had returned
  that label, reopening the identical type-confusion hole through a
  shadowed name instead of a missing `match`. Rebinding a name (via a plain
  `let`, a lambda/`fn` parameter, or a `match` pattern) now always retires
  any stale linkage for that name first.

- **Session types: `match`-ing the label `Chan.offer` returns now checks
  exhaustiveness against the protocol's actual branches, not the open `Atom`
  universe.** A `match` handling every branch the peer could choose used to
  warn `` missing case: _ `` anyway (`Atom` is open, so the checker could
  never see the label as fully covered), and a `match` that truly
  omitted a branch produced the exact same warning, never an error. The one
  signal meant to catch "you forgot a protocol branch" was just
  noise either way. Covering every branch (with or without a catch-all) is
  now silent; a missing branch with no catch-all is a compile error naming
  the branch. A `match` arm naming a label the protocol does *not* offer
  (`:okk` alongside `:ok`) used to be accepted in silence and could never be
  taken; it is now a warning naming the unknown label and the valid set,
  a warning, not an error, since a redundant arm is dead code rather than a
  soundness problem.

- Session types: driving an unrefined `Chan.offer` channel from inside a `_`
  catch-all arm no longer advises "Match on the label first", which read as
  clearly wrong to anyone who had just written a `match`. The message now
  explains the real problem: a catch-all does not identify which branch the
  peer chose, so every label needs its own arm.

- Session types: a `choose` branch that ends in a `loop` is now rejected when
  the protocol continues after the `choose`. Those trailing steps are
  projected into every branch, so in a branch that loops indefinitely they can
  never run, the same unreachable-step bug already rejected when the
  steps are written directly after a `loop`, but reached through the
  post-`choose` tail instead.

- Session types: a protocol role that isn't also a declared type or actor no
  longer produces a "not a known actor or type" hint. Roles are their own
  namespace, so the hint was wrong by construction: it fired on the
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
  silently-unchecked result outlive the fix for that bug, which is how a warm
  cache masked two refinement regression tests. Caches written before this
  change self-heal, and real verdicts are still cached.

- **The `task_await` missed-wakeup deadlock is fixed**: fork-join workloads
  (`task_spawn` + `task_await`) hung roughly once every 20 runs, and the same
  race intermittently hung CI's test step. It was a memory-ordering bug, not a
  logic bug: the waiter's register-then-recheck and the completer's
  publish-then-read-waiter form a classic store-buffering (Dekker) pair, and
  release/acquire ordering does not prevent a store from being reordered after
  a later load of a different address. On Apple Silicon the compiler emits an
  RCpc acquire load (`ldapr`) that may complete before an earlier release
  store drains, so both sides could read stale values at once: the task
  completed, the completer saw no registered waiter and woke no one, and the
  waiter (having read a stale "not done") shelved indefinitely. Upgraded both
  sides of the pair to sequentially-consistent ordering (24 hangs/500 runs →
  1/1000), and closed the residual window (a wake arriving after the
  waiter's final recheck but before it finishes parking was dropped) with a
  wake-permit handshake in the scheduler (0 hangs/3000 runs). The
  `task_burst_await` regression test is back in the default test suite after
  being quarantined as un-runnably flaky; actor mailbox delivery never had
  either bug (its check-and-park runs under the mailbox lock).

- A single malformed verification condition no longer disables refinement
  checking for the rest of a compilation. z3 emits an `(error …)` line and then
  still answers the query, but that line was read as the verdict; the solver was
  killed, respawned, hit the same error, and z3 was then marked unavailable for
  the whole run, so every later call site was silently left unchecked with no
  diagnostic. Error lines are now skipped, and a query that produced one is
  reported as unproven rather than trusted.

- **A z3 error message spanning more than one line no longer shifts every later
  verdict by one.** The fix above skipped a single `(error …)` *line*, but a
  sort mismatch prints the offending term and then a second line naming the
  declaration it violates; the continuation stayed in the pipe and was consumed
  as the *next* query's answer. Under the definite-failure stance that is more harmful
  than an unchecked call: a later, unrelated, **correct** call inherits some
  other query's `unsat` and is reported as a violation. The whole error
  s-expression is now consumed, counting parens only outside its quoted
  message.

- **A record argument holding a list literal with concrete elements is now
  skipped instead of building a malformed query.** `{ history: Cons(1, Nil) }`
  puts a well-sorted `List` constructor at a `List` field, but the built-in
  `List` is generic so its element sort is opaque, and the integer `1` does not
  fit there. The field sort-check only looked at the top-level term, so the
  mismatch reached z3: the exact multi-line error above. The check now
  recurses into a constructor's arguments.

- **A refinement path fact persisted a rebinding of the name it was about**, so
  correct code could be flagged. After `if x < 0 do`, a `let x = 5` inside the
  branch left `x < 0` attached to the *new* `x`, and a call needing `{Int | _ >=
  0}` was reported as a definite violation. Facts are now retired by every
  binding construct that rebinds a name they mention (`let`, `let?`, lambda and
  local-`fn` parameters, and `match` arm binders) in both the call-site and the
  return-position checks.

- **Scalar tagging now contains `nsw`, letting LLVM fold the tag/untag round
  trip away entirely.** The `(v << 1) | 1` immediate-scalar tag was emitted
  as a plain `shl`, so LLVM could not assume the shift preserved the sign and
  a sign-truncating `sbfx` persisted on every scalar round trip, and, more costly,
  that residue blocked accumulator tail-recursion elimination on recursive
  functions with a result that feeds the tag. With `shl nsw` (asserting exactly the
  63-bit-losslessness the tagging convention already assumes), `fib(40)`
  compiles to an accumulator loop with a single recursive call, with the
  preemption check still inside the loop, and drops from 465 ms to ~390 ms.
  Trade-off, made intentionally: an `Int` outside [-2^62, 2^62) passed through
  a generic/erased slot was *already* silently corrupted by the round trip;
  under `nsw` that same out-of-convention value is poison rather than a
  deterministic wrong value. The full differential-oracle sweep (141
  programs) is unchanged: 100 MATCH, 0 divergences.

- **Compiled code no longer pays a thread-local-storage resolver call on every
  function entry.** Each compiled function began by loading, decrementing and
  storing the `_Thread_local` scheduler reduction counter. Thread-local access
  is not a plain load on either supported platform: on Darwin/arm64 the symbol
  is a TLV descriptor and each access compiles to `adrp; ldr; blr` (an
  indirect call into the resolver), and on Linux/arm64 PIE it goes through a
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
  microseconds, far more often than the quantum required, for no benefit.
  Because the flag is process-wide rather than per-thread, a given scheduler
  thread is now preempted on average every (threads × quantum) rather than
  every quantum.

- **`MARCH_NUM_SCHEDULERS=1` had no timer preemption at all.**
  `march_sched_run`'s single-scheduler fast path returned without
  starting the preemption daemon at all, so in the configuration used for
  deterministic, race-free runs the *only* thing that preempted a
  CPU-bound green thread was the per-call reduction counter. A tail-recursive
  loop could otherwise monopolise the scheduler indefinitely. The daemon is
  now started (and stopped) on that path too. Found by a new starvation test
  that runs a CPU-bound task alongside a short one on a single scheduler
  thread, the only configuration in which such a test measures preemption
  rather than parallelism.

- **Perceus FBIP in-place reuse was silently disabled program-wide**, making
  every "functional but in-place" rewrite a heap free + fresh allocation
  instead. `bench/tree_transform.march` (the FBIP showcase) ran at 3842 ms
  against 513 ms in the last published benchmark table, and
  `bench/list_ops.march` at 143 ms against 68 ms.

  Cause: once `join_points` began lifting a `match`'s panic default arm into
  a `$jp_clo` closure, every real arm contained a `dec_rc $jp_clo` between its
  `let` chain and its tail allocation. `try_fbip_sink` only traversed `ELet`
  nodes, so the scrutinee's own `dec_rc` could never reach the allocation and
  no `EReuse` was produced at all. `try_fbip_sink` now also hops `ESeq` heads
  that are RC operations on a *different* variable, sound because RC ops
  neither read fields nor observe ordering, delaying a `dec` can only delay
  (never hasten) a free, and the aliasing corner is caught by `EReuse`'s
  runtime RC==1 uniqueness branch, which sends shared cells down the
  fresh-allocation path. A fail-loudly full-overwrite guard at the generic
  `EReuse` emission site rejects a reuse with an argument count that doesn't match
  the resolved constructor's declared field count, which would otherwise leak
  the reused cell's stale trailing fields.

  After the fix: tree-transform 852 ms, list-ops 67 ms (the latter exactly
  matching the pre-regression figure). Note that `fib(40)` (which allocates
  no heap memory and is therefore unaffected by FBIP) remains ~2.2x slower than the
  same published table, an unrelated and still-open regression.

  This restores work that existed and was verified on the
  `docs/core-march-types-skeleton` line but never reached `main`; the TIR
  golden snapshot `fbip_dead_binding_reuse` had the starved `dec_rc` + `alloc`
  shape pinned in as its expected output, so the one test written to catch
  this regression was certifying it instead.

- `bench/run_benchmarks.sh` invoked `dune exec march` without `--root .`.
  Run from a git worktree (which lives under the parent checkout), dune
  resolved its root to the *parent* repository and benchmarked that
  compiler rather than the one under test, silently reporting the wrong
  binary's numbers, with no error.

### Fixed

- A record refinement where the record had a field of a non-`Int` type bound to a
  variable (e.g. `{ port: 8080, name: n }` where `name : String`) could
  silently disable refinement checking for the **rest of the file**. The
  reflection placed the variable at the wrong solver sort, the solver rejected
  the malformed query, and the error desynchronised the long-lived solver
  session, so every later check (including plain `Int` ones in unrelated
  functions) came back inconclusive and reported no result. Such a record is now
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
  `~/.march/cache/runtime-objs/`, and reused on subsequent builds; only the
  generated LLVM IR for your own program is compiled per invocation. Measured
  locally, this cuts the clang portion of a small program's build from ~1.5s
  to ~0.3s (a ~5x reduction on that step; ~45% off end-to-end, the remainder
  now being March's own frontend). The saving compounds anywhere many
  programs are compiled in sequence: test suites, the differential oracle,
  `forge build` over a multi-file project.

  The cache key covers the runtime sources' content, the C compiler's own
  version, and the full compile-flag string, so editing a runtime `.c`/`.h`,
  bumping clang, or switching optimization/sanitizer/debug flags each get
  their own object set rather than silently reusing a stale one. Builds that
  bake per-invocation defines into the runtime (cross-compilation,
  `--compile-so`, `--hot-reload` with `--signing-pubkey`, and
  `MARCH_HTTP_EVLOOP=1`) automatically fall back to the previous
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
  any `match` in checking position (which is every `match` in a function with
  a return annotation, i.e. most of them) silently skipped the analysis.

- The Zed extension's tree-sitter grammar was pinned to a commit from
  2026-03-26, 4.5 months before `pfn` (private function) and
  `needs` (capability declaration) support were added to the grammar
  (#175, 2026-08-04). Editors built against the stale pin showed `pfn` and
  `needs` as unhighlighted plain text instead of keywords. `rev` in
  `zed-march/extension.toml` now points at current `main`; reload the dev
  extension in Zed to pick it up.

### Documentation

- Migrated 14 language-reference chapters (Type System, Pattern Matching,
  Modules, Interfaces, Linear Types, Refinement Types, Capabilities, Safety
  by Construction, Memory Model, Actors, Parallel Collections, Supervision,
  Session Types, Clustering) from `specs/lang/` into real, styled pages on
  march-lang.org (`/docs/<topic>/`). These previously rendered as blank,
  unstyled `/<topic>.html` stub pages ("this topic has moved") that every
  site page linking to them (the homepage, the language tour, Getting
  Started, the stdlib guide, the FFI guide, and the "coming from X" guides)
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
  identical to the interpreter, exit 0; what remains truly
  unimplemented is multiparty `choose`/`offer`, and MPST still has no
  golden conformance witness. Also documented: `Chan.new(Proto)` returns
  its endpoint pair ordered by alphabetically-sorted role name (not
  declaration order), and `loop do ... end` projects to a real
  recursive session type and must be a protocol's last step.

## [0.2.0] - 2026-07-23

### Fixed

- A module could not reference a same-name-prefixed sibling module in a
  multi-file project (e.g. entry `mod MyApp` calling into a sibling
  `mod MyApp.Router` declared in its own file (the documented
  "one mod per file" multi-file convention), via `MyApp.Router.dispatch(...)`,
  `use MyApp.Router` + bare `Router.dispatch(...)`, or (previously the only
  working spelling) `alias MyApp.Router as R`. The first two failed with
  `Unknown module \`Router\`.`: the entry-module-self-qualification stripping
  pass matched by string prefix only, so `MyApp.Router.dispatch` (which
  only starts with the entry's own name, `MyApp.`) was wrongly mangled to
  `Router.dispatch` as if `Router` were one of the entry's own members. A
  related gap in `use`/`alias` resolution (taking only the first segment of a
  dotted import path) and in `use`'s bare-name binding for dotted paths are
  also fixed. Referencing an unrelated-named sibling module always worked and
  still does.

- Fork-join workloads using `task_spawn`/`task_await`/`task_await_unwrap`
  under high task concurrency (thousands of simultaneously in-flight tasks)
  could hit a severe performance cliff: `bench/par_fib.march`
  (`par_fib(40, 20)`) went from a fraction of a second to 54+ minutes past a
  certain task-count threshold. An earlier pass bounded the worst case with
  a spin-then-sleep backoff (cutting wasted CPU) but the workload still
  didn't complete; `task_await` now parks the awaiting green thread and
  wakes it explicitly on completion (mirroring the existing actor-mailbox
  park/wake pattern), which eliminates both the wasted context-switch
  overhead and a LIFO dispatch-starvation interaction that was compounding
  it. The scheduler's separate internal wake-on-parked-proc spin also keeps
  its own generous-grace-period sleep fallback from the earlier pass, so
  neither wait can peg an OS thread at 100% CPU indefinitely with no possibility
  of self-recovery. Compiled `--compile` programs only; the interpreter was
  unaffected.

- Compiled `Csv.read_all`/`Csv.each_row_with_header` could crash
  (nondeterministic SIGBUS/SIGSEGV) or silently return zero rows. A
  builtin-call argument coercion added to fix an unrelated tagging bug
  (`Some((top, _)) -> int_to_string(top)` printing `7` instead of `3`) was
  incorrectly tagging opaque native-pointer handles (Csv/File/Tcp handles
  are represented as plain `Int` in March's type system by convention, but
  are raw C pointers at runtime) whenever they were passed to a builtin
  with a C signature declaring the parameter as `ptr`. Restricted the
  coercion to the direction it was actually meant for.

- Refinement checking's return-refinement propagation could false-positive
  through a `let? p = e` binding: the continuation after `let? c = ok5()`
  still saw an outer refined local named `c` instead of the newly-bound one,
  so a subsequent correct use of `c` could be wrongly flagged. `let?` now
  shadows its bound names before checking its continuation, matching every
  other binding construct (`let`, lambda params, `match` binders). Also
  reworded refinement counterexamples from `f() returns v` to
  `f() can return v`: the solver's model is a witness satisfying `f`'s
  postcondition, not necessarily `f`'s actual return value.

- The browser cookbook/playground REPL's bundled stdlib was missing
  `Vault`: the docs/cookbook/vault.md examples errored with `no member
  'new' in module 'Vault'` because `vault.march` wasn't in either
  `js/march_browser.ml`'s `browser_stdlib_files` load-list or
  `scripts/gen-browser-stdlib.py`'s `FILES` list used to generate
  `docs/assets/march_stdlib.js`. Added it to both and regenerated the
  bundled assets.

### Documentation

- The "sandboxed plugin runner" example in docs/cookbook/capabilities.md
  called a `sandbox_eval` function that never existed anywhere in the
  compiler or stdlib: it was illustrative pseudocode, so running the
  example in the cookbook REPL errored with `unbound variable:
  sandbox_eval`. Replaced it with a trivial inline stub so the snippet
  actually compiles and runs; the example's real point (the `PluginCap`
  gate) is unaffected.

- A qualified call to a real module's truly nonexistent member (e.g.
  `String.length(...)`; `String` has no `length`; the real API is
  `byte_size`/`codepoint_count`/`grapheme_count`) silently fell through to an
  unrelated same-named binding elsewhere (e.g. the prelude's generic
  `List.length`) instead of reporting "Module `String` does not export
  `length`". The EVar dot-suffix fallback (meant only to resolve
  multi-component local/app-module paths like `Conduit.Storage.workflow_load`
  down to `Storage.workflow_load`) didn't distinguish that case from a
  qualifier that is already a confirmed, loaded stdlib module. Now, once the
  qualifier's first component resolves to a real registered module, a missing
  member always reports the clean "does not export" diagnostic instead of
  falling through to the bare-name search.
- A user-defined interface impl with a compositional `when` constraint (e.g.
  `impl MyEq(Wrap(a)) when MyEq(a) do fn eq(w1, w2) do ... eq(x, y) ... end
  end` (the same shape as the stdlib's own `Eq(List(a)) when Eq(a)`) with a
  body that recursively called its own method name on the constrained inner value
  dispatched incorrectly. Interpreted, the recursive call re-entered the SAME
  impl instead of the inner type's impl, producing a wrong answer (or a
  non-exhaustive-match panic). Compiled, it crashed with an internal compiler
  error ("has no runtime-tag rows") whenever the constrained type happened to
  share a method name with an unrelated interface. Both are fixed: the
  recursive call now dispatches by the runtime type of its own arguments on
  both backends, regardless of impl declaration order or nesting depth.
- `root_cap()`: calling the root capability like a function instead of
  referencing it bare (`root_cap`), typechecked cleanly with `--check` and
  then crashed at runtime: `applied non-function value` interpreted, or an
  `Undefined symbols ... _root_cap` link error compiled. `root_cap` is a
  plain value, not a function; calling it with `()` is now rejected at
  check/compile time with a diagnostic explaining why.
- `File.read` and related I/O builtins (`file_write/append/delete/copy/rename/stat/open`,
  `Dir.list/mkdir/mkdir_p/rmdir/rm_rf`, `Csv.open`, and the TCP/TLS/HTTP/process
  builtins) had their `Result` error type registered as fully polymorphic, so a
  function declaring an incompatible error type (e.g. `Result(_, String)` for
  `File.read`; its real error is `FileError`) typechecked with zero
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
- The same underlying gap (builtin call arguments never coerced to the
  builtin's own declared native parameter type, only to a user-defined
  function's) also reached compiled output through an unrelated path: a
  scalar bound by a tuple or constructor pattern (e.g. `Some((top, rest)) ->
  int_to_string(top)`, or even a plain top-level `(top, rest) ->
  int_to_string(top)`) passed to any compiler builtin with a native scalar
  parameter (`math_sqrt`, `float_abs`, and ~50 more beyond the three fixed
  above) printed the raw internal tagged-integer encoding instead of the real
  value (`7` instead of `3` for the example above). Call-argument coercion
  now also derives each builtin's declared parameter types directly from its
  own preamble `declare` signature, so every builtin gets the same coercion
  user-defined functions already had, not just the three fixed individually
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
  to whichever impl happened to be declared first, a latent miscompile risk
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
  in `T` and fell back to inferring the type from `e` by itself with zero
  diagnostics, e.g. `let e : Vec(Int) = "not a vec"` typechecked cleanly.
  This was meant to tolerate a phantom/typestate tag used in type position
  (`let h : Handle(Open) = ...`, where `Open` is a data constructor, not a
  type name) but was too broad, silently discarding truly broken
  annotations (an unresolvable module, a typo'd or renamed type) too.
  Narrowed to only tolerate the phantom-tag case (an unresolved name that IS
  a known data constructor); any other resolution failure now surfaces as a
  real diagnostic.
- An inline lambda passed directly as a call argument (e.g. `Dom.on_frame(fn _
  -> ...)`) failed to parse if its body had a plain statement (not a `let`
  binding) immediately followed by another expression (e.g. a function call
  followed by an `if`/`else`) even though the identical body worked fine as a
  named function or a lambda wrapped in `do...end`. Symptom: `I got stuck here`
  at the following token. Inline lambda call arguments now accept bare
  statements before the final expression, matching `do...end` block bodies.
- A linear or `always_linear`-typed value *acquired* through `let? p = e` or
  `with Ok(p) <- e do ... end` (rather than bound by a plain `let` or a
  function parameter) was never tracked as linear at all, so consuming it
  twice (e.g. passing the same handle to two separate calls, each behind its
  own `let?`) went completely undetected. The identical double-use was
  already correctly rejected when the value came from an ordinary `let` or a
  function parameter. Affects any code acquiring a linear resource through a
  Result-returning `let?`/`with` chain.
- A self-tail-recursive function forwarding a freshly-built value as its own
  next argument (e.g. an accumulator built via `String.join`/`String.split`)
  could silently corrupt that value in compiled programs: freed one
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
  programs whenever the parsed `Float` was actually used, e.g.
  `match string_to_float(s) do Some(f) -> ... end`. Fine in the interpreter;
  native code stored the parsed value in a representation the rest of the
  compiler didn't expect. Affects any compiled program parsing floats from
  strings, including `stdlib/toml.march`'s float handling.
- `Html.raw(...)` content silently disappeared when interpolated into a `~H`
  sigil in compiled programs, e.g. `~H"<button>${Html.raw("hi")}</button>"`
  rendered `<button></button>`. Fine in the interpreter. Affects the
  documented layout/partial-nesting pattern
  (`~H"<body>${Html.raw(IOList.to_string(body))}</body>"`) as well.
- `Option.or_else` and `Option.unwrap_or_else` crashed at runtime
  (`arity mismatch: expected 0 args, got 1`) when called with a real
  zero-argument callback (`fn -> ...`, the natural spelling for their
  declared `() -> a` parameter). Both functions invoked the callback as
  `f(())` (passing an explicit unit value) instead of `f()`, which only
  matched a 1-arg-discard closure (`fn _ -> ...`). Fixed to call `f()`;
  affects both the interpreter and compiled programs.
- `pfn` (private function) visibility could be silently bypassed when a
  same-file nested module's private function shared its bare name with an
  unrelated global (e.g. a function named `hash`, colliding with the `Hash`
  interface's built-in method). The call typechecked without error, ran
  correctly in the interpreter, and produced a garbage value in compiled
  programs: a privacy violation that also corrupted the result, not just a
  missing diagnostic. Now correctly rejected at `--check` and `--compile`
  with the same "is private to module" error other privacy violations
  already produced.
- `RRB.push`/`Array.push` crashed compiled on the second `Float` element
  pushed (`RRB.push(RRB.push(RRB.empty(), 1.5), 2.5)`). A discarded
  (wildcard-matched) field of a list cell never got the special-casing a
  *named* field already had, so the compiler treated it as reference-counted
  even when the concrete element type (`Float`) doesn't need that, freeing
  memory that was never actually heap-allocated. (Reading a pushed `Float`
  back out, `Array.get`/`RRB.get`, had a separate, sibling bug; see below.)
- `task_spawn`/`Task.async` with a `Float`-returning callback, followed by
  `task_await_unwrap`/`Task.await_unwrap`/`Task.await`, failed to compile
  with an internal LLVM type error. Affects `Parallel.preduce`/`psum_float`,
  which spawn one task per worker chunk.
- A tail-recursive function combining a `Float` accumulator with a
  heap-value parameter (e.g. an `Array`/`List`), the shape `RRB.fold`'s
  internal loop uses, returned a wrong answer or crashed
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
  other DOM function, so they were unreachable from March code
  ("Module `Dom` does not export ...") despite being documented.
- `fn main(cap : Cap(IO)) : ()`: the documented pattern for receiving the
  initial IO capability, never actually worked: in the interpreter it
  silently no-oped (the program appeared to exit successfully having done
  no work), and compiled programs crashed (SIGBUS) on startup. Both backends
  now run it correctly; any other `main` arity or parameter type is now
  rejected at compile time with a clear error instead of misbehaving.
- WebSocket connections in the interpreter (`forge run`, plain `march
  file.march`, and any tool built on it, including `forge scroll.serve`)
  disconnected almost immediately whenever the client went quiet: an open
  connection would flip to closed within milliseconds of the server having
  no data to read, sometimes before the client's very first message was even
  processed. A raw handshake with no further traffic got an instant
  server-initiated close. The server's WebSocket handler was reading from a
  socket still configured for the (unrelated) HTTP accept loop's internal
  bookkeeping, which made an ordinary "no data yet" condition look
  the same as the client disconnecting. Compiled (`--compile`)
  WebSocket servers had a milder version of the same bug: an idle connection
  would be dropped after 10 seconds instead of staying open. Both are fixed;
  idle WebSocket connections now stay open as expected in both backends.
- `Vault.update` crashed (segfault) in compiled programs, for both an inline
  lambda and a named function callback, e.g.
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
  its claimed output, including a large number of stale API references in
  `docs/stdlib.md` (wrong module names, argument order, arity, or return
  types across `String`, `Math`, `JSON`, `HTTP`, `Vault`, `URI`, `Dom`, and
  more), the REPL transcript in `docs/getting-started.md` (real prompt is
  numbered, `= value` output by default), and dozens of smaller fixes across
  `docs/cookbook/*`. Several real compiler/stdlib bugs surfaced along the way
  (silent wrong answers and crashes, mostly compiled-only) that are outside a
  docs fix's scope and were logged separately rather than papered over in the
  docs.
- `docs/cookbook/linear-types.md`'s Typestate section and its "safe socket
  lifecycle" example, left unfixed by the docs audit above pending a design
  decision, didn't compile as written and were internally inconsistent
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
  `parser.mly`/`token_filter.ml` line citations have gone stale (~15 of ~294
  fixed; the rest need a dedicated re-grep pass). Several real compiler bugs
  surfaced along the way and were logged separately, most notably a
  currently-live regression where compiled `Actor.call`/`Actor.reply` returns
  the raw tagged value instead of untagging it; it breaks an existing pinned
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
  pauses) with FBIP (Functional But In-Place): pattern-matched values with
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
