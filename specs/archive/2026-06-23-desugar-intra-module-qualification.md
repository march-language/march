# Desugar: intra-module bare-name qualification

**Status:** Spec — ready to implement  
**File to change:** `lib/desugar/desugar.ml`  
**Companion:** `lib/tir/lower.ml` `rename_tir_vars` (existing equivalent in compiled path)

---

## Problem

After the desugar pass, a bare function call inside a module body is still an
unqualified `EVar "connect"`:

```march
mod Socket do
  fn connect(host, port) = ...
  fn with_connection(host, port, f) do
    match connect(host, port) do   -- EVar "connect" after desugar
      ...
    end
  end
end
```

Three downstream passes each independently compensate:

| Pass | Mechanism |
|---|---|
| Eval | `eval_stdlib_decls` seeds `inner_ref` from `base_env`; stdlib closures never see user functions |
| Typecheck | `check_decl`'s `DMod` handler builds `pre_env` that shadows outer `connect` with the module-local one |
| TIR/LLVM | `rename_tir_vars` rewrites bare intra-module names to qualified ones |

All three protections are correct today. The problem is that they are **implicit and independent**. The AST is ambiguous: `EVar "connect"` inside `mod Socket` means "Socket-local", but the representation is identical to "user-defined global `connect`". A future refactor that touches any one of these three paths can silently re-expose the footgun. The fix is to resolve the ambiguity at the earliest stage.

---

## Solution

Add a `qualify_module_refs` post-pass to `desugar_module`. After the existing desugar step, walk the desugared declaration list and rewrite bare `EVar "name"` inside module bodies to `EVar "Mod.name"` whenever `name` is a function or value directly declared in that module.

This makes the AST self-documenting and removes the burden from the three downstream passes. They can keep their protections as defense-in-depth, but they no longer need to be the primary line of defense.

---

## Design

### New pass: `qualify_module_refs`

Entry point added to `desugar_module`, called after the existing desugar step:

```
desugar_module:
  ...
  let decls = List.map (fun d -> inject_defaults interfaces (desugar_decl d)) expanded in
  let decls = qualify_module_refs decls in   (* NEW *)
  { m with mod_decls = decls }
```

`qualify_module_refs` is a pure transformation over `decl list` that handles nesting
by accumulating a prefix:

```
qualify_module_refs decls
  = qualify_decls_at "" decls

qualify_decls_at prefix decls:
  for each decl:
    DMod(name, vis, inner, sp):
      new_prefix = prefix ^ name.txt ^ "."
      own_names  = collect_direct_names inner
      inner'     = qualify_decls_at new_prefix inner      (* recurse for nesting *)
      inner''    = qualify_in_decls new_prefix own_names inner'  (* qualify bodies *)
      → DMod(name, vis, inner'', sp)
    other decl → unchanged (top-level decls have no module prefix to apply)
```

Two sub-steps for each `DMod`:

1. **Recurse first** (`qualify_decls_at new_prefix inner`) — handles nested modules
   like `mod Foo do mod Bar do ... end end`, so `Bar`'s own functions get prefix
   `"Foo.Bar."` before `Foo`'s qualification step runs.

2. **Qualify bodies** (`qualify_in_decls new_prefix own_names inner'`) — rewrites
   bare names in `DFn` bodies and `DLet`/`DActor` expressions at the current level.
   Does **not** descend into nested `DMod` nodes (they were already handled in step 1).

---

### Helper: `collect_direct_names`

Collects the short (unqualified) names of everything declared directly in a decl
list. Does **not** recurse into nested `DMod`.

```ocaml
let collect_direct_names (decls : decl list) : string list =
  List.concat_map (function
    | DFn (def, _) -> [def.fn_name.txt]
    | DLet (_, b, _) ->
      let rec from_pat = function
        | PatVar n -> [n.txt]
        | PatTuple (ps, _) -> List.concat_map from_pat ps
        | PatCon (_, ps)   -> List.concat_map from_pat ps
        | _                -> []
      in
      from_pat b.bind_pat
    | _ -> []
  ) decls
```

---

### Core function: `qualify_expr`

A scope-aware expression walker. Takes:

- `prefix : string` — e.g. `"Socket."`
- `own_names : string list` — bare names declared in the current module
- `bound : StringSet.t` — names currently shadowed by local binders
- `e : expr` — expression to transform

Returns the qualified expression.

**Rewrite rule for `EVar`:**

```
EVar n  →  EVar { n with txt = prefix ^ n.txt }
    when:
      n.txt ∈ own_names           (* is a module-local name *)
      && n.txt ∉ bound            (* not shadowed by a local binder *)
      && not (String.contains n.txt '.')  (* not already qualified *)
```

The third condition guards against double-qualification. It is not strictly
needed if `own_names` only contains short (unqualified) names, but makes the
invariant explicit.

