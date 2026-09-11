# Six correctness fixes: record-name leak, `FileError` naming, two unlinkable builtins, a dead hook, formatter collapse, coverage > 100%

**Date:** 2026-09-11
**Status:** designed; nothing here has landed
**Todos this must close, one section each:**

| § | Todo | Verdict on the todo's own diagnosis |
|---|---|---|
| 1 | [`2026-09-09-typecheck-record-state-leaks-across-checks`](todos/2026-09-09-typecheck-record-state-leaks-across-checks.md) | correct; the global is named below |
| 2 | [`2026-09-08-fileerror-bare-vs-qualified-type-name`](todos/2026-09-08-fileerror-bare-vs-qualified-type-name.md) | correct, and worse: bare `NotFound` resolves to `DnsError` |
| 3 | [`2026-08-22-builtins-that-typecheck-but-do-not-link`](todos/2026-08-22-builtins-that-typecheck-but-do-not-link.md) | correct; line pointers moved |
| 4 | [`2026-08-27-inject-iface-exports-hook-has-no-reader`](todos/2026-08-27-inject-iface-exports-hook-has-no-reader.md) | correct; all pointers moved; no consumer is reachable |
| 5 | [`2026-08-03-formatter-collapses-multiline-literals`](todos/2026-08-03-formatter-collapses-multiline-literals.md) | half-right: a width budget exists; literals have no multi-line form to break into |
| 6 | [`2026-08-03-coverage-expression-percentage-exceeds-100-percent`](todos/2026-08-03-coverage-expression-percentage-exceeds-100-percent.md) | **wrong**: the numerator IS file-filtered; the denominator skips test bodies |

Every `file:line` below was read on this branch at `79d78def`. Where a todo's
pointer has moved, the section says so.

---

## 0. What is already true in the tree (verify before building)

- **§1** `check_module_core` (`lib/typecheck/typecheck.ml:5959`) already resets one
  process-global per check, `March_ast.Json_dispatch.reset ()` at `:5968`, with a
  comment saying why. The global it does *not* reset is `_record_names`
  (`lib/typecheck/typecheck_types.ml:242`). `bin/main.ml:159-166` restores that
  table from the `~/.cache/march` tcenv cache and `:210-212` marshals it, so a fix
  must keep stdlib's entries across a cache hit.
- **§2** The representation half is fixed
  (`specs/progress/2026-09-08-file-dir-builtins-fileerror-representation-fix.md`).
  What remains is naming: 13 `TCon ("FileError", [])` in
  `lib/typecheck/typecheck_builtins.ml:887-894,980-984` and their mirrors in
  `lib/tir/llvm_builtins.ml:543-567`. `test/test_stdlib_suite.ml:10705` accepts
  `#<tag:N>` as valid compiled output; that acceptance is §2's RED control.
