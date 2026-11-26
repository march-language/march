# Object capabilities, phase 8a: capture sets (inference, display, soundness) — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every function value, and every value that holds one, gets an inferred capture set: an
upper bound, in the scope language, on what it can do when called. Hover, `march-lsp query` and
a new `march --dump-captures FILE` show it. A soundness oracle proves the sets against real
runs. No program is newly accepted or rejected, and no generated code changes.

**Architecture:** Capture inference is a second pass over the already-typechecked AST. It never
touches `Typecheck_types.ty` or unification. It reads each expression's solved type from
`env.type_map`, builds a parallel *annotated type* (the same shape, with a set variable on each
arrow and each declared data type), emits inclusion constraints at flow points, and solves them
for the least solution. Named functions get capture schemes, computed on demand and memoised,
one strongly connected group at a time. In 8a the pass runs only when something asks for it
(hover, query, `--dump-captures`, the tests, or `MARCH_CAPTURES=1`), so an ordinary build does
not run it at all. Erasure is by construction: nothing the pass produces is read by lowering.

**Tech stack:** OCaml 5.5.1 (`lib/caps`, `lib/typecheck`, `lib/eval` test hooks, `bin/main.ml`,
`lsp/lib`). No parser, lexer, TIR, runtime C or stdlib change.

**Spec:** `specs/2026-11-11-ocap-capture-checking-design.md` (approved 2026-11-12; "the design"
below, `§n` is a section of it): §3, §4.1, §4.2, §5 (inferred rows), §6, §9, §10, §12, §13, §14,
§16 row 8a, §18. Parent: `specs/2026-11-10-object-capability-design.md` §4, §5, §13, §21.

## What earlier phases already give us

- `env.type_map : (Ast.span, ty) Hashtbl.t` holds the solved type of every expression
  (`typecheck.ml:5333`, `:5342`), of every `let` and pattern binder, of every parameter
  (`:6154`, `:6856`) and of each function name (`:6991`). Lowering and hover already depend on it.
  The stdlib's is in the marshalled tcenv cache (`bin/main.ml:306`).
- `env.fn_row_bodies` (key → `(params, body)` list) holds every function body the reach solver
  sees, keyed like `fn_refs`, stdlib included. `env.fn_refs` has the reference edges, including
  the dispatch edges from an interface method's node to each impl (`typecheck_caps.ml:1398`).
- `Typecheck_builtins.builtin_cap_table`, `entry_cap_table`, `locally_declared_names_of` and
  `March_ast.Calls.builtin_candidate_calls` find a body's own capability operations by kind.
  `Scoped_literal_check.literal_urls`, `Typecheck_caps.literal_path_uses` and `name_uses` find
  literal targets (phase 6, Q3).
- `env.fn_bound_points` holds each function's concrete clause and each literal `restrict`
  (`<fn>$restrict@<line>:<col>`); `env.grant_module_pkgs` and `Dep_grants` hold package grants.
- `Cap_lattice.cap_subsumes`, `Cap_scope.scope_subsumes`, `Host_scope` and `Name_scope` decide
  covering for one scope against another. There is no OCaml union or meet of scope *sets*: that
  lives in `stdlib/authority.march`. Task 1 builds the small set algebra the pass needs.
- The interpreter checks every gated operation through one builtin, `cap_check_raw(kind,
  target)` (`eval_builtins.ml:2898`), and applies every closure in `apply_inner`'s `VClosure` arm
  (`eval.ml:2117`). A named function read as a value is wrapped by `capture_named_value`
  (`eval.ml:686`). Actors take their authority in `spawn_authority` (`eval.ml:4110`).
- March has no partial application: under-application is a type error (`typecheck.ml:1642`).
  The design's "partial application" case is an eta-lambda, so it is covered by the lambda rule.
- `test/cap_conformance/` has 76 fixtures that exercise capture, `restrict`, grants, tasks and
  actors at run time. They are the oracle's main corpus.

## Global Constraints

- 8a adds no diagnostic of any severity. `scripts/oracle-base.sh all` must report the types
  oracle, the IR oracle and the refine oracle identical to the merge-base, apart from fixtures
  this branch adds.
- `Typecheck_types.ty`, unification, `check_fn_bounds` and `Cap_rows` are not edited. The design
  says capture sets later replace `deps` and `unknown` (§6.3); that replacement would change
  which programs are rejected, so it is not in 8a.
- A set is an upper bound (§3). Where the pass cannot model something, the answer is `Unknown`,
  which is above every set. It is never a smaller set.
- Narrowing by static authority applies only where the run-time authority is certainly at most
  the narrowing (§6.1, §10.1): to operations and direct named calls written in the function
  value's own body. It never applies to a set that arrives through a captured value, a called
  parameter or a value returned by a call (§6.2).
- Sets print in source syntax. An inferred variable prints as `c1`, `c2`, … in order of first
  appearance; no internal name appears (§11.5).
- Module-level function values are not narrowed: their set is their reach (§6.1, parent §21).
- The interpreter's oracle hooks are `option ref`s that are `None` outside the oracle test.
- Fixtures are written in the post-phase-7 style: `needs` lines, no `Cap(IO.*)` parameter, so
  phase 7's corpus migration has nothing to rewrite in them.
- Repo rules: no attribution lines; stage files by name; `dune build --root .`; never skip or
  quarantine a test; merge `origin/main`, never rebase; log to deciduous.

## Questions for the owner

My recommendation is first in each, and the plan is written to it.

- **Q1. Does the capture pass run on every build in 8a?**
  - *Recommended:* no. It runs on demand: hover, `march-lsp query`, `--dump-captures`, the test
    suites, and when `MARCH_CAPTURES=1` is set. An ordinary `--check` or `--compile` does not run
    it, so 8a cannot slow or break a build. The PR reports the forced-on cost
    (`MARCH_CAPTURES=1`) on the stdlib and on a large program, and a sweep test proves the pass
    finishes on every stdlib module, example, bench and native fixture. 8b turns it on for every
    build, because escape errors need it. If the forced-on cost is over the design's 5% budget
    (§18), 8a still ships and the number becomes 8b's entry gate, with a todo.
  - *Alternative:* always on from 8a. It soaks the pass on every real build earlier, but every
    user pays the time for output nobody reads yet, and a bug in the pass could fail a build.
