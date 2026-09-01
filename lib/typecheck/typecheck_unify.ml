(** §1 Unification and §2 surface-type → internal-type conversion.

    The [pp_ty] helpers and the mismatch renderer, [session_ty_equal],
    [session_ty_exact_equal], [expand_record_ref], [unify], [report_mismatch],
    [surface_ty], [expand_record] and [instantiate_ctor].  Lifted verbatim out
    of [Typecheck] on 2026-08-27 (Target B, task B3 — Phase 6's task 6.7,
    which was gated on a module-initialisation-order hazard that turned out
    not to exist).

    {2 Why moving the two [let () =] hook installations is safe}

    The whole initialisation-order surface of [lib/typecheck/] is two lines,
    and both of them are in this band:

    - [inject_iface_exports_ref] (declared in [Typecheck_env]) has no
      dereference anywhere in the tree — the installation below has never had
      a reader.  See
      [specs/todos/2026-08-27-inject-iface-exports-hook-has-no-reader.md];
      it is deliberately left in place as a breadcrumb.  An installation
      nobody reads cannot have an ordering regression.
    - [expand_record_ref] moves as a closed unit: its declaration, its single
      read site (inside [unify]) and its installation are all three in this
      file, in that order.  [Typecheck_unify] initialises strictly before
      [Typecheck], so the install still precedes every possible read.

    {2 The standing check}

    No oracle can see module-initialisation order, so the property is asserted
    directly instead.  Two invariants, to be re-run by anything that touches
    this file:

    - [lib/typecheck/] must contain exactly TWO top-level effects — the two
      installations below.  Grep the whole directory for line-initial
      [let () =]; the count must stay 2.  If it ever grows, the argument above
      no longer covers the new effect and the hazard is live again: say so in
      that change.
    - The three CODE sites of the record-expansion hook — its declaration, the
      single dereference inside [unify], and its installation — must all be in
      this file, in that order.  Grep this file for line-initial
      [let expand_record_ref], for a dereference of it, and for its
      line-initial installation; three hits, no others anywhere in
      [typecheck.ml].

    The runnable form of both is recorded in the commit that created this file
    and in [specs/progress/2026-08-27-typecheck-target-b-decomposition.md].
    It is deliberately not spelled out here as a copy-pasteable command: a
    literal grep pattern written into the file it greps matches itself, which
    silently inflates the count it is supposed to pin.

    [include], not [open], at the call site: only [include] re-exports these
    names as part of [Typecheck]'s own surface, and consumers reach them
    through [let open] and through aliases (Tc., TC., T.) that no grep can
    see. *)

include Typecheck_types
include Typecheck_env
include Typecheck_builtins

(* =================================================================
   §1  Unification
   ================================================================= *)

(** Format a type for display in an error message.
    Uses pretty-printing with line-wrapping for long types. *)
let format_ty_for_error t =
  let flat = pp_ty t in
  if String.length flat > 50 then
    "\n    " ^ String.concat "\n    " (String.split_on_char '\n' (pp_ty_pretty ~indent:4 ~width:60 t))
  else "`" ^ flat ^ "`"

