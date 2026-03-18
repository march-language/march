# REPL v2 Polish Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a block cursor, navigable tab-completion dropdown, and actors panel to the March TUI REPL.

**Architecture:** Changes flow through three layers — `eval.ml` exposes actor data, `tui.ml` renders the new UI regions, and `repl.ml` drives the completion state machine and cursor image. One helper (`complete_replace`) is added to `input.ml` so it can be unit-tested independently.

**Tech Stack:** OCaml 5.3.0, dune, notty 0.2.3, alcotest. Build: `/Users/80197052/.opam/march/bin/dune build`. Test: `/Users/80197052/.opam/march/bin/dune runtest`. **Never use `eval $(opam env ...)`.**

**Spec:** `docs/superpowers/specs/2026-03-18-repl-v2-polish-design.md`

---

## File Map

| File | What changes |
|------|-------------|
| `lib/eval/eval.ml` | Add `ai_name` to `actor_inst`; add `actor_info` type + `list_actors` |
| `lib/repl/input.ml` | Add `complete_replace` |
| `lib/repl/input.mli` | Export `complete_replace` |
| `lib/repl/tui.mli` | Extend `pane_content` with `completions`, `completion_sel`, `actors` |
| `lib/repl/tui.ml` | Render completion dropdown + actors panel |
| `lib/repl/repl.ml` | `make_input_img`, `comp_state` machine, wire up new pane_content fields |
| `test/test_march.ml` | Tests for `list_actors` and `complete_replace` |

---

## Task 1: Actor name + list_actors in eval.ml

**Files:**
- Modify: `lib/eval/eval.ml:42-47` (actor_inst), `lib/eval/eval.ml:475-476` (ESpawn), add after line ~55
- Test: `test/test_march.ml`

### Step 1: Write failing tests

Add to `test/test_march.ml` before the `let () =` at the end:

```ocaml
(* ------------------------------------------------------------------ *)
(* list_actors tests                                                   *)
(* ------------------------------------------------------------------ *)

let dummy_actor_def = March_ast.Ast.{
  actor_state    = [];
  actor_init     = ELit (LitInt 0, dummy_span);
  actor_handlers = [];
}

let mk_actor_inst name alive st = March_eval.Eval.{
  ai_name    = name;
  ai_def     = dummy_actor_def;
  ai_env_ref = ref [];
  ai_state   = st;
  ai_alive   = alive;
}

let test_list_actors_empty () =
  Hashtbl.clear March_eval.Eval.actor_registry;
  Alcotest.(check int) "empty registry" 0
    (List.length (March_eval.Eval.list_actors ()))

let test_list_actors_alive () =
  Hashtbl.clear March_eval.Eval.actor_registry;
  Hashtbl.add March_eval.Eval.actor_registry 0
    (mk_actor_inst "Counter" true (March_eval.Eval.VInt 5));
  let actors = March_eval.Eval.list_actors () in
  Alcotest.(check int) "one actor" 1 (List.length actors);
  let a = List.hd actors in
  Alcotest.(check int)    "pid"   0     a.March_eval.Eval.ai_pid;
  Alcotest.(check string) "name"  "Counter" a.March_eval.Eval.ai_name;
  Alcotest.(check bool)   "alive" true  a.March_eval.Eval.ai_alive;
  Alcotest.(check string) "state" "5"   a.March_eval.Eval.ai_state_str

let test_list_actors_sorted () =
  Hashtbl.clear March_eval.Eval.actor_registry;
  Hashtbl.add March_eval.Eval.actor_registry 2
    (mk_actor_inst "A" true (March_eval.Eval.VInt 0));
  Hashtbl.add March_eval.Eval.actor_registry 0
    (mk_actor_inst "B" false (March_eval.Eval.VUnit));
  let actors = March_eval.Eval.list_actors () in
  Alcotest.(check int) "two actors" 2 (List.length actors);
  Alcotest.(check int) "sorted first pid" 0
    (List.nth actors 0).March_eval.Eval.ai_pid;
  Alcotest.(check int) "sorted second pid" 2
    (List.nth actors 1).March_eval.Eval.ai_pid
```

Also register these in the `Alcotest.run` suite. Find the `"complete"` suite near the end of `test/test_march.ml` and add a new `"actors"` suite entry:

```ocaml
      "actors", [
        Alcotest.test_case "empty"  `Quick test_list_actors_empty;
        Alcotest.test_case "alive"  `Quick test_list_actors_alive;
        Alcotest.test_case "sorted" `Quick test_list_actors_sorted;
      ];
