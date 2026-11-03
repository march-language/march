# Browser REPL: load stdlib and package modules on demand; report Int overflow

Date: 2026-10-14
Status: implemented 2026-10-14 (see "Implementation notes" at the end)

Project 2 of 4 toward "Try it" buttons on documentation examples (project 1:
`specs/2026-10-14-browser-repl-bundle-design.md`). The goal is learning: a reader
running a documented example should get the answer native March gives, or a clear
reason why the browser can't.

## Measured starting point (2026-10-14, release bundle, Node)

- The interpreter REPL (`docs/assets/march.js`) loads a fixed list of 29 stdlib
  files (`js/march_browser.ml` `browser_stdlib_files`), parsing and evaluating all of
  them on the first evaluation: about 165 ms.
- Of the 210 `march>` doc examples in `stdlib/`, 63 evaluate without error. Most
  failures are `no member ...` because the module is not loaded.
- With all 132 files loaded, 204 of 210 evaluate without error (2 are file-system
  calls, 4 panics), but the first evaluation takes about 718 ms and the stdlib download
  grows from about 96 KB to about 520 KB gzipped.
- Four files fail to parse: `dataframe`, `msgpack`, `net_frame` and `node_queue`. Each
  contains an Int literal above 2^31-1.
- **The browser interpreter's Int is 32-bit.** js_of_ocaml's OCaml `int` is 32 bits,
  and the interpreter stores March `Int` in it. In the browser `2147483647 + 1` gives
  `-2147483648`, `65536 * 65536` gives `0`, and `fact(13)` gives `1932053504`.
  Native March Int is 63-bit.
- Parse failures are swallowed silently (`parse_stdlib_src` has `with _ -> []`).

## Decisions (from the conversation)

1. Load modules **on demand**, per module, the first time input uses them. Startup
   keeps today's core set.
2. A module that can't work in a browser gives a **clear "not available in the
   browser REPL" error** with the reason, not a low-level failure.
3. **Int overflow is detected and reported**, not wrapped. Keeping 32-bit was chosen
   over a 63-bit representation.
4. The same loading interface serves **package code** (the basis for project 3).

## Design

### 1. Index and per-module files (build time)

`scripts/gen-browser-stdlib.py` additionally writes:

- `docs/assets/stdlib/<file>.js`: one per stdlib file, each
  `window.marchStdlib[<file>] = <source>;`.
- `docs/assets/march_stdlib_index.js`, which sets `window.marchModuleIndex` to:
  ```
  { "<Module.Name>": { "file": "<file>.march", "uses": ["<Module>", ...],
                       "unavailable": null | "<reason>" }, ... }
  ```
  - `uses` is every capitalised `Name.` / `Name.Sub.` reference in the file that names
    another indexed module, so loads can follow dependencies.
  - Nested modules (`mod A do mod B do`) are indexed as `A.B` pointing at the same file.
  - `unavailable` comes from a hand-kept table in the script, with one reason per
    category:
    - needs a file system;
    - needs network sockets;
    - needs OS processes;
    - needs a cluster runtime;
    - needs 63-bit integers.
  - A module listed there that no longer exists fails the script.

`march_stdlib.js` (the core set, loaded at startup) is unchanged in role. Both
generated forms are added to `scripts/build-browser-repl.sh`'s artifact list.

### 2. Bundle interface (OCaml, `js/march_browser.ml`)

Two new exports beside `marchEvalLine` and `marchResetSession`:

- `marchModulesNeeded(code) -> {load: [file], unavailable: [{module, reason}]}`
  1. Scans `code` for module references.
  2. Follows `uses` through `window.marchModuleIndex`, transitively.
  3. Drops modules already loaded in this session.
  4. Returns the files still to load, in dependency order (dependencies first), and
     every unavailable module reached. A name that isn't in the index is ignored: it
     may be a user module or a constructor.
- `marchLoadModule(file, source) -> {error: null | string}`
  - Parses and evaluates one file into the current session environment, without the
    reset that `eval_module_env` performs, and records it as loaded.
  - A parse or eval error is returned, not swallowed.
  - It works for any source, including a package's, which is how project 3 will load
    package code.
  - `marchResetSession` forgets loaded modules too: after a reset only the core set is
    loaded, as at startup.

Startup still loads the core list, now taken from the index (every module of the 29
current files), so the list is not hand-kept in two places.

### 3. Loader (JS, `docs/assets/march-repl.js`)

Before each evaluation, `MarchRepl` does the following:
1. Calls `marchModulesNeeded`.
2. If anything is unavailable, prints one message per module and does not evaluate:
   `File isn't available in the browser REPL: it needs a file system. Install March to
   run this.`, with a link to the install page. Nothing is evaluated, so the output is
   never a half-run.
