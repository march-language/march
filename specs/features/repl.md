# March REPL Feature Documentation

## Overview

The March REPL (Read-Eval-Print Loop) is a full-featured interactive environment for evaluating March code and declarations. It provides two interaction modes:

- **TUI Mode** (notty two-pane): Rich terminal UI with syntax highlighting, completions, scope panel, and live actor monitoring
- **Simple Mode** (plain text): Fallback readline-like mode for non-TTY environments and script piping

The REPL automatically selects the appropriate mode based on whether stdin/stdout are connected to a terminal. It integrates with the March debugger, supports JIT compilation for function definitions, and maintains command history across sessions.

## Architecture Overview

### Entry Points

**Main REPL invocation** (`bin/main.ml:326-332`):
```ocaml
match !files with
| [] ->  (* No file argument → launch REPL *)
    let runtime_so = ensure_runtime_so () in
    let jit_ctx = March_jit.Repl_jit.create ~runtime_so () in
    March_repl.Repl.run ~stdlib_decls:(load_stdlib ()) ~jit_ctx:(Some jit_ctx) ()
| [f] -> compile f
```

**REPL module** (`lib/repl/repl.ml` - 1217 lines, `lib/repl/repl.mli`):
- `Repl.run()`: Main entry point (line 33-38 in .mli)
- Conditionally dispatches to `run_tui()` (line 506) or `run_simple()` (line 125) based on terminal detection
- Implements both evaluation modes with shared evaluation logic

### Core Data Structures

**Input State Machine** (`lib/repl/input.ml` - 177 lines):
```ocaml
type input_action =
  | Noop | Redraw | Submit of string | EOF | Complete
  | HistoryPrev | HistoryNext | HistorySearch

type state = {
  buffer: string;           (* Current line buffer *)
  cursor: int;              (* Byte position in buffer *)
  kill_ring: string list;   (* Clipboard history (max 8) *)
  history_pos: int;         (* -1 = at bottom, >=0 = navigating *)
  multiline_buf: string list;  (* Previous continuation lines *)
}
```

**Completion State** (in `repl.ml:24`):
```ocaml
type comp_state = CompOff | CompOn of { items: string list; sel: int }
```

**Debug Hooks** (`lib/repl/repl.mli:2-31`):
Injected when REPL is launched at a breakpoint. Provides navigation, frame inspection, environment diffing, trace search, and actor inspection.

## Input Handling & Editing

### Readline-style Input (`lib/repl/input.ml`)

The input module provides a pure, immutable state machine for terminal input. All key handling is stateless and produces an action signal.

**Key Bindings** (lines 85-177):

| Key | Action |
|-----|--------|
| `Ctrl+A` | Move to line start |
| `Ctrl+E` | Move to line end |
| `Ctrl+B` / Left Arrow | Move back one char; with Alt: jump to word start |
| `Ctrl+F` / Right Arrow | Move forward one char; with Alt: jump to word end |
| `Ctrl+W` | Kill word backward → kill ring |
| `Ctrl+K` | Kill to end of line → kill ring |
| `Ctrl+U` | Kill entire line → kill ring |
| `Ctrl+Y` | Yank (paste) from kill ring |
| `Ctrl+D` | EOF if empty; else delete forward |
| `Ctrl+L` | Redraw screen |
| `Ctrl+R` | Reverse history search (initiates search mode) |
| Tab | Trigger tab completion |
| Enter | Submit if complete, else add newline and prompt continuation |
| Backspace / Delete | Delete back/forward |
| Home / End | Move to line boundaries |

**Multiline Input** (lines 118-124):
```ocaml
match handle_key with
| `Enter ->
    if Multiline.is_complete full_buffer then
      submit_and_reset()
    else
      continue_prompt_on_newline()
```

The input state maintains a `multiline_buf` stack of previous continuation lines that are rendered above the current input line.

### Multiline Completion Heuristics (`lib/repl/multiline.ml` - 50 lines)

Determines when accumulated input is syntactically complete and safe to evaluate:

```ocaml
let is_complete buf =
  do_end_depth buf <= 0
  && not (ends_with_with buf)
  && not (starts_with_pipe buf)