(** Report a type mismatch with a conversational Elm-style message. *)
let report_mismatch env ~span ?(occurs_violation = false) ~reason expected found =
  (* Build headline, using pretty-printing for long types.
     Convention: `expected` = inferred type of the expression (what was provided);
                 `found`    = required type from context (what was needed).
     Headline uses standard compiler phrasing: "expected <required> but got <provided>". *)
  let exp_str = format_ty_for_error expected in
  let fnd_str = format_ty_for_error found in
  let headline =
    if String.length (pp_ty expected) > 50 || String.length (pp_ty found) > 50 then
      Printf.sprintf "expected:\n    %s\nbut got:\n    %s"
        (String.concat "\n    " (String.split_on_char '\n' (pp_ty_pretty ~indent:4 ~width:60 found)))
        (String.concat "\n    " (String.split_on_char '\n' (pp_ty_pretty ~indent:4 ~width:60 expected)))
    else
      render_parts
        [ MPText "expected "; MPText fnd_str;
          MPText " but got "; MPText exp_str; MPText "." ]
  in
  let why_note =
    match reason with
    | None   -> []
    | Some r -> [ string_of_reason r ]
  in
  (* Contextual hint: when both types share the same constructor but differ
     in one argument, identify which argument mismatches. *)
  let mismatch_note =
    match repr expected, repr found with
    | TCon (name1, args1), TCon (name2, args2)
      when name1 = name2 && List.length args1 = List.length args2 ->
      (match find_arg_mismatch name1 args1 args2 with
       | Some (i, cname, exp_arg, fnd_arg) ->
         let ordinal = match i with 1 -> "1st" | 2 -> "2nd" | 3 -> "3rd"
           | n -> string_of_int n ^ "th" in
         [ Printf.sprintf "The %s argument of `%s` mismatches: expected `%s` but got `%s`."
             ordinal cname (pp_ty fnd_arg) (pp_ty exp_arg) ]
       | None -> [])
    | TRecord provided_flds, TRecord required_flds ->
      (* Per the convention above, [expected] holds what was PROVIDED and
         [found] holds what was REQUIRED — hence the local names.  Getting
         this backwards is why an extra field used to be reported as a
         missing one ("present in the expected type but missing in the found
         type" for a field that was in the provided value and absent from the
         required type).  Report both directions, surplus first, and name the
         two sides in words rather than reusing the overloaded
         "expected"/"found" pair. *)
      let surplus = List.filter_map (fun (name, t1) ->
        match List.assoc_opt name required_flds with
        | Some t2 when pp_ty t1 <> pp_ty t2 ->
          Some (Printf.sprintf "Field `%s` mismatches: expected `%s` but got `%s`."
            name (pp_ty t2) (pp_ty t1))
        | None ->
          Some (Printf.sprintf
                  "Field `%s` is present in the value provided, but the \
                   expected type has no such field." name)
        | _ -> None) provided_flds
      in
      let absent = List.filter_map (fun (name, _) ->
        if List.mem_assoc name provided_flds then None
        else
          Some (Printf.sprintf
                  "Field `%s` is required by the expected type, but the value \
                   provided has no such field." name)) required_flds
      in
      (match surplus @ absent with n :: _ -> [n] | [] -> [])
    | _ -> []
  in
  (* Common-case hints for frequently-confused types.
     NOTE: `expected` here = the inferred type of the expression (what was provided);
           `found`    here = the required type from context (what was needed).
     Matches are on (provided, required) order. *)
  let common_hint =
    match repr expected, repr found with
    | TCon ("Int", []), TCon ("Float", []) ->
      (* User provided Int, Float was required *)
      [ "Int and Float are distinct types in March.\n\
         Use `int_to_float(x)` to convert, or write a Float literal like `1.0`." ]
    | TCon ("Float", []), TCon ("Int", []) ->
      (* User provided Float, Int was required *)
      [ "Float and Int are distinct types in March.\n\
         Use `float_to_int(x)` to truncate, or write an Int literal like `1`." ]
    | TCon ("Int", []), TCon ("Bool", []) ->
      (* Expression was Int but Bool was required *)
      [ "March does not coerce Int to Bool.\n\
         Try an explicit comparison, e.g. `x != 0`." ]
    | TCon ("Int", []), TCon ("String", []) ->
      (* Expression was Int but String was required *)
      [ "Use `int_to_string(x)` to convert an Int to a String." ]
    | TCon ("Float", []), TCon ("String", []) ->
      (* Expression was Float but String was required *)
      [ "Use `float_to_string(x)` to convert a Float to a String." ]
    | TArrow _, _ ->
      [ "This value is a function. Did you forget to apply it to its arguments?" ]
    | _, TArrow _ ->
      [ "A function was expected here.\n\
         Did you mean to pass this as a callback?" ]
    | _ -> []
  in
  (* Same-printed-name disambiguation.
     March has a single global type namespace, so a user-defined type can share
     its printed name with a stdlib type (e.g. local `Config` vs `Config` from the
     standard library).  When that happens unification fails but both sides render
     identically, yielding the baffling "expected `Config` but got `Config`".
     Detect the case — the two reprs print the same string but are structurally
     distinct — and explain it.  We compare structural shapes (TCon vs TRecord,
     constructor name, argument count) rather than exact identity so we only fire
     when the types genuinely differ despite printing alike. *)
  let same_name_note =
    let pe = pp_ty (repr expected) and pf = pp_ty (repr found) in
    let structurally_distinct =
      match repr expected, repr found with
      | TCon (n1, a1), TCon (n2, a2) ->
        n1 <> n2 || List.length a1 <> List.length a2
      | TCon _, TRecord _ | TRecord _, TCon _ -> true
      | _ -> false
    in
    if pe = pf && structurally_distinct then
      [ Printf.sprintf
          "Two distinct types are both named `%s` — they print the same but have \
           different definitions. March has a single global type namespace, so a \
           local type collides with any same-named type from another module or the \
           standard library.\n\
           Rename one of them (e.g. `App%s`), or qualify/avoid the import that \
           brings the other `%s` into scope."
          pe pe pe ]
    else []
  in
  let labels =
    match reason with
    | Some r ->
      (match span_of_reason r with
       | Some rsp when rsp <> span ->
         [ { Err.lbl_span = rsp;
             lbl_message  = "the expected type comes from here" } ]
       | _ -> [])
    | None -> []
  in
  (* An occurs-check failure is a fundamentally different situation than an
     ordinary mismatch: the type variable would have to equal a type that
     contains itself (e.g. a self-referential record field inferred without
     a type annotation to anchor it, so the compiler discovers the recursion
     structurally instead of stopping at a nominal type name). The plain
     "expected X but got Y" headline above is technically accurate but reads
     as a random-looking, unmemorable variable name mismatching an unrelated
     type — nothing about it says "this can't ever be finite" or suggests
     the fix. Lead with that explanation instead. *)
  let occurs_note =
    if occurs_violation then
      [ "This type would have to be infinitely recursive to satisfy every \
         use — it isn't possible to infer it automatically. Add an explicit \
         type annotation (e.g. on the function parameter or `let` binding) \
         naming the recursive type by its declared name." ]
    else []
  in
  Err.report env.errors
    { Err.severity = Error; span; message = headline;
      labels;
      notes = occurs_note @ why_note @ mismatch_note @ common_hint @ same_name_note;
      code = None; fix = None }

(** Structural equality for session types (used by [unify] for [TChan] cases).
    Intentionally ignores payload types — only checks session structure shape. *)
