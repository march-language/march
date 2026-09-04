(* Refinement checking (Phases A1b + A2, minimal vertical slice).

   A post-typecheck pass over the AST: it collects functions whose parameters
   carry an `{Int | predicate}` refinement, then walks every call site and, for
   each refined parameter, discharges a verification condition through the A0
   Z3 bridge (`March_refine`).

   A1b: Int/Bool predicates over the binder `_`, literal / refined-local args.
   A2 : the `len` measure and cross-argument predicates, so bounds such as
        `{Int | _ >= 0 && _ < len(xs)}` are checkable when the length is known
        (a list literal) or symbolically related.

   Soundness stance: an argument we cannot reflect (an unconstrained variable,
   a complex expression) is conservatively SKIPPED — no false positives.
   Scope: direct (named) calls only, no path sensitivity. *)

(* Table of contents — the § markers below are greppable:
     grep -n '§' lib/refinecheck/refine_check.ml

     §1  Refined parameters and base-type classification
     §2  SMT sorts: strings, scalars, measures, well-sortedness
     §3  Predicate scope and parameter substitution
     §4  Function signatures, measures, and stdlib-provided names
     §5  ADT and record sorts: registry and SMT preamble builders
     §6  AST traversal helpers and measure gating
     §7  Reflection: March expressions into SMT terms
     §8  Rendering: predicates, models, counterexamples
     §9  Scope — the refined bindings in scope
     §10 The other fact channels: path, launder, recenv, cbenv
     §11 Signature extraction and definition collection
     §12 Name resolution: module paths, aliases, call targets
     §13 Reflecting actual arguments: fields, records, scalars
     §14 Verdict state and withdrawal diagnostics
     §15 check_call — precondition checking at a call site
     §16 Postcondition checking
     §17 Postconditions by induction
     §18 Function-level postcondition entry points and gating
     §19 The visit traversal
     §20 Refinement-placement warnings
     §21 The declaration walk
     §22 Registration and stdlib-shape validation
     §23 Entry point: check_module

   §15 is `check_call`, 1,361 lines and the single largest thing here;
   §16-§18 are its postcondition counterpart. *)


