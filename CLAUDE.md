# March compiler

March is a statically-typed functional language (ML/Elixir hybrid) compiled with OCaml 5.3.0.

## Keeping specs up to date

**IMPORTANT:** When implementing a feature, always update `specs/todos.md` and `specs/progress.md` in the same commit:
- Move completed items from the todo list to the "Done" section in `specs/todos.md`.
- Update the "Current State" counts in `specs/progress.md` (test count, known failures).
- Add any new capabilities to the feature bullet list in `specs/progress.md`.

These files are the canonical record of what exists. Do not let them go stale.

## Build & test

The opam switch is `march`. `opam` and `dune` are available directly in PATH — no wrapper needed.

**NEVER use `eval $(opam env ...)` or any opam env setup prefix.** Run `dune`, `opam`, etc. directly without any preamble.

```
dune build          # build everything
dune runtest        # run all 50 tests
dune exec march -- file.march   # run the compiler
```

After implementing or completing a feature, update `specs/todos.md` (move item to Done) and `specs/progress.md` (add to feature list) to keep them current.

After changing a feature, run the benchmark(s) that exercise it to catch regressions — see `specs/benchmarks.md` for the mapping. Quick reference: Perceus/FBIP changes → `bench/tree_transform.march`; closure/HOF changes → `bench/list_ops.march`; allocation/GC changes → `bench/binary_trees.march`.

## Searching the codebase

**Use `forge search` to find modules, functions, types, and other code constructs.** This is the primary way to discover what exists in the codebase.

```
forge search "function_name"    # search for a function
forge search "ModuleName"       # search for a module
forge search "type_name"        # search for a type
```

Always use `forge search` before grepping or manually reading files when looking for modules, functions, or types in March code.

## Project layout

```
bin/main.ml                 compiler entry point (parse→desugar→typecheck→eval)
lib/ast/ast.ml              AST types (span, expr, pattern, decl, …)
lib/lexer/lexer.mll         ocamllex lexer
lib/parser/parser.mly       menhir parser
lib/desugar/desugar.ml      pipe desugar, multi-head fn → single EMatch clause
lib/typecheck/typecheck.ml  bidirectional HM type inference
lib/eval/eval.ml            tree-walking interpreter (1180+ tests)
lib/tir/                    typed IR: lower, mono, defun, perceus, borrow, fusion, llvm_emit
lib/jit/                    REPL JIT compiler
lib/errors/errors.ml        diagnostic type (Error/Warning/Hint + span)
lib/search/search.ml        Hoogle-style type/name search engine
stdlib/                     57 March stdlib modules (bastion, csrf, session, html, islands, …)
runtime/                    C runtime (GC, scheduler, HTTP, TLS, WASM)
forge/                      build tool (new, build, run, test, deps, bastion subcommands)
lsp/                        LSP server (diagnostics, hover, goto-def, completions, code actions)
test/test_march.ml          alcotest suite
specs/                      design specs, progress tracking, feature plans
```

## Surface syntax notes

See [syntax_reference.md](syntax_reference.md) for a complete quick-reference of all March syntax.

- Module: `mod Name do ... end` (not `module`)
- Type variants: `type Foo = A | B(Int)` — no leading `|`
- Conditionals: `if cond do ... end` — use `do...end`, `else` is optional, NO `then` keyword
- Block lets: `let x = expr` with no `in`; subsequent block exprs see the binding
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
fn () -> some_function()          -- ZERO-ARG: must use fn () -> ...

-- Multi-expression bodies with let bindings:
fn x ->
  let y = x + 1
  let z = y * 2
  z

fn () ->
  let result = compute()
  result + 1
```

**Common mistakes:**
- `fn -> expr` — PARSE ERROR. Zero-arg lambdas MUST use `fn () -> expr`
- `fn _ -> expr` when you want zero-arg — WRONG. `_` is a 1-arg lambda; calling it with 0 args gives "arity mismatch: expected 1 args, got 0"

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
