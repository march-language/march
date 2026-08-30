# March compiler

March is a statically-typed functional language (ML/Elixir hybrid) compiled with OCaml 5.3.0.

## Keeping specs up to date

**IMPORTANT:** When implementing a feature, always update `specs/todos/` and `specs/progress/` in the same commit:
- `specs/todos/` holds one open item per file, named `YYYY-MM-DD-slug.md` (date filed). See `specs/todos/README.md`.
- `specs/progress/` holds one completed item per file, same naming convention. See `specs/progress/README.md`.
- When an item is finished, `git mv` its file from `specs/todos/` to `specs/progress/` (or delete it and add a new
  dated file in `specs/progress/`) in the same commit that lands the fix — don't leave a stale open file behind.
- Don't hand-maintain a running "Current State" test count anywhere; run `scripts/run-tests.sh` for the live number.

These directories are the canonical record of what exists. Do not let them go stale. One item, one file — this
structure exists specifically so two PRs filing or closing different items never conflict with each other.

**Doc freshness lint.** `scripts/check-docs.sh` (run in CI) guards the current-truth docs
(root guides, `docs/`, `specs/features/`, the agent SKILL) against two kinds of rot: dead
compiler-source pointers (e.g. a path that moved) and stale stdlib module counts. It does
**not** lint the historical corpus (`specs/plans/`, dated design specs, `specs/todos/`,
`specs/progress/`). If a current doc must reference a since-removed file or a frozen
count, say so in words ("no longer exists", "removed") or add a `doc-lint:ignore-count` /
`doc-lint:ignore-file` marker — don't silently let the pointer rot.

## Maintaining the changelog

