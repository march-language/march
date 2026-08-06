# Js.* namespace for the three JS-only stdlib modules; retire the Perihelion/dom/canvas demo apps

Filed and resolved 2026-08-05, decided in conversation while discussing whether
`dom.march`/`canvas.march`/`audio.march` should be namespaced together.

## What changed

`mod Audio`, `mod Canvas`, `mod Dom` are now `mod Js.Audio`, `mod Js.Canvas`,
`mod Js.Dom`. Filenames (`stdlib/{audio,canvas,dom}.march`) and the
`js_only_stdlib_file_list` entries in `lib/modules/stdlib_manifest.ml` are
unchanged — only the module names moved, matching the existing
`Perihelion.Core`-style dotted-mod convention already used by app code (see
`specs/lang/modules.md`), which stdlib itself had never used before this.

**Why:** these three are the only stdlib modules that panic at runtime if
called from a native (`--target js`-less) build, and nothing in the old flat
names (`Audio`, `Canvas`, `Dom`) signalled that at the call site — the
`--target js`-only requirement lived in a doc comment a caller had to already
know to look for. A shared `Js.` prefix puts that constraint in every call
site instead. It also matches precedent: even the most closely related
existing stdlib family (`Http`/`HttpClient`/`HttpServer`/`HttpTransport`)
stays flat, so this was deliberately *not* generalized to a broader
stdlib-naming policy — it's specific to the JS-only-and-panics-on-native
property these three share.

**Breaking.** No module-level alias/back-compat mechanism exists in March
(only caller-side `alias`), so every caller had to update in the same change.

## What was renamed (in-repo)

- `stdlib/audio.march`, `stdlib/canvas.march`, `stdlib/dom.march` — mod decl +
  all self-referencing doc-comment examples.
- `demo_app/tetris/lib/tetris.march`, `demo_app/tetris_logic/lib/tetris_logic.march`
  — call sites updated, apps kept (not part of the removal below).
- `test/native/js_dom_available.march`, `js_canvas_available.march`,
  `js_dom_timeout_callback.march`.
- `docs/stdlib.md`, `docs/tooling.md`, `docs/cookbook/dom.md` — section
  headers, prose, and code examples.

## Demo apps removed in the same change

`demo_app/perihelion`, `demo_app/dom_demo`, and `demo_app/canvas_demo` are
gone (user call — these three were the highest-call-site-count consumers of
the renamed modules, and there was no reason to migrate throwaway demo code
instead of deleting it).

`demo_app/perihelion` was not just example code: `docs/perihelion.html` served
it live, backed by checked-in compiled assets at `docs/assets/perihelion/`
that `.github/workflows/gen-perihelion-assets.yml` regenerated and
auto-committed on every push touching `demo_app/perihelion/lib/**`. Confirmed
with the user before deleting: the live page comes down too, not frozen in
place, since freezing it would leave a page that silently drifts from
current March forever with no way to regenerate it. Removed alongside the
demo: `docs/perihelion.html`, `docs/assets/perihelion/`,
`.github/workflows/gen-perihelion-assets.yml`, `scripts/gen-perihelion-assets.sh`.

`.claude/commands/build-dom-demo.md` (a slash command whose only job was
building `demo_app/dom_demo`) was removed as dead weight in the same change.

## External consumer

`/Users/80197052/code/perihelion` — a separate, standalone repo (own git
remote `git@github.com:Ch4s3/perihelion.git`), **not** the same code as the
now-deleted `demo_app/perihelion`. It depends on march as an external forge
project and had 277 occurrences of the old bare names. Updated separately;
see that repo's own history for the migration commit. This is the one
real-world case found of an external project depending on these module
names — worth remembering if another JS-only stdlib module ever needs the
same treatment: there is no registry of who depends on march's stdlib, so
"grep every known local checkout" is the only check available.
