# `--cap-sandbox`/`--cap-strict` cannot see capabilities recorded for non-`DFn` names

**Filed:** 2026-08-06, while closing the `record_fn_caps` coverage gap
(`specs/progress/2026-08-06-record-fn-caps-misses-dlet-and-methods.md`).

## The gap

`own_caps_of_this_module` (`bin/main.ml`) filters
`fn_own_capability_closures` with a `belongs` predicate whose `user_fn_names`
set is built by a walk that collects **`DFn` names only**:

- a dotless key (the entry module is unwrapped on the `--compile` path, so its
  own top-level names are bare) `belongs` only if it is a known `DFn` name — so
  a module-level `let`'s entry is dropped;
- a dotted key `belongs` only if its prefix equals the entry module's name — so
  a nested module's key, and an entry-module `impl` method key
  (`Iface$Ty.method`, whose first dot-prefix is `Iface$Ty`), are both dropped.

Measured: a module whose only IO is `let touched = file_write(...)` compiles
with `--cap-sandbox` to a profile with **no** file-write allowance, identical to
a pure program's, on both sides of the gap-closure change.

## Why it matters

The sandbox profile is a security surface. Under-reporting there produces a
profile that is *tighter* than the program needs, so the failure mode is a
runtime denial rather than an escape — but it also means the profile and
`march caps` can disagree, which `own_caps_of_this_module`'s own docstring says
must not happen ("Shared by `march caps` and --cap-sandbox so the reported set
and the embedded sandbox profile cannot disagree"). That claim is currently
false: `march caps` does **not** call `own_caps_of_this_module`; it uses a
separate `belongs` inside `run_check_cmd` keyed on the module names the listed
files declare, and that one *does* see the new entries.

## Shape of the fix

Either point both surfaces at one predicate, or extend the walk in
`own_caps_of_this_module` to collect `DLet`-bound names and `DImpl`
`Iface$Ty.method` keys as well as `DFn` names. Whichever is chosen, correct the
docstring's sharing claim, and re-measure `--cap-sandbox` profiles across the
corpus: widening the profile is the direction that grants more, so it needs its
own sweep rather than being folded into an unrelated change.
