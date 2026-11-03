# Browser REPL: separate "clear" from "reset" (2026-10-14)

The in-browser REPL had one way to clear: reset (button / `:reset`), which also forgot
every definition, and only on the playground and landing page. The cookbook sidebar
had no clear or reset at all, only "close".

`docs/assets/march-repl.js` (shared by all three) now has:
- `clear()`, `:clear` and Ctrl+L: wipe the transcript; definitions and up/down input
  history stay. Nothing is evaluated, so it works before the interpreter loads and never
  triggers its download.
- `reset()` / `:reset`: unchanged in behaviour (clear the screen and forget every
  definition).
- `_wipe()`, shared by both, keeps the transcript entry holding the loading-status line.
  On the landing page and the cookbook sidebar that line lives inside the transcript,
  so `:reset` used to detach it and later "Loading interpreter…" updates went nowhere.

Each REPL header now has clear and reset buttons:
- playground: "clear" added beside "reset", plus a `:clear` example chip;
- landing page: "clear" added beside "reset";
- cookbook sidebar: "clear" and "reset" added beside "close".

Each header title is now kept to one line, truncating with an ellipsis, so a third
button cannot wrap it.

Checked in a browser on all three pages:
- clear (button, Ctrl+L, `:clear`) keeps a definition usable and keeps up-arrow recall;
- reset makes the definition unbound;
- the loading line survives both;
- no console errors.
