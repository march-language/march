(** @[no_alloc] allocation contracts.

    Design: specs/2026-09-03-allocation-contracts-design.md.

    Attribute bookkeeping (form + spans, keyed by the module-qualified
    pre-Mono TIR name) is collected from the AST here and matched to
    TIR functions by [Tir_names.strip_specialization_suffix] — never by
    mutating an annotated function's TIR, because the verdict must be the
    verdict of the code as it compiles WITHOUT the attribute. *)

type form = Hard | Warn | Assume | Transient

let form_of_attrs (attrs : string list) : form option =
  if List.mem "no_alloc" attrs then Some Hard
  else if List.mem "no_alloc:warn" attrs then Some Warn
  else if List.mem "no_alloc:assume" attrs then Some Assume
  else if List.mem "no_alloc:transient" attrs then Some Transient
  else None

(** The attribute text a form is written as — the inverse of
    [form_of_attrs], used by the generation half. *)
let attr_of_form : form -> string = function
  | Hard -> "@[no_alloc]"
  | Warn -> "@[no_alloc(warn)]"
  | Assume -> "@[no_alloc(assume)]"
  | Transient -> "@[no_alloc(transient)]"

type decl_info = {
  d_name      : string;                 (** module-qualified pre-Mono TIR name *)
  d_form      : form option;
  d_name_span : March_ast.Ast.span;     (** the identifier *)
  d_decl_span : March_ast.Ast.span;     (** the whole [DFn] *)
}

(* Same walk as [Vectorize_mark.collect_attrs]: the module-qualified name is
   exactly what [Lower] gives the TIR fn_def before Mono mangles it. *)
let rec collect_prefixed (prefix : string) (decls : March_ast.Ast.decl list)
  : decl_info list =
  List.concat_map (function
      | March_ast.Ast.DFn (def, span) ->
        [ { d_name = prefix ^ def.March_ast.Ast.fn_name.March_ast.Ast.txt;
            d_form = form_of_attrs def.March_ast.Ast.fn_attrs;
            d_name_span = def.March_ast.Ast.fn_name.March_ast.Ast.span;
            d_decl_span = span } ]
      | March_ast.Ast.DMod (nm, _, inner, _) ->
        collect_prefixed (prefix ^ nm.March_ast.Ast.txt ^ ".") inner
      | _ -> [])
    decls

let collect (m : March_ast.Ast.module_) : decl_info list =
  collect_prefixed "" m.March_ast.Ast.mod_decls

(* ── What counts as an allocation ─────────────────────────────────────── *)

type reason =
  | Ctor of string
  | Tuple
  | Record
  | Update
  | Closure
  | Builtin of string
  | FloatBox
  | AggBox of string           (** unboxed aggregate boxed at an erased slot *)
  | UnknownClosure of string   (** ECallPtr through this variable *)
  | Extern of string
  | Callee of string * reason  (** callee display name, its first reason *)

let rec describe = function
  | Ctor c -> Printf.sprintf "constructor `%s` is allocated here" c
  | Tuple -> "a tuple is allocated here"
  | Record -> "a record is allocated here"
  | Update -> "a record update allocates a new record here"
  | Closure -> "a closure is allocated here"
  | Builtin ("++" | "string_concat" | "string_concat3") -> "string concatenation"
  | Builtin b -> Printf.sprintf "`%s` allocates" b
  | FloatBox -> "a Float is boxed here (it crosses an erased slot)"
  | AggBox t ->
    Printf.sprintf "a `%s` is boxed here (it crosses an erased slot)" t
  | UnknownClosure x -> Printf.sprintf "call through an unknown closure `%s`" x
  | Extern e -> Printf.sprintf "call to the extern `%s`" e
  | Callee (g, r) ->
    Printf.sprintf "calls `%s`, which allocates (in `%s`: %s)" g g (describe r)

(* TOTAL over the closed codegen-dispatched set: adding a constructor to
   [Builtin_name.t] without a row here is a build error (no wildcard arm).
   Classification is by what the runtime does; unclear ⇒ allocating. *)
let named_builtin_allocates : Builtin_name.t -> bool = function
  | Builtin_name.Int_abs | Builtin_name.Int_div | Builtin_name.Int_div_euclid
  | Builtin_name.Int_max_value | Builtin_name.Int_min_value | Builtin_name.Int_mod
  | Builtin_name.Int_mod_euclid | Builtin_name.Int_not | Builtin_name.Int_popcount
  | Builtin_name.Int_pow | Builtin_name.Negate | Builtin_name.Not
  | Builtin_name.Pmap_threshold | Builtin_name.Task_is_cancelled
  | Builtin_name.Task_reductions | Builtin_name.Signal_raise_self -> false
  | Builtin_name.Bool_to_string | Builtin_name.Float_to_string
  | Builtin_name.Int_to_string | Builtin_name.To_string
  | Builtin_name.Html_auto_escape | Builtin_name.Html_escape_ctx
  | Builtin_name.Actor_register | Builtin_name.Actor_reply
  | Builtin_name.Chan_choose | Builtin_name.Chan_send | Builtin_name.Get_work_pool
  | Builtin_name.Mpst_send | Builtin_name.Receive | Builtin_name.Record_from_list
  | Builtin_name.Record_get | Builtin_name.Record_has_key | Builtin_name.Record_put
  | Builtin_name.Remote_ref_hashes | Builtin_name.Send
  | Builtin_name.Signal_unwatch | Builtin_name.Signal_watch
  | Builtin_name.Task_await | Builtin_name.Task_await_unwrap
  | Builtin_name.Task_cancel | Builtin_name.Task_cancel_by_id
  | Builtin_name.Task_cancel_token_new | Builtin_name.Task_spawn
  | Builtin_name.Task_spawn_steal | Builtin_name.Task_spawn_with_cancel
  | Builtin_name.Task_yield
  | Builtin_name.Vault_drop | Builtin_name.Vault_get | Builtin_name.Vault_incr
  | Builtin_name.Vault_ns_drop | Builtin_name.Vault_ns_get | Builtin_name.Vault_ns_set
  | Builtin_name.Vault_push_capped | Builtin_name.Vault_put_new | Builtin_name.Vault_set
  | Builtin_name.Vault_set_ttl | Builtin_name.Vault_update -> true