`CHANGELOG.md` (repo root, [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format)
is the user-facing digest of what shipped — a different audience than `specs/progress/`
(implementer-level detail, one file per fix). When a user-visible fix, feature, or
behavior change lands, add a bullet under `## [Unreleased]` in the same commit (`### Added`
/ `### Fixed` / `### Changed` / `### Documentation` as appropriate — see existing entries).
Skip purely internal refactors with no observable effect. When a release is tagged, rename
`[Unreleased]` to the new version + date and start a fresh empty `[Unreleased]` above it;
don't backfill history for versions that predate the file.

## Build & test

The opam switch is `march`. `opam` and `dune` are available directly in PATH — no wrapper needed.

**NEVER use `eval $(opam env ...)` or any opam env setup prefix.** Run `dune`, `opam`, etc. directly without any preamble.

```
dune build          # build everything
dune runtest        # run all tests
dune exec march -- file.march   # run the compiler
```

### Parallel-agent / reliable test invocation

`dune runtest` uses a per-project RPC daemon. Stale zombie dune processes from prior sessions block new runs and prevent log files from updating. Use one of:

```bash
# 1. Agent-safe script — shuts down stale daemon, builds, runs binaries directly
scripts/run-tests.sh                   # full suite (~17s)
scripts/run-tests.sh -q                # quick only, skips Slow tests (~2s)
scripts/run-tests.sh compiler eval     # subset by name
scripts/run-tests.sh -q stdlib         # quick subset
scripts/run-tests.sh stdlib_march      # the .march test files under test/stdlib/
scripts/run-tests.sh test_jit          # REPL-JIT / --jit alcotest suite
scripts/run-tests.sh lsp               # the LSP analysis suite (lsp/test/)

# Suites: compiler, eval, codegen, stdlib, stdlib_march, test_jit, lsp, utf16,
# jsonrpc, incremental, query_cli. The last five are the LSP suites and live
# under lsp/test/, not test/. An unknown
# name is a hard error listing the known suites, not a confusing dune build
# failure.

# 2. Direct binary invocation (no dune RPC at execution time)
dune build test/run_compiler.exe test/run_eval.exe test/run_codegen.exe test/run_stdlib.exe test/test_stdlib_march.exe test/test_jit.exe
./_build/default/test/run_compiler.exe -e
./_build/default/test/run_eval.exe -e
./_build/default/test/run_codegen.exe -e
./_build/default/test/run_stdlib.exe -e
./_build/default/test/test_stdlib_march.exe -e
# test_jit needs MARCH_BIN pointed at a freshly built compiler or its cases
# silently skip (reported as passing) — scripts/run-tests.sh sets this for
# you; direct invocation needs it explicitly:
MARCH_BIN="$PWD/_build/default/bin/main.exe" ./_build/default/test/test_jit.exe -e
# The LSP suites live under lsp/test/. test_jsonrpc drives a real march-lsp
# process over stdio, so lsp/bin/main.exe must be built or all 22 of its cases
# die with Unix.ENOENT; and they are cwd-sensitive -- run them from the repo
# root or test_lsp's "introduce pipe offered" case fails spuriously.
dune build lsp/bin/main.exe lsp/test/test_lsp.exe lsp/test/test_utf16.exe lsp/test/test_jsonrpc.exe lsp/test/test_incremental.exe lsp/test/test_query_cli.exe
./_build/default/lsp/test/test_lsp.exe -e

# 3. Standard dune flags for one-off runs
dune runtest --no-buffer   # real-time output (lines appear as they're written)
dune runtest --force       # re-run even if inputs are cached (avoids silent no-output)
```

To unstick a stale daemon: `dune shutdown` (dune 3.x).

**Shared dune cache.** Dune's build cache is enabled user-globally
(`~/.config/dune/config`), so identical compilation actions are reused across
all worktrees and sessions instead of recompiled — a fresh worktree's build is
mostly cache hits. If you suspect the cache during compiler debugging, bypass
it with `DUNE_CACHE=disabled dune build ...`. Bound its growth occasionally
with `dune cache trim --size 20GB`.

24 tests in `run_stdlib` are marked `Slow` and skipped by `-q`: 6 JIT/interpreter
parity tests (~5s), 15 compiled adversarial regression tests (~20s), 2 pbkdf2
key-derivation tests (~3s), and 1 vault concurrency test. Run the full suite
before merging to main.

After implementing or completing a feature, `git mv` its file from `specs/todos/` to `specs/progress/` (or file a new dated entry in `specs/progress/`) to keep them current.

After changing a feature, run the benchmark(s) that exercise it to catch regressions — see `specs/benchmarks.md` for the mapping. Quick reference: Perceus/FBIP changes → `bench/tree_transform.march`; closure/HOF changes → `bench/list_ops.march`; allocation/GC changes → `bench/binary_trees.march`. **Always run benchmarks compiled** (`march --compile --opt 2 bench/<name>.march -o /tmp/<name> && /tmp/<name>`) — interpreted (`dune exec march --`) can take hours on `fib`-shaped benchmarks.

### TIR golden-snapshot tests

`test/run_snapshots.exe` pins the pretty-printed TIR (`lib/tir/pp.ml`) for a small
hand-picked corpus (`test/snapshots/src/*.march`) at two pipeline stages —
post-lower (`test/snapshots/lower/*.expected`) and post-Perceus/RC-insertion
(`test/snapshots/perceus/*.expected`) — so a lowering/monomorphization/
defunctionalization/Perceus refactor that changes the emitted IR shape shows up
as a readable diff instead of only surfacing later as a runtime regression.
Regenerate deliberately after an intentional TIR-shape change with
`UPDATE_SNAPSHOTS=1 ./_build/default/test/run_snapshots.exe -e`, then review
`git diff test/snapshots/` before committing — the diff IS the code review
artifact. See the workflow/design comment at the top of `test/test_snapshots.ml`
for the full detail (printer choice, prelude-noise filtering, fresh-name-counter
determinism).

### Refactor oracles — prove a change moved nothing

Three scripts exist to prove a refactor changed no observable behaviour. Each
records a baseline, then compares. **Prove any oracle goes RED on a deliberate
perturbation before you trust a GREEN** — two of these three shipped broken
(a `${1:?usage … {a|b} …}` bash expansion ends at the *first* `}`, so the mode
argument was mangled and every run died before touching a fixture), and one of
them was certified "verified" by a review while in that state.

```
scripts/ir-oracle.sh     baseline|check <dir>   # hashes --emit-llvm over ~240 programs
scripts/refine-oracle.sh baseline|check <dir>   # refinement diagnostics over ~297 fixtures
scripts/types-oracle.sh  baseline|check <dir>   # two-tier: core-AST inference results + diagnostic text
```

What they do **not** cover, which matters when choosing one:
- `ir-oracle` is blind to `lib/eval/` (the interpreter is never emitted as IR) and
  to `lsp/` — a green there proves nothing about those trees. For interpreter
  changes use the test suite plus `bench/run_interp_bench.sh --modes interp`.
- `types-oracle` is two-tier because neither channel suffices alone: `--check`
  prints nothing on an accepting program, and `--emit-core-ast`'s JSON keeps only
  each diagnostic's first line, dropping provenance and hint text.
- No oracle sees **match-arm order**, **module-initialisation order**, or any
  behaviour the corpus does not exercise. A reordering refactor can be green and
  wrong; check those properties directly.
- Run oracles under a **private `HOME`**: `~/.cache/march` is shared across
  worktrees and its cached spans carry the populating worktree's absolute paths,
  which produces phantom diffs naming someone else's directory.

Related: `dune build @types-check` **without `--force` is vacuous** — it exits 0
with a zero-byte log. Assert on the log's contents, never on the exit code.

## Multi-file compilation (MARCH_LIB_PATH)

March accepts exactly ONE input file per invocation. Multi-file projects (apps + library deps) use the `MARCH_LIB_PATH` environment variable to auto-discover all `.march` files in dependency directories.

```bash
cd /Users/80197052/code/march
MARCH_LIB_PATH=/path/to/dep1/lib:/path/to/dep2/src \
  ./_build/default/bin/main.exe --compile -o output_binary entry.march
```

March walks ALL `.march` files in each `MARCH_LIB_PATH` directory recursively and loads their modules automatically. The entry file is the single `.march` file passed on the command line.

**CAS cache:** Compiled binaries are content-hash cached in `<project>/.march/cas/artifacts-v2/` (**not** `artifacts/` — that is the inert v1 pointer store; deleting only it clears nothing). The cache key includes digests of the compiler executable and the runtime C sources (`runtime/*.c`, `runtime/*.h`) **of the runtime directory the compiler actually compiles** — the driver resolves it once (exe-relative first, `MARCH_RUNTIME_DIR` overrides) and registers it with the CAS — so editing the runtime or rebuilding the compiler invalidates it automatically. Note that "the runtime the compiler compiles" is the *staged* one, `_build/default/runtime`, which a targeted `dune build bin/main.exe` does **not** refresh: after editing `runtime/*.c`, build a target that restages it (e.g. `dune build --root .` or any rule with a `runtime` dep) or the edit is simply not in the build at all. If a cache ever looks wrong anyway, clear it with:

```bash
rm -rf /Users/80197052/code/march/.march/cas/artifacts-v2/
```

**Example (test_conduit_app):**
```bash
cd /Users/80197052/code/march && \
  MARCH_LIB_PATH=/Users/80197052/code/conduit/lib:/Users/80197052/code/test_conduit_app/src \
  ./_build/default/bin/main.exe --compile \
  -o /Users/80197052/code/test_conduit_app/bin/test_conduit_app \
  /Users/80197052/code/test_conduit_app/src/test_conduit_app.march
```

## Searching the codebase

**Use `forge search` to find modules, functions, types, and other code constructs.** This is the primary way to discover what exists in the codebase.

```
forge search "function_name"    # search for a function
forge search "ModuleName"       # search for a module
forge search "type_name"        # search for a type
forge search --callers NAME     # reverse-reference: find every resolved call/ctor/type-use of NAME
```

Always use `forge search` before grepping or manually reading files when looking for modules, functions, or types in March code. Use `--callers` before grepping when checking whether a declaration is still used anywhere.

## Project layout

```
bin/main.ml                 compiler entry point (parse→desugar→typecheck→eval)
lib/ast/ast.ml              AST types (span, expr, pattern, decl, …)
lib/lexer/lexer.mll         ocamllex lexer
lib/parser/parser.mly       menhir parser
lib/desugar/desugar.ml      pipe desugar, multi-head fn → single EMatch clause
                             (+desugar_derive: derive/satisfy expansion + span uniquification)
lib/typecheck/                bidirectional HM type inference: typecheck (inference core),
                             +typecheck_{env,types,builtins,exhaustive,caps,tailcall,unify,reorder,modcaps,session}
lib/eval/                     tree-walking interpreter: eval (evaluator),
                             +eval_{types,prim,builtins,runtime,net,session,simd}
lib/tir/                    typed IR: lower (+lower_state/types/match/decls/expr/actor/tests), mono, defun,
                             perceus (+perceus_core/liveness/elide/fbip/scrut), borrow, fusion,
                             llvm_emit (+llvm_ctx/builtins/eq/data/case/calls/tco/toplevel/repl,
                             and the per-arm bodies in llvm_emit_{arith,alloc,call,data,html,task,tcoarm,simd,nmap}),
                             builtin_name (closed variant for builtin dispatch),
                             tir_names (cross-pass name contracts), rc_types (needs_rc/borrow_eligible)
lib/refinecheck/            refinement/contract checking (SMT): refine_check (orchestrator),
                             +refine_{encode,scope,resolve,call,post} — the pipeline in
                             dependency order, each including the one before it; plus
                             division_safety, precond/postcond/return/cap_infer, obligation
lib/jit/                    REPL JIT compiler
lib/errors/errors.ml        diagnostic type (Error/Warning/Hint + span)
lib/search/search.ml        Hoogle-style type/name search engine
lsp/lib/                    LSP analysis: analysis (+.mli) + analysis_{types,util},
                             code_actions_{ast,diag} (the two code-action engines)
lsp/test/                   test_lsp (Alcotest registration only) + the test bodies in
                             test_lsp_{harness,analysis,actions,perf,features,refactor,html,depot}
stdlib/                     116 March stdlib modules (list, map, enum, sort, crypto, http, json, distributed-OTP, …)
runtime/                    C runtime (GC, scheduler, HTTP, TLS, WASM)
forge/                      build tool (new, build, run, test, deps, search, publish subcommands)
lsp/                        LSP server (diagnostics, hover, goto-def, completions, code actions)
test/                       alcotest suites — run_{compiler,eval,codegen,stdlib}.ml drivers over test_*.ml
specs/                      design specs, progress tracking, feature plans
```

## Surface syntax notes

See [specs/lang/surface-syntax.md](specs/lang/surface-syntax.md) for a complete quick-reference of all March syntax.

- Module: `mod Name do ... end` (not `module`)
- Type variants: `type Foo = A | B(Int)` — no leading `|`
- Conditionals: `if cond do ... else ... end` — `else` is MANDATORY (omitting it: "March `if` expressions always need an `else` branch"); `then` is rejected ("I don't recognize `then` here — March uses do/end blocks instead.")
- **`else if` chains need one `end` per `if`, not one for the chain.** A two-branch
  chain ends `end end`, a three-branch chain `end end end`. There is no
  `elif`/`elsif`, and `else if` is genuinely a nested `if` in the else position:
  ```march
  if a do 1 else if b do 2 else 3 end end          -- two ifs, two ends
  ```
  Getting this wrong gives a confusing "I got stuck here" pointing at the NEXT
  declaration, not at the `if` — the parser only notices when it runs out of
  input. See `stdlib/uri.march:62` (`else -1 end end end`) for a real one.
- Block lets: `let x = expr` with no `in`; subsequent block exprs see the binding
- Result propagation: `let? p = e` binds the `Ok` payload and returns `Err(e)` immediately; RHS must be `Result`; cannot be the last expr in a block
- No `;` — use newlines to separate block expressions
- Match arms use `block_body` — multi-expression arms with `let` bindings are supported:
  ```march
  match x do
    Some(v) ->
      let y = v + 1
      let z = y * 2
      z
    None -> 0
  end
  ```
  The token filter uses lookahead to distinguish arm boundaries from block continuations. A `do...end` wrapper also works: `Some(v) -> do ... end`

### Lambda syntax (critical — common source of bugs)

Lambdas use `fn ... -> body` (arrow form only, NO `do...end` block form).
The body is a single expression, OR zero or more `let` bindings followed by a
final expression — identical to match arm block bodies:

```march
fn x -> x + 1                     -- single param, single expr
fn _ -> 42                        -- wildcard param
fn (a, b) -> a + b                -- multiple params (parenthesized)
fn () -> some_function()          -- zero-arg (explicit form)
fn -> some_function()             -- zero-arg (short form, identical)

-- Multi-expression bodies with let bindings:
fn x ->
  let y = x + 1
  let z = y * 2
  z

fn ->
  let result = compute()
  result + 1
```

**Common mistakes:**
- `fn _ -> expr` when you want zero-arg — WRONG. `_` is a 1-arg lambda; calling it with 0 args gives "arity mismatch: expected 1 args, got 0"
- `task_spawn(fn -> f())` — WRONG if `task_spawn` passes 1 arg to the callback. Use `fn _ -> f()` (1-arg discard).

### Visibility

- `fn name(...)` — public (default)
- `pfn name(...)` — private (module-internal)
- `type Foo = ...` — public type (no `pub` keyword needed)

## Pipeline

1. Parse (`March_parser.Parser.module_`)
2. Desugar (`March_desugar.Desugar.desugar_module`)
3. Typecheck (`March_typecheck.Typecheck.check_module`) — prints diagnostics, exits 1 on errors
4. Eval (`March_eval.Eval.run_module`) — calls `main()` if present

<!-- deciduous:start -->
## Decision Graph Workflow

**THIS IS MANDATORY. Log decisions IN REAL-TIME, not retroactively.**

### Available Slash Commands

| Command | Purpose |
|---------|---------|
| `/decision` | Manage decision graph - add nodes, link edges, sync |
| `/recover` | Recover context from decision graph on session start |
| `/work` | Start a work transaction - creates goal node before implementation |
| `/document` | Generate comprehensive documentation for a file or directory |
| `/build-test` | Build the project and run the test suite |
| `/serve-ui` | Start the decision graph web viewer |
| `/sync-graph` | Export decision graph to GitHub Pages |
| `/decision-graph` | Build a decision graph from commit history |
| `/sync` | Multi-user sync - pull events, rebuild, push |

### Available Skills

| Skill | Purpose |
|-------|---------|
| `/pulse` | Map current design as decisions (Now mode) |
| `/narratives` | Understand how the system evolved (History mode) |
| `/archaeology` | Transform narratives into queryable graph |

### The Node Flow Rule - CRITICAL

The canonical flow through the decision graph is:

```
goal -> options -> decision -> actions -> outcomes
```

- **Goals** lead to **options** (possible approaches to explore)
- **Options** lead to a **decision** (choosing which option to pursue)
- **Decisions** lead to **actions** (implementing the chosen approach)
- **Actions** lead to **outcomes** (results of the implementation)
- **Observations** attach anywhere relevant
- Goals do NOT lead directly to decisions -- there must be options first
- Options do NOT come after decisions -- options come BEFORE decisions
- Decision nodes should only be created when an option is actually chosen, not prematurely

### The Core Rule

```
BEFORE you do something -> Log what you're ABOUT to do
AFTER it succeeds/fails -> Log the outcome
CONNECT immediately -> Link every node to its parent
AUDIT regularly -> Check for missing connections
```

### Behavioral Triggers - MUST LOG WHEN:

| Trigger | Log Type | Example |
|---------|----------|---------|
| User asks for a new feature | `goal` **with -p** | "Add dark mode" |
| Exploring possible approaches | `option` | "Use Redux for state" |
| Choosing between approaches | `decision` | "Choose state management" |
| About to write/edit code | `action` | "Implementing Redux store" |
| Something worked or failed | `outcome` | "Redux integration successful" |
| Notice something interesting | `observation` | "Existing code uses hooks" |

### Document Attachments

Attach files (images, PDFs, diagrams, specs, screenshots) to decision graph nodes for rich context.

```bash
# Attach a file to a node
deciduous doc attach <node_id> <file_path>
deciduous doc attach <node_id> <file_path> -d "Architecture diagram"
deciduous doc attach <node_id> <file_path> --ai-describe

# List documents
deciduous doc list              # All documents
deciduous doc list <node_id>    # Documents for a specific node

# Manage documents
deciduous doc show <doc_id>     # Show document details
deciduous doc describe <doc_id> "Updated description"
deciduous doc describe <doc_id> --ai   # AI-generate description
deciduous doc open <doc_id>     # Open in default application
deciduous doc detach <doc_id>   # Soft-delete (recoverable)
deciduous doc gc                # Remove orphaned files from disk
```

**When to suggest document attachment:**

| Situation | Action |
|-----------|--------|
| User shares an image or screenshot | Ask: "Want me to attach this to the current goal/action node?" |
| User references an external document | Ask: "Should I attach a copy to the decision graph?" |
| Architecture diagram is discussed | Suggest attaching it to the relevant goal node |
| Files not in the project are dropped in | Attach to the most relevant active node |

**Do NOT aggressively prompt for documents.** Only suggest when files are directly relevant to a decision node. Files are stored in `.deciduous/documents/` with content-hash naming for deduplication.

### CRITICAL: Capture VERBATIM User Prompts

**Prompts must be the EXACT user message, not a summary.** When a user request triggers new work, capture their full message word-for-word.

**BAD - summaries are useless for context recovery:**
```bash
# DON'T DO THIS - this is a summary, not a prompt
deciduous add goal "Add auth" -p "User asked: add login to the app"
```

**GOOD - verbatim prompts enable full context recovery:**
```bash
# Use --prompt-stdin for multi-line prompts
deciduous add goal "Add auth" -c 90 --prompt-stdin << 'EOF'
I need to add user authentication to the app. Users should be able to sign up
with email/password, and we need OAuth support for Google and GitHub. The auth
should use JWT tokens with refresh token rotation.
EOF

# Or use the prompt command to update existing nodes
deciduous prompt 42 << 'EOF'
The full verbatim user message goes here...
EOF
```

**When to capture prompts:**
- Root `goal` nodes: YES - the FULL original request
- Major direction changes: YES - when user redirects the work
- Routine downstream nodes: NO - they inherit context via edges

**Updating prompts on existing nodes:**
```bash
deciduous prompt <node_id> "full verbatim prompt here"
cat prompt.txt | deciduous prompt <node_id>  # Multi-line from stdin
```

Prompts are viewable in the web viewer.

### CRITICAL: Maintain Connections

**The graph's value is in its CONNECTIONS, not just nodes.**

| When you create... | IMMEDIATELY link to... |
|-------------------|------------------------|
| `outcome` | The action that produced it |
| `action` | The decision that spawned it |
| `decision` | The option(s) it chose between |
| `option` | Its parent goal |
| `observation` | Related goal/action |
| `revisit` | The decision/outcome being reconsidered |

**Root `goal` nodes are the ONLY valid orphans.**

### Quick Commands

```bash
deciduous add goal "Title" -c 90 -p "User's original request"
deciduous add action "Title" -c 85
deciduous link FROM TO -r "reason"  # DO THIS IMMEDIATELY!
deciduous serve   # View live (auto-refreshes every 30s)
deciduous sync    # Export for static hosting

# Metadata flags
# -c, --confidence 0-100   Confidence level
# -p, --prompt "..."       Store the user prompt (use when semantically meaningful)
# -f, --files "a.rs,b.rs"  Associate files
# -b, --branch <name>      Git branch (auto-detected)
# --commit <hash|HEAD>     Link to git commit (use HEAD for current commit)
# --date "YYYY-MM-DD"      Backdate node (for archaeology)

# Branch filtering
deciduous nodes --branch main
deciduous nodes -b feature-auth
```

### CRITICAL: Link Commits to Actions/Outcomes

**After every git commit, link it to the decision graph!**

```bash
git commit -m "feat: add auth"
deciduous add action "Implemented auth" -c 90 --commit HEAD
deciduous link <goal_id> <action_id> -r "Implementation"
```

The `--commit HEAD` flag captures the commit hash and links it to the node. The web viewer will show commit messages, authors, and dates.

### Git History & Deployment

```bash
# Export graph AND git history for web viewer
deciduous sync

# This creates:
# - docs/graph-data.json (decision graph)
# - docs/git-history.json (commit info for linked nodes)
```

To deploy to GitHub Pages:
1. `deciduous sync` to export
2. Push to GitHub
3. Settings > Pages > Deploy from branch > /docs folder

Your graph will be live at `https://<user>.github.io/<repo>/`

### Branch-Based Grouping

Nodes are auto-tagged with the current git branch. Configure in `.deciduous/config.toml`:
```toml
[branch]
main_branches = ["main", "master"]
auto_detect = true
```

### Audit Checklist (Before Every Sync)

1. Does every **outcome** link back to what caused it?
2. Does every **action** link to why you did it?
3. Any **dangling outcomes** without parents?

### Git Staging Rules - CRITICAL

**NEVER use broad git add commands that stage everything:**
- ❌ `git add -A` - stages ALL changes including untracked files
- ❌ `git add .` - stages everything in current directory
- ❌ `git add -a` or `git commit -am` - auto-stages all tracked changes
- ❌ `git add *` - glob patterns can catch unintended files

**ALWAYS stage files explicitly by name:**
- ✅ `git add src/main.rs src/lib.rs`
- ✅ `git add Cargo.toml Cargo.lock`
- ✅ `git add .claude/commands/decision.md`

**Why this matters:**
- Prevents accidentally committing sensitive files (.env, credentials)
- Prevents committing large binaries or build artifacts
- Forces you to review exactly what you're committing
- Catches unintended changes before they enter git history

### Session Start Checklist

```bash
deciduous check-update    # Update needed? Run 'deciduous update' if yes
deciduous nodes           # What decisions exist?
deciduous edges           # How are they connected? Any gaps?
deciduous doc list        # Any attached documents to review?
git status                # Current state
```

### Multi-User Sync

Sync decisions with teammates via event logs:

```bash
# Check sync status
deciduous events status

# Apply teammate events (after git pull)
deciduous events rebuild

# Compact old events periodically
deciduous events checkpoint --clear-events
```

Events auto-emit on add/link/status commands. Git merges event files automatically.
<!-- deciduous:end -->
