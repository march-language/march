`[P2]` Native REPL (`march repl`) bugs found by the doc-example checks (2026-10-14)

Converting stdlib examples into checked `march>` transcripts
(scripts/check-stdlib-doctests.py feeds them to `march repl`) found native-REPL-only
bugs. The same code is correct interpreted (`march file.march`) and compiled, and in
the browser REPL unless noted. Each was worked around in the docs; none is fixed here.

1. **Vault values decay after `==`.** In one session, `Vault.get(c, "h") == Some(1)` is
   `true` once, then `false`; a later `let x = Vault.get(c, "h")` shows `None`, while
   `Vault.get_or` still returns the value. `Vault.ns_get` too. Workaround in
   stdlib/vault.march: read with `get_or` / `has` / `Option.unwrap_or`.
2. **A binding named `v` is clobbered by the last result.** After `let v = 5`, entering
   `100` then `v` gives 100. Workaround: examples avoid `v`.
3. **Non-ASCII strings print as escaped bytes** (`"caf\195\169"` for "café").
   Workaround: `... == "café"` → `true`.
4. **Unit prints as `1`** (e.g. a `Vault.set` result); the browser prints `()`.
5. **A panic ends the session** (later inputs get no value). The doctest checker does
   not feed `** panic` examples for this reason.

Filed separately: `Err(:atom)` as a bare result segfaults the REPL (session task
"Fix native REPL segfault on Err(:atom) value"); NativeArray i32 values print as
9223372036854775807 (branch fix/repl-i32-native-array-sign).

Reproduce any of them with `printf '...\n' | ./_build/default/bin/main.exe repl`.
