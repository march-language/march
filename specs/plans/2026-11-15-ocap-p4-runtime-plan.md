# Object capabilities, phase 4: run-time authority in every runtime — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every running piece of March code has a current authority. Capability operations
check against it, function values carry the authority they were made under, actors and tasks
inherit it at spawn and keep it across restarts, and `main`'s `needs` clause, narrowed by
`--grant` / `MARCH_GRANT`, is the launch authority. All of this behaves the same in the
interpreter, the REPL/JIT, compiled native code and JS. A program that uses no scopes, no
narrowed launch and no frame-needing function `needs` clause pays one or two global loads per
capability operation, and nothing per call, per closure or per allocation.

**Architecture:** There are two layers, split along the hot and cold paths.

- **Runtime layer** (the C runtime, the OCaml interpreter, the JS runtime), deliberately tiny.
  It holds one *slot* per green thread and one *launch* global. Each is either empty, or a March
  value of type `List(Authority.Layer)`. It also provides a fast-path `cap_check_raw` and six
  plumbing builtins.
- **Policy layer**, written once in March (`stdlib/authority.march`): the scope-text parser,
  the capability lattice, path/host/name matching, intersection (a stack of layers), subset,
  launch initialisation, and the slow-path check that builds `CapError`. Every backend runs
  the same March code, so the backends cannot drift apart on semantics.

The compiler inserts frames for function `needs` clauses and captures for function values as
a TIR pass after lowering (native, JIT and JS). The interpreter does the same natively, in its
call and closure paths. Static analysis keeps the inserted code to the places where run-time
authority can differ from what the type checker already proved.

**Tech stack:** OCaml 5.5.1 (compiler, interpreter), C (runtime), JS (`runtime/march_runtime.mjs`), March (stdlib).

**Spec:** `specs/2026-11-10-object-capability-design.md` (§3, §5, §7, §11, §15, §18, §21,
phases table §17 row 4). Also respects `specs/2026-11-11-ocap-capture-checking-design.md`
§10 (phase 8 adds no run-time code; a static capture set of `()` may later let codegen skip a
capture; the IR is byte-identical with that layer on or off).

---

## Why the inserted code can be this small (the argument the design rests on)

The type checker already proves three things for every direct call:
- the module ceiling;
- each function's transitive `needs` bound;
- that the whole program's reach sits under `main`'s request (`cap_grant_exceeded`).

It also charges a lambda's body to the function that creates it. So, at run time, an
operation reached by direct calls under a function `f` with `needs N` already has a kind in
`N`. There are only four things the run-time layer can observe that the checker cannot:

1. **A computed target under a scoped limit.** Examples: `File.read(p)` under
   `IO.FileRead("/srv/")`, or under a launch request that carries scopes.