- **Q2. Can a capture set be written in source in 8a?**
  - *Recommended:* no. 8a changes no grammar. Everything is inferred, public functions included,
    and the design's syntax appears only in output. The parser work (`needs` inside a type,
    `scoped`) lands in 8b, which needs both for `File.with_open`. A written set that 8a parsed
    but did not check would be a claim the compiler does not hold anyone to.
  - *Alternative:* parse and check written sets in 8a. That adds rule 2 and rule 3 errors early,
    which the design assigns to 8c.
- **Q3. What does an inferred public signature show?** In 8c a bare arrow in a public signature
  will mean "captures nothing". In 8a nothing is written yet, so hover on a public `map` can
  only show what was inferred: `(List(a), a -> b needs c1) -> List(b) needs c1`.
  - *Recommended:* show the inferred set, exactly as for a private function. It is what
    `forge fix` will write in 8c, so 8a's output doubles as a preview of the migration.
  - *Alternative:* show public signatures bare until 8c. Then 8a's display would be wrong about
    the functions people call most.

## Builder's calls (design §20, for the owner to check)

1. **Representation: a side layer, not a slot on `TArrow` and `TCon`.** `TArrow` has 1,448 uses
   in `typecheck_builtins.ml` alone, unification is symmetric while capture flow is directional
   (§6.3), and a side layer makes "shapes are unchanged" and erasure true by construction. The
   annotated type is `Capture_ty.t` (Task 2).
2. **The solver lives beside `cap_rows.ml`, not in it**: `lib/caps/capture_set.ml` (set algebra)
   and `lib/typecheck/capture_*.ml` (the pass). `Cap_rows` stays as it is (Global Constraints).
3. **A set element in 8a** is a scope `(kind, scope text option)`, the shape a `needs` entry
   already has (`Scope_expr.entry`), or a variable. Tracked names (§3) are added in 8b.
4. **Scoped elements come from literals at the existing entry points only**: a literal URL or
   URL prefix at a `@[net_dest]` function gives `IO.NetConnect("host/path/")`; a literal path at
   a filesystem entry gives `IO.FileRead("./data/")`; a literal name at a name-taking function
   gives `IO.Mut("sessions")`. At such a call the scoped element *replaces* the callee's
   kind-level element of the same kind. The callee's other kinds are kept. Everything else is
   kind-level. Method and limit arguments (`methods(get)`, `max(n)`) are never inferred in 8a.
5. **`Unknown`.** One extra element above every set, for constructs the pass does not model. It
   prints as `needs ?` in `--dump-captures` and as `needs IO` in hover with the note "not
   tracked here". 8b must treat `Unknown` as holding every tracked name. The PR reports how many
   creation sites are `Unknown`, per cause.
6. **Narrowing is a sound over-approximation of intersection.** `narrow e ~by` returns `e` when
   `by` covers it, the related entries of `by` when `e` is unscoped or an ancestor kind, nothing
   when no entry of `by` is related to `e`'s kind, and otherwise `e` itself (two scoped lists of
   one kind: the true meet is smaller, `e` is a safe upper bound).
7. **Interface method calls** take the union over every impl the dispatch node reaches, the
   same edges the reach solver uses. The parent design calls them direct calls (§21); which impl
   runs is not known before monomorphisation.
8. **Builtins get a default capture signature** derived from their HM type: one type variable is
   one annotation wherever it occurs, every function-typed argument may be called, and every set
   in an argument flows to the result's sets. A short table overrides the default where it is too
   coarse (`task_spawn*`, the `vault_*` family, `spawn`, `send`).
9. **Variance table.** Covariant: `List`, `Option`, `Result`, `Map`, `Set`, `Seq`, tuples,
   records, every user ADT, `Task`. Invariant: `Vault`, `Pid`, `Chan`, `Ref`-like builtins, and
   any builtin type not listed. Arrow parameters are contravariant, results covariant.
10. **A pid's message parameter** accepts any scopes (§9.1): sending adds no constraint in 8a.
    An actor's own reach (its handlers and `init`) is charged to the function value that spawns
    it (§6.1).
11. **Declared types** carry one set per value (§4.2): every bare arrow and every declared data
    type that appears in a field, at any depth not under a type parameter, shares the enclosing
    value's set. A type whose declaration reaches no arrow carries no set at all, which is the
    fast path for `Int`, `String`, `List(Int)` and most data.
12. **`--dump-captures` format** (Task 6) and the hover format (Task 7) as specified there.
13. **Oracle instrumentation: the interpreter only**, through three test-only hooks (Task 8). The
    conformance suite already proves the five runtimes agree on authority, so one runtime is
    enough to test the static sets.
14. **The oracle's rule** is by dynamic extent: while a function value created at site `S` is
    running, every operation checked, by it or by anything it calls or spawns, must be inside the
    grounded set of `S`. Grounding replaces each variable by the union of everything any call
    site in the program instantiates it with.
15. **Deferred, each with a todo:** inlay hints for inferred sets (§12 "may"); the run-time-bound
    note on values created inside a `restrict` (§6.2 "may"); replacing `deps`/`unknown` (§6.3);
    caching capture schemes for the stdlib beside the tcenv cache (needed once 8b is always on).

## Where 8a overlaps phase 7 (branch `claude/festive-brattain-e1536a`)

