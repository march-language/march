`[P4]` Spike: render `forge top` / `forge diagnose` / `forge status` with samoht's `console` library (inline live rows that stay in scrollback) (2026-11-16)

**What.** `console` (opam `console`, v0.9.0, github.com/samoht/ocaml-console;
write-up at gazagnaire.org/blog/2026-11-02-console.html) is an OCaml
terminal-output library. Tables, trees, panels and progress bars share one view
type. Each widget is a pure function of (width, height, time), and the caller
supplies the clock and terminal size. Live rows redraw *inline* at the bottom of
the terminal instead of taking over the whole screen, so earlier output stays in
the scrollback. When stdout is not a TTY it prints each line once, with no
redraw. Its only driver today is `console-eio`.

**Where it fits in the recon tier.**

- `forge top`: today it clears the screen and redraws every refresh
  (`forge/lib/cmd_observe.ml`, the `"\027[H\027[2J" ^ frame` loop in the TOP
  runner) and has a separate `--once` path. An inline live table would keep the
  final frame in the scrollback, and piped/CI output would degrade on its own,
  which may make `--once` a plain consequence of not having a TTY.
- `forge diagnose` / `forge status`: static tables, plus the supervision tree as
  a tree widget. Output goes through `Fmt`, so `--json` and `Fmt_tty` colour
  handling are unaffected.

**Out of scope.**

- `forge observe` (`forge/lib/observe_tui.ml`, `observe_tui_live.ml`): a
  full-screen, key-driven, multi-panel Notty app. That is the problem `console`
  says it does not address, so it stays on Notty.
- March-side `Recon.print_top` / `Recon.format_top` (`stdlib/recon.march`) and
  the remote shell's `:top`: these are March code, so an OCaml library can't
  reach them. A March stdlib table/tree module built on the same ideas (pure
  width/time widgets, injected clock) would be its own todo.

**Spike plan.**

1. Depend on the pure `console` package only, not `console-eio`. Forge's observe
   loop is single-threaded `Unix.select`, and Eio shouldn't come in for this.
   Write a small Unix driver: clock from `Unix.gettimeofday`, size from
   `TIOCGWINSZ` and `SIGWINCH`, a formatter on stdout.
2. Port `render_top` and the `diagnose`/`status` printers. Keep the existing
   text tests (`forge/test/test_observe_client.ml`, the fake-node fixtures)
   green, or regenerate them on purpose and review the diff.
3. Decide: keep it (and add it to the opam/dune-project deps, CI images, and a
   CHANGELOG `### Changed` bullet), or drop it and record why here.

**Risks / reasons to wait.** It's pre-1.0 with a single author; 1.0 is planned
once the author has moved their own tools over. It needs OCaml >= 5.4 (we build
on 5.5.1, but `dune-project` still declares `>= 5.3.0`). We'd have two terminal
stacks: Notty for `observe`, `console` for line-mode output.

**Related, outside recon.** The task model (`Task.run` / `Task.log` /
`Task.fail`: a per-task log window that folds on success and stays open on
failure) may fit `forge build` / `forge test` / `forge deps` progress output
even better. If the spike lands, file that as a follow-up.
