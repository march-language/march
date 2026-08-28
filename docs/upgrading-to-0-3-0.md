---
layout: docs
title: Upgrading to 0.3.0
nav_order: 2.5
permalink: /docs/upgrading-to-0-3-0/
---

# Upgrading from 0.2.x to 0.3.0

0.3.0 ships several breaking changes. This guide walks through each one: the
symptom you'll see, and the concrete fix. It was written by migrating eight
real downstream packages against `main` ahead of the release: every fix
below is a real fix that landed in a real package, not a guess.

If you hit something not covered here, check `CHANGELOG.md`'s `[Unreleased]`
section for the full list of changes, and consider filing an issue.

---

## 1. The capability limit is on by default

This is the change you will hit first, and the one that touches the most
code. Every program's `main` must now declare exactly which IO capabilities
it needs, and every module that calls a capability-gated builtin (directly,
or by importing another module that does) must declare a matching `needs`.

### Symptom

```
-- ERROR -------------------------------

`main` performs IO but declares no grant. The program reaches `IO.Console`,
`IO.FileRead`; a `main` with no capability parameter is granted nothing.
help: declare the grant `main` actually needs —
        fn main(_cap_console : Cap(IO.Console), _cap_fileread : Cap(IO.FileRead)) : ()
or grant everything with `fn main(cap : Cap(IO))`.
`forge fix` can apply this.
```

or, for a non-`main` module:

```
-- ERROR -------------------------------

module `Forge.Migrate` imports `Depot.Migration` which requires `Cap(IO.Mut)`,
but `IO.Mut` is not declared in `needs`.
help: add `needs IO.Mut` to the module body.
```

### Fix

For a plain module, add the missing `needs IO.X` line(s) the diagnostic
names. For `main`, either enumerate the specific capabilities it needs:

```march
fn main(_cap_console : Cap(IO.Console), _cap_fileread : Cap(IO.FileRead)) do
  ...
end
```

or grant everything at once, which is fine for an application entry point
that truly needs broad IO:

```march
fn main(cap : Cap(IO)) do
  ...
end
```