| Phase 7 touches | 8a's contact | What I do |
|---|---|---|
| New kinds `Actor.Introspect`, `Actor.Debug`, `IO.Cluster` in the lattice and `builtin_cap_table` | The pass reads kinds as strings from those tables | Nothing: new kinds flow through. One oracle fixture is added after 7a lands |
| `needs` resolution in `typecheck_caps.ml`; the `main` signature check | 8a reads `fn_bound_points`, `restrict_owners`, `grant_module_pkgs`; it edits none of that file | No edit to `typecheck_caps.ml` or the `main` check |
| `mock` syntax: lexer, parser, a new AST node | 8a's walk matches `Ast.expr` exhaustively | When 7a lands, merge `origin/main`; the build fails on the missing arm; add it: walk the body, narrow nothing (§13) |
| Retiring `Cap(IO.*)` and rewriting ~1,190 test files | 8a's fixtures | Written without `Cap(IO.*)` from the start |
| `bin/main.ml` flags; `specs/lang/capabilities.md`; `CHANGELOG.md` | One new flag, one new section, one bullet | Ordinary merge conflicts, resolved by merging `origin/main` |
| Interpreter interception for `mock` (`lib/eval`) | Three hook refs in `eval.ml` / `eval_builtins.ml` | Hooks are single lines next to existing code; re-check their placement after merging 7a |

If 7a merges first, I merge `origin/main` before the whole-branch review and rerun everything.

## File structure

| File | Responsibility |
|---|---|
| `lib/caps/capture_set.ml`, `.mli` (new) | Scope sets: elements, union, covering, narrowing, "admits this run-time target", printing |
| `lib/typecheck/capture_ty.ml` (new) | Annotated types, set variables, building one from a `ty`, the declared-type rule, variance, printing |
| `lib/typecheck/capture_infer.ml` (new) | The walk: constraints, effects, creation sites, schemes for named functions, static authority |
| `lib/typecheck/capture_solve.ml` (new) | Least solution, scheme simplification, grounding, variable naming |
| `lib/typecheck/capture.ml`, `.mli` (new) | The one entry point and the result type; `--dump-captures` rendering |
| `lib/typecheck/typecheck.ml`, `.mli` | Re-export `Capture`; nothing else |
| `bin/flags.ml`, `bin/main.ml` | `--dump-captures`, `MARCH_CAPTURES`, the `[timings] captures` stamp, the warm-cache skip list |
| `lsp/lib/analysis_types.ml`, `analysis.ml` | A lazy capture result per analysis; `type_at` appends the set |
| `lib/eval/eval_prim.ml`, `eval.ml`, `eval_builtins.ml` | Three oracle hook refs and their call sites |
| `test/test_capture_set.ml`, `test/test_captures.ml` (new, in `run_compiler`) | Unit and inference tests |
| `test/run_captures.ml`, `test/captures/*.march` + `.expected` (new suite `captures`) | Golden `--dump-captures` corpus |
| `test/run_capture_oracle.ml` (new suite `capture_oracle`) | The soundness oracle and the sweep |
| `scripts/run-tests.sh`, `scripts/affected.sh`, `scripts/test-affected.sh`, `test/dune`, `.github/workflows/ci.yml` | Register the two suites |

## Review Focus

1. **A closure laundered through polymorphic code**: passed through `id`, a pipe, `Option.map`,
   stored in a `List` or `Map` and read back, then called. The set must survive each step,
   because one type variable is one annotation. Pinned by `launder_*` tests in Task 3 and the
   oracle fixture `capture_laundered.march`.
2. **A closure taken out of data by a pattern**, not a field read: `match c do Client(f) -> f(x)
   end`, a tuple pattern, an `as` pattern, a nested constructor. The binder must carry the
   value's set. Pinned in Task 3.
3. **Recursion**: a higher-order function that passes its parameter to itself, two mutually
   recursive functions in different modules, a local `fn go` that captures a closure. The scheme
   must reach a fixed point and terminate. Pinned in Task 4 with a 2-second timeout assertion.
4. **A construct the pass does not model** (session channels, `receive`, sigils, HTML templates,
   proofs, `dbg`) and **two desugared nodes sharing one span** in `type_map`. The result is
   `Unknown` for that value, never a crash and never a smaller set. Pinned by the sweep (Task 9)
   and by `unknown_*` tests in Task 3.
5. **A closure made inside a `restrict` that calls a closure made outside it**, and a named
   function with a concrete clause used as a value inside a `restrict`. Only the inner body's own
   operations narrow; the outside closure's set arrives whole. Pinned in Task 5 and by the oracle
   fixtures `capture_restrict_mixed.march` and the existing `capture_inside_called_outside`.

---

### Task 1: `Capture_set`, the scope-set algebra

**Files:**
- Create: `lib/caps/capture_set.ml`, `lib/caps/capture_set.mli`, `test/test_capture_set.ml`
- Modify: `test/run_compiler.ml` (register the test group `capture_set`)

**Interfaces:**
- Produces:
  ```ocaml
  type scope = { kind : string; arg : string option }   (* "IO.FileRead", Some "\"./data/\"" *)
  type t                                                  (* normalised: no element covered by another *)
  val empty : t
  val full : t                                            (* IO *)
  val unknown : t                                         (* above every set, full included *)
  val of_scopes : scope list -> t
  val of_entries : March_caps.Scope_expr.entry list -> t  (* a needs clause, a restrict, a grant *)
  val scopes : t -> scope list                            (* sorted *)
  val is_unknown : t -> bool
  val union : t -> t -> t
  val covers : sup:t -> t -> bool
  val narrow : t -> by:t -> t                             (* builder's call 6 *)
  val admits : t -> kind:string -> target:string -> cwd:string -> bool   (* the oracle's question *)
  val to_string : t -> string                             (* "IO.Console, IO.FileRead(\"./data/\")"; "" when empty *)
  ```
- Consumes: `Cap_lattice.cap_subsumes`, `Cap_scope.scope_subsumes` / `within` / `normalize`,
  `Host_scope.parse_decl` / `permits_request` / `authority_of_url`, `Name_scope.parse` /
  `subsumes` / `admits`.

