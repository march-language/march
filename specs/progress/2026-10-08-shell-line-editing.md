# Shell: line editing and persistent history

Done 2026-10-08. `march --shell` (and so `forge shell`) read the prompt with
`In_channel.input_line` in the terminal's cooked mode, so arrow keys showed
up as `^[[A` inside the input and there was no history.

## Did the local REPL have editing to reuse?

Partly, and not usably. `march repl` is a full-screen notty TUI
(`lib/repl/tui.ml`) with its own key machine (`lib/repl/input.ml`) and
history (`lib/repl/history.ml`). Those work on notty key events, move the
cursor by BYTE (a multibyte char takes several steps), are multi-line and
draw the whole screen. The shell needs one inline line, so this adds a
separate small editor rather than bending those.

## What changed

- `lib/repl/shell_line.ml`: a pure editor. Bytes in, state out: buffer,
  byte-offset cursor on a UTF-8 boundary, history position, the line being
  typed (restored by Down), and a pending-sequence buffer, so an escape
  sequence or a multibyte char may arrive split across reads. Also the
  display slice (`view`, horizontal scroll for lines wider than the
  terminal) and the history functions (`record`, `load`, `append`).
- `bin/shell_tty.ml`: the terminal side. Raw mode (ICANON, ECHO, ISIG, IXON,
  ICRNL off) only while a line is read; Ctrl-C is byte 3, handled as "discard
  the line", so no signal. A bare ESC is told from `ESC [ A` by a 50 ms wait.
  Width comes from `stty size`, re-read after SIGWINCH.
- `bin/shell_cmd.ml`: uses it only when `inputs = None` and stdin AND stdout
  are ttys and termios works. Every other path is the old code, unchanged.
- History: `~/.march/shell_history` (dir 0700, file 0600, re-narrowed on
  load), appended per accepted line, skipping blank, `:quit`/`:q` and a line
  equal to the previous one, capped at 1000 (the file is trimmed at load).
  It can contain sensitive inputs; documented in `docs/observe.md`.

## Terminal restoration

Raw mode lasts only for one read, wrapped in `Fun.protect`, so the terminal
is cooked while an input runs. On top of that: an `at_exit` hook (also run on
an uncaught exception) and SIGINT/SIGTERM/SIGHUP handlers, installed for the
read, that restore and exit (130/143/129). SIGKILL cannot be handled.

## Tests

- `test/test_shell_line.ml` (suite `shell_line` in `run_compiler`): arrows at
  every position, history navigation and draft restoration, UTF-8 (incl.
  split reads and broken chars), kill commands, ESC split across reads and
  bare ESC, unknown sequences leaking nothing, the view, record
  dedup/skip/cap, history file load/append/cap/modes.
  RED check: with `Down` no longer restoring the draft and the UTF-8
  boundary step broken, 2 of 11 cases fail (history, UTF-8); restored, green.
- `test/shell/pty_drive.py`: drives the real `march --shell` under a pty
  against a node (up/down, editing keys, Ctrl-C, UTF-8, resize, long line,
  bare ESC, F5, Ctrl-D, `:quit`, SIGTERM mid-edit, termios restored,
  history file mode and contents, history surviving a restart). Not in
  `dune runtest` (needs a live node). Recipe: build the node as in
  `test/dune`'s `native_shell_session` rule, start it with
  `MARCH_HOT_RELOAD_SOCKET=/tmp/x.sock MARCH_SHELL_POLICY=<policy>`, then
  `pty_drive.py <march> /tmp/x.sock test/native/shell_node.march <throwaway HOME>`.
  Prints `ALL PASS`; 5 consecutive passes after making it wait for prompts
  rather than sleep.
- The four `native_shell_*` goldens are byte-identical.

## Not done

- Double-width characters count as one column.
- Edits to a recalled history entry are lost when moving to another entry.
- No Tab completion, reverse search (Ctrl-R), or multi-line input.