**Run `forge fix` first**: it auto-applies most of these (both the `needs`
lines and, in our testing, `main`'s specific-capability grant list). It
won't touch `test/*.march` files, so expect to add a handful of `needs`
lines to test modules by hand afterward.

**Watch for one subtlety**: if you pick the blanket `fn main(cap : Cap(IO))`
form, the module needs a blanket `needs IO`, not a pile of specific
`needs IO.X` lines. Mixing the two (specific `needs`, blanket `main` grant)
produces a confusing second round of `Cap(IO) used ... but IO is not
declared in needs` errors. Pick one style per module and match it: specific
`needs` lines pair with a specific per-capability `main` param list; a
blanket `needs IO` pairs with `fn main(cap : Cap(IO))`.

### Where this hides: orphan entry modules

`forge check` and `forge build` only typecheck files **reachable from your
package's normal import graph**. If your `forge.toml` has `[archive.task.*]`
entries pointing at modules that are *only* invoked via `forge
yourpkg.task_name` (never `import`ed by anything else), those files are
invisible to `forge check`/`forge build` and can bring capability-limit
violations (or any other error) that a clean `forge check` won't catch.

We hit this concretely: bastion has 19 such task modules under `lib/forge/`,
forgepm has 10. In both cases `forge check` reported success while several
of those modules failed to typecheck standalone. Check explicitly:

```sh
# One-by-one, with a proper MARCH_LIB_PATH (matches what forge itself builds — see forge.lock):
MARCH_LIB_PATH=lib:<dep1>/lib:<dep2>/lib:... march --check lib/forge/some_task.march
```

If your `forge.toml` has `[archive.task.*]` entries, budget time to check
each one this way: a `forge build` that reports zero errors can still be
hiding a broken task module.

---

## 2. Vault table handles are now typed `Vault(v)`

`Vault.new`/`Vault.open` used to return an untyped handle that could hold
any mix of value types under different keys. As of 0.3.0 a table handle is
`Vault(v)`, phantom in the type of the values it stores: the element type is
fixed at the binding, so storing an `Int` under one key and a `String` under
another **in the same table** is now a type error instead of a silent
reinterpretation.

### Symptom

```
error: expected `String` but got `Int`.
```

pointing at a `Vault.set`/`Vault.get` call, often far from where the
table was created: the error surfaces at whichever second, differently-typed
use unifies against the first.

### Fix

**Split the table by element type: one `Vault(v)` per distinct value type.**
This is the same fix pattern across every package that hit it (depot,
conduit, forgepm): if a table held both a `String` "mode" flag and `Int`
counters under different keys, it becomes two tables, e.g.:

```march
-- before: one table, two value types under different keys
Vault.set(rk, "mode", "deterministic_replay")   -- String
Vault.set(rk, "cursor", 0)                       -- Int

-- after: two tables
Vault.set(rk_str, "mode", "deterministic_replay")
Vault.set(rk_int, "cursor", 0)
```

Give each table a distinct underlying name too (`Vault.new`/`whereis` mint a
handle from a name string, so reusing the same name for two different
element types will hand back whichever table was created first, silently
wrong):

```march
pfn replay_str_key(id) do
  match Vault.whereis("wf_replay_str_" ++ id) do
    Some(tbl) -> tbl
    None      -> Vault.new("wf_replay_str_" ++ id)
  end
end

pfn replay_int_key(id) do
  match Vault.whereis("wf_replay_int_" ++ id) do
    Some(tbl) -> tbl
    None      -> Vault.new("wf_replay_int_" ++ id)
  end
end
```

Any function/record field that stores a `Vault(v)` handle needs its type
annotation updated too, e.g. a record field previously typed as `String`
(because it held an opaque table-key string) may need to become
`Vault(String)` if it actually held the table handle itself.

Test-suite fakes/mocks that model storage with a Vault often hit this
hardest, since a hand-rolled fake tends to reuse one table for everything the
real backend would track separately (jobs, events, dead letters, ...);
budget time to split those too.

### Known compiler issue: non-`String` keys

Vault documents that keys can be `Int`, `String`, `Bool`, `Atom`, `Tuple`, or
`Ctor`, "stringified on the way in." That is true under the interpreter, but
as of this writing a **non-`String` key crashes when compiled natively**
(SIGSEGV/SIGBUS). If your compiled program crashes inside `vault_key_cstr`
with no assertion output, this is almost certainly why: use a `String` key
(e.g. `int_to_string(id)`) as a workaround until this is fixed. See the
upstream compiler repo's `specs/todos/` for the logged report.

---

## 3. Parser combinator module renamed `Parse` → `Parser`

### Symptom

```
error: Unknown module `Parse`.
```

### Fix

Rename every `Parse.foo(...)` call site to `Parser.foo(...)`. A project-wide
find/replace on `Parse\.` → `Parser.` (careful of the word boundary: don't
touch unrelated identifiers containing "Parse") handles this in one pass for
most codebases.

---

## 4. JS-only stdlib modules are now namespaced under `Js.`

### Symptom

Unknown-module errors for whichever JS-only module your code referenced
directly (compiling for the `js` target, or code behind a JS-only `extern`
block).

### Fix

Qualify the import with the `Js.` prefix, e.g. `Fetch.get(...)` becomes
`Js.Fetch.get(...)`. Check `CHANGELOG.md`'s `[Unreleased]` entry for the
exact list of the three modules affected.

---

## 5. `~H` bare-JS-expression holes render as inert string literals

This changed **the same day** this guide was written (PR #311), so it's
worth calling out even though none of the eight packages surveyed for this
guide hit it directly.

### What changed

A `~H` template hole in *bare-JS-expression position* (inside a
`<script>` block, not inside an HTML attribute or text node) used to
interpolate its value directly into the generated JavaScript:

```march
~H"<script>var n = ${count}</script>"
```

previously emitted `var n = 42` (executable). It now emits `var n = '42'`: a
JS **string literal**, not the raw value. If your generated page's inline
script expected a number (or any non-string value) at that hole, it will now
receive a quoted string instead.

Separately, interpolating into `srcdoc` or `srcset` attributes inside a `~H`
template is now a **compile error** rather than silently accepted: those
two attributes have escaping rules `~H` can't yet apply correctly, so the
compiler will not guess.

### Fix

- For bare-JS holes that need the raw value (not a JS string), pass the
  value through explicitly rather than relying on the hole's old behavior:
  e.g. build the script text yourself and mark it as raw/trusted where your
  templating layer supports that, rather than interpolating directly into a
  `<script>` block.
- For `srcdoc`/`srcset`, restructure to avoid `~H` interpolation into those
  specific attributes (e.g. build the attribute value as a plain string
  first, or use a `<script src="...">`/separate resource instead of an
  inline `srcdoc` payload).
- **If you have a server-rendered-HTML app, grep your templates for
  `<script` combined with `~H` interpolation and for any `srcdoc`/`srcset`
  usage before upgrading**: this is exactly the shape of bug that a
  passing `forge check` won't catch (it's a runtime rendering behavior
  change, not a type error), so a manual sweep is the only way to catch it
  ahead of time.

---

## 6. `List.nth` now includes a bounds contract

### Symptom

Not an error by default: you'll see an advisory `HINT` in `forge
check`/`build`/`test` output:

```
-- HINT --

precondition `_ >= 0 && _ < len(xs)` on `List.nth` was NOT verified here.
reason: solver-undecided — the solver proved neither the predicate nor its negation
note: March reports only definite failures, so a contract it cannot decide
is accepted in silence. Add `cap verified` to this module to make every
unverifiable obligation an error instead; `--refine-report` lists them all.
```

### Fix

No action is required: this is silent-by-default and every package surveyed
for this guide built clean with these hints present. If you want the
compiler to hold you to a stricter standard (turn "can't prove this is safe"
into a hard error), add `cap verified` to the module and either restructure
the call so the bound is provable, or use a checked alternative (`List.get`
returning `Option`, or an explicit length guard before the call).

---

## 7. Removed: the `link` builtin, `march_response_send_plaintext`

If you called either of these directly, you'll get an unknown-builtin/unknown-
function error at the call site. Neither had a direct downstream user among
the eight packages surveyed for this guide; check the commit that removed
each (`git log --oneline -- runtime/ lib/tir/`) for the recommended
replacement if you relied on one.

---

## Toolchain traps that look like compiler bugs but aren't

Two environment issues produced confusing, compiler-bug-shaped symptoms
during this migration. If something looks impossible (a type that should
obviously resolve doesn't, or errors don't match what you just fixed),
check these before assuming a compiler regression:

- **A stray `.march-version` pin file** in a project directory silently
  locks `forge` to whatever toolchain that pin names, even a build from
  weeks earlier; `forge --version`/`march --version` inside that directory
  will report a stale version, and features from newer releases (like typed
  `Vault(v)`) will fail to resolve with confusing "cannot find" errors that
  look like a name-resolution bug. If forge's behavior doesn't match the
  toolchain version you expect, `cat .march-version` (if present) before
  digging further.
- **Path-overridden git dependencies** (`{ path = "../foo" }` in place of a
  `{ git = ... }`/registry entry, for testing a local fix before it's
  published) need `forge deps` re-run after the `forge.toml` edit; and even
  then, a previously-resolved copy under `~/.march/cas/deps/<name>` can
  linger and shadow the local path in some invocations. If a fix you just
  made to a dependency doesn't seem to be picked up, clear
  `~/.march/cas/deps/<name>` and re-run `forge deps`.

---

- **An entry file with a name that does not match the package name.** `forge` derives
  the entry module as `lib/<package name>.march`, so a package named
  `march-doc` needs `lib/march-doc.march`, not `lib/march_doc.march`. This rule
  predates 0.3.0 (it has been in `forge` since March), but at least one package
  contained a latent mismatch that only surfaced while upgrading, and the failure
  reads as a missing module rather than a naming problem. If a module you can
  see on disk is reported as absent, check the spelling against
  `forge.toml`'s `name` first.

## Quick checklist

1. Run `forge check` (or `forge build`) and work through the
   capability-limit errors; run `forge fix` first, it handles most of the
   `needs`/`main`-grant mechanical fixes.
2. Manually add `needs` grants to `test/*.march` files; `forge fix` doesn't
   touch them.
3. If your `forge.toml` has `[archive.task.*]` entries, typecheck each task
   module directly (see §1); `forge check`/`build` won't catch problems in
   task modules that aren't otherwise imported.
4. Grep for `Vault.new`/`Vault.set`/`Vault.get` and check whether any single
   table mixes value types across different keys; split by type if so (§2).
   Use `String` keys only until the non-`String`-key crash is fixed.
5. Grep for `Parse.` and `~H` + `<script>`/`srcdoc`/`srcset` (§3, §5).
6. `forge test`: full green is the real bar; `forge check`/`build` passing
   is necessary but not sufficient (they don't compile+run your test suite).
