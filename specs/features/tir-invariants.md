# Post-Lowering TIR Invariants

This is the shape contract for March's Typed IR (`Tir.expr`/`Tir.ty`, defined
in `lib/tir/tir.ml`) as it exists **after** `lib/tir/lower.ml` has run: the
ANF discipline every downstream pass (mono → defun → known_call →
join_points → borrow → perceus → llvm_emit/js_emit) may assume is maintained, the
placeholder types that appear pre-mono, the lambda-creation shape `defun.ml`
pattern-matches on, the complete `br_tag` namespace, the (lack of) source
spans, and the synthetic-name registry: both the collision-proof `$`-family
and the merely-lexable `__`-family. Each section **cites the owning module**
and narrates around it; where a doc comment is quoted, that comment governs.

Cross-references (neither restates the other): `docs/value-representation.md`
(Wave 4 Task 1) covers memory layout / tagging (what a value's bits mean);
`specs/perceus-invariants.md` (Wave 4 Task 2) covers RC ownership (who
increments/decrements, when). This document covers the **shape** of the IR
itself: what node forms may appear where, and what the compiler is and is
not allowed to assume about a name it sees in one.

Audience: anyone adding a new TIR-producing or TIR-consuming pass, or
debugging "the pattern match in my new pass didn't fire" against a shape it
expected to see.

---

## 1. ANF discipline: what may appear where, post-lowering

**Governing module: `lib/tir/lower.ml`**, module doc (lines 1–39) and the
`lower_to_atom_k`/`lower_atoms_k` doc comments (lines 87–131).

`Tir.expr` is A-normal form by construction: `Tir.atom` (`AVar` / `ADefRef` /
`ALit`) is the only thing that may appear in a **call/alloc position**:
`EApp`'s argument list, `ECallPtr`'s argument list, `EAlloc`/`EStackAlloc`'s
argument list, `ETuple`'s element list, `ERecord`'s field-value list, and
`ECase`'s scrutinee. Every non-atomic sub-expression is hoisted into a fresh
`ELet` binding first via the CPS trick the lowering doc states directly:
*"ANF conversion uses continuation-passing: `lower_to_atom_k e k` lowers `e`
and calls `k atom` with the resulting atom. If `e` is not already atomic, a
fresh `ELet` binding wraps the continuation. This ensures all call arguments
are atoms without dangling variable references."* This is not just a
lowering-time convention that later passes may violate: `Defun`, `Perceus`,
and `Llvm_emit` all pattern-match TIR expecting call/alloc positions to hold
atoms only; a pass that introduced a non-atomic sub-expression into one of
these positions would silently break every consumer downstream of it.

**Verified (probe, `--no-opt --dump-tir`).** A call with two non-atomic
arguments (`add(n + 1, n * 2)`, `n` runtime-derived so the constant-folder
cannot eliminate it) lowers to:

```
fn main() : () =
  let n : Int = 10 in
let $t27192 : Int = let $t27190 : Int = +(n, 1) in
let $t27191 : Int = *(n, 2) in
add($t27190, $t27191) in
println$Int($t27192)
```

Both `n + 1` and `n * 2` are hoisted into fresh `ELet` bindings (`$t27190`,
`$t27191`) **before** `add(...)`, with an argument list that contains only atoms
(`AVar` references to those temps). `--compile` + run: exit 0, prints `31`
(`(10+1) + (10*2)`), matching the interpreter. The identical discipline applies
for `EAlloc`: `P(n + 1, n * 2)` for `type Pair = P(Int, Int)` lowers to
`let p : Pair = let $t27190 = +(n,1) in let $t27191 = *(n,2) in alloc
Pair.P($t27190, $t27191) in ...`; the constructor's argument list is atoms
only, identically to the call case. `--compile` + run: exit 0, prints `31`.

**Standing evidence.** `test/snapshots/lower/*.expected` is the permanent
corpus pinning this discipline across many shapes (tuples, records, nested
`ECase`, closures); e.g. `test/snapshots/lower/float_arms.expected` pins
`describe(1.5)` lowering with the literal `1.5` passed directly as an atom in
call position and the call's own result immediately re-atomized into `$t1`
before being passed to `println($t1)`: a call-position atom feeding another
call-position atom, the general shape this section describes. Any snapshot
regeneration that introduced a non-atomic call argument would visibly diff
against this corpus.

**One TIR-level exception, not a violation:** `ECase`'s scrutinee is typed
`Tir.atom` in the AST (`ECase of atom * branch list * expr option`) but its
**branch bodies** (`br_body`) are full `Tir.expr`, an arbitrary expression,
not required to be atomic. ANF governs argument/allocation *positions*, not
every position in the IR; a branch body is a nested computation, exactly
like a `let`-RHS.

---

## 2. `TVar "_"` semantics

**Governing module: `lib/tir/rc_types.ml`** (module doc, `TVar "_"` row of
the truth table) and **`lib/tir/lower_types.ml`** (`unknown_ty`).

`Tir.ty`'s `TVar of string` constructor serves two, sharply different roles
depending on the string it contains:

- **A truly named type variable** (`TVar "_NNNN"` or similar): an
  unresolved user type-var that leaked into monomorphic TIR because a
  concrete type was not propagated across a module boundary (`rc_types.ml`'s
  example: an opaque `Gate.cast` result staying `'_NNNN`). This is a
  **real** (if regrettable) polymorphism failure to be tracked as a heap
  pointer at runtime.
- **`TVar "_"` exactly**: not a type variable at all, but **lowering's own
  placeholder** for "I do not have enough information at this lowering site
  to know the real type." `lower_types.ml` names it directly:
  `let unknown_ty = Tir.TVar "_"`. Producer sites include: `ECase` branch
  variables/closure params where the source annotation could not be resolved
  (`lower.ml:462`), the join-point closure's synthesized fn type
  (`lower.ml:493`, `TFn ([TVar "_"; ...], ...)`), and `ty_of_span` falling
  back when the typechecker's `type_map` has no entry for a span
  (`lower.ml:234`, `:783`).

Despite the shared representation, `TVar "_"` and a truly named `TVar _`
are treated **identically** by every RC-relevant predicate; `rc_types.ml`'s
truth table has `TVar "_"` as its own explicit row (`needs_rc = true`,
`borrow_eligible = true`) exactly because a placeholder is "conservatively
heap-carrying": since lowering could not determine the real type, Perceus and
Borrow must assume the worst (a heap pointer) rather than the best (a
scalar). This is safe because `llvm_emit` guards every RC call with `if ty =
"ptr" then …`, so emitting `EIncRC`/`EDecRC` for a value that turns out to be
a scalar is a no-op, never a crash.

**Where the two roles DO diverge:** `lib/tir/mono.ml` treats `TVar "_"`
specially at several call-mangling and wildcard-substitution sites, and is
explicit that this is NOT the general type-variable case:

- `mono.ml:38`: `is_polymorphic (TVar "_") = false` ("lowering fallback
  placeholder, not a real polymorph"); a real `TVar _` IS polymorphic and
  drives specialization; the placeholder is not, because there is no real
  type parameter to specialize over.
- `mono.ml:152–158`: when resolving a generic call's substitution, `TVar
  "_"` is recognized as `is_wildcard_placeholder` and mapped to a dummy
  binding rather than treated as a concrete instantiation target; this is
  what prevents infinite mangled-name recursion for a call with an argument
  type that could not be determined (`fold_left$List_Int$Int$...` recursing
  endlessly without this guard, per the module's own comment).
- `mono.ml:497–501`: `Map.key_hash(k : TVar "_")` is recognized so the
  generic-hash dispatch does not try to specialize against a fictitious
  `"_"` type name.

`lib/tir/lower_decls.ml:97–101` documents the corresponding **fallback
direction**: when the typechecker's inferred type IS the placeholder
(`Tir.TVar "_"`), `lower_decls.ml` falls back to the AST-level source
annotation instead of trusting the inference result; the placeholder is a
signal to prefer the other source of truth, not a type to propagate as-is.

---

## 3. The `ELetRec([fn], EAtom(AVar fn))` lambda-creation pattern

**Governing modules: `lib/tir/defun.ml`** (`collect_lambdas`, the pattern
match at line 290) and **`lib/tir/lower_match.ml`** (the join-point producer
at line 204); **`lib/tir/tir_names.ml`**'s module doc names this as the
"lambda creation" pattern.

Lowering represents **every** lambda-shaped value (a real user lambda, a
named local recursive function (`ELetFn`), and a hoisted match-fallback join
point) with the identical TIR shape:

```
Tir.ELetRec ([fn], Tir.EAtom (Tir.AVar ref_var))
  when fn.fn_name = ref_var.v_name
```

i.e. a single-function `ELetRec` immediately followed by a bare reference to
that same function's own name as the `ELetRec`'s body. `defun.ml`'s
`collect_lambdas` pattern-matches on exactly this shape (the guard
`fn.fn_name = ref_var.v_name` is what distinguishes "this `ELetRec` exists
purely to name a fresh closure value" from an ordinary multi-function
`ELetRec (fns, body)` group, which recurses without lifting anything). Once
matched, `defun.ml`'s `lift_lambda` builds a brand-new top-level `fn_def`
tagged `Tir.FnApply` from it (`Tir_names.apply_fn_name`), and rewrites the
lambda-creation site to `EAlloc` of a `$Clo_...` closure struct; no
`FnLambda`/`FnJoinPoint`-tagged `fn_def` persists past Defun to reach
Borrow/Perceus/Llvm_emit (`tir.ml`'s `fn_kind` doc states this explicitly).

**Two independent producers, one consumer:**

- **`FnLambda`**: `lower.ml`'s ordinary `ELam`/`ELetFn` lowering path
  produces this shape for every user-written lambda and named local
  recursive function.
- **`FnJoinPoint`**: `lower_match.ml`'s `compile_matrix` hoists a
  non-atomic match fallback into a 0-arg join-point function using the
  *identical* shape (`lower_match.ml:204`:
  `Tir.ELetRec ([jp_fn], Tir.EAtom (Tir.AVar jp_fn_var))`), specifically so
  it goes through the same `defun.ml` lift into `FnApply` rather than a
  bespoke code path. The role differs (deduping a shared match fallback vs.
  representing user code) but the shape and the lift it triggers are
  identical; this is why `Tir.fn_kind` distinguishes `FnLambda` from
  `FnJoinPoint` as separate constructors even though `defun.ml` treats their
  `ELetRec` shape uniformly: the kind records *why* the shape was
  synthesized, not *how* it is consumed.

Both `defun.ml`'s `collect_lambdas` (detecting recursion by re-deriving
`free_vars_of_expr` with the function's own name removed from the top-level
exclusion set) and `lift_lambda` (building the closure struct + apply
wrapper, `Tir_names.clo_struct_name`/`apply_fn_name`) are cited in full by
`docs/value-representation.md` §4 (the closure struct layout / apply ABI),
not worked out again here.

---

## 4. The `br_tag` namespace: the complete table

**Governing module: `lib/tir/lower_match.ml`**'s `pat_tag_and_subs` (the
producer/encoder, lines 97–137) and **`lib/tir/llvm_case.ml`**'s `emit_case`
(the decoder), plus `Tir_names` for the two sub-encodings (`$TupleN`,
capitalized/lowercase bools) it centralizes. `branch.br_tag : string` is an
untyped namespace by design (TIR erases most static type information by the
time codegen dispatches on a tag), so every producer/consumer pair below
must agree on the string's *shape*, not just its value.

| Form | Encoding | Producer | Decoder behavior |
|---|---|---|---|
| Constructor pattern | Full ctor text verbatim, e.g. `"Cons"`, `"Inline.Text"` (qualified patterns keep their qualifier; stripping loses ambiguity-resolution info) | `pat_tag_and_subs` (`PatCon`) | `llvm_case.ml`'s `qualified_br_key`: bare tag qualified by scrutinee's static `TCon` type name; already-qualified tag resolved by matching qualifier segment against the ctor registry |
| Tuple pattern | `"$TupleN"` (leading `$`, decimal arity) | `pat_tag_and_subs` (`PatTuple`) via `Tir_names.tuple_tag` | `llvm_emit.ml` does NOT string-match this prefix (tuple `ECase` branches identified by the scrutinee's static `TTuple` type instead); `js_emit.ml`'s tuple-case detector treats any 6-char `"$Tuple"`-prefixed tag as a tuple case via `Tir_names.is_tuple_tag` (type info may be erased post-Mono for JS output, so the tag is the only signal left there) |
| Int literal | Decimal digits, optional leading `-` | `pat_tag_and_subs` (`PatLit(LitInt)`) | integer `switch` on the literal value |
| Bool literal (explicit `true`/`false` pattern) | Lowercase `"true"`/`"false"` (`string_of_bool`) | `pat_tag_and_subs` (`PatLit(LitBool)`) via `Tir_names.bool_lit_tag` | `llvm_emit.ml`'s boolean-case dispatch tolerates BOTH capitalizations (`"true"`\|`"True"`\|`"false"`\|`"False"`); this decoder is intentionally capitalize-agnostic because two *different* producer families (see below) emit different cases |
| Synthetic bool (if/else, assert, fusion loops) | Capitalized `"True"`/`"False"` | `lower.ml`'s `EIf`/`ECond`/assert-desugaring (3 sites, `Tir_names.synthetic_true_tag`, wildcard default for the false arm) and `fusion.ml`'s generated fold/filter/map loops (2 sites, both `synthetic_true_tag` AND `synthetic_false_tag` explicit, no wildcard default) | same capitalize-tolerant decoder as above |
| String literal | `"\"..\""` (leading `"`, full quoted text) | `pat_tag_and_subs` (`PatLit(LitString)`) | `llvm_case.ml`: `is_string_case` detects the leading `"`; not a `switch` (no total int encoding) but an if/else chain of `march_string_eq` calls |
| Atom literal/pattern | `":name"` (leading `:`) | `pat_tag_and_subs` (`PatLit(LitAtom)` and bare `PatAtom`) | `llvm_case.ml`: `is_atom_case` detects the leading `:`; compiles to a `switch` on the interned FNV-1a `i64` hash (`Llvm_ctx.atom_hash`, `bit63==bit62` law; see `docs/value-representation.md` §6) |
| Float literal | `"#<hex-float>"` (leading `#`, OCaml `"%h"` exact hex encoding) | `pat_tag_and_subs` (`PatLit(LitFloat)`), **W2 addition** | `llvm_case.ml`: `is_float_case` detects the leading `#`; not a `switch` (no total, exact int encoding of an arbitrary double) but an if/else `fcmp oeq double` chain, decoding the hex string back via `float_of_string` + `Int64.bits_of_float` into the exact LLVM hex-double literal |

**Why the leading-character sigils never collide:** ctor names start
uppercase or are qualified (`Foo`/`Mod.Foo`), tuples start `$`, ints start a
digit or `-`, bools are the bare words `true`/`false`/`True`/`False`, strings
start `"`, atoms start `:`, floats start `#`; `pat_tag_and_subs`'s own
comment states this design explicitly for the float case ("the leading `#`
does not collide with any other tag form"), and it applies transitively for
every other pair by the same leading-character argument.

**Verified (float row, both IR and behavior).** `match x do 0.0 -> "zero" |
1.5 -> "one-half-more" | _ -> "other" end` for a runtime-derived `x = 1.5`:
`--emit-llvm` shows

```llvm
%fcmp5 = fcmp oeq double 0x3FF8000000000000, 0x0000000000000000
%fcmp6 = fcmp oeq double 0x3FF8000000000000, 0x3FF8000000000000
```

That is, the scrutinee (`0x3FF8000000000000` = 1.5's exact IEEE-754 bit
pattern) compared in turn against `0.0`'s hex-double (`0x0`) and `1.5`'s
(`0x3FF8000000000000`), matching `pat_tag_and_subs`'s `#0x1.8p+0` encoding
decoded back to the identical bit pattern. `--compile` + run: exit 0, prints
`one-half-more`. This is also the exact shape pinned by the standing
snapshot `test/snapshots/lower/float_arms.expected`
(`test/snapshots/src/float_arms.march`), which shows the pre-codegen TIR
form directly: `case x of #0x0p+0() -> "zero" | #0x1.8p+0() -> "one-half-more"
| _ -> "other"`.

---

## 5. TIR has no spans

**Governing citation:** `lib/tir/tir.ml:1–74` (the entire `ty`/`var`/
`def_id`/`atom`/`expr`/`branch` type definitions) and
`specs/analysis/2026-07-01-pipeline-deep-review.md`'s finding ("And TIR
carries **no spans at all** (tir.ml:40–74); every downstream diagnostic is
location-free").

Every AST node (`March_ast.Ast.expr`, etc.) includes a `span` for
diagnostics. Lowering discards it: none of `Tir.atom`, `Tir.expr`,
`Tir.var`, `Tir.branch`, or `Tir.fn_def` (`tir.ml:1–120`, verified against
this worktree's HEAD) has a span field or any positional-provenance payload
at all. This is **the accepted design**, not an oversight to fix (the
deep-review finding lists it as a structural fact, not a bug), and its
consequence is stated clearly: **every diagnostic emitted by a TIR-consuming
pass (mono, defun, borrow, perceus, llvm_emit) is necessarily
location-free.** A monomorphization-limit error, a borrow-inference failure,
an LLVM emission `failwith`, or a "record patterns are not yet compilable"
error (`lower_match.ml`'s `PatRecord` case, which does thread a *pre-TIR*
`Ast.span` through its own error message exactly because it fires during
lowering, before the span is dropped); anything raised **after** lowering
has completed cannot report a source line/column, only whatever a producer
pass chose to embed as plain text (a name, a type, a synthesized identifier).

This is why several `lib/tir/*.ml` error paths go out of their way to
embed human-legible names/types directly into the exception message instead
of a span (e.g. `mono.ml`'s "Monomorphization limit reached" message
embeds the offending function's mangled name); it is the only
provenance information still available at that point in the pipeline.

---

## 6. Synthetic-name registry

**Governing module: `lib/tir/tir_names.ml`** (module doc, quoted in full
where relevant) for the collision-proof family; `lib/desugar/desugar.ml`,
`lib/parser/parser.mly`, `lib/typecheck/typecheck.ml`, `lib/eval/eval.ml`,
and `lib/tir/lower_tests.ml` for the lexable family's individual producers.

### 6.1 The `$`-family (collision-proof)

Every synthetic name `tir_names.ml` mints uses `'$'`, which the lexer has no
token for: **no user identifier can collide with a synthetic one**,
by construction, not by convention. This covers: `$TupleN` (tuple branch
tags), `$fvN` (closure free-variable field names), `$Clo_<fn>$<uid>`
(closure struct type names), `<fn>$apply$<uid>` (closure apply wrappers),
`$clo` (the apply wrapper's fixed closure-param name), `Iface$Ty.method`
(interface-impl mangling), `base$mangled_ty` (monomorphization specialization
suffixes), `base$N` (default-arg arity mangling), and the actor field-sort
prefixes `$d_dispatch`/`$e_alive`/`$f_state` (§6.3 below). `tir_names.ml`'s
module doc is the single point of definition for all of these; this section
does not re-derive any of them; see the module doc's own catalogue
(quoted in `docs/value-representation.md` §4 for the apply-ABI piece, and in
`specs/perceus-invariants.md` §3 for the closure-FV piece) for the full list
with byte-identical-consumer verdicts per name.

### 6.2 The `__`-family (lexable, capturable in principle)

Unlike the `$`-family, every name below uses only ASCII letters/digits/`_`
(ordinary March identifier syntax), so a user program CAN declare or
reference an identically-spelled binding. `tir_names.ml`'s module doc names
this explicitly as the sole exception to the collision-proof design,
bringing the risk forward from the front-end review
(`specs/analysis/2026-07-01-pipeline-deep-review.md` §6's "Synthetic
names user-capturable" finding) as accepted, out-of-scope-for-Wave-3 risk.

| Name(s) | Producer | Consumer(s) | Capturable? |
|---|---|---|---|
| `__arg0`…`__argN` | `lib/desugar/desugar.ml`'s `fresh_arg_name`/`desugar_fn_def` general path (multi-clause fn desugaring: synthesizes one param per position of the first clause's arity, then matches on the tuple/single arg) | The synthesized param is read like any ordinary function parameter by every later pass: no special-cased consumer; it IS the parameter | **Yes, verified below** |
| `__celem` | `lib/parser/parser.mly`'s `mk_comp_lambda` (list-comprehension desugaring: names the lambda's implicit parameter when the comprehension pattern is not a bare `PatVar`) | Same as above: read as an ordinary lambda parameter inside the synthesized `EMatch (EVar arg, ...)` body | Yes, in principle (not re-probed this task; same mechanism as `__arg0`) |
| `__app_init__` | `lib/desugar/desugar.ml`'s `DApp` desugaring (an `app` block becomes a private `fn __app_init__()` returning `{spec, on_start, on_stop}`) | `lib/eval/eval.ml:8692` (`List.assoc_opt "__app_init__" env`, locating the app-init record at program-start time); `lib/typecheck/typecheck.ml:7025` and `eval.ml:8313` both assert "DApp is desugared to DFn(__app_init__) before typecheck/eval; reaching here is a bug" (defense against the desugar step being skipped) | Yes: an ordinary top-level `fn __app_init__` is user-definable and would collide |
| `__try_call` / `__try_call_val` | NOT TIR-synthesized; registered directly as compiler builtins in `typecheck.ml` (arity-1 polymorphic fns) and `eval.ml` (`VBuiltin`); user code calls them explicitly, e.g. `__try_call(fn _ -> ...)` | `lib/tir/borrow.ml`'s `is_try` (via `Tir_names.is_try_call`): recognizes the thunk argument as consumed-and-freed locally, not an escape (see `specs/perceus-invariants.md` §3, rule 2) | Lexable as an ordinary name, but calling a user-defined `__try_call` would simply invoke the builtin (name resolution finds the registered builtin like any other top-level name); not examined this task |
| `__march_test_N__` | `lib/tir/lower_tests.ml`'s `lower_test_body` via `Tir_names.test_fn_name` (N = a per-module counter): one synthesized zero-arg fn per `test "..." do ... end` block | Not name-sniffed downstream: the `(fn_name, display_name)` pair is stored as a structural field in `Tir.tir_module.tm_tests`, consulted by `--test`'s driver-wiring in `lib/tir/llvm_toplevel.ml` and rooted for DCE in `lib/tir/dce.ml` by comparing against the exact registered name, not a pattern match rebuilt from the string shape | Yes in principle (double underscore + digits + double underscore is ordinary March syntax), but collision would require guessing the exact per-module counter value |
| `__march_setup__` / `__march_setup_all__` | `lib/tir/lower_tests.ml` (fixed names, "last decl wins": a module's own `setup`/`setup_all` block, if declared more than once, has only its last occurrence's lowering survive) | `lib/tir/dce.ml:100` (exact-name comparison, keeps these fns alive across DCE regardless of reachability) and `lib/tir/llvm_toplevel.ml:810,812,843,845` (exact-name lookup + `mangle_extern`, wiring the test-harness entry points) | Yes: an ordinary top-level `fn __march_setup__` collides directly (fixed name, no counter to guess) |

**Verified capturability (front-end review's method, re-run at HEAD
`e5343e84`; current truth, unchanged since Wave 1).** A truly
multi-clause function forces `desugar_fn_def`'s general path, which names
its own synthesized scrutinee parameter `__arg0`. A body arm with a
pattern that binds no variable under that name (a bare literal pattern) can still
reference `__arg0` directly and observe the real argument value; i.e. the
name is not just lexable, it resolves to the compiler's own synthesized
binding without the user declaring it:

```march
mod ArgCapture do
  fn classify(0) do
    __arg0 + 1000     -- __arg0 was never bound by THIS arm's pattern (`0`);
  end                 -- it resolves to desugar's synthesized parameter.
  fn classify(n) do
    n + 1
  end

  fn main() do
    println(classify(0))
    println(classify(41))
  end
end
```

Interpreter: exit 0, prints `1000` then `42`. `--compile` + run: exit 0,
identical output `1000` / `42`: compiled and interpreted agree, and the
`0`-arm's body clearly observed the live argument value through the
uncontrolled name `__arg0`, confirming the capturability finding is still
exactly true at this HEAD, not just historically at Wave 1.

### 6.3 Actor field-sort prefixes: `$d_`/`$e_`/`$f_` (the runtime mirror)

**Governing module: `lib/tir/tir_names.ml`** (`actor_dispatch_field`,
`actor_alive_field`, `actor_state_field`) and **`lib/tir/lower_actor.ml`**
(the producer, `lower_actor`'s doc comment and field-construction code).

These three names are technically part of the `$`-family (collision-proof
by the same unlexable-`$` argument as §6.1) but get their own callout because
they are the one synthetic-name contract with a **C-runtime consumer**, not
just an OCaml one. `lower_actor` builds the actor struct's field list as
`[actor_dispatch_field, actor_alive_field] @ state_fields_sorted` (or, in
hot-reload mode, `[actor_dispatch_field, actor_alive_field,
actor_state_field]`) — the three synthetic fields are prefixed `$d_`/`$e_`/
`$f_` **specifically so that an alphabetical sort** (which
`llvm_emit.ml`'s field-layout code applies uniformly to every record/struct
type) recreates this exact order, because `$d < $e < $f <` any legal user
field name (user fields cannot start with `$`, unlexable). `lower_actor.ml`
states the payoff directly: this alphabetical-sort trick is what keeps the
struct's in-memory field order aligned with **the C runtime's hardcoded word
indices**: `runtime/march_runtime.c`'s `actor_green_thread` reads the
dispatch closure pointer at `a[2]` and the alive flag at `a[3]` (and, in
hot-reload mode, the state-record pointer at `a[4]`) as raw `int64_t*`
offsets, with no field-name lookup at all on the runtime side.

This task added a cross-reference comment at the C site
(`runtime/march_runtime.c`, the "Actor struct layout" doc block immediately
above `actor_green_thread`, lines 1078–1091) pointing back at
`tir_names.ml`'s field-sort contract, a comment-only change (verified: `git
diff` on `runtime/march_runtime.c` touches only comment lines) so that a
future reader of either side finds the other. The contract itself is
unchanged; the two sides were already correct and already coupled; this
closes the "documented only from the TIR side" gap the deep-review program
flagged for the actor layout specifically.

---

## 7. Lessons from fixed compiler bugs (postmortem digest)

Each entry below is the compressed root cause of a real, now-fixed bug, kept
here so the same bug class doesn't get re-discovered from scratch. Full
investigation history for each lived in a dated `specs/` postmortem, now
archived (`specs/archive/`); this digest is the durable takeaway.

**Option repr must agree across module boundaries.** A generic function
with a return type that includes `Option('a)` determines its `Boxed`-vs-`Niche`
representation from the type-argument concreteness visible *in its own
compilation unit*. `lib/tir/mono.ml`'s `refine_field_types` (added to close
an earlier intra-unit gap: a projected record field with a polymorphic
type var was retyped to the field's concrete type so the callee specialized
consistently) only operates within a single monomorphized unit. When the
generic function is instead defined in a **separately-compiled** dependency
(a stdlib module, a `MARCH_LIB_PATH` package), its `Option` can be emitted
`Boxed` there while a concrete caller in a different unit reads the same
value `Niche`: the box pointer gets dereferenced as if it were the unwrapped
payload. Symptom is a near-zero/corrupt pointer SIGSEGV at the first use of
the "unwrapped" value, several calls away from the actual mismatch. Any
representation decision that depends on type concreteness must either be
forced deterministic independent of instantiation, or the concrete type must
be propagated across the compilation-unit boundary, not just within one.

**TCO loop bodies must not grow the stack per iteration.** A self-tail-call
compiled as a back-edge loop (`entry → br loop; loop: ...; br loop`)
correctly eliminates call-frame growth, but ordinary `alloca`s emitted by the
loop *body* (case-branch bindings, tuple construction, closure environments)
are not automatically hoisted out of the loop; LLVM's `alloca` allocates
fresh stack space on every dynamic execution, and that space is normally only
reclaimed at `ret`, never at a loop back-edge. The fix is `llvm.stacksave()`
once at the loop header and `llvm.stackrestore()` immediately before every
back-edge. Separately, Perceus's TCO-detection only matched the
`ELet(tmp, EApp(self,args), body)` shape; a self-call immediately followed by
a trivial dec-chain with no `ELet` wrapper (`ESeq(EApp(self,args), decs)`,
arising when a matched constructor wildcards a field so Perceus has no
variable to bind) fell through to an ordinary non-tail call, silently losing TCO and
the stack-bound guarantee for that shape. Any change to tail-call detection
must check both the `ELet`-wrapped and the bare-`ESeq`-with-dec-chain shapes.

**A field projected from a row-polymorphic value must have its concrete type
propagated to its uses, not just to the containing binding.** A generic
helper like `get_req_header(conn, name) = lookup(conn.hdrs, name)` types
`conn` as a bare row-polymorphic var, so `conn.hdrs` gets a fresh, unrelated
type var; monomorphizing the call site makes `conn`'s type concrete but
leaves that projection's type var (and everything downstream of it, like
`lookup`'s value type) unresolved. An abstract `Option('V)` is then emitted
`Boxed` while a concrete caller elsewhere reads the same value `Niche`,
dereferencing the `Some`-box pointer as if it were the unwrapped payload:
SIGSEGV several calls away from the actual mismatch. Fixed in `lib/tir/mono.ml`
by `refine_field_types`, run after `subst_fn_def` and before `rewrite_calls`:
for every `let v = a.fld` where `a` resolves to a concrete record, retype `v`
to the field's concrete type and propagate it to `v`'s uses; `match_ty` also
needed a `TRecord` case (previously only `TTuple`/`TCon`/`TFn` bound a type
var visible through the parameter) so a record-typed parameter with a
type var in a field binds it too. (The investigation initially suspected a
Perceus RC under-count from the `--` string-concat symptom; the actual
mismatch was two calls upstream, in what `boundary`'s argument actually
pointed at; worth remembering that a symptom in one pass's output doesn't
localize the bug to that pass.) This intra-unit fix is the precursor to the
cross-module case above: the same representation-must-be-deterministic-or-
propagated principle, but scoped to a single compilation unit.