- [ ] **Step 1: Write the failing tests** in `test/test_capture_set.ml`:
  - `union_drops_covered`: `IO.FileRead("./data/")` ∪ `IO.FileRead` prints `IO.FileRead`;
    `IO.Console` ∪ `IO` prints `IO`.
  - `union_keeps_unrelated_scopes`: two hosts of `IO.NetConnect` both print.
  - `covers_*`: `IO` covers everything but `unknown`; `IO.FileSystem` covers
    `IO.FileRead("./x/")`; `IO.FileRead("./data/")` covers `IO.FileRead("./data/in/")` and not
    `IO.FileRead("./other/")`; nothing but `unknown` covers `unknown`.
  - `narrow_*`, one per arm of builder's call 6, plus `narrow_unrelated_is_empty`:
    `IO.Console` narrowed by `IO.FileRead` is empty.
  - `narrow_is_upper_bound` (property, 500 random pairs from a fixed pool of 12 scopes): for
    every probe target admitted by both `e` and `by`, `narrow e ~by` admits it.
  - `admits_*`: path under a scoped read; `..` escaping it refused; a URL against a host scope
    with a path prefix; a name against `IO.Mut("sessions")`; any target against the unscoped kind.
- [ ] **Step 2:** Run `scripts/run-tests.sh -q compiler`; expect the build to fail on the
  missing module.
- [ ] **Step 3:** Implement `Capture_set` to the signature above.
- [ ] **Step 4:** Run `scripts/run-tests.sh -q compiler`; expect the `capture_set` group green.
- [ ] **Step 5:** Commit `lib/caps/capture_set.ml lib/caps/capture_set.mli
  test/test_capture_set.ml test/run_compiler.ml`.

### Task 2: `Capture_ty`, annotated types

**Files:**
- Create: `lib/typecheck/capture_ty.ml`
- Test: `test/test_captures.ml` (new; registered in `test/run_compiler.ml` as group `captures`)

**Interfaces:**
- Consumes: `Capture_set.t`; `Typecheck_types.ty`, `repr`; `env.ctors` (`ctor_info.ci_arg_tys`,
  `ci_params`) and the record-type table for declarations.