- **§3** `worker` / `dynamic_supervisor` are at `typecheck_builtins.ml:988` and
  `:992` (the todo's `typecheck.ml:2811/2815` predate the Phase 6 split). Neither
  has an `llvm_builtins.ml` entry or a `runtime/*.c` definition (`grep -rn
  'worker\|dynamic_supervisor' lib/tir runtime` finds nothing), so both still fail
  at link time. The compiled supervision path is `supervise do`
  (`lib/tir/lower_actor.ml:330-343`, `llvm_builtins.ml:928-930`).
- **§4** `inject_iface_exports_ref` moved twice since filing and still has zero
  dereferences: declared `lib/typecheck/typecheck_env.ml:1140`, exported
  `typecheck_env.mli:262`, installed `lib/typecheck/typecheck_unify.ml:812`, and
  the export-dropping arm is `typecheck_env.ml:1233`. `typecheck_unify.ml:15-19`
  already calls it "a breadcrumb".
- **§5** `lib/format/format.ml` has a width budget (`should_break` `:511-513`,
  used at `:655`, `:754`, `:871`, `:891`) and a multi-line call emitter
  (`emit_call_multiline` `:594`) that fires only for trailing lambdas
  (`trailing_multiline` `:503`). List and record literals are rendered solely by
  `expr_inline` (`:361-364`, `:436-438`), which has no multi-line form.
- **§6** `lib/coverage/coverage.ml:202-210` (`count_unique_hits`) filters the
  numerator by file and has since the flag's birth commit `e8277b8c`. `walk_decl`
  `:174` skips `DTest | DSetup | DSetupAll` on purpose. `march_coverage` is linked
  into no test executable (`test/dune:8,15`).

---

## 1. A record declared in one `check_module` changes a later check's diagnostic

### The gap

Two `Typecheck.check_module` calls in one process share the display-only
record-name index, so `{ a : Int }` declared in check N decides whether check
N+1's "expected `Thing` but got `Thing`" error carries its "Two distinct types
are both named" note. Reproducer, one alcotest process: `typecheck "mod X do type
A = { a : Int } end"`, then `test/test_compiler.ml:12308`
(`test_same_name_type_collision_note`). The second fails; either alone passes.

### Root cause, grounded

- `lib/typecheck/typecheck_types.ml:242` — `_record_names : (string, string
  option) Hashtbl.t`, keyed by sorted field-name signature. `register_record_name`
  (`:256-278`) poisons a signature to `None` at `:276` when a *different* bare
  name claims the same field set; nothing ever un-poisons.
- `pp_ty`'s `TRecord` arm (`:306-311`) prints the recovered name when
  `recover_record_name` (`:280`) returns `Some`, else structural `{ a : Int }`.
- `lib/typecheck/typecheck_unify.ml:91-93` — `same_printed = structurally_distinct
  && pp_ty expected = pp_ty found`; `:211` suppresses the note when false; `:228`
  is the note text.
- Registration: six unconditional sites in `typecheck.ml` (`:4243`, `:6100-6101`,
  `:6174`, `:6475-6476`, `:6537`), never cleared.

In the failing test `Inner.Thing = { a : Int }` registers `"a" -> Thing`;
`use_inner(t : Inner.Thing)` is a `TRecord`, `make()` a `TCon Thing`, so they
print alike only while `"a"` recovers to `Thing`. An earlier `"a" -> A` poisons
the signature, `pp_ty` prints `{ a : Int }`, `same_printed` is false, the note is
gone. That is the todo's "field name matters" observation.

Exposed: the test suite; the LSP (`lsp/lib/analysis.ml:2496` →
`check_module_with_env_full` → `check_module_core`); the REPL JIT
(`lib/jit/repl_jit.ml:1001,1075,1183,1313`). Not the CLI (one check per process;
the cache restore reinstates only stdlib entries).

### Candidate fixes

**A — snapshot-in-env restore (chosen).** Add `record_names_snapshot : (string *
string option) list` to `env`. `check_module_core` copies `_record_names` into the
returned env at exit; at entry it resets the table and reloads
`se.record_names_snapshot` when `seed_env = Some se`, or to empty when `None`.
Every check starts from exactly the state its seed was produced in: stdlib
entries survive (they are in the seed), a previous check's user entries do not.
The cached env is marshalled wholesale, so the snapshot rides along; the explicit
marshal at `bin/main.ml:210-212` becomes redundant but harmless.

**B — `Hashtbl.reset` only when `seed_env = None`.** One line; fixes the suite,
leaves the LSP and REPL (which always seed) leaking — and those are the todo's
stated reason for P2.

Cost of A: one list copy per check (a few hundred entries after stdlib) and one
env field; the six registration sites are untouched.

### Test plan

`test/test_compiler.ml`: case `record name index does not leak across checks` —
`typecheck "mod P do type A = { a : Int } end"` then the body of
`test_same_name_type_collision_note`, asserting the note. **RED control**: fails
on today's tree with the note missing (the todo's measured behaviour). REJECT
witness for the snapshot: seed a check with an env containing a stdlib-declared
record and assert `pp_ty` still recovers that name (A did not wipe the seed).
Then, same commit, remove the landmine comment at
`test/test_cap_unforgeable.ml:173-185` and rename `FjdAlpha` back to `A`; the
suite staying green is the third witness.

