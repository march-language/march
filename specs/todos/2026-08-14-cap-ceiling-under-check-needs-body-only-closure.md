# Running the capability ceiling under `march --check` needs a body-only closure table

Filed while working Task 7 of `specs/2026-08-13-capability-ux-plan.md` (Steps
3-4 landed — see `specs/progress/2026-08-13-capability-ceiling-second-class-and-compile-only.md`
for the full writeup; this file is the forward-looking half of that report).

**The gap**: `march --check` does not lower to TIR, so the `--compile`-only
`Cap_ceiling.check` (which runs over `Cap_attrib`'s TIR attribution) cannot
run there. A module whose `needs` manifest is falsified only by a
stdlib-mediated call (`File.read(p)` rather than `file_read(p)` — the
idiomatic way to do IO, not an edge case) is caught by `--compile` and
missed by `--check` entirely. Verified live:

```march
mod CeilApp do
  needs IO.Console
  needs IO.FileRead
  mod Dep do
    needs IO.Console
    fn slurp(p : String) : String do
      match File.read(p) do
        Ok(s) -> s
        Err(_) -> ""
      end
    end
  end
  fn main(cap_console : Cap(IO.Console), cap_fileread : Cap(IO.FileRead)) : () do
    println(Dep.slurp("/etc/passwd"))
  end
end
```

`--check` exits 0 on this file today (`Dep` under-declares — only
`IO.Console` — while the entry module's own broader grant satisfies
`check_main_grant`'s whole-program view, so nothing at typecheck time
currently checks `Dep`'s manifest against `Dep`'s own use). `--compile`
correctly rejects it: `` module `Dep` uses `IO.FileRead` but does not
declare `needs IO.FileRead` ``.

**Why the obvious fix (reuse `Typecheck.own_cap_closures`) is unsound**:
`own_cap_closures` is fed both a function's body-scanned capabilities AND
its SIGNATURE capabilities (`record_fn_caps qname sig_caps`, typecheck.ml
~line 9223) — correct for its existing consumer (Check 2, "declared `needs`
but unused" — a `Cap(X)` parameter legitimately counts as use), wrong for a
ceiling check, which needs to know what code actually DOES. This is the
exact bug class `specs/progress/2026-08-08-ceiling-signature-only-fixed.md`
closed on the `--compile` side (false positive on the documented
`fn main(cap : Cap(IO))` entry-point shape) — reusing `own_cap_closures`
as-is for a `--check`-side ceiling reintroduces it. Confirmed by prototype:
this exact false positive reproduced on the brief's own worked example.

**What a real fix needs**: a SECOND closure table, seeded from body/extern-
scanned capabilities only (not signatures), walking the same `env.fn_refs`
edges to the same fixpoint `fn_transitive_capability_closures_tbl` already
computes — kept separate from `own_cap_closures` because `record_fn_caps`
currently merges both into one entry and Check 2 depends on that merge.
Needs its own record-time call sites (wherever `record_fn_caps` is called
today) and its own regression coverage before it can be trusted to run
under `--check` by default, given the documented history of this exact
capability-table-drift failure mode (five prior source-level decl-walks,
each independently buggy; two prior signature-vs-body confusions in this
same subsystem).

**Also note**: `env.fn_refs` is deliberately over-inclusive by design one
layer below this (a function referenced as a value, not just called, must
still count — see the "cardinal sin" comment on `record_fn_refs`,
typecheck.ml ~line 9007, guarding against the OPPOSITE false-negative bug).
Whatever seeds a body-only table still walks that same over-inclusive edge
set, so a module that merely holds a reference to (without ever calling) a
`Cap(X)`-parameterized helper elsewhere could still inherit `X` falsely.
Worth an explicit test case before this ships, not just the `main`-shape
regression test the 2026-08-08 fix already has.

Not urgent — under-reporting (this gap) is the tolerable failure mode per
the capability-UX plan's own priorities; `--compile` still catches the real
case before it reaches a binary. Priority is "close before `--check` is
advertised as a complete substitute for `--compile`'s capability guarantees
anywhere in the docs."