(* Non-allocating builtins that are NOT codegen-dispatched through
   [Builtin_name] (they go through the generic runtime-call fallback or are
   emitted inline): scalar arithmetic, comparisons, predicates, and reads of
   existing cells.  Anything not listed here is allocating. *)
let scalar_builtins = [
  "+"; "-"; "*"; "/"; "%"; "+."; "-."; "*."; "/."; "<"; ">"; "<="; ">="; "&&"; "||";
  "=="; "!="; "compare_int"; "compare_float"; "compare_string";
  "int_and"; "int_or"; "int_xor"; "int_shl"; "int_shr"; "int_to_float";
  "float_to_int"; "float_abs"; "float_ceil"; "float_floor"; "float_round";
  "float_truncate"; "float_is_nan"; "float_is_infinite"; "float_infinity";
  "float_neg_infinity"; "float_nan"; "float_epsilon";
  "math_sqrt"; "math_cbrt"; "math_pow"; "math_exp"; "math_exp2"; "math_log";
  "math_log2"; "math_log10"; "math_sin"; "math_cos"; "math_tan"; "math_asin";
  "math_acos"; "math_atan"; "math_atan2"; "math_sinh"; "math_cosh"; "math_tanh";
  "char_is_alpha"; "char_is_digit"; "char_is_alphanumeric"; "char_is_whitespace";
  "char_is_uppercase"; "char_is_lowercase"; "char_to_int"; "char_from_int";
  "byte_to_char"; "char_to_uppercase"; "char_to_lowercase";
  "string_length"; "string_byte_length"; "string_byte_at"; "string_is_empty";
  "is_nil"; "head"; "tail";
  (* Divergence, not allocation: these never return, so no path through them
     reaches a caller with a heap value.  The message is a literal (a global
     constant), and the match fall-through lower_match inserts calls `panic_`
     — without this entry every `match` would fail its contract. *)
  "panic"; "panic_"; "todo_"; "unreachable_"; "process_exit";
  (* Reference counting and freeing, not allocating: [Drop.run] synthesizes a
     call to [march_decrc_freed] inside every generated __drop$T helper, so
     without this entry any function that drops an owned value fails. *)
  "march_decrc_freed"; "march_incrc"; "march_decrc"; "march_free";
  "native_int_arr_get"; "native_int_arr_length"; "native_int_arr_set"; "native_int_arr_sum";
  "native_float_arr_get"; "native_float_arr_length"; "native_float_arr_set"; "native_float_arr_sum";
  "native_f32_arr_get"; "native_f32_arr_length"; "native_f32_arr_set"; "native_f32_arr_sum";
  "native_i32_arr_get"; "native_i32_arr_length"; "native_i32_arr_set"; "native_i32_arr_sum";
  "native_u8_arr_get"; "native_u8_arr_length"; "native_u8_arr_set"; "native_u8_arr_sum";
  "native_int_arr_max"; "native_int_arr_min"; "native_float_arr_max"; "native_float_arr_min";
]

let scalar_set : (string, unit) Hashtbl.t =
  let h = Hashtbl.create 128 in
  List.iter (fun n -> Hashtbl.replace h n ()) scalar_builtins;
  h

let base = Tir_names.strip_specialization_suffix

let builtin_allocates (name : string) : bool =
  let b = base name in
  match Builtin_name.of_string b with
  | Some c -> named_builtin_allocates c
  | None -> not (Hashtbl.mem scalar_set b)

(* ── Float boxing ──────────────────────────────────────────────────────── *)

let ty_of_atom = function
  | Tir.AVar v -> v.Tir.v_ty
  | Tir.ALit (March_ast.Ast.LitFloat _) -> Tir.TFloat
  | Tir.ALit (March_ast.Ast.LitInt _) -> Tir.TInt
  | _ -> Tir.TUnit

(* An [EAlloc]/[EReuse] constructor key is "Type.Ctor" (lower_expr's
   [ctor_key]); the variant definition keys its constructors by the bare
   name.  Split at the last '.'. *)
let split_ctor_key (key : string) : string option * string =
  match String.rindex_opt key '.' with
  | Some i -> (Some (String.sub key 0 i), String.sub key (i + 1) (String.length key - i - 1))
  | None -> (None, key)

let ctor_short (key : string) : string = snd (split_ctor_key key)

(* Declared field types of the constructor / record / tuple [ty] builds. *)
let ctor_fields (m : Tir.tir_module) (ty : Tir.ty) : Tir.ty list option =
  match ty with
  | Tir.TTuple ts -> Some ts
  | Tir.TRecord fs -> Some (List.map snd fs)
  | Tir.TCon (key, _) ->
    let (tname, ctor) = split_ctor_key key in
    let exact =
      List.find_map (function
          | Tir.TDVariant (n, ctors) when tname = None || tname = Some n ->
            List.assoc_opt ctor ctors
          | Tir.TDRecord (n, fs) when n = key -> Some (List.map snd fs)
          | Tir.TDClosure (n, tys) when n = key -> Some tys
          | _ -> None) m.Tir.tm_types
    in
    (match exact with
     | Some _ -> exact
     | None ->
       (* Unqualified fallback: any variant declaring this constructor. *)
       List.find_map (function
           | Tir.TDVariant (_, ctors) -> List.assoc_opt ctor ctors
           | _ -> None) m.Tir.tm_types)
  | _ -> None

(* A Float stored into a slot whose declared type is not TFloat is boxed by
   [Llvm_ctx.coerce] ("double" -> "ptr"): a march_alloc_float cell.  [skip]
   is the index of a TRMC hole, absent from [args]. *)
let stores_boxed_float ?skip m ty args =
  match ctor_fields m ty with
  | None -> false
  | Some fields ->
    let fields = match skip with
      | None -> fields
      | Some h -> List.filteri (fun i _ -> i <> h) fields in
    List.length fields = List.length args
    && List.exists2 (fun a f -> ty_of_atom a = Tir.TFloat && f <> Tir.TFloat) args fields

