`[P0]` - [x] **A user-defined top-level function silently replaces a same-named Prelude function everywhere in the program, including inside Prelude's own internal calls — found while benchmarking `Parse`. Fixed 2026-08-14.**

**Fixed.** `lib/modules/prelude_collision.ml`, wired into every compiler
entry point (`march file.march`, `--check`, `--compile`, `march check`,
`march dap`). Design and full history — including two corrections forced
by running the fix against the real corpus rather than trusting a design
review — in `specs/plans/2026-08-13-prelude-entry-fn-name-collision.md`.
Both repros below are now compile errors naming the collision; verified
against the real compiler (interpreted/`--check`/`--compile`), 8 unit
tests (all proven non-vacuous by sabotage), and the full test suite
(2,643 tests, 0 failures). The original report is kept below verbatim as
the evidence trail.

Any top-level function (`fn` *or* `pfn`, public or private, in any module) whose bare name matches a name Prelude uses **internally** silently hijacks that name for the whole program. Prelude functions call other Prelude functions unqualified (e.g. `println(x) do print(show(x)); print("\n") end`), and those unqualified calls resolve against a single flat post-lowering namespace rather than the module `println` is lexically defined in. No redefinition error, no warning, at any stage — parse, typecheck, or codegen.

**Minimal repro (arity-mismatch manifestation):**
```march
mod Shadow do
  needs IO.Console
  pfn show(label : String, t : Int) : Unit do
    println(label ++ int_to_string(t))
  end
  fn main(_cap : Cap(IO.Console)) : Unit do
    println("hello")
    show("x", 1)
  end
end
```
Interpreted: `arity mismatch: expected 2 args, got 1`, stack frame `[0] println() shadow.march:8` — the error is misattributed to the call site, giving no hint that a private helper is the cause. Compiled `--opt 2`: **SIGBUS, exit 138, zero output** — not even `println("hello")`'s own text reaches stdout before the crash.

**Minimal repro (silent-no-op manifestation, more dangerous):**
```march
mod Shadow3 do
  needs IO.Console
  fn print(x : Int) : Unit do
    ()
  end
  fn main(_cap : Cap(IO.Console)) : Unit do
    println("should print this and a newline")
  end
end
```
`print` is public here, not a typeclass/interface name, arity happens to match (1 param). Both interpreted *and* compiled: **complete silent no-op** — no output, no error, no crash, in either backend. `println`'s entire body becomes a no-op because both of its internal `print(...)` calls route to the user's `Int -> Unit` stub, which discards its argument and returns `()`.

**Confirmed at the IR level**, not just behaviorally — `--dump-tir` on the first repro:
```
fn show(label : String, t : Int) : () = ...
...
fn println$String(x : String) : () =
  let $t422 : String = show(x) in
```
There is exactly ONE `show` symbol in the entire dumped program: the user's. Prelude's own `println$String` specialization calls it unqualified and gets the user's definition — proof the collision happens in the flat post-lowering function table, not merely as a surface-syntax ambiguity that later resolves correctly.

**Not `show`-specific and not `pfn`-specific.** Reproduced with `print` (a plain function, not a Show/Eq/Compare/Hash-style structural dispatch name) and with `fn` (public) instead of `pfn` (private) — so this is general flat-namespace shadowing, not a quirk of the `Show` interface's dispatch mechanism.

**Severity — corrected after CI (2026-08-14):** NOT every prelude name is exposed, only names Prelude's own function bodies actually call unqualified from within another Prelude function — `panic` (called by `unwrap`/`head`/`tail`), `reverse` (called by `filter`/`map`), `print` and `to_string` (called by `println`/`debug`/`str`/`inspect`), plus `show`/`eq`/`compare`/`hash` at a matching arity (arity-gated separately, see the fix design). `println`, `str`, `map`, `filter`, `head`, `tail`, `unwrap`, `unwrap_or`, `identity`, `compose`, `flip`, `debug`, `inspect`, and most of the rest of the ~21-name Prelude list are **never called from within another Prelude function's body**, so shadowing them is safe and already correctly resolved by the compiler's real name resolution (`specs/lang/types/accept/t126_entry_module_shadows_list_length.march` and `t168_module_fn_shadows_builtin_name.march` are explicit regression tests for exactly this). The initial version of this fix wrongly treated the whole ~21-name list plus the entire builtin table as dangerous; PR #274's CI caught the over-breadth via 9 rejected accept-corpus fixtures. See `specs/plans/2026-08-13-prelude-entry-fn-name-collision.md` §2.5b for the full correction. A user choosing a name Prelude genuinely relies on internally can still silently corrupt unrelated Prelude behavior program-wide, with three observed failure modes depending on arity/type overlap: a misattributed runtime error (interpreted), a **SIGBUS with no diagnostic** (compiled), or a **fully silent wrong result** (both backends) — the last being the most dangerous, since nothing signals anything went wrong.

**Not yet root-caused to a specific pass.** The TIR dump shows the collision is already present by the time TIR exists, so the bug is somewhere in name resolution / symbol-table construction feeding lowering — plausibly the same family as the previously-fixed "ambiguous ctor -> prefer current module" bug (`project_ambiguous_ctor_current_module` in memory), but for **functions** rather than constructors, and here the wrong-module preference reaches into Prelude's *own* source rather than just a foreign stdlib module. Needs a dedicated session reading `lib/typecheck/typecheck.ml`'s / `lib/tir/lower.ml`'s function-name resolution to find where the flat table is built and why declaring-module identity isn't part of the key.

**Impact on other in-flight work:** `stdlib/parse.march`'s A/B benchmark work (`specs/progress/2026-08-12-json-combinator-ab.md`, `2026-08-12-parse-rebuild-cost-measured.md`) is unaffected — none of those helper functions were named `show`/`print`/other Prelude names (checked). This was found via a *later*, still-unfinished benchmark script that did define a colliding `show` helper; that script's results are discarded, not reused anywhere.
