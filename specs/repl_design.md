# March REPL v2 — Design Spec

## Overview

Upgrade the March REPL from a basic `input_line` loop into a full TUI application with syntax highlighting, history navigation, tab completion, a live variables-in-scope panel, magic result variables, and additional features that leverage March's unique language capabilities.

**Dependencies**: `notty` + `notty.unix` (TUI rendering and input handling).

**Non-TUI fallback**: When stdin is not a TTY (piped input, dumb terminals, CI), the REPL falls back to the current `input_line`-based loop with no colors or TUI. Detected via `Unix.isatty Unix.stdin`.

---

## 1. Architecture & Module Structure

New `lib/repl/` library replaces the REPL logic currently in `bin/main.ml`:

```
lib/repl/
  repl.ml        — main loop: read → parse → desugar → typecheck → eval → render
  tui.ml         — notty screen management, pane layout, resize handling
  input.ml       — keystroke dispatch, line buffer, readline-style editing (Ctrl+A/E/W/K/U, word movement)
  highlight.ml   — syntax highlighting (lexer → color attribute mapping)
  complete.ml    — tab completion engine (context-aware)
  history.ml     — input history (ring buffer + file persistence)
  result_vars.ml — magic v/v() result variable management
  multiline.ml   — multi-line input completion heuristics (migrated from bin/main.ml)
```

`bin/main.ml` retains the file-compiler path. When invoked with no arguments or `--repl`, it delegates to `March_repl.Repl.run`.

### Main Loop

```
while running:
  1. Render screen (left pane history + input, right pane scope, status bar)
  2. Read keystroke via notty (raw mode key events)
  3. Dispatch keystroke through input.ml (line editing state machine)
  4. On Enter (with complete input):
     a. Parse → Desugar → Typecheck → Eval
     b. Push result to history buffer
     c. Update scope panel
     d. Update result variables (v, v(1), v(2), ...)
  5. On Tab: trigger completion
  6. On Up/Down: navigate history
  7. On Ctrl+R: incremental search
  8. On resize: recompute layout
```

---

## 2. Screen Layout

```
┌─────────────────────────────────────┬──────────────────────┐
│ march(1)> let x = 42               │ Variables in Scope   │
│ val x = 42                          │ ──────────────────── │
│ march(2)> x + 1                     │ x : Int = 42         │
│ = 43                                │ v : Int = 43         │
│ march(3)> fn double(n) do n*2 end   │ double : Int -> Int  │
│ val double = <fn>                   │                      │
│ march(4)> █                         │                      │
│                                     │                      │
│                                     │                      │
│                                     │                      │
├─────────────────────────────────────┴──────────────────────┤
│ March REPL v0.1 │ :help │ Tab: complete │ ↑↓: history      │
└────────────────────────────────────────────────────────────┘
```

- **Left pane (70% width)**: Scrollable REPL transcript (history + output) with active input line pinned at bottom. Scroll with Shift+Up/Down or mouse wheel.
- **Right pane (30% width)**: Live variables in scope, showing `name : Type = value` (or `<fn>`, `<actor>` for non-printable values). Scrollable when bindings exceed pane height. Updated after every successful eval. Built-in bindings (like `+`, `println`) are hidden — only user-defined bindings shown.
- **Status bar (1 row)**: Version string, available commands hint, current mode indicator.
- **Pane split**: Fixed ratio in v1 (not user-resizable).

### Rendering with Notty

The screen is composed as a `Notty.I.t` image each frame:

```ocaml
let screen =
  let panes = I.hcat [
    I.hpad 0 1 left_pane;        (* 70% width, 1-col right padding *)
    I.char A.empty '│' 1 h;      (* vertical separator *)
    I.hpad 1 0 right_pane;       (* 30% width, 1-col left padding *)
  ] in
  I.(panes <-> status_bar)       (* vertical stack: panes above status bar *)
```

Resize events (`Notty_unix.Term.event` → `Resize (w, h)`) trigger recomputation of pane widths.

---

## 3. Colored Output & Syntax Highlighting

### Input Highlighting

As the user types, the current input is re-lexed on each keystroke using `March_lexer` and rendered with color attributes:

| Token Class | Color | Examples |
|-------------|-------|---------|
| Keywords | Bold magenta | `fn`, `do`, `end`, `let`, `match`, `if`, `mod`, `actor`, `type` |
| Type names | Cyan | `Int`, `String`, any capitalized identifier |
| Constructors | Cyan bold | `Some`, `None`, `Ok`, `Err` |
| String literals | Green | `"hello"` |
| Number literals | Yellow | `42`, `3.14` |
| Atoms | Blue | `:ok`, `:error` |
| Comments | Dim gray | `-- comment` |
| Operators | White bold | `+`, `\|>`, `->`, `=`, `\|` |
| Default | Terminal default | identifiers, punctuation |

