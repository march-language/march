(** @[no_alloc] allocation contracts.

    Design: specs/2026-09-03-allocation-contracts-design.md.

    Attribute bookkeeping (form + spans, keyed by the module-qualified
    pre-Mono TIR name) is collected from the AST here and matched to
    TIR functions by [Tir_names.strip_specialization_suffix] — never by
    mutating an annotated function's TIR, because the verdict must be the
    verdict of the code as it compiles WITHOUT the attribute. *)

type form = Hard | Warn | Assume

let form_of_attrs (attrs : string list) : form option =
  if List.mem "no_alloc" attrs then Some Hard
  else if List.mem "no_alloc:warn" attrs then Some Warn
  else if List.mem "no_alloc:assume" attrs then Some Assume
  else None

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
let direct_reason ~(m : Tir.tir_module) ~fns ~externs (body : Tir.expr) : reason option =
  let found = ref None in
  let set r = if !found = None then found := Some r in
  Policy_dce.fold_expr (fun () e ->
      match e with
      (* Nullary constructors are immediate tags per the design's allocation
         table (specs/2026-09-03-allocation-contracts-design.md); see the
         caveat in specs/lang/memory-model.md about today's codegen. *)
      | Tir.EAlloc (_, []) -> ()
      | Tir.EAlloc (Tir.TCon (c, _), _) when Tir_names.is_clo_struct c -> set Closure
      | Tir.EAlloc (Tir.TCon (c, _), _) -> set (Ctor (ctor_short c))
      | Tir.EAlloc (ty, _) -> set (Ctor (Tir.show_ty ty))
      | Tir.EAllocHole (None, Tir.TCon (c, _), _, _) -> set (Ctor (ctor_short c))
      | Tir.EAllocHole (None, ty, _, _) -> set (Ctor (Tir.show_ty ty))
      | Tir.ETuple (_ :: _) -> set Tuple
      | Tir.ERecord _ -> set Record
      | Tir.EUpdate _ -> set Update
      | Tir.EReuse (_, ty, args) when stores_boxed_float m ty args -> set FloatBox
      | Tir.EStackAlloc (ty, args) when stores_boxed_float m ty args -> set FloatBox
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
  let set : (string, reason) Hashtbl.t = Hashtbl.create 64 in
  List.iter (fun fd ->
      if not (is_assume ~decls fd.Tir.fn_name) then
        match direct_reason ~m ~fns ~externs fd.Tir.fn_body with
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

(** [check ~decls ~allocating ~opt ~trmc ~trmc_eligible m]: one diagnostic per
    failing contract, from its first failing monomorphised clone.  [opt =
    false] (--no-opt) downgrades the hard form to a warning that names the
    flag; a direct constructor allocation in a TRMC-eligible function gets
    the --trmc note while TRMC is off. *)
let check ~decls ~(allocating : (string, reason) Hashtbl.t) ~opt ~trmc
    ~(trmc_eligible : string -> bool) (m : Tir.tir_module)
  : March_errors.Errors.diagnostic list =
  let seen = Hashtbl.create 16 in
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
          | Assume, _ -> assert false (* excluded by the pattern above *)
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