```

**do_end_depth** (line 22): Counts open/close block pairs
- Increments on: `do`, `match ... with` clauses
- Decrements on: `end`
- Known limitation: Tokens inside string literals are miscounted

**ends_with_with** (line 33): Detects incomplete match expressions
- Match expressions require at least one clause after `with`

**starts_with_pipe** (line 41): Detects incomplete match arms
- Allows continuation of pattern-matching clauses starting with `|`

## Tab Completion

### Completion Engine (`lib/repl/complete.ml` - 32 lines)

```ocaml
let complete prefix scope =
  if String.length prefix > 0 && prefix.[0] = ':' then
    List.filter (starts_with prefix) repl_commands
  else
    scope_matches @ keyword_matches
```

**Context-aware matching**:
1. **REPL commands** (if prefix starts with `:`):
   - `:quit`, `:q`, `:env`, `:help`, `:type`, `:clear`, `:reset`, `:load`, `:save`
2. **Keywords**: `fn`, `do`, `end`, `let`, `match`, `if`, `actor`, `spawn`, etc.
3. **Environment bindings**: User-defined values from current scope (filtered to show only user code)

**Word Boundary Logic** (`Input.complete_replace`, lines 68-77):
- Scans left from cursor to nearest space (word start)
- Scans right from cursor to nearest space (word end)
- Replaces entire word with completion
- Updates cursor to end of replacement

### TUI Completion Dropdown (in `repl.ml:102-128`)

- Shows up to 8 items in a viewport
- Selection wraps with Up/Down arrows
- Selected item highlighted with `▶` prefix and blue background
- Displays overflow count if more items exist
- Dismissed when Tab is pressed again or selection is accepted

## Syntax Highlighting

### Lexer-based Tokenization (`lib/repl/highlight.ml` - 85 lines)

Provides real-time syntax highlighting in TUI mode. Uses the March lexer to tokenize input and colorize based on token type.

**Token → Attribute Mapping** (lines 11-27):

| Token Type | Color | Style |
|------------|-------|-------|
| Keywords (FN, LET, DO, etc.) | Magenta | Bold |
| Numbers (INT, FLOAT) | Yellow | - |
| Strings (STRING, INTERP_*) | Green | - |
| Atoms | Blue | - |
| Type names (UPPER_IDENT) | Cyan | - |
| Operators (+, -, *, /, ==, &&, etc.) | Bold | - |
| Default (whitespace, parens) | Default | - |

**Rendering Strategy** (lines 44-85):
1. Tokenizes input string from left to right
2. Emits each token with appropriate color attribute
3. Composes token images horizontally
4. Gracefully handles lexer errors (renders remainder in default color)
5. Handles newlines by composing images vertically

**Best-effort**: On lex error, tokenization stops and remainder is rendered in default color.

## Command History

### History Ring Buffer (`lib/repl/history.ml` - 94 lines)

Provides persistent command history with navigation and file persistence.

**Data Structure** (lines 3-12):
```ocaml
type t = {
  mutable entries  : string array;   (* Ring buffer *)
  max_size         : int;            (* Circular capacity *)
  mutable count    : int;            (* Actual entries *)
  mutable write_at : int;            (* Next write position *)
  mutable nav_pos  : int;            (* -1 = at bottom, >=0 = navigating *)
}
```

**Operations**:

| Function | Purpose |
|----------|---------|
| `create ~max_size` | Initialize with capacity (default: 1000 entries) |
| `add h entry` | Add entry (ignores blanks and duplicate of most recent) |
| `prev h` | Navigate up (older); returns None if at oldest |
| `next h` | Navigate down (newer); returns None if at bottom |
| `reset_pos h` | Reset to bottom (call after submit) |
| `save h path` | Persist to file (NUL-separated) |
| `load h path` | Restore from file; silently ignores missing files |

**Ring Buffer Logic**:
- Circular array with `write_at` pointer advancing
- Old entries overwrite when capacity exceeded
- Navigation indices are adjusted by `((write_at - 1 - n) + max_size * 2) % max_size`

**Environment Variables**:
- `MARCH_HISTORY_FILE`: Path to history file (default: `~/.march_history`)
- `MARCH_HISTORY_SIZE`: Max history entries (default: 1000)

### History File Format

NUL-byte (`\x00`) separated entries, oldest first. Allows multi-line entries to be preserved exactly.

## Result Variables

### Magic Result History (`lib/repl/result_vars.ml` - 52 lines)

Automatically stores the result of each expression evaluation, accessible as:
- `v`: Most recent result (displayed in green in scope panel)
- `v(1)`, `v(2)`, etc.: Historical results (accessible in code)

**Implementation** (lines 7-51):
```ocaml
type entry = {
  val_str  : string;
  type_str : string;
  eval_val : March_eval.Eval.value;
}