**Implementation** (`highlight.ml`):

```ocaml
val highlight : string -> Notty.I.t
(** Lex the input string and return a styled notty image.
    Falls back to unstyled text for the tail if lexing fails mid-input. *)
```

The lexer is run in a best-effort mode. If the input is partial (e.g., unterminated string), everything up to the failure point is highlighted and the rest is rendered in default color.

### Output Coloring

| Output Kind | Style |
|-------------|-------|
| `val name = value` | `val` dim, `name` bold white, `=` dim, value default |
| `= value` (expression result) | `=` dim, value green |
| `error:` label | Red bold |
| `warning:` label | Yellow bold |
| `hint:` / `note:` label | Blue |
| Type annotations in diagnostics | Cyan |
| Prompt `march(N)>` | Bold blue for `march`, dim for parens/number, bold white for `>` |

The existing `print_repl_diag` function is replaced with a `render_diag : diagnostic -> Notty.I.t` that returns styled images instead of printing to stdout.

---

## 4. History & Line Editing

### History Navigation

- In-memory ring buffer of past inputs, navigated with Up/Down arrows.
- Persisted to file on exit, loaded on startup.
  - **Path**: `MARCH_HISTORY_FILE` env var, defaulting to `~/.march_history`.
  - **Size cap**: `MARCH_HISTORY_SIZE` env var, defaulting to `1000`.
- Multi-line inputs stored as a single history entry. **File format**: entries are separated by NUL bytes (`\x00`). Newlines within entries are preserved literally. This avoids ambiguity with entries containing literal `\n` sequences. The file is read/written atomically on startup/shutdown.
- **Reverse search**: Ctrl+R enters incremental search mode. Prompt changes to `(reverse-i-search)'query': match`. Each keystroke narrows the search. Enter accepts, Esc cancels.

### Line Editing Keybindings

Implemented in `input.ml` as a state machine over notty key events (`Notty.Unescape.event`). No external line-editing library — notty owns the terminal exclusively.

| Key | Action |
|-----|--------|
| Ctrl+A / Home | Move to start of line |
| Ctrl+E / End | Move to end of line |
| Ctrl+B / Left | Move back one char |
| Ctrl+F / Right | Move forward one char |
| Alt+B | Move back one word |
| Alt+F | Move forward one word |
| Ctrl+W | Delete word backward |
| Ctrl+K | Kill to end of line |
| Ctrl+U | Kill entire line |
| Ctrl+D | EOF on empty line; delete char otherwise |
| Ctrl+R | Reverse incremental search |
| Ctrl+L | Force full redraw |

**Kill ring**: Ctrl+K and Ctrl+W push deleted text onto a kill ring. Ctrl+Y yanks the most recent kill. This is a small ring (8 entries), not a full emacs kill ring.

### Multi-line Input

Multi-line completion heuristics are migrated from the existing `bin/main.ml` implementation (`do_end_depth`, `ends_with_with`, `starts_with_pipe`) into `lib/repl/multiline.ml`.

When input is syntactically incomplete:
- Open `do`/`end` depth > 0
- Last line ends with `with` (match expression)
- Last line starts with `|` (match arm)

...then Enter inserts a newline and shows a continuation prompt (indented, aligned). A blank line or Ctrl+D on an empty continuation line force-submits the input.

**Known limitation (carried forward)**: Tokens inside string literals can cause false depth calculations. The blank-line escape hatch mitigates this.

### Input Architecture

Since notty and linenoise both require exclusive terminal control (raw mode), we use notty exclusively for all terminal I/O. The `input.ml` module implements readline-style editing as a pure state machine:

```ocaml
type input_state = {
  buffer : string;       (* current line content *)
  cursor : int;          (* cursor position in buffer *)
  kill_ring : string list;
  history_pos : int option;  (* None = editing new input *)
}

val handle_key : input_state -> Notty.Unescape.key -> input_state * input_action
(** Pure function: takes current state + key event, returns new state + action.
    Actions: `Noop | Redraw | Submit of string | Complete | HistorySearch | EOF` *)
```

This is more work than using linenoise but gives us full control over rendering — the line buffer is always rendered through `highlight.ml` into the notty screen, with no competing terminal writes.

---

## 5. Tab Completion

### Completion Sources (checked in priority order)

