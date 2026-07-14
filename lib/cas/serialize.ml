(** Canonical deterministic serialization of TIR nodes.

    Produces stable byte sequences suitable for BLAKE3 hashing.
    Rules:
    - No spans, no source locations, no comments — structural content only.
    - All multi-byte integers are little-endian.
    - Record fields sorted alphabetically before serialization.
    - Prefix-free: every construct is unambiguously decodable.
    - Bound variables are alpha-normalized: a binder (function parameter,
      let/branch/letrec binder) is written by its binding INDEX, assigned in
      deterministic left-to-right traversal order, NOT by its name.  A variable
      occurrence is written as its binder's index if it is in scope, otherwise
      (a free reference: a top-level / monomorphized callee name in EApp, or a
      global) by its name.  This makes [impl_hash] invariant to the temp-name
      counters ($t<n>, $f<n>, $lam<n>) that vary with surrounding compilation
      context, so the same source function hashes identically across separate
      binaries — required for cross-binary RPC admission.

    Format version: 2 (v1 hashed raw variable names; v2 alpha-normalizes them)

    Type constructor tags (u8):
      TInt    0x01
      TFloat  0x02
      TBool   0x03
      TString 0x04
      TUnit   0x05
      TTuple  0x06
      TRecord 0x07
      TCon    0x08
      TFn     0x09
      TPtr    0x0a
      TVar    0x0b

    Variable occurrence tags (u8, inside AVar / EApp callee):
      bound   0x01  (followed by u32 binder index)
      free    0x02  (followed by length-prefixed name)

    Atom tags:
      AVar    0x20
      ALit    0x21
      ADefRef 0x80  (hash only, name excluded for content-addressing)

    Literal tags:
      LInt    0x30
      LFloat  0x31
      LBool   0x32
      LString 0x33
      LUnit   0x34
      LAtom   0x35 (March atom literals, e.g. :ok)

    Expr tags:
      EAtom      0x40
      EApp       0x41
      ECallPtr   0x42
      ELet       0x43
      ELetRec    0x44
      ECase      0x45
      ETuple     0x46
      ERecord    0x47
      EField     0x48
      EUpdate    0x49
      EAlloc     0x4a
      EStackAlloc 0x4b
      EFree      0x4c
      EIncRC     0x4d
      EDecRC     0x4e
      EReuse        0x4f
      ESeq          0x50
      EAtomicIncRC  0x51
      EAtomicDecRC  0x52

    Linearity tags:
      Lin  0x60
      Aff  0x61
      Unr  0x62

    TypeDef tags:
      TDVariant  0x70
      TDRecord   0x71
      TDClosure  0x72
*)

open March_tir.Tir

(* ── Buffer helpers ─────────────────────────────────────────────────────── *)

let buf_u8 buf (n : int) =
  Buffer.add_char buf (Char.chr (n land 0xff))

let buf_u32_le buf (n : int) =
  buf_u8 buf (n land 0xff);
  buf_u8 buf ((n lsr 8) land 0xff);
  buf_u8 buf ((n lsr 16) land 0xff);
  buf_u8 buf ((n lsr 24) land 0xff)

let buf_i64_le buf (n : int64) =
  let b i = Int64.(to_int (logand (shift_right_logical n (i * 8)) 0xffL)) in
  for i = 0 to 7 do buf_u8 buf (b i) done

let buf_f64_le buf (f : float) =
  buf_i64_le buf (Int64.bits_of_float f)

let buf_string buf (s : string) =
  buf_u32_le buf (String.length s);
  Buffer.add_string buf s

(* ── Recursive serializers ──────────────────────────────────────────────── *)

