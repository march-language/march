(** March TIR → ES module (JavaScript) emission.
    Consumes the full post-pipeline TIR (after Mono, Fusion, Defun, Known_call,
    Beta_adt, Join_points, Simplify, Perceus, Escape, Opt).

    Constructor layout: {$: "CtorName", _0: field0, _1: field1, ...}
    Closure layout:     {$: "$Clo_name", _0: apply_fn, _1: fv1, _2: fv2, ...}
    Tuple layout:       {_0: a, _1: b, ...}
    The $ field holds the constructor/closure tag.

    Every user-defined function emits both a plain JS function (for direct
    known-call sites) and a $clo closure-protocol object (for first-class use
    via ECallPtr's f._0(f, args) dispatch).

    Runtime shim (march_runtime.mjs) must be co-located with the output .mjs. *)

(* ── Context ─────────────────────────────────────────────────────── *)

type ctx = {
  buf          : Buffer.t;
  mutable indent : int;
  mutable line   : int;  (* 0-indexed output line counter, updated by emit *)
  runtime_uses : (string, unit) Hashtbl.t;
  (* runtime function names referenced — imported at top of output *)
  fn_names     : (string, unit) Hashtbl.t;
  (* user-defined function names in this module — used to emit $clo wrappers *)
  param_names  : (string, unit) Hashtbl.t;
  (* local parameter names in the current function — excluded from $clo suffix
     to avoid false positives when a parameter shadows a module function *)
  extern_fns   : (string, Tir.extern_decl) Hashtbl.t;
  (* extern march_name → decl; populated before emission for call-site tracking *)
  used_externs : (string, unit) Hashtbl.t;
  (* extern march names that actually appear in emitted code; drives lazy bridge emit *)
  async_fns    : (string, unit) Hashtbl.t;
  (* user function names that must be emitted as `async function` (Chunk A) *)
  fn_lines     : (string, int) Hashtbl.t;
  (* fn_name → 1-indexed source line; looked up when recording source map segments *)
  segments     : (int * int) list ref;
  (* (output_line_0indexed, source_line_0indexed) segments collected during fn emission *)
}

let create_ctx ?(fn_lines=[]) () = {
  buf          = Buffer.create 4096;
  indent       = 0;
  line         = 0;
  runtime_uses = Hashtbl.create 16;
  fn_names     = Hashtbl.create 64;
  param_names  = Hashtbl.create 8;
  extern_fns   = Hashtbl.create 8;
  used_externs = Hashtbl.create 8;
  async_fns    = Hashtbl.create 8;
  fn_lines     = (let t = Hashtbl.create 16 in
                  List.iter (fun (n, l) -> Hashtbl.replace t n l) fn_lines; t);
  segments     = ref [];
}

let use_runtime ctx name = Hashtbl.replace ctx.runtime_uses name ()

(* ── Output helpers ──────────────────────────────────────────────── *)

let emit ctx s =
  Buffer.add_string ctx.buf s;
  String.iter (fun c -> if c = '\n' then ctx.line <- ctx.line + 1) s

let emit_indent ctx =
  for _ = 1 to ctx.indent do Buffer.add_string ctx.buf "  " done

let emitl ctx s =
  emit_indent ctx; Buffer.add_string ctx.buf s; emit ctx "\n"

let with_indent ctx f =
  ctx.indent <- ctx.indent + 1; f (); ctx.indent <- ctx.indent - 1

(* ── Name mangling ───────────────────────────────────────────────── *)

(** March qualified names use '.'; JS identifiers cannot. Replace with '$'.
    E.g. "List.map" -> "List$map". *)
let js_reserved = [
  (* strict-mode reserved identifiers *)
  "eval"; "arguments"; "implements"; "interface"; "let"; "package";
  "private"; "protected"; "public"; "static"; "yield";
  (* keywords *)
  "break"; "case"; "catch"; "class"; "const"; "continue"; "debugger";
  "default"; "delete"; "do"; "else"; "export"; "extends"; "finally";
  "for"; "function"; "if"; "import"; "in"; "instanceof"; "new"; "return";
  "super"; "switch"; "this"; "throw"; "try"; "typeof"; "var"; "void";
  "while"; "with";
]

let mangle name =
  let b = Bytes.of_string name in
  Bytes.iteri (fun i c -> if c = '.' then Bytes.set b i '$') b;
  let s = Bytes.to_string b in
  if List.mem s js_reserved then "_" ^ s else s

(** Constructor key in EAlloc is "TypeName.CtorName"; return just "CtorName". *)
let bare_ctor key =
  match String.rindex_opt key '.' with
  | Some i -> String.sub key (i + 1) (String.length key - i - 1)
  | None   -> key

(** Encode a March string as a JS string literal.
    OCaml's %S uses octal escapes for non-ASCII bytes, which are not allowed
    in ES module strict mode. This encoder keeps valid UTF-8 bytes verbatim
    and uses \uXXXX only for control characters. *)
let js_string_lit s =
  let buf = Buffer.create (String.length s + 4) in
  Buffer.add_char buf '"';
  String.iter (fun c ->
    match c with
    | '"'  -> Buffer.add_string buf "\\\""
    | '\\' -> Buffer.add_string buf "\\\\"
    | '\n' -> Buffer.add_string buf "\\n"
    | '\r' -> Buffer.add_string buf "\\r"
    | '\t' -> Buffer.add_string buf "\\t"
    | c when Char.code c < 0x20 ->
      Buffer.add_string buf (Printf.sprintf "\\u%04X" (Char.code c))
    | c -> Buffer.add_char buf c
  ) s;
  Buffer.add_char buf '"';
  Buffer.contents buf

(* ── Atom emission ───────────────────────────────────────────────── *)

let emit_literal ctx lit =
  let open March_ast.Ast in
  match lit with
  | LitInt n    -> emit ctx (string_of_int n)
  | LitFloat f  ->
    let s = string_of_float f in
    emit ctx (if String.contains s '.' || String.contains s 'e' then s else s ^ ".0")
  | LitBool b   -> emit ctx (if b then "true" else "false")
  | LitString s -> emit ctx (js_string_lit s)
  | LitAtom a   -> emit ctx (Printf.sprintf "\":%s\"" a)

(* Emit an atom as a plain name — used for apply-function slots in EAlloc
   where we need the raw function, not a closure wrapper. *)
let emit_atom_raw ctx = function
  | Tir.AVar v    -> emit ctx (mangle v.Tir.v_name)
  | Tir.ADefRef d -> emit ctx (mangle d.Tir.did_name)
  | Tir.ALit l    -> emit_literal ctx l

(* Standard atom emission: user-defined function names use their $clo wrapper
   so that ECallPtr dispatch (f._0(f, args)) works when they're first-class.
   Both AVar and ADefRef can hold a module-level function reference — check fn_names.
   Extern function names also get the $clo suffix and are tracked as used. *)
let emit_atom ctx = function
  | Tir.AVar v ->
    let n = mangle v.Tir.v_name in
    if Hashtbl.mem ctx.extern_fns v.Tir.v_name
       && not (Hashtbl.mem ctx.param_names v.Tir.v_name)
    then begin
      Hashtbl.replace ctx.used_externs v.Tir.v_name ();
      emit ctx (n ^ "$clo")
    end else if Hashtbl.mem ctx.fn_names v.Tir.v_name
       && not (Hashtbl.mem ctx.param_names v.Tir.v_name)
    then emit ctx (n ^ "$clo")
    else emit ctx n
  | Tir.ADefRef d ->
    let n = mangle d.Tir.did_name in
    if Hashtbl.mem ctx.extern_fns d.Tir.did_name then begin
      Hashtbl.replace ctx.used_externs d.Tir.did_name ();
      emit ctx (n ^ "$clo")
    end else if Hashtbl.mem ctx.fn_names d.Tir.did_name then
      emit ctx (n ^ "$clo")
    else
      emit ctx n
  | Tir.ALit l    -> emit_literal ctx l

(* ── Builtin lowering ────────────────────────────────────────────── *)

(** Binary arithmetic/comparison builtins that inline as JS infix operators. *)
let inline_binop = function
  (* Named (fully-qualified monomorphic) forms *)
  | "add_int" | "add_float"              -> Some "+"
  | "sub_int" | "sub_float"              -> Some "-"
  | "mul_int" | "mul_float"              -> Some "*"
  | "div_float"                          -> Some "/"
  | "eq_int" | "eq_float" | "eq_bool"
  | "eq_string" | "string_eq"            -> Some "==="
  | "neq_int" | "neq_float" | "neq_bool"
  | "neq_string"                         -> Some "!=="
  | "lt_int" | "lt_float"               -> Some "<"
  | "lte_int" | "lte_float"             -> Some "<="
  | "gt_int" | "gt_float"               -> Some ">"
  | "gte_int" | "gte_float"             -> Some ">="
  | "and_bool"                           -> Some "&&"
  | "or_bool"                            -> Some "||"
  | "string_concat" | "++"              -> Some "+"
  (* Symbolic operator forms emitted by TIR after monomorphization *)
  | "+"  | "+." -> Some "+"
  | "-"  | "-." -> Some "-"   (* binary; unary negation is handled separately *)
  | "*"  | "*." -> Some "*"
  | "/"  | "/." -> Some "/"
  | "%"         -> Some "%"
  | "<"         -> Some "<"
  | ">"         -> Some ">"
  | "<="        -> Some "<="
  | ">="        -> Some ">="
  | "==" | "=.=" -> Some "==="
  | "!=" | "!=." -> Some "!=="
  | "&&"        -> Some "&&"
  | "||"        -> Some "||"
  | _    -> None

(* ── Scrutinee type helpers ─────────────────────────────────────── *)

let atom_ty = function
  | Tir.AVar v    -> v.Tir.v_ty
  | Tir.ALit (March_ast.Ast.LitInt _)    -> Tir.TInt
  | Tir.ALit (March_ast.Ast.LitFloat _)  -> Tir.TFloat
  | Tir.ALit (March_ast.Ast.LitBool _)   -> Tir.TBool
  | Tir.ALit (March_ast.Ast.LitString _) -> Tir.TString
  | Tir.ALit (March_ast.Ast.LitAtom _)   -> Tir.TCon ("Atom", [])
  | Tir.ADefRef _                         -> Tir.TVar "_"

(** True when the scrutinee requires literal-equality (if/else) rather than
    constructor-tag (switch on .$). *)
let is_literal_scrutinee_ty = function
  | Tir.TBool | Tir.TInt | Tir.TFloat | Tir.TString
  | Tir.TCon ("Atom", []) -> true
  | _ -> false

(** JS comparison RHS for a branch tag in a literal if/else chain.
    lower.ml encodes:
      PatLit(LitInt n)    -> string_of_int n     e.g. "42"
      PatLit(LitBool b)   -> "true" / "false"    (lowercase)
      PatLit(LitString s) -> "\"s\""             (OCaml-quoted)
      PatLit(LitAtom a)   -> ":a"
      ECase on bool (if-lowering) -> "True" / "False"   (uppercase) *)
let literal_tag_js br_tag =
  match br_tag with
  | "True"  | "true"  -> "true"
  | "False" | "false" -> "false"
  | _ when br_tag <> "" && (br_tag.[0] = '-'
                             || (br_tag.[0] >= '0' && br_tag.[0] <= '9')) ->
    br_tag  (* numeric literal — emit as-is *)
  | _ when br_tag <> "" && br_tag.[0] = '"' ->
    (* lower.ml wraps the raw string s as "\"" ^ s ^ "\"" — unwrap and re-encode
       using js_string_lit so special chars like newlines become \n, not literal bytes *)
    let inner = String.sub br_tag 1 (String.length br_tag - 2) in
    js_string_lit inner
  | _ -> js_string_lit br_tag  (* atom tags (":name"), ADT ctor tags, etc. *)

(* ── JS-module detection + extern classification ─────────────────── *)

(** True when the library name is a JS module specifier (not a C lib name).
    JS specifiers start with a scheme, relative path, or scoped npm prefix. *)
let is_js_module lib =
  let has_prefix p = String.length lib >= String.length p
                     && String.sub lib 0 (String.length p) = p in
  has_prefix "./" || has_prefix "../"
  || has_prefix "npm:" || has_prefix "jsr:"
  || has_prefix "node:" || has_prefix "https://" || has_prefix "http://"

(** How an extern should be called on the JS target. *)
type js_extern_kind =
  | JsModuleSync            (* import { sym } from "spec" — plain synchronous call *)
  | JsModuleBlocking        (* same, but the result must be await-ed (Chunk A) *)
  | JsModuleRaises          (* same, but errors become Err via try/catch (Chunk B) *)
  | JsModuleBlockingRaises  (* await + try/catch → Ok/Err (Chunks A+B combined) *)
  | CBacked                 (* non-JS-module lib name — unsupported on JS target (Chunk C) *)

let classify_js_extern (ed : Tir.extern_decl) : js_extern_kind =
  if not (is_js_module ed.Tir.ed_lib_name) then CBacked
  else if ed.Tir.ed_blocking && ed.Tir.ed_raises then JsModuleBlockingRaises
  else if ed.Tir.ed_blocking then JsModuleBlocking
  else if ed.Tir.ed_raises   then JsModuleRaises
  else JsModuleSync

(** Extract the E from Result(T, E) in an extern's declared return type.
    For raises externs, ed_ret = Result(T, E); returns E for error marshalling. *)
let err_payload_ty : Tir.ty -> Tir.ty = function
  | Tir.TCon ("Result", [_; t_err]) -> t_err
  | t -> t

(** Warn at compile time when a raises extern has a non-String error type.
    The actual marshalling is always best-effort (String(e?.message ?? e)) via
    the __js_err_to helper; this just surfaces the limitation. *)
let warn_err_type source_name (e_ty : Tir.ty) =
  match e_ty with
  | Tir.TString -> ()
  | _ ->
    Printf.eprintf
      "warning: `raises` extern `%s` has non-String error type; \
       the JS exception is coerced via String(e?.message ?? e) (best-effort). \
       Full structured-error marshalling is not yet supported.\n"
      source_name

(** Emit the call expression for a direct extern call site.
    Marks the extern as used. Dispatches on js_extern_kind:
    - Sync/CBacked: plain synchronous call (Chunk 0 / C)
    - Raises: IIFE with try/catch → Ok/Err (Chunk B)
    - Blocking: plain call for now — Chunk A adds await *)
let emit_extern_call (ctx : ctx) (ed : Tir.extern_decl) (args : Tir.atom list) : unit =
  let march_name = mangle ed.ed_march_name in
  Hashtbl.replace ctx.used_externs ed.ed_march_name ();
  (match classify_js_extern ed with
   | JsModuleSync | CBacked ->
     emit ctx (march_name ^ "(");
     List.iteri (fun i a -> if i > 0 then emit ctx ", "; emit_atom ctx a) args;
     emit ctx ")"
   | JsModuleBlocking ->
     emit ctx ("(await " ^ march_name ^ "(");
     List.iteri (fun i a -> if i > 0 then emit ctx ", "; emit_atom ctx a) args;
     emit ctx "))"
   | JsModuleRaises ->
     warn_err_type ed.ed_march_name (err_payload_ty ed.Tir.ed_ret);
     emit ctx ("(() => { try { return { $: \"Ok\", _0: " ^ march_name ^ "(");
     List.iteri (fun i a -> if i > 0 then emit ctx ", "; emit_atom ctx a) args;
     emit ctx ") }; } catch (e) { return { $: \"Err\", _0: __js_err_to(e) }; } })()"
   | JsModuleBlockingRaises ->
     warn_err_type ed.ed_march_name (err_payload_ty ed.Tir.ed_ret);
     emit ctx ("(await (async () => { try { return { $: \"Ok\", _0: (await " ^ march_name ^ "(");
     List.iteri (fun i a -> if i > 0 then emit ctx ", "; emit_atom ctx a) args;
     emit ctx ")) }; } catch (e) { return { $: \"Err\", _0: __js_err_to(e) }; } })()")

(* ── Async colouring analysis (Chunk A) ──────────────────────────── *)

(** Collect the set of fn/extern names referenced in a TIR expression.
    Tracks both EApp (direct calls) and ECallPtr (closure dispatch, which is
    how extern calls reach the emitter after defunctionalization). *)
let rec calls_in_expr = function
  | Tir.EApp (f, args) ->
    f.Tir.v_name :: List.concat_map calls_in_atom args
  | Tir.ELet (_, e, body) -> calls_in_expr e @ calls_in_expr body
  | Tir.ELetRec (fns, body) ->
    List.concat_map (fun (fn : Tir.fn_def) -> calls_in_expr fn.fn_body) fns
    @ calls_in_expr body
  | Tir.ESeq (e1, e2) -> calls_in_expr e1 @ calls_in_expr e2
  | Tir.ECase (_, brs, def) ->
    List.concat_map (fun (br : Tir.branch) -> calls_in_expr br.Tir.br_body) brs
    @ (match def with Some d -> calls_in_expr d | None -> [])
  | Tir.ECallPtr (f, args) ->
    calls_in_atom f @ List.concat_map calls_in_atom args
  | Tir.EAlloc (_, fields) -> List.concat_map calls_in_atom fields
  | Tir.EUpdate (a, fields) ->
    calls_in_atom a @ List.concat_map (fun (_, fa) -> calls_in_atom fa) fields
  | Tir.EAtom a -> calls_in_atom a
  | Tir.EField (a, _) -> calls_in_atom a
  | Tir.ETuple atoms -> List.concat_map calls_in_atom atoms
  | Tir.ERecord fields -> List.concat_map (fun (_, a) -> calls_in_atom a) fields
  | _ -> []
and calls_in_atom = function
  | Tir.AVar v    -> [v.Tir.v_name]
  | Tir.ADefRef d -> [d.Tir.did_name]
  | Tir.ALit _    -> []

(** Populate ctx.async_fns via seed + fixpoint over tm_fns.
    Seed: a fn is async if it directly calls a JsModuleBlocking extern.
    Fixpoint: a fn is async if it calls any already-async fn.
    Must run BEFORE emit_fn_decl to guarantee async_fns is complete. *)
let compute_async_fns (ctx : ctx) (fns : Tir.fn_def list) : unit =
  (* Build per-fn call set *)
  let fn_calls : (string, string list) Hashtbl.t = Hashtbl.create 16 in
  List.iter (fun (fn : Tir.fn_def) ->
    Hashtbl.replace fn_calls fn.fn_name (calls_in_expr fn.fn_body)
  ) fns;
  (* Seed: fns that directly call a blocking extern *)
  List.iter (fun (fn : Tir.fn_def) ->
    let called = Option.value (Hashtbl.find_opt fn_calls fn.fn_name) ~default:[] in
    if List.exists (fun callee ->
         match Hashtbl.find_opt ctx.extern_fns callee with
         | Some ed -> (match classify_js_extern ed with
                       | JsModuleBlocking | JsModuleBlockingRaises -> true
                       | _ -> false)
         | None -> false) called
    then Hashtbl.replace ctx.async_fns fn.fn_name ()
  ) fns;
  (* Fixpoint: propagate async through the call graph *)
  let changed = ref true in
  while !changed do
    changed := false;
    List.iter (fun (fn : Tir.fn_def) ->
      if not (Hashtbl.mem ctx.async_fns fn.fn_name) then begin
        let called = Option.value (Hashtbl.find_opt fn_calls fn.fn_name) ~default:[] in
        if List.exists (Hashtbl.mem ctx.async_fns) called then begin
          Hashtbl.replace ctx.async_fns fn.fn_name ();
          changed := true
        end
      end
    ) fns
  done

(* ── Forward declarations ────────────────────────────────────────── *)

let rec emit_val  ctx expr = emit_val_impl  ctx expr
and     emit_stmts ctx expr = emit_stmts_impl ctx expr
and     emit_case  ctx rv expr = emit_case_impl ctx rv expr
and     emit_fn_decl ctx fn = emit_fn_decl_impl ctx fn

(* ── Value emission ──────────────────────────────────────────────── *)

and emit_val_impl ctx expr =
  match expr with
  | Tir.EAtom a -> emit_atom ctx a

  | Tir.EApp (f, args) ->
    let name = f.Tir.v_name in
    begin match inline_binop name with
    | Some op when List.length args = 2 ->
      emit ctx "(";
      emit_atom ctx (List.nth args 0);
      emit ctx (" " ^ op ^ " ");
      emit_atom ctx (List.nth args 1);
      emit ctx ")"
    | _ ->
      begin match name, args with
      | ("neg_int" | "neg_float" | "negate" | "-" | "-."), [a] -> emit ctx "(-"; emit_atom ctx a; emit ctx ")"
      | ("not_bool" | "not"),  [a] -> emit ctx "(!"; emit_atom ctx a; emit ctx ")"
      | "div_int", [a; b] ->
        emit ctx "Math.trunc("; emit_atom ctx a;
        emit ctx " / "; emit_atom ctx b; emit ctx ")"
      | "/", [a; b] when (match atom_ty a with Tir.TInt -> true | _ -> false) ->
        emit ctx "Math.trunc("; emit_atom ctx a;
        emit ctx " / "; emit_atom ctx b; emit ctx ")"
      | "/", [a; b] ->
        emit ctx "("; emit_atom ctx a; emit ctx " / "; emit_atom ctx b; emit ctx ")"
      | "mod_int",   [a; b] ->
        emit ctx "("; emit_atom ctx a; emit ctx " % "; emit_atom ctx b; emit ctx ")"
      | "int_to_float", [a] ->
        emit_atom ctx a
      | "float_to_int", [a] | "float_truncate", [a] ->
        emit ctx "Math.trunc("; emit_atom ctx a; emit ctx ")"
      | "int_to_string",   [a] ->
        emit ctx "String("; emit_atom ctx a; emit ctx ")"
      | "bool_to_string",  [a] ->
        emit ctx "String("; emit_atom ctx a; emit ctx ")"
      | "float_to_string", [a] ->
        use_runtime ctx "march_float_to_string";
        emit ctx "march_float_to_string("; emit_atom ctx a; emit ctx ")"
      | ("string_length" | "string_byte_length"), [a] ->
        use_runtime ctx "march_string_byte_length";
        emit ctx "march_string_byte_length("; emit_atom ctx a; emit ctx ")"
      | "string_grapheme_count", [a] ->
        use_runtime ctx "march_string_grapheme_count";
        emit ctx "march_string_grapheme_count("; emit_atom ctx a; emit ctx ")"
      | "string_is_empty", [a] ->
        emit ctx "("; emit_atom ctx a; emit ctx " === \"\")"
      | "println", [a] ->
        emit ctx "console.log("; emit_atom ctx a; emit ctx ")"
      | "print", [a] ->
        use_runtime ctx "march_print";
        emit ctx "march_print("; emit_atom ctx a; emit ctx ")"
      | "print_stderr", [a] ->
        emit ctx "console.error("; emit_atom ctx a; emit ctx ")"
      | ("panic" | "panic_" | "todo_" | "unreachable_"), _ ->
        let msg = if args = [] then "\"panic\""
                  else (let b = Buffer.create 16 in
                        emit_atom { ctx with buf = b } (List.hd args);
                        Buffer.contents b) in
        emit ctx (Printf.sprintf "(() => { throw new Error(%s); })()" msg)
      (* ADT structural equality: eq_TypeName / neq_TypeName *)
      | n, [a; b] when String.length n > 3 && String.sub n 0 3 = "eq_" ->
        let ty = mangle (String.sub n 3 (String.length n - 3)) in
        emit ctx (Printf.sprintf "__eq_%s(" ty);
        emit_atom ctx a; emit ctx ", "; emit_atom ctx b; emit ctx ")"
      | n, [a; b] when String.length n > 4 && String.sub n 0 4 = "neq_" ->
        let ty = mangle (String.sub n 4 (String.length n - 4)) in
        emit ctx (Printf.sprintf "(!__eq_%s(" ty);
        emit_atom ctx a; emit ctx ", "; emit_atom ctx b; emit ctx "))"
      (* Runtime-delegated builtins *)
      | n, _ when (match n with
          | "string_to_int" | "string_to_float" | "string_to_lowercase"
          | "string_to_uppercase" | "string_trim" | "string_trim_start"
          | "string_trim_end" | "string_reverse" | "string_chars"
          | "string_from_chars" | "string_join" | "string_contains"
          | "string_starts_with" | "string_ends_with" | "string_slice"
          | "string_split" | "string_split_first" | "string_replace"
          | "string_replace_all" | "string_repeat" | "string_pad_left"
          | "string_pad_right" | "string_index_of" | "string_last_index_of"
          | "char_from_int" | "byte_to_char" | "char_to_int"
          | "char_is_digit" | "char_is_alphanumeric" | "char_is_whitespace"
          | "list_append" | "list_concat" -> true | _ -> false) ->
        let rt = "march_" ^ n in
        use_runtime ctx rt;
        emit ctx (rt ^ "(");
        List.iteri (fun i a ->
          if i > 0 then emit ctx ", "; emit_atom ctx a) args;
        emit ctx ")"
      (* Math builtins → JS Math.* *)
      | "math_sqrt",  [a] -> emit ctx "Math.sqrt(";  emit_atom ctx a; emit ctx ")"
      | "math_cbrt",  [a] -> emit ctx "Math.cbrt(";  emit_atom ctx a; emit ctx ")"
      | "math_sin",   [a] -> emit ctx "Math.sin(";   emit_atom ctx a; emit ctx ")"
      | "math_cos",   [a] -> emit ctx "Math.cos(";   emit_atom ctx a; emit ctx ")"
      | "math_tan",   [a] -> emit ctx "Math.tan(";   emit_atom ctx a; emit ctx ")"
      | "math_asin",  [a] -> emit ctx "Math.asin(";  emit_atom ctx a; emit ctx ")"
      | "math_acos",  [a] -> emit ctx "Math.acos(";  emit_atom ctx a; emit ctx ")"
      | "math_atan",  [a] -> emit ctx "Math.atan(";  emit_atom ctx a; emit ctx ")"
      | "math_atan2", [a; b] ->
        emit ctx "Math.atan2("; emit_atom ctx a; emit ctx ", "; emit_atom ctx b; emit ctx ")"
      | "math_sinh",  [a] -> emit ctx "Math.sinh(";  emit_atom ctx a; emit ctx ")"
      | "math_cosh",  [a] -> emit ctx "Math.cosh(";  emit_atom ctx a; emit ctx ")"
      | "math_tanh",  [a] -> emit ctx "Math.tanh(";  emit_atom ctx a; emit ctx ")"
      | "math_exp",   [a] -> emit ctx "Math.exp(";   emit_atom ctx a; emit ctx ")"
      | "math_exp2",  [a] -> emit ctx "Math.pow(2, "; emit_atom ctx a; emit ctx ")"
      | "math_log",   [a] -> emit ctx "Math.log(";   emit_atom ctx a; emit ctx ")"
      | "math_log2",  [a] -> emit ctx "Math.log2(";  emit_atom ctx a; emit ctx ")"
      | "math_log10", [a] -> emit ctx "Math.log10("; emit_atom ctx a; emit ctx ")"
      | "math_pow",   [a; b] ->
        emit ctx "Math.pow("; emit_atom ctx a; emit ctx ", "; emit_atom ctx b; emit ctx ")"
      (* General call — route externs through emit_extern_call seam *)
      | _, _ ->
        (match Hashtbl.find_opt ctx.extern_fns name with
         | Some ed -> emit_extern_call ctx ed args
         | None ->
           let is_async_callee = Hashtbl.mem ctx.async_fns name in
           if is_async_callee then emit ctx "(await ";
           emit ctx (mangle name ^ "(");
           List.iteri (fun i a ->
             if i > 0 then emit ctx ", "; emit_atom ctx a) args;
           if is_async_callee then emit ctx "))" else emit ctx ")")
      end
    end

  | Tir.ETuple atoms ->
    (* Tuples are accessed via EField with "$fvN" which maps to _N,
       so use object form { _0: a, _1: b, ... } rather than JS array. *)
    emit ctx "{ ";
    List.iteri (fun i a ->
      if i > 0 then emit ctx ", ";
      emit ctx (Printf.sprintf "_%d: " i); emit_atom ctx a) atoms;
    emit ctx " }"

  | Tir.ERecord fields ->
    emit ctx "({ ";
    List.iteri (fun i (name, a) ->
      if i > 0 then emit ctx ", ";
      emit ctx (name ^ ": "); emit_atom ctx a) fields;
    emit ctx " })"

  | Tir.EField (a, field) ->
    emit_atom ctx a; emit ctx ".";
    (* Closure free-variable fields are named "$fvN" in TIR but stored as "_N"
       in the JS closure struct (EAlloc uses positional _0/_1/_2 ... layout) *)
    if String.length field > 3 && String.sub field 0 3 = "$fv" then
      emit ctx ("_" ^ String.sub field 3 (String.length field - 3))
    else
      emit ctx field

  | Tir.EUpdate (a, updates) ->
    emit ctx "({ ..."; emit_atom ctx a;
    List.iter (fun (name, v) ->
      emit ctx (", " ^ name ^ ": "); emit_atom ctx v) updates;
    emit ctx " })"

  | Tir.EAlloc (ty, args) ->
    let tag = bare_ctor (match ty with Tir.TCon (t, _) -> t | _ -> "_") in
    (* Closure allocations: _0 is the apply function (must be a plain JS function,
       not a $clo wrapper); free-variable slots _1+ are ordinary atoms. *)
    let is_clo = String.length tag >= 4 && String.sub tag 0 4 = "$Clo" in
    emit ctx (Printf.sprintf "{ $: %S" tag);
    List.iteri (fun i a ->
      emit ctx (Printf.sprintf ", _%d: " i);
      if is_clo && i = 0 then emit_atom_raw ctx a
      else emit_atom ctx a) args;
    emit ctx " }"

  | Tir.EStackAlloc (ty, args) ->
    let tag = bare_ctor (match ty with Tir.TCon (t, _) -> t | _ -> "_") in
    emit ctx (Printf.sprintf "{ $: %S" tag);
    List.iteri (fun i a ->
      emit ctx (Printf.sprintf ", _%d: " i); emit_atom ctx a) args;
    emit ctx " }"

  (* EReuse(old, ty, args): Perceus reuses old's memory — in GC'd JS just alloc fresh *)
  | Tir.EReuse (_, ty, args) ->
    let tag = bare_ctor (match ty with Tir.TCon (t, _) -> t | _ -> "_") in
    emit ctx (Printf.sprintf "{ $: %S" tag);
    List.iteri (fun i a ->
      emit ctx (Printf.sprintf ", _%d: " i); emit_atom ctx a) args;
    emit ctx " }"

  (* EIncRC returns its atom; other RC ops are pure side-effects → undefined *)
  | Tir.EIncRC a | Tir.EAtomicIncRC a -> emit_atom ctx a
  | Tir.EDecRC _ | Tir.EAtomicDecRC _ | Tir.EFree _ ->
    emit ctx "undefined"

  (* Complex forms in value position: wrap in IIFE.
     When the body contains async calls, use an async IIFE + await so that
     the resolved value (not a Promise) is what the expression produces. *)
  | Tir.ECase _ | Tir.ELet _ | Tir.ELetRec _ | Tir.ESeq _ ->
    let has_async = List.exists (fun name ->
      match Hashtbl.find_opt ctx.extern_fns name with
      | Some ed -> (match classify_js_extern ed with
                    | JsModuleBlocking | JsModuleBlockingRaises -> true
                    | _ -> false)
      | None -> Hashtbl.mem ctx.async_fns name)
      (calls_in_expr expr) in
    if has_async then emit ctx "(await (async () => {\n"
    else emit ctx "(() => {\n";
    ctx.indent <- ctx.indent + 1;
    emit_stmts ctx expr;
    ctx.indent <- ctx.indent - 1;
    if has_async then (emit_indent ctx; emit ctx "})())")
    else (emit_indent ctx; emit ctx "})()")

  | Tir.ECallPtr (f, args) ->
    (* Post-Defun closure dispatch: closure struct has apply fn at ._0.
       Apply fn ABI: apply(clo, args...) — pass closure as first argument.
       Await if callee is a blocking extern or an async user fn. *)
    let is_async_call = match f with
      | Tir.AVar v ->
        (match Hashtbl.find_opt ctx.extern_fns v.Tir.v_name with
         | Some ed -> (match classify_js_extern ed with
                       | JsModuleBlocking | JsModuleBlockingRaises -> true
                       | _ -> false)
         | None -> Hashtbl.mem ctx.async_fns v.Tir.v_name)
      | Tir.ADefRef d ->
        (match Hashtbl.find_opt ctx.extern_fns d.Tir.did_name with
         | Some ed -> (match classify_js_extern ed with
                       | JsModuleBlocking | JsModuleBlockingRaises -> true
                       | _ -> false)
         | None -> Hashtbl.mem ctx.async_fns d.Tir.did_name)
      | _ -> false
    in
    if is_async_call then emit ctx "(await ";
    emit_atom ctx f;
    emit ctx "._0(";
    emit_atom ctx f;
    List.iter (fun a -> emit ctx ", "; emit_atom ctx a) args;
    if is_async_call then emit ctx "))" else emit ctx ")"

(* ── Statement emission ──────────────────────────────────────────── *)

and emit_stmts_impl ctx expr =
  match expr with

  | Tir.ELet (v, (Tir.ECase _ as case_expr), rest) ->
    (* let v = match ... — emit switch that assigns to v.
       Wrap in a block so this binding can shadow an outer variable of the same name. *)
    emit_indent ctx; emit ctx "{\n";
    ctx.indent <- ctx.indent + 1;
    emitl ctx ("let " ^ mangle v.Tir.v_name ^ ";");
    emit_case ctx (Some (mangle v.Tir.v_name)) case_expr;
    emit_stmts ctx rest;
    ctx.indent <- ctx.indent - 1;
    emit_indent ctx; emit ctx "}\n"

  | Tir.ELet (v, e1, e2) ->
    (* Wrap in a block so this binding can shadow a parameter or outer let of the same name. *)
    emit_indent ctx; emit ctx "{\n";
    ctx.indent <- ctx.indent + 1;
    emit_indent ctx;
    emit ctx ("const " ^ mangle v.Tir.v_name ^ " = ");
    emit_val ctx e1;
    emit ctx ";\n";
    emit_stmts ctx e2;
    ctx.indent <- ctx.indent - 1;
    emit_indent ctx; emit ctx "}\n"

  | Tir.ELetRec (fns, body) ->
    List.iter (emit_fn_decl ctx) fns;
    emit_stmts ctx body

  | Tir.ESeq (e1, e2) ->
    (match e1 with
     | Tir.EIncRC _ | Tir.EDecRC _ | Tir.EAtomicIncRC _ | Tir.EAtomicDecRC _
     | Tir.EFree _ | Tir.EReuse _ -> ()
     | _ ->
       emit_indent ctx;
       emit_val ctx e1;
       emit ctx ";\n");
    emit_stmts ctx e2

  | Tir.ECase _ ->
    emit_case ctx None expr

  (* RC side-effects in terminal position — no side effects needed in JS *)
  | Tir.EIncRC _ | Tir.EDecRC _ | Tir.EAtomicIncRC _ | Tir.EAtomicDecRC _
  | Tir.EFree _ -> ()

  (* EReuse in terminal position: Perceus reuses old's slot — in JS emit a fresh object *)
  | Tir.EReuse (_, ty, args) ->
    let tag = bare_ctor (match ty with Tir.TCon (t, _) -> t | _ -> "_") in
    emit_indent ctx;
    emit ctx (Printf.sprintf "return { $: %S" tag);
    List.iteri (fun i a ->
      emit ctx (Printf.sprintf ", _%d: " i); emit_atom ctx a) args;
    emit ctx " };\n"

  | e ->
    emit_indent ctx;
    emit ctx "return ";
    emit_val ctx e;
    emit ctx ";\n"

(* ── ECase: switch / if-else ─────────────────────────────────────── *)

and emit_case_impl ctx result_var expr =
  match expr with
  | Tir.ECase (scrutinee, branches, default) ->
    let s_ty = atom_ty scrutinee in
    (* Helper: emit the result assignment or return for a branch body *)
    let emit_result body =
      match result_var with
      | Some v ->
        emit_indent ctx;
        emit ctx (v ^ " = ");
        emit_val ctx body;
        emit ctx ";\n"
      | None ->
        emit_indent ctx;
        emit ctx "return ";
        emit_val ctx body;
        emit ctx ";\n"
    in
    (* Tuples can appear as TTuple or as TCon("$TupleN", ...) or detected
       by the branch tag starting with "$Tuple". Use branch tags as the
       authoritative signal since type info may be erased after Mono. *)
    let is_tuple_case =
      match s_ty with Tir.TTuple _ -> true | _ -> false
      || (match branches with
          | br :: _ -> let t = br.Tir.br_tag in
                       String.length t >= 6 && String.sub t 0 6 = "$Tuple"
          | [] -> false) in
    if is_tuple_case then begin
      (* Tuple: exactly one branch, directly destructure _0, _1, ... *)
      List.iter (fun br ->
        let scrut_name = match scrutinee with
          | Tir.AVar sv -> mangle sv.Tir.v_name
          | _ ->
            let tmp = "_tup" in
            emit_indent ctx;
            emit ctx (Printf.sprintf "const %s = " tmp);
            emit_atom ctx scrutinee;
            emit ctx ";\n";
            tmp
        in
        List.iteri (fun i bv ->
          emitl ctx (Printf.sprintf "const %s = %s._%d;"
            (mangle bv.Tir.v_name) scrut_name i)
        ) br.Tir.br_vars;
        (match result_var with
         | Some rv ->
           emit_indent ctx; emit ctx (rv ^ " = ");
           emit_val ctx br.Tir.br_body; emit ctx ";\n"
         | None -> emit_stmts ctx br.Tir.br_body)
      ) branches;
      (match default with
       | Some d ->
         (match result_var with
          | Some rv ->
            emit_indent ctx; emit ctx (rv ^ " = ");
            emit_val ctx d; emit ctx ";\n"
          | None -> emit_stmts ctx d)
       | None -> ())
    end else
    if is_literal_scrutinee_ty s_ty then begin
      (* Literal/bool: if/else chain *)
      List.iteri (fun i br ->
        if i = 0 then (emit_indent ctx; emit ctx "if (")
        else (emit_indent ctx; emit ctx "} else if (");
        emit_atom ctx scrutinee;
        emit ctx (" === " ^ literal_tag_js br.Tir.br_tag ^ ") {\n");
        with_indent ctx (fun () ->
          (* bind branch vars (rare for literal patterns, but possible) *)
          List.iteri (fun j bv ->
            let scrut_name = match scrutinee with
              | Tir.AVar sv -> mangle sv.Tir.v_name | _ -> "_s" in
            emitl ctx (Printf.sprintf "const %s = %s._%d;"
              (mangle bv.Tir.v_name) scrut_name j)
          ) br.Tir.br_vars;
          emit_result br.Tir.br_body)
      ) branches;
      (match default with
       | Some d ->
         emit_indent ctx; emit ctx "} else {\n";
         with_indent ctx (fun () -> emit_result d);
         emit_indent ctx; emit ctx "}\n"
       | None ->
         if branches <> [] then (emit_indent ctx; emit ctx "}\n"))
    end else begin
      (* Constructor: switch on .$ *)
      emit_indent ctx; emit ctx "switch (";
      emit_atom ctx scrutinee;
      emit ctx ".$) {\n";
      List.iter (fun br ->
        (* Use bare ctor name to match EAlloc which stores bare tag in $ field *)
        let tag = bare_ctor br.Tir.br_tag in
        emitl ctx (Printf.sprintf "  case %S: {" tag);
        with_indent ctx (fun () ->
          with_indent ctx (fun () ->
            (* Bind constructor fields to br_vars *)
            let scrut_name = match scrutinee with
              | Tir.AVar sv -> mangle sv.Tir.v_name
              | _ ->
                let tmp = "_scrut" in
                emit_indent ctx;
                emit ctx (Printf.sprintf "const %s = " tmp);
                emit_atom ctx scrutinee;
                emit ctx ";\n";
                tmp
            in
            List.iteri (fun i bv ->
              emitl ctx (Printf.sprintf "const %s = %s._%d;"
                (mangle bv.Tir.v_name) scrut_name i)
            ) br.Tir.br_vars;
            (match result_var with
             | Some rv ->
               emit_indent ctx;
               emit ctx (rv ^ " = ");
               emit_val ctx br.Tir.br_body;
               emit ctx ";\n";
               emitl ctx "break;"
             | None ->
               emit_stmts ctx br.Tir.br_body)
          )
        );
        emitl ctx "  }"
      ) branches;
      (match default with
       | Some d ->
         emitl ctx "  default: {";
         with_indent ctx (fun () ->
           with_indent ctx (fun () ->
             match result_var with
             | Some rv ->
               emit_indent ctx; emit ctx (rv ^ " = ");
               emit_val ctx d; emit ctx ";\n";
               emitl ctx "break;"
             | None -> emit_stmts ctx d
           )
         );
         emitl ctx "  }"
       | None -> ());
      emitl ctx "}"
    end
  | _ -> failwith "emit_case: expected ECase"

(* ── Function definition emission ───────────────────────────────── *)

and emit_fn_decl_impl ctx (fn : Tir.fn_def) =
  let fname = mangle fn.Tir.fn_name in
  let is_async = Hashtbl.mem ctx.async_fns fn.Tir.fn_name in
  (* Record source map segment: current output line → source line for this fn *)
  (match Hashtbl.find_opt ctx.fn_lines fn.Tir.fn_name with
   | Some src_line when src_line > 0 ->
     ctx.segments := (ctx.line, src_line - 1) :: !(ctx.segments)
   | _ -> ());
  emit_indent ctx;
  if is_async then emit ctx "async ";
  emit ctx ("function " ^ fname ^ "(");
  List.iteri (fun i p ->
    if i > 0 then emit ctx ", ";
    emit ctx (mangle p.Tir.v_name)) fn.Tir.fn_params;
  emit ctx ") {\n";
  (* Register params so emit_atom won't add $clo suffix to param variables
     that happen to share a name with a module-level function. *)
  Hashtbl.clear ctx.param_names;
  List.iter (fun p -> Hashtbl.replace ctx.param_names p.Tir.v_name ()) fn.Tir.fn_params;
  with_indent ctx (fun () -> emit_stmts ctx fn.Tir.fn_body);
  Hashtbl.clear ctx.param_names;
  emit_indent ctx;
  emit ctx "}\n";
  (* Closure-protocol wrapper: allows this function to be used as a first-class
     value via ECallPtr dispatch (f._0(f, args)).
     $_ is the closure self-pointer (unused since top-level fns have no free vars).
     Async fns get an async arrow so the $clo call also propagates the Promise. *)
  emit_indent ctx;
  if is_async then
    emit ctx ("const " ^ fname ^ "$clo = { _0: async ($_")
  else
    emit ctx ("const " ^ fname ^ "$clo = { _0: ($_");
  List.iter (fun p -> emit ctx (", " ^ mangle p.Tir.v_name)) fn.Tir.fn_params;
  emit ctx (") => " ^ fname ^ "(");
  List.iteri (fun i p ->
    if i > 0 then emit ctx ", ";
    emit ctx (mangle p.Tir.v_name)) fn.Tir.fn_params;
  emit ctx ") };\n\n"

(* ── Structural equality ─────────────────────────────────────────── *)

(** Emit a per-type structural equality function __eq_TypeName(a, b). *)
let emit_eq_fn ctx (td : Tir.type_def) =
  let emit_field_cmp fname fty =
    match fty with
    | Tir.TInt | Tir.TFloat | Tir.TBool | Tir.TString ->
      emitl ctx (Printf.sprintf "if (a.%s !== b.%s) return false;" fname fname)
    | Tir.TCon (ty_name, _) ->
      emitl ctx (Printf.sprintf "if (!__eq_%s(a.%s, b.%s)) return false;"
        (mangle ty_name) fname fname)
    | _ ->
      emitl ctx (Printf.sprintf "if (a.%s !== b.%s) return false;" fname fname)
  in
  let emit_field_cmp_idx i fty =
    let fname = Printf.sprintf "_%d" i in
    match fty with
    | Tir.TInt | Tir.TFloat | Tir.TBool | Tir.TString ->
      emitl ctx (Printf.sprintf "if (a.%s !== b.%s) return false;" fname fname)
    | Tir.TCon (ty_name, _) ->
      emitl ctx (Printf.sprintf "if (!__eq_%s(a.%s, b.%s)) return false;"
        (mangle ty_name) fname fname)
    | _ ->
      emitl ctx (Printf.sprintf "if (a.%s !== b.%s) return false;" fname fname)
  in
  match td with
  | Tir.TDVariant (name, ctors) ->
    emitl ctx (Printf.sprintf "function __eq_%s(a, b) {" (mangle name));
    with_indent ctx (fun () ->
      emitl ctx "if (a.$ !== b.$) return false;";
      emitl ctx "switch (a.$) {";
      with_indent ctx (fun () ->
        List.iter (fun (ctor, fields) ->
          emitl ctx (Printf.sprintf "case %S: {" ctor);
          with_indent ctx (fun () ->
            List.iteri (fun i fty -> emit_field_cmp_idx i fty) fields;
            emitl ctx "return true;"
          );
          emitl ctx "}"
        ) ctors
      );
      emitl ctx "}";
      emitl ctx "return true;"
    );
    emitl ctx "}\n"
  | Tir.TDRecord (name, fields) ->
    emitl ctx (Printf.sprintf "function __eq_%s(a, b) {" (mangle name));
    with_indent ctx (fun () ->
      List.iter (fun (fname, fty) -> emit_field_cmp fname fty) fields;
      emitl ctx "return true;"
    );
    emitl ctx "}\n"
  | Tir.TDClosure _ -> ()

(* ── Extern bridge emission ──────────────────────────────────────── *)

(** Build the $clo wrapper string for a single extern.
    Dispatches on js_extern_kind:
    - Sync/CBacked: plain arrow (Chunk 0)
    - Raises: arrow with try/catch → Ok/Err (Chunk B)
    - Blocking: plain arrow for now — Chunk A upgrades to async *)
let emit_extern_clo_str (ed : Tir.extern_decl) : string =
  let march_name = mangle ed.ed_march_name in
  let nparams = List.length ed.ed_params in
  let pnames = List.init nparams (fun i -> Printf.sprintf "p%d" i) in
  let plist = String.concat ", " pnames in
  match classify_js_extern ed with
  | JsModuleSync | CBacked ->
    Printf.sprintf "const %s$clo = { _0: ($_, %s) => %s(%s) };\n"
      march_name plist march_name plist
  | JsModuleBlocking ->
    Printf.sprintf "const %s$clo = { _0: async ($_, %s) => (await %s(%s)) };\n"
      march_name plist march_name plist
  | JsModuleRaises ->
    warn_err_type ed.ed_march_name (err_payload_ty ed.Tir.ed_ret);
    Printf.sprintf
      "const %s$clo = { _0: ($_, %s) => {\n  \
         try { return { $: \"Ok\", _0: %s(%s) }; }\n  \
         catch (e) { return { $: \"Err\", _0: __js_err_to(e) }; }\n} };\n"
      march_name plist march_name plist
  | JsModuleBlockingRaises ->
    warn_err_type ed.ed_march_name (err_payload_ty ed.Tir.ed_ret);
    Printf.sprintf
      "const %s$clo = { _0: async ($_, %s) => {\n  \
         try { return { $: \"Ok\", _0: (await %s(%s)) }; }\n  \
         catch (e) { return { $: \"Err\", _0: __js_err_to(e) }; }\n} };\n"
      march_name plist march_name plist

(** Emit extern bridges for [eds].  Returns (imports_str, consts_str):
    - imports_str: ES import statements for JS-module externs (goes before const decls)
    - consts_str:  const aliases, runtime registrations, and $clo wrappers *)
let emit_extern_bridges (ctx : ctx) (eds : Tir.extern_decl list) : string * string =
  if eds = [] then ("", "")
  else begin
    let imp_buf = Buffer.create 256 in
    let cst_buf = Buffer.create 256 in
    let imp s = Buffer.add_string imp_buf s in
    let cst s = Buffer.add_string cst_buf s in

    (* ── JS module imports ──────────────────────────────────────────── *)
    let js_externs = List.filter (fun ed -> is_js_module ed.Tir.ed_lib_name) eds in
    let by_lib : (string, (string * string) list ref) Hashtbl.t = Hashtbl.create 4 in
    List.iter (fun (ed : Tir.extern_decl) ->
      let key = ed.ed_lib_name in
      match Hashtbl.find_opt by_lib key with
      | Some lst -> lst := (ed.ed_march_name, ed.ed_js_sym) :: !lst
      | None -> Hashtbl.add by_lib key (ref [(ed.ed_march_name, ed.ed_js_sym)])
    ) js_externs;
    Hashtbl.iter (fun lib pairs ->
      let specs = List.map (fun (march_name, js_sym) ->
        if march_name = js_sym then js_sym
        else js_sym ^ " as " ^ mangle march_name
      ) !pairs in
      imp (Printf.sprintf "import { %s } from %s;\n"
             (String.concat ", " specs) (js_string_lit lib))
    ) by_lib;
    if js_externs <> [] then imp "\n";

    (* ── Runtime-backed externs (non-JS-module lib names) ───────────── *)
    let rt_externs = List.filter (fun ed -> not (is_js_module ed.Tir.ed_lib_name)) eds in
    List.iter (fun (ed : Tir.extern_decl) ->
      let march_name = mangle ed.ed_march_name in
      let c_sym = ed.ed_c_name in
      let march_prefix = "march_" in
      let is_runtime = String.length c_sym >= String.length march_prefix
                       && String.sub c_sym 0 (String.length march_prefix) = march_prefix in
      if is_runtime then use_runtime ctx c_sym;
      if march_name <> c_sym then
        cst (Printf.sprintf "const %s = %s;\n" march_name c_sym)
    ) rt_externs;
    if rt_externs <> [] then cst "\n";

    (* ── $clo wrappers for first-class use of extern fns ────────────── *)
    List.iter (fun ed -> cst (emit_extern_clo_str ed)) eds;
    if eds <> [] then cst "\n";

    (Buffer.contents imp_buf, Buffer.contents cst_buf)
  end

(* ── Source map generation ───────────────────────────────────────── *)

let base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

(** VLQ-encode a signed integer as base64 (source map v3 format). *)
let vlq_encode value =
  let buf = Buffer.create 4 in
  let vlq = ref (if value < 0 then ((-value) lsl 1) lor 1 else value lsl 1) in
  let continue_ = ref true in
  while !continue_ do
    let digit = !vlq land 0x1F in
    vlq := !vlq lsr 5;
    let digit = if !vlq > 0 then digit lor 0x20 else digit in
    Buffer.add_char buf base64_chars.[digit];
    if !vlq = 0 then continue_ := false
  done;
  Buffer.contents buf

(** Count newlines in string s. *)
let count_lines s =
  String.fold_left (fun n c -> if c = '\n' then n + 1 else n) 0 s

(** Build source map v3 JSON for a single-source JS file.
    [segments] is a list of (output_line_0indexed, source_line_0indexed) pairs.
    [preamble_lines] is the number of output lines before the first function. *)
let build_source_map ~source_file ~segments ~preamble_lines =
  let adjusted = List.map (fun (ol, sl) -> (ol + preamble_lines, sl)) segments in
  let sorted = List.sort_uniq (fun (a, _) (b, _) -> compare a b) adjusted in
  if sorted = [] then None
  else begin
    let max_line = List.fold_left (fun acc (ol, _) -> max acc ol) 0 sorted in
    let segs = Array.make (max_line + 1) "" in
    let prev_src = ref 0 in
    List.iter (fun (out_line, src_line) ->
      let delta = src_line - !prev_src in
      prev_src := src_line;
      (* Segment: col=0, src_file_delta=0, src_line_delta, src_col=0 *)
      segs.(out_line) <- "A" ^ "A" ^ vlq_encode delta ^ "A"
    ) sorted;
    let mappings = String.concat ";" (Array.to_list segs) in
    Some (Printf.sprintf "{\n  \"version\": 3,\n  \"sources\": [%s],\n  \"sourceRoot\": \"\",\n  \"names\": [],\n  \"mappings\": %s\n}\n"
      (js_string_lit source_file) (js_string_lit mappings))
  end

(* ── Module emission ─────────────────────────────────────────────── *)

(* Closure-protocol wrappers for builtins used as first-class values.
   When a builtin is captured in a closure, Defun calls it via f._0(f, args...).
   These objects satisfy that protocol while also being directly callable.
   Inline call sites still emit the faster form (String(x), etc.). *)
let builtin_wrappers = {|
const int_to_string   = { _0: ($_, x) => String(x) };
const bool_to_string  = { _0: ($_, x) => String(x) };
const int_to_float    = { _0: ($_, x) => x };
const float_to_int    = { _0: ($_, x) => Math.trunc(x) };
const float_truncate  = { _0: ($_, x) => Math.trunc(x) };
const string_is_empty = { _0: ($_, x) => x === "" };
const not_bool        = { _0: ($_, x) => !x };
const negate_int      = { _0: ($_, x) => -x };
const negate_float    = { _0: ($_, x) => -x };
|}

(** Raised by [emit_module] when used C-backed externs are compiled with [--target js].
    Each string in the list is a formatted diagnostic for one offending extern. *)
exception Js_emit_error of string list

(** Emit a TIR module as an ES module string.
    Returns [(js_content, source_map_json option)].
    [fn_lines] maps TIR function names to 1-indexed source lines (from the AST).
    [source_file] is the path to the originating .march file (for source maps).
    Raises [Js_emit_error] when used C-backed externs are present (Chunk C). *)
let emit_module ?(source_file="") ?(fn_lines=[]) (m : Tir.tir_module) : string * string option =
  let ctx = create_ctx ~fn_lines () in
  (* Pre-register all user-defined function names so emit_atom emits $clo versions *)
  List.iter (fun fn -> Hashtbl.replace ctx.fn_names fn.Tir.fn_name ()) m.Tir.tm_fns;
  (* Register externs separately for lazy tracking (not in fn_names to avoid
     emitting $clo suffixes for extern call sites that don't need them) *)
  List.iter (fun (ed : Tir.extern_decl) ->
    Hashtbl.replace ctx.extern_fns ed.ed_march_name ed
  ) m.Tir.tm_externs;
  (* Equality helpers before functions (needed by EApp eq_ calls) *)
  List.iter (emit_eq_fn ctx) m.Tir.tm_types;
  (* Async analysis: must run after extern_fns is populated, before any fn emission *)
  compute_async_fns ctx m.Tir.tm_fns;
  (* Top-level functions — populates used_externs via call-site tracking
     and records (output_line, source_line) segments for source maps *)
  List.iter (emit_fn_decl ctx) m.Tir.tm_fns;
  let fns_js = Buffer.contents ctx.buf in
  let raw_segments = !(ctx.segments) in
  (* Emit extern bridges only for externs actually referenced in the emitted code *)
  let used_ed = List.filter (fun (ed : Tir.extern_decl) ->
    Hashtbl.mem ctx.used_externs ed.ed_march_name
  ) m.Tir.tm_externs in
  (* Chunk C: reject used C-backed externs — they have no JS implementation *)
  let bad_externs = List.filter (fun ed -> classify_js_extern ed = CBacked) used_ed in
  if bad_externs <> [] then begin
    let msgs = List.map (fun (ed : Tir.extern_decl) ->
      Printf.sprintf
        "error: extern \"%s\" function `%s` cannot be called on the JavaScript target.\n\
         The JS backend supports only JS-module externs:\n\
           extern \"node:fs\"   extern \"npm:lodash\"   extern \"./local.mjs\"\n\
         `%s` is bound to the C symbol `%s`, which has no JS runtime\n\
         implementation. To call it from JS, wrap it in a JS module, or build a\n\
         native/wasm target."
        ed.Tir.ed_lib_name ed.Tir.ed_march_name ed.Tir.ed_march_name ed.Tir.ed_c_name
    ) bad_externs in
    raise (Js_emit_error msgs)
  end;
  let (extern_imports, extern_consts) = emit_extern_bridges ctx used_ed in
  (* Chunk B: __js_err_to helper — emitted only when at least one raises extern is used *)
  let raises_helper =
    if List.exists (fun ed -> match classify_js_extern ed with
                               | JsModuleRaises | JsModuleBlockingRaises -> true
                               | _ -> false) used_ed then
      "const __js_err_to = (e) => String(e?.message ?? e);\n\n"
    else ""
  in
  (* Runtime-dependent builtin wrappers need these in the import regardless of
     whether the compiled code already uses them directly. *)
  Hashtbl.replace ctx.runtime_uses "march_float_to_string" ();
  Hashtbl.replace ctx.runtime_uses "march_string_byte_length" ();
  let runtime_wrappers =
    "const float_to_string    = { _0: ($_, x) => march_float_to_string(x) };\n" ^
    "const string_length      = { _0: ($_, x) => march_string_byte_length(x) };\n" ^
    "const string_byte_length = { _0: ($_, x) => march_string_byte_length(x) };\n"
  in
  let runtime_import =
    let names = Hashtbl.fold (fun k () acc -> k :: acc) ctx.runtime_uses [] in
    let sorted = List.sort String.compare names in
    if sorted = [] then ""
    else
      "import { " ^ String.concat ", " sorted
      ^ " } from \"./march_runtime.mjs\";\n\n"
  in
  (* Order: runtime import → extern module imports → builtin consts → extern consts → raises helper → fns *)
  let preamble = runtime_import ^ extern_imports ^ builtin_wrappers ^ runtime_wrappers ^ extern_consts ^ raises_helper in
  (* Build ES exports and call main() *)
  let export_buf = Buffer.create 256 in
  let has_main = List.exists (fun fn -> fn.Tir.fn_name = "main") m.Tir.tm_fns in
  if has_main then begin
    Buffer.add_string export_buf "export { main };\n";
    if Hashtbl.mem ctx.async_fns "main" then
      Buffer.add_string export_buf "await main();\n"
    else
      Buffer.add_string export_buf "main();\n"
  end;
  List.iter (fun name ->
    if name <> "main" then
      Buffer.add_string export_buf
        (Printf.sprintf "export { %s };\n" (mangle name))
  ) m.Tir.tm_exports;
  let js = preamble ^ fns_js ^ Buffer.contents export_buf in
  (* Source map: only when source_file provided and segments were recorded *)
  let map_opt =
    if source_file = "" || raw_segments = [] then None
    else
      let preamble_lines = count_lines preamble in
      build_source_map ~source_file ~segments:raw_segments ~preamble_lines
  in
  (js, map_opt)