let rec session_ty_equal s1 s2 =
  match s1, s2 with
  | SEnd, SEnd -> true
  | SError, SError -> true
  | SSend (_, s1'), SSend (_, s2') -> session_ty_equal s1' s2'
  | SRecv (_, s1'), SRecv (_, s2') -> session_ty_equal s1' s2'
  | SChoose bs1, SChoose bs2 | SOffer bs1, SOffer bs2 ->
    List.length bs1 = List.length bs2 &&
    List.for_all2 (fun (l1, s1') (l2, s2') ->
        l1 = l2 && session_ty_equal s1' s2') bs1 bs2
  | SRec (x1, s1'), SRec (x2, s2') -> x1 = x2 && session_ty_equal s1' s2'
  | SVar x1, SVar x2 -> x1 = x2
  | SMSend (r1, _, s1'), SMSend (r2, _, s2') -> r1 = r2 && session_ty_equal s1' s2'
  | SMRecv (r1, _, s1'), SMRecv (r2, _, s2') -> r1 = r2 && session_ty_equal s1' s2'
  | _ -> false

(** Exact structural equality including payload types.
    Used by MPST mergeability check to determine if branches can be merged.
    Two branches can be merged only if they are completely identical. *)
let rec session_ty_exact_equal s1 s2 =
  match s1, s2 with
  | SEnd, SEnd -> true
  | SError, SError -> true
  | SSend (t1, s1'), SSend (t2, s2') ->
    pp_ty t1 = pp_ty t2 && session_ty_exact_equal s1' s2'
  | SRecv (t1, s1'), SRecv (t2, s2') ->
    pp_ty t1 = pp_ty t2 && session_ty_exact_equal s1' s2'
  | SChoose bs1, SChoose bs2 | SOffer bs1, SOffer bs2 ->
    List.length bs1 = List.length bs2 &&
    List.for_all2 (fun (l1, s1') (l2, s2') ->
        l1 = l2 && session_ty_exact_equal s1' s2') bs1 bs2
  | SRec (x1, s1'), SRec (x2, s2') -> x1 = x2 && session_ty_exact_equal s1' s2'
  | SVar x1, SVar x2 -> x1 = x2
  | SMSend (r1, t1, s1'), SMSend (r2, t2, s2') ->
    r1 = r2 && pp_ty t1 = pp_ty t2 && session_ty_exact_equal s1' s2'
  | SMRecv (r1, t1, s1'), SMRecv (r2, t2, s2') ->
    r1 = r2 && pp_ty t1 = pp_ty t2 && session_ty_exact_equal s1' s2'
  | _ -> false

(** Normalize type-level nat arithmetic.
    Reduces concrete sub-expressions and applies identity / annihilation laws.
    The result is in weak-head normal form: outer-most TNatOp is simplified as
    far as possible, sub-expressions are recursively normalized. *)
let rec normalize_tnat t =
  match repr t with
  | TNatOp (op, a, b) ->
    let a = normalize_tnat a and b = normalize_tnat b in
    (match op, a, b with
     | Ast.NatAdd, TNat m, TNat n  -> TNat (m + n)
     | Ast.NatAdd, t',    TNat 0   -> t'
     | Ast.NatAdd, TNat 0, t'      -> t'
     | Ast.NatMul, TNat m, TNat n  -> TNat (m * n)
     | Ast.NatMul, _,     TNat 0   -> TNat 0
     | Ast.NatMul, TNat 0, _       -> TNat 0
     | Ast.NatMul, t',    TNat 1   -> t'
     | Ast.NatMul, TNat 1, t'      -> t'
     | _                           -> TNatOp (op, a, b))
  | t -> t

(** Assert that a [TRecord]'s field list satisfies the sorted-name invariant.
    Raises [Failure] with a diagnostic if the invariant is violated.
    Called at every TRecord unification site to catch construction-path bugs
    early — a misordered TRecord produces confusing "type mismatch" errors
    that look like unrelated failures.
    Only active in debug builds (guarded by [Sys.getenv_opt]) to avoid overhead
    in production; set [MARCH_DEBUG_TC=1] to enable. *)
let assert_trecord_sorted flds label =
  match Sys.getenv_opt "MARCH_DEBUG_TC" with
  | Some _ ->
    let names = List.map fst flds in
    let sorted = List.sort String.compare names in
    if names <> sorted then
      failwith (Printf.sprintf
        "INVARIANT VIOLATION: TRecord %s has unsorted fields [%s]; expected [%s]. \
         All TRecord values must be constructed with List.sort."
        label
        (String.concat ", " names)
        (String.concat ", " sorted))
  | None -> ()

(** Forward ref to [expand_record], which is defined later because it depends on
    [surface_ty].  [unify] uses it to reconcile a nominal record [TCon] with the
    structural [TRecord] the same type expands to elsewhere (see the
    [TCon]/[TRecord] case in [unify]).  Wired up immediately after
    [expand_record] is defined. *)
let expand_record_ref : (env -> ty -> ty option) ref =
  ref (fun _ _ -> None)

(** Unify [t1] and [t2], reporting any mismatch to [env.errors].
    Uses [TError] as a recovery sentinel — if either side is [TError]
    the constraint is silently satisfied (the error was already reported). *)
