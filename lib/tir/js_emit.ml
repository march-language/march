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

(* Tail-call loop state for the function (or mutual-TCO group) currently
   being emitted.  A tail call to a member is emitted as an assignment to the
   $tco_aN parameter slots (and $tco_tag for a group) followed by
   `continue __tco`, so self and mutual tail recursion run in constant stack.
   None outside such a function and inside any nested JS function (an IIFE or
   an ELetRec fn), where `continue __tco` would not reach the loop. *)
type tco = {
  tco_members : (string * int * Tir.var list) list;  (* name, tag, params *)
  tco_mutual  : bool;
}

type ctx = {
  buf          : Buffer.t;
  mutable indent : int;
  mutable line   : int;  (* 0-indexed output line counter, updated by emit *)
  runtime_uses : (string, unit) Hashtbl.t;
  (* runtime function names referenced — imported at top of output *)
  fn_names     : (string, unit) Hashtbl.t;
  (* user-defined function names in this module — used to emit $clo wrappers *)
  zero_arg_fns : (string, unit) Hashtbl.t;
  (* the zero-parameter subset of fn_names: a module-level `let` outside the
     entry module is lowered to one, and a value-position reference CALLS it
     (see emit_atom; native's Llvm_ctx.zero_arg_fns) *)
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
  local_fns    : (string, unit) Hashtbl.t;
  (* ELetRec-local function names seen during emission — legitimate bare-call
     targets that are not in fn_names *)
  unmapped     : (string, string) Hashtbl.t;
  (* direct-call names that resolve to nothing (not a user fn, local fn,
     extern, or mapped builtin): emitting them would produce a runtime
     ReferenceError, so emit_module raises Js_emit_error instead *)
  name_env     : (string, string) Hashtbl.t;
  (* source local-binding name → the JS identifier it is currently emitted as.
     A `let x = …` that SHADOWS an in-scope `x` is emitted under a fresh unique
     JS name (x$sN) so the RHS — evaluated while the outer `x` is still the
     live one — never resolves to the block-hoisted inner `const x` in its
     temporal dead zone. Populated with params (identity) at fn entry, then
     pushed/popped around each ELet body. *)
  mutable shadow_ctr : int;
  (* monotonic counter minting the $sN suffix for shadowing rebindings *)
  mutable tco : tco option;
  (* tail-call loop target of the function being emitted (see [tco]) *)
  reserved : (string, unit) Hashtbl.t;
  (* JS names of variables being assigned by [emit_assign] right now: a
     binding minted inside (an arm's `x`, an inner `let x`) must not take
     one, or it would capture the assignment meant for the outer variable *)
  mutable int_check : bool;
  (* --js-int-check: integer + - * results are range-checked (see march_ck_int) *)
  mutable src_file : string;
  mutable cur_loc : string;
  (* "Fn.name (file.march:LINE)" of the function being emitted, for diagnostics *)
  type_defs : (string, Tir.type_def) Hashtbl.t;
  (* the module's variant/record declarations by name, for [show_expr] *)
  show_fns : (string, string) Hashtbl.t;
  (* type key → name of its generated `__show$N` printer (see [show_expr]) *)
  show_buf : Buffer.t;
  (* the generated printers, appended after the functions (hoisted) *)
}

let create_ctx ?(fn_lines=[]) () = {
  buf          = Buffer.create 4096;
  indent       = 0;
  line         = 0;
  runtime_uses = Hashtbl.create 16;
  fn_names     = Hashtbl.create 64;
  zero_arg_fns = Hashtbl.create 16;
  param_names  = Hashtbl.create 8;
  extern_fns   = Hashtbl.create 8;
  used_externs = Hashtbl.create 8;
  async_fns    = Hashtbl.create 8;
  fn_lines     = (let t = Hashtbl.create 16 in
                  List.iter (fun (n, l) -> Hashtbl.replace t n l) fn_lines; t);
  segments     = ref [];
  local_fns    = Hashtbl.create 8;
  unmapped     = Hashtbl.create 4;
  name_env     = Hashtbl.create 16;
  shadow_ctr   = 0;
  tco          = None;
  reserved     = Hashtbl.create 8;
  int_check    = false;
  src_file     = "";
  cur_loc      = "";
  type_defs    = Hashtbl.create 16;
  show_fns     = Hashtbl.create 8;
  show_buf     = Buffer.create 256;
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
  | LitInt n when ctx.int_check && (n > 9007199254740991 || n < -9007199254740991) ->
    (* --js-int-check: a literal (often a constant-folded product) that a
       double can't hold exactly would silently round. *)
    use_runtime ctx "march_ck_lit";
    emit ctx (Printf.sprintf "march_ck_lit(%s, %s)"
      (js_string_lit (string_of_int n)) (js_string_lit ctx.cur_loc))
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

(** The JS identifier a source local name is currently emitted as.
    Falls back to the plain mangling for anything not in [name_env]
    (closure free-vars accessed via EField, or top-level names). *)
let js_local ctx name =
  match Hashtbl.find_opt ctx.name_env name with
  | Some js -> js
  | None    -> mangle name

(** Mint the JS identifier for a NEW local binding of [name]. When [name] is
    already in scope the binding SHADOWS it, so we mint a fresh unique id
    (name$sN) — this is what makes a self-referential rebinding safe on JS:
    the RHS (emitted before [install_local]) still resolves the source name to
    the outer binding, and the fresh inner id never collides with it (no
    temporal-dead-zone read of a same-named block-hoisted const). *)
let fresh_local_name ctx name =
  if Hashtbl.mem ctx.name_env name || Hashtbl.mem ctx.reserved (mangle name) then begin
    ctx.shadow_ctr <- ctx.shadow_ctr + 1;
    mangle name ^ "$s" ^ string_of_int ctx.shadow_ctr
  end else mangle name

(* Run [f] with [js] reserved (see [ctx.reserved]); nested reservations of
   the same name restore correctly. *)
let with_reserved ctx js f =
  let had = Hashtbl.mem ctx.reserved js in
  Hashtbl.replace ctx.reserved js ();
  let r = f () in
  if not had then Hashtbl.remove ctx.reserved js;
  r

(** Install [js] as the current emission of source [name]; returns the previous
    mapping so [unbind_local] can restore it when the binding leaves scope. *)
let install_local ctx name js =
  let prev = Hashtbl.find_opt ctx.name_env name in
  Hashtbl.replace ctx.name_env name js;
  prev

let unbind_local ctx name prev =
  match prev with
  | Some o -> Hashtbl.replace ctx.name_env name o
  | None   -> Hashtbl.remove ctx.name_env name

(** Bind a case branch's pattern variables: emit `const <js> = <scrut>._i` for
    each and register it (shadow-renaming an outer same-named local), so the
    branch body's uses resolve to the pattern binding rather than any outer
    rename. Returns the restore list for [unbind_br_vars] after the body. *)
let bind_br_vars ctx scrut_name br_vars =
  List.mapi (fun i bv ->
    let nm = bv.Tir.v_name in
    let js = fresh_local_name ctx nm in
    emitl ctx (Printf.sprintf "const %s = %s._%d;" js scrut_name i);
    (nm, install_local ctx nm js)
  ) br_vars

let unbind_br_vars ctx binds =
  List.iter (fun (nm, prev) -> unbind_local ctx nm prev) (List.rev binds)

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
       (* a let-bound local of the same name shadows the function *)
       && not (Hashtbl.mem ctx.name_env v.Tir.v_name)
    then begin
      (* A zero-param top-level fn referenced at a non-function type is a
         module-level `let` from outside the entry module (lowered to a
         zero-arg fn; the entry module's own lets are injected as locals):
         call it for the value, as native does (llvm_emit's emit_atom
         falls through to a 0-arg call for zero_arg_fns), once per read,
         no caching (#1170).  At a function type it is a first-class
         function value and keeps its $clo wrapper, exactly as native's
         TFn arm wraps it in a closure. *)
      match v.Tir.v_ty with
      | Tir.TFn _ -> emit ctx (n ^ "$clo")
      | _ when Hashtbl.mem ctx.zero_arg_fns v.Tir.v_name ->
        if Hashtbl.mem ctx.async_fns v.Tir.v_name
        then emit ctx ("(await " ^ n ^ "())")
        else emit ctx (n ^ "()")
      | _ -> emit ctx (n ^ "$clo")
    end
    (* Local binding: honour any active shadow-rename. *)
    else emit ctx (js_local ctx v.Tir.v_name)
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

(* ── `to_string` without a Show impl ──────────────────────────────── *)

(** A JS expression rendering [v] (a JS expression, evaluated once per use, so
    pass a name) of static type [ty] the way the interpreter's
    [value_to_string] does, and native's constructor-descriptor renderer
    ([Llvm_ctor_desc], march_extras.c): records with their fields sorted by
    name, `Ctor(a, b)`, a List as `[a, b]`, and every String beneath the top
    quoted and escaped.  This is what the `to_string` builtin reaches on JS:
    mono routes a value with no `Show` impl (a plain record, a variant with no
    derive) to it.  JS values carry no Int/Float distinction, so the type is
    read statically; a field typed by a type variable the declaration does not
    let us resolve (more than one parameter) is classified at run time by
    march_show_dyn, which prints a whole-number Float as an Int. *)
let rec show_expr ctx (ty : Tir.ty) (v : string) : string =
  match ty with
  | Tir.TInt | Tir.TCon ("Int", []) -> Printf.sprintf "String(%s)" v
  | Tir.TBool | Tir.TCon ("Bool", []) -> Printf.sprintf "(%s ? \"true\" : \"false\")" v
  | Tir.TFloat | Tir.TCon ("Float", []) ->
    use_runtime ctx "march_float_to_string";
    Printf.sprintf "march_float_to_string(%s)" v
  | Tir.TString | Tir.TCon ("String", []) ->
    use_runtime ctx "march_show_str";
    Printf.sprintf "march_show_str(%s)" v
  | Tir.TCon ("Atom", []) -> v
  | Tir.TUnit | Tir.TTuple [] | Tir.TCon ("Unit", []) -> "\"()\""
  | Tir.TFn _ -> "\"<fn>\""
  | Tir.TTuple ts ->
    "(\"(\" + " ^ String.concat " + \", \" + "
      (List.mapi (fun i t -> show_expr ctx t (Printf.sprintf "%s._%d" v i)) ts)
    ^ " + \")\")"
  | Tir.TRecord fs -> show_record ctx fs v
  | Tir.TCon (name, args) ->
    (match find_type_def ctx name with
     | Some td -> Printf.sprintf "%s(%s)" (show_fn ctx ty name args td) v
     | None -> show_dyn ctx v)
  | Tir.TPtr _ | Tir.TVar _ -> show_dyn ctx v

and show_dyn ctx v =
  use_runtime ctx "march_show_dyn";
  Printf.sprintf "march_show_dyn(%s)" v

and show_record ctx fs v =
  let fs = List.stable_sort (fun (a, _) (b, _) -> String.compare a b) fs in
  if fs = [] then "\"{  }\""
  else
    "(\"{ " ^ String.concat " + \", "
      (List.map (fun (f, t) ->
           f ^ ": \" + "
           ^ show_expr ctx t (Printf.sprintf "%s.%s" v f)) fs)
    ^ " + \" }\")"

and find_type_def ctx name =
  match Hashtbl.find_opt ctx.type_defs name with
  | Some _ as r -> r
  | None ->
    (* An unqualified reference to a qualified declaration (or the reverse):
       accept the bare-name match only when it is unique. *)
    let bare = bare_ctor name in
    let hits = Hashtbl.fold (fun k td acc ->
        if bare_ctor k = bare then td :: acc else acc) ctx.type_defs [] in
    (match hits with [td] -> Some td | _ -> None)

(* The printer function for one instantiation [name(args)], generated once
   into [show_buf].  Field types mention the declaration's parameters as
   TVars; with exactly one parameter and one argument the substitution is
   unambiguous, otherwise those fields stay TVar (march_show_dyn). *)
and show_fn ctx ty name args td =
  let key = Pp.string_of_ty ty in
  match Hashtbl.find_opt ctx.show_fns key with
  | Some f -> f
  | None ->
    let f = Printf.sprintf "__show$%d" (Hashtbl.length ctx.show_fns) in
    Hashtbl.replace ctx.show_fns key f;
    let field_tys = match td with
      | Tir.TDVariant (_, ctors) -> List.concat_map snd ctors
      | Tir.TDRecord (_, fs) -> List.map snd fs
      | Tir.TDClosure _ -> [] in
    let rec tvars acc = function
      | Tir.TVar a -> if List.mem a acc then acc else acc @ [a]
      | Tir.TTuple ts | Tir.TCon (_, ts) -> List.fold_left tvars acc ts
      | Tir.TRecord fs -> List.fold_left tvars acc (List.map snd fs)
      | Tir.TFn (ps, r) -> List.fold_left tvars acc (ps @ [r])
      | Tir.TPtr t -> tvars acc t
      | _ -> acc in
    let subst = match List.fold_left tvars [] field_tys, args with
      | [a], [t] -> (fun x -> if x = a then Some t else None)
      | _ -> (fun _ -> None) in
    let rec sub = function
      | Tir.TVar a as t -> (match subst a with Some t' -> t' | None -> t)
      | Tir.TTuple ts -> Tir.TTuple (List.map sub ts)
      | Tir.TCon (n, ts) -> Tir.TCon (n, List.map sub ts)
      | Tir.TRecord fs -> Tir.TRecord (List.map (fun (f, t) -> (f, sub t)) fs)
      | Tir.TFn (ps, r) -> Tir.TFn (List.map sub ps, sub r)
      | Tir.TPtr t -> Tir.TPtr (sub t)
      | t -> t in
    let b = Buffer.create 256 in
    Printf.bprintf b "function %s(v) {\n" f;
    (match td with
     | Tir.TDRecord (_, fs) ->
       Printf.bprintf b "  return %s;\n"
         (show_record ctx (List.map (fun (n, t) -> (n, sub t)) fs) "v")
     | Tir.TDVariant (_, ctors)
       when bare_ctor name = "List"
         && List.sort compare (List.map (fun (c, _) -> bare_ctor c) ctors)
            = ["Cons"; "Nil"] ->
       let elt = match List.find_opt (fun (c, _) -> bare_ctor c = "Cons") ctors with
         | Some (_, e :: _) -> sub e | _ -> Tir.TVar "_" in
       Printf.bprintf b
         "  let s = \"[\";\n  for (let first = true; v.$ === \"Cons\"; v = v._1, first = false)\n    s += (first ? \"\" : \", \") + %s;\n  return s + \"]\";\n"
         (show_expr ctx elt "v._0")
     | Tir.TDVariant (_, ctors) ->
       Buffer.add_string b "  switch (v.$) {\n";
       List.iter (fun (c, fts) ->
           let c = bare_ctor c in
           if fts = [] then
             Printf.bprintf b "    case %s: return %s;\n" (js_string_lit c) (js_string_lit c)
           else
             Printf.bprintf b "    case %s: return %s + \"(\" + %s + \")\";\n"
               (js_string_lit c) (js_string_lit c)
               (String.concat " + \", \" + "
                  (List.mapi (fun i t -> show_expr ctx (sub t) (Printf.sprintf "v._%d" i)) fts)))
         ctors;
       Buffer.add_string b "  }\n";
       Printf.bprintf b "  return %s;\n" (show_dyn ctx "v")
     | Tir.TDClosure _ -> Buffer.add_string b "  return \"<fn>\";\n");
    Buffer.add_string b "}\n";
    Buffer.add_buffer ctx.show_buf b;
    f

(** The Error a `panic` / `todo` / `unreachable` throws: its message is the
    bare text (what a test report and an uncaught panic print), and
    march_panic_error records the prefix __try_call puts on the Err, as
    march_panic_user / march_todo_ext do natively. *)
let panic_error ctx name args =
  use_runtime ctx "march_panic_error";
  let msg = match name, args with
    | "unreachable_", _ -> "\"unreachable: reached unreachable code\""
    | _, a :: _ -> let b = Buffer.create 16 in emit_atom { ctx with buf = b } a; Buffer.contents b
    | "todo_", [] -> "\"not yet implemented\""
    | _, [] -> "\"panic\"" in
  let prefix = match name with
    | "todo_" -> "todo: " | "unreachable_" -> "" | _ -> "panic: " in
  Printf.sprintf "march_panic_error(%s, %s)" (js_string_lit prefix) msg

(** Int `/` and `%`, truncating like native sdiv/srem.  A zero divisor
    panics with the interpreter's and native code's operator message
    ("division by zero" / "modulo by zero", march_runtime.c's
    march_checked_div_op / march_checked_mod_op) through march_div_zero /
    march_mod_zero, instead of yielding NaN.  The quotient is
    `(a - a % b) / b`: the remainder is exact, so the division is of an exact
    multiple (see the inline "/" arm).  Operands are atoms, so evaluating them
    more than once is free; the fast path adds one strict compare. *)
let emit_int_div ctx a b =
  use_runtime ctx "march_div_zero";
  emit ctx "("; emit_atom ctx b; emit ctx " === 0 ? march_div_zero() : (";
  emit_atom ctx a; emit ctx " - "; emit_atom ctx a; emit ctx " % ";
  emit_atom ctx b; emit ctx ") / "; emit_atom ctx b; emit ctx ")"

let emit_int_mod ctx a b =
  use_runtime ctx "march_mod_zero";
  emit ctx "("; emit_atom ctx b; emit ctx " === 0 ? march_mod_zero() : ";
  emit_atom ctx a; emit ctx " % "; emit_atom ctx b; emit ctx ")"

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
      PatLit(LitFloat f)  -> "#<hex-float>"      e.g. "#0x1.8p+0" for 1.5
      ECase on bool (if-lowering) -> "True" / "False"   (uppercase) *)
let literal_tag_js br_tag =
  match br_tag with
  | "True"  | "true"  -> "true"
  | "False" | "false" -> "false"
  | _ when br_tag <> "" && br_tag.[0] = '#' ->
    (* Decode the "%h" hex-float tag back to the exact double (same decode as
       llvm_emit.ml's emit_case float-chain), then re-encode with "%.17g" — a
       plain decimal JS number literal.  JS numbers are IEEE-754 doubles too,
       so "%.17g" (which always carries enough significant digits to
       round-trip a double exactly) parses back to the identical bit pattern
       in both OCaml and JS; unlike the hex form, it's also valid JS syntax
       (JS numeric literals don't support C99 hex-float notation). *)
    let hex = String.sub br_tag 1 (String.length br_tag - 1) in
    Printf.sprintf "%.17g" (float_of_string hex)
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

(* Map built-in March runtime lib names to their JS module paths.
   These are shipped alongside march_runtime.mjs and imported automatically. *)
let js_runtime_module_path = function
  | "dom"    -> Some "./march_dom.mjs"
  | "canvas" -> Some "./march_canvas.mjs"
  | "audio"  -> Some "./march_audio.mjs"
  | _        -> None

(** True when the library name is a JS module specifier (not a C lib name).
    JS specifiers start with a scheme, relative path, or scoped npm prefix. *)
let is_js_module lib =
  let has_prefix p = String.length lib >= String.length p
                     && String.sub lib 0 (String.length p) = p in
  has_prefix "./" || has_prefix "../"
  || has_prefix "npm:" || has_prefix "jsr:"
  || has_prefix "node:" || has_prefix "https://" || has_prefix "http://"
  || Option.is_some (js_runtime_module_path lib)

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

(* True when an expression is pure RC bookkeeping (inc/dec-ref, free) with no
   real returned value — a no-op on the JS backend, where RC is free (GC'd).
   Used to detect Perceus's self-tail-call ESeq(call, decrc...) shape (see
   perceus.ml's "EXCEPTION: self-recursive tail calls" comment): when the
   trailing side of an ESeq chain reduces to only this, the expression BEFORE
   it is the chain's actual tail value, not a fire-and-forget statement. *)
let rec is_rc_noop_only = function
  | Tir.EIncRC _ | Tir.EDecRC _ | Tir.EAtomicIncRC _ | Tir.EAtomicDecRC _
  | Tir.EFree _ -> true
  | Tir.ESeq (a, b) -> is_rc_noop_only a && is_rc_noop_only b
  | _ -> false

(** Emit a tagged heap object: `{ $: "Tag", _0: a0, _1: a1, ... }`.

    Shared by EAlloc and by the two rewrites Perceus/escape-analysis produce
    from it — EStackAlloc and EReuse. All three must agree on the closure rule
    below; when only EAlloc had it, a closure that Perceus rewrote to EReuse got
    an apply slot holding a `$clo` wrapper record, and ECallPtr's `f._0(f, x)`
    dispatch called a record ("TypeError: f._0 is not a function").

    Closure objects ($Clo* tag) hold their apply function in _0, which must be
    the RAW function — emit_atom would rewrite a module-level function name to
    its `name$clo` wrapper, which is itself an object, not a callable. Free
    variable slots (_1+) are ordinary atoms. *)
let emit_tagged_alloc ctx ty args =
  let tag = bare_ctor (match ty with Tir.TCon (t, _) -> t | _ -> "_") in
  let is_clo = String.length tag >= 4 && String.sub tag 0 4 = "$Clo" in
  emit ctx (Printf.sprintf "{ $: %S" tag);
  List.iteri (fun i a ->
    emit ctx (Printf.sprintf ", _%d: " i);
    if is_clo && i = 0 then emit_atom_raw ctx a
    else emit_atom ctx a) args;
  emit ctx " }"

(* TRMC hole allocation.  Same tagged object as [emit_tagged_alloc], with the
   hole field written as [null]: JS is garbage-collected, so a hole simply
   holds null until [ESetField] fills it and there is no uninitialized-memory
   hazard to mirror.  [args] carries only the FILLED fields, so the full arity
   is [List.length args + 1] and [hole] indexes the complete field list. *)
let emit_tagged_alloc_hole ctx ty args hole =
  let tag = bare_ctor (match ty with Tir.TCon (t, _) -> t | _ -> "_") in
  let arity = List.length args + 1 in
  emit ctx (Printf.sprintf "{ $: %S" tag);
  let rest = ref args in
  for i = 0 to arity - 1 do
    emit ctx (Printf.sprintf ", _%d: " i);
    if i = hole then emit ctx "null"
    else match !rest with
      | a :: tl -> rest := tl; emit_atom ctx a
      | [] -> emit ctx "null"
  done;
  emit ctx " }"

(* ── User top-level fn shadowing a name-dispatched builtin ─────────── *)

(* True when [name] is a top-level March function of this module, which then
   owns the name: emit_val_impl's builtin arms all dispatch on the callee's
   BARE name, so without this check an entry-module `fn negate` / `fn not` /
   `fn int_xor` compiled its call sites into the JS operator or runtime helper
   and never ran (#1177).  Shadowing a builtin name from the entry module is a
   supported feature (lib/modules/prelude_collision.ml), and builtins have no
   March definition, so fn_names membership is the discriminator, exactly as
   native's [shadows_dispatched_builtin] uses top_fns (llvm_emit.ml).

   [panic] is the one exception: Prelude's own `fn panic(msg) do panic_(msg)
   end` is in tm_fns, and its JS arm (a throw, and a throw STATEMENT in
   emit_assign) is the same behaviour without the indirection.  An entry
   module cannot define `panic` (Prelude's bodies call it bare, so
   Prelude_collision rejects it), so excluding it shadows nothing. *)
let shadows_js_builtin ctx name =
  Hashtbl.mem ctx.fn_names name && name <> "panic"

(* A direct call of a user-defined (or letrec-local / parameter) function. *)
let emit_direct_call ctx name args =
  let is_async_callee = Hashtbl.mem ctx.async_fns name in
  if is_async_callee then emit ctx "(await ";
  emit ctx (mangle name ^ "(");
  List.iteri (fun i a ->
    if i > 0 then emit ctx ", "; emit_atom ctx a) args;
  if is_async_callee then emit ctx "))" else emit ctx ")"

(* ── Forward declarations ────────────────────────────────────────── *)

let rec emit_val  ctx expr = emit_val_impl  ctx expr
and     emit_stmts ctx expr = emit_stmts_impl ctx expr
and     emit_case  ctx rv expr = emit_case_impl ctx rv expr
and     emit_fn_decl ctx fn = emit_fn_decl_impl ctx fn
and     emit_assign ctx rv expr = emit_assign_impl ctx rv expr

(* ── Value emission ──────────────────────────────────────────────── *)

and emit_val_impl ctx expr =
  match expr with
  | Tir.EAtom a -> emit_atom ctx a

  (* A user top-level fn owns its name: ahead of every bare-name builtin arm
     below (see [shadows_js_builtin]). *)
  | Tir.EApp (f, args) when shadows_js_builtin ctx f.Tir.v_name ->
    emit_direct_call ctx f.Tir.v_name args

  | Tir.EApp (f, args) ->
    let name = f.Tir.v_name in
    (* Operands `==`/`!=` compares STRUCTURALLY iff both are primitive (JS `===`
       is correct for Int/Float/Bool/String/Atom); on any non-primitive operand
       (ADT/tuple/record, or an erased TVar) JS `===` is reference equality and
       gives wrong answers (e.g. `x == Some(Ctor)` was always false). Route those
       through march_deep_eq, mirroring native's ensure_adt_eq_fn / march_poly_eq. *)
    let is_prim_eq_ty = function
      | Tir.TBool | Tir.TInt | Tir.TFloat | Tir.TString | Tir.TCon ("Atom", []) -> true
      | _ -> false in
    begin match inline_binop name with
    | Some op when List.length args = 2 ->
      (match op, args with
       | ("===" | "!=="), [a; b]
         when not (is_prim_eq_ty (atom_ty a) && is_prim_eq_ty (atom_ty b)) ->
         use_runtime ctx "march_deep_eq";
         if op = "!==" then emit ctx "(!";
         emit ctx "march_deep_eq(";
         emit_atom ctx a; emit ctx ", "; emit_atom ctx b; emit ctx ")";
         if op = "!==" then emit ctx ")"
       (* Int `/` truncates toward zero. The symbolic "/" reaches this inline
          branch first, so the fallback's typed "/" arm below never ran and
          `n / 2` emitted a plain JS `/` (7 / 2 printed 3.5). Either operand
          being Int decides it: both sides have one type, and a negated
          literal (`-7 / 2`) arrives as a temp whose recorded type may not be
          TInt. `(a - a % b) / b` rather than `Math.trunc(a / b)`: the
          remainder is exact, so the division is of an exact multiple and
          exact everywhere within +-(2^53 - 1), where `a / b` can round up to
          the next integer (march_int_div in march_runtime.mjs does the same).
          Operands are atoms, so evaluating them twice is free.  A zero
          divisor panics "division by zero" like the other backends
          (march_div_zero); the fast path costs one strict compare. *)
       | "/", [a; b]
         when (match atom_ty a, atom_ty b with
               | Tir.TInt, _ | _, Tir.TInt -> true | _ -> false) ->
         emit_int_div ctx a b
       (* Int `%` (the only `%`: Float has none): a zero divisor panics
          "modulo by zero" like native and the interpreter, not NaN. *)
       | "%", [a; b] -> emit_int_mod ctx a b
       (* --js-int-check: an Int + - * whose result leaves the doubles' exact
          range throws, naming the enclosing function (TIR has no expression
          positions). Operands are atoms, so evaluating them twice is free. *)
       | ("+" | "-" | "*"), [a; b]
         when ctx.int_check
              && (match name with
                  | "add_int" | "sub_int" | "mul_int" -> true
                  | "+" | "-" | "*" ->
                    (match atom_ty a, atom_ty b with
                     | Tir.TInt, _ | _, Tir.TInt -> true | _ -> false)
                  | _ -> false) ->
         use_runtime ctx "march_ck_int";
         emit ctx "march_ck_int(("; emit_atom ctx a; emit ctx (" " ^ op ^ " ");
         emit_atom ctx b; emit ctx "), "; emit_atom ctx a;
         emit ctx (", " ^ js_string_lit op ^ ", "); emit_atom ctx b;
         emit ctx (", " ^ js_string_lit ctx.cur_loc ^ ")")
       (* Int `+ - *` panic when the result leaves the 63-bit range, as on
          the other backends (march_int_ovf in march_runtime.mjs).  Only
          when an operand is known to be Int: the symbolic forms are
          Int-or-Float, and a Float result must never be range-checked. *)
       | ("+" | "-" | "*"), [a; b]
         when (match name with
               | "add_int" | "sub_int" | "mul_int" -> true
               | "+" | "-" | "*" ->
                 (match atom_ty a, atom_ty b with
                  | Tir.TInt, _ | _, Tir.TInt -> true | _ -> false)
               | _ -> false) ->
         (* The in-range test is inline (atoms: recomputing the result is a
            single add or multiply that V8 shares); only an overflow calls the
            runtime, which throws. *)
         use_runtime ctx "march_int_ovf";
         let r () = emit ctx "("; emit_atom ctx a; emit ctx (" " ^ op ^ " "); emit_atom ctx b; emit ctx ")" in
         emit ctx "("; r (); emit ctx " < 4611686018427387904 && "; r ();
         emit ctx " >= -4611686018427387904 ? "; r (); emit ctx " : march_int_ovf("; r ();
         emit ctx (match op with "+" -> ", 0))" | "-" -> ", 1))" | _ -> ", 2))")
       | _ ->
         emit ctx "(";
         emit_atom ctx (List.nth args 0);
         emit ctx (" " ^ op ^ " ");
         emit_atom ctx (List.nth args 1);
         emit ctx ")")
    | _ ->
      begin match name, args with
      | ("neg_int" | "negate" | "-"), [a]
        when name = "neg_int" || atom_ty a = Tir.TInt ->
        use_runtime ctx "march_int_ovf";
        emit ctx "march_int_ovf(-("; emit_atom ctx a; emit ctx "), 3)"
      | ("neg_int" | "neg_float" | "negate" | "-" | "-."), [a] -> emit ctx "(-"; emit_atom ctx a; emit ctx ")"
      | ("not_bool" | "not"),  [a] -> emit ctx "(!"; emit_atom ctx a; emit ctx ")"
      | "div_int", [a; b] -> emit_int_div ctx a b
      | "/", [a; b] when (match atom_ty a with Tir.TInt -> true | _ -> false) ->
        emit_int_div ctx a b
      | "/", [a; b] ->
        emit ctx "("; emit_atom ctx a; emit ctx " / "; emit_atom ctx b; emit ctx ")"
      | "mod_int",   [a; b] -> emit_int_mod ctx a b
      | "int_to_float", [a] ->
        emit_atom ctx a
      | "float_to_int", [a] | "float_truncate", [a] ->
        emit ctx "Math.trunc("; emit_atom ctx a; emit ctx ")"
      (* Show$String.show's body (lib/tir/lower.ml) — a dynamic identity that
         classifies the UNIFORM representation at runtime, because Mono defaults
         a dangling type variable to String and an erased value may really be a
         tagged Int or a boxed Float.  JS has no uniform representation and no
         erasure: values arrive as their own JS types, so the identity that this
         body replaced is still exactly right here.  Emitting it keeps the JS
         backend byte-for-byte unchanged instead of calling an undefined symbol. *)
      | "march_value_to_string", [a] ->
        emit_atom ctx a
      (* `to_string` on a value with no `Show` impl (see [show_expr]).  A
         top-level String is the identity, as natively. *)
      | "to_string", [a] ->
        (match atom_ty a with
         | Tir.TString | Tir.TCon ("String", []) -> emit_atom ctx a
         | ty ->
           let b = Buffer.create 16 in
           emit_atom { ctx with buf = b } a;
           let v = Buffer.contents b in
           (match ty with
            | Tir.TVar _ | Tir.TPtr _ ->
              use_runtime ctx "march_to_string_dyn";
              emit ctx (Printf.sprintf "march_to_string_dyn(%s)" v)
            (* The atom may be a zero-arg fn's call (a module-level `let`):
               bind it once, as [show_expr] reads it per field. *)
            | _ -> emit ctx (Printf.sprintf "((v) => %s)(%s)" (show_expr ctx ty "v") v)))
      (* `compare` on Int / String (Ord$Int.compare, Ord$String.compare and
         the compare_* builtins; a derived `Ord` on a record or payload type
         calls these per field): -1/0/1 like march_compare_int /
         march_compare_string in march_runtime.c.  A String orders by JS `<`,
         the same order the JS backend's String `<` already uses.  Operands
         are atoms, so evaluating them twice is free. *)
      | ("march_compare_int" | "compare_int"
        | "march_compare_string" | "compare_string"), [a; b] ->
        emit ctx "(("; emit_atom ctx a; emit ctx " < "; emit_atom ctx b;
        emit ctx ") ? -1 : ("; emit_atom ctx a; emit ctx " > "; emit_atom ctx b;
        emit ctx ") ? 1 : 0)"
      (* `compare` on Float: NaN-total, as march_compare_float in
         march_runtime.c and the interpreter's Float.compare. *)
      | ("march_compare_float" | "compare_float"), [a; b] ->
        use_runtime ctx "march_compare_float";
        emit ctx "march_compare_float("; emit_atom ctx a; emit ctx ", ";
        emit_atom ctx b; emit ctx ")"
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
      | ("println" | "print_line"), [a] ->
        use_runtime ctx "march_println";
        emit ctx "march_println("; emit_atom ctx a; emit ctx ")"
      | "print", [a] ->
        use_runtime ctx "march_print";
        emit ctx "march_print("; emit_atom ctx a; emit ctx ")"
      | "string_to_codepoints", [a] ->
        use_runtime ctx "march_string_to_codepoints";
        emit ctx "march_string_to_codepoints("; emit_atom ctx a; emit ctx ")"
      | "string_from_codepoint", [a] ->
        use_runtime ctx "march_string_from_codepoint";
        emit ctx "march_string_from_codepoint("; emit_atom ctx a; emit ctx ")"
      | "print_stderr", [a] ->
        emit ctx "console.error("; emit_atom ctx a; emit ctx ")"
      (* The Diagnostics panic-site record: nothing to record in JS. *)
      | "__panic_site", _ -> emit ctx "undefined"
      (* --test (issue #1176): the running test's panic header, and a failed
         assert, which throws the whole rendered report (header and value
         diff), as the native march_test_header / march_assert_fail do. *)
      | "__test_header", [h] ->
        use_runtime ctx "march_test_header";
        emit ctx "march_test_header("; emit_atom ctx h; emit ctx ")"
      | "__assert_fail", [meta; l; r] ->
        use_runtime ctx "march_assert_fail";
        emit ctx "march_assert_fail("; emit_atom ctx meta; emit ctx ", ";
        emit_atom ctx l; emit ctx ", "; emit_atom ctx r; emit ctx ")"
      (* Capability dictionaries (--test turns capability mocking on).  A
         capability is undefined or its dictionary, as native's is NULL or
         the dictionary (march_cap_impl / march_cap_dict); [cap_dict] reads
         it back as an Option.  [root_cap] is the undefined sentinel (a const
         in [builtin_wrappers]); a minted capability carries no dictionary. *)
      | "cap_impl", [_; d] -> emit_atom ctx d
      | "cap_narrow", [c] -> emit_atom ctx c
      | "mint_cap", [_] -> emit ctx "undefined"
      | "cap_dict", [c] ->
        emit ctx "(("; emit_atom ctx c; emit ctx " == null) ? { $: \"None\" } : { $: \"Some\", _0: ";
        emit_atom ctx c; emit ctx " })"
      | ("panic" | "panic_" | "todo_" | "unreachable_"), _ ->
        emit ctx (Printf.sprintf "(() => { throw %s; })()" (panic_error ctx name args))
      (* Check.try_prop's panic-catching call (and Depot's): run the
         `fn _ -> body` thunk, a panic becoming Err(message) with the prefix
         the interpreter and native put on it ("panic: boom"). *)
      | ("__try_call" | "__try_call_val"), [t] ->
        use_runtime ctx "march_try_call";
        emit ctx "march_try_call("; emit_atom ctx t; emit ctx ")"
      | "process_env", [a] ->
        use_runtime ctx "march_process_env";
        emit ctx "march_process_env("; emit_atom ctx a; emit ctx ")"
      | "process_cwd", _ ->
        use_runtime ctx "march_process_cwd";
        emit ctx "march_process_cwd()"
      | "process_pid", _ ->
        use_runtime ctx "march_process_pid";
        emit ctx "march_process_pid()"
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
      (* Bitwise ops on values that fit in int32 (pixels, flags, masks — the
         common case) inline to JS's own operators, which agree with the
         63-bit semantics there; anything wider falls back to the exact,
         checked runtime helper. Operands are atoms, so repeating them is free. *)
      | ("int_and" | "int_or" | "int_xor" as n), [a; b] ->
        let rt = "march_" ^ n in
        let op = match n with "int_and" -> "&" | "int_or" -> "|" | _ -> "^" in
        use_runtime ctx rt;
        emit ctx "(("; emit_atom ctx a; emit ctx " | 0) === "; emit_atom ctx a;
        emit ctx " && ("; emit_atom ctx b; emit ctx " | 0) === "; emit_atom ctx b;
        emit ctx " ? ("; emit_atom ctx a; emit ctx (" " ^ op ^ " "); emit_atom ctx b;
        emit ctx (") : " ^ rt ^ "("); emit_atom ctx a; emit ctx ", "; emit_atom ctx b; emit ctx "))"
      | "int_shr", [a; b] ->
        use_runtime ctx "march_int_shr";
        emit ctx "(("; emit_atom ctx a; emit ctx " | 0) === "; emit_atom ctx a;
        emit ctx " && "; emit_atom ctx b; emit ctx " >= 0 && "; emit_atom ctx b;
        emit ctx " < 32 ? ("; emit_atom ctx a; emit ctx " >> "; emit_atom ctx b;
        emit ctx ") : march_int_shr("; emit_atom ctx a; emit ctx ", "; emit_atom ctx b; emit ctx "))"
      | n, _ when (match n with
          | "string_to_int" | "string_to_float" | "string_to_lowercase"
          | "string_to_uppercase" | "string_trim" | "string_trim_start"
          | "string_trim_end" | "string_reverse" | "string_chars"
          | "string_from_chars" | "string_join" | "string_concat3"
          | "string_concat_n" | "string_contains"
          | "string_starts_with" | "string_ends_with" | "string_slice"
          | "string_split" | "string_split_first" | "string_replace"
          | "string_replace_all" | "string_repeat" | "string_pad_left"
          | "string_pad_right" | "string_index_of" | "string_index_of_from"
          | "string_byte_at"
          | "string_last_index_of"
          | "char_from_int" | "byte_to_char" | "char_to_int"
          | "char_is_digit" | "char_is_alphanumeric" | "char_is_whitespace"
          | "list_append" | "list_concat"
          | "native_i32_arr_make" | "native_i32_arr_length"
          | "native_i32_arr_get" | "native_i32_arr_set"
          | "native_u8_arr_make" | "native_u8_arr_length"
          | "native_u8_arr_get" | "native_u8_arr_set"
          | "native_int_arr_make" | "native_int_arr_length"
          | "native_int_arr_get" | "native_int_arr_set"
          | "u8_arr_to_bytes"
          | "process_argv"
          | "list_stable_sort_by" | "list_sort_by_int_key"
          (* Int builtins with 63-bit semantics — checked implementations in
             march_runtime.mjs (exact within ±2^53, throw beyond) *)
          | "int_and" | "int_or" | "int_xor" | "int_not"
          | "int_shl" | "int_shr" | "int_popcount"
          | "int_mod" | "int_div" | "int_mod_euclid" | "int_div_euclid"
          | "int_mod_floor" | "int_div_floor"
          | "int_wrapping_add" | "int_wrapping_sub" | "int_wrapping_mul"
            -> true | _ -> false) ->
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
      | "int_abs", [a] -> emit ctx "Math.abs("; emit_atom ctx a; emit ctx ")"
      (* int_pow: exponentiation by squaring in the runtime (negative exponent
         -> 0, mirroring the native backend, not JS's fractional Math.pow).
         From origin/main. *)
      | "int_pow", [a; b] ->
        use_runtime ctx "march_int_pow";
        emit ctx "march_int_pow("; emit_atom ctx a; emit ctx ", "; emit_atom ctx b; emit ctx ")"
      | "float_abs",   [a] -> emit ctx "Math.abs(";   emit_atom ctx a; emit ctx ")"
      (* float_floor/ceil/round return Int in March; the results are
         integer-valued JS numbers, which IS the JS target's Int repr *)
      | "float_floor", [a] -> emit ctx "Math.floor("; emit_atom ctx a; emit ctx ")"
      | "float_ceil",  [a] -> emit ctx "Math.ceil(";  emit_atom ctx a; emit ctx ")"
      | "float_round", [a] ->
        (* OCaml Float.round rounds half AWAY FROM ZERO; JS Math.round rounds
           half toward +inf — delegate to the runtime helper *)
        use_runtime ctx "march_float_round";
        emit ctx "march_float_round("; emit_atom ctx a; emit ctx ")"
      (* float_from_string is string_to_float under a second name (one C
         symbol natively); the float constants and predicates are plain JS
         numbers. Unmapped before #1178, so they failed the JS compile. *)
      | "float_from_string", [a] ->
        use_runtime ctx "march_string_to_float";
        emit ctx "march_string_to_float("; emit_atom ctx a; emit ctx ")"
      | "float_infinity", _ -> emit ctx "Infinity"
      | "float_neg_infinity", _ -> emit ctx "(-Infinity)"
      | "float_nan", _ -> emit ctx "NaN"
      | "float_epsilon", _ -> emit ctx "Number.EPSILON"
      | "float_is_nan", [a] -> emit ctx "Number.isNaN("; emit_atom ctx a; emit ctx ")"
      | "float_is_infinite", [a] ->
        emit ctx "(Math.abs("; emit_atom ctx a; emit ctx ") === Infinity)"
      (* unix_time takes a Unit argument in March; the JS runtime fn takes none *)
      | "unix_time", _ ->
        use_runtime ctx "march_unix_time";
        emit ctx "march_unix_time()"
      | "unix_time_ms", _ ->
        use_runtime ctx "march_unix_time_ms";
        emit ctx "march_unix_time_ms()"
      (* General call — route externs through emit_extern_call seam *)
      | _, _ ->
        (match Hashtbl.find_opt ctx.extern_fns name with
         | Some ed -> emit_extern_call ctx ed args
         | None ->
           (* A direct call that is not a user fn, letrec-local fn, or
              parameter can only be an unmapped builtin — the bare emit below
              would be a guaranteed ReferenceError at runtime, so record it
              and let emit_module fail the compile instead. *)
           if not (Hashtbl.mem ctx.fn_names name)
              && not (Hashtbl.mem ctx.local_fns name)
              && not (Hashtbl.mem ctx.param_names name)
           then (if not (Hashtbl.mem ctx.unmapped name) then Hashtbl.replace ctx.unmapped name ctx.cur_loc);
           emit_direct_call ctx name args)
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
    if Tir_names.is_fv_field field then
      emit ctx ("_" ^ String.sub field 3 (String.length field - 3))
    else
      emit ctx field

  | Tir.EUpdate (a, updates) ->
    emit ctx "({ ..."; emit_atom ctx a;
    List.iter (fun (name, v) ->
      emit ctx (", " ^ name ^ ": "); emit_atom ctx v) updates;
    emit ctx " })"

  | Tir.EAlloc (ty, args) -> emit_tagged_alloc ctx ty args

  (* Escape analysis rewrites a non-escaping EAlloc to EStackAlloc; on JS there
     is no stack allocation, so it is the same tagged object. *)
  | Tir.EStackAlloc (ty, args) -> emit_tagged_alloc ctx ty args

  (* EReuse(old, ty, args): Perceus reuses old's memory — in GC'd JS just alloc fresh *)
  | Tir.EReuse (_, ty, args) -> emit_tagged_alloc ctx ty args

  | Tir.EAllocHole (_, ty, args, hole) -> emit_tagged_alloc_hole ctx ty args hole

  (* TRMC hole fill: an in-place property write, sequenced with [undefined] so
     the expression's value is unit rather than the assigned value. *)
  | Tir.ESetField (o, i, v) ->
    emit ctx "("; emit_atom ctx o;
    emit ctx (Printf.sprintf "._%d = " i);
    emit_atom ctx v; emit ctx ", undefined)"

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
    let saved_tco = ctx.tco in
    ctx.tco <- None;
    emit_stmts ctx expr;
    ctx.tco <- saved_tco;
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

  | Tir.EApp (f, args) when tco_member ctx f.Tir.v_name args <> None ->
    emit_tail_jump ctx f.Tir.v_name args

  | Tir.ELet (tmp, Tir.EApp (f, args), body)
    when tco_member ctx f.Tir.v_name args <> None
         && Llvm_tco.is_trivial_dec_chain_returning tmp.Tir.v_name body ->
    (* Perceus's post-call DecRC wrapper around a tail call: the DecRCs are
       no-ops in JS, so the call is the tail. *)
    emit_tail_jump ctx f.Tir.v_name args

  | Tir.ELet (v, e1, rest) when is_compound e1 && (match e1 with Tir.ECase _ -> false | _ -> true) ->
    (* A let whose value is itself a let/seq: compute it as statements into
       the binding, not through a closure (see [emit_assign]). *)
    let name = v.Tir.v_name in
    let js = fresh_local_name ctx name in
    emit_indent ctx; emit ctx "{\n";
    ctx.indent <- ctx.indent + 1;
    emitl ctx ("let " ^ js ^ ";");
    with_reserved ctx js (fun () -> emit_assign ctx js e1);
    let prev = install_local ctx name js in
    emit_stmts ctx rest;
    unbind_local ctx name prev;
    ctx.indent <- ctx.indent - 1;
    emit_indent ctx; emit ctx "}\n"

  | Tir.ELet (v, (Tir.ECase _ as case_expr), rest) ->
    (* let v = match ... — emit switch that assigns to v.
       Wrap in a block so this binding can shadow an outer variable of the same
       name; [js] is a fresh id when v shadows, so the case (which sees the
       OUTER v) and [rest] (which sees the new v) never collide. *)
    let name = v.Tir.v_name in
    let js = fresh_local_name ctx name in
    emit_indent ctx; emit ctx "{\n";
    ctx.indent <- ctx.indent + 1;
    emitl ctx ("let " ^ js ^ ";");
    with_reserved ctx js (fun () -> emit_case ctx (Some js) case_expr);
    let prev = install_local ctx name js in
    emit_stmts ctx rest;
    unbind_local ctx name prev;
    ctx.indent <- ctx.indent - 1;
    emit_indent ctx; emit ctx "}\n"

  | Tir.ELet (v, e1, e2) ->
    (* Wrap in a block so this binding can shadow a parameter or outer let of
       the same name. The RHS [e1] is emitted BEFORE [install_local], so a
       self-referential rebinding (`let x = x + 1`) resolves its `x` to the
       OUTER binding; [js] is a fresh id when shadowing, so the inner const
       never shadows that read in its temporal dead zone. *)
    let name = v.Tir.v_name in
    let js = fresh_local_name ctx name in
    emit_indent ctx; emit ctx "{\n";
    ctx.indent <- ctx.indent + 1;
    emit_indent ctx;
    emit ctx ("const " ^ js ^ " = ");
    emit_val ctx e1;
    emit ctx ";\n";
    let prev = install_local ctx name js in
    emit_stmts ctx e2;
    unbind_local ctx name prev;
    ctx.indent <- ctx.indent - 1;
    emit_indent ctx; emit ctx "}\n"

  | Tir.ELetRec (fns, body) ->
    (* Register names first: mutually-recursive locals may call each other
       (and themselves) before their own decl is emitted. *)
    List.iter (fun (fn : Tir.fn_def) ->
      Hashtbl.replace ctx.local_fns fn.Tir.fn_name ()) fns;
    List.iter (emit_fn_decl ctx) fns;
    emit_stmts ctx body

  | Tir.ESeq (e1, e2) when is_rc_noop_only e2 && not (is_rc_noop_only e1) ->
    (* Perceus keeps a self-tail-call in the ESeq(call, post_dec_vars...)
       shape specifically so llvm_emit.ml's has_self_tail_call can recognize
       and TCO-rewrite it (see perceus.ml's "EXCEPTION: self-recursive tail
       calls" comment) — the trailing EDecRC's are meant to become dead code
       once TCO emits the loop back-edge. The JS backend has no such TCO
       rewrite, so without this case the generic ESeq handling below would
       emit e1 (the call) as a bare statement — discarding its return value —
       then emit_stmts on e2 (all RC no-ops in JS) would produce nothing,
       leaving the function to fall off the end and implicitly return
       undefined. Since e2 is pure RC bookkeeping (free in JS), e1 IS this
       chain's real tail value; recurse via emit_stmts so it gets proper
       return/switch-tail treatment instead of being flattened away. *)
    emit_stmts ctx e1

  | Tir.ESeq (e1, e2) ->
    emit_effect ctx e1;
    emit_stmts ctx e2

  | Tir.ECase _ ->
    emit_case ctx None expr

  (* RC side-effects in terminal position — no side effects needed in JS *)
  | Tir.EIncRC _ | Tir.EDecRC _ | Tir.EAtomicIncRC _ | Tir.EAtomicDecRC _
  | Tir.EFree _ -> ()

  (* EReuse in terminal position: Perceus reuses old's slot — in JS emit a fresh
     object. Shares emit_tagged_alloc with the value-position forms so the
     closure apply-slot rule cannot diverge here either. No fixture currently
     reaches this arm with a $Clo tag, so this is guarding the shape rather than
     fixing an observed miscompile — but a divergent copy of this emission is
     exactly what produced the EReuse apply-slot bug. *)
  | Tir.EReuse (_, ty, args) ->
    emit_indent ctx;
    emit ctx "return ";
    emit_tagged_alloc ctx ty args;
    emit ctx ";\n"

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
      | Some v -> emit_assign ctx v body
      | None -> emit_stmts ctx body
    in
    (* Tuples can appear as TTuple or as TCon("$TupleN", ...) or detected
       by the branch tag starting with "$Tuple". Use branch tags as the
       authoritative signal since type info may be erased after Mono. *)
    let is_tuple_case =
      match s_ty with Tir.TTuple _ -> true | _ -> false
      || (match branches with
          | br :: _ -> Tir_names.is_tuple_tag br.Tir.br_tag
          | [] -> false) in
    if is_tuple_case then begin
      (* Tuple: exactly one branch, directly destructure _0, _1, ... *)
      List.iter (fun br ->
        let scrut_name = match scrutinee with
          | Tir.AVar sv -> js_local ctx sv.Tir.v_name
          | _ ->
            let tmp = "_tup" in
            emit_indent ctx;
            emit ctx (Printf.sprintf "const %s = " tmp);
            emit_atom ctx scrutinee;
            emit ctx ";\n";
            tmp
        in
        let binds = bind_br_vars ctx scrut_name br.Tir.br_vars in
        (match result_var with
         | Some rv -> emit_assign ctx rv br.Tir.br_body
         | None -> emit_stmts ctx br.Tir.br_body);
        unbind_br_vars ctx binds
      ) branches;
      (* A tuple's one branch always matches (it only destructures), so the
         default — the compiler's non-exhaustive throw — is reachable only
         when there is no branch.  Emitted after a branch in assignment mode
         it overwrote the branch's result with the throw. *)
      (match default, branches with
       | Some d, [] ->
         (match result_var with
          | Some rv -> emit_assign ctx rv d
          | None -> emit_stmts ctx d)
       | _ -> ())
    end else
    (* Also take the literal if/else path when the scrutinee's static type is
       ERASED (a TVar-typed tuple-field / ctor-payload binder — e.g. the `n` in a
       desugared multi-head fn `match (cells, n) do (cells, 0) -> … | (cells, n)
       -> …`) but every branch tag is an immediate literal (Int/Bool/Atom).
       Otherwise we emit `switch (n.$) { case "0": … }` on a raw number, whose
       `.$` is `undefined`, so the base case is dead and the fn infinite-loops
       (and a String field matched against literals never matched at all).
       Mirrors the native backend's all_imm_lit_tags (llvm_case.ml). *)
    let all_imm_lit_tags =
      branches <> [] &&
      List.for_all (fun br ->
        let t = br.Tir.br_tag in
        t = "true" || t = "false" || int_of_string_opt t <> None
        (* atom, string (`"s"`, e.g. a tuple field matched against string
           literals) and float (`#hex`) tags: never a constructor's *)
        || (String.length t > 0 && (t.[0] = ':' || t.[0] = '"' || t.[0] = '#'))) branches
    in
    if is_literal_scrutinee_ty s_ty || all_imm_lit_tags then begin
      (* Literal/bool: if/else chain *)
      List.iteri (fun i br ->
        if i = 0 then (emit_indent ctx; emit ctx "if (")
        else (emit_indent ctx; emit ctx "} else if (");
        emit_atom ctx scrutinee;
        emit ctx (" === " ^ literal_tag_js br.Tir.br_tag ^ ") {\n");
        with_indent ctx (fun () ->
          (* bind branch vars (rare for literal patterns, but possible) *)
          let scrut_name = match scrutinee with
            | Tir.AVar sv -> js_local ctx sv.Tir.v_name | _ -> "_s" in
          let binds = bind_br_vars ctx scrut_name br.Tir.br_vars in
          emit_result br.Tir.br_body;
          unbind_br_vars ctx binds)
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
              | Tir.AVar sv -> js_local ctx sv.Tir.v_name
              | _ ->
                let tmp = "_scrut" in
                emit_indent ctx;
                emit ctx (Printf.sprintf "const %s = " tmp);
                emit_atom ctx scrutinee;
                emit ctx ";\n";
                tmp
            in
            let binds = bind_br_vars ctx scrut_name br.Tir.br_vars in
            (match result_var with
             | Some rv ->
               emit_assign ctx rv br.Tir.br_body;
               emitl ctx "break;"
             | None ->
               (* Statement position: emit_stmts does not always end in a
                  `return` (e.g. a trailing Unit-typed call emits as a bare
                  statement), and a JS case arm without break/return FALLS
                  THROUGH into the next case or the non-exhaustive-match
                  default throw. The break is unreachable (harmless) when the
                  body did return. (from origin/main) *)
               emit_stmts ctx br.Tir.br_body;
               emitl ctx "break;");
            unbind_br_vars ctx binds
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
               emit_assign ctx rv d;
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

(* ── Assignment mode ──────────────────────────────────────────────

   [emit_assign ctx rv e] emits statements that compute [e] and assign it to
   the (already declared) JS variable [rv].  A compound expression in value
   position (a let bound to a match, a let chain, an arm that binds) used to
   become an immediately invoked closure, one per expression, which was ~40%
   of a Herald frame; this keeps it in the enclosing function.  It never emits
   a tail-call jump: nothing it emits is in tail position. *)
and emit_assign_impl ctx rv expr =
  match expr with
  | Tir.ELet (v, e1, e2) ->
    let name = v.Tir.v_name in
    let js = fresh_local_name ctx name in
    emit_indent ctx; emit ctx "{\n";
    ctx.indent <- ctx.indent + 1;
    if is_compound e1 then begin
      emitl ctx ("let " ^ js ^ ";");
      with_reserved ctx js (fun () -> emit_assign ctx js e1)
    end else begin
      emit_indent ctx;
      emit ctx ("const " ^ js ^ " = ");
      emit_val ctx e1;
      emit ctx ";\n"
    end;
    let prev = install_local ctx name js in
    emit_assign ctx rv e2;
    unbind_local ctx name prev;
    ctx.indent <- ctx.indent - 1;
    emit_indent ctx; emit ctx "}\n"
  | Tir.ELetRec (fns, body) ->
    List.iter (fun (fn : Tir.fn_def) ->
      Hashtbl.replace ctx.local_fns fn.Tir.fn_name ()) fns;
    List.iter (emit_fn_decl ctx) fns;
    emit_assign ctx rv body
  | Tir.ESeq (e1, e2) when is_rc_noop_only e2 && not (is_rc_noop_only e1) ->
    (* Perceus's self-call + post-DecRC shape: e1 is the value *)
    emit_assign ctx rv e1
  | Tir.ESeq (e1, e2) ->
    emit_effect ctx e1;
    emit_assign ctx rv e2
  | Tir.ECase _ -> emit_case ctx (Some rv) expr
  | Tir.EApp (f, args)
    when (match f.Tir.v_name with
          | "panic" | "panic_" | "todo_" | "unreachable_" -> true | _ -> false) ->
    (* a panic needs no value: a throw statement, not a throwing closure *)
    emit_indent ctx;
    emit ctx ("throw " ^ panic_error ctx f.Tir.v_name args ^ ";\n")
  | e ->
    emit_indent ctx;
    emit ctx (rv ^ " = ");
    emit_val ctx e;
    emit ctx ";\n"

(* An expression evaluated only for its effect: RC ops vanish; a compound one
   is computed into a throwaway variable rather than a closure. *)
and emit_effect ctx e =
  match e with
  | Tir.EIncRC _ | Tir.EDecRC _ | Tir.EAtomicIncRC _ | Tir.EAtomicDecRC _
  | Tir.EFree _ | Tir.EReuse _ -> ()
  | e when is_compound e ->
    let tmp = fresh_local_name ctx "$eff" in
    emit_indent ctx; emit ctx "{\n";
    ctx.indent <- ctx.indent + 1;
    emitl ctx ("let " ^ tmp ^ ";");
    with_reserved ctx tmp (fun () -> emit_assign ctx tmp e);
    ctx.indent <- ctx.indent - 1;
    emit_indent ctx; emit ctx "}\n"
  | e ->
    emit_indent ctx;
    emit_val ctx e;
    emit ctx ";\n"

and is_compound = function
  | Tir.ECase _ | Tir.ELet _ | Tir.ELetRec _ | Tir.ESeq _ -> true
  | _ -> false

and emit_fn_decl_impl ctx (fn : Tir.fn_def) =
  let self_loop = Llvm_tco.has_self_tail_call fn.Tir.fn_name fn.Tir.fn_body in
  let params = fn.Tir.fn_params in
  let slot i = Printf.sprintf "$tco_a%d" i in
  emit_fn_header ctx fn
    (if self_loop then List.mapi (fun i _ -> slot i) params
     else List.map (fun p -> mangle p.Tir.v_name) params);
  let saved_tco = ctx.tco in
  if self_loop then begin
    ctx.tco <- Some { tco_members = [ (fn.Tir.fn_name, 0, params) ];
                      tco_mutual = false };
    with_indent ctx (fun () ->
      emitl ctx "__tco: for (;;) {";
      with_indent ctx (fun () ->
        emit_fn_body ctx params ~slots:true fn.Tir.fn_body;
        emitl ctx "return undefined;");
      emitl ctx "}")
  end else begin
    ctx.tco <- None;
    with_indent ctx (fun () -> emit_fn_body ctx params ~slots:false fn.Tir.fn_body)
  end;
  ctx.tco <- saved_tco;
  emit_indent ctx;
  emit ctx "}\n";
  emit_clo_wrapper ctx fn

(* `[async] function NAME(P0, P1, ...) {` with a source-map segment. *)
and emit_fn_header ctx (fn : Tir.fn_def) (param_js : string list) =
  let fname = mangle fn.Tir.fn_name in
  let is_async = Hashtbl.mem ctx.async_fns fn.Tir.fn_name in
  set_loc ctx fn;
  (match Hashtbl.find_opt ctx.fn_lines fn.Tir.fn_name with
   | Some src_line when src_line > 0 ->
     ctx.segments := (ctx.line, src_line - 1) :: !(ctx.segments)
   | _ -> ());
  emit_indent ctx;
  if is_async then emit ctx "async ";
  emit ctx ("function " ^ fname ^ "(" ^ String.concat ", " param_js ^ ") {\n")

and set_loc ctx (fn : Tir.fn_def) =
  ctx.cur_loc <-
    (match Hashtbl.find_opt ctx.fn_lines fn.Tir.fn_name with
     | Some l when l > 0 ->
       Printf.sprintf "%s (%s:%d)" fn.Tir.fn_name (Filename.basename ctx.src_file) l
     | _ -> fn.Tir.fn_name)

(* A function body in its own name scope.  With [slots], the params arrive in
   $tco_aN and are bound to fresh consts first, so each loop iteration (and any
   closure it builds) sees its own values. *)
and emit_fn_body ctx (params : Tir.var list) ~slots body =
  (* Register params so emit_atom won't add $clo suffix to param variables
     that happen to share a name with a module-level function. *)
  Hashtbl.clear ctx.param_names;
  List.iter (fun p -> Hashtbl.replace ctx.param_names p.Tir.v_name ()) params;
  (* Seed the shadow-rename scope with the params (identity mapping) and, for
     a nested (ELetRec) fn, SAVE the enclosing fn's local scope so it can be
     restored — a nested fn's body reaches outer values via $fv closure fields,
     never by their source names, so it only needs its own params in scope. *)
  let saved_names = Hashtbl.copy ctx.name_env in
  Hashtbl.clear ctx.name_env;
  List.iteri (fun i p ->
    Hashtbl.replace ctx.name_env p.Tir.v_name (mangle p.Tir.v_name);
    if slots then
      emitl ctx (Printf.sprintf "const %s = $tco_a%d;" (mangle p.Tir.v_name) i))
    params;
  emit_stmts ctx body;
  Hashtbl.clear ctx.name_env;
  Hashtbl.iter (fun k v -> Hashtbl.replace ctx.name_env k v) saved_names;
  Hashtbl.clear ctx.param_names

(* Closure-protocol wrapper: allows this function to be used as a first-class
   value via ECallPtr dispatch (f._0(f, args)).
   $_ is the closure self-pointer (unused since top-level fns have no free vars).
   Async fns get an async arrow so the $clo call also propagates the Promise. *)
and emit_clo_wrapper ctx (fn : Tir.fn_def) =
  let fname = mangle fn.Tir.fn_name in
  let ps = List.map (fun p -> mangle p.Tir.v_name) fn.Tir.fn_params in
  emit_indent ctx;
  if Hashtbl.mem ctx.async_fns fn.Tir.fn_name then
    emit ctx ("const " ^ fname ^ "$clo = { _0: async ($_")
  else
    emit ctx ("const " ^ fname ^ "$clo = { _0: ($_");
  List.iter (fun p -> emit ctx (", " ^ p)) ps;
  emit ctx (") => " ^ fname ^ "(" ^ String.concat ", " ps ^ ") };\n\n")

(* The loop member a call to [name] with [args] jumps to, if any. *)
and tco_member ctx name args =
  match ctx.tco with
  | None -> None
  | Some t ->
    List.find_opt (fun (n, _, ps) ->
      String.equal n name && List.length ps = List.length args) t.tco_members

(* A tail call to a loop member: rebind the parameter slots and loop.  Args are
   atoms naming consts (never the slots), so assigning in order is safe. *)
and emit_tail_jump ctx name args =
  match ctx.tco, tco_member ctx name args with
  | Some t, Some (_, tag, _) ->
    emitl ctx "{";
    with_indent ctx (fun () ->
      if t.tco_mutual then emitl ctx (Printf.sprintf "$tco_tag = %d;" tag);
      List.iteri (fun i a ->
        emit_indent ctx;
        emit ctx (Printf.sprintf "$tco_a%d = " i);
        emit_atom ctx a;
        emit ctx ";\n") args;
      emitl ctx "continue __tco;");
    emitl ctx "}"
  | _ -> failwith "emit_tail_jump: not a loop member"

(* A mutual-TCO group: one dispatcher looping over a switch on $tco_tag (one
   case per member, its body emitted with tail calls to any member as jumps),
   plus a wrapper per member that enters the dispatcher at its tag. *)
and emit_mutual_group ctx (group : Tir.fn_def list) =
  let disp = "$mutco_" ^ mangle (List.hd group).Tir.fn_name in
  let is_async = List.exists (fun fn -> Hashtbl.mem ctx.async_fns fn.Tir.fn_name) group in
  let width = List.fold_left (fun m fn -> max m (List.length fn.Tir.fn_params)) 0 group in
  let slots = List.init width (fun i -> Printf.sprintf "$tco_a%d" i) in
  emit_indent ctx;
  if is_async then emit ctx "async ";
  emit ctx ("function " ^ disp ^ "(" ^ String.concat ", " ("$tco_tag" :: slots) ^ ") {\n");
  let saved_tco = ctx.tco in
  ctx.tco <- Some {
    tco_members = List.mapi (fun i fn -> (fn.Tir.fn_name, i, fn.Tir.fn_params)) group;
    tco_mutual = true };
  with_indent ctx (fun () ->
    emitl ctx "__tco: for (;;) {";
    with_indent ctx (fun () ->
      emitl ctx "switch ($tco_tag) {";
      List.iteri (fun i fn ->
        emitl ctx (Printf.sprintf "case %d: {" i);
        set_loc ctx fn;
        with_indent ctx (fun () ->
          emit_fn_body ctx fn.Tir.fn_params ~slots:true fn.Tir.fn_body;
          emitl ctx "return undefined;");
        emitl ctx "}") group;
      emitl ctx "}";
      emitl ctx "throw new Error(\"mutual-TCO dispatch: bad tag\");");
    emitl ctx "}");
  ctx.tco <- saved_tco;
  emitl ctx "}";
  List.iteri (fun i fn ->
    let ps = List.map (fun p -> mangle p.Tir.v_name) fn.Tir.fn_params in
    let pad = List.init (width - List.length ps) (fun _ -> "undefined") in
    emit_fn_header ctx fn ps;
    with_indent ctx (fun () ->
      emitl ctx ("return " ^ disp ^ "(" ^
                 String.concat ", " (string_of_int i :: ps @ pad) ^ ");"));
    emitl ctx "}";
    emit_clo_wrapper ctx fn) group

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
      let import_path = match js_runtime_module_path lib with
        | Some p -> p
        | None   -> lib
      in
      let specs = List.map (fun (march_name, js_sym) ->
        if march_name = js_sym then js_sym
        else js_sym ^ " as " ^ mangle march_name
      ) !pairs in
      imp (Printf.sprintf "import { %s } from %s;\n"
             (String.concat ", " specs) (js_string_lit import_path))
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
const negate_int      = { _0: ($_, x) => march_int_ovf(-x, 3) };
const negate_float    = { _0: ($_, x) => -x };
const float_abs       = { _0: ($_, x) => Math.abs(x) };
const float_floor     = { _0: ($_, x) => Math.floor(x) };
const float_ceil      = { _0: ($_, x) => Math.ceil(x) };
const root_cap        = undefined;
|}

(** Raised by [emit_module] when used C-backed externs are compiled with [--target js].
    Each string in the list is a formatted diagnostic for one offending extern. *)
exception Js_emit_error of string list

(** Emit a TIR module as an ES module string.
    Returns [(js_content, source_map_json option)].
    [fn_lines] maps TIR function names to 1-indexed source lines (from the AST).
    [source_file] is the path to the originating .march file (for source maps).
    Raises [Js_emit_error] when used C-backed externs are present (Chunk C). *)
let emit_module ?(source_file="") ?(fn_lines=[]) ?(int_check=false) (m : Tir.tir_module) : string * string option =
  let ctx = create_ctx ~fn_lines () in
  ctx.int_check <- int_check;
  List.iter (fun td -> match td with
      | Tir.TDVariant (n, _) | Tir.TDRecord (n, _) -> Hashtbl.replace ctx.type_defs n td
      | Tir.TDClosure _ -> ()) m.Tir.tm_types;
  ctx.src_file <- source_file;
  (* Pre-register all user-defined function names so emit_atom emits $clo versions *)
  List.iter (fun fn ->
    Hashtbl.replace ctx.fn_names fn.Tir.fn_name ();
    if fn.Tir.fn_params = [] then Hashtbl.replace ctx.zero_arg_fns fn.Tir.fn_name ()
  ) m.Tir.tm_fns;
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
  let groups =
    List.filter (fun g -> List.length g >= 2) (Llvm_tco.tarjan_sccs m.Tir.tm_fns) in
  let in_group name = List.exists (List.mem name) groups in
  List.iter (fun g ->
    emit_mutual_group ctx
      (List.filter_map (fun n ->
         List.find_opt (fun fn -> String.equal fn.Tir.fn_name n) m.Tir.tm_fns) g))
    groups;
  List.iter (fun fn -> if not (in_group fn.Tir.fn_name) then emit_fn_decl ctx fn)
    m.Tir.tm_fns;
  (* The `to_string` printers (function declarations, so hoisted). *)
  let fns_js = Buffer.contents ctx.buf ^ Buffer.contents ctx.show_buf in
  let raw_segments = !(ctx.segments) in
  (* Emit extern bridges only for externs actually referenced in the emitted code *)
  let used_ed = List.filter (fun (ed : Tir.extern_decl) ->
    Hashtbl.mem ctx.used_externs ed.ed_march_name
  ) m.Tir.tm_externs in
  (* Chunk C: reject used C-backed externs — they have no JS implementation *)
  let bad_externs = List.filter (fun ed -> classify_js_extern ed = CBacked) used_ed in
  let extern_msgs = List.map (fun (ed : Tir.extern_decl) ->
    Printf.sprintf
      "error: extern \"%s\" function `%s` cannot be called on the JavaScript target.\n\
       The JS backend supports only JS-module externs:\n\
         extern \"node:fs\"   extern \"npm:lodash\"   extern \"./local.mjs\"\n\
       `%s` is bound to the C symbol `%s`, which has no JS runtime\n\
       implementation. To call it from JS, wrap it in a JS module, or build a\n\
       native/wasm target."
      ed.Tir.ed_lib_name ed.Tir.ed_march_name ed.Tir.ed_march_name ed.Tir.ed_c_name
  ) bad_externs in
  (* Unmapped builtins: previously these were emitted as bare calls that threw
     ReferenceError at runtime; fail the compile with a diagnostic instead. *)
  let unmapped_names =
    List.sort String.compare
      (Hashtbl.fold (fun k _ acc -> k :: acc) ctx.unmapped []) in
  let unmapped_msgs = List.map (fun name ->
    match name with
    | "int_max_value" | "int_min_value" ->
      Printf.sprintf
        "error: builtin `%s` is not supported on the JavaScript target.\n\
         Its value (±2^62) is not representable there: March Int is stored in\n\
         a JS double, which is exact only within ±(2^53 - 1). Restructure the\n\
         code to avoid full 63-bit values (e.g. stdlib Random uses a 32-bit\n\
         core for exactly this reason), or build a native/wasm target."
        name
    | _ when String.length name >= 5 && String.sub name 0 5 = "simd_" ->
      Printf.sprintf
        "error: `%s` is a Simd vector builtin; the Simd module is not\n\
         supported on the JavaScript target (fixed 128-bit SIMD has no JS\n\
         lowering). Build a native/wasm target, or use NativeArray's\n\
         map/map2/sum, which do compile on JS."
        name
    | _ ->
      Printf.sprintf
        "error: builtin `%s` has no JavaScript-target implementation%s.\n\
         The compiled call would throw ReferenceError at runtime. Add a\n\
         mapping in lib/tir/js_emit.ml (+ runtime/march_runtime.mjs if it\n\
         needs a helper), or build a native/wasm target."
        name
        (match Hashtbl.find_opt ctx.unmapped name with
         | Some loc when loc <> "" -> " (called from " ^ loc ^ ")"
         | _ -> "")
  ) unmapped_names in
  if extern_msgs <> [] || unmapped_msgs <> [] then
    raise (Js_emit_error (extern_msgs @ unmapped_msgs));
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
  Hashtbl.replace ctx.runtime_uses "march_int_ovf" ();   (* negate_int *)
  let int_rt_builtins2 =   (* two-argument runtime-backed int builtins *)
    [ "int_and"; "int_or"; "int_xor"; "int_shl"; "int_shr";
      "int_mod"; "int_div"; "int_mod_euclid"; "int_div_euclid";
      "int_mod_floor"; "int_div_floor";
      "int_wrapping_add"; "int_wrapping_sub"; "int_wrapping_mul" ] in
  let int_rt_builtins1 = [ "int_not"; "int_popcount" ] in
  List.iter (fun n -> Hashtbl.replace ctx.runtime_uses ("march_" ^ n) ())
    (int_rt_builtins2 @ int_rt_builtins1);
  Hashtbl.replace ctx.runtime_uses "march_unix_time" ();
  Hashtbl.replace ctx.runtime_uses "march_unix_time_ms" ();
  Hashtbl.replace ctx.runtime_uses "march_float_round" ();
  (* The --test runner emitted after the functions, below. *)
  if m.Tir.tm_tests <> [] then
    List.iter (fun n -> Hashtbl.replace ctx.runtime_uses n ())
      [ "march_test_init"; "march_test_setup_all"; "march_test_run"; "march_test_report" ];
  (* A user top-level fn of the same name owns it (#1177): its own
     `function n` + `n$clo` are emitted, and a second `const n` would be a
     load-time SyntaxError (redeclared identifier). *)
  let wrapper n body =
    if Hashtbl.mem ctx.fn_names n then "" else Printf.sprintf "const %s = %s;\n" n body in
  let runtime_wrappers =
    wrapper "float_to_string" "{ _0: ($_, x) => march_float_to_string(x) }" ^
    wrapper "string_length" "{ _0: ($_, x) => march_string_byte_length(x) }" ^
    wrapper "string_byte_length" "{ _0: ($_, x) => march_string_byte_length(x) }" ^
    String.concat "" (List.map (fun n ->
      wrapper n (Printf.sprintf "{ _0: ($_, a, b) => march_%s(a, b) }" n))
      int_rt_builtins2) ^
    String.concat "" (List.map (fun n ->
      wrapper n (Printf.sprintf "{ _0: ($_, a) => march_%s(a) }" n))
      int_rt_builtins1) ^
    wrapper "int_abs" "{ _0: ($_, a) => Math.abs(a) }" ^
    wrapper "unix_time" "{ _0: ($_) => march_unix_time() }" ^
    wrapper "unix_time_ms" "{ _0: ($_) => march_unix_time_ms() }" ^
    wrapper "float_round" "{ _0: ($_, a) => march_float_round(a) }"
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
  let has_fn n = List.exists (fun fn -> fn.Tir.fn_name = n) m.Tir.tm_fns in
  if m.Tir.tm_tests <> [] then begin
    (* --test (issue #1176): run every test as the native test binary does
       (llvm_toplevel's test-runner @main over the same [tm_tests]) and not
       `main`: the same dots, report and summary, exit status 1 on a failure
       through process.exitCode.  The runner functions are imported above
       ([runtime_uses]); each call is awaited, as a test may be async. *)
    let setup =
      if has_fn Tir_names.setup_fn_name then mangle Tir_names.setup_fn_name
      else "null" in
    Buffer.add_string export_buf "march_test_init();\n";
    if has_fn Tir_names.setup_all_fn_name then
      Buffer.add_string export_buf
        (Printf.sprintf "await march_test_setup_all(%s);\n"
           (mangle Tir_names.setup_all_fn_name));
    List.iter (fun (fn_name, display) ->
        Buffer.add_string export_buf
          (Printf.sprintf "await march_test_run(%s, %s, %s);\n"
             (mangle fn_name) (js_string_lit display) setup))
      m.Tir.tm_tests;
    Buffer.add_string export_buf "march_test_report();\n"
  end else if has_main then begin
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