2. **A narrowed launch** (`MARCH_GRANT` narrower than the request).
3. **An actor spawned under `f`.** Its handlers are charged to the actor's module, not to `f`,
   so its operations may lie outside `N` (design §7: "a worker spawned inside `restrict` is
   restricted for life").
4. **A function value called somewhere other than where it was made.** It must run under its
   own captured authority, not under the frame it is called in.

The consequences:
- A function `needs` clause needs a run-time **frame** only if it carries a scope (case 1) or
  the function transitively reaches an actor spawn (case 3).
- A function value needs a **capture** only if (a) its body reaches a capability operation or a
  spawn, and (b) the program has at least one frame. With no frames, every slot is the launch
  authority all the time, so capturing would change nothing.
- With no frames, the TIR pass is the identity and closures are byte-identical.

The interpreter does not run the static analysis. It always captures and always frames a
function with a `needs` clause. By the argument above, this differs from the native decisions
only where the static checker is wrong, so the conformance suite doubles as a differential
check on those decisions.

## Performance approach and budget

Baseline: main @ `2caf18fdd`, `scripts/perf-ab.sh` A/A, 11 rounds, load 6–8 on 14 cores.
All 11 benches were within noise. The noise floor for `list_ops` is about ±5% cpu. Table:
`side-session-notes/.../ocap-p4-baseline-perf.md`.

| Path | Mechanism | Budget (checked by) |
|---|---|---|
| Pure compute: `fib tree_transform binary_trees list_ops list_ops_nested json_stream` | No change to calls, closures or objects unless the program has a frame | perf-ab verdict `~` on cpu for each (CI includes 1.00 or \|Δ\| ≤ 3%); allocation counters identical |
| Capability op, fast path (no scopes, no grant, no frames) | `cap_check_raw` reads two globals (`launch`, `frames_ever`) and returns 0 without touching TLS | `println_loop`, `spawn_loop`, `actor_ping` `~`; added cost ≤ 2 ns/op |
| Capability op, slow path (scoped/narrowed launch or inside a frame) | March walks the layers; strings are parsed once at launch or at frame entry | ≤ 1 µs/op with a 2-layer authority, measured on `bench/cap_check_slow.march` (new) |
| Spawn | One pointer copy + incrc into the child proc / actor meta | `spawn_loop`, `actor_ping` `~` |
| Closures in a program with frames | One extra captured word and two slot writes per call, only for closures that reach a capability op | `bench/cap_capture_closures.march` (new): report the delta; no budget gate |
| Startup | One `Authority.launch_init` call; returns at once when unscoped and `MARCH_GRANT` is unset | hello-world wall time `~` |
| IR | `scripts/oracle-base.sh ir` | Every changed program differs only by the entry `launch_init` call plus the linked `Authority` launch functions; programs with frames also change at those frames. A sample diff is pasted in the PR |

`bench/clock_loop.march` calls the raw `unix_time_ms` builtin. Once Task 8 gates raw
builtins, it moves to the checked `Clock` entry point. The PR reports that move separately
(it measures the check's cost, not a regression), and the source diff is shown.

## Global Constraints

- Every capability operation keeps returning `Result(T, CapError)`. Refusals are values,
  never panics (design §15). `CapError(kind, target, limit, limit_scope)` and `CapLimit` keep
  their Prelude definitions (`stdlib/prelude.march:35-36`).
- "Every runtime the same": interpreter, `--jit`, REPL, `--compile`, `--target js` print
  identical output for every conformance fixture. The JS target has no tasks or actors;
  fixtures that need them go in `js_unsupported` with the reason "the JS target has no tasks".
- Nothing ever widens the current authority (design §3). `MARCH_GRANT`/`--grant` wider than
  the request is a launch error, not a widening.
- A function value created by module-level code captures nothing and runs under its
  caller's authority (design §21). An actor spawned at top level does keep the launch authority.
- Calling a function value: the caller's authority plays no part (design §5).
- Supervisor restart restores the authority of the child's first spawn (design §7).
- The REPL runs with the full authority of the person at the terminal; `--grant` narrows it.
  A test file's request is its module's `needs` line (design §21).
- The TLS trap: never read a `_Thread_local` after a `swapcontext` that can migrate. The C
  slot lives in `march_proc` and is read through a `noinline` accessor
  (`runtime/march_scheduler.c:2839-2866`).
- Repo rules (CLAUDE.md): `dune build --root .` in the worktree. Stage files by name. No
  attribution lines. No rebase or force-push. Never `gh pr merge --auto`. Never skip or
  quarantine a test. Update `specs/todos/`, `specs/progress/`, `CHANGELOG.md`, and
  `specs/lang/` + `scripts/gen-lang-docs.py` in the same commit. `test/refine_audit/corpus.baseline`
  is regenerated from a fresh build only if `test/native` fixtures are added.
- Grammar changes to `lib/parser/parser.mly` come with `tree-sitter-march/grammar.js`, or with
  known-failures entries and a todo (`scripts/check-tree-sitter.sh`).

## Decisions taken in this plan (for the owner to check)

1. **Policy in March, mechanism in each runtime** (design §20 leaves the representation to
   the builder). The scope parser, lattice and matchers exist once, in `stdlib/authority.march`.
   A differential test pins them against `lib/caps` (Task 2).
2. **Scoped function `needs` clauses are allowed** (today `fn_needs` cannot carry a scope).
   They are enforced at run time only. A literal-target compile-time check for them is filed
   as a todo; the runtime check is complete on its own (design §8: "a computed scope is
   checked at run time only").
3. **`main`'s request** is `main`'s `needs` clause ∪ the kinds of its legacy `Cap(...)`
   parameters. With neither, it is the module's `needs` line (design §11). The `Cap` form gets
   no deprecation warning here; retiring it is phase 7.
4. **Launch errors** (malformed `MARCH_GRANT`, or one wider than the request) print one line
   to stderr and exit with status 2 before any module-level code runs:
   - `march: MARCH_GRANT is not a scope list: <detail>`
   - `march: MARCH_GRANT grants <scope>, which main does not request (main requests: <request text>)`
5. **The refusing limit is the innermost refusing layer.** Layers are checked from the
   innermost frame out to the launch layer.
6. **Entering a frame already in force is a no-op.** If the top layer has the same limit and
   scope text, nothing is pushed. A framed function's self tail calls target its unframed body.
7. **Deferred, each with a todo:**
   - The cross-node authority wire format (§21 "Across nodes"). Today `DistSupervisor` starts
     remote children by a CAS-typed `RemoteRef` over `NodeCall`, which carries no authority;
     the receiving node runs them under its launch authority, which never widens anything.
   - `realpath`/`O_NOFOLLOW` hardening of path checks (here they are lexical, after resolving
     relative paths against the current directory).
   - Mutually tail-recursive *framed* functions grow the stack by one wrapper per hop.
   - `IO.Env(prefix)` / `IO.Spawn(max(n))` scopes, which are not in the scope language yet.
   - `HttpTransport`/`HttpClient` re-typing (they already check, and fold a refusal into
     `Refused`).

## Delivery: two PRs (recommended)

- **PR A (Tasks 1–7, 10):** run-time authority itself, plus the conformance suite.
- **PR B (Tasks 8–9):** closes the two phase-4 todos that are mostly corpus migration:
  - the raw-builtin gate, about 300 direct calls in `test/`, `bench/`, `examples/`;
  - the network opens (`HttpServer.*`, `Udp.resolve`, about 55 call sites).

  Until PR B lands, a user program that calls a raw builtin directly (`file_read(p)`) bypasses
  the run-time check (but not the compile-time one). PR B follows PR A immediately, in the
  same session.

## Review Focus

1. **A closure made outside a frame and called inside it.** It must run under the outer
   authority, not the frame's. This is the case a naive "capture only closures created under
   frames" rule gets wrong. Pinned by the fixture `capture_outside_called_inside`.
2. **Deep self-recursion through a framed function.** Expected: constant stack, and the layer
   list does not grow. Pinned by `frame_reenter_noop` (1,000,000 self tail calls).
3. **An actor under a frame, restarted by its supervisor from a proc with different
   authority.** Expected: the restarted child has its first spawn's authority, not the
   restarter's. Pinned by `actor_restart_keeps_authority`.
4. **A relative path and a `..` path under a path scope.** `File.read("../x")` from inside
   the scope dir must be refused when it leaves; `File.read("sub/f")` must be admitted.
   Pinned by `path_scope_relative_and_dotdot`.
5. **`MARCH_GRANT` set to the empty string.** Treated as unset, not as "grant nothing"; to
   grant nothing, write `MARCH_GRANT=()`. Pinned by `grant_empty_string_is_unset` and
   `grant_unit_grants_nothing`.

---

### Task 1: Runtime slot, launch global and fast path (C, interpreter, JS)

Replaces the phase-1 `MARCH_TEST_REFUSE` hook in all three runtimes.

**Files:**
- Modify: `runtime/march_scheduler.h` (add `void *auth` to `march_proc`), `runtime/march_scheduler.c` (init NULL in `sched_spawn_common`; copy the parent's slot with incrc beside `spawn_code_epoch` at ~:1983; decrc on proc exit)
- Modify: `runtime/march_extras.c:4289-4365` (delete the hook; new builtins), `runtime/march_runtime.h:206`
- Modify: `lib/eval/eval_builtins.ml:161-171,2883-2890` (delete the hook; `cap_slot`/`cap_launch` refs)
- Modify: `runtime/march_runtime.mjs:755-780`
- Modify, per the compiler-builtin skill's site list: `lib/typecheck/typecheck_builtins.ml`, `lib/typecheck/typecheck_env.ml` (`stdlib_only`), `lib/tir/llvm_builtins.ml` (row + `PDeclare`), `lib/tir/defun.ml` (`builtin_names`), `lib/tir/purity.ml` (`impure_builtins`: ALL of these), `lib/tir/borrow.ml` (both tables), `lib/tir/js_emit.ml`, `lib/caps/cap_ops.ml` (`Internal`), `test/test_stdlib_only.ml`
- Test: `test/test_codegen.ml` (`golden_preamble_*`), `test/test_cap_runtime_slot.ml` (new, registered in `test/run_compiler.ml`)

**Interfaces (Produces):** stdlib-only builtins. `CapAuthRef` is a new opaque builtin type, an erased pointer, NULL allowed (the C RC is NULL-safe; generic RC only, no drop glue).
- `cap_check_raw(kind : String, target : String) : Int`: 0 = admitted without looking further (`launch` empty and no frame slot); 1 = consult the March slow path. C: `if (!march_cap_launch && !atomic_load_relaxed(&march_cap_frames_ever)) return 0;` and only then read the slot.
- `cap_layers() : List(Authority.Layer)`: the current slot if non-empty, else the launch list, else `Nil` (C: `make_nil()`).
- `cap_set_launch(l : List(Authority.Layer)) : ()`: write-once (a second call panics).
- `cap_save() : CapAuthRef`: the slot, incrc'd.
- `cap_restore(r : CapAuthRef) : ()`: consumes `r`, sets the slot, decrcs the old value.
- `cap_push(l : Authority.Layer) : CapAuthRef`: returns the saved old slot. New slot = `Cons(l, cap_layers())`. Sets `frames_ever`.
- `cap_enter(r : CapAuthRef) : CapAuthRef`: sets the slot to `r` (incrc), returns the old one, sets `frames_ever` if `r` is non-NULL. Used by closure prologues.
- `cap_grant_text() : String`: `MARCH_GRANT`, trimmed; `""` when unset or blank.
- The interpreter and JS use `Nil` / `null` for "empty". Their `CapAuthRef` is the list value itself.

- [ ] Step 1: Write `test_cap_runtime_slot.ml`. It compiles and interprets a stdlib-spanned fixture (`--stdlib-source`) that calls `cap_save`/`cap_push`/`cap_restore` and prints `cap_check_raw` before, inside and after a push. Expected output in every mode: `0\n1\n0`. A second case: under `MARCH_GRANT` unset, `cap_grant_text()` prints `""`; under `MARCH_GRANT=" IO.Console "`, it prints `IO.Console`.
- [ ] Step 2: Run `scripts/run-tests.sh compiler` and expect FAIL (unknown builtins).
- [ ] Step 3: Implement the builtins at every site above. Remove `MARCH_TEST_REFUSE` and `cap_launch_text` everywhere: `grep -rn MARCH_TEST_REFUSE lib runtime test stdlib` returns nothing once Task 7 has migrated the fixtures. Keep `Authority.check` compiling by having it call the slow path (Task 2) only when `cap_check_raw` returns 1.
- [ ] Step 4: Run `scripts/run-tests.sh compiler codegen` and expect PASS. Run `test/test_codegen.ml` golden preamble updates and review the diff.
- [ ] Step 5: Commit `runtime: per-proc authority slot and launch global replace the phase-1 refusal hook`.

### Task 2: The policy layer in March: layers, parser, lattice, matching, slow path, launch

**Files:**
- Modify: `stdlib/authority.march`
- Create: `lib/caps/emit_march_lattice.ml` (+ dune rule), which writes the lattice as a March function block between markers in `stdlib/authority.march`, with a freshness check in `test/dune` next to "cap lattice freshness"
- Test: `test/stdlib/test_authority.march` (extend or create), `test/test_authority_differential.ml` (new, in `run_compiler`)

**Interfaces (Produces), all in `mod Authority`:**
- `type Arg = Any | Paths(List(String)) | Hosts(String) | Names(List(String), List(String))`. `Hosts` holds the packed spec the parser already produces (`"api.x.com/v1/;methods=get"`); `Names(names, prefixes)`.
- `type Scope = Scope(String, Arg)`, `type Layer = Layer(CapLimit, String, List(Scope))` (limit, scope text as written, parsed scopes).
- `pfn parse(text : String) : Result(List(Scope), String)`. The `needs` surface grammar: comma-separated `Kind` / `Kind("a", "b", opt(...))`, with `()` meaning the empty list. The error string is the `<detail>` of decision 4.
- `pfn admits(scopes : List(Scope), kind : String, target : String, cwd : String) : Bool`. An entry admits when its kind equals or is a lattice ancestor of `kind`, and either it is `Any`, or `kind` is scopable and the target matches:
  - **paths:** resolve a relative target against `cwd`, normalise lexically, then match by whole segments (`Cap_scope.within`);
  - **`host:port`:** `Host_scope.permits`;
  - **names:** `Name_scope.admits`.
  - An unscoped related entry admits everything, as in `typecheck_caps.ml:1580-1590`.
- `pfn subset(a : List(Scope), b : List(Scope)) : Bool`: every entry of `a` is admitted by some entry of `b` with an ancestor-or-equal kind and a subsumed argument (paths `within`, names `Name_scope.subsumes`, hosts: same host or within the wildcard, path within, methods ⊆).
- `fn check(kind, target)` (public, unchanged signature): `if cap_check_raw(kind, target) == 0 do Ok(()) else check_layers(kind, target, cap_layers()) end`. `check_layers` returns `Err(CapError(kind, target, limit, text))` for the first refusing layer (innermost first; decision 5), else `Ok(())`.
- `@[stdlib_internal] fn launch_init(request : String, scoped : Bool) : ()`:
  - return at once when `!scoped && cap_grant_text() == ""`;
  - otherwise parse the request, and parse the grant (or reuse the request when `""`);
  - enforce decision 4: stderr + exit 2 via raw builtins;
  - `cap_set_launch([Layer(ByLaunch, text, scopes)])`, where `text` is the grant text if given, else the request text.
- `@[stdlib_internal] fn enter_fn(name : String, needs_text : String) : CapAuthRef`:
  - when the top layer is `Layer(ByFnNeeds(name), needs_text, _)`, return `cap_save()` (decision 6);
  - else parse and return `cap_push(Layer(ByFnNeeds(name), needs_text, scopes))`;
  - `needs_text` comes from the compiler and is never malformed; a parse failure panics with "internal".

- [ ] Step 1: Write `test/stdlib/test_authority.march` cases (pure functions, no launch needed):
  - `parse("IO.Console, IO.FileRead(\"/srv/a/\")") == Ok([Scope("IO.Console", Any), Scope("IO.FileRead", Paths(["/srv/a"]))])`; `parse("()") == Ok([])`; `parse("IO.Console(") ` is `Err(_)`;
  - `admits([Scope("IO.FileSystem", Paths(["/srv"]))], "IO.FileRead", "/srv/x", "/")`; not `"/srvx"`; `admits(.., "IO.FileRead", "../x", "/srv")` is false; `admits([Scope("IO", Any)], "IO.Clock", "", "/")`;
  - `subset([Scope("IO.FileRead", Paths(["/srv/a"]))], [Scope("IO.FileSystem", Paths(["/srv"]))])`; not the reverse;
  - `check_layers` with two layers refusing in each one returns the inner one's `CapLimit`.
- [ ] Step 2: Write `test_authority_differential.ml`: a table of about 60 `(scope text, kind, target)` triples covering paths, hosts with ports and wildcards, names and prefixes, and lattice ancestry. The OCaml verdict comes from `Cap_lattice`/`Cap_scope`/`Host_scope`/`Name_scope`; the March verdict from one interpreted program that prints `admits` for every row. They must agree row for row.
- [ ] Step 3: Run `scripts/run-tests.sh stdlib_march compiler` and expect FAIL.
- [ ] Step 4: Implement. Reuse `Http`'s host-spec decoder if its semantics match `Host_scope.permits`; otherwise port `Host_scope`. Generate the lattice block.
- [ ] Step 5: Run the same tests and expect PASS. `dune build --root . @runtest` for the freshness rule.
- [ ] Step 6: Commit `stdlib: Authority's run-time policy: scope parser, lattice, matching, layered check, launch_init`.

### Task 3: `main`'s request, scoped function `needs`, launcher narrowing

**Files:**
- Modify: `lib/ast/ast.ml:297` (`fn_needs : ((name list * string option) list * span) option`), `lib/parser/parser.mly` (function `needs` reuses `scoped_cap_path`), `tree-sitter-march/grammar.js` + corpus test
- Modify: every `fn_needs` consumer (`lib/typecheck/typecheck_caps.ml:737,1262`, `lib/refinecheck/cap_infer.ml`, `lib/driver/cap_static.ml`, the LSP); scopes are ignored statically except to compute texts
- Modify: `lib/typecheck/typecheck.ml` `check_main_grant` (:10387) and `main_grant_of_decls` (:10728): the request is per decision 3; export `launch_request : Ast.module_ -> string * bool` (canonical text: entries in source order joined by `", "`, each printed as written; `bool` = any entry scoped)
- Modify: `lib/tir/lower.ml` / `lib/tir/llvm_toplevel.ml`: the program entry calls `Authority.launch_init(text, scoped)` before module-level initialisers and `main`. The same goes for the JIT entry (`lib/jit/repl_jit.ml`), the JS entry, `Eval.run_module` (`lib/eval/eval.ml:4678`, before top-level evaluation), and test runners (the request is the module `needs` line). The REPL calls `launch_init("IO", false)`.
- Modify: `bin/main.ml`: `--grant SCOPES` sets `MARCH_GRANT` for this run (interp, `--jit`, REPL, `march test`); `forge/lib/cmd_run.ml` + `forge/bin/main.ml`: `forge run --grant` passes it to the child environment
- Test: `test/errors/` (scoped `fn` needs parse; the `cap_grant` fixtures whose expected outcome changes under decision 3, regenerated and reviewed), `test/test_compiler.ml` `launch_request_*` unit tests

**Interfaces:** Consumes `Authority.launch_init` (Task 2). Produces `Typecheck.launch_request` and `fn_needs` with scopes (Tasks 4, 5).

- [ ] Step 1: Unit tests in `test_compiler.ml`:
  - `launch_request` of `fn main() : () needs IO.Console, IO.FileRead("/srv/") do ... end` is `("IO.Console, IO.FileRead(\"/srv/\")", true)`;
  - of `fn main(_c : Cap(IO.Console))` it is `("IO.Console", false)`;
  - of a main with neither, in a module with `needs IO.Clock`, it is `("IO.Clock", false)`.
  - A parse test: `fn f() needs IO.FileRead("/a/") do () end` is accepted.
- [ ] Step 2: Run and expect FAIL.
- [ ] Step 3: Implement the parser/AST change, the request computation, the entry calls and `--grant`. Run `scripts/check-tree-sitter.sh`.
- [ ] Step 4: Run `scripts/run-tests.sh compiler errors` with `UPDATE_ERRORS=1` only for the changed `cap_grant_*` fixtures. Review `git diff test/errors/` and expect PASS.
- [ ] Step 5: Commit `ocap p4: main's needs clause is the launch request; --grant / MARCH_GRANT narrow it`.

### Task 4: Frames for function `needs` clauses

**Files:**
- Modify: `lib/tir/lower_decls.ml` (carry `fn_needs` text into a side table `Lower.fn_needs_tbl : (string, string * bool) Hashtbl.t`, keyed by the lowered fn name: needs text, scoped)
- Create: `lib/tir/auth_rt.ml` (+ `.mli`). It runs right after `Lower.lower_module` in `bin/main.ml` (~:4805), in `lib/jit/repl_jit.ml` (~:542) and on the JS path.
- Modify: `lib/eval/eval.ml:3675-3702` (the `DFn` wrapper): when `def.fn_needs` is present and the fn is not `main`, call March `Authority.enter_fn(name, text)` before the body and `cap_restore` after (`Fun.protect`)
- Test: `test/test_auth_rt.ml` (new, in `run_compiler`), `test/snapshots/src/auth_frame.march` (new TIR snapshot)

**Interfaces:**
- `Auth_rt.frames : Tir.module_ -> needs:(string, string * bool) Hashtbl.t -> Tir.module_ * bool`. It returns the module and whether any frame was kept (`has_frames`, consumed by Task 5).
- A fn `f` with needs `(text, scoped)` is framed iff `scoped || reaches_actor_spawn f`. `reaches_actor_spawn` is a fixpoint over direct `EApp` calls to user/stdlib fns, seeded by calls to `march_spawn`/`march_spawn_supervised` and the lowered actor-spawn glue (`lib/tir/lower_actor.ml:520-531`).
- A framed `f` is rewritten to:
  - `f(args) = let s = Authority.enter_fn("<Mod.f>", text) in let r = f$auth(args) in cap_restore(s); r`;
  - `f$auth`, which is the original body with self calls to `f` retargeted to `f$auth`.
- No frame is generated for `main`.

- [ ] Step 1: `test_auth_rt.ml` cases on lowered TIR:
  - a fn with `needs IO.Console` that reaches no spawn is not framed, `has_frames = false`, and the module is physically equal to the input;
  - a fn with `needs IO.FileRead("/a/")` is framed;
  - a fn with `needs IO.Console` that calls a fn that spawns an actor is framed;
  - the self tail call in a framed fn targets `f$auth`.
- [ ] Step 2: Run and expect FAIL.
- [ ] Step 3: Implement `Auth_rt.frames` and the interpreter frame.
- [ ] Step 4: Run `scripts/run-tests.sh compiler eval`. Add the snapshot with `UPDATE_SNAPSHOTS=1` and review it. Expect PASS.
- [ ] Step 5: Commit `ocap p4: run-time frames for function needs clauses that carry a scope or reach an actor spawn`.

### Task 5: Capture of authority by function values

**Files:**
- Modify: `lib/tir/auth_rt.ml` (`captures`), `lib/eval/eval_types.ml:34` (`VClosure` gains a 5th field `cap : value option`, where `None` means "captured nothing", used for module-level closures), every `VClosure` construction and match site (`lib/eval/eval.ml` lines from the survey: 1943, 2243, 2572, 3675-3702, 4048, 4055, 4373, 4557), `apply_inner` (:1952-1981)
- Test: `test/test_auth_rt.ml`, `test/snapshots/src/auth_capture.march`

**Interfaces:**
- `Auth_rt.captures : Tir.module_ -> has_frames:bool -> repl:bool -> Tir.module_`. It is the identity when `not has_frames && not repl`. Otherwise:
  - **Lambdas.** For each lambda (`ELetRec ([fn], EAtom (AVar fn))`, `lib/tir/defun.ml:492`) whose body reaches a capability op (a call to a `Cap_ops.classify = Checked` builtin, to `Authority.check`, or to a fn that does, by the same fixpoint) or an actor/task spawn, and which is not created in module-initialiser code:
    - wrap it as `let $capN = cap_save() in <lambda>`;
    - prefix the lambda body with `let $s = cap_enter($capN)`, and restore with `cap_restore($s)` on exit.
  - **Named functions used as values.** A named fn used as a value (an `AVar` of a top-level fn outside callee position) that reaches an op becomes an eta lambda first, then gets the same treatment.
  - **Partial applications** are lambdas after lowering. Verify this in step 1's test; if they are not, handle them like named values.
- Interpreter: `VClosure` creation records `Some !cap_slot` (and `None` while evaluating module-level declarations). `apply_inner` of `Some a` swaps the slot to `a` around the body when `a != !cap_slot` (physical inequality), using `Fun.protect`. Named functions used as values are wrapped at `EVar` evaluation outside `EApp` callee position.

- [ ] Step 1: `test_auth_rt.ml` cases:
  - a program without frames is unchanged (physically equal);
  - with frames, a lambda calling `println` is captured, and `fn x -> x + 1` is not;
  - `List.map(xs, File.read)` produces a capturing eta lambda;
  - `File.read` partially applied produces a lambda that captures;
  - a lambda in a top-level `let` is not captured.
- [ ] Step 2: Run and expect FAIL.
- [ ] Step 3: Implement the native and interpreter paths.
- [ ] Step 4: Run `scripts/run-tests.sh compiler eval codegen`. Run `UPDATE_SNAPSHOTS=1`, then review `git diff test/snapshots/`: only `auth_*` may change. Expect PASS.
- [ ] Step 5: Commit `ocap p4: function values capture the authority they were made under`.

### Task 6: Spawn and restart

**Files:**
- Modify: `runtime/march_runtime.c`:
  - `march_spawn_common` (:8708): store `tl_sched->current->auth` (incrc) on `march_actor_meta`, next to `spawn_cap` (:4377);
  - `actor_green_thread` (:6783): install it on the actor's proc slot;
  - supervisor child slot (~:4220): keep the first spawn's authority. `stash_child_for_restart` (:5882) / `march_respawn_child` (:7399-7461) reinstall it, the way `pending_spawn_cap` already flows; release it at :13345;
  - tasks inherit through `sched_spawn_common` (Task 1). `march_task_spawn_with_cancel_thunk` (:9632) goes through `march_sched_spawn_with_cancel`; make it copy too.
- Modify: `lib/eval/eval_runtime.ml:227` (`ai_authority` on `actor_inst`), `lib/eval/eval.ml:2412` (`ESpawn` records it), `run_scheduler` (:2875, :2975-3044) and Shutdown/`run_on_stop` (`eval.ml:3545`, `eval_runtime.ml:1556`) set the slot around handlers; `spawn_child_actor` (`eval_runtime.ml:1000-1012`) copies it from the first incarnation
- Test: conformance fixtures in Task 7 (`actor_under_frame_restricted`, `actor_restart_keeps_authority`, `task_inherits_capture`); `test/test_cap_runtime_slot.ml` adds an ASAN-relevant case: 10,000 spawn/exit cycles under a frame leave no live authority object (`MARCH_TRACE_GC=1` + `scripts/gc-trace-report.py` exits 0)

- [ ] Step 1: Write the three conformance fixtures (Task 7's format) and the leak case.
- [ ] Step 2: Run `scripts/run-tests.sh cap_conformance compiler` and expect FAIL.
- [ ] Step 3: Implement.
- [ ] Step 4: Run the same and expect PASS. Then run an ASAN rebuild of one actor fixture via `scripts/triage.sh <fixture>` and expect a clean ASAN section.
- [ ] Step 5: Commit `ocap p4: actors and tasks run under their spawner's authority; restarts restore the first spawn's`.

### Task 7: The conformance suite carries every enforcement test to every backend

**Files:**
- Modify: `test/run_cap_conformance.ml`. Replace the mandatory `-- REFUSE:` header with optional headers, each on its own line at the top:
  - `-- GRANT: <scopes>`, exported as `MARCH_GRANT`;
  - `-- EXIT-ONLY`, which compares only the exit status and stderr's first line. Use it for launch errors.
  - Keep the four modes (interp, jit, compiled, js).
  - Add a fifth mode, `repl`: feed the file's `main()` body through `march --repl` with `--grant` from the header, for the fixtures that do not use actors.
- Modify: all existing fixtures in `test/cap_conformance/`. `-- REFUSE: K` becomes the equivalent `-- GRANT:`, which is the request minus K. Keep the `.expected` unchanged except for `CapError`'s `limit_scope`, which is now the grant text.
- Create the fixtures (one `.march` + `.expected` each). Names are pinned, and each covers a design §18 run-time line:
  - `grant_narrower_refuses`, `grant_wider_launch_error`, `grant_malformed_launch_error`, `grant_empty_string_is_unset`, `grant_unit_grants_nothing`;
  - `request_scoped_computed_path_refused`, `request_from_module_needs`, `path_scope_relative_and_dotdot`, `host_scope_computed_refused`, `name_scope_computed_refused`;
  - `fn_scoped_needs_refuses` (`ByFnNeeds`), `nested_fn_needs_intersect` (one refusal from each layer), `frame_reenter_noop`;
  - `capture_inside_called_outside`, `capture_outside_called_inside`, `capture_named_fn_value`, `capture_partial_application`, `capture_stored_in_record_list_vault`, `toplevel_closure_runs_under_caller`;
  - `actor_under_frame_restricted`, `actor_restart_keeps_authority`, `task_inherits_capture`, `no_scope_program_unchanged`.
  - `js_unsupported` gets the actor/task fixtures, with the reason "the JS target has no tasks".
- Modify: `test/test_cap_mode_parity.ml` if it reads `MARCH_TEST_REFUSE`

- [ ] Step 1: Write the fixtures and the runner change. Generate `.expected` with `UPDATE_CAP_CONFORMANCE=1` from the interp run *after* checking each by hand against the design rule it names. Record the check in the commit message body, one line per fixture.
- [ ] Step 2: Run `scripts/run-tests.sh cap_conformance` and expect all modes agree for every fixture (only JS `SKIP` for the listed ones).
- [ ] Step 3: Commit `test: ocap p4 conformance fixtures across interp, JIT, REPL, compiled and JS`.

### Task 8 (PR B): Raw capability builtins become stdlib-only

Do exactly what `specs/todos/2026-11-10-ocap-p1-gate-raw-capability-builtins.md` says. Task 8 must:
- gate every `Cap_ops.gated` row except `println` and `random_bytes`;
- give the `stdlib_internal` diagnostic a machine fix to the row's first entry point where the arity matches;
- migrate the corpus (about 300 calls; the `test_codegen` builtin-level tests move behind a stdlib-spanned fixture);
- confirm `path_arg_builtins` still fires through the `File.*` entry points;
- move `bench/clock_loop.march` to `Clock`.

**Test:** `test/test_stdlib_only.ml` gains `raw_capability_builtins_gated`. The `stdlib_internal_*` error fixtures add one case with its machine fix. The full suite stays green. `git mv` the todo to `specs/progress/`.

- [ ] Step 1: Write the failing `raw_capability_builtins_gated` test and run it (expect FAIL).
- [ ] Step 2: Gate, add the fix-its, run `forge fix` over the corpus, and hand-fix the rest.
- [ ] Step 3: Run `scripts/run-tests.sh` (full) and `scripts/affected.sh --run`; expect PASS.
- [ ] Step 4: Commit `ocap p4: raw capability builtins are stdlib-only`.

### Task 9 (PR B): Network opens check their target and return `Result(Result(_, E), CapError)`

Per `specs/todos/2026-11-10-ocap-p1-network-opens-deferred-to-p2.md`:
- `HttpServer.listen`, `spawn_n`, `bind_host` and `plain_listener` call `Authority.check("IO.NetListen", "<addr>:<port>")`;
- `Udp.resolve` calls `Authority.check("IO.NetConnect", "<host>:0")`;
- all of them return the nested result;
- migrate the roughly 55 call sites (`forge fix` where it applies);
- remove their rows from `test/test_cap_check_coverage.ml`'s allowlist.

The `HttpTransport`/`HttpClient` re-typing stays in that todo, edited to say so.

**Test:** `test/test_cap_check_coverage.ml` passes with the rows removed. The new conformance fixture `listen_refused` runs under `-- GRANT: IO.Console`.

- [ ] Step 1: Remove the allowlist rows and add the fixture; run both (expect FAIL).
- [ ] Step 2: Implement and migrate.
- [ ] Step 3: Run `scripts/run-tests.sh` (full) and expect PASS.
- [ ] Step 4: Commit `ocap p4: HttpServer opens and Udp.resolve are checked operations`.

### Task 10: Benchmarks, docs, specs, changelog (in PR A; Task 8/9 additions in PR B)

**Files:**
- Create: `bench/cap_check_slow.march`:
  - 1,000,000 `Authority.check("IO.Console", "stdout")` calls inside a scoped frame;
  - prints the count;
  - registered in `test/test_bench_gate.ml` with its expected output.
- Create: `bench/cap_capture_closures.march`:
  - the `list_ops` workload plus one framed fn, so captures are on;
  - registered the same way.
- Modify: `specs/benchmarks.md` (the mapping: ocap run-time changes → `println_loop clock_loop spawn_loop actor_ping cap_check_slow cap_capture_closures list_ops`)
- Modify: `specs/lang/` capability chapter (current authority, capture, frames, `--grant`/`MARCH_GRANT`, launch errors), then run `scripts/gen-lang-docs.py`
- Modify: `CHANGELOG.md` `[Unreleased]`:
  - `### Added`: run-time authority, `--grant` / `MARCH_GRANT`, scoped function `needs`;
  - `### Changed`: `main` with no clause and no `Cap` parameter asks for its module's `needs`; `MARCH_TEST_REFUSE` removed.
- Create: `specs/progress/2026-11-15-ocap-p4-runtime.md`. Create todos, one per deferral in decision 7, plus a todo for the scoped function `needs` literal-target compile-time check.
- Modify: `specs/todos/2026-11-12-ocap-capture-checking.md`: "Waits on phase 4" becomes unblocked. Close `specs/todos/2026-11-10-ocap-p1-handle-uses-not-capability-ops.md` (`git mv` to progress) after confirming that none of its builtins is in `Cap_ops`/`builtin_cap_table`.

- [ ] Step 1: Write the benches and register them; run `scripts/run-tests.sh -q` (bench gate).
- [ ] Step 2: Perf verification:
  - `scripts/perf-ab.sh --runs 15 --no-counter-gate --cand-dir . --benches "fib tree_transform binary_trees list_ops list_ops_nested json_stream println_loop spawn_loop actor_ping" origin/main`, with load average recorded;
  - repeat once if any row is outside noise;
  - `cap_check_slow` gives ns/op = wall / 1e6, and must be ≤ 1000;
  - `scripts/oracle-base.sh ir`, and classify every changed program per the budget table;
  - paste all of it into the PR body.
- [ ] Step 3: Run `scripts/check-docs.sh` and expect PASS.
- [ ] Step 4: Commit `docs/specs: ocap phase 4`; push; open PR A; drive it to green (do not merge).

---

## Self-review notes

- **Spec coverage, §17 row 4:**
  - current authority: Tasks 1–2;
  - limits as intersection: Task 2 (layers) and Task 4;
  - capture by function values: Task 5;
  - spawn and restart: Task 6;
  - `main`'s `needs` and launcher narrowing: Task 3;
  - the conformance suite: Task 7.
- **§18:** the run-time lines are in Task 7's fixture list. The `restrict`, grant and `mock` lines belong to phases 5–7. "No-scope programs: IR unchanged apart from the per-operation check" is Task 10, with the entry call disclosed.
- **§21 module-level code:** Task 5's top-level exclusion and `toplevel_closure_runs_under_caller`.
- **Across nodes:** deferred with a todo (decision 7).
