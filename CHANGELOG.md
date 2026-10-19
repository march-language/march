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

- `march --compile --static` builds a self-contained executable: on Linux a fully
  static binary that runs in a `scratch` image (musl hosts such as Alpine; refused on
  glibc), on macOS one that loads nothing outside `/usr/lib` and `/System`. A missing
  static library is an error naming the package to install, and the compiler checks
  the finished binary before keeping it. See "Static binaries" in the tooling docs,
  including how a static binary finds TLS certificates.

### Fixed

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

### Changed

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

### Documentation

- **An upgrade guide for 0.6.0.** `docs/upgrading-to-0-6-0.md` covers the two
  security fixes, the `send_wrong_actor` check and the RFC 3986 `Uri` changes. The
  landing page and the toolchain examples now name v0.6.0.

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
