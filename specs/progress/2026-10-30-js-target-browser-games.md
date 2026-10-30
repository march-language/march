# JS target: enough to run a Herald game in the browser

Landed 2026-10-30 on `claude/js-browser-target`, driven by compiling Eclipse
(a Herald game) with `--target js`
(eclipse `docs/superpowers/specs/2026-10-29-eclipse-browser-build-design.md`).

- **Tail calls** (`js_emit.ml`): self tail calls become `__tco: for (;;)` over
  `$tco_aN` slots, each iteration binding fresh consts (closures keep their own
  values). Tail-call SCCs from `Llvm_tco.tarjan_sccs` become one `$mutco_*`
  dispatcher on `$tco_tag` plus a wrapper per member. IIFEs suspend the loop
  target. Tests: `js_tail_loop`, `js_mutual_tail`.
- **Native arrays** (`march_runtime.mjs`): Int32Array / Uint8Array /
  Float64Array; `set` mutates in place (no COW: RC is erased). Test:
  `js_native_arrays`.
- **Byte strings**: canonical form (ASCII, decoded valid UTF-8, other bytes as
  U+F780+(b-0x80)); byte ops use a cached per-string byte view.
  `march_bytes_to_string` is the constructor for externs. Test:
  `js_binary_string`.
- **`--js-int-check`**: `march_ck_int` / `march_ck_lit`; location is the
  enclosing function (TIR has no expression spans). forge passes it via
  `MARCH_JS_INT_CHECK`. Tests: `js_int_check`, `js_int_check_c`,
  `js_int_check_lit`.
- **Bundling** (`bin/main.ml` `bundle_js_modules`), **`process_argv`** on Node,
  **forge `js_entrypoint`** (`Project.entry ~js`). Tests: `js_bundle`,
  `js_argv`, `js_unreached_c_extern`, forge `js_entrypoint picks the
  --target js entry`.
- **Native symbols for JS-module externs** (`lower_decls.ml`): sanitized to C
  identifiers. Test: `native_js_module_extern_native`.