let rec write_ty buf (ty : ty) =
  match ty with
  | TInt    -> buf_u8 buf 0x01
  | TFloat  -> buf_u8 buf 0x02
  | TBool   -> buf_u8 buf 0x03
  | TString -> buf_u8 buf 0x04
  | TUnit   -> buf_u8 buf 0x05
  | TTuple ts ->
    buf_u8 buf 0x06;
    buf_u32_le buf (List.length ts);
    List.iter (write_ty buf) ts
  | TRecord fields ->
    buf_u8 buf 0x07;
    (* Sort alphabetically by field name for canonical order *)
    let sorted = List.sort (fun (a,_) (b,_) -> String.compare a b) fields in
    buf_u32_le buf (List.length sorted);
    List.iter (fun (name, ty) -> buf_string buf name; write_ty buf ty) sorted
  | TCon (name, args) ->
    buf_u8 buf 0x08;
    buf_string buf name;
    buf_u32_le buf (List.length args);
    List.iter (write_ty buf) args
  | TFn (params, ret) ->
    buf_u8 buf 0x09;
    buf_u32_le buf (List.length params);
    List.iter (write_ty buf) params;
    write_ty buf ret
  | TPtr inner ->
    buf_u8 buf 0x0a;
    write_ty buf inner
  | TVar name ->
    buf_u8 buf 0x0b;
    buf_string buf name

let write_linearity buf = function
  | Lin -> buf_u8 buf 0x60
  | Aff -> buf_u8 buf 0x61
  | Unr -> buf_u8 buf 0x62

(* ── Alpha-normalized variables ───────────────────────────────────────────
   [scope] maps an in-scope binder name to its assigned index (most-recent
   binding first, so shadowing resolves to the nearest binder).  [next] is the
   monotonic index counter, fresh per top-level definition. *)

