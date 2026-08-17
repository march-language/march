# LANDED 2026-08-17 — capability ceiling now runs under `march --check`

**Status: shipped.** This file was the forward-looking todo; the design it
prescribed is implemented. What landed, and the two places the design was
sharpened during implementation:

- **A typecheck-side ceiling** (`Typecheck.check_stdlib_mediated_ceiling`), gated
  by `Typecheck.cap_strict_ceiling` (the driver sets it on `--check`/`--check-json`,
  respecting `--no-cap-strict`). Seeded from a new body-only capability table
  (`env.body_cap_closures`, recorded at the body-scan sites, never the sig-caps
  site — avoiding the `fn main(cap : Cap(IO))` false positive) and a
  stdlib-membership set (`env.stdlib_fns`, marked span-accurately including
  prelude functions).

- **Design sharpening 1 — it is NOT the full `fn_refs` transitive closure the
  todo suggested.** A full closure over-reports: it would charge a caller for
  capabilities a *user* callee (in another module) reaches, which `--compile`
  attributes to that other module. The correct closure is stdlib-TRANSPARENT —
  roll caps up only through stdlib callees, stopping at user-module boundaries —
  which exactly matches `Cap_attrib`'s roll-up and is a provable subset of the
  `--compile` result. Verified: zero over-reports across all 143 `@types-check`
  accept fixtures; reject witness `reject/t180`.

- **Design sharpening 2 — the fail-closed `Unattributed` arm is deliberately
  NOT reproduced.** It over-reports on closure-heavy code (indirect calls);
  `--compile` remains the complete check for that route. `--check` under-reports
  it, which is the tolerable direction.

- **The FInsert cross-file trap (flagged below) is fixed:** the fix is suppressed
  when the owner module's span is `dummy_span` (a cross-file dependency not in the
  entry file's tree), and indented to the owner's own column otherwise. Also
  delivers the todo's second motivation — the ceiling's fix payload now reaches
  `--check-json`, so `forge fix`/LSP can apply it.

**Known follow-ups (not blocking):** the check runs on the primary
`bin/main.exe --check`/`--check-json` path; the separate `march check`
(`run_check_cmd`) and LSP typecheck entry points do not yet enable
`cap_strict_ceiling`. Cross-file dependency modules under-report (their spans
are not in the entry file's `module_spans`) — sound, but the diagnostic lands
without a fix there.

---

## Original todo (design rationale, retained)

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

**A second, independent reason to land this**: Task 7 Steps 3-4 already gave
each `Undeclared` violation a real span and a machine-applicable `FInsert`
fix (see `specs/progress/2026-08-13-capability-ceiling-second-class-and-compile-only.md`).
That payload is unconsumed today — `forge fix`'s only input is `march
--check-json` (`forge/lib/cmd_cap.ml` is unrelated; the relevant call site
is `forge/lib/cmd_fix.ml:52`), and `bin/main.ml`'s `--check-json` branch
prints and exits well before the `--compile`-only ceiling block ever runs,
so the fix currently reaches neither `forge fix` nor the LSP. Landing this
item doesn't just close the detection gap — it is also what turns an
already-built, already-tested fix payload into something a user can
actually apply.

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
layer below this — see `record_fn_refs`'s doc comment, typecheck.ml
~8990-8996: `free_vars_expr` is used instead of a calls-only walker
specifically because a function referenced as a *value*, not just called,
must still contribute its capabilities, or they "silently vanish from the
caller's closure" (that comment's own words for the false-NEGATIVE this
guards against). The SEPARATE "cardinal sin" remark two paragraphs later
(~line 9009) is the opposite-direction failure this same over-inclusion can
cause — a sibling function merely sharing scope inheriting capabilities it
never uses — which is a false POSITIVE, not the false negative. Both are
real and both matter here: whatever seeds a body-only table still walks
that same over-inclusive edge set, so a module that merely holds a
reference to (without ever calling) a `Cap(X)`-parameterized helper
elsewhere could still inherit `X` falsely. Worth an explicit test case
before this ships, not just the `main`-shape
regression test the 2026-08-08 fix already has.

**A latent trap to fix WHILE implementing this**: the `FInsert` fix that
Task 7 Steps 3-4 built is currently mis-placed for cross-file modules, and it
is invisible today only because nothing consumes it. `span_and_is_header`
(`bin/main.ml:2138`) falls back, when a module's `decl_span` is `dummy_span`
(which is how every module loaded from a separate file is synthesized —
`bin/main.ml:361-364`), to `first_real_decl_span` — the module's first inner
declaration, typically a `fn` — while still returning `is_header = true`.
`cap_ceiling_fix_indent` (`bin/main.ml:2194`) then computes `base + 2` off
that `fn` line's indentation, and the insert is anchored after it. So applying
the fix would write `needs X` INSIDE the function body rather than at the top
of the module — syntactically wrong, and on the exact cross-file shape this
todo is about.

The moment the ceiling runs under `--check`, that payload reaches
`--check-json` and `forge fix` and the mis-placement becomes a real,
user-visible bug. Either give the fallback its own `is_header = false` plus a
module-body-relative anchor, or suppress the fix payload entirely when the
span came from the fallback. Cover it with a test that APPLIES the fix and
re-parses the result, not merely one that asserts the diagnostic text — a
text-only assertion passes with the insert in the wrong place.

Not urgent — under-reporting (this gap) is the tolerable failure mode per
the capability-UX plan's own priorities; `--compile` still catches the real
case before it reaches a binary. Priority is "close before `--check` is
advertised as a complete substitute for `--compile`'s capability guarantees
anywhere in the docs."