1. **REPL commands** — when input starts with `:`, complete from `:quit`, `:q`, `:env`, `:help`, `:type`, `:clear`, `:reset`
2. **Keywords** — `fn`, `do`, `end`, `let`, `match`, `with`, `if`, `then`, `else`, `mod`, `actor`, `type`, `pub`, `use`, `impl`, `interface`, `sig`, `spawn`, `send`
3. **Identifiers in scope** — variable names, function names, constructor names, type names from the current `tc_env`
4. **Module members** — after `ModuleName.`, complete with that module's exported bindings
5. **Record field completion** — after `expr.`, infer the type of `expr` using `Typecheck.infer_expr`, then complete with that record type's field names

### UX Behavior

- **Single match**: complete inline immediately
- **Multiple matches**: show a popup menu rendered in notty below the cursor line. Each entry shows `name : Type` so the user can see signatures while picking.
  - Tab / Down: cycle forward
  - Shift+Tab / Up: cycle backward
  - Enter: accept selection
  - Esc: dismiss popup
  - Continuing to type narrows the matches
- **No matches**: no popup, no beep, no noise

### Type-Aware Field Completion (`complete.ml`)

```ocaml
val complete_dot : Typecheck.env -> string -> (string * ty) list
(** Given an expression string before the dot, attempt to parse and infer its type,
    then return field names with their types. Returns [] on any failure. *)
```

Pipeline: parse the prefix string into an `Ast.expr` → desugar → call `Typecheck.infer_expr`. If any step fails (partial input that doesn't parse, inference failure, result type isn't a record), return `[]`. No error is surfaced — completion simply shows nothing. This is best-effort by design.

---

## 6. Magic Result Variables

### `v` / `v(n)` — Result History

Every expression evaluation (not declarations) pushes its result onto a history stack.

- `v` or `v()` — the most recent result
- `v(1)` — one step back (second most recent)
- `v(2)` — two steps back
- etc.

**Implementation** (`result_vars.ml`):

```ocaml
type result_history

val create : unit -> result_history
val push : result_history -> Eval.value -> Typecheck.ty -> unit
val get : result_history -> int -> (Eval.value * Typecheck.ty) option
(** get h 0 = most recent, get h 1 = one back, etc. *)
```

**Parser integration**: `v` and `v(n)` are parsed as a dedicated AST node, not as regular identifiers:

```ocaml
(* in ast.ml *)
| EResultRef of int option   (* v = EResultRef None, v(2) = EResultRef (Some 2) *)
```

The parser recognizes `v` as a keyword in REPL mode only (not in file compilation). `v` alone produces `EResultRef None`. `v(n)` where `n` is an integer literal produces `EResultRef (Some n)`. This avoids ambiguity with user-defined bindings named `v` — in the REPL, `v` is reserved.

**Type checking**: The type checker handles `EResultRef` directly by looking up the result history:
- `EResultRef None` → type of the most recent result
- `EResultRef (Some n)` → type of the nth-previous result
- Out of bounds → type error: `"result history index N is out of bounds"`

This avoids the unsoundness of trying to type-check `v(n)` as a function application (where `v : Int` would make `v(n)` a type error before the evaluator could intercept).

**Evaluation**: The evaluator handles `EResultRef` by looking up `result_vars.ml`:
- `EResultRef None` → `get history 0`
- `EResultRef (Some n)` → `get history n`

**Scope panel**: The most recent `v` is shown in the right pane as `v : Type = value`. Older `v(n)` are not shown (to avoid clutter) but are accessible.

**History depth**: Capped at 100 entries. Accessing beyond the cap returns a type error at check time: `"result history only goes back 100 entries"`.

---

## 7. Additional REPL Commands

Extend the existing `:quit` / `:env` with:

| Command | Description |
|---------|-------------|
| `:help` | Show available commands and keybindings |
| `:type <expr>` | Print the inferred type of an expression without evaluating it |
| `:clear` | Clear the REPL transcript (keeps bindings and history) |
| `:reset` | Reset all bindings to base_env, clear result history |
| `:load <file>` | Load and evaluate a `.march` file into the current session |
| `:save <file>` | Save the current session's declarations to a `.march` file |

### `:load` semantics

`:load` reads the file and evaluates its declarations sequentially into the current environment, as if the user had typed each declaration at the prompt. It does **not** wrap the file in a `mod ... end` — the bindings merge directly into the REPL's top-level scope. If the file defines a `main()` function, it is **not** auto-called (unlike file compilation). Actors defined in the file are available for `spawn` but not auto-spawned.

If any declaration fails to typecheck, `:load` stops at that point, prints the error, and keeps all bindings from declarations that succeeded before the failure.

### `:save` semantics

`:save` writes all user-defined declarations from the current session in the order they were entered. Only `let`, `fn`, `type`, `actor`, and `mod` declarations are saved — bare expression evaluations are omitted. The output is a valid `.march` file that can be `:load`ed back.

---

## 8. Suggested Additional Features