- Produces:
  ```ocaml
  type svar = int                                 (* a set variable *)
  type t =
    | Plain of ty                                 (* capture-free: no set anywhere inside *)
    | Arrow of t list * t * svar                  (* params, result, the function value's set *)
    | Con of string * t list * svar option        (* declared or builtin type; None when it holds no arrow *)
    | Tuple of t list
    | Record of (string * t) list
    | Var of int                                  (* an HM type variable, by id *)
    | Opaque                                      (* not modelled: every set inside is Unknown *)
  val fresh_svar : unit -> svar
  val of_ty : env -> ty -> t                      (* fresh variables at every set position *)
  val holds_arrow : env -> string -> bool         (* memoised per declared type; builder's call 11 *)
  val field_types : env -> ctor:string -> t -> t list   (* the declared-type rule, §4.2 *)
  val variance : string -> int -> [ `Co | `Contra | `Inv ]    (* builder's call 9 *)
  val flow : emit:(svar -> svar -> unit) -> src:t -> dst:t -> unit   (* src ⊆ dst, by variance *)
  val svars : t -> svar list
  val pp : names:(svar -> string) -> sets:(svar -> string) -> t -> string
  ```
  `pp` prints `needs` on the nearest arrow and parenthesises a function result that carries a
  set, as §4.1 and §4.3 write it. A set that prints empty prints nothing.

- [ ] **Step 1: Write the failing tests** (`ty_*` in `test/test_captures.ml`), each building a
  `ty` by typechecking a two-line module and reading `type_map`:
  - `ty_plain_fast_path`: `Int`, `List(String)` and a record of ints are `Plain`.
  - `ty_arrow_has_one_svar`; `ty_nested_arrow_two_svars`.
  - `ty_client_shares_set`: for `type Client = Client(fetch : String -> Int)`,
    `field_types ~ctor:"Client"` of a `Con("Client", [], Some s)` gives one `Arrow` whose set is
    `s`. Same for a recursive type and for a field of another arrow-holding declared type.
  - `ty_type_argument_keeps_own_set`: `Option(a)` applied to an arrow keeps the arrow's own
    variable; the `Option` itself has `None`.
  - `ty_flow_variance`: flowing `(A -> B needs s1)` into `(A -> B needs s2)` emits `s1 ⊆ s2`;
    as an argument of an arrow it emits the reverse; under `Vault` it emits both.
  - `ty_pp`: `String -> () needs IO.Console`; `a -> (b -> c needs c1)`;
    `() -> (Client needs IO.NetConnect)`; `List(String -> () needs IO.Console)`.
  - `ty_unresolved_is_opaque`: a `TError`, `TChan` or `TLin` payload gives `Opaque`.
- [ ] **Step 2:** Run `scripts/run-tests.sh -q compiler`; expect failure on the missing module.
- [ ] **Step 3:** Implement `Capture_ty`.
- [ ] **Step 4:** Run again; expect group `captures` green.
- [ ] **Step 5:** Commit the two files and `test/run_compiler.ml`.

### Task 3: Inference inside one function body

**Files:**
- Create: `lib/typecheck/capture_infer.ml`, `lib/typecheck/capture_solve.ml`,
  `lib/typecheck/capture.ml`, `lib/typecheck/capture.mli`
- Modify: `lib/typecheck/typecheck.ml`, `typecheck.mli` (one line each: `module Capture = Capture`)
- Test: `test/test_captures.ml`

**Interfaces:**
- Produces (`capture.mli`):
  ```ocaml
  type site_kind = Lambda | Local_fn of string | Named_value of string
  type reason = { r_elem : string; r_why : string; r_span : Ast.span }
      (* r_why: "calls `File.read`", "captures `sink`", "calls its parameter `f`", "spawns `Logger`" *)
  type site = {
    s_span : Ast.span;           (* the lambda, the local fn's name, or the name used as a value *)
    s_key : Ast.span;            (* the oracle's key: a lambda's or local fn's BODY span, a named value's own span *)
    s_kind : site_kind;
    s_owner : string;            (* enclosing function's key, "" at module level *)
    s_set : string;              (* printed, with c1.. names *)
    s_ground : Capture_set.t;    (* variables replaced by everything they are instantiated with *)
    s_reasons : reason list;
  }
  type result = {
    sites : site list;                              (* in source order *)
    type_at : Ast.span -> string option;            (* annotated type of the expression or binder at this span *)
    fn_types : (string * string) list;              (* function key -> printed capture scheme *)
    unknown_causes : (string * int) list;           (* cause -> how many sites it made Unknown *)
  }
  val analyse : ?unsound:[ `Drop_captured | `Drop_callee_effect ] -> env -> Ast.module_ -> result
  ```
  `?unsound` exists only so the oracle can be shown to go red (Task 8).
- Internal contract that Tasks 4 and 5 fill in: `Capture_infer` asks
  `scheme_of : string -> Capture_solve.scheme option` for a named callee and
  `authority_at : owner:string -> Ast.span -> Capture_set.t` for narrowing. In this task
  `scheme_of` returns `None` for every name (the call is `Unknown`) and `authority_at` returns
  `Capture_set.full`.

The walk, for each expression, yields its annotated type and adds to the *effect* of the
enclosing function value (what running this code can do):

| Expression | Rule |
|---|---|
| `fn ps -> body` | A site. Its set ⊇ the body's own operations (narrowed, Task 5) ∪ the set of every free variable it captures ∪ the body's effect from calling values ∪ the set of every function value the body creates. The lambda's effect does not leak to the enclosing function |
| `f(args)`, `f` a local value | The arrow's set is added to the current effect; arguments flow to parameters, the result type is the arrow's result |
| `f(args)`, `f` a named function | Task 4 |
| own capability operation | Its kind, or the scoped element (builder's call 4), is added to the current effect |
| `let`, block, `if`, `match`, `cond` | Types flow from each branch to the result; binders take the value's type; local `let`s do not generalise (§5) |
| constructor, tuple, record, list literal | Fields flow into the declared type's field types (`Capture_ty.field_types`) |
| pattern, field read | The reverse: binders and the read take the field types |
| local `fn go` | A site, like a lambda; `go` is bound before its body is walked |
| `spawn`, `task_spawn*` | Task 5 |
| anything else | `Opaque`, and one count under its cause in `unknown_causes` |

A missing `type_map` entry, or one whose shape disagrees with the expression (two desugared
nodes on one span), makes that expression `Opaque`.

- [ ] **Step 1: Write the failing tests.** A helper `set_at src needle` returns `s_set` of the
  site whose `s_span` starts where `needle` does; `ty_of src needle` uses `type_at`. Tests:
  - `lam_pure`: `fn x -> x + 1` has set `""`.
  - `lam_own_op_kind`: `fn s -> println(s)` has `IO.Console`.
  - `lam_literal_path`: `fn () -> File.read("./data/a.txt")` has `IO.FileRead("./data/a.txt")`;
    `lam_computed_path`: `fn p -> File.read(p)` has `IO.FileRead` (needs Task 4's schemes; write
    it now, expect `?` until then, and tighten in Task 4).
  - `lam_captures_closure`: `let g = fn s -> println(s)` then `fn x -> g(x)` has `IO.Console`,
    with a reason "captures `g`".
  - `lam_returns_captured_uncalled`: `fn () -> g` also has `IO.Console` (§6.1: captured counts).
  - `lam_creates_closure`: `fn () -> fn s -> println(s)`: both sites have `IO.Console`.
  - `lam_calls_param`: `fn f -> f()` has type `(() -> a needs c1) -> a needs c1`.
  - `local_let_no_generalise`: one local `apply` used with a printing and a pure closure: its
    parameter's set is `IO.Console` at both uses.
  - `data_build_and_read`: `Client(fn c -> println(c))` has type `Client needs IO.Console`;
    `.fetch` on it is `String -> () needs IO.Console`.
  - `data_pattern`: `match c do Client(f) -> f end` gives `f` the same set (Review Focus 2);
    tuple, `as` and nested-constructor variants.
  - `data_list_option`: `[f, g]` is `List(String -> () needs IO.Console, IO.FileRead)`-shaped
    (one element type, the union); `Some(c)` is `Option(Client needs IO.Console)`.
  - `branch_union`: `if b do f else g end` has the union.
  - `local_fn_site`: a block-local `fn go` that prints is a `Local_fn "go"` site with
    `IO.Console`.
  - `unknown_span_collision` and `unknown_unmodelled` (a `receive`-style or sigil expression):
    the site is `?`, `unknown_causes` names the cause, no exception (Review Focus 4).
- [ ] **Step 2:** Run `scripts/run-tests.sh -q compiler`; expect the new tests to fail.
- [ ] **Step 3:** Implement the walk, the constraint store (`s1 ⊆ s2`, `const ⊆ s`) and the least
  solution: each variable is the union of its lower bounds, by worklist over the constraint
  graph. Reasons are recorded per (variable, element) at the constraint that first added it.
- [ ] **Step 4:** Run again; expect green apart from `lam_computed_path`, which stays at `?` and
  is marked in the test with the exact expected value for Task 4.
- [ ] **Step 5:** Commit the four new files, the two `typecheck` lines and the test.

### Task 4: Named functions: schemes, calls, values, recursion, interfaces, builtins

**Files:**
- Modify: `lib/typecheck/capture_infer.ml`, `lib/typecheck/capture_solve.ml`
- Test: `test/test_captures.ml`

**Interfaces:**
- Produces (`capture_solve.ml`):
  ```ocaml
  type scheme = {
    sc_ty : Capture_ty.t;                 (* parameters and result, with interface variables only *)
    sc_effect : svar;                     (* what calling the function can do *)
    sc_bounds : (svar * Capture_set.t) list;   (* const ⊆ v, over interface variables *)
    sc_flows : (svar * svar) list;        (* u ⊆ v, over interface variables, transitively closed *)
  }
  val generalise : store -> Capture_ty.t -> effect:svar -> scheme   (* eliminates internal variables *)
  val instantiate : store -> scheme -> site:Ast.span -> Capture_ty.t * svar   (* fresh copy; records the instantiation for grounding *)
  val ground : store -> svar -> Capture_set.t
  ```
- `scheme_of key` computes on demand from `env.fn_row_bodies`, memoised. A function already
  on the stack is in a recursive group: the group is solved together, monomorphically inside,
  and generalised once.
- A direct call `f(args)` instantiates `f`'s scheme, flows the arguments in, and adds the
  instantiated effect to the current effect. A named function read as a value is a site
  `Named_value f` whose set is the instantiated effect, narrowed by `f`'s concrete clause (§6.1).
- Type variables in a scheme are matched against the call's solved type from `type_map`, so one
  variable gets one annotation at every occurrence (Review Focus 1).
- An interface method call uses the union of its impls' schemes (builder's call 7). A builtin
  uses the default signature or the override table (builder's call 8).

- [ ] **Step 1: Write the failing tests:**
  - `named_direct_call`: `fn p -> File.read(p)` has `IO.FileRead` (the test deferred from Task 3).
  - `named_as_value`: `List.map(paths, File.read)`: the site `File.read` is `Named_value` with
    `IO.FileRead`.
  - `named_clause_narrows_value`: a `fn f() needs IO.Console` that calls a helper reaching
    `IO.Console` and `IO.Clock`, used as a value, has `IO.Console`.
  - `hof_polymorphic`: private `apply(f, x)` used with a printing closure and a pure one: the
    two results differ; `fn_types` shows `apply : (a -> b needs c1, a) -> b needs c1`.
  - `hof_stdlib_map`: `fn_types` for `List.map` is `(List(a), a -> b needs c1) -> List(b) needs c1`.
  - `returns_capturing_value`: `Weather.new` from the design's opening example has scheme
    `() -> (Client needs IO.NetConnect("api.weather.com/v1/"))`, and `let c = Weather.new()`
    has that type; calling it inside a literal `restrict` shows the same type (§6.2).
  - `launder_id`, `launder_pipe`, `launder_option_map`, `launder_list_roundtrip`,
    `launder_map_roundtrip`: the set survives (Review Focus 1).
  - `rec_self_hof`, `rec_mutual_across_modules`, `rec_local_go_captures`: correct sets, and each
    `analyse` call returns within 2 seconds (Review Focus 3).
  - `iface_union`: a generic function calling `show(x)` where one impl prints: a closure calling
    it has `IO.Console`.
  - `builtin_default`: a closure passed to a builtin with a function parameter is charged to
    the caller's effect; `builtin_vault_invariant`: a closure put in a `Vault` and read back has
    the same set, and a wider closure put in the same vault widens both.
  - `toplevel_let_closure`: a module-level `let h = fn s -> println(s)` has `IO.Console`, not
    narrowed by anything (§6.1).
- [ ] **Step 2:** Run `scripts/run-tests.sh -q compiler`; expect the new tests to fail.
- [ ] **Step 3:** Implement schemes, on-demand computation with recursive groups, instantiation
  with type-variable matching, the dispatch-node union, and the builtin default and table.
- [ ] **Step 4:** Run again; expect all `captures` tests green, `lam_computed_path` tightened.
- [ ] **Step 5:** Commit the two modified files and the test.

### Task 5: Static authority, spawns, grants

**Files:**
- Modify: `lib/typecheck/capture_infer.ml`
- Test: `test/test_captures.ml`

**Interfaces:**
- Produces: `authority_at ~owner span`, the meet of (a) the concrete part of `owner`'s clause
  from `env.fn_bound_points`, (b) every literal `restrict` lexically around `span`
  (`Scope_expr.restrict_entries`; a computed one narrows nothing, §13), (c) the owner's package
  grant from `env.grant_module_pkgs` and `Dep_grants`. `Capture_set.full` when there is none.
  At module level it is always `full`.
- A lambda's own operations and direct named calls are passed through
  `Capture_set.narrow ~by:(authority_at ...)` before they enter its set. Nothing else is.
- `spawn(Actor)` adds the actor's reach (the union of its handlers' and `init`'s effects) to the
  spawning function value's effect, narrowed the same way. `task_spawn*` adds the thunk's set.
  A detached spawn is the same rule.

- [ ] **Step 1: Write the failing tests:**
  - `restrict_narrows_created`: the design's §6.2 example: `fn p -> File.read(p)` inside
    `restrict IO.FileRead("./data/")` has `IO.FileRead("./data/")`.
  - `restrict_drops_unrelated`: a lambda that prints, inside `restrict IO.FileRead`, has `""`.
  - `restrict_computed_narrows_nothing`.
  - `restrict_outside_closure_keeps_set`: a closure made outside and called by a closure made
    inside: the inner one's set includes the outer one's whole set (Review Focus 5).
  - `restrict_named_value_inside`: a named function with a concrete clause used as a value
    inside a `restrict` is narrowed by both.
  - `clause_narrows_lambda`: a lambda in `fn f() needs IO.Console` that calls a helper reaching
    `IO.Console` and `IO.Clock` has `IO.Console`.
  - `spawn_actor_charged`, `spawn_task_charged`: the closure that spawns carries the reach.
  - `grant_narrows_package_closure`: with a grants file granting package `P` `IO.Console`, a
    closure in `P` that prints and reads the clock has `IO.Console`; the same source without the
    grants file has both (§14).
  - `mock_narrows_nothing`: added when 7a has landed; until then listed as pending in the task's
    checklist, not as a skipped test.
- [ ] **Step 2:** Run; expect failure.
- [ ] **Step 3:** Implement `authority_at`, narrowing at creation sites, and the spawn rules.
- [ ] **Step 4:** Run; expect green.
- [ ] **Step 5:** Commit.

### Task 6: `march --dump-captures FILE` and the golden corpus

**Files:**
- Modify: `bin/flags.ml`, `bin/main.ml` (flag, implies `--check`; add to the warm check-cache
  skip list at `bin/main.ml:3836`; `MARCH_CAPTURES=1` runs `Capture.analyse` after typecheck and
  discards the result; `[timings] captures` stamp), `lib/typecheck/capture.ml` (`render`)
- Create: `test/run_captures.ml`, `test/captures/*.march` with `.expected`
- Modify: `test/dune`, `scripts/run-tests.sh`, `scripts/affected.sh`, `scripts/test-affected.sh`,
  `.github/workflows/ci.yml` (run `@test/runtest-run_captures` in the `forge` shard, beside
  `run_cap_conformance`)

**Interfaces:**
- Produces: `Capture.render : file:string -> result -> string`. Format, one block per site in
  source order, then the file's named functions, then a summary:
  ```
  12:25  lambda in `load`  needs IO.FileRead("./data/")
           IO.FileRead("./data/")  calls `File.read` with a literal path (12:31)
  30:24  `File.read` as a value in `main`  needs IO.FileRead
  41:5   lambda in `wrap`  needs c1
           c1  calls its parameter `f` (41:16)
  fn Weather.new : () -> (Client needs IO.NetConnect("api.weather.com/v1/"))
  fn wrap : (() -> a needs c1) -> (() -> a needs c1)
  3 function values, 0 not tracked
  ```
  A site with the empty set prints `captures nothing`. `Unknown` prints `needs ?` with its
  cause on the next line.
- Suite `captures`: `test/run_captures.exe` runs `march --dump-captures` on each
  `test/captures/*.march` and compares with `.expected`; `UPDATE_CAPTURES=1` regenerates;
  `CAPTURES_ONLY=prefix,…` limits a run.

- [ ] **Step 1:** Write `test/run_captures.ml` and the first fixture, `lambda_basic.march`, with
  a hand-written `.expected` in the format above. Run `scripts/run-tests.sh captures`; expect
  failure ("unknown option --dump-captures").
- [ ] **Step 2:** Implement the flag, `render`, the env var and the timing stamp.
- [ ] **Step 3:** Run; expect green. Run `march --dump-captures` twice with a warm
  `.march/cas`; expect the same output both times (the skip-list entry).
- [ ] **Step 4:** Add one fixture per case of design §18 "Inference" and "Data" (lambda, named
  value, eta-lambda for partial application, closure capturing a closure, closure creating a
  closure, closure spawning a task and an actor, literal `restrict` narrowed, call inside a
  `restrict` not narrowed, top-level `let`, granted package, `Client` built and read, list of
  closures, `Option` of a client, `Vault` of closures) and the design's opening `Weather`
  example. Generate with `UPDATE_CAPTURES=1`, then read every `.expected` against the design
  before committing.
- [ ] **Step 5:** Run `scripts/test-affected.sh`; expect green. Commit every file by name.

### Task 7: Hover and `march-lsp query`

**Files:**
- Modify: `lsp/lib/analysis_types.ml` (field `captures : Tc.Capture.result Lazy.t`),
  `lsp/lib/analysis.ml` (fill it where `type_map` is filled, `:2607`; `type_at`, `:3866`)
- Test: `lsp/test/test_lsp_analysis.ml`, `lsp/test/test_query_cli.ml`

**Interfaces:**
- `Analysis.type_at` returns the annotated type from `Capture.result.type_at` for the span
  `ty_at` already picks, when that type prints differently from the plain one; otherwise the
  plain `pp_ty` string, byte for byte as today. `march-lsp query hover` and `query type` go
  through `type_at`, so they need no code of their own.
- The lazy value is forced by the first hover on an analysis, never by diagnostics.

- [ ] **Step 1: Write the failing tests:** `hover_closure_shows_set` (hover on `load` in
  `let load = fn p -> File.read(p)` contains `needs IO.FileRead`); `hover_client_value`
  (`Client needs IO.Console`); `hover_pure_unchanged` (hover on `let n = 42` is exactly `Int`);
  `hover_does_not_force_on_diagnostics` (analyse a file, read diagnostics,
  `Lazy.is_val a.captures = false`); `cli_type_json_has_needs` in `test_query_cli.ml`.
- [ ] **Step 2:** Run `scripts/run-tests.sh lsp query_cli`; expect the new tests to fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `scripts/run-tests.sh lsp query_cli jsonrpc incremental`; expect green.
  Any existing hover expectation that changes is listed in the commit message with its old and
  new text.
- [ ] **Step 5:** Commit.

### Task 8: The soundness oracle

**Files:**
- Modify: `lib/eval/eval_prim.ml` (three refs), `lib/eval/eval_builtins.ml` (`cap_check_raw`),
  `lib/eval/eval.ml` (`apply_inner`'s `VClosure` arm, `capture_named_value`, the spawn path)
- Create: `test/run_capture_oracle.ml`, `test/capture_oracle/*.march` (extra fixtures)
- Modify: `test/dune`, `scripts/run-tests.sh`, `scripts/affected.sh`, `scripts/test-affected.sh`,
  `.github/workflows/ci.yml` (same shard as Task 6)

**Interfaces:**
- Produces (`eval_prim.ml`), all `None` by default:
  ```ocaml
  val cap_observer : (string -> string -> unit) option ref          (* kind, target as written *)
  val fn_value_enter : (Ast.span -> unit) option ref                (* key: s_key of the site *)
  val fn_value_leave : (unit -> unit) option ref
  val spawn_inherit : (unit -> (unit -> unit)) option ref           (* snapshot now; the thunk installs it in the spawned actor's handlers *)
  ```
- The driver, per program: parse, desugar, typecheck with the stdlib as the CLI does, run
  `Capture.analyse`, build `site_of_key : (Ast.span, site) Hashtbl.t`, install the hooks, evaluate
  `main` under the fixture's `-- GRANT:` header with `Eval.eval_module_env ~launch`. The hooks
  keep a stack of active site keys (a key not in `site_of_key` is a named function's own body
  and is not pushed). On each observed `(kind, target)`, for every site on the stack:
  `Capture_set.admits site.s_ground ~kind ~target ~cwd`. A miss is a failure that prints the
  site, its set, the operation and the stack.
- Corpus: `test/capture_oracle/*.march`, every `test/cap_conformance/*.march` the interpreter
  mode runs, every `test/captures/*.march` that has a `main`, and the `.march` test modules under
  `test/stdlib/` run through their test entry.
- The run also reports, and the PR quotes: programs run, function-value calls observed,
  operations checked, sites `Unknown`.

- [ ] **Step 1:** Write the driver and the fixtures `capture_laundered.march`,
  `capture_restrict_mixed.march`, `capture_data_field_call.march`, `capture_actor_spawn.march`,
  `capture_task.march`, `capture_iface_impl.march`, each performing real operations on
  `./test/capture_oracle/tmp/` and the console. Run `scripts/run-tests.sh capture_oracle`; expect
  a build failure on the missing hooks.
- [ ] **Step 2:** Add the hooks and their call sites.
- [ ] **Step 3:** Run; expect green, with a non-zero count of operations checked for every
  fixture in `test/capture_oracle/` (a fixture that checks nothing fails the suite).
- [ ] **Step 4: Prove the oracle goes red.** Two cases in the driver run the same corpus with
  `Capture.analyse ~unsound:` `` `Drop_captured `` and `` `Drop_callee_effect `` and assert that the
  oracle reports at least one miss each, naming `capture_laundered` and
  `capture_data_field_call`. Run; expect both red-proof cases to pass. Then temporarily make
  `Capture_set.narrow` return `empty` in its last arm, run, confirm the oracle fails on
  `capture_restrict_mixed`, and revert. Record the three outputs in the progress note.
- [ ] **Step 5:** Run `bench/run_interp_bench.sh --modes interp` on this tree and on the
  merge-base; expect no benchmark outside noise (the hooks are one `ref` read on closure
  application). Record the numbers.
- [ ] **Step 6:** Commit every file by name.

### Task 9: The sweep and the cost

**Files:**
- Modify: `test/run_capture_oracle.ml` (a `sweep` group)
- Create: `scripts/capture-cost.sh`

**Interfaces:**
- `sweep`: `Capture.analyse` over every `stdlib/*.march` (checked as the CLI checks it), every
  `examples/*.march`, `bench/*.march` and `test/native/*.march` that typechecks. It asserts no
  exception and that each file finishes within 10 seconds, and prints the total of
  `unknown_causes` by cause.
- `scripts/capture-cost.sh [FILE…]`: for each file, 11 interleaved `march --check` runs with
  and without `MARCH_CAPTURES=1`, under a private `HOME` with a warm stdlib cache; prints median
  wall time, the ratio and the `[timings] captures` stamp. Defaults: `stdlib/cluster_node.march`
  (the largest stdlib module), every `bench/*.march`, and `examples/lab_app`'s entry file.

- [ ] **Step 1:** Add the sweep; run `scripts/run-tests.sh capture_oracle`. Fix every crash and
  every timeout it finds before going on. Each fix gets a unit test in `test/test_captures.ml`.
- [ ] **Step 2:** Write and run `scripts/capture-cost.sh`. If the forced-on ratio on any default
  is above 1.05, profile, and apply the cheap fixes (the `Plain` fast path, memoised
  `holds_arrow`, skipping functions whose type and body hold no arrow and no operation). Record
  the final table. A ratio still above 1.05 is reported to the owner with the table (Q1).
- [ ] **Step 3:** Commit.

### Task 10: Proof of no change, docs, specs, changelog, review, PR

**Files:**
- Modify: `specs/lang/capabilities.md` (new section "Capture sets (inferred)": what a set is, how
  to read hover and `--dump-captures`, that nothing is checked yet), then run
  `scripts/gen-lang-docs.py` and commit `docs/capabilities.md` with it
- Modify: `CHANGELOG.md` (`### Added` under `[Unreleased]`), `.github/workflows/README.md` (the
  two suites), `.claude/skills/march-debug/SKILL.md` (one line for `--dump-captures`)
- Create: `specs/progress/2026-11-24-ocap-p8a-capture-sets.md`; todos for each item of builder's
  call 15, for the `Unknown` causes the sweep reports, and (if needed) the cost follow-up
- Modify: `specs/todos/2026-11-12-ocap-capture-checking.md` (8a done; 8b and 8c open)

- [ ] **Step 1:** Merge `origin/main`. If 7a has landed, add the `mock` arm and the
  `mock_narrows_nothing` test (Task 5), and re-check the hook placements (Task 8).
- [ ] **Step 2:** Run `scripts/oracle-base.sh all`. Expected: IR, refine and types oracles report
  no change apart from fixtures this branch adds. First prove the types oracle would see a
  change: add a temporary warning emitted from `Capture.analyse` under `MARCH_CAPTURES=1`, run
  the types oracle with that variable set, confirm it goes red, revert.
- [ ] **Step 3:** Run `scripts/affected.sh --run`, then the full `scripts/run-tests.sh`, then
  `scripts/check-docs.sh` and `scripts/check-tree-sitter.sh` (no grammar change: expect green).
- [ ] **Step 4:** Write the docs, changelog, progress and todo files. Commit by name.
- [ ] **Step 5:** Ask for a fresh whole-branch review (superpowers:requesting-code-review) and
  act on it (superpowers:receiving-code-review).
- [ ] **Step 6:** Push and open a **draft** PR. Its body carries: the oracle results; the
  capture-cost table; the soundness oracle's counts and its three red-proof outputs; the sweep's
  `Unknown` counts by cause; the interpreter bench table; the phase 7 overlap status. Bind the PR
  with the ccd_pr tools, wait for CI, and tell the parent session when it is green. Do not
  merge. Log the outcome in deciduous.

## Self-review notes

- **Spec coverage.** §3 → Task 1; §4.1, §4.2 → Tasks 2, 3; §4.3 (clauses with variables), §4.4,
  §5's public rows, §7, §8, §11 → 8b and 8c by §16, with Q2 and Q3 covering what 8a shows
  meanwhile; §6.1 → Tasks 3 to 5; §6.2 → `returns_capturing_value`; §6.3 → Tasks 2 to 4, with
  `deps`/`unknown` deliberately left (Global Constraints); §9 → builder's calls 9 and 10, Tasks 4
  and 5; §10 → Tasks 8 and 10; §12 → Tasks 6 and 7, inlay hints deferred; §13, §14 → Task 5;
  §18 → Tasks 3 to 10, with the "every mode" and golden-diagnostic lines belonging to 8b and 8c
  because 8a has no diagnostic.
- **Proportion.** The design is 719 lines; this plan is shorter.
- **The largest risk** is that `type_map` does not give enough to rebuild instantiations at
  every call (Task 4). The fallback is already in the design of the pass: that call is
  `Unknown`, the sweep counts it, and the PR reports the count. If the count makes the display
  useless on ordinary code, I stop and bring the owner the numbers before going further.