```

- [x] **Step 2: Run tests to verify they fail**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep -A3 "actors"
```

Expected: compile error or test failure (functions not yet defined).

- [x] **Step 3: Add `ai_name` to `actor_inst` in eval.ml**

Find `type actor_inst` (line 42) and change it from:

```ocaml
type actor_inst = {
  ai_def     : actor_def;
  ai_env_ref : env ref;         (** Module environment at spawn time *)
  mutable ai_state : value;
  mutable ai_alive : bool;
}
```

to:

```ocaml
type actor_inst = {
  ai_name    : string;           (** Actor type name, e.g. "Counter" *)
  ai_def     : actor_def;
  ai_env_ref : env ref;         (** Module environment at spawn time *)
  mutable ai_state : value;
  mutable ai_alive : bool;
}
```

- [x] **Step 4: Update ESpawn handler to populate ai_name**

Find the `ESpawn` handler (around line 475), change the `actor_inst` construction from:

```ocaml
       let inst = { ai_def = def; ai_env_ref = env_ref;
                    ai_state = init_state; ai_alive = true } in
```

to:

```ocaml
       let inst = { ai_name = actor_name; ai_def = def; ai_env_ref = env_ref;
                    ai_state = init_state; ai_alive = true } in
```

- [x] **Step 5: Add `actor_info` type and `list_actors`**

`value_to_string` is defined around line 270 in `eval.ml` — OCaml requires definitions before their uses. Place both new definitions **immediately after `value_to_string`**:

```ocaml
type actor_info = {
  ai_pid       : int;
  ai_name      : string;
  ai_alive     : bool;
  ai_state_str : string;
  (** Distinct from actor_inst.ai_state which is a [value]. *)
}

let list_actors () =
  Hashtbl.fold (fun pid inst acc ->
    { ai_pid       = pid;
      ai_name      = inst.ai_name;
      ai_alive     = inst.ai_alive;
      ai_state_str = value_to_string inst.ai_state }
    :: acc
  ) actor_registry []
  |> List.sort (fun a b -> compare a.ai_pid b.ai_pid)
```

- [x] **Step 6: Build**

```bash
/Users/80197052/.opam/march/bin/dune build 2>&1
```

Expected: clean build. If there are compile errors about missing `ai_name` fields in pattern matches, find every place that constructs or destructures `actor_inst` (search for `ai_def =` or `ai_alive`) and add `ai_name` as appropriate.

- [x] **Step 7: Run tests**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep -E "actors|FAIL|PASS|Error"
```

Expected: 3 passing actor tests.

- [x] **Step 8: Commit**

```bash
git add lib/eval/eval.ml test/test_march.ml
git commit -m "feat(eval): add ai_name to actor_inst, expose list_actors"
```

---

## Task 2: complete_replace in input.ml

**Files:**
- Modify: `lib/repl/input.ml` (add function after `word_end_right`)
- Modify: `lib/repl/input.mli` (export it)
- Test: `test/test_march.ml`

### Step 1: Write failing tests

Add to `test/test_march.ml` before the `let () =`:

```ocaml
(* ------------------------------------------------------------------ *)
(* complete_replace tests                                              *)
(* ------------------------------------------------------------------ *)

let mk_inp buf cur = { March_repl.Input.empty with
  March_repl.Input.buffer = buf;
  March_repl.Input.cursor = cur }

let test_complete_replace_prefix () =
  (* cursor at end of prefix "fo", no right side → replace "fo" with "foo" *)
  let s = mk_inp "fo" 2 in
  let s' = March_repl.Input.complete_replace s "foo" in
  Alcotest.(check string) "buf" "foo" s'.March_repl.Input.buffer;
  Alcotest.(check int)    "cur" 3     s'.March_repl.Input.cursor

let test_complete_replace_midword () =
  (* cursor mid-word: "fo|bar" → replace whole word "foobar" with "baz" *)
  let s = mk_inp "fobar" 2 in
  let s' = March_repl.Input.complete_replace s "foobar" in
  Alcotest.(check string) "buf" "foobar" s'.March_repl.Input.buffer;
  Alcotest.(check int)    "cur" 6        s'.March_repl.Input.cursor

let test_complete_replace_with_suffix () =
  (* context: "x = fo|bar + 1" → replace word "fobar" with "foobar", keep rest *)
  let s = mk_inp "x = fobar + 1" 7 in
  let s' = March_repl.Input.complete_replace s "foobar" in
  Alcotest.(check string) "buf" "x = foobar + 1" s'.March_repl.Input.buffer;
  Alcotest.(check int)    "cur" 10               s'.March_repl.Input.cursor