type t = {
  mutable entries : entry array;    (* Ring, max 100 entries *)
  mutable size    : int;
  mutable head    : int;            (* Index of most recent *)
}
```

**Operations**:
- `create()`: Initialize empty history
- `push h value type_str`: Record new result (converts value to string)
- `get h n`: Retrieve entry at index n (0=most recent); returns None if out of bounds
- `length h`: Total recorded entries

**Ring Buffer**: Holds up to 100 entries with index 0 always pointing to most recent.

## Terminal UI (TUI) Rendering

### Two-Pane Layout (`lib/repl/tui.ml` - 164 lines)

Renders a split-screen interface using the [notty](https://github.com/dbuenzli/notty) terminal library:

```
┌─────────────────────────────────┬─────────┐
│         LEFT PANE               │  RIGHT  │
│  (Input + Transcript)           │  PANE   │
│  (Continuation lines)           │(Scope)  │
│  (Completion dropdown)          │         │
├─────────────────────────────────┼─────────┤
│ Status Bar (50/1000 chars, scrolled, etc)  │
└─────────────────────────────────┴─────────┘
```

**Dimensions**:
- Right pane width: 1/3 of terminal
- Left pane: remaining 2/3 minus 1-char separator
- Status bar: 1 row

**Right Pane Content** (lines 55-96):
1. Header: "Variables in Scope"
2. Most recent result `v` (green, if available)
3. User-defined bindings: `name : type = value`
4. Actor list (if any live actors)
   - Alive actors: ● (orange circle) with pid, name, state
   - Dead actors: ✕ (grey X) with pid, name, "(dead)"

**Left Pane Content** (lines 99-144):
1. Syntax-highlighted input line with prompt
2. History of transcript lines (accumulated stdout + errors)
3. Continuation lines (previous incomplete input lines)
4. Tab completion dropdown (if active)
   - Selection highlighted with ▶ prefix and blue background
   - Shows up to 8 items; overflow count if more

**Scrolling** (lines 132-140):
- Scroll offset tracks lines scrolled back from bottom
- Status bar shows `[↑5 scrolled ...]` indicator
- PgUp/PgDn or wheel scroll adjusts offset
- Auto-pins to bottom when new input arrives

**Event Loop** (`next_event`, lines 156-164):
- Blocks on `Notty_unix.Term.event`
- Returns `Key`, `Resize`, `Scroll`, or `End` (EOF/signal)
- Ignores mouse moves and paste events

### TUI Types (`lib/repl/tui.mli`):

```ocaml
type scope_entry = {
  name     : string;      (* Variable name *)
  type_str : string;      (* Inferred type *)
  val_str  : string;      (* String representation of value *)
}