let rec unify env ~span ?(reason = None) t1 t2 =
  let t1 = normalize_tnat t1 and t2 = normalize_tnat t2 in
  match t1, t2 with
  (* Error sentinel absorbs everything *)
  | TError, _ | _, TError -> ()

  (* Same variable — trivially unified *)
  | TVar r1, TVar r2 when r1 == r2 -> ()

  (* Bind a variable *)
  | TVar r, t | t, TVar r ->
    (match !r with
     | Unbound (id, level) ->
       if occurs id level t then begin
         report_mismatch env ~span ~reason ~occurs_violation:true t1 t2;
         r := Link TError
       end else begin
         (* Proof-cap forge hook: if [r] is a tagged [cap_narrow]-result inner
            var (see [cap_producer_ivars]), reject the instant it is bound to a
            nominal proof cap — a cap_narrow value can NEVER become a proof cap,
            in any position or flow (direct, let-generalized, or laundered
            through a polymorphic function). If it binds to ANOTHER var, propagate
            the tag so the check fires when that var is eventually pinned. IO caps
            are not in [proof_caps], so IO-lattice narrowing is never affected. *)
         (match Hashtbl.find_opt env.cap_producer_ivars id with
          | Some cn_sp ->
            let forge_error p =
              Err.error env.errors ~span:cn_sp
                (render_parts [
                  MPText "cap_narrow cannot produce "; MPCode ("Cap(" ^ p ^ ")");
                  MPText " — "; MPCode ("Cap(" ^ p ^ ")");
                  MPText " is a proof capability, not an IO capability.";
                  MPBreak;
                  MPText "hint: a proof capability may only be minted by a public function of its declaring module via ";
                  MPCode "mint_cap";
                  MPText "; cap_narrow only attenuates IO capabilities." ])
            in
            (match repr t with
             (* Tag is on the inner cap var: [a] binds directly to a proof cap. *)
             | TCon (p, []) when List.mem_assoc p env.proof_caps -> forge_error p
             (* Tag is on a whole-value var (laundered result): binds to Cap(P). *)
             | TCon ("Cap", [inner]) ->
               (match repr inner with
                | TCon (p, []) when List.mem_assoc p env.proof_caps -> forge_error p
                | TVar r2 ->
                  (* Cap of an unbound var: propagate the tag to the inner var. *)
                  (match !r2 with
                   | Unbound (id2, _) -> Hashtbl.replace env.cap_producer_ivars id2 cn_sp
                   | Link _ -> ())
                | _ -> ())
             (* Binds to another bare var: propagate the tag so the check fires
                when that var is eventually pinned. *)
             | TVar r2 ->
               (match !r2 with
                | Unbound (id2, _) -> Hashtbl.replace env.cap_producer_ivars id2 cn_sp
                | Link _ -> ())
             | _ -> ())
          | None -> ());
         r := Link t
       end
     | Link _ -> assert false)  (* repr should have resolved links *)

  | TCon (n1, a1), TCon (n2, a2) ->
    if n1 = n2 && List.length a1 = List.length a2 then
      List.iter2 (unify env ~span ~reason) a1 a2
    else
      (report_mismatch env ~span ~reason t1 t2)

  | TArrow (a1, b1), TArrow (a2, b2) ->
    unify env ~span ~reason a1 a2;
    unify env ~span ~reason b1 b2

  | TTuple ts1, TTuple ts2 when List.length ts1 = List.length ts2 ->
    List.iter2 (unify env ~span ~reason) ts1 ts2

  | TRecord f1, TRecord f2 ->
    (* Defensive: check the sorted-name invariant when debug mode is on.
       A TRecord with unsorted fields produces confusing mismatches here
       because ns1 <> ns2 even if the field sets are identical. *)
    assert_trecord_sorted f1 "lhs";
    assert_trecord_sorted f2 "rhs";
    let ns1 = List.map fst f1 and ns2 = List.map fst f2 in
    if ns1 <> ns2 then
      report_mismatch env ~span ~reason t1 t2
    else
      List.iter2
        (fun (_, t1) (_, t2) -> unify env ~span ~reason t1 t2)
        f1 f2

  (* Reconcile a nominal record [TCon] with its structural [TRecord] form.
     A record type's *name* and its *field structure* are interchangeable in
     March's structural record model, but the two representations reach [unify]
     from different paths: [surface_ty] expands a record annotation to a
     [TRecord], while lighter-weight converters (notably [prebind_fn_scheme],
     which pre-binds cross-module function signatures in Pass 1 without record
     field information) leave the same type as a nominal [TCon(Name)].  When a
     cross-module qualified reference like `Cfg.Site` meets the owning module's
     own structural use, the two sides collide as `TCon` vs `TRecord`.  Expand
     the [TCon] side via the [expand_record_ref] hook (a no-op unless [Name]
     denotes a known record that is not also a colliding variant — variants and
     opaque types stay nominal) and retry; fall back to a genuine mismatch if it
     does not name an unambiguous record. *)
  | (TCon _ as tc), (TRecord _ as tr) | (TRecord _ as tr), (TCon _ as tc) ->
    (match !expand_record_ref env tc with
     | Some (TRecord _ as expanded) -> unify env ~span ~reason expanded tr
     | _ -> report_mismatch env ~span ~reason t1 t2)

  | TLin (l1, inner1), TLin (l2, inner2) when l1 = l2 ->
    unify env ~span ~reason inner1 inner2

  (* Transparent coercion: a linear/affine value is structurally the same
     type as its inner (unrestricted) type.  This allows e.g. a field of
     type [linear Int] to unify with an expected [Int] at a use site while
     still preserving the TLin wrapper for linearity tracking in let-bindings. *)
  | TLin (_, inner), other | other, TLin (_, inner) ->
    unify env ~span ~reason inner other

  | TNat n1, TNat n2 when n1 = n2 -> ()

  (* Structural unification for nat ops that could not be fully normalized
     (e.g. both sides have the same un-solved variable structure). *)
  | TNatOp (op1, a1, b1), TNatOp (op2, a2, b2) when op1 = op2 ->
    unify env ~span ~reason a1 a2;
    unify env ~span ~reason b1 b2

  (* Solve: one side is a concrete nat, the other is a partially-known op.
     E.g. TVar a + TNat 2 = TNat 5  →  a = 3. *)
  | TNatOp (op, a, b), TNat n ->
    solve_nat_eq env ~span ~reason op a b n
  | TNat n, TNatOp (op, a, b) ->
    solve_nat_eq env ~span ~reason op a b n

  (* Session-typed channels unify by checking their current session states match. *)
  | TChan r1, TChan r2 ->
    (* LAUNDERING GUARD (F5 residual, 2026-07-27).  The [Chan.*] operation arms
       reject an unrefined `offer` continuation by PHYSICAL identity against
       [env.offer_unrefined] — but unification does not alias refs, it only
       compares states.  So any construct that mints a fresh [TChan] ref and
       unifies it with the marked one (a `Chan(R, P)` type annotation, an
       `if`/`match` join with another channel, a record field, an annotated
       function parameter at a CALL SITE) would hand back a different, unmarked
       ref carrying the same state — and the physical-identity guard would never
       fire again.  Every such route goes through THIS arm, so reject here: an
       unrefined offer continuation may not be unified with any other channel
       type at all, only refined by a `match` on its paired label.  (Reporting
       rather than propagating the mark is deliberate — propagation cannot help
       across a function boundary, where the callee's body was already checked
       against its own ref.) *)
    if (not (r1 == r2))
       && (offer_ref_unrefined env r1 || offer_ref_unrefined env r2) then
      Err.error env.errors ~span (offer_unrefined_message "This channel")
    else if not (session_ty_equal !r1 !r2) then
      Err.error env.errors ~span
        (Printf.sprintf
           "Session type mismatch: expected channel at `%s` but found `%s`."
           (pp_session_ty !r1) (pp_session_ty !r2))

  | _ ->
    report_mismatch env ~span ~reason t1 t2