**Binder tracking — which AST nodes introduce new local names:**

| Node | Names introduced | Scope |
|---|---|---|
| `ELam (ps, body, sp)` | param names from `ps` | `body` |
| `ELet (b, sp)` | `pat_vars b.bind_pat` | subsequent block exprs only |
| `ELetFn (name, params, _, body, sp)` | `name.txt` | subsequent block exprs; `params` bind inside `body` |
| `ELetQ (pat, result, cont, sp)` | `pat_vars pat` | `cont` only (not `result`) |
| `EMatch (_, branches, _)` | `pat_vars branch.branch_pat` | `branch_body` and `branch_guard` |

**`EBlock` is the critical case.** Each `ELet`/`ELetFn` in a block extends the
bound set for all subsequent expressions, not just for the binding's RHS.
Traversal must be left-to-right with accumulated bound:

```ocaml
let rec qualify_block prefix own_names bound = function
  | [] -> []
  | ELet (b, sp) :: rest ->
    let b' = { b with bind_expr = qualify_expr prefix own_names bound b.bind_expr } in
    let bound' = add_pat_vars bound b.bind_pat in
    ELet (b', sp) :: qualify_block prefix own_names bound' rest
  | ELetFn (nm, ps, ret, body, sp) :: rest ->
    let body_bound = List.fold_left
        (fun acc p -> StringSet.add p.param_name.txt acc) bound ps in
    let body' = qualify_expr prefix own_names body_bound body in
    let bound' = StringSet.add nm.txt bound in
    ELetFn (nm, ps, ret, body', sp) :: qualify_block prefix own_names bound' rest
  | ELetQ (pat, result, cont, sp) :: rest ->
    let result' = qualify_expr prefix own_names bound result in
    let bound_cont = add_pat_vars bound pat in
    let cont' = qualify_expr prefix own_names bound_cont cont in
    ELetQ (pat, result', cont', sp) :: qualify_block prefix own_names bound rest
    (* ELetQ is a 3-part node: the *rest* list does NOT see pat's bindings —
       cont is the explicit continuation, not the next sibling. *)
  | e :: rest ->
    qualify_expr prefix own_names bound e :: qualify_block prefix own_names bound rest
```

**Helper: `add_pat_vars`**

```ocaml
let rec add_pat_vars bound = function
  | PatVar n        -> StringSet.add n.txt bound
  | PatTuple (ps,_) -> List.fold_left add_pat_vars bound ps
  | PatCon (_,ps)   -> List.fold_left add_pat_vars bound ps
  | PatRecord (fs,_)-> List.fold_left (fun b (_,p) -> add_pat_vars b p) bound fs
  | _               -> bound
```

**Full `qualify_expr` cases:**

```ocaml
let rec qualify_expr prefix own_names bound e =
  let qe = qualify_expr prefix own_names in       (* short alias, no bound change *)
  let qe_b b = qualify_expr prefix own_names b in (* with explicit bound *)
  match e with
  | EVar n when List.mem n.txt own_names
             && not (StringSet.mem n.txt bound)
             && not (String.contains n.txt '.') ->
    EVar { n with txt = prefix ^ n.txt }

  | ELam (ps, body, sp) ->
    let bound' = List.fold_left
        (fun b p -> StringSet.add p.param_name.txt b) bound ps in
    ELam (ps, qe_b bound' body, sp)

  | EBlock (es, sp) ->
    EBlock (qualify_block prefix own_names bound es, sp)

  | ELet (b, sp) ->
    (* Stand-alone ELet (outside EBlock): the RHS does NOT see the binding.
       The binding itself is visible in whatever enclosing EBlock follows. *)
    ELet ({ b with bind_expr = qe_b bound b.bind_expr }, sp)

  | ELetFn (nm, ps, ret, body, sp) ->
    let bound' = List.fold_left
        (fun b p -> StringSet.add p.param_name.txt b) bound ps in
    ELetFn (nm, ps, ret, qe_b bound' body, sp)

  | ELetQ (pat, result, cont, sp) ->
    let cont_bound = add_pat_vars bound pat in
    ELetQ (pat, qe_b bound result, qe_b cont_bound cont, sp)

  | EMatch (scrut, branches, sp) ->
    let branches' = List.map (fun br ->
      let bound' = add_pat_vars bound br.branch_pat in
      { br with branch_body  = qe_b bound' br.branch_body
              ; branch_guard = Option.map (qe_b bound') br.branch_guard }
    ) branches in
    EMatch (qe_b bound scrut, branches', sp)

  (* Standard recursive descent for all other nodes: *)
  | EApp (f, args, sp)     -> EApp (qe_b bound f, List.map (qe_b bound) args, sp)
  | ECon (n, args, sp)     -> ECon (n, List.map (qe_b bound) args, sp)
  | ETuple (es, sp)        -> ETuple (List.map (qe_b bound) es, sp)
  | ERecord (fs, sp)       -> ERecord (List.map (fun (n,ex) -> (n, qe_b bound ex)) fs, sp)
  | ERecordUpdate (b,fs,sp)-> ERecordUpdate (qe_b bound b,
                                List.map (fun (n,ex) -> (n, qe_b bound ex)) fs, sp)
  | EField (ex, n, sp)     -> EField (qe_b bound ex, n, sp)
  | EIf (c,t,f,sp)         -> EIf (qe_b bound c, qe_b bound t, qe_b bound f, sp)
  | ECond (arms, sp)        -> ECond (List.map (fun (c,b) ->
                                (qe_b bound c, qe_b bound b)) arms, sp)
  | EPipe (l, r, sp)       -> EPipe (qe_b bound l, qe_b bound r, sp)
  | EAnnot (ex, ty, sp)    -> EAnnot (qe_b bound ex, ty, sp)
  | EDbg (Some ex, sp)     -> EDbg (Some (qe_b bound ex), sp)
  | ESend (cap, msg, sp)   -> ESend (qe_b bound cap, qe_b bound msg, sp)
  | ESpawn (ex, sp)        -> ESpawn (qe_b bound ex, sp)
  | EAssert (ex, sp)       -> EAssert (qe_b bound ex, sp)
  | EAtom (a, args, sp)    -> EAtom (a, List.map (qe_b bound) args, sp)
  | ESigil (s, args, sp)   -> ESigil (s, List.map (qe_b bound) args, sp)
  (* Leaf nodes that cannot contain EVar: *)
  | ELit _ | EVar _ | EHole _ | EResultRef _ | EDbg (None,_) -> e
```