(* ── §1–§6 moved to [Refine_encode] ───────────────────────────────────────
   The four module aliases (A, Smt, Refine, Err) moved with the band and
   arrive through the include, so they are no longer declared above.
   The SMT encoding and sort discipline moved VERBATIM into [Refine_encode].
   [include], not aliases: the included chain owns all 16 of the cells
   reached through this include (9 in [Refine_encode], 1 in
   [Refine_resolve], 6 in [Refine_call]; [Refine_scope] and [Refine_post]
   declare none at top level — [Obligation.log] and [Witness]'s three cells
   are pass state too, but they live outside this include chain) and they
   are written from the far end of this file, so the SAME ref cell must be
   in scope here — see [Refine_encode]'s header. *)
(* ── §1–§11 moved out ─────────────────────────────────────────────────────
   §1–§6 (the SMT encoding and sort discipline) live in [Refine_encode];
   §7–§11 (reflection, rendering, and the two fact channels) live in
   [Refine_scope]; §12–§13 (name resolution, argument reflection) live in
   [Refine_resolve].  Each includes the one below it, so this single include
   brings the whole chain back in its original order.  So this single include
   brings both back, in their original order.  The four module aliases
   (A, Smt, Refine, Err) arrive through it too.

   [include], not aliases: those bands own all 16 of the cells reached
   through this include (9 in [Refine_encode], 1 in [Refine_resolve], 6 in
   [Refine_call]; [Refine_scope] and [Refine_post] declare none at top
   level — [Obligation.log] and [Witness]'s three cells are pass state too,
   but they live outside this include chain) and they are written from the
   far end of this file, so the SAME ref cell must be in scope here. *)
include Refine_post

(* =================================================================
   §19 The visit traversal
   ================================================================= *)

(* ── An annotated `let`'s refinement is an OBLIGATION, not a promise ───────

   `let ys : {List(Int) | len(_) > 0} = []` used to be believed on sight:
   [scope_add_binding]'s annotated arm admits the predicate into [scope]
   unconditionally, so the annotation became a fact about `ys` and every later
   goal that needed it was PROVED off an expression that plainly violates it.
   Under `cap verified` — whose premise is "if it compiles, it is proved" —
   that is an unsound hole reachable by ordinary, non-adversarial code: an
   author writes an annotation to document an invariant and instead silently
   manufactures it.

   The check is not new machinery.  "Does this expression satisfy this
   predicate" is exactly what [check_call] answers for a call's actual, so the
   binding is reflected AS a one-parameter call: the annotation is the
   precondition, the bound expression is the sole argument.  That inherits the
   definite-failure stance (report only on a positive proof of ¬goal;
   unreflectable or solver-unsure stays a [Skipped]) and every resolver
   [check_call] already has, including the measure and constructor-tag paths
   added for contract composition.

   Two details that are easy to get wrong and are load-bearing:

   - [param_names] carries the LET NAME, not the refinement's binder.
     [check_call] resolves the refined value through [actual_of_name], which
     looks a name up in [param_names]; the binder travels separately in
     [rparam.binder].  All three spellings of the value must land on the same
     actual — `_`, a declared binder (`{v : T | p(v)}`), and the bound name
     itself (`len(ys)`) — and only this arrangement gets the third one.  (This
     is the difference from [callback_sig_of_ty], whose `$cb_arg` placeholder
     is safe precisely because a callback's domain has no name a predicate
     could spell.)

   - The binding's own name is SHADOWED out of all three fact channels first.
     The predicate's `ys` denotes the value being bound here, never an outer
     `ys`; leaving a stale entry visible would let an outer value's fact be
     attributed to this binder, which is the false-positive direction this
     subsystem must never take.  Retiring a fact can only cost precision (a
     skip), never soundness.

   Returns [Some true] when the annotation was PROVED, [Some false] when it was
   violated or left undecided, and [None] when the binding carries no refined
   annotation at all (so the caller falls through to [scope_add_binding]'s
   ordinary postcondition-derived handling).

   The caller uses that verdict to decide whether the predicate may enter
   [scope].  Admitting it on anything but a proof would re-open the hole in a
   quieter form: a `let ys : {List(Int) | len(_) > 0} = zs` the checker cannot
   decide would file a Skipped obligation and then STILL hand `len(ys) > 0` to
   every later goal, so `inner(ys)` would report `Proved` on the strength of a
   premise nobody established.  A proof that rests on an unverified assumption
   is exactly what this change exists to remove, so an unproven annotation
   grants nothing.  That costs precision — an invariant the author knows but
   the checker cannot see is no longer usable — and the cost lands entirely in
   the safe direction, as more skips. *)
let check_let_annotation ~root errctx defs (ctx : rctx) (path : (A.expr * bool) list)
    (lets : launder) (sc : scope) (re : recenv) (b : A.binding) : bool option =
  match b.A.bind_pat, refined_scope_ty b.A.bind_ty with
  | A.PatVar n, Some (binder, pred, sort) ->
    let name = n.A.txt in
    let names = pat_binders b.A.bind_pat in
    let sg =
      { param_names = [ name ]
      ; param_str = [ sort = Some str_sort ]
      ; param_scalar = [ scalar_sort_or_int sort ]
      ; refined = [ { idx = 0; binder; pred; sort } ]
      ; ret = None
      ; ret_sort = None
      }
    in
    let out = ref None in
    (* Every fact channel is shadowed by the names this binding introduces —
       see [call_ctx]'s note: all of them, or none. *)
    let cx =
      { root
      ; errctx
      ; postcond = postcond_of ctx defs
      ; path = path_shadow path names
      ; lets = launder_shadow lets names
      ; sc = scope_shadow sc names
      ; re = recenv_shadow re names
      }
    in
    check_call cx ~span:n.A.span
      ~callee:(Printf.sprintf "let %s" name)
      ~subject:Bound_expr ~verdict_out:out sg
      [ b.A.bind_expr ]
      { idx = 0; binder; pred; sort };
    Some (!out = Some Obligation.Proved)
  | _ -> None

(* ── Walk expressions, threading the refined-local scope, the record-typed
   variables ([recenv]) and the path context ─────────────────────────────── *)
let rec visit ~root errctx defs (ctx : rctx) (path : (A.expr * bool) list)
    (lets : launder) (sc : scope) (re : recenv) (cb : cbenv) (e : A.expr) : unit =
  let go = visit ~root errctx defs ctx path lets sc re cb in
  let go_path p = visit ~root errctx defs ctx p lets sc re cb in
  match e with
  | A.EApp (A.EVar { A.txt = fname; _ }, args, sp) ->
    (match resolve_call ctx defs fname with
     | Some (Some sg) ->
       let cx = { root; errctx; postcond = postcond_of ctx defs; path; lets; sc; re } in
       List.iter (fun rp -> check_call cx ~span:sp ~callee:fname sg args rp) sg.refined
     | _ ->
       (* Not a resolvable NAMED callee: fall back to the callee env — a call
          made through a refined function-typed parameter, or through a local
          alias of a named function (see [cbenv]). *)
       (match List.assoc_opt fname cb with
        | Some sg ->
          let cx = { root; errctx; postcond = postcond_of ctx defs; path; lets; sc; re } in
          List.iter (fun rp -> check_call cx ~span:sp ~callee:fname sg args rp) sg.refined
        | None -> ()));
    List.iter go args
  | A.EApp (f, args, _) -> go f; List.iter go args
  | A.ECon (_, args, _) | A.EAtom (_, args, _) | A.ETuple (args, _) -> List.iter go args
  | A.EBlock (es, _) ->
    (* Thread the path context, the refined-local scope AND the callee env
       left-to-right: a `let` extends the scope (and, for a bare-alias RHS,
       the callee env); an `assert(p)` (used as an `assume`) extends the path
       so a later call can rely on p.

       A block-level `fn f(...) do ... end` (ELetFn) is itself a SIBLING
       block statement, not nested inside — [visit]'s dedicated [A.ELetFn]
       case only descends into that local function's OWN body, so its bound
       name must ALSO be retired here for the statements that follow it in
       this block.  It carries no [scope]/[recenv] fact of its own (those
       channels track Int/String/ADT VALUES, and a function name is never
       one), but it always shadows [cbenv]: a same-named outer refined
       callback parameter must not keep being checked against calls to this
       new, unrelated local function. *)
    ignore
      (List.fold_left
         (fun (ctx, path, lets, sc, re, cb) e ->
           visit ~root errctx defs ctx path lets sc re cb e;
           (* An annotated `let`'s refinement is checked against its bound
              expression HERE, against the scope as it stands BEFORE the
              binding — exactly as a call's arguments are checked against the
              caller's pre-call scope.  Doing it after [scope_add_binding]
              would let the annotation discharge itself. *)
           let annot_proved =
             match e with
             | A.ELet (b, _) -> check_let_annotation ~root errctx defs ctx path lets sc re b
             | _ -> None
           in
           (* A `let`/local-`fn` binder also retires the name for CALLEE
              RESOLUTION in the statements that follow — see [local_shadow]. *)
           let ctx' =
             match e with
             | A.ELet (b, _) -> local_shadow ctx (pat_binders b.A.bind_pat)
             | A.ELetFn (n, _, _, _, _) -> local_shadow ctx [ n.A.txt ]
             | _ -> ctx
           in
           let path' =
             match e with
             | A.EAssert (p, _) -> (p, false) :: path
             (* A `let` REBINDS its names: retire any fact about them first
                (the shadow discipline every other channel obeys), then, for
                an admitted RHS shape, push `n == rhs` as an ordinary path
                fact — reusing the same translator and the same retirement
                rule that already protects [check_call]'s other path facts,
                so a later rebinding of anything `rhs` mentions retires this
                equality too. *)
             | A.ELet (b, _) ->
               let names = pat_binders b.A.bind_pat in
               let path = path_shadow path names in
               (match b.A.bind_pat, b.A.bind_expr with
                (* A self-referential RHS (`let k = k - 100`) resolves both
                   occurrences of `k` to the SAME SMT constant once pushed,
                   turning the equality into a (usually unsatisfiable)
                   constraint on the OLD value rather than a definition of
                   the new one — see the whole-plan review's finding 1.
                   [names] is exactly the set [path_shadow] just retired
                   facts about, so require the RHS to mention none of them. *)
                | A.PatVar n, rhs
                  when let_equality_rhs rhs && not (expr_mentions names rhs) ->
                  let sp = n.A.span in
                  let eq =
                    A.EApp
                      ( A.EVar { A.txt = "=="; A.span = sp }
                      , [ A.EVar { A.txt = n.A.txt; A.span = sp }; rhs ]
                      , sp )
                  in
                  (eq, false) :: path
                | _ -> path)
             | A.ELetFn (n, _, _, _, _) -> path_shadow path [ n.A.txt ]
             | _ -> path
           in
           (* The laundering channel: retire first (both the key and any entry
              whose RHS mentions a rebound name — see [launder]), then record a
              single-name binding whose RHS is a direct application, so a later
              guard on that name can be traced back to the call it launders.
              Any [A.EApp] qualifies — [alias_withdrawal_cause] re-checks the
              recorded RHS against the withdrawn spelling and the obligation's
              own subject, so recording a non-measure application costs nothing
              but the entry. *)
           let lets' =
             match e with
             | A.ELet (b, _) ->
               let names = pat_binders b.A.bind_pat in
               let lets = launder_shadow lets names in
               (match b.A.bind_pat, b.A.bind_expr with
                | A.PatVar n, (A.EApp _ as rhs) -> (n.A.txt, rhs) :: lets
                (* A `let n = a` where `a` is ITSELF a laundered name copies the
                   underlying application forward under the new name, so the chain
                   extends to any depth without extra lookup machinery at use time.
                   `lets` is most-recent-first and already shadow-disciplined by
                   [launder_shadow] above, so `List.assoc_opt` finds the live entry. *)
                | A.PatVar n, A.EVar { A.txt = y; _ } ->
                  (match List.assoc_opt y lets with
                   | Some rhs -> (n.A.txt, rhs) :: lets
                   | None -> lets)
                | _ -> lets)
             | A.ELetFn (n, _, _, _, _) -> launder_shadow lets [ n.A.txt ]
             | _ -> lets
           in
           let sc' =
             match e with
             (* An annotation that was NOT proved grants no fact — it is
                retired rather than admitted, so no later goal can be
                discharged by a premise this binding failed to establish. *)
             | A.ELet (b, _) when annot_proved = Some false ->
               scope_shadow sc (pat_binders b.A.bind_pat)
             | A.ELet (b, _) -> scope_add_binding ~postcond:(postcond_of ctx defs) sc b
             | _ -> sc
           in
           let re' = match e with A.ELet (b, _) -> recenv_add_binding re b | _ -> re in
           let cb' =
             match e with
             | A.ELet (b, _) -> cb_add_binding ctx defs cb b
             | A.ELetFn (n, _, _, _, _) -> cb_shadow cb [ n.A.txt ]
             | _ -> cb
           in
           (ctx', path', lets', sc', re', cb'))
         (ctx, path, lets, sc, re, cb) es)
  | A.ELet (b, _) -> go b.A.bind_expr
  | A.ELam (ps, body, _) ->
    let names = List.map (fun (p : A.param) -> p.A.param_name.A.txt) ps in
    let ctx = local_shadow ctx names in
    visit ~root errctx defs ctx (path_shadow path names) (launder_shadow lets names)
      (List.fold_left scope_add_param sc ps)
      (List.fold_left recenv_add_param re ps)
      (List.fold_left cb_add_param cb ps)
      body
  | A.ELetFn (n, ps, _, body, _) ->
    let names = n.A.txt :: List.map (fun (p : A.param) -> p.A.param_name.A.txt) ps in
    let sc = scope_shadow sc [ n.A.txt ] in
    let re = recenv_shadow re [ n.A.txt ] in
    let cb = cb_shadow cb [ n.A.txt ] in
    let ctx = local_shadow ctx names in
    visit ~root errctx defs ctx (path_shadow path names) (launder_shadow lets names)
      (List.fold_left scope_add_param sc ps)
      (List.fold_left recenv_add_param re ps)
      (List.fold_left cb_add_param cb ps)
      body
  | A.EMatch (subj, branches, _) ->
    go subj;
    ignore
    @@ List.fold_left
      (fun (earlier : A.branch list) (br : A.branch) ->
        let binders = pat_binders br.A.branch_pat in
        (* A pattern binder shadows a same-named refined outer local. *)
        let sc = scope_shadow sc binders in
        (* …and a same-named fact in the path context, for the same reason. *)
        let path = path_shadow path binders in
        (* …and a same-named laundered-guard fact — see [launder]. *)
        let lets = launder_shadow lets binders in
        (* …and a same-named callback/alias fact — see [cbenv]. *)
        let cb = cb_shadow cb binders in
        (* …and a same-named GLOBAL FUNCTION, for callee resolution. *)
        let ctx = local_shadow ctx binders in
        (* …and a same-named record IDENTITY, so an inner binder is not
           reflected as the outer record's SMT constant.  A bare `PatVar`
           binder on a record-typed variable scrutinee then re-enters the env
           under the NEW name: `match d do c -> …` makes `c` the same value as
           `d`, so sharing one constant is correct.  Looked up in the OUTER env
           on purpose — `match c do c -> …` must find the pre-shadow entry. *)
        let re_outer = re in
        let re = recenv_shadow re binders in
        let re =
          match subj, br.A.branch_pat with
          | A.EVar s, A.PatVar n ->
            (match List.assoc_opt s.A.txt re_outer with
             | Some sort -> (n.A.txt, sort) :: re
             | None -> re)
          | _ -> re
        in
        (* A record DESTRUCTURED OUT OF AN ADT PAYLOAD — `match b do Wrap(c) ->
           …` where `Wrap` carries a record.  Such a binder is a record-typed
           variable exactly like a record-typed PARAMETER, and [recenv] is what
           lets a field guard (`if c.port <= 0 do …`) attach to it; without an
           entry the guard's `c.port` translated to nothing and every call
           taking `c` was skipped.  The plain-parameter spelling of the same
           code was checked, so the two disagreed.

           The positional field's SMT sort is already recorded by ADT
           registration, and [is_record_sort] distinguishes a record from a
           plain variant — only records have selectors to project.  Only a
           DIRECT `PatVar` sub-pattern is registered; a deeper nested pattern
           has no single name to attach the identity to and is left alone
           (silence).

           Retirement needs no new code: the entry is added AFTER
           [recenv_shadow] above, and every binding construct inside the arm
           already retires a name it rebinds from [recenv].  Like a parameter's
           entry it carries NO predicate — the constant is wholly
           unconstrained, so on its own it proves nothing in either direction
           and the call stays skipped unless the path context settles it. *)
        let re =
          match br.A.branch_pat with
          | A.PatCon (ctor, subpats) ->
            let sorts = try Hashtbl.find ctor_field_sorts ctor.A.txt with Not_found -> [] in
            if List.length subpats <> List.length sorts then re
            else
              List.fold_left2
                (fun re sub srt ->
                  match sub, srt with
                  | A.PatVar n, Smt.SData s when is_record_sort s -> (n.A.txt, s) :: re
                  | _ -> re)
                re subpats sorts
          | _ -> re
        in
        let p = match br.A.branch_guard with Some g -> (g, false) :: path | None -> path in
        (* Constructor-tag narrowing.  Inside a `Ctor(…) ->` arm a VARIABLE
           scrutinee is known to carry that tag, so we push the synthetic path
           condition `is_Ctor(s)` — an ordinary predicate expression, which
           reaches the solver through the existing [smt_of] translation with no
           new plumbing.  Three guards keep it sound:
             - the scrutinee must be a bare variable (any other expression has
               no stable name to attach the fact to → no fact),
             - the pattern head must be an unambiguous registered constructor,
             - the arm must not REBIND the scrutinee's name: matching `y` with
               `Some(x) ->` says nothing about the fresh `x`, so a narrowing
               recorded against a shadowed name would be a false positive. *)
        let p =
          match subj, br.A.branch_pat with
          | A.EVar s, A.PatCon (ctor, _)
            when sort_of_ctor ctor.A.txt <> None && not (List.mem s.A.txt binders) ->
            let sp = s.A.span in
            let tester =
              A.EApp
                ( A.EVar { A.txt = "is_" ^ ctor.A.txt; A.span = sp }
                , [ A.EVar { A.txt = s.A.txt; A.span = sp } ]
                , sp )
            in
            (tester, false) :: p
          | _ -> p
        in
        (* A Bool-literal arm — `match cond do true -> … false -> … end`.
           This is the same branch on the same Bool as an [A.EIf], so it earns
           the same fact, and it is recorded in the same (condition, negated)
           form the [A.EIf] arm below uses: the `true` arm learns the
           scrutinee holds, the `false` arm learns its negation.

           Unlike the constructor narrowing above this needs NO stable name
           for the scrutinee — a path condition is an arbitrary expression, so
           an inline `match a >= b do` works exactly as `if a >= b do` does.
           Gating on the PATTERN being a Bool literal is what keeps it typed:
           only a Bool scrutinee can be matched against `true`/`false`. *)
        let p =
          match br.A.branch_pat with
          | A.PatLit (A.LitBool bv, _) -> (subj, not bv) :: p
          | _ -> p
        in
        (* Arm-order exclusion.  Reaching this arm means every EARLIER arm
           failed to match, so for each of those whose failure is decided purely
           by the tag ([arm_excludes_tag]), the scrutinee is known NOT to carry
           it.  This is what gives the `_` arm of

             match xs do Nil -> Err(…) | _ -> Ok(mean(xs)) end

           the fact `not is_Nil(xs)` — the shape every "safe wrapper" in a
           standard library has, and previously a permanent source of unprovable
           debt.  Same three guards as the positive narrowing above, plus: an
           earlier arm with a guard, or with a refutable sub-pattern, licenses
           nothing, because it can fail with the tag still matching. *)
        let p =
          match subj with
          | A.EVar s when not (List.mem s.A.txt binders) ->
            List.fold_left
              (fun p (prev : A.branch) ->
                match arm_excludes_tag prev with
                | Some ctor when sort_of_ctor ctor <> None ->
                  let sp = s.A.span in
                  let tester =
                    A.EApp
                      ( A.EVar { A.txt = "is_" ^ ctor; A.span = sp }
                      , [ A.EVar { A.txt = s.A.txt; A.span = sp } ]
                      , sp )
                  in
                  (tester, true) :: p
                | _ -> p)
              p earlier
          | _ -> p
        in
        (* Arm-order exclusion for Bool-literal arms, the counterpart of the
           tag exclusion above: reaching this arm means every earlier
           `true ->` / `false ->` failed to match, so the scrutinee is known
           NOT to be that literal — which is what gives the `_` arm of
           `match cond do true -> … _ -> … end` the negated guard, exactly as
           an `if`'s else-branch gets it.  An earlier arm carrying a GUARD
           licenses nothing: it can fail with the literal still matching. *)
        let p =
          List.fold_left
            (fun p (prev : A.branch) ->
              match prev.A.branch_pat, prev.A.branch_guard with
              | A.PatLit (A.LitBool bv, _), None -> (subj, bv) :: p
              | _ -> p)
            p earlier
        in
        (* Nested-pattern exclusion over the CURRENT arm's binder.  An earlier
           unguarded arm with the same head and a single nullary refutable
           sub-pattern at index [i] ([arm_excludes_nested]) means that,
           having failed to match there, the scrutinee's field [i] is not
           that nullary constructor — so if THIS arm's own sub-pattern at
           [i] is a bare variable binder, that binder itself carries the
           exclusion.  This is what gives `Cons(_, t)` after `Cons(x, Nil)`
           the fact `not is_Nil(t)`, pushed over the binder rather than the
           scrutinee since [t] is new in this arm and has no path/scope
           identity of its own until here — must therefore run AFTER the
           binder-shadowing above, and is independent of the scrutinee-level
           exclusion above (that one requires a bare-variable SCRUTINEE;
           this one requires a bare-variable SUB-PATTERN). *)
        let p =
          match br.A.branch_pat with
          | A.PatCon (cur, cur_subs) ->
            List.fold_left
              (fun p (prev : A.branch) ->
                match arm_excludes_nested prev with
                | Some (ctor, i, d) when cur.A.txt = ctor && sort_of_ctor d <> None ->
                  (match List.nth_opt cur_subs i with
                   | Some (A.PatVar t) ->
                     let sp = t.A.span in
                     let tester =
                       A.EApp
                         ( A.EVar { A.txt = "is_" ^ d; A.span = sp }
                         , [ A.EVar { A.txt = t.A.txt; A.span = sp } ]
                         , sp )
                     in
                     (tester, true) :: p
                   | _ -> p)
                | _ -> p)
              p earlier
          | _ -> p
        in
        visit ~root errctx defs ctx p lets sc re cb br.A.branch_body;
        br :: earlier)
      [] branches
  | A.EIf (c, t, e, _) ->
    go c;
    go_path ((c, false) :: path) t;
    go_path ((c, true) :: path) e
  | A.ECond (arms, _) ->
    List.iter (fun (c, b) -> go c; go_path ((c, false) :: path) b) arms
  | A.ERecord (fields, _) -> List.iter (fun (_, v) -> go v) fields
  | A.ERecordUpdate (r, fields, _) -> go r; List.iter (fun (_, v) -> go v) fields
  | A.EField (r, _, _) -> go r
  | A.EPipe (a, b, _) -> go a; go b
  | A.EAnnot (e, _, _) | A.ESpawn (e, _) | A.EAssert (e, _) | A.ESigil (_, e, _) -> go e
  | A.ESend (a, b, _) -> go a; go b
  | A.ELetQ (p, e1, e2, _) | A.ELetStar (p, e1, e2, _) ->
    go e1;
    (* `let? p = e1` (and `let* p = e1`, same shape) binds p's names in the
       Ok payload / flat_map callback before continuing into e2 — a binding
       construct exactly like ELet/ELam/EMatch, so it must shadow any
       same-named outer refined local before e2 is visited. *)
    let binders = pat_binders p in
    let sc = scope_shadow sc binders in
    let re = recenv_shadow re binders in
    let cb = cb_shadow cb binders in
    let ctx = local_shadow ctx binders in
    visit ~root errctx defs ctx (path_shadow path binders) (launder_shadow lets binders)
      sc re cb e2
  | A.EDbg (Some e, _) -> go e
  | A.ELit _ | A.EVar _ | A.EHole _ | A.EResultRef _ | A.EDbg (None, _) -> ()

(* =================================================================
   §20 Refinement-placement warnings
   ================================================================= *)

(* Render a dotted MODULE path (`List.length`, `M.N.f`, …) back to a string, or
   [None] for anything else.  Mirrors [desugar_expr]'s [flatten_module_path]
   (`lib/desugar/desugar.ml`) exactly, which is the ground truth for what the
   parser produces for a dotted reference: an uppercase module segment parses
   as a zero-arg `A.ECon`, and the chain BOTTOMS OUT there.

   A bare `A.EVar` receiver is deliberately NOT accepted. `c.cb(1)` is a record
   FIELD call on a value, not a qualified call on a module; flattening it would
   report it as "a qualified call" and suggest the field name as a "bare
   spelling", both of which are false. It enforces nothing either way (`smt_of`
   has no arm for an applied field access), but a wrong explanation costs more
   than silence here. *)
let rec qualified_name (e : A.expr) : string option =
  match e with
  | A.ECon (mod_name, [], _) -> Some mod_name.A.txt
  | A.EField (r, { A.txt = n; _ }, _) ->
    Option.map (fun base -> base ^ "." ^ n) (qualified_name r)
  | _ -> None

(* The bare measure a QUALIFIED spelling should be rewritten to, independent of
   whether that alias is currently withdrawn.

   Deliberately NOT [measure_alias]: that function is gated on the
   stdlib-ownership refs ([list_length_is_stdlib] &c), so it answers "does this
   spelling alias `len` right now". The question here is the different one
   "what should the author write instead", whose answer is `len` either way —
   a withdrawn alias is a separate problem with its own attribution machinery
   ([withdrawals]), not a reason to send the author somewhere else.

   Deriving the suggestion from the last dotted segment instead — the obvious
   shortcut — hands back `length`, which is not predicate vocabulary: following
   that advice merely swaps this warning for the unknown-name one, and the
   contract still enforces nothing. *)
let qualified_measure_spelling (qname : string) : string option =
  match qname with "List.length" | "String.byte_size" -> Some "len" | _ -> None

(* ── Predicate-vocabulary warning ──────────────────────────────────────────
   A refinement predicate that calls a name [known_predicate_fn] does not
   recognize is never reflected into an SMT query — the definite-failure
   stance simply skips it, so the contract silently enforces nothing.  This
   walk finds every `{T | pred}` in the module (parameter, return, and local
   `let`-binding refinements — anywhere `A.TyRefine` can appear) and warns
   once per unrecognized applied name.

   Must run AFTER [registered_measures] is populated (see [check_module]):
   otherwise every user `@[measure]` looks unrecognized and warns spuriously.

   [warn_qualified_call] is the shared remedy-builder for an unresolved
   dotted spelling [qname], reached whether it arrives as an un-flattened
   `EField` chain or as a dotted `EVar` [Desugar.desugar_ty] already
   flattened but that still failed [known_predicate_fn] (alias withdrawn, or
   simply not a recognized qualified spelling). *)
let warn_qualified_call (errctx : Err.ctx) ~(span : A.span) (qname : string) : unit =
  let remedy =
    match qualified_measure_spelling qname with
    | Some bare -> Printf.sprintf " Use the bare spelling `%s` instead." bare
    | None ->
      " A predicate can only call the bare measure vocabulary — `len`, or an \
       `@[measure]` function by its bare name."
  in
  Err.warning errctx ~span
    (Printf.sprintf
       "`%s` is a qualified call inside a refinement predicate. This spelling is \
        never reflected here, so the refinement enforces nothing.%s"
       qname remedy)

let warn_predicate_expr (errctx : Err.ctx) (e : A.expr) : unit =
  let rec go (e : A.expr) =
    match e with
    | A.EApp (A.EVar { A.txt = f; _ }, args, span) ->
      if not (known_predicate_fn f) then begin
        if String.contains f '.' then
          (* [Desugar.desugar_ty] (Task 8) now flattens a MODULE-PATH call head
             (`List.length(_)`) in predicate position into this dotted `EVar`
             the SAME way ordinary call heads are flattened — so a live alias
             is already reflected by the time [known_predicate_fn] is
             consulted, and this branch is reached ONLY when the alias is
             unavailable (withdrawn by a competing binding, or simply not a
             recognized qualified spelling at all).  Route it through the
             SAME remedy as an unresolved qualified call so a withdrawn
             `List.length` still points at `len`, instead of degrading to the
             generic "not a measure" message below. *)
          warn_qualified_call errctx ~span f
        else
          Err.warning errctx ~span
            (Printf.sprintf
               "`%s` is not a measure or known predicate, so this refinement is not checked. \
                Annotate the function `@[measure]`, or use a supported predicate."
               f)
      end;
      List.iter go args
    (* A qualified call in call position that ISN'T already flattened to a
       dotted `EVar` by [Desugar.desugar_ty] — e.g. a receiver that is itself
       a call (`f(x).g(y)`), which [Desugar.flatten_pred_quals] deliberately
       does not rewrite (mirrors [Desugar.desugar_expr]'s own `EField` arm,
       which only flattens a chain bottoming out at a bare module `ECon`). *)
    | A.EApp ((A.EField _ as fhd), args, span) ->
      (match qualified_name fhd with
       | Some qname -> warn_qualified_call errctx ~span qname
       | None -> ());
      go fhd;
      List.iter go args
    | A.EApp (f, args, _) -> go f; List.iter go args
    | A.ETuple (es, _) | A.ECon (_, es, _) | A.EAtom (_, es, _) -> List.iter go es
    | A.EAnnot (e, _, _) -> go e
    | A.ELit _ | A.EVar _ -> ()
    | _ -> ()
  in
  go e

let rec warn_predicate_ty (errctx : Err.ctx) (t : A.ty) : unit =
  match t with
  | A.TyRefine (base, _binder, pred) ->
    warn_predicate_ty errctx base;
    warn_predicate_expr errctx pred
  | A.TyCon (_, args) -> List.iter (warn_predicate_ty errctx) args
  | A.TyArrow (a, b) -> warn_predicate_ty errctx a; warn_predicate_ty errctx b
  | A.TyTuple ts -> List.iter (warn_predicate_ty errctx) ts
  | A.TyRecord fs -> List.iter (fun (_, t) -> warn_predicate_ty errctx t) fs
  | A.TyLinear (_, t) -> warn_predicate_ty errctx t
  | A.TyChan _ | A.TyVar _ | A.TyNat _ | A.TyNatOp _ -> ()

(* ── Interface-signature refinement warning ────────────────────────────────
   A refinement written in an `interface` method signature (`A.method_decl`'s
   [md_ty]) is inert.  NOTHING in this pass reads [md_ty]: [visit_decl]'s
   `DInterface` arm descends only into [md_default], and the two other walks
   that touch [iface_methods] ([stdlib_member_defs_ok], [bare_builtin_undefined])
   read method NAMES only.  Nor does the front end carry it anywhere:
   [Desugar.inject_defaults] synthesises a default method's `fn_def` with
   `fn_ret_ty = None` and parameters taken from the default LAMBDA (which
   carries no `param_ty`), so even the one place an interface signature turns
   into code drops the predicate on the floor.

   So it obliges no call site AND lets no body assume anything — a missing
   check, not an unsound one.  The defect is that it is silent: it parses,
   typechecks, and reads exactly like a working contract.

   The remedy is deliberately stated for BOTH positions, because they are
   enforced under different conditions and naming only the parameter one would
   be wrong advice for a return refinement:
     · a RETURN refinement on an `impl` method is always checked — [visit_fn]
       calls [check_fn_post] unconditionally;
     · a PARAMETER refinement is enforced only when [adoptable_impl_methods]
       adopts the method name (exactly one `impl` defines it and no top-level
       `fn` owns it); otherwise [visit_decl] walks the body with the parameter
       refinements STRIPPED and no caller is obliged.
   Saying "put it on the impl parameter" flatly would send an author with an
   ambiguous method name from one silent no-op to another.

   The caller has already established [ty_has_refinement m.md_ty] and branches
   on it.  [strict] is the module's own `cap verified` status — NOT read from
   the [strict_verified] ref, which by the time [warn_predicate_decls] runs
   has already been restored by [visit_decls]'s [Fun.protect] (it is scoped to
   the walk, and this vocabulary pass runs after the walk finishes).  The
   caller threads the flag through explicitly for that reason; see
   [warn_predicate_decls]. `cap verified` promises "if it compiles, it is
   proved" — a contract that provably enforces nothing is exactly the shape
   that promise exists to rule out, so under `cap verified` this is an error,
   matching [check_call]/[check_post]'s own escalation. *)
let warn_iface_method_refinement (errctx : Err.ctx) ~(strict : bool) (m : A.method_decl) : unit =
  let msg =
    Printf.sprintf
      "the interface signature of `%s` carries a refinement, which enforces \
       nothing: an interface method signature is never read by the refinement \
       checker, so no call site is obliged by this predicate and no body may \
       assume it. Write the refinement on the corresponding `impl` method's own \
       signature instead — a refinement on its return type is always checked, \
       and one on a parameter is enforced when the method name is unambiguous \
       (exactly one `impl` defines it and no top-level `fn` shares the name)."
      m.A.md_name.A.txt
  in
  if strict then Err.error errctx ~span:m.A.md_name.A.span msg
  else Err.warning errctx ~span:m.A.md_name.A.span msg

(* ── `sig` signature refinement warning ────────────────────────────────────
   A refinement in a `sig` module signature (`A.sig_def`'s [sig_fns]) is inert
   for the same structural reason the interface one is: nothing in this pass
   reads [sig_fns].  [visit_decl] has no `DSig` arm that descends, and the
   signature is an ASCRIPTION — it constrains what a module exports, not what
   any particular function body does, so there is no `fn_def` for the predicate
   to attach to and no call site that consults it.

   The remedy is the module's own `fn` definition, where a parameter refinement
   obliges callers and a return refinement is discharged against the body.

   Emits unconditionally: the caller has already established
   [ty_has_refinement]. *)
let warn_sig_fn_refinement (errctx : Err.ctx) (sig_name : A.name) (fn_name : A.name) : unit =
  Err.warning errctx ~span:fn_name.A.span
    (Printf.sprintf
       "the `sig %s` signature of `%s` carries a refinement, which enforces \
        nothing: a `sig` signature is never read by the refinement checker, so \
        no call site is obliged by this predicate and no body may assume it. \
        Write the refinement on the module's own `fn` definition instead, where \
        a parameter refinement obliges callers and a return refinement is \
        checked against the body."
       sig_name.A.txt fn_name.A.txt)

(* ── `extern` signature refinement warning ─────────────────────────────────
   A refinement on an `extern` function's parameter or return type is inert,
   and here the reason is not merely that the pass does not walk it — it is
   that it CANNOT be honoured.  The callee is foreign C, so:
     · a RETURN refinement is an unverifiable claim: there is no March body to
       discharge it against, and assuming it would be UNSOUND rather than
       merely missing;
     · a PARAMETER refinement has a March-side call site that could in
       principle be obliged, but the extern declaration is not a `fn_def` and
       registers no contract, so today it obliges nothing.
   The remedy is a March wrapper: put the parameter refinement on the wrapper,
   where callers are obliged, and CHECK the foreign result at runtime rather
   than asserting it in a type.

   Emits unconditionally: the caller has already established
   [ty_has_refinement]. *)
let warn_extern_fn_refinement (errctx : Err.ctx) (ef : A.extern_fn) : unit =
  Err.warning errctx ~span:ef.A.ef_name.A.span
    (Printf.sprintf
       "the `extern` signature of `%s` carries a refinement, which enforces \
        nothing: the callee is not March code, so the refinement checker \
        obliges no caller with it and can discharge no claim about the value it \
        returns. Wrap the extern in a March `fn` and write the parameter \
        refinement there, where call sites are obliged; a foreign RESULT cannot \
        be verified at all and must be checked at runtime rather than asserted \
        in its type."
       ef.A.ef_name.A.txt)

let rec warn_predicate_expr_tys (errctx : Err.ctx) (e : A.expr) : unit =
  let ge = warn_predicate_expr_tys errctx in
  match e with
  | A.ELit _ | A.EVar _ | A.EHole _ | A.EResultRef _ -> ()
  | A.EApp (f, args, _) -> ge f; List.iter ge args
  | A.ECon (_, es, _) | A.EAtom (_, es, _) | A.ETuple (es, _) -> List.iter ge es
  | A.ELam (ps, body, _) ->
    List.iter (fun (p : A.param) -> Option.iter (warn_predicate_ty errctx) p.A.param_ty) ps;
    ge body
  | A.EBlock (es, _) -> List.iter ge es
  | A.ELet (b, _) ->
    Option.iter (warn_predicate_ty errctx) b.A.bind_ty;
    ge b.A.bind_expr
  | A.EMatch (e, brs, _) ->
    ge e;
    List.iter
      (fun (br : A.branch) ->
        Option.iter ge br.A.branch_guard;
        ge br.A.branch_body)
      brs
  | A.ERecord (fs, _) -> List.iter (fun (_, e) -> ge e) fs
  | A.ERecordUpdate (e, fs, _) -> ge e; List.iter (fun (_, e) -> ge e) fs
  | A.EField (e, _, _) -> ge e
  | A.EIf (c, t, e, _) -> ge c; ge t; ge e
  | A.ECond (arms, _) -> List.iter (fun (c, b) -> ge c; ge b) arms
  | A.EPipe (a, b, _) -> ge a; ge b
  | A.EAnnot (e, t, _) -> ge e; warn_predicate_ty errctx t
  | A.ESend (a, b, _) -> ge a; ge b
  | A.ESpawn (e, _) -> ge e
  | A.EDbg (eo, _) -> Option.iter ge eo
  | A.ELetFn (_, ps, ret_ty, body, _) ->
    List.iter (fun (p : A.param) -> Option.iter (warn_predicate_ty errctx) p.A.param_ty) ps;
    Option.iter (warn_predicate_ty errctx) ret_ty;
    ge body
  | A.ELetQ (_, e1, e2, _) | A.ELetStar (_, e1, e2, _) -> ge e1; ge e2
  | A.EAssert (e, _) -> ge e
  | A.ESigil (_, e, _) -> ge e

(* Exhaustive over [A.decl], for the same reason the obligation walks are: the
   `| _ -> ()` this replaced meant the "not a measure or known predicate"
   warning never fired for a refinement written on an `impl` or `interface`
   method — precisely where the widened checks now CONSUME such predicates, so
   an unrecognized one there was both unchecked and unmentioned. *)
(* Whether [decls] itself declares `cap verified` — the same test
   [visit_decls] applies, extracted so [warn_predicate_decls] (which runs
   AFTER [visit_decls] has already restored [strict_verified], see that
   function's [Fun.protect]) can recompute the same fact independently rather
   than reading a ref that no longer holds it. *)
let decls_declare_verified (decls : A.decl list) : bool =
  List.exists (function A.DOpts (opts, _) -> List.mem "verified" opts | _ -> false) decls

(* [strict]: whether the ENCLOSING decl list (module or `describe` block) is
   under `cap verified`.  Mirrors [strict_verified]'s own scoping rule from
   [visit_decls]: a nested `mod` does not inherit its parent's `cap verified`
   and recomputes from its own decls (below); a `describe` block is not a
   module and inherits the flag unchanged, matching [visit_decl]'s own
   [visit_group] treatment of `DDescribe`. *)
let rec warn_predicate_decls (errctx : Err.ctx) ~(strict : bool) (decls : A.decl list) : unit =
  let warn_fn (fd : A.fn_def) =
    Option.iter (warn_predicate_ty errctx) fd.A.fn_ret_ty;
    List.iter
      (fun (c : A.fn_clause) ->
        List.iter
          (function
            | A.FPNamed p | A.FPDefault (p, _) ->
              Option.iter (warn_predicate_ty errctx) p.A.param_ty
            | A.FPPat _ -> ())
          c.A.fc_params;
        warn_predicate_expr_tys errctx c.A.fc_body)
      fd.A.fn_clauses
  in
  let expr = warn_predicate_expr_tys errctx in
  List.iter
    (function
      | A.DFn (fd, _) -> warn_fn fd
      | A.DMod (_, _, ds, _) -> warn_predicate_decls errctx ~strict:(decls_declare_verified ds) ds
      | A.DDescribe (_, ds, _) -> warn_predicate_decls errctx ~strict ds
      | A.DImpl (idf, _) -> List.iter (fun (_, fd) -> warn_fn fd) idf.A.impl_methods
      | A.DInterface (idf, _) ->
        List.iter
          (fun (m : A.method_decl) ->
            (* Either the signature carries a refinement — in which case the
               whole thing is inert and [warn_iface_method_refinement] says so —
               or it does not, in which case [warn_predicate_ty] has nothing to
               find.  Running BOTH would append "annotate the function
               `@[measure]`" to a signature where no annotation can help:
               following that advice leaves the contract enforcing nothing just
               the same, and a misleading remedy costs more here than a missing
               one.  The vocabulary warning still fires once the predicate is
               moved to the `impl` method, which is where it can act. *)
            if ty_has_refinement m.A.md_ty then warn_iface_method_refinement errctx ~strict m
            else warn_predicate_ty errctx m.A.md_ty;
            (* A DEFAULT body is real code; it is walked as such and is not
               part of the signature this warning is about. *)
            Option.iter expr m.A.md_default)
          idf.A.iface_methods
      | A.DLet (_, b, _) ->
        Option.iter (warn_predicate_ty errctx) b.A.bind_ty;
        expr b.A.bind_expr
      | A.DActor (_, _, ad, _) ->
        expr ad.A.actor_init;
        List.iter (fun (h : A.actor_handler) -> expr h.A.ah_body) ad.A.actor_handlers;
        Option.iter expr ad.A.actor_invariant
      | A.DApp (app, _) ->
        expr app.A.app_body;
        Option.iter expr app.A.app_on_start;
        Option.iter expr app.A.app_on_stop
      | A.DTest (t, _) -> expr t.A.test_body
      | A.DSetup (e, _) | A.DSetupAll (e, _) -> expr e
      (* `DSig` and `DExtern` used to sit in the "not walked" list below under
         the label "inert: no type annotation or expression that can carry a
         refinement predicate".  That label was FALSE for both and was
         demonstrated so by probe: `sig Store do fn put : Int -> {Int | _ > 0}
         end` exited 0 with no diagnostic at all.  Both are now walked, on the
         same footing as `DInterface` — same shape, same reason, and the same
         either/or between the inert-signature warning and the vocabulary one
         (running both would append "annotate the function `@[measure]`" to a
         position where no annotation can help). *)
      | A.DSig (sig_name, sd, _) ->
        List.iter
          (fun ((fn_name : A.name), (t : A.ty)) ->
            if ty_has_refinement t then warn_sig_fn_refinement errctx sig_name fn_name
            else warn_predicate_ty errctx t)
          sd.A.sig_fns
      | A.DExtern (ed, _) ->
        List.iter
          (fun (ef : A.extern_fn) ->
            let tys = ef.A.ef_ret_ty :: List.map snd ef.A.ef_params in
            if List.exists ty_has_refinement tys then warn_extern_fn_refinement errctx ef
            else List.iter (warn_predicate_ty errctx) tys)
          ed.A.ext_fns
      (* ── Not walked.  Named so a new decl form breaks the build. ──
         Genuinely inert: none of these carries a type annotation or expression
         that can hold a refinement predicate.  Do not re-derive that claim by
         eyeballing the list — it was load-bearing and wrong for `DSig`/`DExtern`
         until they were moved out of it above.  Probe a candidate before adding
         it here. ── *)
      | A.DType _ | A.DAlwaysLinearType _  (* refinements in a type DEFINITION
                                              are checked where they are used *)
      | A.DProtocol _ | A.DTransitions _
      | A.DNeeds _ | A.DProofCap _ | A.DOpts _
      | A.DDeriving _ | A.DSatisfy _       (* desugared into DImpl before this *)
      | A.DUse _ | A.DAlias _ -> ())
    decls

(* =================================================================
   §21 The declaration walk
   ================================================================= *)

(* [assume_params:false] walks the body with the parameter refinements erased,
   so none of them can discharge anything.  Used for an `impl` method whose
   contract [collect_all_defs] could not adopt unambiguously: with no caller
   obliged to establish the predicate, assuming it inside the body would be
   assume-without-check.  The POSTcondition check still sees the original
   [fd] — a return refinement is verified, not assumed, and verifying it
   against the declared parameters is exactly right. *)
let visit_fn ~root errctx defs ?(assume_params = true) (ctx : rctx) (fd : A.fn_def) : unit =
  let is_trusted = List.mem "trusted" fd.A.fn_attrs in
  (* `@[trusted]` outside `cap verified` changes no behaviour at all — [note]
     only consults [trusted_fn] inside the [strict_verified] escalation
     branch.  An attribute that silently does nothing is exactly the failure
     mode this subsystem keeps producing, so say so. *)
  if is_trusted && not !strict_verified then
    Err.warning errctx ~span:fd.A.fn_name.A.span
      (Printf.sprintf
         "`@[trusted]` on `%s` has no effect here: this function is not inside \
          a `cap verified` module, so there is no escalation for it to \
          suppress. Add `cap verified` to this module, or remove the attribute."
         fd.A.fn_name.A.txt);
  (* Scoped to exactly this function, mirroring [strict_verified]'s own
     save/restore around a decl list — a nested `fn` (there is no such thing
     in March, but a fresh call into [visit_fn] for a sibling clearly must not
     inherit this) never sees a stale `true` left behind by a caller. *)
  let saved_trusted = !trusted_fn in
  let saved_enclosing = !enclosing_fn in
  trusted_fn := is_trusted;
  enclosing_fn := Some fd;
  (match !enclosing_fn_probe with
   | Some probe -> probe fd
   | None -> ());
  Fun.protect
    ~finally:(fun () ->
      trusted_fn := saved_trusted;
      enclosing_fn := saved_enclosing)
    (fun () ->
    check_fn_post ~root errctx fd;
    let walked = if assume_params then fd else strip_param_refinements fd in
    List.iter
      (fun (c : A.fn_clause) ->
        let sc = List.fold_left scope_add_fnparam [] c.A.fc_params in
        let re = List.fold_left recenv_add_fnparam [] c.A.fc_params in
        let cb = List.fold_left cb_add_fnparam [] c.A.fc_params in
        (* A PARAMETER named like a module-level function shadows it for callee
           resolution inside this body too — see [local_shadow]. *)
        let ctx = local_shadow ctx (List.concat_map fnparam_binders c.A.fc_params) in
        let path = match c.A.fc_guard with Some g -> [ (g, false) ] | None -> [] in
        visit ~root errctx defs ctx path [] sc re cb c.A.fc_body)
      walked.A.fn_clauses)

let rec visit_decls ~root errctx defs (ctx : rctx) (decls : A.decl list) : unit =
  (* Gather this scope's aliases/uses first so every function in the module sees
     them (matches lexical, module-wide visibility; inner modules inherit). *)
  let ctx =
    List.fold_left
      (fun ctx d ->
        match d with
        | A.DAlias (ad, _) -> { ctx with aliases = (ad.A.alias_name.A.txt, dotted ad.A.alias_path) :: ctx.aliases }
        | A.DUse (ud, _) ->
          (* [ctx.modpath] here is exactly the module that OWNS this `use` —
             [visit_decls]'s caller ([visit_decl]'s [A.DMod] arm) extends
             [modpath] BEFORE recursing into this fold, so tagging with the
             current [ctx.modpath] needs no extra plumbing.  See the [uses]
             field comment. *)
          { ctx with uses = (dotted ud.A.use_path, ud.A.use_sel, ctx.modpath) :: ctx.uses }
        | _ -> ctx)
      ctx decls
  in
  (* `cap verified` is scoped to the decl list that declares it — saved and
     restored here so a nested module neither inherits it nor leaks its own
     back out.  See [strict_verified] for why inheritance would be wrong. *)
  let saved_strict = !strict_verified in
  strict_verified := decls_declare_verified decls;
  (* Per-decl-list, for the same reason [strict_verified] is: a nested module is
     its own unit of advice, and one hint there should not silence the parent's
     (or vice versa). *)
  let saved_hinted = !unverified_hinted in
  unverified_hinted := false;
  Fun.protect
    ~finally:(fun () ->
      strict_verified := saved_strict;
      unverified_hinted := saved_hinted)
    (fun () -> List.iter (visit_decl ~root errctx defs ctx) decls)

(* One declaration.  Every constructor of [A.decl] is named — there is NO
   wildcard, deliberately: for years this walk descended only into [DFn] and
   [DMod] and ended in `| _ -> ()`, so `cap no_panic` said nothing about a
   division inside an `impl` method, a top-level `let`, or an actor handler,
   and accepted programs that divided by zero at runtime.  With the match
   exhaustive, a 25th decl form is a COMPILE ERROR here rather than a silent
   hole — the same guarantee [stdlib_member_defs_ok] already gives. *)
and visit_decl ~root errctx defs (ctx : rctx) (d : A.decl) : unit =
  (* A bare expression that is not a function clause: no parameters, no guard,
     hence empty scope/recenv/cbenv and an empty path condition. *)
  let visit_expr e = visit ~root errctx defs ctx [] [] [] [] [] e in
  (* Decls that merely group other decls (`describe`) must NOT go through
     [visit_decls]: that would re-derive [strict_verified] from the inner list,
     which carries no `cap` directive of its own, and so would silently drop
     the enclosing module's capability.  A `describe` block is part of its
     module's scope, so it inherits. *)
  let visit_group ds = List.iter (visit_decl ~root errctx defs ctx) ds in
  match d with
  | A.DFn (fd, _) -> visit_fn ~root errctx defs ctx fd
  | A.DMod (name, _, ds, _) ->
    let modpath = if ctx.modpath = "" then name.A.txt else ctx.modpath ^ "." ^ name.A.txt in
    visit_decls ~root errctx defs { ctx with modpath } ds
  (* Each method body is an ordinary function body — but its parameter
     refinements may be assumed ONLY if callers are obliged to establish them,
     i.e. only if [collect_all_defs] adopted this method's contract under the
     name a caller would write.  When it could not (a `fn` owns the name, or
     two impls of the same interface define the method), the body is walked
     with the refinements stripped rather than silently trusted. *)
  | A.DImpl (idf, _) ->
    List.iter
      (fun ((mn : A.name), (fd : A.fn_def)) ->
        let assume_params = contract_is_enforced ctx defs mn.A.txt (sig_of_fn fd) in
        visit_fn ~root errctx defs ~assume_params ctx fd)
      idf.A.impl_methods
  (* An interface's DEFAULT method body is real code; the signatures are not. *)
  | A.DInterface (idf, _) ->
    List.iter
      (fun (m : A.method_decl) -> Option.iter visit_expr m.A.md_default)
      idf.A.iface_methods
  | A.DLet (_, b, _) ->
    (* A top-level `let`'s own annotation must be CHECKED against its bound
       expression exactly as a block-level `let`'s is -- see
       [check_let_annotation] and its call site inside the [A.EBlock] case
       above.  There is no enclosing block to thread scope/path/lets/recenv
       through here, so all four start empty, matching [visit_expr]'s own
       convention just above; a top-level `let` also has no following
       sibling statements in THIS sense of "block", so there is nothing to
       admit the proved fact into afterward. *)
    ignore (check_let_annotation ~root errctx defs ctx [] [] [] [] b);
    visit_expr b.A.bind_expr
  | A.DActor (_, _, ad, _) ->
    visit_expr ad.A.actor_init;
    List.iter
      (fun (h : A.actor_handler) ->
        (* Handler parameters bind exactly like named function parameters, so
           their refinements must be in scope for the body. *)
        let ps = List.map (fun p -> A.FPNamed p) h.A.ah_params in
        let sc = List.fold_left scope_add_fnparam [] ps in
        let re = List.fold_left recenv_add_fnparam [] ps in
        let cb = List.fold_left cb_add_fnparam [] ps in
        let ctx = local_shadow ctx (List.concat_map fnparam_binders ps) in
        visit ~root errctx defs ctx [] [] sc re cb h.A.ah_body)
      ad.A.actor_handlers;
    (* The @invariant predicate is evaluated at run time like any other
       expression, so obligations inside it count. *)
    Option.iter visit_expr ad.A.actor_invariant
  | A.DApp (app, _) ->
    visit_expr app.A.app_body;
    Option.iter visit_expr app.A.app_on_start;
    Option.iter visit_expr app.A.app_on_stop
  | A.DTest (t, _) -> visit_expr t.A.test_body
  | A.DSetup (e, _) | A.DSetupAll (e, _) -> visit_expr e
  | A.DDescribe (_, ds, _) -> visit_group ds
  (* ── Inert: these decl forms carry no expression an obligation can arise in.
     Named individually so adding a 25th form breaks the build here. ────── *)
  | A.DType _                (* type definitions: types only, no terms *)
  | A.DAlwaysLinearType _    (* likewise, plus a linearity marker *)
  | A.DSig _                 (* module signature: names and types only *)
  | A.DProtocol _            (* session type: message types, no bodies *)
  | A.DTransitions _         (* state-machine edges: names of fns declared elsewhere *)
  | A.DExtern _              (* FFI declarations: signatures, bodies live in C *)
  | A.DNeeds _               (* capability manifest: capability paths *)
  | A.DProofCap _            (* proof-capability declaration: a name *)
  | A.DOpts _                (* the `cap` directive itself, read above *)
  | A.DDeriving _            (* desugared into DImpl before this pass runs *)
  | A.DSatisfy _             (* likewise desugared into DImpl *)
  | A.DUse _                 (* import: read into [ctx.uses] above *)
  | A.DAlias _ -> ()         (* alias: read into [ctx.aliases] above *)

(* =================================================================
   §22 Registration and stdlib-shape validation
   ================================================================= *)

(** Register ADT/record sorts for a list of declarations without running the full
    VC pass.  Called by [--check-migration] mode to prime the type tables before
    invoking [check_fn_post] on a synthesised migrate_state signature.

    Clears all tables first to avoid stale accumulation from prior calls.
    Must be called with the prior-version record decls (e.g. [RawRecord]) so
    that their selectors are available when check_post reflects field projections. *)
let register_types_for_check (decls : A.decl list) : unit =
  Hashtbl.clear adt_ctors;
  Hashtbl.clear ctor_field_sorts;
  Hashtbl.clear ctor_field_names;
  Hashtbl.clear axiom_measures;
  Hashtbl.clear measure_base_cases;
  Hashtbl.clear measure_scalar_field_dep;
  Hashtbl.clear measure_preamble_sorts;
  registered_measures := [];
  measure_nonneg := [];
  measure_preamble := "";
  type_preamble := "";
  register_builtin_adts ();
  register_adt_names decls;
  register_field_sorts decls;
  build_type_preamble ()

(** Entry point: check refinement preconditions across [m], emitting
    diagnostics into [errctx].  [root] is the project root for the VC cache. *)
(* Functions annotated `@[measure]` as (bare name, fn_def). *)
let rec collect_measure_fns (decls : A.decl list) : (string * A.fn_def) list =
  List.concat_map
    (function
      | A.DFn (fd, _) when List.mem "measure" fd.A.fn_attrs -> [ (fd.A.fn_name.A.txt, fd) ]
      | A.DMod (_, _, ds, _) -> collect_measure_fns ds
      | _ -> [])
    decls

(* Decide whether `List.length` in THIS compilation unit is the stdlib list
   length — the only reading under which aliasing it to `len` is a true fact.
   See [list_length_is_stdlib].

   The gate is deliberately COARSE.  A precise answer needs the lexical
   [resolve_call] resolver, which [smt_of] does not have in scope; and the
   asymmetry of the two errors is total — over-suppressing costs a missed
   proof (silence, the status quo ante), under-suppressing costs a FALSE
   POSITIVE on correct code.  So anything that even looks like a competing
   `List.length` withdraws the alias for the whole module.

   It cannot key on the module PATH.  bin/main.ml prepends the whole stdlib —
   including `mod List` — into every module it checks, so "reject any `mod
   List`" would disable the feature in production.  And the outer `mod Q` is
   the [module_] record rather than a decl, so a nested `mod List do fn length`
   lands at path `List.length` too, exactly like the stdlib's: the two are
   indistinguishable by name alone.

   What separates them is the SOURCE FILE the definition came from, tested
   against the identity the CALLER supplied in [stdlib_source_files].  It must
   NOT be inferred from the path's shape: an earlier revision of this gate
   asked for a parent directory named `stdlib`, which

     - disabled the feature outright in an installed March, where `stdlib/dune`
       ships the sources to `<prefix>/share/march` (parent `march`), and under
       any `MARCH_STDLIB` pointing elsewhere; and
     - accepted ANY file path ending `stdlib/list.march`, so a vendored or
       forked `List` under `MARCH_LIB_PATH` was taken for the real one and
       re-opened the false positive it was written to close.

     - `mod Q do mod List do fn length … end end`  -> not a stdlib file -> suppress
     - a vendored `MARCH_LIB_PATH` `mod List`      -> not a stdlib file -> suppress
     - the stdlib's own, whatever the layout       -> stdlib file       -> allow
     - no `List` module at all (the unit tests)    -> no defs           -> allow

   `alias Foo as List` and `use Some.List` can also make the spelling denote
   someone else's function, so either withdraws the alias too. *)
(* [is_stdlib_source_file] itself lives in [Refine_encode], beside the
   [stdlib_source_files] ref it reads — the promotion gate in [Refine_call]
   needs the same predicate and sits upstream of this file.  The reasoning
   above is about WHY the test is an identity rather than a path pattern, and
   applies wherever it is called from. *)

(* ── Glob imports: LOOK instead of assuming ────────────────────────────────
   `import X` / `use X.*` can only make a spelling denote something else if X
   actually PROVIDES the competing member.  An earlier revision of both gates
   below withdrew on the mere presence of a glob, on the reasoning that it
   might carry anything.  That is not merely coarse, it is fatal: bin/main.ml
   prepends the whole stdlib into every compilation unit and both gates are
   unit-global, so the single `import Process` in `stdlib/system.march`
   withdrew every alias for EVERY March program ever compiled — the feature
   was inert in production, and only a REJECT witness could notice (a skip
   exits 0, exactly like a proof).

   So resolve the glob's target and ask.  Resolution is purely syntactic over
   the declarations of the compilation unit that was handed to us, which is
   all the module structure this pass has; whenever it cannot answer — the
   path names a module not present in the unit, or the search runs out of fuel
   — the answer is `true`, i.e. WITHDRAW, exactly as before.  Precision is
   only ever added where the contents are actually in hand.

   Direction of doubt is unchanged and non-negotiable: over-suppressing costs
   a missed proof (silence); under-suppressing puts a wrong fact in the
   assumption set, which makes violations EASIER to prove and reports correct
   code — a false positive, this pass's cardinal sin. *)

(* Walk [path] down through nested `mod` declarations from [root]. *)
let find_module_decls (root : A.decl list) (path : A.name list) : A.decl list option =
  let rec descend ds = function
    | [] -> Some ds
    | (seg : A.name) :: rest ->
      let rec search = function
        | [] -> None
        | A.DMod (n, _, ds', _) :: _ when n.A.txt = seg.A.txt -> descend ds' rest
        | _ :: tl -> search tl
      in
      search ds
  in
  match path with [] -> None | _ -> descend root path

(* Does a glob import of the module at [path] bring a competitor into scope?

   [binds_decl] recognises a NON-`use` declaration of the target module that
   provides the thing (a nested `mod List`, a `fn string_byte_length`, …).
   [names_it] answers whether an explicit selector list names it, and
   [single_binds] whether a bare `use A.B` (no selector) binds it under its
   last segment.  A `use` INSIDE the target is followed transitively, since we
   cannot be sure March does not re-export it; [fuel] bounds that walk and its
   exhaustion, like any other unresolved case, withdraws. *)
let glob_import_competes ~(root : A.decl list) ~(unit_name : string)
    ~(binds_decl : A.decl -> bool) ~(names_it : A.name list -> bool)
    ~(single_binds : A.name list -> bool) (path : A.name list) : bool =
  (* A path may be written relative to the unit's own module (`import
     System.Process` from inside `mod System`), whose declarations ARE the
     root list rather than a `DMod` within it. *)
  let resolve p =
    match find_module_decls root p with
    | Some ds -> Some ds
    | None -> (
      match p with
      | (hd : A.name) :: tl when hd.A.txt = unit_name -> find_module_decls root tl
      | _ -> None)
  in
  let rec provides fuel ds =
    List.exists
      (fun d ->
        binds_decl d
        ||
        match d with
        | A.DDescribe (_, ds', _) -> provides fuel ds'
        | A.DUse (u, _) -> (
          match u.A.use_sel with
          | A.UseSingle -> single_binds u.A.use_path
          | A.UseNames xs -> names_it xs
          | A.UseExcept xs -> (not (names_it xs)) && glob fuel u.A.use_path
          | A.UseAll -> glob fuel u.A.use_path)
        | _ -> false)
      ds
  and glob fuel p =
    if fuel <= 0 then true
    else match resolve p with Some ds -> provides (fuel - 1) ds | None -> true
  in
  glob 4 path

(* Is the qualified spelling `<md>.<fn>` still the standard library's own?
   Parameterised over the pair so the `List.length` and `String.byte_size`
   aliases share one gate rather than two that can drift apart.

   ── THE INVARIANT (shared with [bare_builtin_undefined]) ───────────────────
   Ask only: can this declaration make the spelling `<md>.<fn>` denote a
   function that is not the stdlib's?  Two ways — DEFINE a member named [fn]
   inside a module named [md], or REBIND the bare segment [md] to some other
   module.  Everything that can do either must be named here.

   An earlier revision asked instead "is this an `A.DFn` inside a `DMod`?" and
   ended its walk in a `| _ -> ()` wildcard.  A competing member defined as a
   module-level `let`, or declared in an `extern` block, was therefore
   invisible: the alias stayed on, `List.length` was equated with `len`, the
   dead branch under a contradictory guard was treated as reachable, and
   CORRECT code was reported — a false positive, the one error this pass must
   never make.  That is the identical hole [bare_builtin_undefined] had closed
   for the bare spelling and this gate never inherited; hence the match below
   is EXHAUSTIVE over [A.decl] with no wildcard, so a new declaration form is a
   compile error here rather than a silent hole.  The arms that do nothing say
   so by name, and each is a claim that that form can neither define a member
   nor rebind a module name; check it rather than trusting it.

   [mod_name] is the ENCLOSING module's own name.  The entry module's
   declarations are top-level rather than a `DMod` — and bin/main.ml strips the
   stdlib's `DMod List` whenever the entry module shadows it — so a file
   `mod List do fn length …` defines `List.length` with nothing nested to see.
   Starting the walk with `in_mod = true` when the names match closes that.

   That walk start is PINNED by `specs/lang/types/accept/t126_entry_module_
   shadows_list_length.march` (and `t127…string_byte_size` for the other
   alias), not by any unit fixture here — a string-parsed module has an empty
   [stdlib_source_files], so nothing in it can be told apart from the stdlib's
   own definitions.  The witness declares `length` as an `interface`/`impl`
   method pair on purpose: desugar's [strip_entry_self_qual] rewrites
   `List.length` to bare `length` when the entry module declares `length` as a
   `fn`, a `let` or (since 2026-07-30) an `extern`, so only the decl forms it
   does not rewrite (`impl`, `interface`) leave a qualified call site for this
   gate to matter at.  Revert this to `go false` and the corpus rejects `t126`
   with a false `len(ys) = 0`.

   The `A.DExtern` arm of the member scan below is pinned separately, by
   `accept/t139_nested_module_shadows_list_length_extern.march` — a NESTED
   `mod List` with a foreign `length`, whose module name [strip_entry_self_qual]
   does not touch.  Delete that arm and the corpus rejects `t139` with the same
   false `len(ys) = 0`.  Before 2026-07-30, `t126` covered both at once; it can
   no longer, because an entry-level extern member's call site is now stripped
   bare and never reaches the alias at all.

   Direction of doubt is always to SUPPRESS: a missed proof is silence, the
   status quo ante; a wrong fact in the assumption set is a false positive.

   Returns the verdict PLUS the span of the first competing declaration found,
   so a withdrawal can point at its cause instead of leaving the user to search
   the unit (which, with `MARCH_LIB_PATH`, may not even be their own code).
   The span is diagnostic-only — the boolean is computed exactly as before. *)
let stdlib_member_defs_ok ~(md : string) ~(fn : string) ~(mod_name : string)
    (decls : A.decl list) : bool * A.span option =
  let foreign = ref false in
  let rebound = ref false in
  let cause = ref None in
  let blame (sp : A.span) = if !cause = None then cause := Some sp in
  (* A member definition only competes if it did NOT come from the standard
     library's own sources — see [is_stdlib_source_file]. *)
  let defines in_mod (sp : A.span) b =
    if in_mod && b && not (is_stdlib_source_file sp.A.file) then begin
      foreign := true;
      blame sp
    end
  in
  let mentions_md xs = List.exists (fun (n : A.name) -> n.A.txt = md) xs in
  (* Does glob-importing the module at [path] put some other module under the
     bare name `<md>`?  A nested `mod <md>` or an `alias … as <md>` inside the
     target does; nothing else in it can. *)
  let glob_competes path =
    glob_import_competes ~root:decls ~unit_name:mod_name
      ~binds_decl:(function
        | A.DMod (n, _, _, _) -> n.A.txt = md
        | A.DAlias (a, _) -> a.A.alias_name.A.txt = md
        | _ -> false)
      ~names_it:mentions_md
      ~single_binds:(fun p ->
        match List.rev p with last :: _ -> last.A.txt = md | [] -> false)
      path
  in
  (* A `use`/`alias` competes for the bare name `<md>` on the same terms a
     member definition does: only when it is the PROGRAM's, not the standard
     library's.  Without this the exclusion was asymmetric — [defines] already
     ignored stdlib spans — and one `import` added inside stdlib withdrew the
     alias for every program compiled with that stdlib.

     That happened: #112 added `import Process` to stdlib/system.march to
     dedupe System.ProcessResult.  It is a glob (`UseAll`), which an earlier
     revision of this scan treated as "could carry a nested module named
     List", so `List.length` stopped being recognised as the stdlib's and
     every `{List(a) | len(_) > 0}` contract silently stopped being enforced —
     caught only by specs/lang/types/reject/t117, whose whole purpose is to
     notice the alias going missing.

     Scoping makes this sound beyond the stdlib case: an import inside
     `mod System` binds names in System's body, not in the module being
     checked.  This stays conservative for user code and only stops the
     stdlib's own internals from speaking for the program.

     ── WHY THIS COMPOSES WITH [glob_competes] ─────────────────────────────
     The two guards were written independently for the same bug and are kept
     BOTH, conjoined: a glob withdraws only when it is the program's own AND
     its target provably provides a competitor.  That is sound for the reason
     any intersection of over-approximations is.  Write C for "this
     declaration really can make `<md>` denote a non-stdlib module".  The
     span rule is sound, i.e. C ⟹ ¬is_stdlib_source_file; the resolution rule
     is sound, i.e. C ⟹ glob_competes (unresolvable answers `true`).  Hence
     C ⟹ both, so anything that really competes still withdraws, and the two
     only ever subtract cases where at least one of them has a proof that
     nothing competes.  Neither can license the other into missing a genuine
     competitor, because neither weakens the other's test — they are ANDed,
     not substituted. *)
  let rebinds (sp : A.span) b =
    if b && not (is_stdlib_source_file sp.A.file) then begin
      rebound := true;
      blame sp
    end
  in
  (* ── The UseSingle narrowing (Task 9, 2026-07-31): LOOK, don't assume ────
     `use X.<md>` used to withdraw purely syntactically on its last path
     segment, while the two glob forms already RESOLVE their target and check
     it.  Measured cost (MARCH_LIB_PATH fixture, obligation-ledger report):
     one nested `use Extras.Deep.List` in a dependency module — whose target
     had NO `length` member at all — flipped an entry program's obligation
     from `1 proved` to `1 skipped (alias-withdrawn)`, program-wide.

     [use_target_provides] answers: can the module at [path] provide a member
     named [fn]?  If it provably cannot, rebinding the bare segment `<md>` to
     it cannot make `<md>.<fn>` denote a non-stdlib function at ANY call site
     — the spelling either fails to resolve through that binding (a typecheck
     error, not a wrong refinement fact) or resolves elsewhere, and any
     elsewhere that competes is some OTHER declaration this walk still sees.
     The argument deliberately does NOT rest on resolver semantics (scoping,
     shadowing order): it only needs "a module provides no `<fn>` ⟹ member
     lookup of `<fn>` in it finds nothing", so the resolve_call step-ordering
     hole filed in specs/todos.md is neither consulted nor widened.

     Fail-closed edges, each an over-approximation:
       - resolution considers EVERY module scope of the unit and ALL matches
         (duplicate paths, enclosing-relative spellings), withdrawing if ANY
         match provides — which resolution the real resolver would pick is
         exactly the question this pass cannot answer;
       - nothing resolves ⇒ withdraw, as the glob forms always have;
       - "provides" counts every member-capable decl form the [defines] scan
         counts (fn, let-bound, extern, interface/impl — the latter two the
         same deliberate over-approximation documented on the member arms
         below), PLUS the target's own use-forms: a `use Y.{<fn>}` or an
         unenumerable glob inside the target may re-export the member, so
         both count as providing (glob fuel exhaustion ⇒ provides).

     Note the residual duty is small by construction: a target that provides
     `<fn>` via a DIRECT member decl is a `mod <md>` carrying that member,
     which the [defines] scan withdraws independently — so this check alone
     stands guard over the re-export and unresolvable shapes, and an
     under-count in the member forms here is still backstopped there.
     DAlias/UseNames stay unconditionally withdrawing: no measured cost
     implicated them, and each narrowing in this gate must pay its own way. *)
  let use_target_provides (path : A.name list) : bool =
    let member = function
      | A.DFn (fd, _) -> fd.A.fn_name.A.txt = fn
      | A.DLet (_, b, _) -> List.mem fn (pat_binders b.A.bind_pat)
      | A.DExtern (ed, _) ->
        List.exists (fun (f : A.extern_fn) -> f.A.ef_name.A.txt = fn) ed.A.ext_fns
      | A.DInterface (idf, _) ->
        List.exists
          (fun (m : A.method_decl) -> m.A.md_name.A.txt = fn)
          idf.A.iface_methods
      | A.DImpl (idf, _) ->
        List.exists (fun ((mn : A.name), _) -> mn.A.txt = fn) idf.A.impl_methods
      | _ -> false
    in
    let mentions_fn xs = List.exists (fun (n : A.name) -> n.A.txt = fn) xs in
    (* Every decl-list scope in the unit: the root, and the body of every
       (arbitrarily nested) module.  `describe` blocks do not open a scope. *)
    let scopes =
      let rec go acc ds =
        List.fold_left
          (fun acc d ->
            match d with
            | A.DMod (_, _, ds', _) -> go (ds' :: acc) ds'
            | A.DDescribe (_, ds', _) -> go acc ds'
            | _ -> acc)
          acc ds
      in
      go [ decls ] decls
    in
    (* All decl-lists reachable by [p] from scope [ds] — every matching module
       per segment, describe blocks flattened at each level. *)
    let rec descend_all ds p =
      match p with
      | [] -> [ ds ]
      | (seg : A.name) :: rest ->
        let rec at_level acc = function
          | [] -> acc
          | A.DMod (n, _, ds', _) :: tl when n.A.txt = seg.A.txt ->
            at_level (descend_all ds' rest @ acc) tl
          | A.DDescribe (_, ds', _) :: tl -> at_level (at_level acc ds') tl
          | _ :: tl -> at_level acc tl
        in
        at_level [] ds
    in
    let resolve_all p =
      let direct = List.concat_map (fun s -> descend_all s p) scopes in
      (* A path may be written relative to the unit's own module, whose
         declarations are the root list rather than a `DMod` within it. *)
      match p with
      | (hd : A.name) :: (_ :: _ as tl) when hd.A.txt = mod_name ->
        direct @ List.concat_map (fun s -> descend_all s tl) scopes
      | _ -> direct
    in
    let rec provides fuel ds =
      List.exists
        (fun d ->
          member d
          ||
          match d with
          | A.DDescribe (_, ds', _) -> provides fuel ds'
          | A.DUse (u, _) -> (
            match u.A.use_sel with
            (* `use A.B` binds the MODULE B, not B's members — but a
               lowercase last segment is a shape we do not understand, so
               count it as providing rather than reason about it. *)
            | A.UseSingle -> (
              match List.rev u.A.use_path with
              | last :: _ -> last.A.txt = fn
              | [] -> false)
            | A.UseNames xs -> mentions_fn xs
            | A.UseExcept xs -> (not (mentions_fn xs)) && glob fuel u.A.use_path
            | A.UseAll -> glob fuel u.A.use_path)
          | _ -> false)
        ds
    and glob fuel p =
      if fuel <= 0 then true
      else
        match resolve_all p with
        | [] -> true
        | ms -> List.exists (provides (fuel - 1)) ms
    in
    match resolve_all path with
    | [] -> true
    | ms -> List.exists (provides 4) ms
  in
  let rec go in_mod ds =
    List.iter
      (function
        (* ── Can define `<md>.<fn>` ──────────────────────────────────────── *)
        | A.DFn (fd, sp) -> defines in_mod sp (fd.A.fn_name.A.txt = fn)
        (* `let length = fn xs -> …` is a member exactly like `fn length`. *)
        | A.DLet (_, b, sp) -> defines in_mod sp (List.mem fn (pat_binders b.A.bind_pat))
        (* An `extern` block declares its functions as members of the module
           that encloses it. *)
        | A.DExtern (ed, sp) ->
          defines in_mod sp
            (List.exists (fun (f : A.extern_fn) -> f.A.ef_name.A.txt = fn) ed.A.ext_fns)
        (* Interface/impl methods are counted as a DELIBERATE OVER-APPROXIMATION.
           They are NOT actually reachable under the declaring module's
           qualified spelling — `Bar.greet(1)` fails `unbound variable` for a
           nested module and the entry module alike, because a method resolves
           through interface dispatch rather than module member lookup (measured
           2026-07-30; see the residual in `specs/todos.md`).  An earlier
           revision of this comment asserted the opposite as fact.

           The arms stay anyway, because this gate's policy is suppress-on-doubt:
           over-counting a competitor costs a lost proof (silence), while
           under-counting puts a wrong fact in the assumption set and reports
           correct code — the cardinal sin here.  Do NOT "fix" this by deleting
           the arms: `accept/t126`/`t127` now depend on them, and see the
           coupling note on that residual before changing either. *)
        | A.DInterface (idf, sp) ->
          defines in_mod sp
            (List.exists
               (fun (m : A.method_decl) -> m.A.md_name.A.txt = fn)
               idf.A.iface_methods)
        | A.DImpl (idf, sp) ->
          defines in_mod sp
            (List.exists (fun ((mn : A.name), _) -> mn.A.txt = fn) idf.A.impl_methods)
        (* ── Rebinds the bare segment `<md>` ─────────────────────────────── *)
        | A.DAlias (a, sp) -> rebinds sp (a.A.alias_name.A.txt = md)
        | A.DUse (u, sp) ->
          (* Four selector forms, all of which can put some other module under
             the bare name `<md>`:
               `use X.<md>`            — UseSingle, the path's last segment
               `import X.{<md>, …}`    — UseNames (its list admits upper names)
               `import X`              — UseAll, a glob that can carry a
                                         nested module named `<md>`
               `import X, except: [_]` — UseExcept, ditto unless `<md>` is
                                         excluded. *)
          (match u.A.use_sel with
           (* UseSingle RESOLVES its target and asks whether it can provide
              the member, instead of assuming so from the segment name — see
              [use_target_provides] above for the measurement and the
              soundness argument.  Unresolvable ⇒ withdraw, as before. *)
           | A.UseSingle ->
             rebinds sp
               (match List.rev u.A.use_path with
                | last :: _ :: _ ->
                  last.A.txt = md && use_target_provides u.A.use_path
                | _ -> false)
           | A.UseNames xs -> rebinds sp (mentions_md xs)
           (* The two glob forms RESOLVE their target and look for a module
              named `<md>` rather than assuming one — see
              [glob_import_competes].  Unresolvable ⇒ withdraw, as before.
              [rebinds] then adds the stdlib-span exclusion on top. *)
           | A.UseExcept xs ->
             rebinds sp ((not (mentions_md xs)) && glob_competes u.A.use_path)
           | A.UseAll -> rebinds sp (glob_competes u.A.use_path))
        (* ── Contains declarations; recurse ──────────────────────────────── *)
        | A.DMod (name, _, ds, _) -> go (name.A.txt = md) ds
        (* A `describe` block does not open a module scope of its own, so its
           declarations sit at the enclosing module's level. *)
        | A.DDescribe (_, ds, _) -> go in_mod ds
        (* ── Can neither define `<md>.<fn>` nor rebind `<md>` ────────────── *)
        (* Types and their constructors: constructors are capitalised, so they
           cannot collide with the lowercase `length`/`byte_size`. *)
        | A.DType _ | A.DAlwaysLinearType _ | A.DTransitions _
        (* Capitalised entities in their own namespaces; none of them is a
           module that the bare segment `<md>` could resolve to. *)
        | A.DActor _ | A.DProtocol _ | A.DSig _ | A.DApp _
        (* Desugared into `DImpl` before this pass runs; handled above. *)
        | A.DDeriving _ | A.DSatisfy _
        (* Capability/compiler directives — no bindings at all. *)
        | A.DNeeds _ | A.DProofCap _ | A.DOpts _
        (* Test bodies bind only within themselves. *)
        | A.DTest _ | A.DSetup _ | A.DSetupAll _ -> ())
      ds
  in
  go (mod_name = md) decls;
  (((not !foreign) && not !rebound), !cause)

let list_length_defs_ok ~(mod_name : string) (decls : A.decl list) : bool * A.span option =
  stdlib_member_defs_ok ~md:"List" ~fn:"length" ~mod_name decls

let string_byte_size_defs_ok ~(mod_name : string) (decls : A.decl list) :
    bool * A.span option =
  stdlib_member_defs_ok ~md:"String" ~fn:"byte_size" ~mod_name decls

(* Does any binding construct inside [e] bind [name]?  BINDER positions only —
   an ordinary `string_byte_length(t)` CALL mentions the name without binding
   it, so [expr_mentions] (which counts every occurrence) is the wrong tool
   here: it would report the very uses this alias exists to serve.

   [iter_all] supplies the structure-agnostic descent, so a new expression form
   is covered as soon as it appears in [children]; this match only has to name
   the forms that BIND.

   Returns the SPAN of the first binder found rather than a bare boolean: the
   `cap verified` diagnostic points the user at the binding that withdrew the
   alias, and "somewhere in this unit" is not actionable when the unit spans a
   `MARCH_LIB_PATH` dependency.  The predicate [expr_binds_name] below is this
   function's `<> None`, so the two cannot drift. *)
let expr_binder_span (name : string) (e : A.expr) : A.span option =
  let found = ref None in
  let is n = n = name in
  let param (p : A.param) = is p.A.param_name.A.txt in
  iter_all
    (fun e ->
      if !found = None then
        let here =
          match e with
          | A.ELam (ps, _, sp) -> if List.exists param ps then Some sp else None
          | A.ELetFn (n, ps, _, _, sp) ->
            if is n.A.txt || List.exists param ps then Some sp else None
          | A.ELet (b, sp) ->
            if List.exists is (pat_binders b.A.bind_pat) then Some sp else None
          | A.ELetQ (p, _, _, sp) | A.ELetStar (p, _, _, sp) ->
            if List.exists is (pat_binders p) then Some sp else None
          | A.EMatch (_, brs, sp) ->
            if
              List.exists
                (fun (br : A.branch) -> List.exists is (pat_binders br.A.branch_pat))
                brs
            then Some sp
            else None
          | _ -> None
        in
        if here <> None then found := here)
    e;
  !found

let expr_binds_name (name : string) (e : A.expr) : bool =
  expr_binder_span name e <> None

(* Is the BARE name [name] still the compiler builtin?  There is no stdlib
   March definition of `string_byte_length` to identify (it is an intrinsic),
   so unlike [stdlib_member_defs_ok] there is no allow-because-stdlib case:
   any binding of the name is a competing one.

   Deliberately coarse — it does not ask whether the binding is actually in
   scope at the call, because the errors are asymmetric (over-suppress = a lost
   proof; under-suppress = a FALSE POSITIVE) and the precise answer needs a
   lexical resolver this pass does not have here.  A glob `use X.*` (or an
   `except:` list that does not exclude the name) can import an arbitrary
   `string_byte_length`, so both count as taking it.

   ── THE INVARIANT ──────────────────────────────────────────────────────────
   Scan every construct that can BIND [name] into a scope some `DFn` body can
   see.  That is strictly LARGER than the set the checker descends into, and
   conflating the two is how this gate has been wrong twice:

     - round 1 scanned declaration forms only, missing a `let`/parameter
       binding INSIDE a `DFn` body;
     - round 2 argued the scanned set "is exactly [visit_decls]'s", which is
       the wrong invariant even though the sentence was true.  [visit_decls]
       recurses into `DFn`/`DMod` alone — but a module-level `DLet` is never
       DESCENDED INTO and still BINDS the name for every sibling `DFn`, which
       is precisely where obligations are raised.  Both misses were the same
       failure: a real shadowing left the alias active, so a dead `== 0`
       branch was treated as reachable and a correct program was reported.

   So do not reason about where bodies are visited.  Ask only: can this
   construct put the name in scope for a checked body?  Two consequences —
   this walks expression binders via [expr_binds_name] (round 1), and the
   match below is EXHAUSTIVE over [A.decl] with no wildcard, so a new
   declaration form is a compile error here rather than a silent hole (round
   2).  The arms that do nothing say so by name, and each is a claim that that
   form cannot bind a bare value name; check it rather than trusting it. *)
let bare_builtin_undefined ?(mod_name = "") (name : string) (decls : A.decl list) :
    bool * A.span option =
  let taken = ref false in
  let cause = ref None in
  (* [sp] is the best location we have for this binder; the FIRST one recorded
     wins, so the reported cause is stable under list order. *)
  let take (sp : A.span) b =
    if b then begin
      taken := true;
      if !cause = None then cause := Some sp
    end
  in
  (* A binder found INSIDE an expression knows its own span, which is far more
     useful than the enclosing declaration's. *)
  let take_in (sp : A.span) e =
    match expr_binder_span name e with Some s -> take s true | None -> ignore sp
  in
  let named xs = List.exists (fun (n : A.name) -> n.A.txt = name) xs in
  (* Does glob-importing the module at [path] bring a member called [name]
     into scope?  Only a value DECLARATION of that name in the target does —
     a nested module's members are not glob-imported along with it. *)
  let glob_competes path =
    glob_import_competes ~root:decls ~unit_name:mod_name
      ~binds_decl:(function
        | A.DFn (fd, _) -> fd.A.fn_name.A.txt = name
        | A.DLet (_, b, _) -> List.mem name (pat_binders b.A.bind_pat)
        | A.DExtern (ed, _) ->
          List.exists (fun (f : A.extern_fn) -> f.A.ef_name.A.txt = name) ed.A.ext_fns
        | A.DInterface (idf, _) ->
          List.exists
            (fun (m : A.method_decl) -> m.A.md_name.A.txt = name)
            idf.A.iface_methods
        | A.DImpl (idf, _) ->
          List.exists (fun ((mn : A.name), _) -> mn.A.txt = name) idf.A.impl_methods
        | _ -> false)
      ~names_it:named
      ~single_binds:(fun _ -> false)
      path
  in
  let fn_def_takes (sp : A.span) (fd : A.fn_def) =
    take fd.A.fn_name.A.span (fd.A.fn_name.A.txt = name);
    List.iter
      (fun (c : A.fn_clause) ->
        take sp (List.mem name (List.concat_map fnparam_binders c.A.fc_params));
        (* A default-value expression is a binder site too (it can carry a
           lambda), and [fc_params] holds it outside the body. *)
        List.iter
          (function
            | A.FPDefault (_, d) -> take_in sp d
            | A.FPNamed _ | A.FPPat _ -> ())
          c.A.fc_params;
        (match c.A.fc_guard with Some g -> take_in sp g | None -> ());
        take_in sp c.A.fc_body)
      fd.A.fn_clauses
  in
  let rec go ds =
    List.iter
      (function
        (* ── Binds a bare value name ─────────────────────────────────────── *)
        | A.DFn (fd, sp) -> fn_def_takes sp fd
        (* A module-level `let` is never descended into by [visit_decls], yet it
           binds the name for every sibling `DFn` body — the round-2 hole. *)
        | A.DLet (_, b, sp) ->
          take sp (List.mem name (pat_binders b.A.bind_pat));
          take_in sp b.A.bind_expr
        (* An `extern` block declares its functions under their bare names. *)
        | A.DExtern (ed, sp) ->
          take sp
            (List.exists (fun (f : A.extern_fn) -> f.A.ef_name.A.txt = name) ed.A.ext_fns)
        (* Interface METHODS are called by bare name and dispatched on the
           argument's type, so a method of this name takes the spelling; a
           default body is a binder site as well. *)
        | A.DInterface (idf, sp) ->
          List.iter
            (fun (m : A.method_decl) ->
              take m.A.md_name.A.span (m.A.md_name.A.txt = name);
              match m.A.md_default with Some d -> take_in sp d | None -> ())
            idf.A.iface_methods
        | A.DImpl (idf, sp) ->
          List.iter
            (fun ((mn : A.name), (fd : A.fn_def)) ->
              take mn.A.span (mn.A.txt = name);
              fn_def_takes sp fd)
            idf.A.impl_methods
        | A.DAlias (a, sp) -> take sp (a.A.alias_name.A.txt = name)
        | A.DUse (u, sp) ->
          (match u.A.use_sel with
           (* A glob takes the name only if its target actually defines it —
              see [glob_import_competes].  Unresolvable ⇒ take, as before. *)
           | A.UseAll -> take sp (glob_competes u.A.use_path)
           | A.UseExcept xs -> take sp ((not (named xs)) && glob_competes u.A.use_path)
           | A.UseNames xs -> take sp (named xs)
           (* `use A.B` binds the MODULE `B`, never a bare value name. *)
           | A.UseSingle -> ())
        (* ── Contains declarations; recurse ──────────────────────────────── *)
        | A.DMod (_, _, ds, _) | A.DDescribe (_, ds, _) -> go ds
        (* ── Cannot bind a bare value name ───────────────────────────────── *)
        (* Types and their constructors: March constructors are capitalised, so
           they cannot collide with a lowercase builtin, and they are `ECon`
           rather than `EVar` at the call anyway. *)
        | A.DType _ | A.DAlwaysLinearType _ | A.DTransitions _
        (* Named, capitalised entities with their own namespace. *)
        | A.DActor _ | A.DProtocol _ | A.DSig _ | A.DApp _
        (* Desugared into `DImpl` before this pass runs; handled above. *)
        | A.DDeriving _ | A.DSatisfy _
        (* Capability/compiler directives — no value bindings at all. *)
        | A.DNeeds _ | A.DProofCap _ | A.DOpts _
        (* Test bodies bind only within themselves, and no obligation raised in
           a sibling `DFn` can see those bindings. *)
        | A.DTest _ | A.DSetup _ | A.DSetupAll _ -> ())
      ds
  in
  go decls;
  (not !taken, !cause)

(* =================================================================
   §23 Entry point: check_module
   ================================================================= *)

(* [measure_axioms] (default true) gates the whole measure-axiom machinery —
   datatype modelling, recursion-equation axioms, AND the M-b soundness gate (the
   gate exists to keep those axioms sound, so with axioms off it has no purpose).
   With it off, measures reflect purely symbolically (the pre-M-a behaviour:
   sound, no quantifiers, no datatype theory), an escape hatch for the per-query
   cost of quantified/datatype reasoning.  It changes only diagnostics, never the
   compiled artifact, so it is not part of the CAS cache key. *)
(* [stdlib_files]: the source files the caller loaded as the standard library.
   Only used to decide whether a `List.length` / `String.byte_size` in scope is
   the real one — see [stdlib_source_files].  (The bare `string_byte_length`
   alias does not consult it: that name is a compiler builtin with no stdlib
   definition, so any definition of it is competing by construction.)

   Omitting it does NOT disable the `List.length` alias.  It makes the answer
   "no file is the stdlib's", which matters only when a competing
   `List.length` definition is actually in scope: with none present — the case
   for every string-parsed test fixture — [list_length_defs_ok] finds nothing
   foreign and the alias stays enabled.  So the default is safe in the sense
   that no non-stdlib definition can ever be mistaken for the stdlib's, not in
   the sense that it turns the feature off. *)
let check_module ?(root = Sys.getcwd ()) ?(measure_axioms = true)
    ?(stdlib_files : string list = [])
    ?(audit : ((Refine_audit.site * Refine_audit.disposition) list -> unit) option)
    ?(pre_desugar_decls : A.decl list option)
    (errctx : Err.ctx) (m : A.module_) : unit =
  (* A module owns one solver declaration scope.  Z3 4.8.x does not reliably
     retract datatype declarations on [pop], even with [:global-decls false]:
     checking a later module that reuses a qualified type name with a different
     shape then yields declaration errors and silently downgrades its VCs to
     [Unknown].  Start each module with a fresh process while retaining solver
     reuse for every VC within the module; the content-addressed VC cache still
     preserves cross-module results. *)
  March_refine.Refine.shutdown ();
  (* Register the module with the witness validator so a Refuted model can be
     confirmed by execution before it is reported (its interpreter env is
     built lazily, on the first candidate that needs it). *)
  Witness.set_module m;
  (* The ledger is per-module: without this, counts accumulate across every
     compilation in one process (the test binary today, an LSP session
     tomorrow) and a report would describe every module ever checked. *)
  Obligation.reset ();
  (* Hygiene: [visit_decls] sets this per decl list, but a prior module must
     never be able to leave it on. *)
  strict_verified := false;
  (* Same hygiene, same reason: [Precond_infer.attach_promoted_fixes] drains
     this after the walk, and a site left over from a previous module would
     send it looking for a diagnostic this context never had. *)
  promoted_sites := [];
  (* Same hygiene: a prior module's enclosing function must never leak into
     this module's promotion checks. *)
  enclosing_fn := None;
  stdlib_source_files := stdlib_files;
  let mod_name = m.A.mod_name.A.txt in
  (* Each gate answers "is the alias still safe?"; a `false` is a WITHDRAWAL,
     and the withdrawal is what a `cap verified` diagnostic must be able to
     name.  The boolean stored is exactly the gate's own answer — this records
     alongside it, it does not decide anything. *)
  withdrawals := [];
  let gate spelling measure ~str (ok, cause) =
    if not ok then
      withdrawals :=
        { wd_spelling = spelling; wd_measure = measure; wd_str = str; wd_span = cause }
        :: !withdrawals;
    ok
  in
  list_length_is_stdlib :=
    gate "List.length" "len" ~str:false (list_length_defs_ok ~mod_name m.A.mod_decls);
  string_byte_size_is_stdlib :=
    gate "String.byte_size" "len" ~str:true
      (string_byte_size_defs_ok ~mod_name m.A.mod_decls);
  string_byte_length_is_builtin :=
    gate "string_byte_length" "len" ~str:true
      (bare_builtin_undefined ~mod_name "string_byte_length" m.A.mod_decls);
  let mfns = collect_measure_fns m.A.mod_decls in
  registered_measures := List.map fst mfns;
  (* Determine which measures are non-negative (single pass; a measure depending
     only on already-classified ones, itself, and `len` is classified). *)
  measure_nonneg :=
    List.fold_left
      (fun known (name, fd) ->
        match fd.A.fn_clauses with
        | c :: _ when measure_body_nonneg name known c.A.fc_body -> name :: known
        | _ -> known)
      [] mfns;
  Hashtbl.reset adt_ctors;
  Hashtbl.reset ctor_field_sorts;
  Hashtbl.reset ctor_field_names;
  Hashtbl.reset axiom_measures;
  Hashtbl.reset measure_base_cases;
  Hashtbl.reset measure_scalar_field_dep;
  Hashtbl.reset measure_preamble_sorts;
  measure_preamble := "";
  type_preamble := "";
  (* Reset per-module so the SMT constant names a VC is built from are a
     function of the module alone.  Without this the counter drifts across
     repeated [check_module] calls in one process (the test binary today; an
     LSP/REPL embedding tomorrow) and every VC mentioning a propagated
     postcondition misses the content-addressed VC cache forever. *)
  ret_ctr := 0;
  (* Registering the module's (and the built-in) ADTs is NOT part of the
     measure-axiom machinery [measure_axioms] gates: constructor-tag
     refinements build their own small datatype preamble per VC and pay no
     quantifier cost.  Leaving these inside the guard emptied [adt_ctors] under
     `--no-measure-axioms`, which made `is_Some` look like unknown vocabulary
     and produced a warning that is simply false. *)
  register_builtin_adts ();
  register_adt_names m.A.mod_decls;
  register_field_sorts m.A.mod_decls;
  if measure_axioms then begin
    build_measure_preamble mfns;
    build_type_preamble ();
    (* M-b soundness gate: a `@[measure]` must be a total, terminating, pure
       function, else its axioms would be unsound.  Emit a hard error per
       violation (filtered to user files by the caller, like every diagnostic). *)
    List.iter
      (fun (_name, fd) ->
        List.iter
          (fun msg ->
            Err.error errctx ~span:fd.A.fn_name.A.span
              (Printf.sprintf "@[measure] `%s` %s" fd.A.fn_name.A.txt msg))
          (measure_gate_errors fd))
      mfns;
    (* Silent-inertness warning.  A measure reading a scalar constructor field
       is axiomatised correctly and still proves nothing, because call-site
       reflection erased the field (see [measure_scalar_field_dep]).  Every
       symptom of a working measure is present, so without this the author's
       only signal is that contracts using it never fire — which is how this
       cost a full investigation to find on `Array.length`.

       A WARNING, not an error: the measure is sound and its predicates remain
       legal vocabulary, so nothing that compiles today stops compiling.  It
       changes no verdict. *)
    List.iter
      (fun (name, fd) ->
        if Hashtbl.mem measure_scalar_field_dep name then
          Err.warning errctx ~span:fd.A.fn_name.A.span
            (Printf.sprintf
               "@[measure] `%s` reads a constructor field that is not itself a \
                data type, so its value cannot be computed at a call site and \
                refinements using it will never be proved or refuted."
               name))
      mfns
  end;
  let defs = collect_all_defs m.A.mod_decls in
  (* Only POSITIVELY VERIFIED postconditions may be assumed at call sites. *)
  gate_unverified_posts ~root errctx defs m.A.mod_decls;
  (* Always walk: a function may have a refined *return* (postcondition) even
     with no refined parameters, so it won't appear in [defs]. *)
  visit_decls ~root errctx defs rctx0 m.A.mod_decls;
  (* Vocabulary warning: runs last so [registered_measures] (set at the top of
     this function) is already populated — otherwise a user `@[measure]`
     would look unrecognized and warn spuriously. *)
  warn_predicate_decls errctx ~strict:(decls_declare_verified m.A.mod_decls) m.A.mod_decls;
  (* Coverage audit: runs last, only when asked, and touches neither [errctx]
     nor the obligation ledger; it is a read-only classification of every
     declared refinement occurrence against the registration state this
     function has just finished building (ADT/record sorts, and, if
     [measure_axioms] is set, [measure_preamble_sorts]). Placed after
     [warn_predicate_decls] rather than before it so the audit can never
     observe a partially-registered module, and before any caller-side
     inference probe (`--refine-suggest*`, [Precond_infer.attach_promoted_fixes])
     gets a chance to re-run [check_module] against a hypothesis and disturb
     global state a naive audit implementation might have relied on; this
     one does not touch the obligation ledger at all, but the placement is
     chosen to make that true by construction, not by accident.

     Calls [Refine_audit] directly: no cycle, because [Refine_audit] depends
     only on [Refine_post] and earlier links in this file's own [include]
     chain, never on [Refine_check] itself (see [Refine_encode.ty_has_refinement]'s
     own comment for why it moved there). [?audit] carries the caller's sink
     as an ordinary optional function argument, not a global mutable ref: a
     caller that wants the result passes [~audit:(fun result -> ...)] and
     receives the classified list exactly once, synchronously, from this
     call; a caller that omits it (every caller before this flag existed)
     pays nothing and nothing is ever computed.

     [?pre_desugar_decls], when given, is the SAME module's decl list before
     [Desugar.desugar_module] ran. [m.A.mod_decls] is always POST-desugar
     (every caller of [check_module] passes the desugared module), which
     hides two real gaps from [Refine_audit.sites]/[classify] entirely: a
     multi-head function's clause merge drops every declared parameter type
     before this function ever runs, and a default-argument function
     survives only under mangled arity-variant names no plain call can
     resolve to, so a refinement that lands on the survivor gets a false
     [Enforced] verdict (whole-plan review, findings 1 and 2). Without
     [?pre_desugar_decls] this function cannot see either: the omission is
     silent, not a warning, matching every other optional argument here.
     Every existing caller that does not supply it keeps today's exact
     behaviour ([desugar_dropped] simply has nothing to compare against). *)
  match audit with
  | None -> ()
  | Some sink ->
    let post_sites = Refine_audit.sites m.A.mod_decls in
    let dropped =
      match pre_desugar_decls with
      | None -> []
      | Some pre_decls -> Refine_audit.desugar_dropped ~pre:(Refine_audit.sites pre_decls) ~post:post_sites
    in
    let dropped_reason =
      "this refinement was declared here, but no occurrence with the same \
       enclosing name and predicate text survives desugaring: either the \
       declared type was discarded entirely (a multi-head function's \
       clause merge drops every parameter type before the checker ever \
       sees it) or it now lives only under a mangled name a plain call \
       cannot resolve to (a default-argument function's arity variant, \
       e.g. `f$2`). See specs/todos/2026-09-03-desugar-dropped-refinement-unchecked.md."
    in
    sink
      (List.map (fun s -> (s, Refine_audit.Unenforced dropped_reason)) dropped
      @ List.map (fun s -> (s, Refine_audit.classify s)) post_sites)