```

Register in the test suite — add to `Alcotest.run`:

```ocaml
      "complete_replace", [
        Alcotest.test_case "prefix only"    `Quick test_complete_replace_prefix;
        Alcotest.test_case "mid word"       `Quick test_complete_replace_midword;
        Alcotest.test_case "with suffix"    `Quick test_complete_replace_with_suffix;
      ];
```

- [x] **Step 2: Run tests to confirm they fail**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep -E "complete_replace|Error"
```

- [x] **Step 3: Add `complete_replace` to input.ml**

Add after `word_end_right` (after line 62):

```ocaml
(** Replace the word surrounding the cursor with [completion].
    Word start: scan left from cursor to first space (or buffer start).
    Word end: scan right from cursor to first space (or buffer end).
    No space-skipping — spaces are hard boundaries. *)
let complete_replace s completion =
  let b = s.buffer and c = s.cursor in
  let len = String.length b in
  let ws = ref c in
  while !ws > 0 && b.[!ws - 1] <> ' ' do decr ws done;
  let we = ref c in
  while !we < len && b.[!we] <> ' ' do incr we done;
  let new_buf = String.sub b 0 !ws ^ completion ^ String.sub b !we (len - !we) in
  let new_cur = !ws + String.length completion in
  { s with buffer = new_buf; cursor = new_cur }
```

- [x] **Step 4: Export in input.mli**

Add after `val insert_at`:

```ocaml
val complete_replace : state -> string -> state
(** Replace the word at/around the cursor with [completion].
    Word boundaries are nearest spaces (or buffer start/end). *)
```

- [x] **Step 5: Build and test**

```bash
/Users/80197052/.opam/march/bin/dune build 2>&1 && /Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep -E "complete_replace|FAIL"
```

Expected: 3 passing complete_replace tests.

- [x] **Step 6: Commit**

```bash
git add lib/repl/input.ml lib/repl/input.mli test/test_march.ml
git commit -m "feat(input): add complete_replace for word-boundary completion"
```

---

## Task 3: Extend tui.mli / tui.ml for dropdown + actors

**Files:**
- Modify: `lib/repl/tui.mli` (extend `pane_content`)
- Modify: `lib/repl/tui.ml` (render dropdown and actors panel)
- Modify: `lib/repl/repl.ml` (pass stub values so build passes — real values in Task 4)

No new tests (rendering is TUI-only, verified interactively).

- [x] **Step 1: Extend pane_content in tui.mli**

Find the `pane_content` type in `lib/repl/tui.mli` and add three fields:

```ocaml
type pane_content = {
  history       : Notty.I.t list;
  input_line    : Notty.I.t;
  prompt        : string;
  scope         : scope_entry list;
  result_latest : (string * string) option;
  status        : string;
  completions    : string list;
  (** Tab completion candidates. Empty = no dropdown shown. *)
  completion_sel : int;
  (** Index of the currently highlighted completion. *)
  actors         : March_eval.Eval.actor_info list;
  (** Live actor instances from the evaluator. *)
}
```

- [x] **Step 2: Add dropdown rendering to tui.ml**

In `lib/repl/tui.ml`, find the left-pane construction (around the `input_row`/`all_rows` section) and replace:

```ocaml
  let prompt_img  = I.string (st bold ++ fg blue) content.prompt in
  let input_row   = I.(prompt_img <|> content.input_line) in
  let all_rows    = content.history @ [input_row] in
```

with:

```ocaml
  let prompt_img  = I.string (st bold ++ fg blue) content.prompt in
  let input_row   = I.(prompt_img <|> content.input_line) in
  let dropdown_rows =
    let items = content.completions in
    let n = List.length items in
    if n = 0 then []
    else
      let max_show = 8 in
      (* Viewport: keep selection visible *)
      let win_size  = min n max_show in
      let win_start = max 0 (min content.completion_sel (n - win_size)) in
      let win_end   = win_start + win_size in
      let overflow  = n - win_end in
      let win_items = List.filteri (fun i _ -> i >= win_start && i < win_end) items in
      let rows = List.mapi (fun rel item ->
        let abs_i   = win_start + rel in
        let selected = abs_i = content.completion_sel in
        let prefix  = if selected then "\xe2\x96\xb6 " else "  " in
        (* ▶ in UTF-8 *)
        let attr    = if selected
                      then A.(bg (rgb_888 0 80 160) ++ fg white)
                      else A.empty in
        fit_width left_w (I.string attr (prefix ^ item))
      ) win_items in
      if overflow > 0 then
        rows @ [fit_width left_w (I.string A.empty
          (Printf.sprintf "  \xe2\x86\x93 %d more" overflow))]
        (* ↓ in UTF-8 *)
      else rows
  in
  let all_rows    = content.history @ [input_row] @ dropdown_rows in
```

- [x] **Step 3: Add actors section to tui.ml right pane**

In `lib/repl/tui.ml`, find the right pane construction. After `scope_rows`, before assembling `right_rows`, add:

```ocaml
  let actors_rows =
    if content.actors = [] then []
    else
      let header = fit_width right_w (I.string (st bold) "Actors") in
      let sep    = I.string A.empty (String.make right_w '-') in
      let rows   = List.map (fun (a : March_eval.Eval.actor_info) ->
        let bullet, attr =
          if a.ai_alive
          then ("\xe2\x97\x8f", A.(fg (rgb_888 255 152 0)))
            (* ● orange *)
          else ("\xe2\x9c\x95", A.(fg (rgb_888 100 100 100)))
            (* ✕ dark grey *)
        in
        let body =
          if a.ai_alive
          then Printf.sprintf "%s pid:%d  %s  %s" bullet a.ai_pid a.ai_name a.ai_state_str
          else Printf.sprintf "%s pid:%d  %s  (dead)" bullet a.ai_pid a.ai_name
        in
        fit_width right_w (I.string attr body)
      ) content.actors in
      [header; sep] @ rows
  in
```

Then update the final `right_rows` assembly from:

```ocaml
  let right_rows = [right_header; right_sep] @ v_rows @ scope_rows in
```

to:

```ocaml
  let right_rows = [right_header; right_sep] @ v_rows @ scope_rows @ actors_rows in
```

- [x] **Step 4: Update repl.ml to pass stub values for new pane_content fields**

In `lib/repl/repl.ml`, find the `Tui.render tui Tui.{...}` call inside `render_frame` and add the three new stub fields:

```ocaml
    Tui.render tui Tui.{
      history       = transcript;
      input_line    = input_img;
      prompt;
      scope;
      result_latest;
      status;
      completions    = [];      (* stub — wired in Task 4 *)
      completion_sel = 0;       (* stub *)
      actors         = [];      (* stub — wired in Task 4 *)
    }
```

- [x] **Step 5: Build**

```bash
/Users/80197052/.opam/march/bin/dune build 2>&1
```

Expected: clean build with no errors.

- [x] **Step 6: Run tests**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1
```

Expected: all existing tests still pass (no regressions).

- [x] **Step 7: Commit**

```bash
git add lib/repl/tui.mli lib/repl/tui.ml lib/repl/repl.ml
git commit -m "feat(tui): add completion dropdown and actors panel rendering"
```

---

## Task 4: Wire up cursor, completion state machine, and actor data in repl.ml

**Files:**
- Modify: `lib/repl/repl.ml` (all the active logic)

No new tests (TUI-only; verify interactively).

- [x] **Step 1: Add `comp_state` type and `make_input_img` at the top of repl.ml**

Add after the opening comment (before `history_path`):

```ocaml
open Notty

type comp_state = CompOff | CompOn of { items: string list; sel: int }

(** Build the input line image with a block cursor at position [cur].
    Uses plain text rendering (no syntax highlight) so the cursor character
    is always correct. *)
let make_input_img s cur =
  let n = String.length s in
  let left  = String.sub s 0 cur in
  let cur_c = if cur < n then String.make 1 s.[cur] else " " in
  let right = if cur < n then String.sub s (cur+1) (n - cur - 1) else "" in
  I.(string A.empty left
     <|> string A.(bg white ++ fg black) cur_c
     <|> string A.empty right)
```

- [x] **Step 2: Update render_frame to use make_input_img and real pane_content fields**

Find `render_frame` in `run_tui`. Change:

```ocaml
    let input_img = Highlight.highlight !inp.Input.buffer in
```

to:

```ocaml
    let input_img = make_input_img !inp.Input.buffer !inp.Input.cursor in
```

Replace the stub `completions`, `completion_sel`, `actors` fields:

```ocaml
      completions    = [];
      completion_sel = 0;
      actors         = [];
```

with the real values. First add `let comp = ref CompOff in` with the other `ref` declarations near the top of `run_tui`. Then update:

```ocaml
      let (comp_items, comp_sel) = match !comp with
        | CompOff -> ([], 0)
        | CompOn { items; sel } -> (items, sel)
      in
      let actors = March_eval.Eval.list_actors () in
```

and use them in the render call:

```ocaml
      completions    = comp_items;
      completion_sel = comp_sel;
      actors;
```

- [x] **Step 3: Replace the Input.Complete handler with the new dropdown logic**

Find the existing `| Input.Complete ->` case (around line 433-452) and replace it entirely with:

```ocaml
        | Input.Complete ->
          let b = !inp.Input.buffer and c = !inp.Input.cursor in
          let i = ref c in
          while !i > 0 && b.[!i - 1] <> ' ' do decr i done;
          let prefix = String.sub b !i (c - !i) in
          let scope = List.filter_map (fun (name, _v) ->
            if List.mem_assoc name March_eval.Eval.base_env then None
            else Some (name, "")
          ) !env in
          let items = Complete.complete prefix scope in
          (match items with
          | [] -> ()
          | [single] ->
            inp := Input.complete_replace !inp single;
            render_frame ()
          | multiple ->
            comp := CompOn { items = multiple; sel = 0 };
            render_frame ())
```

- [x] **Step 4: Add CompOn key interception before Input.handle_key**

**Implementation:** Extract the existing action-dispatch block (the `(match action with ...)` content) into a local `dispatch_action` helper defined inside `run_tui`. Then rewrite the `| \`Key key ->` branch to check `!comp` first.

First define `dispatch_action` inside `run_tui` (before the `while !running do` loop), containing all the existing action handlers:

```ocaml
  let dispatch_action action =
    (match action with
     | Input.EOF -> running := false
     | Input.Submit src -> ...  (* all existing Submit logic *)
     | Input.HistoryPrev -> ...
     | Input.HistoryNext -> ...
     | Input.Redraw | Input.Noop -> render_frame ()
     | Input.Complete -> ... (* new dropdown logic from Step 3 *)
     | Input.HistorySearch -> ())
  in
```

Then the event loop becomes:

```ocaml
     | `Key key ->
       (match !comp with
        | CompOn { items; sel } ->
          let n = List.length items in
          (match key with
          | (`Tab, _) | (`Arrow `Down, _) ->
            comp := CompOn { items; sel = (sel + 1) mod n };
            render_frame ()
          | (`Arrow `Up, _) ->
            comp := CompOn { items; sel = (sel - 1 + n) mod n };
            render_frame ()
          | (`Enter, _) ->
            let chosen = List.nth items sel in
            inp := Input.complete_replace !inp chosen;
            comp := CompOff;
            render_frame ()
          | (`Escape, _) ->
            comp := CompOff;
            render_frame ()
          | _ ->
            comp := CompOff;
            let (inp', action) = Input.handle_key !inp key in
            inp := inp';
            dispatch_action action)
        | CompOff ->
          let (inp', action) = Input.handle_key !inp key in
          inp := inp';
          dispatch_action action)
```

Also: when any key other than Tab/arrows is pressed while `CompOff`, `comp` should be reset to `CompOff` on `Submit` to ensure stale state doesn't linger. Add `comp := CompOff;` at the start of the `| Input.Submit src ->` branch in `dispatch_action`.

- [x] **Step 5: Build**

```bash
/Users/80197052/.opam/march/bin/dune build 2>&1
```

Expected: clean build. Common errors to watch for:
- `Unbound value Notty.I.string` → you need `open Notty` or use fully qualified `Notty.I.string`. Since we added `open Notty` at the top, just use `I.string`.
- `comp_state` not recognized → ensure `type comp_state = ...` is at module level (not inside a function).
- `This expression has type ... but an expression of type pane_content was expected` → the `Tui.{...}` record must have all fields.

- [x] **Step 6: Run tests**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1
```

Expected: all tests pass (144+).

- [x] **Step 7: Manual smoke test**

```bash
/Users/80197052/.opam/march/bin/dune exec march
```

Verify:
- Block cursor visible at input position
- Tab opens dropdown below prompt
- Arrow keys navigate selection (highlighted entry moves)
- Enter inserts selected completion
- Escape dismisses dropdown
- After `spawn(Counter)` (if Counter actor is defined), right pane shows actor info

- [x] **Step 8: Commit**

```bash
git add lib/repl/repl.ml
git commit -m "feat(repl): block cursor, navigable completion dropdown, actor panel wired up"
```
