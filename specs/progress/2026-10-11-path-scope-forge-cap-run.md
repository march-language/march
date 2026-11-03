# `forge cap run` enforces declared path scopes (embedded manifest)

**Filed under:** `specs/todos/2026-08-04-path-scope-followups.md`, item
"Wire scopes into `forge cap run`". Design: `specs/2026-08-04-path-scoped-capabilities-design.md` §6.

## Owner decision (2026-10-11)

Use the embedded-manifest route, not scoped markers. For enforcement a
declared scope is enough. The sandbox blocks everything outside it, so the
claim does not have to be proved from emitted code. Scoped markers with
`DYNAMIC` (design §7) stay open for a sound AUDIT later.

## What changed

- **Writer.** `Cap_scope.manifest_json` (`lib/caps/cap_scope.ml`) serializes
  the program's declared `needs` that relate to a filesystem class, scoped and
  unscoped, as `{"v":1,"scopes":[{"cap":..,"scope":..|null}]}`. It returns
  `None` when nothing is scoped. `bin/main.ml` computes it from
  `Typecheck.declared_cap_scopes` (the same source `--cap-sandbox` uses) and
  passes it to `emit_module ?cap_manifest`. `lib/tir/llvm_toplevel.ml` emits
  it as `@__march_capscope_manifest`, a `MARCHCAP\x01 <u32 le len> <json>`
  blob pinned through `@llvm.used`. That is the blob format `Cap_binary`
  already scanned for (forge audit design §6), which no compiler had emitted
  until now. The prefix `__march_capscope_` differs from the flat-marker
  prefix `__march_cap_` at the 12th character, so the marker reader cannot
  decode it as a capability.
- **Unscoped programs are unchanged.** No manifest is emitted, so their IR
  and their CAS key are byte-for-byte what they were.
- **CAS key.** The post-TIR cache key is built from TIR impl hashes, and the
  manifest is not in the TIR. Two programs with identical code and different
  scopes therefore shared one cached binary; the end-to-end test caught a
  scoped binary's manifest coming back on an unscoped build. The manifest
  JSON is now folded into `mod_hash` when present. The same gap affects the
  `__march_capfrom_`/`__march_capdecl_` owner markers (a cache hit across
  two differently named modules keeps the first one's owners); that was
  filed separately and is not fixed here.
- **Reader.** `Cap_binary.scope_decls` parses the `scopes` array. A missing
  manifest or a missing key is `Ok []`, so old binaries keep their behaviour.
  A malformed array is an `Error`, and `forge cap run` refuses to run, rather
  than widening a broken claim to "any path".
- **Enforcement.** `Cap_sandbox` (`profile_for`, `bwrap_args` and `run` take
  `?scopes`). `Cap_scope.effective_scopes` decides each OS class: a related
  unscoped declaration (including `IO.FileSystem` or `IO`) means it is not
  narrowed. Scopes are resolved on the running machine through
  `resolve_scope`, which takes the realpath of the longest existing prefix
  (the same rule as the runtime's `march_scope_resolve`).
  - macOS SBPL: a held `IO.FileWrite` becomes one
    `(allow file-write* (subpath ..))` per scope. Read scopes are not applied,
    because `file-read*` is baseline, and they are reported as advisory.
  - Linux bwrap: a scoped read uses the allow-list namespace plus
    `--ro-bind-try` of each scope. A scoped write uses `--bind-try` of each
    scope, over `--ro-bind / /` when reads are unscoped. The binds come after
    the `/tmp` tmpfs, read-only binds first, so a nested writable scope wins.
    A read scope next to an UNSCOPED write grant cannot be enforced
    (`--dev-bind / /`), and `scope_notes` says so.
  - Scopes only narrow a class the policy already grants, so `forge cap run`
    applies them under `--allow-only` as well.

## Tests

- `test/test_cap_scope.ml`: `effective scopes per OS class`,
  `scope manifest json`.
- `forge/test/test_cap_binary.ml`: manifest round trip (the compiler's own
  writer read back by forge's reader), no manifest means no scopes, malformed
  scopes are an error.
- `forge/test/test_cap_sandbox.ml`: bwrap write scope, bwrap read scope,
  scopes never widen (a withheld class, an unscoped grant alongside a scope,
  and no scopes all give the old flags or profile), SBPL write scope,
  `resolve_scope` following symlinks. End to end, `forge cap run` enforces a
  declared scope: real compiled binaries are run through `forge cap run`, and
  the checks are on host-side effects. With a scoped grant, the in-scope
  write lands and the out-of-scope write does not. With an unscoped grant,
  there is no manifest and both writes land (asserted on macOS).

**Exercised:** macOS (sandbox-exec) end to end. **Not run:** the Linux bwrap
path. Its arguments are unit-tested and the end-to-end test runs there when
bwrap is usable, but it was not run on Linux when this landed. That is
recorded as an open item in the todo.