(** Solve a type-level nat equation: (op a b) = n.
    Handles exactly the cases where one operand is an unbound TVar and
    the other is a concrete TNat, so we can isolate the variable.
    Falls back to [report_mismatch] for anything more complex. *)
and solve_nat_eq env ~span ~reason op a b n =
  match op, a, b with
  (* a + k = n  →  a = n - k  (when n >= k) *)
  | Ast.NatAdd, TVar _, TNat k when n >= k ->
    unify env ~span ~reason a (TNat (n - k))
  (* k + a = n  →  a = n - k  (when n >= k) *)
  | Ast.NatAdd, TNat k, TVar _ when n >= k ->
    unify env ~span ~reason b (TNat (n - k))
  (* a * k = n  →  a = n / k  (when k divides n) *)
  | Ast.NatMul, TVar _, TNat k when k <> 0 && n mod k = 0 ->
    unify env ~span ~reason a (TNat (n / k))
  (* k * a = n  →  a = n / k  (when k divides n) *)
  | Ast.NatMul, TNat k, TVar _ when k <> 0 && n mod k = 0 ->
    unify env ~span ~reason b (TNat (n / k))
  | _ ->
    report_mismatch env ~span ~reason (TNatOp (op, a, b)) (TNat n)

(* =================================================================
   §2  Surface-type → internal-type conversion
   ================================================================= *)

(** True when [name] denotes a variant/sum type in scope — i.e. some
    constructor has it as its parent type ([ci_type], matched bare or as a
    [.name] suffix since [ci_type] may be module-qualified).

    Records register in [env.records] under their BARE name globally, so a
    user's `type Color = Red | Green | Blue` collides in that flat namespace
    with, e.g., stdlib `Plot.Color = { r, g, b }`.  Without this guard the
    record-structural expansion below (and in [register_impl_shape]) rewrites
    the variant's `impl Eq(Color)` to the record's `TRecord{r,g,b}` shape,
    which then never matches the variant's `TCon("Color")` dispatch target —
    the derived impl becomes invisible and the type "does not implement Eq".
    A variant type is never itself a record, so suppressing the expansion for
    variant names only removes incorrect expansions. *)
let name_is_variant env name =
  let matches ci_type =
    ci_type = name ||
    (let n = String.length name and l = String.length ci_type in
     l > n && ci_type.[l - n - 1] = '.' && String.sub ci_type (l - n) n = name)
  in
  StrMap.exists
    (fun _ cis -> List.exists (fun (ci : ctor_info) -> matches ci.ci_type) cis)
    env.ctors

(* Names of records currently being structurally expanded on the current
   [surface_ty]/[expand_record] call path. A record field that mentions its
   own type — directly (`type Tr = { left : Option(Tr), ... }`) or through a
   cycle of records — would otherwise make expansion require expanding the
   same record again, forever: expanding [Tr]'s fields expands [Option(Tr)],
   which expands its argument [Tr], which re-enters the very branch that
   started this. Shared between [surface_ty] and [expand_record] since a
   chain can pass through either. *)
let expanding_records : StringSet.t ref = ref StringSet.empty

(** Convert a surface [Ast.ty] to an internal [ty].
    [tvars] accumulates a mapping from type-variable *names* to fresh
    unification-variable ids (so that two mentions of [a] in the same
    annotation get the same variable). *)
