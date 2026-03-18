# REPL v2 Polish — Design Spec

## Goal

Add four UX improvements to the March TUI REPL: a block cursor, a navigable tab-completion dropdown below the prompt, and an actors panel in the right pane.

## Architecture

All changes flow through the existing three-layer stack:

- **`lib/eval/eval.ml`** — exposes a new `list_actors` query function
- **`lib/repl/tui.ml` / `tui.mli`** — extended `pane_content` record; new rendering for cursor, dropdown, actor section
- **`lib/repl/repl.ml`** — tracks cursor position; manages completion state machine; queries actor registry each frame

No new files are needed.

## Feature Designs

### 1. Block Cursor

`pane_content` gains `cursor_col : int` (column offset into the raw input string, 0-based).

In `tui.ml`, the input image is built by splitting the displayed input at `cursor_col`:
- chars before cursor: normal style
- char at cursor: `A.(bg white ++ fg black)` (inverted — the iex style)
- chars after cursor: normal style

If cursor is at end-of-line, render a space with inverted background so the cursor is always visible.

`repl.ml` already tracks `buf` and `cur` (`Buffer.t` + int position). `cur` maps directly to `cursor_col`.

### 2. Tab Completion Dropdown

**State:** `repl.ml` adds a local `completion_state` variant:
```ocaml
type comp_state = CompOff | CompOn of { items: string list; sel: int }
```

**Key bindings (while `CompOn`):**
- `Tab` / `↓` — move selection down (wraps)
- `↑` — move selection up (wraps)
- `Enter` — replace the current partial word in `buf` with `items.(sel)`, close dropdown
- `Esc` — close dropdown without inserting
- Any other printable key — close dropdown, process key normally

**Triggering:** `Tab` while `CompOff` calls `Complete.complete prefix scope_pairs` where `prefix` is the word to the left of the cursor. If one result → insert immediately (no menu). If multiple → show menu with first item selected.

**Rendering:** `pane_content` gains two fields:
```ocaml
completions    : string list;   (* empty = hidden *)
completion_sel : int;
```

`tui.ml` renders a bordered box immediately below the input row when `completions` is non-empty. Max 8 lines shown; selected line is highlighted `A.(bg (rgb_888 0 80 160) ++ fg white)`.

### 3. Actors Panel in Right Pane

**`eval.ml`** exposes:
```ocaml
type actor_info = {
  ai_pid   : int;
  ai_name  : string;
  ai_alive : bool;
  ai_state : string;  (* value_to_string of current state *)
}
val list_actors : unit -> actor_info list
```

**`pane_content`** gains:
```ocaml
actors : actor_info list;
```

**`tui.ml`** renders an "Actors" section below the scope list in the right pane:
- Header `"Actors"` + separator line
- Each alive actor: orange `●  pid:N  TypeName  {state}`
- Each dead actor: dim grey `✕  pid:N  TypeName  (dead)`
- If no actors ever spawned: nothing shown (section is hidden)

**`repl.ml`** populates `actors` each frame by calling `March_eval.Eval.list_actors ()`.

## Files Changed

| File | Change |
|------|--------|
| `lib/eval/eval.ml` | Add `actor_info` type + `list_actors` function |
| `lib/repl/tui.mli` | Add `actor_info` type (re-exported or imported); extend `pane_content` with `cursor_col`, `completions`, `completion_sel`, `actors` |
| `lib/repl/tui.ml` | Cursor rendering in input row; dropdown box below input; actors section in right pane |
| `lib/repl/repl.ml` | Pass `cursor_col`; completion state machine; populate `actors` each frame |

## Testing

- Unit tests for `list_actors` (empty, alive, dead actors)
- Unit tests for tab completion triggering (single-result auto-insert, multi-result menu open)
- The cursor and dropdown are TUI-only; test by running `dune exec march` interactively