3. Fetches each missing `stdlib/<file>.js` (cache-busted with the page's `ver`), calls
   `marchLoadModule`, then evaluates. A failed fetch or load prints the error and does
   not evaluate.

The index file is loaded with the bundle. Package docs (project 3) add their own index
entries and source URLs; the loader takes a base URL per index entry.

### 4. Int overflow (OCaml, `lib/eval/`)

- `Eval_runtime` gets `narrow_int = Sys.int_size < 63`, which is false on native, and
  checked helpers `int_add`, `int_sub`, `int_mul`, `int_neg` and `int_pow`. When
  `narrow_int` is true they raise an eval error on overflow:

  > this result does not fit the browser REPL's 32-bit Int; native March uses 63-bit
  > Int.

  On native the helpers are the plain operators.
- `arith_num` uses them for `+ - *`. `negate`, `int_pow`, `abs`, `int_shl`,
  `string_to_int` and `float_to_int` check their results the same way.
- The lexer's oversized-literal message names the host limit only when it is narrow:
  "... exceeds the browser REPL's 32-bit Int (native March allows up to
  4611686018427387903)". The native message is unchanged.
- **Wraparound users.** Stdlib code that relies on wrapping (hashes) would raise under
  the check. The first implementation task measures this: run every stdlib doc example
  and the smoke test with checking on. If it happens, those call sites use explicitly
  wrapping builtins, or the module joins the "needs 63-bit integers" list; the
  measurement decides which.

## Testing

- `scripts/browser-repl-smoke.js` gains:
  - an on-demand load (`HashMap.from_list`, previously `no member`);
  - an unavailable module (`File.read`) with its exact message;
  - an overflow (`2147483647 + 1`) with its exact message;
  - a package module loaded with `marchLoadModule` from a fixture and then called;
  - reset forgetting a loaded module.
- A browser doc-example sweep, run in CI as a step of the `browser-repl` job, feeds
  every stdlib `march>` expression through the on-demand path. It fails unless every
  example either evaluates or fails with a reason in a committed allowlist. That
  allowlist starts from the probe: file-system calls, intended panics, unavailable
  modules, overflow.
- Native: `scripts/run-tests.sh eval stdlib` and `bench/run_interp_bench.sh --modes
  interp` show no regression (the check is a constant `false` branch on native).
- A manual browser pass on the playground and a cookbook page:
  - `HashMap` in a cookbook snippet now runs;
  - `File.read` gives the unavailable message;
  - `65536 * 65536` gives the overflow message.

## Non-goals

- 63-bit Int in the browser (not chosen).
- Typechecking in the browser REPL.
- Project 3's `march_doc` side (emitting package indexes, buttons).

## Implementation notes (2026-10-14)

- **Only directly named modules get the "unavailable" message.** A dependency that
  cannot run in a browser is skipped silently. Crypto references Random, yet most of
  Crypto works; blocking it on Random would block it entirely.
- **Random is unavailable: it relies on wraparound.** With overflow checking on, it was
  the only wraparound user found: `Random.int` overflows in its 32-bit masks. It was
  already broken in the browser before this change (`65536 * 65536` is `0` at 32 bits,
  so `Random.int` failed with "division by zero"). It joins the "needs 63-bit
  integers" list and leaves the startup set. Every stdlib doc example and a heavier
  workload (maps and sets of 2,000-3,000 keys, Crypto, CRDT) raised no other
  overflow.
- **Results.**
  - Doc sweep: 210 examples, 197 run cleanly; 13 fail as listed in
    `scripts/browser-repl-doc-sweep.js`. That is 9 "unavailable" (Cluster, Dir,
    HttpServer) and 4 documented panics.
  - Startup is unchanged at about 160 ms.
  - The cookbook `HashMap` snippets now run, loading `hash_map.js` on demand.
- **Native.** compiler, eval, stdlib and stdlib_march suites pass.
  `bench/run_interp_bench.sh --modes interp` is within noise of the previous build
  (load average about 8; `fib` +1%).
- **Index.** `march_stdlib_index.js` (19.6 KB, 2.7 KB gzipped) indexes 140 modules,
  nested ones included. There are 132 per-file sources under
  `docs/assets/stdlib/`.
- **Not covered here, filed separately.** The browser interpreter runs out of JS stack
  on modest recursion depth: `List.map` over 500 elements. This predates the change;
  see `specs/todos/2026-10-14-browser-repl-stack-depth.md`.