type pane_content = {
  history        : Notty.I.t list;   (* Transcript images *)
  input_line     : Notty.I.t;        (* Highlighted input *)
  prompt         : string;           (* e.g. "march(5)> " *)
  scope          : scope_entry list; (* User bindings *)
  result_latest  : (string * string) option;  (* (type, value) *)
  status         : string;           (* Status bar text *)
  completions    : string list;      (* Dropdown items *)
  completion_sel : int;              (* Selected item index *)
  actors         : March_eval.Eval.actor_info list;
  scroll_offset  : int;              (* Lines scrolled back *)
}
```

## Debug Mode Features

### Debug REPL Hooks (`lib/repl/repl.mli:2-31`)

When a breakpoint (`dbg()`) is hit, the REPL is launched with injected `debug_hooks` providing trace navigation, frame inspection, and actor debugging:

```ocaml
type debug_hooks = {
  dh_back      : int -> int;          (* Step back n frames *)
  dh_forward   : int -> int;          (* Step forward n frames *)
  dh_goto      : int -> int;          (* Jump to absolute frame *)
  dh_where     : unit -> string list; (* Current position + source *)
  dh_stack     : unit -> string list; (* Call stack *)
  dh_trace     : int -> string list;  (* Last n frames *)
  dh_diff      : int -> string list -> string list;  (* Env diff *)
  dh_find      : (env -> bool) -> int option;  (* Search frames *)
  dh_replay    : env -> value option; (* Re-eval with modified env *)
  dh_frame_env : unit -> env option;  (* Current frame's env *)
  dh_actors    : unit -> string list; (* Actor summaries *)
  dh_actor     : int -> int option -> string list;  (* Actor history *)
  dh_save_trace: string -> result;    (* Persist trace *)
  dh_load_trace: string -> result;    (* Load trace *)
}
```

### Debug Commands

**Navigation**:
```
:continue :c         — Resume execution
:back [n]            — Step back n frames (default 1)
:forward [n]         — Step forward n frames (default 1)
:step :s             — Step forward 1 frame
:goto N              — Jump to absolute frame N
```

**Inspection**:
```
:where :w            — Show current position with source context
:stack :sk           — Show call stack
:trace [n] :t [n]    — Show last n trace frames (default 10)
:diff [n]            — Env diff vs n frames back (default 1)
```

**Search & Replay**:
```
:find <expr>         — Find frame where expr evaluates to true
:replay :r           — Re-evaluate from current frame with current env
```

**Actors**:
```
:actors              — List actors with message counts
:actor <pid> [n]     — Show actor message history (optionally jump to msg n)
```

**Trace Persistence**:
```
:tsave <path>        — Save trace to file
:tload <path>        — Load trace from file
```

### Debug Session Entry (`lib/debug/debug_repl.ml`)

**Function**: `run_session(ctx: debug_ctx) -> unit` (lines 32-47)

1. Locates breakpoint by reading `current_frame` from trace
2. Prints "[debug] Breakpoint hit at file:line:col"
3. Builds `debug_hooks` record wiring trace/replay functions
4. Calls `Repl.run()` with hooks and initial breakpoint environment
5. Shows `:where` output immediately upon entry

### Trace Management (`lib/debug/trace.ml` - 245 lines)

Provides frame navigation, formatting, and environment diffing:

**Key Functions**:
- `back(ctx, n)`: Move cursor back n frames (toward older); clamps at oldest
- `forward(ctx, n)`: Move cursor forward n frames (toward recent); clamps at 0
- `goto(ctx, n)`: Jump to absolute frame index
- `current_frame(ctx)`: Get frame at current cursor position
- `show_trace(ctx, n)`: Format and return last n frames
- `show_where(ctx)`: Show current position with 2-line source context
- `diff_frames(ctx, n, baseline_names)`: Show env changes from n frames back
- `find_frame(ctx, pred)`: Search backward for first frame matching predicate
- `source_context(file, line, n)`: Read n lines of context around line from file

**Frame Format**: `Frame i | file:line:col | depth d | result: ...`

## Evaluation & Binding Management

### Expression Evaluation (in `repl.ml:371-497`)

**Simple Mode** (lines 371-497):
1. Parse input as `ReplExpr` or `ReplDecl`
2. Desugar to core AST
3. Type-check and display inferred type
4. Evaluate with JIT (if available) or interpreter
5. Store result with `Result_vars.push` (non-JIT only)
6. Update `v` in environment

**TUI Mode** (lines 636-760):
- Same logic plus:
- Redirect stdout to capture evaluation output
- Display captured output in transcript
- Update watches (if any) after successful eval
- Render updated scope panel

### Declaration Evaluation (DLet, DFn, DActor)

**Functions** (lines 397-406 in simple mode):
- JIT-compile if available (faster startup)
- Else: interpret with `eval_decl`
- Display: `val name = <fn>`

**Actors** (line 423):
- Spawn actor with `eval_decl`
- Display: `val name = <actor>`

**Let Bindings** (lines 414-422):
- Evaluate and extract bound name
- Display: `val name = <value>` or `val _ = ...` for pattern-matched bindings

### Scope Filtering (in `repl.ml:51-82`)

User scope in TUI right pane is filtered to hide:
1. Stdlib bindings (names in `baseline_env`)
2. Underscore-prefixed names
3. Recursive closure markers (`<rec:...>`)
4. Built-in functions (except constructors)
5. Duplicates

## JIT Compilation

### REPL JIT Integration

**Context Creation** (`bin/main.ml:328`):
```ocaml
let jit_ctx = March_jit.Repl_jit.create ~runtime_so () in
```

**Function Declaration** (in `repl.ml:397-406`):
- Detects `DFn` declarations
- Calls `March_jit.Repl_jit.run_decl()` with desugared module
- Binds function name to compiled code
- Much faster than interpretation for repeated calls

**Expression Evaluation** (in `repl.ml:470-474`):
- Wraps expression in synthetic `main()` function
- JIT-compiles and executes
- Returns type and result string

**Environment Variable**:
- `MARCH_REPL_INTERP=1`: Force interpreter mode (disable JIT)

## Source Files & Line References

### Core REPL Module
- **lib/repl/repl.ml** (1217 lines)
  - `run_simple()`: 125-503 (plain text REPL)
  - `run_tui()`: 506-900+ (TUI main loop)
  - `run()`: Dispatcher (end of file)
- **lib/repl/repl.mli** (38 lines)
  - Entry point signatures

### Input Handling
- **lib/repl/input.ml** (177 lines)
  - `handle_key()`: 85-177 (key dispatch)
  - `complete_replace()`: 68-77 (word completion)
  - Kill ring operations: 79-83
- **lib/repl/input.mli** (26 lines)

### Multiline Logic
- **lib/repl/multiline.ml** (50 lines)
  - `is_complete()`: 46-49 (main entry)
  - `do_end_depth()`: 22-23 (block counting)
  - `ends_with_with()`: 33-38
  - `starts_with_pipe()`: 41-43
- **lib/repl/multiline.mli** (4 lines)

### Tab Completion
- **lib/repl/complete.ml** (32 lines)
  - `complete()`: 19-31 (context-aware matching)
  - Repl commands list: 4
  - Keywords list: 6-11
- **lib/repl/complete.mli** (5 lines)

### Syntax Highlighting
- **lib/repl/highlight.ml** (85 lines)
  - `highlight()`: 44-85 (tokenize and colorize)
  - `attr_of_token()`: 11-27 (token → color mapping)
- **lib/repl/highlight.mli** (3 lines)

### History Management
- **lib/repl/history.ml** (94 lines)
  - Ring buffer ops: 11-31
  - Navigation: 34-57
  - Persistence: 63-94
- **lib/repl/history.mli** (22 lines)

### Result Variables
- **lib/repl/result_vars.ml** (52 lines)
  - Ring buffer implementation: 7-51
- **lib/repl/result_vars.mli** (21 lines)

### TUI Rendering
- **lib/repl/tui.ml** (164 lines)
  - `render()`: 47-154 (layout & composition)
  - Right pane: 55-96 (scope & actors)
  - Left pane: 99-144 (input & transcript)
  - `next_event()`: 156-164 (event loop)
  - `create()`: 29-34 (notty initialization)
- **lib/repl/tui.mli** (47 lines)

### Debug Integration
- **lib/debug/debug_repl.ml** (~48 lines)
  - `run_session()`: 32-47 (debug REPL entry)
  - `make_hooks()`: 10-29 (wire hooks to trace/replay)
- **lib/debug/debug.ml** (~38 lines)
  - `make_debug_ctx()`: 15-21 (create trace buffer)
  - `get_frame()`: 32-33 (fetch from ring)
- **lib/debug/trace.ml** (245 lines)
  - `back()`, `forward()`, `goto()`: 9-21
  - `show_where()`: 67-80
  - `show_trace()`: 41-46
  - `diff_frames()`: 92-117
  - `find_frame()`: ~120s
  - Actor history: ~150s

### Main Entry
- **bin/main.ml** (350+ lines)
  - REPL invocation: 326-332
  - Stdlib loading: 65-93
  - Runtime compilation: 98-141

## Test Coverage

### REPL Tests (`test/test_march.ml:1700-1800+`)

**Multiline Completion**:
- `test_do_end_depth()`: do/end nesting
- `test_ends_with_with()`: match expression detection
- `test_starts_with_pipe()`: match arm continuation
- `test_is_complete()`: full completeness check

**Tab Completion**:
- `test_complete_command()`: REPL command filtering
- `test_complete_keywords()`: Keyword suggestions
- `test_complete_scope()`: Environment variable matching

**Input State Machine**:
- `test_complete_replace_prefix()`: Prefix completion
- `test_complete_replace_midword()`: In-word replacement
- `test_complete_replace_with_suffix()`: Word replacement with suffix preservation

**Coverage**: Core multiline logic, completion matching, input manipulation. Full TUI interaction (key dispatch, rendering, event handling) is tested manually.

## Known Limitations

1. **UTF-8 Cursor Display**: Cursor may display garbled glyphs over multi-byte UTF-8 characters in plain text mode (cursor is always byte-accurate; display issue only)

2. **Multiline Token Misparsing**: Multiline completion heuristics count tokens naively and can be fooled by:
   - Tokens inside string literals (`"do something end"` counts as 1 do/1 end)
   - Nested string interpolation

3. **Watch Expressions (Debug)**: Implemented in TUI only; simple mode shows placeholder message

4. **Actor Display Limits**: Right pane shows all live actors but may overflow on narrow terminals

5. **Trace Buffer Capacity**: Default 100,000 frames; overflow discards oldest frames (FIFO)
   - Configurable via `MARCH_DEBUG_TRACE_SIZE` environment variable

6. **History File**: Each history entry stored once; circular buffer fills and overwrites on reload

7. **No Undo/Redo**: History navigation provides replay but no edit-history undo

8. **Limited Scope Filtering**: Hides stdlib but may show implementation details if user redefines stdlib names

## Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `MARCH_HISTORY_FILE` | Path to persistent history | `~/.march_history` |
| `MARCH_HISTORY_SIZE` | Max history entries | 1000 |
| `MARCH_REPL_INTERP` | Force interpreter (disable JIT) | (unset) |
| `MARCH_DEBUG_TRACE_SIZE` | Trace buffer capacity (debug mode) | 100,000 |

## Prompt Format

- **Normal Mode**: `march(N)> ` (where N is prompt counter)
- **Debug Mode**: `dbg(N)> ` (while at breakpoint)
- **Continuation**: Same length as prompt, padded with spaces

## Performance Characteristics

- **Input Rendering**: O(1) per keystroke (single line buffer)
- **Tab Completion**: O(n) where n = scope size + keywords (linear scan)
- **History Navigation**: O(1) ring buffer modulo arithmetic
- **TUI Rendering**: O(h) where h = visible transcript lines (recompose all lines)
- **Syntax Highlighting**: O(m) where m = input length (single-pass tokenization)

## Integration with Other Modules

- **March_eval**: Expression/declaration evaluation, builtin functions, value stringification
- **March_typecheck**: Type inference, scheme instantiation
- **March_parser**: Expression/declaration parsing
- **March_lexer**: Tokenization for syntax highlighting
- **March_desugar**: AST desugaring before evaluation
- **March_jit**: JIT-compile function declarations and expressions
- **March_debug**: Debug context, trace recording, breakpoint handling
- **Notty**: Terminal rendering, event loop, mouse/resize handling
- **Notty_unix**: Raw mode terminal I/O

## Future Enhancement Opportunities

1. **Async REPL**: Non-blocking evaluation with cancellation
2. **Multiple Output Panels**: Show types alongside results
3. **Extended Watch Expressions**: Evaluate and plot numeric series over time
4. **Replay Timeline**: Visual timeline scrubbing of trace frames
5. **IDE Integration**: LSP server for remote REPL access
6. **Macro System**: Define custom REPL commands with argument parsing
7. **Persistent Bindings**: Save/load defined functions across sessions
8. **Profiling Integration**: Track eval time per expression