Features that would make the March REPL world-class by leveraging the language's unique capabilities:

### 8.1 Actor Inspector (`:actors`)

March has a built-in actor system. The REPL should expose it:

- `:actors` — list all live actors spawned in the session: PID, actor type, state summary, message count
- `:inspect <pid>` — show an actor's current state, message history, and whether it's alive
- Actor state shown in the right pane when inspecting (replaces variables view temporarily)

This turns the REPL into an actor debugger, not just an evaluator.

### 8.2 Type Hole Explorer

March supports typed holes (`?` or `?name`). In the REPL, make them interactive:

- When the user writes an expression with a `?`, show the expected type and all values in scope that would fit the hole
- Offer tab-completion specifically for hole fillers

Example:
```
march(5)> List.map(?, [1,2,3])
  hole expects: Int -> a
  candidates: double : Int -> Int, negate : Int -> Int, int_to_string : Int -> String
```

### 8.3 Pipe Playground

March's `|>` pipe operator is central to the language. Add a `:pipe` mode that shows intermediate values at each pipe stage:

```
march(6)> :pipe [1,2,3,4,5] |> List.filter(fn x -> x > 2) |> List.map(fn x -> x * 10)
  [1, 2, 3, 4, 5]
    |> List.filter(fn x -> x > 2)
  [3, 4, 5]
    |> List.map(fn x -> x * 10)
  [30, 40, 50]
```

Each intermediate value is shown with its type, colored to visually trace the data flow.

### 8.4 Linearity Lens (`:linear`)

March tracks linear and affine types. The REPL can surface this:

- `:linear <name>` — show whether a binding is linear, affine, or unrestricted, and how many uses remain
- Warn when a linear value is about to expire (has been bound but not used)
- In the scope panel, mark linear values with a `!` indicator: `cap ! : Cap(Auth) = <cap>`

### 8.5 Session Replay (`:replay`)

- `:replay` — re-evaluate all inputs from the current session from scratch (useful after a `:load` that changes definitions)
- `:replay <file>` — replay a saved session file
- Useful for reproducible demonstrations and tutorials

### 8.6 Auto-import Suggestions

When the user writes an identifier that isn't in scope but exists in a known module:

```
march(7)> reverse([1,2,3])
  error: undefined variable `reverse`
  hint: did you mean `List.reverse`? (use List.{reverse} to import)
```

This leverages the typechecker's knowledge of all modules and their exports.

### 8.7 Timing & Allocation Info (`:time`)

- `:time <expr>` — evaluate and show wall-clock time and allocation stats
- Useful for performance exploration, especially when the compiler later adds escape analysis and different allocation strategies

### 8.8 Documentation Strings (`:doc`)

If March adds doc comments (e.g., `--- This function does X`), surface them:

- `:doc <name>` — show documentation for a binding, type, or module
- Tab completion popup could show a one-line doc summary alongside the type

### 8.9 Multi-cursor Actor Messaging

An interactive mode for working with actors:

- `:watch <pid>` — add an actor to a "watch list" shown in the right pane with live state updates
- The scope panel could have tabs: `[Vars] [Actors] [Types]` switchable with function keys

### 8.10 Undo (`:undo`)

- `:undo` — roll back the last input (remove its bindings, restore previous env)
- Internally this is cheap: we already snapshot `env` and `tc_env` before each eval. Just keep a stack of snapshots.
- `:undo 3` — roll back last 3 inputs

---

## 9. Dependencies

Add to `dune-project` / `march.opam`:

```
notty (>= 0.2)
notty.unix
```

`notty` is a pure OCaml library with no C dependencies. Note: `notty` has not been updated since 0.2.3 and its upper bound is `ocaml < 5.4`. Since we use OCaml 5.3.0 this works today, but a future OCaml upgrade may require forking or finding an alternative.

No `linenoise` dependency — line editing is implemented in `input.ml` using notty's key events directly. This avoids the terminal ownership conflict between two libraries that both require raw mode.

---

## 10. Migration Path

1. **Phase 1**: Add `lib/repl/` with `notty`. Implement basic TUI layout (two panes, status bar), colored output, history, line editing (`input.ml`), non-TUI fallback. Magic `v` variable. Keep feature parity with current REPL.
2. **Phase 2**: Tab completion (identifiers + commands + keywords). Record field completion.
3. **Phase 3**: Additional commands (`:type`, `:load`, `:save`, `:clear`, `:reset`).
4. **Phase 4**: Actor inspector, pipe playground, type hole explorer.
5. **Phase 5**: Linearity lens, undo, session replay, auto-import suggestions.

Each phase is independently shippable. Phase 1 is the critical path — it replaces the current REPL entirely.
