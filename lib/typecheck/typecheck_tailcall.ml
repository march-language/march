(** Tail-call enforcement — March's guarantee that a self- or mutually
    recursive function in tail position does not grow the stack.

    Lifted verbatim out of [Typecheck] (§16) on 2026-08-26.  It had been
    sitting inside the type checker without belonging to it: measured with
    the decomposition plan's [dep.py], this band references **zero** other
    definitions in [typecheck.ml] — not even [env], [ty] or [scheme].  It is
    a pure AST pass over declarations, and the only thing it shares with
    inference is the error sink it reports into.

    [Typecheck] regains these names with [include Typecheck_tailcall] at the
    position the band used to occupy, so nothing about [Typecheck]'s exported
    surface changes.

    See specs/plans/2026-08-19-compiler-file-decomposition.md (Phase 6,
    Task 6.2). *)

(* The module aliases live inside [Aliases] and are reached by [open] rather
   than declared at the top of this structure.  They are the same three
   [Typecheck] itself declares, and a bare `module Ast = …` here would be
   re-exported by [include Typecheck_tailcall] and collide with [Typecheck]'s
   own — "Multiple definition of the module name Ast".  An [open] of a nested
   module binds the names without adding them to this module's signature. *)
module Aliases = struct
  module Ast = March_ast.Ast
  module Err = March_errors.Errors
  module StringSet = Set.Make (String)
end

open Aliases

(* =================================================================
   §16  Tail-call enforcement
   ================================================================= *)

(** Collect all variable names bound by a pattern (used to find structurally
    smaller variables introduced by pattern matching, and to retire shadowed
    names from the call-graph name set). *)
let rec collect_pattern_vars (pat : Ast.pattern) : StringSet.t =
  match pat with
  | Ast.PatWild _ | Ast.PatLit _ -> StringSet.empty
  | Ast.PatVar v -> StringSet.singleton v.txt
  | Ast.PatCon (_, pats) ->
    List.fold_left (fun acc p -> StringSet.union acc (collect_pattern_vars p))
      StringSet.empty pats
  | Ast.PatAtom (_, pats, _) ->
    List.fold_left (fun acc p -> StringSet.union acc (collect_pattern_vars p))
      StringSet.empty pats
  | Ast.PatTuple (pats, _) ->
    List.fold_left (fun acc p -> StringSet.union acc (collect_pattern_vars p))
      StringSet.empty pats
  | Ast.PatRecord (fields, _) ->
    List.fold_left (fun acc (_, p) -> StringSet.union acc (collect_pattern_vars p))
      StringSet.empty fields
  | Ast.PatAs (p, v, _) -> StringSet.add v.txt (collect_pattern_vars p)
  | Ast.PatOr (pats, _) ->
    List.fold_left (fun acc p -> StringSet.union acc (collect_pattern_vars p))
      StringSet.empty pats

(** Collect all names from [fn_names] that are called directly (not through
    lambdas or local [ELetFn] bodies) in [e].  Used to build the call graph
    for SCC / mutual-recursion detection.

    [fn_names] is a SCOPE, not a flat name list: a local binder (an inner
    [ELetFn], or a [let] whose pattern binds the name) retires that name for
    the rest of the enclosing block.  Without this, a local helper whose name
    collides with a top-level function forges a call-graph edge and invents an
    SCC that does not exist — e.g. prelude's [length] uses a local [fn go], so
    any program with its own top-level [go] was told its calls were "recursive
    calls not in tail position". *)
let rec collect_direct_fn_calls (fn_names : StringSet.t) (e : Ast.expr) : StringSet.t =
  match e with
  | Ast.EApp (Ast.EVar fn, args, _) ->
    let self = if StringSet.mem fn.txt fn_names then StringSet.singleton fn.txt
               else StringSet.empty in
    List.fold_left (fun acc a ->
      StringSet.union acc (collect_direct_fn_calls fn_names a)
    ) self args
  | Ast.EApp (f, args, _) ->
    List.fold_left (fun acc a ->
      StringSet.union acc (collect_direct_fn_calls fn_names a)
    ) (collect_direct_fn_calls fn_names f) args
  | Ast.ECon (_, args, _) ->
    List.fold_left (fun acc a ->
      StringSet.union acc (collect_direct_fn_calls fn_names a)
    ) StringSet.empty args
  | Ast.EIf (c, t, f, _) ->
    StringSet.union (collect_direct_fn_calls fn_names c)
      (StringSet.union (collect_direct_fn_calls fn_names t)
                       (collect_direct_fn_calls fn_names f))
  | Ast.ECond (arms, _) ->
    List.fold_left (fun acc (ce, be) ->
      StringSet.union acc
        (StringSet.union (collect_direct_fn_calls fn_names ce)
                         (collect_direct_fn_calls fn_names be))
    ) StringSet.empty arms
  | Ast.EMatch (scrut, branches, _) ->
    List.fold_left (fun acc br ->
      (* Arm-bound names shadow same-named top-level functions inside the arm. *)
      let names =
        StringSet.diff fn_names (collect_pattern_vars br.Ast.branch_pat) in
      let g = Option.fold ~none:StringSet.empty
                ~some:(collect_direct_fn_calls names) br.Ast.branch_guard in
      StringSet.union acc
        (StringSet.union g (collect_direct_fn_calls names br.Ast.branch_body))
    ) (collect_direct_fn_calls fn_names scrut) branches
  (* A block is the one place where a binder's scope extends to SIBLING
     expressions: [ELetFn]/[ELet] carry no continuation of their own, so the
     shadowing has to be applied here, to the rest of the block. *)
  | Ast.EBlock (exprs, _) ->
    let (acc, _) =
      List.fold_left (fun (acc, names) ex ->
        let acc' = StringSet.union acc (collect_direct_fn_calls names ex) in
        let names' = match ex with
          | Ast.ELetFn (iname, _, _, _, _) -> StringSet.remove iname.txt names
          | Ast.ELet (b, _) -> StringSet.diff names (collect_pattern_vars b.Ast.bind_pat)
          | _ -> names
        in
        (acc', names')
      ) (StringSet.empty, fn_names) exprs
    in
    acc
  | Ast.ELet (b, _) -> collect_direct_fn_calls fn_names b.Ast.bind_expr
  | Ast.ELetFn (_, _, _, _, _) -> StringSet.empty   (* new scope *)
  | Ast.ELam (_, _, _)         -> StringSet.empty   (* new scope *)
  | Ast.ETuple (es, _) ->
    List.fold_left (fun acc ex ->
      StringSet.union acc (collect_direct_fn_calls fn_names ex)
    ) StringSet.empty es
  | Ast.ERecord (fields, _) ->
    List.fold_left (fun acc (_, ex) ->
      StringSet.union acc (collect_direct_fn_calls fn_names ex)
    ) StringSet.empty fields
  | Ast.ERecordUpdate (base, fields, _) ->
    List.fold_left (fun acc (_, ex) ->
      StringSet.union acc (collect_direct_fn_calls fn_names ex)
    ) (collect_direct_fn_calls fn_names base) fields
  | Ast.EField (ex, _, _)  -> collect_direct_fn_calls fn_names ex
  | Ast.EAnnot (ex, _, _)  -> collect_direct_fn_calls fn_names ex
  | Ast.EPipe (l, r, _) ->
    StringSet.union (collect_direct_fn_calls fn_names l)
                    (collect_direct_fn_calls fn_names r)
  | Ast.EAtom (_, args, _) ->
    List.fold_left (fun acc a ->
      StringSet.union acc (collect_direct_fn_calls fn_names a)
    ) StringSet.empty args
  | Ast.ESend (a, b, _) ->
    StringSet.union (collect_direct_fn_calls fn_names a)
                    (collect_direct_fn_calls fn_names b)
  | Ast.ESpawn (ex, _)       -> collect_direct_fn_calls fn_names ex
  | Ast.EDbg (Some ex, _)    -> collect_direct_fn_calls fn_names ex
  | Ast.ELetQ (pat, r, c, _) | Ast.ELetStar (pat, r, c, _) ->
    StringSet.union (collect_direct_fn_calls fn_names r)
      (collect_direct_fn_calls
         (StringSet.diff fn_names (collect_pattern_vars pat)) c)
  | Ast.EAssert (ex, _) -> collect_direct_fn_calls fn_names ex
  | Ast.ESigil (_, content, _) -> collect_direct_fn_calls fn_names content
  | Ast.ELit _ | Ast.EVar _ | Ast.EHole _ | Ast.EResultRef _
  | Ast.EDbg (None, _)       -> StringSet.empty

(** Tarjan's SCC algorithm.  [adj] is a list of (name, called-names) pairs.
    Returns each SCC as a list; non-recursive singletons are included. *)
let find_sccs (adj : (string * StringSet.t) list) : string list list =
  let idx_ctr   = ref 0 in
  let stk       = ref [] in
  let on_stk    = Hashtbl.create 16 in
  let idx_map   = Hashtbl.create 16 in
  let lowlink   = Hashtbl.create 16 in
  let sccs      = ref [] in
  let rec sc v =
    let vi = !idx_ctr in
    Hashtbl.replace idx_map  v vi;
    Hashtbl.replace lowlink  v vi;
    incr idx_ctr;
    stk := v :: !stk;
    Hashtbl.replace on_stk v true;
    let neighbors = match List.assoc_opt v adj with
      | Some s -> StringSet.elements s | None -> [] in
    List.iter (fun w ->
      if not (Hashtbl.mem idx_map w) then begin
        sc w;
        let lv = Hashtbl.find lowlink v in
        let lw = Hashtbl.find lowlink w in
        Hashtbl.replace lowlink v (min lv lw)
      end else if Hashtbl.mem on_stk w then begin
        let lv = Hashtbl.find lowlink v in
        let iw = Hashtbl.find idx_map  w in
        Hashtbl.replace lowlink v (min lv iw)
      end
    ) neighbors;
    if Hashtbl.find lowlink v = Hashtbl.find idx_map v then begin
      let scc = ref [] in
      let go  = ref true in
      while !go do
        match !stk with
        | [] -> go := false
        | w :: rest ->
          stk := rest;
          Hashtbl.remove on_stk w;
          scc := w :: !scc;
          if w = v then go := false
      done;
      sccs := !scc :: !sccs
    end
  in
  List.iter (fun (v, _) ->
    if not (Hashtbl.mem idx_map v) then sc v
  ) adj;
  !sccs

let is_infix_op name =
  match name with
  | "+" | "-" | "*" | "/" | "%" | "<" | ">" | "<=" | ">="
  | "==" | "!=" | "&&" | "||" | "+." | "-." | "*." | "/." -> true
  | _ -> false

(** True if [expr] is provably structurally smaller than some function parameter.
    - [params]: the set of function parameter variable names.
    - [smaller]: variables known to be sub-components of a parameter (from pattern matching).
    Recognises:
      1. A pattern-bound sub-component: [EVar v] where [v ∈ smaller].
      2. Arithmetic reduction: [v - k] or [v / k] where [v ∈ params ∪ smaller].
      3. List element access: [list_nth_safe(xs,i)], [List.nth(xs,i)] where xs is smaller.
      4. Nullary constructor (e.g. HEmpty, Nil): structurally minimal. *)
let rec is_structurally_smaller (params : StringSet.t) (smaller : StringSet.t) (expr : Ast.expr) : bool =
  match expr with
  | Ast.EVar v -> StringSet.mem v.txt smaller
  | Ast.EApp (Ast.EVar op, [lhs; _], _) when op.txt = "-" || op.txt = "/" ->
    (match lhs with
     | Ast.EVar v -> StringSet.mem v.txt params || StringSet.mem v.txt smaller
     | _ -> false)
  (* List element accessor: element is structurally smaller than the list *)
  | Ast.EApp (Ast.EVar fn, arg :: _, _)
    when List.mem fn.txt ["list_nth_safe"; "list_nth"; "List.nth"; "List.hd"; "List.head"] ->
    is_structurally_smaller params smaller arg
  (* Nullary constructor (e.g. HEmpty, Nil): always structurally minimal *)
  | Ast.ECon (_, [], _) -> true
  | _ -> false

(** True if [expr] is a function parameter or a known-smaller variable — meaning
    pattern-bound sub-components of this scrutinee can be treated as smaller. *)
let scrutinee_is_param_or_smaller (params : StringSet.t) (smaller : StringSet.t) (expr : Ast.expr) : bool =
  match expr with
  | Ast.EVar v -> StringSet.mem v.txt params || StringSet.mem v.txt smaller
  | _ -> false

(** Verify that every call to any name in [recursive_names] within [body]
    is either in tail position OR is structurally recursive (guaranteed to
    terminate because every argument is provably smaller than a parameter).
    Emits [Error] diagnostics only for truly unbounded non-tail recursion.
    [fn_name] is the enclosing function (for readable error messages).
    [fn_params] is the set of parameter variable names for [fn_name].

    [recursive_names] is a SCOPE, threaded through [chk] as [names]: a local
    binder (inner [fn], [let], [let?], a match arm's pattern) retires that name
    for its extent, so a call to a shadowing local is not misattributed to the
    same-named recursive function. *)
let rec check_tail_position
    ?(display = fun (n : string) -> n)
    (errors : Err.ctx)
    (recursive_names : StringSet.t)
    (fn_name : string)
    (fn_params : StringSet.t)
    (body : Ast.expr) : unit =
  (* [recursive_names] is in the post-desugar CALL-SITE namespace, which inside
     a nested `mod` carries a qualifying prefix the author never typed
     (`Inner.boom` for a source that says `boom`).  [display] maps a matched
     call-site name back to the bare name, so the diagnostic quotes the program
     rather than the desugarer's rewrite.  Defaults to the identity for the
     inner-`fn` recursion below, whose names are local and never qualified. *)
  (* [smaller] accumulates variables known to be structurally smaller than a
     function parameter (introduced by pattern-matching on a parameter). *)
  let rec chk in_tail (names : StringSet.t) (smaller : StringSet.t) ctx expr =
    match expr with
    (* ── Recursive call ── *)
    | Ast.EApp (Ast.EVar fn, args, sp) when StringSet.mem fn.txt names ->
      if not in_tail then begin
        (* Allow if at least one argument is provably structurally smaller:
           this covers structural recursion on sub-trees/sub-lists and
           arithmetic reductions like n-1, n-2. *)
        let is_structural =
          List.exists (is_structurally_smaller fn_params smaller) args
        in
        if not is_structural then begin
          (* The advice has to match the blocker. An accumulator moves work
             that happens AFTER the call to before it — the right fix when a
             result is combined arithmetically, and useless for a branching
             search joined by `||`/`&&`. Those are strict in March
             (specs/lang/core-march.md 4.4.1), so the call genuinely is not in
             tail position, but the fix is to branch instead: an `if` branch
             inherits tail position, so `a || b` written as
             `if a do true else b end` puts the right-hand call in tail
             position (and skips it when the left already decides). *)
          let is_boolop =
            let has sub =
              let n = String.length sub and m = String.length ctx in
              let rec go i = i + n <= m && (String.sub ctx i n = sub || go (i + 1)) in
              go 0
            in
            has "`||`" || has "`&&`"
          in
          let hint =
            if is_boolop then
              "Hint: `&&`/`||` evaluate both sides in March. Rewrite `a || b` as \
               `if a do true else b end` (and `a && b` as `if a do b else false end`) \
               to put the right-hand call in tail position.\n\
               If the depth is bounded and you accept the stack use, annotate \
               the function with `@[no_warn_recursion]`."
            else
              "Hint: Consider using an accumulator parameter.\n\
               If the depth is bounded and you accept the stack use, annotate \
               the function with `@[no_warn_recursion]`."
          in
          Err.error errors ~span:sp
            (Printf.sprintf
               "Function `%s`: recursive call to `%s` is not in tail position \
                (%s).\n%s"
               fn_name (display fn.txt) ctx hint)
        end
        else begin
          (* Structural recursion: warn but allow — distinguish arithmetic
             reductions (n-1, n-2) from pattern-bound sub-components. *)
          let is_arithmetic = List.exists (fun arg ->
            match arg with
            | Ast.EApp (Ast.EVar op, [lhs; _], _) when op.txt = "-" ->
              (match lhs with
               | Ast.EVar v ->
                 StringSet.mem v.txt fn_params || StringSet.mem v.txt smaller
               | _ -> false)
            | _ -> false
          ) args in
          if is_arithmetic then
            Err.warning errors ~span:sp
              (Printf.sprintf
                 "Warning: function `%s` is structurally recursive but not \
                  tail-recursive. Consider using an accumulator parameter \
                  for O(n) performance."
                 fn_name)
          else
            (* The loop is NOT automatic.  TRMC (lib/tir/trmc.ml) does perform
               exactly this transformation and is correct on eligible shapes,
               but `Trmc.enabled` defaults to false, so on the default pipeline
               a constructor-wrapped recursive call really does keep O(depth)
               stack and really does overflow on deep input.  This message once
               promised the loop unconditionally — it was reworded ahead of a
               default flip (specs/plans/2026-08-10-trmc-on-by-default.md) that
               never landed.  State the opt-in, not the promise. *)
            Err.warning errors ~span:sp
              (Printf.sprintf
                 "Warning: function `%s` is structurally recursive but not \
                  tail-recursive. This is safe for bounded input but uses \
                  O(depth) stack space, so deep input can overflow the stack. \
                  Consider an accumulator parameter. Tail-recursion-modulo-cons \
                  can compile a recursive call that is the direct argument of a \
                  constructor into a loop instead, but it is off by default; \
                  enable it with `--trmc`."
                 fn_name)
        end
      end;
      List.iteri (fun i arg ->
        chk false names smaller
          (Printf.sprintf "argument #%d in call to `%s`" (i + 1) fn.txt)
          arg
      ) args
    (* ── Regular application ── *)
    | Ast.EApp (f, args, _) ->
      let arg_ctx = match f with
        | Ast.EVar op when is_infix_op op.txt ->
          Printf.sprintf "wrapped in binary operation `%s`" op.txt
        | Ast.EVar fn_n -> Printf.sprintf "passed as argument to `%s`" fn_n.txt
        | _ -> "passed as argument to a function"
      in
      chk false names smaller "function part of application" f;
      List.iter (chk false names smaller arg_ctx) args
    (* ── Constructor ── *)
    | Ast.ECon (name, args, _) ->
      let arg_ctx = Printf.sprintf "wrapped in constructor `%s`" name.txt in
      List.iter (chk false names smaller arg_ctx) args
    (* ── if/do/else/end: condition not tail; branches inherit ── *)
    | Ast.EIf (cond, then_, else_, _) ->
      chk false names smaller "condition of `if`" cond;
      chk in_tail names smaller ctx then_;
      chk in_tail names smaller ctx else_
    (* ── match do cond_arm* end ── *)
    | Ast.ECond (arms, _) ->
      List.iter (fun (ce, be) ->
        chk false names smaller "condition in `match do`" ce;
        chk in_tail names smaller ctx be
      ) arms
    (* ── match: scrutinee not tail; if scrutinee is a parameter or smaller
          variable, extend [smaller] with all vars bound in each arm's pattern ── *)
    | Ast.EMatch (scrut, branches, _) ->
      chk false names smaller "scrutinee of `match`" scrut;
      let scrut_is_smaller = scrutinee_is_param_or_smaller fn_params smaller scrut in
      List.iter (fun (br : Ast.branch) ->
        let arm_pat_vars = collect_pattern_vars br.branch_pat in
        let arm_smaller =
          if scrut_is_smaller then StringSet.union smaller arm_pat_vars else smaller
        in
        (* Arm-bound names shadow the recursive names inside the arm. *)
        let arm_names = StringSet.diff names arm_pat_vars in
        Option.iter (chk false arm_names arm_smaller "match guard") br.branch_guard;
        chk in_tail arm_names arm_smaller ctx br.branch_body
      ) branches
    (* ── block: only last expression is in tail position.
          Propagate structural smallness: if a let binding assigns a variable
          to a structurally-smaller expression, that variable is also smaller. ── *)
    | Ast.EBlock (exprs, _) ->
      let rec go ns s = function
        | [] -> ()
        | [last] -> chk in_tail ns s ctx last
        | hd :: tl ->
          chk false ns s "non-final expression in block" hd;
          let s' = match hd with
            | Ast.ELet (b, _) ->
              (match b.Ast.bind_pat with
               | Ast.PatVar v
                 when is_structurally_smaller fn_params s b.Ast.bind_expr ->
                 StringSet.add v.txt s
               | _ -> s)
            | _ -> s
          in
          (* A local binder shadows a same-named recursive function for the
             rest of the block — calls to it are not recursive calls. *)
          let ns' = match hd with
            | Ast.ELetFn (iname, _, _, _, _) -> StringSet.remove iname.txt ns
            | Ast.ELet (b, _) -> StringSet.diff ns (collect_pattern_vars b.Ast.bind_pat)
            | _ -> ns
          in
          go ns' s' tl
      in
      go names smaller exprs
    (* ── let binding: RHS is never tail ── *)
    | Ast.ELet (b, _) ->
      chk false names smaller "right-hand side of `let` binding" b.Ast.bind_expr
    (* ── inner named function: check its own self-recursion in its own scope ── *)
    | Ast.ELetFn (iname, iparams, _, ibody, _) ->
      let iparams_set =
        List.fold_left (fun acc (p : Ast.param) -> StringSet.add p.param_name.txt acc)
          StringSet.empty iparams
      in
      check_tail_position errors (StringSet.singleton iname.txt) iname.txt iparams_set ibody
    (* ── lambda: new scope, skip outer recursive-name check ── *)
    | Ast.ELam _ -> ()
    (* ── transparent ── *)
    | Ast.EAnnot (ex, _, _) -> chk in_tail names smaller ctx ex
    (* ── non-tail contexts ── *)
    | Ast.ETuple (es, _) ->
      List.iter (chk false names smaller "tuple element") es
    | Ast.ERecord (fields, _) ->
      List.iter (fun ((nm : Ast.name), ex) ->
        chk false names smaller (Printf.sprintf "value of record field `%s`" nm.txt) ex
      ) fields
    | Ast.ERecordUpdate (base, fields, _) ->
      chk false names smaller "base of record update" base;
      List.iter (fun ((nm : Ast.name), ex) ->
        chk false names smaller (Printf.sprintf "value of record field `%s`" nm.txt) ex
      ) fields
    | Ast.EField (ex, _, _)  -> chk false names smaller "object of field access" ex
    | Ast.EPipe  (l, r, _)   -> chk false names smaller "left side of pipe" l;
                                 chk false names smaller "right side of pipe" r
    | Ast.EAtom (_, args, _) -> List.iter (chk false names smaller "atom argument") args
    | Ast.ESend (cap, msg, _) ->
      chk false names smaller "capability in `send`" cap;
      chk false names smaller "message in `send`" msg
    | Ast.ESpawn (ex, _)      -> chk false names smaller "argument to `spawn`" ex
    | Ast.EDbg (Some ex, _)   -> chk false names smaller "argument to `dbg`" ex
    | Ast.ELetQ (pat, r, cont, _) ->
      chk false names smaller "right-hand side of `let?`" r;
      chk in_tail (StringSet.diff names (collect_pattern_vars pat))
        smaller ctx cont
    (* `let*` desugars to `M.flat_map(r, fn pat -> cont end)` (TIR lowering) --
       unlike `let?` (a direct `match`, no call-frame boundary), `cont` ends
       up INSIDE a callback lambda handed to `flat_map`, so it is never in
       tail position relative to the enclosing function no matter what
       `in_tail` says here. Treat it exactly like `ELam` above: a fresh
       scope, not walked further by THIS check -- a self-recursive call
       inside `cont` is an ordinary non-tail call through a closure, not a
       tail-position violation. *)
    | Ast.ELetStar (_, r, _, _) ->
      chk false names smaller "right-hand side of `let*`" r
    | Ast.EAssert (ex, _)     -> chk false names smaller "assert expression" ex
    | Ast.ESigil (_, content, _) -> chk false names smaller "sigil content" content
    (* ── leaves ── *)
    | Ast.EDbg (None, _) | Ast.ELit _ | Ast.EVar _ | Ast.EHole _
    | Ast.EResultRef _ -> ()
  in
  chk true recursive_names StringSet.empty "" body

(** Run tail-call enforcement for all [DFn] declarations in [decls]
    (at a single scope level).  Recurses into [DMod] sub-modules.

    [mod_path] is the accumulated dotted path of the enclosing [DMod]s, with a
    trailing dot ("" at the top level, then "Inner.", then "Outer.Inner.").
    [file_mod] is the name of the module this file declares.

    ── Why a PATH is needed at all ──────────────────────────────────────────

    This pass runs AFTER desugaring, and desugaring rewrites call sites into a
    different namespace than the one declarations live in.
    [Desugar.qualify_module_refs] rewrites bare intra-module CALL SITES inside
    every nested [DMod] to [Prefix.name] ([EVar "boom"] -> [EVar "Inner.boom"]),
    and deliberately leaves the DECLARATION name alone.  Building [fn_names]
    from the bare [def.fn_name.txt] therefore searched a post-desugar body for a
    pre-desugar name: [collect_direct_fn_calls] matched nothing, [is_recursive]
    came out false, and the function was never checked.  Everything this pass
    rejects at the top level was silently accepted one [mod] deeper, at any
    depth — and the [DMod] recursion below, which looks like it covers nested
    modules, ran and found nothing.

    The top level of the ENTRY file hid this: [qualify_module_refs] seeds
    [entry_prefix = ""] and only rewrites inside [DMod] NODES, and the parser
    splits a file's sole top-level [mod] into [mod_name]/[mod_decls] — so a
    top-level [DFn] is never qualified and never mismatched.

    ── Why TWO candidate prefixes ───────────────────────────────────────────

    A name declared here can be referenced under either of two conventions, and
    which one applies is a property of the FILE, not of this declaration list:

    - [mod_path] — the entry file's convention.  [desugar_module] passes
      [~entry_prefix:""] when [is_entry], so the accumulation starts empty.
    - [file_mod ^ "." ^ mod_path] — the non-entry convention.  A dependency
      file is desugared with [~entry_prefix:(mod_name ^ ".")], so a nested
      module inside stdlib's [Helper] qualifies to ["Helper.Inner."], not
      ["Inner."].

    Typecheck is not told which one it is looking at, so it accepts both.  This
    costs nothing in precision: a file is one or the other, so the inapplicable
    candidate simply never occurs in any body.

    At the TOP level ([mod_path = ""]) the second candidate is [file_mod ^ "."],
    which additionally catches a hand-written SELF-QUALIFIED call in a non-entry
    module ([Helper.boom] inside [mod Helper]) — [strip_entry_self_qual]
    normalises that away only for the entry file, so in a dependency it survives
    to here and was a second, nesting-free instance of the same blind spot.
    Recognising it cannot misfire: inside [mod Helper], [Helper.boom] is
    unambiguously this module's [boom]. *)
let rec enforce_tail_calls_in_decls
    ?(mod_path = "") ~(file_mod : string)
    (errors : Err.ctx) (decls : Ast.decl list) : unit =
  (* Names declared in an [extern] block at this level.  An extern has no
     body, so it can never recurse; a bare call to one must not be resolved
     against a same-named ordinary function (the entry module's decls include
     the injected prelude, so e.g. an extern `length` sat next to prelude's
     `fn length`). *)
  let extern_names =
    List.fold_left (fun acc d ->
      match d with
      | Ast.DExtern (ext, _) ->
        List.fold_left (fun acc ef -> StringSet.add ef.Ast.ef_name.txt acc)
          acc ext.Ast.ext_fns
      | _ -> acc
    ) StringSet.empty decls
  in
  (* Collect function names at this level, BARE — the namespace declarations
     and diagnostics live in, and the one the call graph is keyed by. *)
  let bare_fn_names =
    List.fold_left (fun acc d ->
      match d with
      | Ast.DFn (def, _) -> StringSet.add def.fn_name.txt acc
      | _ -> acc
    ) StringSet.empty decls
  in
  (* Extern names are subtracted BARE, before qualification: an extern is never
     qualified at a call site either ([qualify_level] passes [~externs:false]),
     so the two sets are comparable only here. *)
  let bare_fn_names = StringSet.diff bare_fn_names extern_names in
  (* The two conventions a name declared here can be referenced under — see
     this function's doc comment. *)
  let prefixes = [ mod_path; file_mod ^ "." ^ mod_path ] in
  (* [call_names] is the CALL-SITE namespace (what [collect_direct_fn_calls]
     and [check_tail_position] match [EVar]s against); [to_bare] maps back, so
     the graph, the SCCs and the diagnostics all stay in the bare namespace. *)
  let to_bare = Hashtbl.create 16 in
  let call_names =
    StringSet.fold (fun bare acc ->
      List.fold_left (fun acc p ->
        let qualified = p ^ bare in
        Hashtbl.replace to_bare qualified bare;
        StringSet.add qualified acc
      ) acc prefixes
    ) bare_fn_names StringSet.empty
  in
  (* Callees of [body], as BARE local names. *)
  let bare_calls_in body =
    StringSet.fold (fun called acc ->
      match Hashtbl.find_opt to_bare called with
      | Some bare -> StringSet.add bare acc
      | None -> acc
    ) (collect_direct_fn_calls call_names body) StringSet.empty
  in
  (* Build call graph *)
  let adj = List.filter_map (function
    | Ast.DFn (def, _) ->
      (match def.fn_clauses with
       | [clause] ->
         Some (def.fn_name.txt, bare_calls_in clause.Ast.fc_body)
       | _ -> None)
    | _ -> None
  ) decls in
  (* Find SCCs *)
  let sccs = find_sccs adj in
  let scc_of = Hashtbl.create 16 in
  List.iter (fun scc ->
    List.iter (fun nm -> Hashtbl.replace scc_of nm scc) scc
  ) sccs;
  (* Check each function that participates in recursion *)
  List.iter (function
    | Ast.DFn (def, _) ->
      (match def.fn_clauses with
       | [clause] ->
         let scc = try Hashtbl.find scc_of def.fn_name.txt
                   with Not_found -> [def.fn_name.txt] in
         let direct = match List.assoc_opt def.fn_name.txt adj with
           | Some s -> s | None -> StringSet.empty in
         let is_recursive =
           List.length scc > 1 ||
           StringSet.mem def.fn_name.txt direct
         in
         if is_recursive && not (List.mem "no_warn_recursion" def.fn_attrs) then begin
           (* [check_tail_position] matches [EVar]s, so the recursive-name set
              has to be in the CALL-SITE namespace, not the bare one. *)
           let rec_set =
             List.fold_left (fun acc bare ->
               List.fold_left (fun acc p -> StringSet.add (p ^ bare) acc)
                 acc prefixes
             ) StringSet.empty scc
           in
           let fn_params =
             List.fold_left (fun acc p ->
               match p with
               | Ast.FPNamed named -> StringSet.add named.param_name.txt acc
               | Ast.FPDefault (named, _) -> StringSet.add named.param_name.txt acc
               | Ast.FPPat pat -> StringSet.union acc (collect_pattern_vars pat)
             ) StringSet.empty clause.Ast.fc_params
           in
           let display n =
             match Hashtbl.find_opt to_bare n with Some b -> b | None -> n in
           check_tail_position ~display errors rec_set def.fn_name.txt fn_params
             clause.Ast.fc_body
         end
       | _ -> ())
    | Ast.DMod (name, _, inner_decls, _) ->
      enforce_tail_calls_in_decls
        ~mod_path:(mod_path ^ name.txt ^ ".") ~file_mod errors inner_decls
    | _ -> ()
  ) decls