let rec surface_ty env ~(tvars : (string * ty) list ref) (s : Ast.ty) : ty =
  match s with
  | Ast.TyCon (name, args) ->
    (* Skip when [caller = ""]: either no fn has been entered yet, or (since
       Fix round 1) a callerless surface_ty call site — interface method
       signature, impl header/when-constraint — deliberately blanked
       [current_decl] via [with_no_caller] to suppress recording rather than
       misattribute to an unrelated function. Either way, an empty caller was
       never a meaningful attribution for `forge search --callers`. *)
    (if String.contains name.Ast.txt '.' && !(env.current_decl) <> "" then
       env.refs := { callee = name.Ast.txt;
                     caller = !(env.current_decl);
                     ref_kind = `TypeRef;
                     ref_file = name.Ast.span.Ast.file;
                     ref_line = name.Ast.span.Ast.start_line } :: !(env.refs));
    (* Special case: Chan(Role, Proto) — session-typed channel endpoint.
       Users write Chan(RoleName, ProtoName) in type annotations.
       The parser produces TyCon("Chan", [TyCon("Role",[]), TyCon("Proto",[])]).
       We intercept this before the normal type-lookup path. *)
    (match name.txt, args with
     | "Chan", [Ast.TyCon (role, []); Ast.TyCon (proto, [])] ->
       (match StrMap.find_opt proto.txt env.protocols with
        | None ->
          Err.error env.errors ~span:proto.span
            (Printf.sprintf "I don't know a protocol called `%s`." proto.txt);
          TChan (ref SError)
        | Some pi ->
          (match List.assoc_opt role.txt pi.pi_projections with
           | None ->
             Err.error env.errors ~span:role.span
               (Printf.sprintf
                  "Protocol `%s` has no role called `%s`.\n\
                   Known roles: %s"
                  proto.txt role.txt
                  (String.concat ", " (List.map fst pi.pi_projections)));
             TChan (ref SError)
           | Some sty ->
             TLin (Ast.Linear, TChan (ref sty))))
     | "Chan", _ when name.txt = "Chan" ->
       Err.error env.errors ~span:name.span
         "Chan expects exactly two type arguments: Chan(RoleName, ProtocolName)";
       TChan (ref SError)
     | _ ->
    let env_loaded, arity = match lookup_type name.txt env with
      | Some a -> env, a
      | None   ->
        (* Try qualified module resolution: "Mod.Type" *)
        match resolve_qualified_type name.txt env with
        | env', Some a -> env', a
        | _ ->
          Err.error env.errors ~span:name.span
            (qualified_error_msg name.txt env);
          env, 0
    in
    (* March uses a single global type namespace: a type declared inside a
       module has its *bare* name as its canonical identity.  Both the type's
       own registration and the result type of its constructors use the bare
       form (see the constructor `ci_type = name.txt` sites and the "ci_type is
       the BARE type name" note in Pass 1b).  A *qualified* reference like
       `Token.Token` from outside the module must therefore resolve to the SAME
       nominal `TCon` as the bare `Token`, otherwise a value produced inside the
       module (bare) fails to unify against the qualified annotation with the
       baffling "expected `Token.Token` but got `Token`".  Canonicalize the
       constructor name to its bare suffix whenever that suffix denotes a type
       of the same arity in scope. *)
    let canon_name =
      (* The bare suffix is the component after the LAST '.' (the type's own
         name); everything before is the module path.  Uses its own rindex
         here rather than calling [split_qualified] (same rindex convention
         as of this writing, but this call's purpose — extracting the bare
         type-name suffix — is independent of module-load resolution, so it
         stays deliberately decoupled from that function's behavior.
         Look up the bare suffix in [env_loaded] (not the pre-resolution
         [env]): when [name.txt] needed [resolve_qualified_type] to lazily
         load its module, [load_module_into_env]'s [ExType]/[ExRecord] arms
         seed the BARE name too (first-wins — see their doc comment), so an
         opaque `ptype` seen for the first time via qualification (e.g.
         `RRB.Vec`, never promoted to the outer bare namespace since it's
         never `Public`) still canonicalizes correctly.  Looking this up in
         the original [env] would always miss for such a type, silently
         skipping canonicalization and leaving a real value (whose actual
         type uses the bare `TCon`) unable to unify against the qualified
         annotation. *)
      match String.rindex_opt name.txt '.' with
      | Some i ->
        let bare = String.sub name.txt (i + 1) (String.length name.txt - i - 1) in
        (match lookup_type bare env_loaded with Some a when a = arity -> bare | _ -> name.txt)
      | None -> name.txt
    in
    let args' = List.map (surface_ty env ~tvars) args in
    if List.length args' <> arity then
      Err.error env.errors ~span:name.span
        (Printf.sprintf "`%s` expects %d type argument(s) but got %d."
           name.txt arity (List.length args'));
    (* If this is a named record type, expand it structurally so that
       type annotations like `: Point` unify correctly with record literals.
       Skip when the name also denotes a variant (see [name_is_variant]): the
       local variant shadows a same-named record from another module. *)
    (match StrMap.find_opt name.txt env.records with
     | Some (params, field_decls)
       when List.length params = List.length args'
            && not (name_is_variant env name.txt) ->
       if StringSet.mem name.txt !expanding_records then
         (* Already expanding this record on the current path — a directly
            or mutually self-referential field. Stop unfolding and return
            the plain nominal type instead of recursing forever; [unify]'s
            lazy TCon<->TRecord reconciliation (via [expand_record_ref])
            expands one level on demand wherever a field is actually used,
            so this loses no precision the caller needed right now. *)
         TCon (canon_name, args')
       else begin
         let saved = !tvars in
         List.iter2 (fun pname arg -> tvars := (pname, arg) :: !tvars) params args';
         expanding_records := StringSet.add name.txt !expanding_records;
         let flds =
           Fun.protect
             ~finally:(fun () ->
                 expanding_records := StringSet.remove name.txt !expanding_records)
             (fun () ->
                List.map (fun (fn, fty) -> (fn, surface_ty env ~tvars fty)) field_decls)
         in
         tvars := saved;
         TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) flds)
       end
     | _ ->
       (* For qualified names not in env.records, check the module registry for
          ExRecord entries. This handles record types in modules loaded lazily
          (not pre-registered via stdlib_file_list) so cross-module field access
          and structural unification work correctly without env threading. *)
       let registry_record =
         match split_qualified name.txt with
         | None -> None
         | Some (mod_name, member) ->
           let open March_modules.Module_registry in
           (match ensure_loaded mod_name with
            | None -> None
            | Some exports ->
              List.fold_left (fun acc entry ->
                match acc with
                | Some _ -> acc
                | None ->
                  (match entry.ex_kind with
                   | ExRecord (arity, fields) when entry.ex_name = member ->
                     let params = List.init arity
                       (fun i -> Printf.sprintf "$t%d" i) in
                     (* Thread an env enriched with the DEFINING module's exports
                        so the record's field types — stored as UNRESOLVED surface
                        types that name sibling types by their BARE name (`scope :
                        UniqueScope`) — resolve against those siblings' bare names.
                        Without this the fields would be expanded in the referrer's
                        env, which has only the qualified sibling names, failing
                        with a bogus "I cannot find `UniqueScope`" pointing at the
                        definer's field span.  [load_module_into_env] seeds both
                        the qualified and bare forms (first-wins), so this cannot
                        clobber a name the referrer already bound. *)
                     let fenv = load_module_into_env mod_name exports env in
                     Some (params, fields, fenv)
                   | _ -> None)
              ) None exports.me_entries)
       in
       (match registry_record with
        | Some (params, field_decls, fenv)
          when List.length params = List.length args'
               && not (name_is_variant env name.txt) ->
          let saved = !tvars in
          List.iter2 (fun pname arg -> tvars := (pname, arg) :: !tvars) params args';
          let flds = List.map (fun (fn, fty) -> (fn, surface_ty fenv ~tvars fty)) field_decls in
          tvars := saved;
          TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) flds)
        | _ ->
          (* Normalize built-in unit/bool so surface annotations unify with internal reps *)
          match canon_name with
          | "Unit" -> t_unit
          | _ -> TCon (canon_name, args'))))

  | Ast.TyVar name ->
    (match List.assoc_opt name.txt !tvars with
     | Some t -> t
     | None   ->
       let t = fresh_var env.level in
       tvars := (name.txt, t) :: !tvars;
       t)

  | Ast.TyArrow (a, b) ->
    TArrow (surface_ty env ~tvars a, surface_ty env ~tvars b)

  | Ast.TyTuple ts ->
    TTuple (List.map (surface_ty env ~tvars) ts)

  | Ast.TyRecord flds ->
    let flds' = List.map (fun (n, t) -> (n.Ast.txt, surface_ty env ~tvars t)) flds in
    TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) flds')

  | Ast.TyLinear (lin, t) ->
    TLin (lin, surface_ty env ~tvars t)

  | Ast.TyNat n  -> TNat n
  | Ast.TyNatOp (op, a, b) ->
    TNatOp (op, surface_ty env ~tvars a, surface_ty env ~tvars b)

  | Ast.TyChan (role, proto) ->
    (* Look up the protocol and project onto the given role. *)
    (match StrMap.find_opt proto.txt env.protocols with
     | None ->
       Err.error env.errors ~span:proto.span
         (Printf.sprintf "I don't know a protocol called `%s`." proto.txt);
       TChan (ref SError)
     | Some pi ->
       (match List.assoc_opt role.txt pi.pi_projections with
        | None ->
          Err.error env.errors ~span:role.span
            (Printf.sprintf
               "Protocol `%s` has no role called `%s`.\n\
                Known roles: %s"
               proto.txt role.txt
               (String.concat ", " (List.map fst pi.pi_projections)));
          TChan (ref SError)
        | Some sty ->
          TChan (ref sty)))
  (* Carry the refinement in the internal type.  It is transparent to
     unification (repr strips it), so base-type inference is unchanged; the
     predicate is read only at the deliberate obligation sites. *)
  | Ast.TyRefine (base, binder, pred) ->
    let b = match binder with None -> "_" | Some n -> n.Ast.txt in
    TRefine (surface_ty env ~tvars base, b, pred)

(* Now that surface_ty and generalize are defined, wire up the forward ref so
   resolve_qualified_var can inject interface method bindings cross-module. *)
let () = inject_iface_exports_ref := (fun mod_name exports env ->
  let open March_modules.Module_registry in
  List.fold_left (fun env entry ->
    match entry.ex_kind with
    | ExInterface idef ->
      List.fold_left (fun env (m : Ast.method_decl) ->
        let qname = mod_name ^ "." ^ idef.iface_name.txt ^ "." ^ m.md_name.txt in
        if StrMap.mem qname env.vars then env
        else begin
          (* Use level 1 for the interface type parameter so generalize 0 quantifies it. *)
          let a = fresh_var 1 in
          let tvars = ref [(idef.iface_param.txt, a)] in
          (* No enclosing function checks a cross-module interface's own
             method signature — see [with_no_caller]. *)
          let ty = with_no_caller env (fun () -> surface_ty env ~tvars m.md_ty) in
          let a_id = match a with
            | TVar r -> (match !r with Unbound (id, _) -> id | _ -> 0)
            | _ -> 0
          in
          let base_sch = generalize 0 ty in
          let sch = match base_sch with
            | Poly (ids, cs, t) ->
              Poly (ids, CInterface (idef.iface_name.txt, a) :: cs, t)
            | Mono t ->
              Poly ([a_id], [CInterface (idef.iface_name.txt, a)], t)
          in
          { env with vars = StrMap.add qname sch env.vars }
        end
      ) env idef.iface_methods
    | _ -> env
  ) env exports.me_entries)

(** Instantiate a constructor's type at the current level.
    Creates fresh unification variables for each type parameter of the
    parent type, then converts the constructor's argument surface-types
    using those variables.  Returns [(arg_tys, result_ty)]:
    - [arg_tys]   : the expected type of each constructor argument
    - [result_ty] : the type the fully-applied constructor produces *)
let instantiate_ctor env (ci : ctor_info) : ty list * ty =
  (* One fresh unification variable per type parameter *)
  let fresh_pairs = List.map (fun name -> (name, fresh_var env.level)) ci.ci_params in
  let tvars = ref fresh_pairs in
  (* Convert each argument's surface type, substituting the fresh vars *)
  let arg_tys = List.map (surface_ty env ~tvars) ci.ci_arg_tys in
  (* Build TCon(ParentType, [fresh_a; fresh_b; …]) *)
  let result_ty = TCon (ci.ci_type, List.map snd fresh_pairs) in
  (arg_tys, result_ty)

(** Try to expand a [TCon] of a named record type to [TRecord].
    Returns the [TRecord] type if the name is a known record def, else [None].
    Falls back to the module registry for cross-module record types that were
    loaded lazily (not pre-registered in env.records via stdlib_file_list). *)
let expand_record env ty =
  match repr ty with
  | TRecord _ as t -> Some t
  | TCon (name, args) ->
    let record_info =
      match StrMap.find_opt name env.records with
      | Some _ as r -> r
      | None ->
        (* Qualified type like "NodeIdentity.Identity": check registry for ExRecord *)
        (match split_qualified name with
         | None -> None
         | Some (mod_name, member) ->
           let open March_modules.Module_registry in
           match ensure_loaded mod_name with
           | None -> None
           | Some exports ->
             List.fold_left (fun acc entry ->
               match acc with
               | Some _ -> acc
               | None ->
                 match entry.ex_kind with
                 | ExRecord (arity, fields) when entry.ex_name = member ->
                   let params = List.init arity (fun i ->
                     Printf.sprintf "$t%d" i) in
                   Some (params, fields)
                 | _ -> None
             ) None exports.me_entries)
    in
    (match record_info with
     | Some (params, field_decls) when List.length params = List.length args ->
       if StringSet.mem name !expanding_records then
         (* Same self-referential-record guard as [surface_ty]'s own
            record-expansion branch (they share [expanding_records]): don't
            re-expand a record already being expanded on this path. *)
         Some (TCon (name, args))
       else begin
         let tvars = ref (List.combine params args) in
         expanding_records := StringSet.add name !expanding_records;
         let flds =
           Fun.protect
             ~finally:(fun () ->
                 expanding_records := StringSet.remove name !expanding_records)
             (fun () ->
                List.map (fun (fn, fty) -> (fn, surface_ty env ~tvars fty)) field_decls)
         in
         Some (TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) flds))
       end
     | _ -> None)
  | _ -> None

(* Wire up the forward ref so [unify] (defined earlier) can reconcile a nominal
   record [TCon] with its structural [TRecord] form.  Guard with
   [name_is_variant] exactly as [surface_ty]'s own record-expansion does: in a
   global-namespace collision a variant and a record can share a printed name
   (and the record leaks into [env.records] under that bare name), so a bare
   [TCon] naming the *variant* must NOT be expanded into the colliding record's
   structure — that would silently unify two genuinely distinct types and
   swallow the "two distinct types share the name" diagnostic. *)
let () = expand_record_ref := (fun env ty ->
  match repr ty with
  | TCon (name, _) when name_is_variant env name -> None
  | _ -> expand_record env ty)

(** Register per-field linear sentinels for a named record variable [varname].
    When [ty] is or expands to a TRecord with linear fields, adds phantom
    ["varname#fieldname"] entries to env.lin so that EField accesses on
    that variable can detect double-use of individual linear fields. *)
let bind_linear_field_sentinels varname ty env =
  match expand_record env (repr ty) with
  | Some (TRecord flds) ->
    List.fold_left (fun acc_env (fname, fty) ->
        match repr fty with
        | TLin (lin, _) when lin <> Ast.Unrestricted ->
          let key = varname ^ "#" ^ fname in
          let le = { le_name = key; le_lin = lin; le_used = ref false; le_first_use = ref None } in
          { acc_env with lin = le :: acc_env.lin }
        | _ -> acc_env
      ) env flds
  | _ -> env