**Effort:** S. **Risk:** low — `_record_names` feeds rendering only
(`typecheck_types.ml:239-241`).

---

## 2. `file_*`/`dir_*` declare a bare `FileError` that no type declares

### The gap

Application code cannot branch on a file error's constructor. Reproducer
(interpreted, against `_build/default/bin/main.exe` built 2026-09-10 22:31,
twelve hours before `79d78def`; the intervening commits touched neither table):

```march
mod FeProbe do
  needs IO
  fn classify(r : Result(String, FileError)) : String do
    match r do
      Ok(_) -> "ok"
      Err(NotFound(p)) -> "notfound:" ++ p
      Err(_) -> "other"
    end
  end
  fn main(cap : Cap(IO)) do println(classify(file_read("/nonexistent/zzz"))) end
end
```

Three errors: ``I cannot find `FileError` `` on the annotation; ``expected
`FileError` but got `DnsError` `` on `NotFound` (the bare constructor resolves to
`Dns`'s same-named one, `stdlib/dns.march:15`); with `Err(File.NotFound(p))`,
``expected `FileError` but got `File.FileError` ``. Only opaque `Err(e)` checks.

### Root cause, grounded

- `typecheck_builtins.ml:887-894` (eight `file_*`) and `:980-984` (five `dir_*`)
  use `TCon ("FileError", [])`; the comment at `:880` itself says "a concrete
  `File.FileError` value at runtime". `:893` has the same shape for `FileStat`
  (`ptype FileStat`, `stdlib/file.march:18`); sweep it too.
- The only declaration is `ptype FileError` inside `mod File`
  (`stdlib/file.march:12`). A stdlib-loaded module's constructors carry the
  qualified type (`instantiate_ctor`, `typecheck_unify.ml:850-858`, builds
  `TCon (ci.ci_type, …)`), hence the pattern reports `File.FileError`.
- Compiled `to_string`: `lib/tir/llvm_ctor_desc.ml:175` looks the descriptor up
  by the static TIR type name; `llvm_builtins.ml:543-567` declare `ret_ty =
  Result(_, TCon ("FileError", []))`; no descriptor is named bare `FileError`;
  the fallback prints `#<tag:N>` (`llvm_ctor_desc.ml:5,17`).
- Precedent for a qualified name in the table: `csv_next_row : … ->
  TCon ("Csv.CsvRow", [])` (`typecheck_builtins.ml:916`) for `ptype CsvRow` in
  `stdlib/csv.march:29`.

### Candidate fixes

**A — qualify the tables (chosen).** Replace the 13 + 1 bare names in
`typecheck_builtins.ml` and the matching `ret_ty`s in `llvm_builtins.ml:543-567`
with `"File.FileError"` / `"File.FileStat"`, as `Csv.CsvRow` does. Annotations
write `File.FileError` (`resolve_qualified_type`, `typecheck_env.ml:1250`),
patterns write `File.NotFound(p)`, and the descriptor lookup finds
`File.FileError`, so compiled `to_string` prints `NotFound("…")`.

**B — register a bare alias `FileError -> File.FileError`.** Nothing in the tree
typechecks with the bare spelling today (the probe shows it is unresolvable), and
it keeps the `DnsError.NotFound` ambiguity alive.

Why A: existing convention; removes an ambiguity rather than papering over one;
`stdlib/file.march`'s wrappers (`fn read(path) do file_read(path) end`, `:22`)
are inside `mod File` and already see the qualified type. Cost: a two-table
sweep, plus re-qualifying any stdlib match on bare `NotFound(` over a file
result (grep during the change).

### Test plan

- Native golden `test/native/file_error_ctor_match.march`: the reproducer with
  `File.FileError` / `File.NotFound`, expected `notfound:/nonexistent/zzz`,
  compiled and interpreted. RED control: fails to typecheck today.
- Tighten `test/test_stdlib_suite.ml:10705`: delete the `|| compiled_line =
  Printf.sprintf "#<tag:%d>" tag` alternative. RED control: every compiled row
  fails today (`#<tag:0>` / `#<tag:4>`).
- REJECT witness: bare `Err(NotFound(p))` on a `file_read` result stays an
  error, now `File.FileError` vs `DnsError` (guards against B creeping back).

**Effort:** S–M (mechanical, but a new `test/native` fixture moves
`test/refine_audit/corpus.baseline`, and `@types-check` goldens may re-word).
**Risk:** low-medium; declared types only, representation already fixed.

---

## 3. `worker` and `dynamic_supervisor` typecheck but do not link

### The gap

`Supervisor.spec(:one_for_one, [worker(Worker)])` is documented
(`docs/supervision.md:466-480`) and works interpreted
(`test/test_helpers.ml:1513-1614`), but `march --compile` of any program calling
`worker(...)` or `dynamic_supervisor(...)` dies at link time with `Undefined
symbols: _worker` — a C symbol, no March span.

### Root cause, grounded

- Types: `typecheck_builtins.ml:988` (`worker : ∀a. a -> ChildSpec`), `:992`
  (`dynamic_supervisor : Atom -> Atom -> ChildSpec`); consumers `Supervisor.spec`
  `:989`, `Supervisor.start_child` `:993`; `ChildSpec`/`SupervisorSpec` opaque at
  `:1655`.
- Interpreter: `lib/eval/eval.ml:2766` (`worker` → `VRecord` with
  `actor`/`restart`/optional `name`), `:2857` (`dynamic_supervisor`), `:2889`
  (`Supervisor.start_child`).
- Compiled backend: no `llvm_builtins.ml` entry, no `lib/tir/defun.ml`
  `builtin_names` entry, no `purity.ml` entry, no C symbol. The `app` declaration
  hosting this DSL desugars to `__app_init__` for eval (`eval.ml:3561-3562`) and
  sits in `lib/tir/lower.ml:875`'s list of declarations lowering ignores. The
  whole value-level supervisor DSL is interpreter-only, not just these two names.
- Not in the todo: `test/test_codegen.ml:5424` defines a user `pfn worker(remaining
  : Int)` — a common identifier now claimed by a `∀a. a -> ChildSpec` builtin.

### Candidate fixes

**A — implement the runtime symbol.** Decide `ChildSpec`'s C representation,
then back `Supervisor.spec` and `Supervisor.start_child` too, or the first
program past `worker` fails on the next symbol. That is a second compiled
supervisor beside `supervise do` (`march_register_supervisor`,
`llvm_builtins.ml:928-930`), which the 2026-09-08 design made the single compiled
surface. Sites, per the `unix_time_ms` precedent (`grep -rn unix_time_ms`):
`typecheck_builtins.ml` (present), `eval.ml` (present), `llvm_builtins.ml`,
`defun.ml:145`, `purity.ml:28`, `js_emit.ml:704`, `runtime/march_runtime.c` +
`.h`, `lsp/lib/analysis.ml:4521` capability map, `test/test_codegen.ml:397`
byte-identical preamble golden, `lsp/test/test_lsp_analysis.ml:127`
prelude-collision parity. Effort L.

**B — delete the builtin.** Removes `:988`/`:992`, `eval.ml:2766-2887`, the
`Supervisor.spec`/`start_child` consumers, the `app` docs
(`docs/supervision.md:466-480`, `specs/lang/supervision.md`) and the interpreter
tests at `test_helpers.ml:1513-1614`. Deletes a documented, working interpreter
feature to fix a compiled link error. Effort M; a language change, not a fix.

**C — delete from the compiled backend only: reject at lowering (chosen).** A
closed list in `lib/tir/lower.ml` — `interpreter_only_builtins = ["worker";
"dynamic_supervisor"; "Supervisor.spec"; "Supervisor.start_child"; …]` — that
raises a diagnostic at the call span: "`worker` builds a value-level child spec,
which only the interpreter runs; in a compiled program declare the child in a
`supervise do … end` block." The link-time C symbol becomes a compile-time March
error, which is the todo's actual defect, and the whole DSL is covered in one
list. The same list is the exclusion set the todo's proposed CI drift check
needs (interpreter-only builtins and derive-bound placeholders like
`from_json_events` are its two legitimate skip categories).

Why C: A duplicates a surface just designed to be unique; B removes documented
behaviour. Cost: one list, one diagnostic, one sentence in `docs/supervision.md`
saying `app`/`Supervisor.spec` are interpreter-only.

### Test plan

`test/test_codegen.ml`: compile a module calling `worker(Counter)`; assert
failure text contains the new diagnostic and a `.march:` span. **RED control**:
today the text contains `Undefined symbols` and no span. `test_helpers.ml:
1513-1614` stay untouched as the witness that eval lost nothing;
`test_codegen.ml:5424-5436` stays as the witness that a user `worker` still
compiles (cite it in the new test's comment).

**Effort:** S. **Risk:** low; fires only on names that cannot link today.

---

## 4. `inject_iface_exports_ref` is installed but never read

### The gap

A forward hook meant to inject cross-module interface-method bindings has had no
reader since its WIP birth commit `d95631a6`; the comments at its declaration and
at the `ExInterface` load arm assert a behaviour the code lacks. Reproducer:
`grep -rn inject_iface_exports lib lsp bin forge test` — declaration, `.mli`,
installation, three comments, no `!`.

### Root cause, grounded

All four of the todo's pointers moved in the Phase 6 decomposition:

| todo said | now |
|---|---|
| `typecheck_env.ml:1073` decl | `lib/typecheck/typecheck_env.ml:1140` (+ `typecheck_env.mli:262`) |
| `typecheck.ml:745` install | `lib/typecheck/typecheck_unify.ml:812-847` |
| `typecheck_env.ml:1166` drop arm | `lib/typecheck/typecheck_env.ml:1233` `ExInterface _ -> env` |
| `typecheck.ml:743` comment | `typecheck_unify.ml:810-811`, `typecheck.ml:92` |

Is any consumer reachable? Follow the data:

- `ExInterface` entries come only from `extract_exports`
  (`lib/modules/module_registry.ml:208-211`).
- The registry is populated by `ensure_loaded` (`module_registry.ml:227-259`),
  which reads **stdlib files only** (`find_stdlib_file`), and by the REPL
  (`lib/repl/repl.ml:875`, `:1468`). `forge/` never references `Module_registry`.
  `MARCH_LIB_PATH` modules are synthesized as `DMod` nodes in the entry AST
  (`bin/main.ml:1410-1412`), not registry entries.
- stdlib declares **zero** interfaces (`grep -c '^ *interface ' stdlib/*.march`),
  so the stdlib path never yields an `ExInterface`.
- In the REPL, `tc_env` threads and `check_decl` on a `DMod` runs
  `prebind_interface_decl` (`typecheck.ml:6105`, `:6480`), binding each method as
  both `Iface.method` and `Mod.Iface.method` (`typecheck_env.ml:263-265`). The
  hook's `qname` (`typecheck_unify.ml:820`) is that second form, and its first
  line is `if StrMap.mem qname env.vars then env` — a no-op there.

No path exists on which the hook would bind a name `prebind` has not already
bound. The todo's "observable consequence (unconfirmed)" does not exist here.

### Candidate fixes

**A — finish it** (call from `load_module_into_env`): runs only for
REPL-registered modules whose methods are already bound. Dead on arrival.

**B — delete it (chosen).** Remove `typecheck_env.ml:1137-1142` and the `.mli`
line, `typecheck_unify.ml:810-847`, the breadcrumb at `typecheck_unify.ml:15-19`
and the mention at `typecheck.ml:92`; reword `typecheck_env.ml:1146` and `:1233`
to "cross-module interface exports are not injected here; in-file and REPL
modules bind interface methods via `prebind_interface_decl`". Also drops
`lib/typecheck/`'s top-level side effects from two to one (`expand_record_ref`,
`typecheck_unify.ml:922`), which
`specs/plans/2026-08-27-remaining-decomposition-targets.md` Target B wants.
Cost: ~40 lines removed, nothing to migrate.

### Test plan

A guard that the deletion changes nothing observable: `test/test_compiler.ml`
case `qualified interface method resolves across in-file modules` — `mod A do
interface Sh(a) do fn sh(x : a) : String end end` plus an `impl`, and `mod B do fn
f() do A.Sh.sh(1) end end`, asserting no errors; plus the two-fragment REPL
equivalent in `test/test_jit.ml`. The control is inverted: both must be GREEN
before and after; what must change is `grep -c inject_iface_exports lib` from 6
to 0. Run `scripts/types-oracle.sh` under a private `HOME` before/after; any diff
means a consumer existed after all.

**Effort:** S. **Risk:** very low.

---

## 5. The formatter collapses a multi-line literal onto one line

### The gap

`march fmt` on a function whose body is a long list of records with `++`-chained
string fields emits the literal as one line (19,509 chars in the todo's forgepm
case). In `test/test_fmt.ml` terms:

```ocaml
fmt {|mod T do
fn all() do
  [{ name: "…40 chars…", sql: "…40 chars…" }, { name: "…", sql: "…" }, { name: "…", sql: "…" }]
end
end|}
```

returns a body line far over 80 columns.

### Root cause, grounded

The todo's "no width budget" is not what the code shows:

- `format.ml:511-513` — `should_break indent expr = is_multiline expr ||
  String.length (expr_inline expr) + indent*2 > 80`; the header (`:6`, `:10`)
  promises 80 columns and four sites honour it (`:655` if/else, `:754` pipes,
  `:871`, `:891` record type declarations).
- `emit_stmt` (`:520-583`) has no arm for a list or record *literal*. Its arms:
  blocks, lets, match, if, pipe, `let?`/`let*`, multi-line sigils, multi-line
  lambdas, and calls/constructors with a trailing multi-line lambda
  (`trailing_multiline` `:503`, used `:576-581`, via `emit_call_multiline`
  `:594`). Everything else hits `| _ -> line ctx (expr_inline e)` (`:582-583`).
- `expr_inline` renders a list as `"[%s]"` over `", "`-joined elements
  (`:361-364`, rebuilt from `Cons` cells by `try_collect_list` `:313`) and a
  record as `"{ %s }"` (`:436-438`). Neither can break.

The budget exists but is consulted only where a multi-line renderer exists;
literals have none, so `should_break` is never asked about them. This also
confirms the todo's instinct that `++` is not the issue.

Also confirmed: `lsp/lib/server_dispatch.ml:330-345` calls `format_source
~filename src` and reads no `FormattingOptions`; `tabSize`/`insertSpaces` are
ignored.

### Candidate fixes

**A — add multi-line literal renderers (chosen).** New `emit_stmt` arms before
the fallback, each gated on `should_break ctx.indent e`: a collected `Cons` list
→ `[` / one element per line at `indent+1` with trailing commas / `]`;
`ERecord` → `{` / `field: value,` per line / `}`; `EApp`/`ECon` with too-wide
args and no trailing lambda → reuse `emit_call_multiline`. Elements recurse
through `emit_stmt` so a too-wide record inside a list breaks in turn; extend
`is_multiline` (`:495`) so a parent whose child broke does not re-flatten it via
`expr_inline`.

**B — a Wadler/Leijen group-based printer.** The "standard fix" the todo names;
a rewrite of a 1,240-line file with 34 round-trip tests whose comment
re-insertion is by source line number (`extract_comments` `:33`) and would not
survive a re-layout engine. Rejected here; A is the incremental subset of B.

Honest cost of A: a single atom wider than 80 columns (one long string, or one
`++` chain the todo forbids splitting) still yields an over-width line. The
forgepm acceptance must read "no line exceeds 80 unless a single element does",
and the sweep should print the count of such lines rather than pretend to zero.

### Test plan

`test/test_fmt.ml` (helpers `fmt`, `check_parses`, `check_idempotent` `:16-28`),
four cases: (1) long list of records → one element per line, every line ≤ 80
unless a single literal is longer — **RED control**: one line today; (2) REJECT
witness: `[1, 2, 3]` and `{ a: 1, b: 2 }` stay on one line byte-for-byte; (3)
`check_idempotent` on case 1's *output*; (4) a too-wide record element inside a
list breaks at `indent+2`. Then `march fmt` over `~/code/forgepm`, reporting max
width and the over-width-single-literal count.

**Effort:** M. **Risk:** medium — non-idempotent output is the classic failure;
the 34 existing round-trips plus case 3 guard it.

---

## 6. `--coverage` reports an expression percentage above 100%

### The gap

`march test --coverage` on a test file prints `Expressions: 2095 / 430 (487.2%)`.
Reproducer (interpreted): a `.march` with one two-line function and a `describe`
holding one `test` that calls it thirty times; the denominator is the function's
few nodes, the numerator every node in the test body too.

### Root cause, grounded

The todo's likely cause — an unfiltered numerator — is not it:

- `coverage.ml:202-210` `count_unique_hits … ~file` keeps only keys whose
  `file_part = file`; `git log -S'file_part = file'` shows it arrived with the
  flag (`e8277b8c`). Keys are `file:line:col` (`span_key` `:26-27`).
- The evaluator records **every** evaluated expression — `lib/eval/eval.ml:2322`
  `record_expr (span_of_expr e)` — including those inside `test … end` bodies in
  the target file.
- The denominator walks the AST (`walk_expr` `:87-156`, `walk_decl` `:163-180`)
  and at `:174` does `| DTest _ | DSetup _ | DSetupAll _ -> ()` — comment: "their
  bodies always execute and would inflate the coverage denominator". `DDescribe`
  recurses (`:179`) but its `DTest` children are skipped.

Numerator includes test bodies, denominator excludes them: 2095 evaluated sites
vs 430 non-test sites is exactly a test file's shape. Branches look sane (6/9)
because `record_branch` (`eval.ml:1989,1993`) fires only on `EIf` and test bodies
are mostly straight-line asserts. Caller: `bin/main.ml:1245` `report_summary
~target_file:filename desugared ()`.

### Candidate fixes

**A — intersect hits with the walked set (chosen).** `count_totals` also returns
the `StringSet` of `span_key (span_of_expr e)` for every node it counts;
the expression numerator becomes `|expr_hits ∩ set|`, and likewise for branch
keys (`:T`/`:F`/`:armN`). The numerator can never exceed the denominator
whatever `walk_decl` skips now or later, and the `:172-173` intent is kept.

**B — count `DTest` bodies in the denominator.** One line at `:174`; makes the
ratio meaningful but inflates it with always-executed code the author excluded
on purpose, and leaves the two counters free to drift apart again.

Why A: it restores the invariant `hit ⊆ total` rather than one instance of its
violation. Cost: one `StringSet` per report. The slowness the todo notes
(`span_key` allocation per evaluation) is a separate item and stays separate.

### Test plan

Add `march_coverage` to the `run_eval` library's `libraries` (`test/dune:15`).
New case in `test/test_eval.ml`: parse + desugar the reproducer, `Coverage.reset
()` (`:56`), set `coverage_enabled` (`:14`), `Eval.run_module`, then assert
`count_unique_hits expr_hits ~file <= fst (count_totals ~file m)` and the
percentage ≤ 100. **RED control**: on today's tree the inequality fails for any
module whose test body outnumbers its non-test nodes. Second case: a module with
no tests reports identical numbers before and after (A only intersects, never
subtracts real coverage).

**Effort:** S. **Risk:** low; reporting only.

---

## Landing order

§4 and §1 first (pure removal, pure state hygiene; both unblock test authoring),
then §6 and §3, then §2 (two tables plus the refine-audit baseline), then §5
(largest surface, most idempotency risk). Each lands with its todo `git mv`'d to
`specs/progress/` and a `CHANGELOG.md` `[Unreleased]` bullet: `Fixed` for all six,
plus a `Changed` note for the `File.FileError` spelling (§2) and the new
compile-time rejection (§3).
