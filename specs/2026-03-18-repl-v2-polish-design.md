# REPL v2 Polish — Design Spec

## Goal

Add four UX improvements to the March TUI REPL: a block cursor, a navigable tab-completion dropdown below the prompt, and an actors panel in the right pane.

## Architecture

All changes flow through the existing three-layer stack:

- **`lib/eval/eval.ml`** — adds `ai_name` to `actor_inst`; exposes `list_actors` query function
- **`lib/repl/tui.ml` / `tui.mli`** — extended `pane_content` record; new rendering for dropdown and actor section
- **`lib/repl/repl.ml`** — builds cursor-inclusive input image; manages completion state machine; queries actor registry each frame

No new files are needed.

## Feature Designs

### 1. Block Cursor

The cursor is applied in **`repl.ml`** when building the `input_line` image, before passing it to `pane_content`. `tui.ml` does not need to know about the cursor.

`repl.ml` builds `input_line` as follows:
1. Take the syntax-highlighted image from `Highlight.highlight buf_str`
2. Overlay the cursor: render the character at `cur` (the existing `int` cursor position in `repl.ml`) with `A.(bg white ++ fg black)` (inverted — the iex style)
3. If `cur` is at end-of-line, append a space rendered with `A.(bg white)` so the cursor is always visible

Implementation note: since `Highlight.highlight` returns an `I.t`, the cursor overlay must be built by splitting the raw string at `cur`, rendering each segment with appropriate attributes, and `I.hcat`-ing them. Concretely:

```ocaml
let make_input_img buf cur =
  let s = Buffer.contents buf in
  let n = String.length s in
  let left  = String.sub s 0 cur in
  let cur_c = if cur < n then String.make 1 s.[cur] else " " in
  let right = if cur < n then String.sub s (cur+1) (n - cur - 1) else "" in
  (* Render each segment as plain text (no syntax highlight) so the cursor
     character is always correct. Splitting a highlighted I.t post-hoc is
     not possible, and calling Highlight.highlight on sub-strings loses token
     context at boundaries. Plain rendering is visually acceptable here. *)
  let left_img  = I.string A.empty left in
  let cur_img   = I.string A.(bg white ++ fg black) cur_c in
  let right_img = I.string A.empty right in
  I.(left_img <|> cur_img <|> right_img)
```

`pane_content` gains **no new fields** for the cursor — it is baked into `input_line`.

### 2. Tab Completion Dropdown

**Completion state in `repl.ml`:**

```ocaml
type comp_state = CompOff | CompOn of { items: string list; sel: int }
```

**Key interception:** `CompOn` is checked **before** `Input.handle_key` in the event loop. The raw `Notty.Unescape.key` is matched first:

```
while CompOn:
  Tab / (`Arrow `Down)  → sel := (sel + 1) mod List.length items
  `Arrow `Up            → sel := (sel - 1 + n) mod n
  `Enter / `Return      → confirm: replace word around cursor, set CompOff
  `Escape               → CompOff (no insert); consumed, NOT passed to Input.handle_key
  any other key         → CompOff, then fall through to Input.handle_key normally
```

**Triggering:** `Tab` while `CompOff` extracts the word around the cursor (scan left for non-space prefix start, scan right for non-space suffix end), calls `Complete.complete prefix scope_pairs`, then:
- 0 results → no-op
- 1 result → insert immediately (replace word in buf), stay `CompOff`
- 2+ results → set `CompOn { items; sel=0 }`

**Word replacement on confirm:** To replace the current word when confirming a completion (mid-word case `fo|bar`):
1. `word_start` = scan left from `cur` to first space (or 0)
2. `word_end` = scan right from `cur` to first space (or end of buffer)
3. Replace `buf[word_start..word_end)` with the selected completion string
4. Set `cur = word_start + String.length completion`

**Rendering fields added to `pane_content`:**

```ocaml
completions    : string list;   (* empty = CompOff, hidden *)
completion_sel : int;
```

**`tui.ml` renders the dropdown** immediately below the input row when `completions` is non-empty:
- Bordered box, left-aligned with the start of the typed text (after prompt)
- Max 8 entries shown; if more, last visible line is `I.string A.empty "  ↓ N more"` where N = remaining count
- Selected entry: `A.(bg (rgb_888 0 80 160) ++ fg white)` with `▶ ` prefix
- Other entries: `A.empty` with `  ` prefix
- The dropdown occupies rows in the history area (does not push the input line down — it overlaps if needed); `tui.ml` inserts it as additional rows just after the input row in `all_rows`

### 3. Actors Panel in Right Pane

**`eval.ml` changes:**

Add `ai_name : string` to `actor_inst` (populated from the actor name at `ESpawn` time):

```ocaml
type actor_inst = {
  ai_name    : string;           (* NEW: actor type name, e.g. "Counter" *)
  ai_def     : actor_def;
  ai_env_ref : env ref;
  mutable ai_state : value;
  mutable ai_alive : bool;
}
```

In the `ESpawn` handler (around line 475), set `ai_name = actor_name` when constructing the `actor_inst`.

Expose a query function:

```ocaml
type actor_info = {
  ai_pid       : int;
  ai_name      : string;
  ai_alive     : bool;
  ai_state_str : string;   (* value_to_string of current state; distinct from actor_inst.ai_state : value *)
}

val list_actors : unit -> actor_info list
(* Returns Hashtbl.fold over actor_registry, sorted by pid ascending *)
```

**`pane_content` gains:**

```ocaml
actors : March_eval.Eval.actor_info list;
```

`tui.mli` does **not** re-export `actor_info` — call sites use the full path `March_eval.Eval.actor_info`.

**`tui.ml` renders** an "Actors" section in the right pane below the scope list, but **only when `actors` is non-empty**:

```
Actors
────────────────────
● pid:1  Counter  {count=0}    ← A.(fg (rgb_888 255 152 0))   (orange; use ai_state_str for state)
● pid:2  Counter  {count=5}    ← A.(fg (rgb_888 255 152 0))
✕ pid:3  Counter  (dead)       ← A.(fg (rgb_888 100 100 100))  (dark grey; show "(dead)", ignore ai_state_str)
```

**`repl.ml`** calls `March_eval.Eval.list_actors ()` when building `pane_content` each frame.

## Files Changed

| File | Change |
|------|--------|
| `lib/eval/eval.ml` | Add `ai_name` to `actor_inst`; add `actor_info` type + `list_actors` function |
| `lib/repl/tui.mli` | Extend `pane_content` with `completions`, `completion_sel`, `actors` |
| `lib/repl/tui.ml` | Dropdown rendering below input row; actors section in right pane |
| `lib/repl/repl.ml` | Cursor-inclusive `input_line` via `make_input_img`; completion state machine; populate `actors`/`completions`/`completion_sel` each frame |

## Testing

- Unit tests for `list_actors` (empty registry, one alive, one dead, mixed)
- Unit tests for completion word-replacement logic (prefix-only, suffix-only, mid-word)
- Cursor and dropdown are TUI-only; test interactively with `dune exec march`
