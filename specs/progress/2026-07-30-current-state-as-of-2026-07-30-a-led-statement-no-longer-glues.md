# Current State (as of 2026-07-30, a `(`-led statement no longer glues onto the previous line)


**Counts:** `run_compiler` 619 (was 615, +4 parse tests), `run_codegen` 520
(was 518, +2), `run_eval` 256, `run_snapshots` 33 (unchanged — Perceus/borrow behaviour
did not shift), `run_stdlib` 826 with only the pre-existing environmental
`MARCH_SANITIZE` failure, grammar corpus 45/45, `dune build @runtest` clean.

**Reported as a native-codegen crash; it was a parser bug.** A compiled binary
died with `EXC_BAD_ACCESS`/exit 138 (or SIGSEGV/139) whenever it called a
function that both discarded a parameter (`let _ = a`) and had a literal `()`
as its tail. The emitted IR was damning-looking: the callee was never emitted
at all, and its call site had become a closure-style indirect call *through the
argument* — `getelementptr i8, ptr %sl, i64 16` (the closure ABI's `fn_ptr`
slot) then `call ptr (ptr) %fv(%sl)` — with `%sl` a `String`, so the program
counter ended up at `0x1`.

Codegen was faithfully compiling what it was given. `--dump-tir` at `tir-lower`
showed the callee's body as `a()`: `let _ = a` followed by a line holding only
`()` had parsed as the single binding `let _ = a()`, because a block's newlines
are swallowed by the token filter and the parser therefore saw `a` `(` `)`
adjacent and applied the call rule. The parameter was being *invoked*. The
interpreter agreed — `fn f(a) do let _ = a ⏎ () end` applied to
`fn -> IO.puts("CALLED")` printed `CALLED`, which is what turned a two-fault
codegen theory into a one-line parse fact.

The reported trigger matrix falls out of that reading exactly: both conditions
are required because the discard is what leaves a value-ending token at the end
of the previous line and the literal `()` is what puts a `(` at the start of
the next; a `None`/`0`/`IO.puts(...)` tail has no leading `(`, and a zero-arg
callee has no discard. It is not cross-module, and not an RC bug.

**The fix** (`lib/parser/token_filter.ml`, `lib/parser/parser.mly`). The
newline-separates-statements rule was already specified for `f(1)`⏎`(g(2))`
(grammar §7.3, witness `parse/p24`) but was only ever enforced for the
curried-call `)`⏎`(` shape; the *classification* of the paren ignored the
newline entirely. A `(` that follows a value-ending token across a newline is
now retagged `LPAREN_STMT`, a token accepted only by `expr_atom`'s
group/tuple/unit rules and by `simple_pattern`'s parenthesised/tuple rules
(a match arm may legitimately open a fresh line with a tuple pattern — that
case is what the `Deque.pop_front` codegen test caught mid-fix). The call rule
does not accept it, which is the whole fix. menhir's shift/reduce count is
unchanged at 9.

Pinned by four parse tests (`run_compiler`, including two negative controls:
a same-line call and a multi-line argument list must both still be calls), two
codegen tests (`run_codegen` — one asserting no `call ptr (ptr)` is emitted for
this program, one compiling and running it), and grammar witness
`parse/p33_paren_stmt_after_bare_ident.march`. All were confirmed RED against a
`git show`-sourced copy of the pre-fix parser and GREEN after.

Worth recording separately: the five `try_call_capture_ownership_codegen`
failures seen while verifying this were **not** related — they were the stale
staged-runtime trap (`_build/default/runtime` is not refreshed by a targeted
`dune build bin/main.exe`). `dune build @install` + `@test/cas-runtime-dir`
cleared all five.