(* The unboxed-aggregate analogue of [stores_boxed_float].  An inline
   aggregate stored into a slot whose declared type is not that aggregate is
   BOXED by [Llvm_ctx.coerce] into the very heap cell the representation
   exists to avoid — a real [march_alloc], reported as one.  Returns the
   aggregate's type name for the diagnostic. *)
let stores_boxed_agg ?skip m ty args : string option =
  match ctor_fields m ty with
  | None -> None
  | Some fields ->
    let fields = match skip with
      | None -> fields
      | Some h -> List.filteri (fun i _ -> i <> h) fields in
    if List.length fields <> List.length args then None
    else
      List.find_map (fun (a, f) ->
          match ty_of_atom a with
          | Tir.TCon (n, _) as at
            when Repr.unboxed_of_type_name n <> None && f <> at -> Some n
          | _ -> None)
        (List.combine args fields)

(* Whether an [EAlloc]/[EAllocHole] of constructor key [key] actually reaches
   the heap.  Codegen elides two shapes entirely, and a checker that ignored
   them would reject allocation-free code:

   - [Repr.Newtype]: represented as the raw payload, no cell at all.
   - [Repr.Unboxed]: a small scalar-only single-ctor variant, built with
     [insertvalue] in registers.
   - Niche (Option-shaped) with a niche-safe or erased payload: None = 0,
     Some(x) = x.  A niche-UNSAFE payload (Float, Option(Option(_)), ...)
     falls through to a real boxed cell, so it still counts.

   Mirrors [Llvm_emit_alloc]'s own arms; keep the two in step. *)
let alloc_is_elided ~collision_set (m : Tir.tir_module) (key : string)
    (args : Tir.atom list) : bool =
  let (tname_opt, _ctor) = split_ctor_key key in
  match tname_opt with
  | None -> false
  | Some tname ->
    let type_defs = m.Tir.tm_types in
    (match Repr.repr_of_ty ~collision_set type_defs (Tir.TCon (tname, [])) with
     | Repr.Newtype _ -> true
     (* Milestone 3: an unboxed aggregate's construction is an [insertvalue]
        chain in registers — [Llvm_emit_alloc]'s [Repr.Unboxed] arm.  No cell,
        so no allocation, so a function that only builds them satisfies the
        contract. *)
     | Repr.Unboxed _ -> true
     | _ ->
       Repr.is_niche_shaped ~collision_set type_defs tname
       && (match args with
           | [] -> true
           | [ arg ] ->
             let t = ty_of_atom arg in
             Repr.niche_payload_ok ~collision_set type_defs t
             || (match t with Tir.TVar _ -> true | _ -> false)
           | _ -> false))

(* A capture-free lambda becomes a static, immortal global closure rather than
   a heap cell (Llvm_emit's [emit_static_closure] arm): a [$Clo_] alloc whose
   only argument is the apply-fn pointer.  Hot-reload and the REPL disable
   that path, so this mirrors only the ordinary compile. *)
let closure_is_static (args : Tir.atom list) : bool =
  match args with
  | [ (Tir.AVar _ | Tir.ADefRef _) ] -> true
  | _ -> false

(* ── Per-function classification ───────────────────────────────────────── *)

let has_reuse_or_stack (e : Tir.expr) : bool =
  Policy_dce.fold_expr (fun acc e ->
      acc || (match e with
          | Tir.EReuse _ | Tir.EStackAlloc _ | Tir.EAllocHole (Some _, _, _, _) -> true
          | _ -> false)) false e

let decl_of decls name = List.find_opt (fun d -> d.d_name = base name) decls

let is_assume ~decls name =
  match decl_of decls name with
  | Some { d_form = Some Assume; _ } -> true
  | _ -> false

let display_name name =
  match Tir_names.apply_fn_base name with
  | Some b -> base b
  | None -> base name

(* First direct reason in [body], in evaluation order ([Policy_dce.fold_expr]
   visits a node, then its sub-expressions in order). *)
let direct_reason ~(m : Tir.tir_module) ~collision_set ~fns ~externs
    (body : Tir.expr) : reason option =
  let found = ref None in
  let set r = if !found = None then found := Some r in
  let elided key args = alloc_is_elided ~collision_set m key args in
  Policy_dce.fold_expr (fun () e ->
      match e with
      | Tir.EAlloc (Tir.TCon (c, _), args) when Tir_names.is_clo_struct c ->
        if not (closure_is_static args) then set Closure
      | Tir.EAlloc (Tir.TCon (c, _), args) ->
        if not (elided c args) then begin
          if stores_boxed_float m (Tir.TCon (c, [])) args then set FloatBox
          else set (Ctor (ctor_short c))
        end else
          (* Elided cell, but an inline aggregate stored into one of its
             erased slots is still boxed into a real one. *)
          (match stores_boxed_agg m (Tir.TCon (c, [])) args with
           | Some t -> set (AggBox t)
           | None -> ())
      | Tir.EAlloc (ty, _) -> set (Ctor (Tir.show_ty ty))
      | Tir.EAllocHole (None, Tir.TCon (c, _), _, _) -> set (Ctor (ctor_short c))
      | Tir.EAllocHole (None, ty, _, _) -> set (Ctor (Tir.show_ty ty))
      | Tir.ETuple (_ :: _) -> set Tuple
      | Tir.ERecord _ -> set Record
      | Tir.EUpdate _ -> set Update
      (* A reused or stack-promoted cell still BOXES a Float it stores into an
         erased slot: that box is a fresh march_alloc_float heap cell. *)
      | Tir.EReuse (_, ty, args) when stores_boxed_float m ty args -> set FloatBox
      | Tir.EStackAlloc (ty, args) when stores_boxed_float m ty args -> set FloatBox
      | Tir.EReuse (_, ty, args) | Tir.EStackAlloc (ty, args)
        when stores_boxed_agg m ty args <> None ->
        (match stores_boxed_agg m ty args with
         | Some t -> set (AggBox t) | None -> ())
      | Tir.EAllocHole (Some _, ty, args, hole)
        when stores_boxed_float ~skip:hole m ty args -> set FloatBox
      | Tir.ECallPtr (Tir.AVar f, _) -> set (UnknownClosure f.Tir.v_name)
      | Tir.ECallPtr (Tir.ADefRef d, _) -> set (UnknownClosure d.Tir.did_name)
      | Tir.ECallPtr (Tir.ALit _, _) -> set (UnknownClosure "<closure>")
      | Tir.EApp (f, args) ->
        let n = f.Tir.v_name in
        if Hashtbl.mem fns n then begin
          (* Boundary B: a direct apply-fn call passes every arg through the
             uniform ptr closure ABI, boxing Floats via march_alloc_float. *)
          if Tir_names.is_apply_fn n
             && List.exists (fun a -> ty_of_atom a = Tir.TFloat) args
          then set FloatBox
          else if Tir_names.is_apply_fn n then
            (* Same boundary for an inline aggregate: the uniform ptr closure
               ABI boxes it. *)
            (match List.find_map (fun a -> match ty_of_atom a with
                 | Tir.TCon (t, _) when Repr.unboxed_of_type_name t <> None -> Some t
                 | _ -> None) args with
            | Some t -> set (AggBox t)
            | None -> ())
        end
        else if Hashtbl.mem externs n then set (Extern n)
        else if builtin_allocates n then set (Builtin (base n))
      | _ -> ()) () body;
  !found

(* The transitive allocating set: seed with direct reasons, then a fixpoint
   over the call graph (the [Policy_dce.panicky_fns_of_module] pattern).  A
   function marked @[no_alloc(assume)] is never in the set, whatever its
   body — that is the whole point of the form. *)
let allocating_fns ~decls (m : Tir.tir_module) : (string, reason) Hashtbl.t =
  let fns = Hashtbl.create 64 in
  List.iter (fun fd -> Hashtbl.replace fns fd.Tir.fn_name ()) m.Tir.tm_fns;
  let externs = Hashtbl.create 16 in
  List.iter (fun e -> Hashtbl.replace externs e.Tir.ed_march_name ()) m.Tir.tm_externs;
  let collision_set = Collision_set.compute m.Tir.tm_types in
  let set : (string, reason) Hashtbl.t = Hashtbl.create 64 in
  List.iter (fun fd ->
      if not (is_assume ~decls fd.Tir.fn_name) then
        match direct_reason ~m ~collision_set ~fns ~externs fd.Tir.fn_body with
        | Some r -> Hashtbl.replace set fd.Tir.fn_name r
        | None -> ()) m.Tir.tm_fns;
  let callees fd =
    List.rev (Policy_dce.fold_expr (fun acc e ->
        match e with
        | Tir.EApp (f, _) -> f.Tir.v_name :: acc
        | _ -> acc) [] fd.Tir.fn_body) in
  let rec fix () =
    let changed = ref false in
    List.iter (fun fd ->
        let n = fd.Tir.fn_name in
        if not (Hashtbl.mem set n) && not (is_assume ~decls n) then
          match List.find_opt (fun c -> Hashtbl.mem set c) (callees fd) with
          | Some c ->
            Hashtbl.replace set n (Callee (display_name c, Hashtbl.find set c));
            changed := true
          | None -> ()) m.Tir.tm_fns;
    if !changed then fix ()
  in
  fix ();
  set

(* ── @[no_alloc(transient)] ────────────────────────────────────────────

   "This function allocates nothing that SURVIVES the call": every allocation
   it or its callees perform is released before it returns.  That is the
   property a frame loop actually has and the base contract cannot state — the
   engine that motivated this allocates ~a dozen cells per frame and frees all
   of them in the same frame, a net live-object delta of 1.

   The verdict is the conjunction of two questions, each a fixpoint over the
   call graph, and both are about where a value ENDS UP rather than about
   whether one was made:

   1. [returns_fresh f] — may [f]'s returned value BE a fresh allocation?
      Whatever a function returns outlives the call by definition, so a
      function that returns something it allocated retains it.  An
      [EReuse]/[EAllocHole (Some _)] result does not count: that cell came in
      through a parameter, so returning it hands back the caller's own object.
      Nor does an [EStackAlloc] — escape analysis only produces one for a
      value it proved does not leave the frame.

   2. [leaks f] — does [f] hand a value to something with its own lifetime?
      An [ESetField] write into an object [f] did not allocate, a message to
      an actor mailbox, a [Vault] write, a spawned task's closure, an extern,
      or a call through an unknown closure.  Unlike (1) these are not visible
      in the return type at all, which is exactly why they need their own
      classification.

   [f] is transient iff neither holds for [f] and neither holds for anything
   [f] calls.  Note what this deliberately ACCEPTS and what it does not:

   - a callee that allocates freely and returns the result, whose result [f]
     drops before returning — accepted, and the whole point of the form;
   - an amortized growth path (a buffer that reallocates its storage and keeps
     the new storage) — REJECTED, because the new storage reaches a returned
     value and is therefore retained.  Nobody should expect this form to cover
     that case; see the docs.

   Blind spot, shared with the base contract: a value that is neither released
   nor reachable — a leak — is not "retained" by this analysis, because
   nothing in the final TIR says where it went.  The form pins "does not
   retain", not "does not leak"; [march_live_allocs] is the instrument for the
   latter. *)

type retain =
  | RReturn of string          (** returns a freshly allocated `X` *)
  | RSetField                  (** writes into an object it did not allocate *)
  | RBuiltin of string         (** hands a value to a longer-lived place *)
  | RExtern of string
  | RUnknownClosure of string
  | RCallee of string * retain (** callee display name, its first reason *)

let rec describe_retain = function
  | RReturn what -> Printf.sprintf "it returns a freshly allocated %s" what
  | RSetField -> "it writes into an object it did not allocate"
  | RBuiltin b -> Printf.sprintf "`%s` hands its argument somewhere longer-lived" b
  | RExtern e -> Printf.sprintf "it calls the extern `%s`" e
  | RUnknownClosure x -> Printf.sprintf "it calls through an unknown closure `%s`" x
  | RCallee (g, r) ->
    Printf.sprintf "it calls `%s`, which retains (in `%s`: %s)" g g (describe_retain r)

(* TOTAL over the closed codegen-dispatched set, like [named_builtin_allocates]
   above: adding a constructor to [Builtin_name.t] without a row here is a
   build error.  The question is NOT "does it allocate" but "does it put a
   value somewhere that outlives this call". *)
let named_builtin_retains : Builtin_name.t -> bool = function
  (* Hands a value to a mailbox, a task, a channel, a registry or a Vault —
     all of which outlive the call. *)
  | Builtin_name.Send | Builtin_name.Actor_reply | Builtin_name.Actor_register
  | Builtin_name.Chan_send | Builtin_name.Chan_choose | Builtin_name.Mpst_send
  | Builtin_name.Task_spawn | Builtin_name.Task_spawn_steal
  | Builtin_name.Task_spawn_with_cancel | Builtin_name.Task_cancel_token_new
  | Builtin_name.Signal_watch | Builtin_name.Get_work_pool
  | Builtin_name.Vault_get | Builtin_name.Vault_incr | Builtin_name.Vault_ns_get
  | Builtin_name.Vault_ns_set | Builtin_name.Vault_push_capped
  | Builtin_name.Vault_put_new | Builtin_name.Vault_set | Builtin_name.Vault_set_ttl
  | Builtin_name.Vault_update -> true
  (* Produces a fresh value and hands it back, or reads/removes one: nothing
     the caller passed in acquires a longer life. *)
  | Builtin_name.Bool_to_string | Builtin_name.Float_to_string
  | Builtin_name.Int_to_string | Builtin_name.To_string
  | Builtin_name.Html_auto_escape | Builtin_name.Html_escape_ctx
  | Builtin_name.Int_abs | Builtin_name.Int_div | Builtin_name.Int_div_euclid
  | Builtin_name.Int_max_value | Builtin_name.Int_min_value | Builtin_name.Int_mod
  | Builtin_name.Int_mod_euclid | Builtin_name.Int_not | Builtin_name.Int_popcount
  | Builtin_name.Int_pow | Builtin_name.Negate | Builtin_name.Not
  | Builtin_name.Pmap_threshold | Builtin_name.Task_is_cancelled
  | Builtin_name.Task_reductions | Builtin_name.Signal_raise_self
  | Builtin_name.Receive | Builtin_name.Record_from_list
  | Builtin_name.Record_get | Builtin_name.Record_has_key | Builtin_name.Record_put
  | Builtin_name.Remote_ref_hashes
  | Builtin_name.Signal_unwatch
  | Builtin_name.Task_await | Builtin_name.Task_await_unwrap
  | Builtin_name.Task_cancel | Builtin_name.Task_cancel_by_id
  | Builtin_name.Task_yield
  | Builtin_name.Vault_drop | Builtin_name.Vault_ns_drop -> false

let builtin_retains (name : string) : bool =
  match Builtin_name.of_string (base name) with
  | Some c -> named_builtin_retains c
  | None -> false   (* the generic runtime-call fallback: arithmetic, string
                       and array primitives, none of which take custody *)

(* Does the expression in TAIL position produce a value this function freshly
   allocated, and/or one that CARRIES one of the function's own arguments?

   Two answers, computed together because the second is what makes the first
   sound across a call.  A function whose result merely passes an argument
   through — `copy_into(src, dst, ...) = dst`, or a reused cell rebuilt with an
   argument in a field — allocates nothing itself, so the first question alone
   answers "not fresh". But at a CALL SITE whose argument IS fresh, that
   pass-through hands the fresh value straight back:

   {v
     pfn grow(d, n, cap) = copy_into(d, NativeArray.make_f32(cap, 0.0), 0, n)
     fn push(b, v) = match b do F32Buf(d, n, cap) -> ... F32Buf(grow(...), ...)
   v}

   The array `grow` returns is freshly allocated and ends up inside the buffer
   `push` returns — the amortized growth path, which `transient` must reject.
   Asking only "does the callee return something fresh" misses it, because the
   freshness entered `grow` through a parameter. So the pair is:

   - [fresh]        — this expression's value was allocated here (or by a
                      callee that returns something fresh);
   - [carries_arg]  — this expression's value IS, or CONTAINS, one of this
                      function's parameters.

   At an [EApp], the result is fresh if the callee returns fresh OR (the callee
   carries an argument through AND the argument at that site is fresh here).
   The second clause is deliberately imprecise about WHICH argument — matching
   positions would be more exact and is not worth the machinery for a
   conservative check.  The same pass-through rule applies to a NON-allocating
   builtin: `NativeArray.set_f32(d, i, v)` allocates nothing but hands `d`
   back, so its result carries whatever `d` carried.

   [scalar_result] is what keeps that conservatism from swallowing everything:
   a value whose type is [Int]/[Float]/[Bool]/[Unit] cannot CONTAIN a heap
   value, so it is never fresh however it was computed.  Without it
   `String.byte_size(describe(i))` would count as retaining the String it
   measured, and the form's flagship case — a callee that allocates and whose
   result is dropped — would fail. *)

(* A value of this type cannot contain a heap value, so it can never carry a
   retained allocation.  Note [Tir.TCon ("Atom", [])] is an interned i64. *)
let scalar_result : Tir.ty -> bool = function
  | Tir.TInt | Tir.TFloat | Tir.TBool | Tir.TUnit -> true
  | Tir.TCon ("Atom", []) -> true
  | _ -> false

let rec returns_fresh_expr ~m ~collision_set ~fns ~returns_fresh ~carries_arg
    ~(params : (string, unit) Hashtbl.t)
    (fresh : (string, unit) Hashtbl.t) (e : Tir.expr) : string option =
  let recur = returns_fresh_expr ~m ~collision_set ~fns ~returns_fresh
      ~carries_arg ~params in
  let arg_is_fresh = function
    | Tir.AVar v -> Hashtbl.mem fresh v.Tir.v_name
    | _ -> false in
  let any_fresh args = List.exists arg_is_fresh args in
  match e with
  | Tir.ELet (v, rhs, body) ->
    (match recur fresh rhs with
     | Some _ when not (scalar_result v.Tir.v_ty) ->
       Hashtbl.replace fresh v.Tir.v_name ()
     | _ -> Hashtbl.remove fresh v.Tir.v_name);
    recur fresh body
  | Tir.ESeq (_, e2) -> recur fresh e2
  | Tir.ECase (_, branches, default) ->
    let from_branches =
      List.find_map (fun br ->
          (* Branch binders are FIELDS of the scrutinee: owned by it, not
             freshly allocated here. *)
          List.iter (fun (bv : Tir.var) -> Hashtbl.remove fresh bv.Tir.v_name)
            br.Tir.br_vars;
          recur fresh br.Tir.br_body) branches in
    (match from_branches with
     | Some _ as r -> r
     | None -> (match default with Some d -> recur fresh d | None -> None))
  | Tir.EAtom (Tir.AVar v) ->
    if Hashtbl.mem fresh v.Tir.v_name then Some (Tir.show_ty v.Tir.v_ty) else None
  | Tir.EAlloc (Tir.TCon (c, _), args) when Tir_names.is_clo_struct c ->
    if closure_is_static args then None else Some "closure"
  | Tir.EAlloc (Tir.TCon (c, _), args) ->
    if alloc_is_elided ~collision_set m c args then None
    else Some (Printf.sprintf "`%s`" (ctor_short c))
  | Tir.EAlloc (ty, _) -> Some (Printf.sprintf "`%s`" (Tir.show_ty ty))
  | Tir.EAllocHole (None, Tir.TCon (c, _), _, _) ->
    Some (Printf.sprintf "`%s`" (ctor_short c))
  | Tir.ETuple (_ :: _) -> Some "tuple"
  | Tir.ERecord _ -> Some "record"
  | Tir.EUpdate _ -> Some "record"
  (* A reused or hole-filled CELL is not fresh — it is the caller's own object
     handed back — but a freshly allocated value stored into one of its FIELDS
     survives in it just the same, so the arguments still count.  A stack cell
     never leaves the frame at all. *)
  | Tir.EReuse (_, _, args) | Tir.EAllocHole (Some _, _, args, _) ->
    if any_fresh args then Some "value stored into the reused cell" else None
  | Tir.EStackAlloc _ -> None
  | Tir.ECallPtr _ -> Some "value from an unknown closure"
  | Tir.EApp (f, args) ->
    let n = f.Tir.v_name in
    if Hashtbl.mem fns n then
      (if Hashtbl.mem returns_fresh n then
         Some (Printf.sprintf "value from `%s`" (display_name n))
       else if Hashtbl.mem carries_arg n && any_fresh args then
         Some (Printf.sprintf "value passed through `%s`" (display_name n))
       else None)
    else if builtin_allocates n then Some (Printf.sprintf "value from `%s`" (base n))
    else if any_fresh args then
      (* A non-allocating builtin that hands one of its arguments back —
         `NativeArray.set_f32(d, i, v)` returns `d`.  Filtered by
         [scalar_result] wherever the result cannot hold anything. *)
      Some (Printf.sprintf "value passed through `%s`" (base n))
    else None
  | _ -> None

(* The companion answer: may this TAIL expression's value be, or contain, one
   of the enclosing function's parameters?  See [returns_fresh_expr]'s comment
   for why the two are computed together. *)
let rec carries_arg_expr ~fns ~carries_arg
    ~(params : (string, unit) Hashtbl.t) (e : Tir.expr) : bool =
  let recur = carries_arg_expr ~fns ~carries_arg ~params in
  let is_param = function
    | Tir.AVar v -> Hashtbl.mem params v.Tir.v_name
    | _ -> false in
  let any_param args = List.exists is_param args in
  match e with
  | Tir.ELet (v, rhs, body) ->
    (* A local bound to something carrying an argument carries it onward. *)
    if recur rhs then Hashtbl.replace params v.Tir.v_name ()
    else Hashtbl.remove params v.Tir.v_name;
    recur body
  | Tir.ESeq (_, e2) -> recur e2
  | Tir.ECase (_, branches, default) ->
    List.exists (fun br ->
        (* Branch binders are fields OF the scrutinee: if the scrutinee carries
           an argument, so does each field extracted from it. *)
        List.iter (fun (bv : Tir.var) -> Hashtbl.replace params bv.Tir.v_name ())
          br.Tir.br_vars;
        recur br.Tir.br_body) branches
    || (match default with Some d -> recur d | None -> false)
  | Tir.EAtom a -> is_param a
  | Tir.EAlloc (_, args) | Tir.ETuple args | Tir.EReuse (_, _, args)
  | Tir.EAllocHole (_, _, args, _) | Tir.EStackAlloc (_, args) -> any_param args
  | Tir.ERecord fields -> any_param (List.map snd fields)
  | Tir.EUpdate (base_a, fields) -> is_param base_a || any_param (List.map snd fields)
  | Tir.EField (a, _) -> is_param a
  | Tir.ECallPtr _ -> true   (* unknown callee: assume it hands an argument back *)
  | Tir.EApp (f, args) ->
    let n = f.Tir.v_name in
    if Hashtbl.mem fns n then Hashtbl.mem carries_arg n && any_param args
    else any_param args      (* a builtin: conservatively pass-through *)
  | _ -> false

(* The first place [fd] hands a value to something with its own lifetime. *)
let direct_leak ~fns ~externs ~assume (fd : Tir.fn_def) : retain option =
  let found = ref None in
  let set r = if !found = None then found := Some r in
  Policy_dce.fold_expr (fun () e ->
      match e with
      | Tir.ESetField _ -> set RSetField
      (* An extern reached through a resolved pointer rather than a direct
         [EApp] is still an extern; say so, or the diagnostic sends the reader
         looking for a closure that does not exist in their source. *)
      | Tir.ECallPtr (Tir.AVar f, _) when not assume ->
        set (if Hashtbl.mem externs f.Tir.v_name then RExtern f.Tir.v_name
             else RUnknownClosure f.Tir.v_name)
      | Tir.ECallPtr (Tir.ADefRef d, _) when not assume ->
        set (if Hashtbl.mem externs d.Tir.did_name then RExtern d.Tir.did_name
             else RUnknownClosure d.Tir.did_name)
      | Tir.ECallPtr (Tir.ALit _, _) when not assume ->
        set (RUnknownClosure "<closure>")
      | Tir.EApp (f, _) ->
        let n = f.Tir.v_name in
        if Hashtbl.mem fns n then ()
        else if Hashtbl.mem externs n then (if not assume then set (RExtern n))
        else if builtin_retains n then set (RBuiltin (base n))
      | _ -> ()) () fd.Tir.fn_body;
  !found

(** The two fixpoints, and the per-function transient verdict computed from
    them.  Returns the reason a function FAILS the transient contract, or
    [None] when it holds. *)
let retaining_fns ~decls (m : Tir.tir_module) : (string, retain) Hashtbl.t =
  let fns = Hashtbl.create 64 in
  List.iter (fun (fd : Tir.fn_def) -> Hashtbl.replace fns fd.Tir.fn_name ()) m.Tir.tm_fns;
  (* Keyed by every spelling an extern's call site can carry: its March name,
     its C symbol, and the last segment of each.  A direct [EApp] names it the
     March way; a call the pipeline resolved to a pointer ([ECallPtr]) can
     carry either, qualified or not, and answering "unknown closure" for an
     extern the user can see in their own source is a worse diagnostic than no
     diagnostic. *)
  let externs = Hashtbl.create 16 in
  let add_extern n =
    if n <> "" then begin
      Hashtbl.replace externs n ();
      match String.rindex_opt n '.' with
      | Some i -> Hashtbl.replace externs (String.sub n (i + 1) (String.length n - i - 1)) ()
      | None -> ()
    end
  in
  List.iter (fun (e : Tir.extern_decl) ->
      add_extern e.Tir.ed_march_name; add_extern e.Tir.ed_c_name) m.Tir.tm_externs;
  let collision_set = Collision_set.compute m.Tir.tm_types in
  let params_of (fd : Tir.fn_def) =
    let h = Hashtbl.create 8 in
    List.iter (fun (p : Tir.var) -> Hashtbl.replace h p.Tir.v_name ()) fd.Tir.fn_params;
    h
  in
  (* Fixpoint 1a: which functions may hand one of their own arguments back.
     Runs to completion first because fixpoint 1b consults it. *)
  let carries_arg = Hashtbl.create 64 in
  let rec fix_ca () =
    let changed = ref false in
    List.iter (fun (fd : Tir.fn_def) ->
        if not (Hashtbl.mem carries_arg fd.Tir.fn_name)
        && carries_arg_expr ~fns ~carries_arg ~params:(params_of fd) fd.Tir.fn_body
        then begin Hashtbl.replace carries_arg fd.Tir.fn_name (); changed := true end)
      m.Tir.tm_fns;
    if !changed then fix_ca ()
  in
  fix_ca ();
  (* Fixpoint 1b: which functions may return a freshly allocated value. *)
  let returns_fresh : (string, string) Hashtbl.t = Hashtbl.create 64 in
  let rf_names = Hashtbl.create 64 in
  let rec fix_rf () =
    let changed = ref false in
    List.iter (fun (fd : Tir.fn_def) ->
        if not (Hashtbl.mem returns_fresh fd.Tir.fn_name)
        && not (scalar_result fd.Tir.fn_ret_ty) then
          match returns_fresh_expr ~m ~collision_set ~fns ~returns_fresh:rf_names
                  ~carries_arg ~params:(params_of fd)
                  (Hashtbl.create 16) fd.Tir.fn_body with
          | Some what ->
            Hashtbl.replace returns_fresh fd.Tir.fn_name what;
            Hashtbl.replace rf_names fd.Tir.fn_name ();
            changed := true
          | None -> ()) m.Tir.tm_fns;
    if !changed then fix_rf ()
  in
  fix_rf ();
  (* Fixpoint 2: retention, seeded with both direct answers. *)
  let set : (string, retain) Hashtbl.t = Hashtbl.create 64 in
  List.iter (fun (fd : Tir.fn_def) ->
      let n = fd.Tir.fn_name in
      if not (is_assume ~decls n) then begin
        match direct_leak ~fns ~externs ~assume:false fd with
        | Some r -> Hashtbl.replace set n r
        | None ->
          match Hashtbl.find_opt returns_fresh n with
          | Some what -> Hashtbl.replace set n (RReturn what)
          | None -> ()
      end) m.Tir.tm_fns;
  let callees (fd : Tir.fn_def) =
    List.rev (Policy_dce.fold_expr (fun acc e ->
        match e with
        | Tir.EApp (f, _) -> f.Tir.v_name :: acc
        | _ -> acc) [] fd.Tir.fn_body) in
  let rec fix () =
    let changed = ref false in
    List.iter (fun (fd : Tir.fn_def) ->
        let n = fd.Tir.fn_name in
        if not (Hashtbl.mem set n) && not (is_assume ~decls n) then
          (* A callee's RETURNING a fresh value is not this function's
             problem — dropping that value is exactly what the form allows.
             Only a callee that LEAKS propagates. *)
          match List.find_opt (fun c ->
              match Hashtbl.find_opt set c with
              | Some (RReturn _) -> false
              | Some _ -> true
              | None -> false) (callees fd) with
          | Some c ->
            Hashtbl.replace set n (RCallee (display_name c, Hashtbl.find set c));
            changed := true
          | None -> ()) m.Tir.tm_fns;
    if !changed then fix ()
  in
  fix ();
  set

(* ── The contract check ────────────────────────────────────────────────── *)

let diag ~severity ~span ~code ?(notes = []) message : March_errors.Errors.diagnostic =
  { March_errors.Errors.severity; span; message; labels = []; notes;
    code = Some code; fix = None }

(* Message body shared by the explicit-attribute and policy diagnostics:
   [head] is "`f` is marked @[no_alloc]" or "`f` is specialized to a NoAlloc
   policy". *)
let failure_message ~head ~name ~suffix (reason : reason) : string =
  match reason with
  | UnknownClosure x ->
    Printf.sprintf
      "%s but calls through an unknown closure.%s\n  I can't see what `%s` does. \
       If you know it doesn't allocate, mark `%s` @[no_alloc(assume)]."
      head suffix x name
  | Extern e ->
    Printf.sprintf
      "%s but calls the extern `%s`.%s\n  I can't see what `%s` does. \
       If you know it doesn't allocate, mark `%s` @[no_alloc(assume)]."
      head e suffix e name
  | Callee (g, r) ->
    Printf.sprintf "%s but allocates.%s\n  `%s` calls `%s`, which allocates (in `%s`: %s)."
      head suffix name g g (describe r)
  | r ->
    Printf.sprintf "%s but allocates.%s\n  In `%s`: %s." head suffix name (describe r)

let trmc_note = "This function is TRMC-eligible; compiling with --trmc turns the \
                 constructor into an in-place write."

(* ── Generation scope (LSP quick fix and forge fix --contracts) ───────── *)

(* A glob is a module/function pattern with `*` standing for any run of
   characters: "Dsp.*", "Audio.mix", "ad*". *)
let glob_matches (pat : string) (name : string) : bool =
  let np = String.length pat and nn = String.length name in
  let rec go i j =
    if i = np then j = nn
    else if pat.[i] = '*' then
      (* Skip consecutive stars, then try every split. *)
      let rec star k = k <= nn && (go (i + 1) k || star (k + 1)) in
      star j
    else j < nn && pat.[i] = name.[j] && go (i + 1) (j + 1)
  in
  go 0 0

(** Verified-clean functions that should carry the attribute but don't.

    Default scope: functions whose final TIR contains an [EReuse], a tokened
    [EAllocHole] or an [EStackAlloc] — the ones where a later change would
    silently reintroduce an allocation.  [globs] widens it to any
    verified-clean function whose name matches (forge.toml's
    `[contracts] no_alloc`).  Never in scope: functions already carrying any
    no_alloc form, `$`-prefixed synthetics, and anything outside the user's
    own sources ([is_user]).

    Each candidate comes back with the STRONGEST form that holds for it:
    [Hard] when the function allocates nothing at all, otherwise [Transient]
    when everything it allocates is released before it returns.  A function
    that satisfies neither is not a candidate.  Passing an empty [retaining]
    table (the default) asks for [Hard] candidates only, which is what a
    caller that has not computed the transient verdict wants. *)
let generation_candidates ~decls ~(allocating : (string, reason) Hashtbl.t)
    ?(retaining : (string, retain) Hashtbl.t = Hashtbl.create 0)
    ~(globs : string list) ~(is_user : March_ast.Ast.span -> bool)
    (m : Tir.tir_module) : (decl_info * form) list =
  List.filter_map (fun d ->
      if not (d.d_form = None
              && d.d_name <> "" && d.d_name.[0] <> '$'
              && is_user d.d_name_span)
      then None
      else
        let clones =
          List.filter (fun (fn : Tir.fn_def) -> base fn.Tir.fn_name = d.d_name)
            m.Tir.tm_fns in
        let none_in tbl =
          not (List.exists (fun (fn : Tir.fn_def) ->
              Hashtbl.mem tbl fn.Tir.fn_name) clones) in
        let in_scope =
          clones <> []
          && (List.exists (fun p -> glob_matches p d.d_name) globs
              || List.exists (fun (fn : Tir.fn_def) ->
                  has_reuse_or_stack fn.Tir.fn_body) clones)
        in
        if not in_scope then None
        else if none_in allocating then Some (d, Hard)
        else if Hashtbl.length retaining > 0 && none_in retaining then
          Some (d, Transient)
        else None) decls

(** True if [fd] carries a [Tagged(_, P)] parameter whose policy forbids
    allocation (NoAlloc, or Realtime which implies it).  [Policy_dce] used to
    answer this pre-Perceus by banning every EAlloc/EStackAlloc; the verdict
    now comes from the same final-TIR analysis the attribute uses. *)
let has_noalloc_policy (fd : Tir.fn_def) : bool =
  List.exists (fun c -> c = Policy_dce.NoAlloc) (Policy_dce.policies_of_fn fd)

(** [check ~decls ~allocating ~retaining ~opt ~trmc ~trmc_eligible m]: one
    diagnostic per failing contract, from its first failing monomorphised
    clone.  [retaining] carries the @[no_alloc(transient)] verdicts.  [opt =
    false] (--no-opt) downgrades the hard form to a warning that names the
    flag; a direct constructor allocation in a TRMC-eligible function gets
    the --trmc note while TRMC is off. *)
let check ~decls ~(allocating : (string, reason) Hashtbl.t)
    ?(retaining : (string, retain) Hashtbl.t = Hashtbl.create 0) ~opt ~trmc
    ~(trmc_eligible : string -> bool) (m : Tir.tir_module)
  : March_errors.Errors.diagnostic list =
  let seen = Hashtbl.create 16 in
  let policy_diags =
    List.filter_map (fun (fd : Tir.fn_def) ->
        let n = fd.Tir.fn_name in
        if not (has_noalloc_policy fd) then None
        else match Hashtbl.find_opt allocating n with
          | None -> None
          | Some reason ->
            let name = display_name n in
            let span = match decl_of decls n with
              | Some d -> d.d_name_span
              | None -> March_ast.Ast.dummy_span in
            let head =
              Printf.sprintf "`%s` is specialized to a NoAlloc policy" name in
            Some (diag ~severity:March_errors.Errors.Error ~span ~code:"no_alloc_policy"
                    (failure_message ~head ~name ~suffix:"" reason)))
      m.Tir.tm_fns
  in
  policy_diags @
  List.filter_map (fun (fd : Tir.fn_def) ->
      let n = fd.Tir.fn_name in
      match decl_of decls n, Hashtbl.find_opt allocating n with
      | Some ({ d_form = Some ((Hard | Warn) as form); _ } as d), Some reason
        when not (Hashtbl.mem seen d.d_name) ->
        Hashtbl.replace seen d.d_name ();
        let name = d.d_name in
        let severity, suffix =
          match form, opt with
          | Warn, _ -> (March_errors.Errors.Warning, "")
          | Hard, true -> (March_errors.Errors.Error, "")
          | Hard, false ->
            (March_errors.Errors.Warning,
             " (TIR optimisation was skipped by --no-opt; the normal build may pass.)")
          | (Assume | Transient), _ ->
            assert false (* excluded by the pattern above *)
        in
        let notes =
          match reason with
          | Ctor _ when (not trmc) && trmc_eligible name -> [ trmc_note ]
          | _ -> []
        in
        let head = Printf.sprintf "`%s` is marked @[no_alloc]" name in
        Some (diag ~severity ~span:d.d_name_span ~code:"no_alloc" ~notes
                (failure_message ~head ~name ~suffix reason))
      | _ -> None) m.Tir.tm_fns
  @
  (* @[no_alloc(transient)]: same shape, different question.  A transient
     contract is never downgraded by --no-opt: its verdict is about where
     values END UP, and skipping the optimiser cannot turn a retained value
     into a released one. *)
  (let seen_t = Hashtbl.create 16 in
   List.filter_map (fun (fd : Tir.fn_def) ->
       let n = fd.Tir.fn_name in
       match decl_of decls n, Hashtbl.find_opt retaining n with
       | Some ({ d_form = Some Transient; _ } as d), Some reason
         when not (Hashtbl.mem seen_t d.d_name) ->
         Hashtbl.replace seen_t d.d_name ();
         let msg =
           Printf.sprintf
             "`%s` is marked @[no_alloc(transient)] but retains an allocation.\n  In `%s`: %s."
             d.d_name d.d_name (describe_retain reason) in
         let notes = match reason with
           | RUnknownClosure _ | RExtern _ ->
             [ Printf.sprintf
                 "If you know it hands nothing on, mark `%s` @[no_alloc(assume)]."
                 d.d_name ]
           | _ -> [] in
         Some (diag ~severity:March_errors.Errors.Error ~span:d.d_name_span
                 ~code:"no_alloc_transient" ~notes msg)
       | _ -> None) m.Tir.tm_fns)
