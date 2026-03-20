(** Canonical deterministic serialization of TIR nodes.

    Produces stable byte sequences suitable for BLAKE3 hashing.
    Rules:
    - No spans, no source locations, no comments — structural content only.
    - All multi-byte integers are little-endian.
    - Record fields sorted alphabetically before serialization.
    - Prefix-free: every construct is unambiguously decodable.

    Format version: 1

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
      EReuse     0x4f
      ESeq       0x50

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

let write_var buf (v : var) =
  buf_string buf v.v_name;
  write_ty buf v.v_ty;
  write_linearity buf v.v_lin

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

let write_atom buf (a : atom) =
  match a with
  | AVar v ->
    buf_u8 buf 0x20;
    write_var buf v
  | ALit lit ->
    buf_u8 buf 0x21;
    write_literal buf lit
  | ADefRef did ->
    (* Tag 0x80; serialize only the hash — name is for display only *)
    buf_u8 buf 0x80;
    buf_string buf did.did_hash

let rec write_expr buf (e : expr) =
  match e with
  | EAtom a ->
    buf_u8 buf 0x40;
    write_atom buf a
  | EApp (fn_var, args) ->
    buf_u8 buf 0x41;
    write_var buf fn_var;
    buf_u32_le buf (List.length args);
    List.iter (write_atom buf) args
  | ECallPtr (fn_atom, args) ->
    buf_u8 buf 0x42;
    write_atom buf fn_atom;
    buf_u32_le buf (List.length args);
    List.iter (write_atom buf) args
  | ELet (v, e1, e2) ->
    buf_u8 buf 0x43;
    write_var buf v;
    write_expr buf e1;
    write_expr buf e2
  | ELetRec (fns, body) ->
    buf_u8 buf 0x44;
    (* Sort by name for stability *)
    let sorted = List.sort (fun a b -> String.compare a.fn_name b.fn_name) fns in
    buf_u32_le buf (List.length sorted);
    List.iter (write_fn_def buf) sorted;
    write_expr buf body
  | ECase (scrutinee, branches, default) ->
    buf_u8 buf 0x45;
    write_atom buf scrutinee;
    buf_u32_le buf (List.length branches);
    List.iter (write_branch buf) branches;
    (match default with
     | None   -> buf_u8 buf 0x00
     | Some e -> buf_u8 buf 0x01; write_expr buf e)
  | ETuple atoms ->
    buf_u8 buf 0x46;
    buf_u32_le buf (List.length atoms);
    List.iter (write_atom buf) atoms
  | ERecord fields ->
    buf_u8 buf 0x47;
    let sorted = List.sort (fun (a,_) (b,_) -> String.compare a b) fields in
    buf_u32_le buf (List.length sorted);
    List.iter (fun (name, atom) -> buf_string buf name; write_atom buf atom) sorted
  | EField (atom, name) ->
    buf_u8 buf 0x48;
    write_atom buf atom;
    buf_string buf name
  | EUpdate (atom, fields) ->
    buf_u8 buf 0x49;
    write_atom buf atom;
    let sorted = List.sort (fun (a,_) (b,_) -> String.compare a b) fields in
    buf_u32_le buf (List.length sorted);
    List.iter (fun (name, a) -> buf_string buf name; write_atom buf a) sorted
  | EAlloc (ty, args) ->
    buf_u8 buf 0x4a;
    write_ty buf ty;
    buf_u32_le buf (List.length args);
    List.iter (write_atom buf) args
  | EStackAlloc (ty, args) ->
    buf_u8 buf 0x4b;
    write_ty buf ty;
    buf_u32_le buf (List.length args);
    List.iter (write_atom buf) args
  | EFree a ->
    buf_u8 buf 0x4c;
    write_atom buf a
  | EIncRC a ->
    buf_u8 buf 0x4d;
    write_atom buf a
  | EDecRC a ->
    buf_u8 buf 0x4e;
    write_atom buf a
  | EReuse (a, ty, args) ->
    buf_u8 buf 0x4f;
    write_atom buf a;
    write_ty buf ty;
    buf_u32_le buf (List.length args);
    List.iter (write_atom buf) args
  | ESeq (e1, e2) ->
    buf_u8 buf 0x50;
    write_expr buf e1;
    write_expr buf e2

and write_branch buf (br : branch) =
  buf_string buf br.br_tag;
  buf_u32_le buf (List.length br.br_vars);
  List.iter (write_var buf) br.br_vars;
  write_expr buf br.br_body

and write_fn_def buf (fd : fn_def) =
  buf_string buf fd.fn_name;
  buf_u32_le buf (List.length fd.fn_params);
  List.iter (write_var buf) fd.fn_params;
  write_ty buf fd.fn_ret_ty;
  write_expr buf fd.fn_body

(** Serialize only the signature of a function (name, param types, ret type).
    Does NOT include the body or variable names — only types matter for the sig. *)
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
let serialize_atom     (a : atom)       : bytes = to_bytes write_atom a
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