---

### Helper: `qualify_in_decls`

Applies `qualify_expr` to the body of each `DFn` and expression-bearing decl
at the **current** module level. Does **not** recurse into `DMod` — nested modules
were already handled by `qualify_decls_at`'s recursive call.

```ocaml
let qualify_in_decls prefix own_names decls =
  List.map (function
    | DFn (def, sp) ->
      let def' = { def with fn_clauses = List.map (fun c ->
        let bound = List.fold_left (fun b p ->
            StringSet.add p.param_name.txt b) StringSet.empty
            (fn_params_of_clause c) in
        { c with fc_body  = qualify_expr prefix own_names bound c.fc_body
               ; fc_guard = Option.map
                    (qualify_expr prefix own_names bound) c.fc_guard }
      ) def.fn_clauses } in
      DFn (def', sp)
    | DLet (vis, b, sp) ->
      DLet (vis, { b with bind_expr =
          qualify_expr prefix own_names StringSet.empty b.bind_expr }, sp)
    | DActor (vis, name, actor, sp) ->
      let qa e = qualify_expr prefix own_names StringSet.empty e in
      let actor' = { actor with
        actor_init     = qa actor.actor_init
      ; actor_handlers = List.map (fun h ->
            { h with ah_body = qa h.ah_body }) actor.actor_handlers
      } in
      DActor (vis, name, actor', sp)
    | DMod _ as d -> d   (* handled by recursive qualify_decls_at call *)
    | other -> other
  ) decls
```

Where `fn_params_of_clause` extracts `FPNamed` and `FPPat(PatVar)` param names
from a `fn_clause` (same logic already in `eval.ml::clause_params`).

---

### Where in `desugar_module` to call it

```ocaml
let desugar_module ?(errors = Err.create ()) (m : module_) : module_ =
  ...
  let decls = List.map (fun d ->
      inject_defaults interfaces (desugar_decl d)
    ) expanded in
  let decls = qualify_module_refs decls in   (* NEW — run after desugar *)
  { m with mod_decls = decls }
```

`qualify_module_refs` is the entry point:

```ocaml
let qualify_module_refs (decls : decl list) : decl list =
  let rec qualify_decls_at prefix decls =
    List.map (function
      | DMod (name, vis, inner, sp) ->
        let new_prefix = prefix ^ name.txt ^ "." in
        let own_names  = collect_direct_names inner in
        let inner'  = qualify_decls_at new_prefix inner in     (* recurse *)
        let inner'' = qualify_in_decls new_prefix own_names inner' in  (* qualify *)
        DMod (name, vis, inner'', sp)
      | other -> other   (* top-level decls have no module context *)
    ) decls
  in
  qualify_decls_at "" decls
```

---

## What changes in downstream passes

After this fix, `EVar "connect"` in `Socket.with_connection`'s body becomes
`EVar "Socket.connect"` before typecheck, eval, or TIR ever see it.

The three existing protections (eval `base_env` isolation, typecheck `pre_env`
shadowing, TIR `rename_tir_vars`) remain in place as defense-in-depth. They
are still useful because:

- **Eval** `base_env`: still needed to prevent user code from polluting stdlib
  evaluation state for OTHER reasons (not just name shadowing).
- **Typecheck** `pre_env`: still correctly scopes `local_fns` and `fn_arities`
  for other uses.
- **TIR** `rename_tir_vars`: still needed for `DUse` import aliasing and for
  `DLet` module-level values (which are zero-arg functions in TIR and whose
  bare names need renaming to the global TIR function name).

So `rename_tir_vars` should still run, but after this fix it becomes a no-op for
the intra-module-function case (all those names are already qualified).

---

## Corner cases

### Already-qualified names
`EVar "Socket.connect"` contains a `.` — the `not (String.contains n.txt '.')`
guard in `qualify_expr` leaves it untouched. No double-qualification.

### Parameters shadowing module names
```march
mod Foo do
  fn connect(x) = x        -- own_names includes "connect"
  fn dial(connect) =        -- param named "connect"
    connect("host", 80)     -- should NOT be rewritten
end
```
The param `connect` is in `bound` when qualifying `dial`'s body. The guard
`not (StringSet.mem n.txt bound)` leaves it as-is. ✓

### Let-bindings shadowing module names
```march
mod Foo do
  fn connect(x) = x
  fn test() =
    let connect = fn x -> x  -- local binding
    connect("a")             -- refers to local, NOT Foo.connect
end
```
`connect` from the `ELet` is added to `bound` before qualifying the subsequent
block expressions. ✓

### Nested modules
```march
mod Outer do
  fn helper() = "outer"
  mod Inner do
    fn helper() = "inner"
    fn work() = helper()    -- should become Inner.helper, not Outer.helper
  end
  fn top() = helper()       -- should become Outer.helper
end
```
`qualify_decls_at` recurses into `mod Inner` FIRST with prefix `"Outer.Inner."`.
It collects `own_names = ["helper", "work"]` for Inner and qualifies `work`'s
`helper()` call to `"Outer.Inner.helper"`. Then the outer `qualify_in_decls`
runs on Outer's decls with `own_names = ["helper", "Inner"]` and prefix
`"Outer."`. It qualifies `top`'s `helper()` to `"Outer.helper"`. The `Inner`
DMod node is skipped (already handled). ✓

### Mutual recursion within a module
```march
mod M do
  fn even(n) = if n == 0 do true else odd(n-1) end
  fn odd(n)  = if n == 0 do false else even(n-1) end
end
```
Both `even` and `odd` are in `own_names`. `even`'s body `odd(n-1)` becomes
`M.odd(n-1)`. `odd`'s body `even(n-1)` becomes `M.even(n-1)`. These are
already the correct fully-qualified names that eval, typecheck, and TIR use. ✓

### `DUse` / import inside a module
```march
mod Http do
  use Net    -- imports Net.connect as bare "connect" via DUse
  fn get(url) = connect(url, 80)   -- means Net.connect, not Http.connect
end
```
`own_names` for `Http` only contains names declared via `DFn`/`DLet` directly
in `Http`, NOT names imported via `DUse`. So `connect` is NOT in `own_names`
and will NOT be rewritten by `qualify_in_decls`. The TIR `_use_aliases`
mechanism handles the `DUse` case separately (as it did before). ✓

### Non-function module members (types, interfaces)
Types and interfaces are not function calls — they don't appear as `EVar` nodes
in expressions. Type annotations use `TyCon` / `TyVar`, not `EVar`. No changes
needed for them. ✓

---

## Tests to add

Add cases to `test/test_compiler.ml` (or a new file in the same suite) covering:

1. **Basic intra-module call** — verify that `mod M do fn f() = g() fn g() = 42 end` outputs 42 when `f()` is called.
2. **User shadows stdlib name** — user defines top-level `fn connect(h) = ...`; calling `Socket.with_connection(...)` still uses `Socket.connect`, not the user's.
3. **Parameter shadows module name** — verify the parameter-shadow case compiles and runs correctly.
4. **Let-binding shadows module name** — same for `let connect = ...`.
5. **Nested module** — `mod Outer do mod Inner do fn f() = g() fn g() = 1 end fn h() = g() fn g() = 2 end end` — `Inner.f()` returns 1, `Outer.h()` returns 2.
6. **Mutual recursion** — `even`/`odd` inside a module.

---

## Implementation order

1. Add `collect_direct_names` (trivial)
2. Add `add_pat_vars` helper
3. Add `qualify_expr` (the main body of work)
4. Add `qualify_block` (called from `qualify_expr`)
5. Add `qualify_in_decls`
6. Add `qualify_module_refs`
7. Wire into `desugar_module`
8. Run the test suite — verify no regressions
9. Add the new tests listed above
10. Update `specs/todos.md` and `specs/progress.md`