(* A variable occurrence: bound → index, free → name.  Always followed by the
   variable's type and linearity (a binder and its uses agree on these). *)
let write_var_use buf (scope : (string * int) list) (v : var) =
  (match List.assoc_opt v.v_name scope with
   | Some idx -> buf_u8 buf 0x01; buf_u32_le buf idx
   | None     -> buf_u8 buf 0x02; buf_string buf v.v_name);
  write_ty buf v.v_ty;
  write_linearity buf v.v_lin

(* Introduce a binder: assign it the next index, emit it, and return the
   extended scope.  Emitted identically to a bound occurrence so structure is
   self-describing. *)
let bind_var buf (next : int ref) (scope : (string * int) list) (v : var)
  : (string * int) list =
  let idx = !next in
  incr next;
  buf_u8 buf 0x01; buf_u32_le buf idx;
  write_ty buf v.v_ty;
  write_linearity buf v.v_lin;
  (v.v_name, idx) :: scope

let write_literal buf (lit : March_ast.Ast.literal) =
  match lit with
  | LitInt n ->
    buf_u8 buf 0x30;
    buf_i64_le buf (Int64.of_int n)
  | LitFloat f ->
    buf_u8 buf 0x31;
    buf_f64_le buf f
  | LitBool b ->
    buf_u8 buf 0x32;
    buf_u8 buf (if b then 0x01 else 0x00)
  | LitString s ->
    buf_u8 buf 0x33;
    buf_string buf s
  | LitAtom s ->
    buf_u8 buf 0x35;
    buf_string buf s

let write_atom buf scope (a : atom) =
  match a with
  | AVar v ->
    buf_u8 buf 0x20;
    write_var_use buf scope v
  | ALit lit ->
    buf_u8 buf 0x21;
    write_literal buf lit
  | ADefRef did ->
    (* Tag 0x80; serialize only the hash — name is for display only *)
    buf_u8 buf 0x80;
    buf_string buf did.did_hash

let rec write_expr buf (next : int ref) (scope : (string * int) list) (e : expr) =
  match e with
  | EAtom a ->
    buf_u8 buf 0x40;
    write_atom buf scope a
  | EApp (fn_var, args) ->
    buf_u8 buf 0x41;
    (* Callee: a bound local (closure-by-name) → index; a top-level /
       monomorphized function → free name (stable across binaries). *)
    write_var_use buf scope fn_var;
    buf_u32_le buf (List.length args);
    List.iter (write_atom buf scope) args
  | ECallPtr (fn_atom, args) ->
    buf_u8 buf 0x42;
    write_atom buf scope fn_atom;
    buf_u32_le buf (List.length args);
    List.iter (write_atom buf scope) args
  | ELet (v, e1, e2) ->
    buf_u8 buf 0x43;
    (* e1 is evaluated in the OUTER scope; v is bound only for e2. *)
    write_expr buf next scope e1;
    let scope' = bind_var buf next scope v in
    write_expr buf next scope' e2
  | ELetRec (fns, body) ->
    buf_u8 buf 0x44;
    (* Sort by name for stability, then bind all names (mutual recursion) before
       serializing any body. *)
    let sorted = List.sort (fun a b -> String.compare a.fn_name b.fn_name) fns in
    let scope' = List.fold_left (fun sc (fd : fn_def) ->
        let idx = !next in incr next; (fd.fn_name, idx) :: sc) scope sorted in
    buf_u32_le buf (List.length sorted);
    List.iter (write_letrec_fn buf next scope') sorted;
    write_expr buf next scope' body
  | ECase (scrutinee, branches, default) ->
    buf_u8 buf 0x45;
    write_atom buf scope scrutinee;
    buf_u32_le buf (List.length branches);
    List.iter (write_branch buf next scope) branches;
    (match default with
     | None   -> buf_u8 buf 0x00
     | Some e -> buf_u8 buf 0x01; write_expr buf next scope e)
  | ETuple atoms ->
    buf_u8 buf 0x46;
    buf_u32_le buf (List.length atoms);
    List.iter (write_atom buf scope) atoms
  | ERecord fields ->
    buf_u8 buf 0x47;
    let sorted = List.sort (fun (a,_) (b,_) -> String.compare a b) fields in
    buf_u32_le buf (List.length sorted);
    List.iter (fun (name, atom) -> buf_string buf name; write_atom buf scope atom) sorted
  | EField (atom, name) ->
    buf_u8 buf 0x48;
    write_atom buf scope atom;
    buf_string buf name
  | EUpdate (atom, fields) ->
    buf_u8 buf 0x49;
    write_atom buf scope atom;
    let sorted = List.sort (fun (a,_) (b,_) -> String.compare a b) fields in
    buf_u32_le buf (List.length sorted);
    List.iter (fun (name, a) -> buf_string buf name; write_atom buf scope a) sorted
  | EAlloc (ty, args) ->
    buf_u8 buf 0x4a;
    write_ty buf ty;
    buf_u32_le buf (List.length args);
    List.iter (write_atom buf scope) args
  | EStackAlloc (ty, args) ->
    buf_u8 buf 0x4b;
    write_ty buf ty;
    buf_u32_le buf (List.length args);
    List.iter (write_atom buf scope) args
  | EFree a ->
    buf_u8 buf 0x4c;
    write_atom buf scope a
  | EIncRC a ->
    buf_u8 buf 0x4d;
    write_atom buf scope a
  | EDecRC a ->
    buf_u8 buf 0x4e;
    write_atom buf scope a
  | EReuse (a, ty, args) ->
    buf_u8 buf 0x4f;
    write_atom buf scope a;
    write_ty buf ty;
    buf_u32_le buf (List.length args);
    List.iter (write_atom buf scope) args
  | ESeq (e1, e2) ->
    buf_u8 buf 0x50;
    write_expr buf next scope e1;
    write_expr buf next scope e2
  | EAtomicIncRC a ->
    buf_u8 buf 0x51;
    write_atom buf scope a
  | EAtomicDecRC a ->
    buf_u8 buf 0x52;
    write_atom buf scope a

and write_branch buf next scope (br : branch) =
  buf_string buf br.br_tag;
  buf_u32_le buf (List.length br.br_vars);
  (* Bind the pattern variables (in order) for the branch body. *)
  let scope' = List.fold_left (fun sc v -> bind_var buf next sc v) scope br.br_vars in
  write_expr buf next scope' br.br_body

(* A letrec-inner function: its name is already bound in [scope]; bind its
   parameters and serialize the body.  The name itself is not re-emitted (its
   binding index was assigned when the recursive group was opened). *)
and write_letrec_fn buf next scope (fd : fn_def) =
  buf_u32_le buf (List.length fd.fn_params);
  let scope' = List.fold_left (fun sc v -> bind_var buf next sc v) scope fd.fn_params in
  write_ty buf fd.fn_ret_ty;
  write_expr buf next scope' fd.fn_body

(* A top-level function: its name IS its stable identity, so it is emitted by
   name; parameters are alpha-normalized binders.

   [fd.fn_kind] (Wave 3 Task 3) is deliberately NOT serialized here (nor in
   [write_letrec_fn] / [write_fn_sig] below): this module produces the
   BLAKE3-hashed [impl_hash]/[sig_hash] used for cross-binary RPC admission
   and the CAS artifact cache key (bin/main.ml). Hashing fn_kind would change
   every impl_hash the moment the field was introduced — a real behavior
   change (cache invalidation, RPC admission drift), not the additive,
   printer-invisible field this task promises. fn_kind is a same-binary
   compiler-internal role tag, not part of a function's externally-observable
   identity, so it stays out of the canonical serialization by design. *)
let write_fn_def buf (fd : fn_def) =
  buf_string buf fd.fn_name;
  buf_u32_le buf (List.length fd.fn_params);
  let next = ref 0 in
  let scope = List.fold_left (fun sc v -> bind_var buf next sc v) [] fd.fn_params in
  write_ty buf fd.fn_ret_ty;
  write_expr buf next scope fd.fn_body

(** Serialize only the signature of a function (name, param types, ret type).
    Does NOT include the body or variable names — only types matter for the sig.
    Also does not include [fn_kind] — see [write_fn_def]'s comment. *)
let write_fn_sig buf (fd : fn_def) =
  buf_string buf fd.fn_name;
  buf_u32_le buf (List.length fd.fn_params);
  List.iter (fun v -> write_ty buf v.v_ty) fd.fn_params;
  write_ty buf fd.fn_ret_ty

(* ── Public API ─────────────────────────────────────────────────────────── *)

let to_bytes f x =
  let buf = Buffer.create 64 in
  f buf x;
  Buffer.to_bytes buf

let serialize_ty       (ty : ty)        : bytes = to_bytes write_ty ty
let serialize_atom     (a : atom)       : bytes =
  to_bytes (fun buf a -> write_atom buf [] a) a
let serialize_fn_def   (fd : fn_def)    : bytes = to_bytes write_fn_def fd
let serialize_fn_sig   (fd : fn_def)    : bytes = to_bytes write_fn_sig fd

let serialize_type_def (td : type_def) : bytes =
  let buf = Buffer.create 64 in
  (match td with
   | TDVariant (name, ctors) ->
     buf_u8 buf 0x70;
     buf_string buf name;
     (* Sort constructors by name for canonical order *)
     let sorted = List.sort (fun (a,_) (b,_) -> String.compare a b) ctors in
     buf_u32_le buf (List.length sorted);
     List.iter (fun (ctor_name, arg_tys) ->
       buf_string buf ctor_name;
       buf_u32_le buf (List.length arg_tys);
       List.iter (write_ty buf) arg_tys) sorted
   | TDRecord (name, fields) ->
     buf_u8 buf 0x71;
     buf_string buf name;
     let sorted = List.sort (fun (a,_) (b,_) -> String.compare a b) fields in
     buf_u32_le buf (List.length sorted);
     List.iter (fun (fname, fty) -> buf_string buf fname; write_ty buf fty) sorted
   | TDClosure (name, tys) ->
     buf_u8 buf 0x72;
     buf_string buf name;
     buf_u32_le buf (List.length tys);
     List.iter (write_ty buf) tys);
  Buffer.to_bytes buf
