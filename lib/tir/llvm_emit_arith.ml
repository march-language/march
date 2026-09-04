(** Arithmetic and comparison codegen: the bodies of [Llvm_emit.emit_expr]'s
    `+ - * / %`, `== != < <= > >=` and `+. -. *. /.` arms.

    Phase 2b of specs/plans/2026-08-19-compiler-file-decomposition.md, the
    per-arm delegation Phase 2 deferred.  Each arm keeps its exact position
    and its exact guard in [emit_expr]'s match -- match order there is
    load-bearing (non-builtin arms interleave with builtin ones, and the TCO
    arms sit below several builtin arms), so nothing is grouped or reordered.
    Only the arm BODIES live here, byte-identical to the text they replaced,
    reached through one function each.  [emit_atom] is threaded in as a
    labelled callback, the convention [Llvm_emit_simd] and [Llvm_emit_nmap]
    already established.

    The three operator-string tables ([int_arith_op], [int_cmp_pred],
    [float_arith_op]) moved with the bodies: they had no other caller. The
    [is_int_arith]/[is_int_cmp]/[is_float_arith] guard predicates did NOT --
    they are still evaluated in [emit_expr]'s `when` clauses. *)

open Llvm_ctx
open Llvm_emit_simd

let ensure_adt_eq_fn = Llvm_eq.ensure_adt_eq_fn

let int_arith_op = function
  | "+" -> "add" | "-" -> "sub" | "*" -> "mul"
  | "/" -> "sdiv" | "%" -> "srem" | s -> failwith ("unknown int op: " ^ s)

let int_cmp_pred = function
  | "==" -> "eq"  | "!=" -> "ne"
  | "<"  -> "slt" | "<=" -> "sle"
  | ">"  -> "sgt" | ">=" -> "sge"
  | s -> failwith ("unknown cmp: " ^ s)

let float_arith_op = function
  | "+." -> "fadd" | "-." -> "fsub"
  | "*." -> "fmul" | "/." -> "fdiv" | s -> failwith ("unknown float op: " ^ s)

(* [emit_atom_as] is [Llvm_emit]'s one-liner "emit and coerce"; it cannot be
   referenced from here (it is defined in terms of [emit_atom], which lives in
   the file that calls us), so each body that used it gets it back as a local
   shadow built from the threaded callback.  Same definition, same behaviour --
   this is what keeps the moved text byte-identical. *)
(** Body of the `+ - * / %` arm.  Polymorphic over Int and Float: float
    operands are detected from the emitted LLVM type of the first argument. *)
let emit_int_arith ~emit_atom ctx (f : Tir.var) (a : Tir.atom) (b : Tir.atom)
  : string * string =
  let emit_atom_as ctx ty a =
    let (actual_ty, v) = emit_atom ctx a in coerce ctx actual_ty v ty
  in
    (* +, -, *, /, % are polymorphic over Int and Float in March.
       Detect float operands by checking the actual LLVM type of the first arg;
       if double, use floating-point ops instead of integer ops. *)
    let (ty_a, va) = emit_atom ctx a in
    if ty_a = "double" then begin
      let vb = emit_atom_as ctx "double" b in
      let r  = fresh ctx "ar" in
      (* Division uses march_checked_fdiv so that x / 0.0 aborts with an error
         rather than silently returning infinity (IEEE 754 default for fdiv).
         All other float ops use native LLVM instructions directly. *)
      if f.Tir.v_name = "/" then begin
        emit ctx (Printf.sprintf "%s = call double @march_checked_fdiv(double %s, double %s)" r va vb)
      end else begin
        let fop = match f.Tir.v_name with
          | "+" -> "fadd" | "-" -> "fsub" | "*" -> "fmul"
          | _ -> "fmul"
        in
        let op_str = if ctx.fast_math then fop ^ " fast" else fop in
        emit ctx (Printf.sprintf "%s = %s double %s, %s" r op_str va vb)
      end;
      ("double", r)
    end else begin
      let va' = coerce ctx ty_a va "i64" in
      let vb = emit_atom_as ctx "i64" b in
      let r  = fresh ctx "ar" in
      (* / and % on Int route through checked helpers so a zero divisor traps
         (matching the interpreter) instead of emitting a raw sdiv/srem that
         returns garbage.  The helpers use the bare operator messages
         ("division by zero" / "modulo by zero"); other ops stay native. *)
      (match f.Tir.v_name with
       | "/" -> emit ctx (Printf.sprintf "%s = call i64 @march_checked_div_op(i64 %s, i64 %s)" r va' vb)
       | "%" -> emit ctx (Printf.sprintf "%s = call i64 @march_checked_mod_op(i64 %s, i64 %s)" r va' vb)
       | _   -> emit ctx (Printf.sprintf "%s = %s i64 %s, %s" r (int_arith_op f.Tir.v_name) va' vb));
      ("i64", r)
    end

(** Body of the `== != < <= > >=` arm: SIMD lanes, string equality and
    ordering, ADT structural equality, and the numeric/pointer fallback. *)
let emit_int_cmp ~emit_atom ctx (f : Tir.var) (a : Tir.atom) (b : Tir.atom)
  : string * string =
    let (ty_a, va) = emit_atom ctx a in
    let (ty_b, vb) = emit_atom ctx b in
    if (is_vec_ty ty_a || is_vec_ty ty_b) && (f.Tir.v_name = "==" || f.Tir.v_name = "!=") then begin
      (* SIMD vector `==`/`!=`: [ensure_adt_eq_fn] below synthesizes structural
         equality by walking a `type_def`'s fields, but the 5 SIMD vector
         types are opaque compiler primitives (TCon with no type_def/fields —
         their "fields" are vector lanes, invisible to that walk), so the
         general ADT path can't handle them and would otherwise fall through
         to the raw i64/ptr fallback below and reinterpret the vector
         register as a scalar (an LLVM type-mismatch, not just a wrong
         answer). Lower directly: per-lane compare (`fcmp oeq` for the float
         families — NaN-sensitive, a NaN lane always compares unequal, the
         same semantics [impl Eq(F32x4)]'s hand-written per-lane `==` chain
         gives interpreted) then AND all lanes together. *)
      let vv_ty = if is_vec_ty ty_a then ty_a else ty_b in
      let sty = snd (List.find (fun (_, s) -> s.s_vec = vv_ty) simd_tys) in
      let av = coerce ctx ty_a va vv_ty and bv = coerce ctx ty_b vb vv_ty in
      let cmp = fresh ctx "veq" in
      (if sty.s_boundary_float then
         emit ctx (Printf.sprintf "%s = fcmp oeq %s %s, %s" cmp vv_ty av bv)
       else
         emit ctx (Printf.sprintf "%s = icmp eq %s %s, %s" cmp vv_ty av bv));
      let packed = fresh ctx "veq" in
      emit ctx (Printf.sprintf "%s = bitcast <%d x i1> %s to i%d" packed sty.s_lanes cmp sty.s_lanes);
      let alleq = fresh ctx "veq" in
      emit ctx (Printf.sprintf "%s = icmp eq i%d %s, -1" alleq sty.s_lanes packed);
      let r64 = coerce ctx "i1" alleq "i64" in
      let final =
        if f.Tir.v_name = "!=" then begin
          let nr = fresh ctx "veq" in
          emit ctx (Printf.sprintf "%s = xor i64 %s, 1" nr r64); nr
        end else r64
      in
      ("i64", final)
    end else
    (* Only route through march_string_eq when we are sure the operand is an
       actual String.  ty_a = "ptr" may also occur for polymorphic values
       (TVar "_" after mono leaks) that happen to carry an Int via inttoptr —
       calling march_string_eq on such a value dereferences it as a march_string
       struct and crashes.  Check the TIR type of either operand instead. *)
    let atom_is_string = function
      | Tir.AVar v    -> (match v.Tir.v_ty with Tir.TString -> true | _ -> false)
      | Tir.ALit (March_ast.Ast.LitString _) -> true
      | _             -> false
    in
    let is_string_eq =
      ty_a = "ptr"
      && (f.Tir.v_name = "==" || f.Tir.v_name = "!=")
      && (atom_is_string a || atom_is_string b)
    in
    (* String ordering (<, <=, >, >=): the inline icmp fallback would compare
       the string struct POINTERS as integers, which has nothing to do with
       lexicographic order.  Route through march_compare_string (returns
       -1/0/1) and compare the result against 0 with the same predicate. *)
    let is_string_ord =
      ty_a = "ptr"
      && List.mem f.Tir.v_name ["<"; "<="; ">"; ">="]
      && (atom_is_string a || atom_is_string b)
    in
    if is_string_eq then begin
      (* String equality: call march_string_eq which returns i64 (0 or 1).
         Coerce both operands to ptr — vb may be an i64 literal (e.g. "0" for
         false/unit) which is invalid as a bare ptr argument in LLVM IR. *)
      let va_ptr = coerce ctx ty_a va "ptr" in
      let vb_ptr = coerce ctx ty_b vb "ptr" in
      let r = fresh ctx "cr" in
      emit ctx (Printf.sprintf "%s = call i64 @march_string_eq(ptr %s, ptr %s)" r va_ptr vb_ptr);
      if f.Tir.v_name = "!=" then begin
        let nr = fresh ctx "ar" in
        emit ctx (Printf.sprintf "%s = xor i64 %s, 1" nr r);
        ("i64", nr)
      end else
        ("i64", r)
    end else if is_string_ord then begin
      (* String ordering: compare(a, b) <pred> 0. *)
      let va_ptr = coerce ctx ty_a va "ptr" in
      let vb_ptr = coerce ctx ty_b vb "ptr" in
      let c   = fresh ctx "scmp" in
      let cmp = fresh ctx "cmp" in
      let r   = fresh ctx "ar" in
      emit ctx (Printf.sprintf "%s = call i64 @march_compare_string(ptr %s, ptr %s)" c va_ptr vb_ptr);
      emit ctx (Printf.sprintf "%s = icmp %s i64 %s, 0" cmp (int_cmp_pred f.Tir.v_name) c);
      emit ctx (Printf.sprintf "%s = zext i1 %s to i64" r cmp);
      ("i64", r)
    end else if
      (f.Tir.v_name = "==" || f.Tir.v_name = "!=")
      && (Repr.unboxed_of_llvm_ty ty_a <> None || Repr.unboxed_of_llvm_ty ty_b <> None)
    then begin
      (* Unboxed aggregate equality (Milestone 3): compare field by field in
         registers.  Boxing both sides and reusing [Llvm_eq.ensure_adt_eq_fn]
         would give the same answer, but it would allocate two cells per
         comparison — which is precisely what the representation exists to
         avoid, and would make `v == v` fail a [@[no_alloc]] contract.

         The per-field predicates are the SAME ones the boxed structural
         comparison uses ([Llvm_eq]: `fcmp oeq double` for a Float field,
         `icmp eq i64` for Int/Bool), so the two paths agree on every input
         including NaN (a NaN field compares unequal under `oeq` in both). *)
      let sty = match Repr.unboxed_of_llvm_ty ty_a with
        | Some _ -> ty_a | None -> ty_b in
      let fields = match Repr.unboxed_of_llvm_ty sty with
        | Some (_, _, fs) -> fs
        | None -> assert false (* guard checked one side is unboxed *) in
      let av = coerce ctx ty_a va sty and bv = coerce ctx ty_b vb sty in
      let acc = ref "true" in
      List.iteri (fun i fty_tir ->
          let fty = Llvm_ctx.llvm_ty fty_tir in
          let fa = fresh ctx "ubea" and fb = fresh ctx "ubeb" in
          emit ctx (Printf.sprintf "%s = extractvalue %s %s, %d" fa sty av i);
          emit ctx (Printf.sprintf "%s = extractvalue %s %s, %d" fb sty bv i);
          let c = fresh ctx "ubec" in
          if fty = "double" then
            emit ctx (Printf.sprintf "%s = fcmp oeq double %s, %s" c fa fb)
          else
            emit ctx (Printf.sprintf "%s = icmp eq %s %s, %s" c fty fa fb);
          let nx = fresh ctx "ubea" in
          emit ctx (Printf.sprintf "%s = and i1 %s, %s" nx !acc c);
          acc := nx)
        fields;
      let bit =
        if f.Tir.v_name = "!=" then begin
          let n = fresh ctx "ubea" in
          emit ctx (Printf.sprintf "%s = xor i1 %s, true" n !acc); n
        end else !acc
      in
      ("i64", coerce ctx "i1" bit "i64")
    end else begin
      (* Fallback comparison: float or i64 (pointer coercion). *)
      let fallback_cmp () =
        let cmp = fresh ctx "cmp" in
        let r   = fresh ctx "ar" in
        if ty_a = "double" || ty_b = "double" then begin
          (* Float comparison: use fcmp ordered predicates.
             Coerce both sides to double in case one came from a boxed ptr. *)
          let fpred = match f.Tir.v_name with
            (* "!=" must match IEEE `<>` semantics used by the interpreter
               (OCaml's polymorphic `<>` on floats is true whenever either
               operand is NaN), i.e. "unordered or not equal" ("une"), not
               "one" (ordered and not equal, which is false for any NaN
               operand). See eval.ml's cmp_op float branch. *)
            | "==" -> "oeq" | "!=" -> "une"
            | "<"  -> "olt" | "<=" -> "ole"
            | ">"  -> "ogt" | ">=" -> "oge"
            | s -> failwith ("unknown cmp: " ^ s)
          in
          let va_f = coerce ctx ty_a va "double" in
          let vb_f = coerce ctx ty_b vb "double" in
          emit ctx (Printf.sprintf "%s = fcmp %s double %s, %s" cmp fpred va_f vb_f);
        end else if ty_a = "ptr" || ty_b = "ptr" then begin
          (* Erased operand(s): the static type is TVar, so the runtime value may
             be a tagged int, a boxed Float (tag -3), or a string.  A raw
             ptr→i64 + icmp mis-orders boxed floats (float-boxing, Stage 2 —
             and, pre-boxing, negative-float bits: mechanism 2).  Dispatch on the
             runtime tag via march_poly_compare (returns -1/0/1) and apply the
             requested ordering vs 0.  A concrete i64 operand coerces to a tagged
             immediate ptr, which march_poly_compare's odd→int arm handles. *)
          let va_p = coerce ctx ty_a va "ptr" in
          let vb_p = coerce ctx ty_b vb "ptr" in
          let c = fresh ctx "pcmp" in
          emit ctx (Printf.sprintf "%s = call i64 @march_poly_compare(ptr %s, ptr %s)" c va_p vb_p);
          emit ctx (Printf.sprintf "%s = icmp %s i64 %s, 0" cmp (int_cmp_pred f.Tir.v_name) c)
        end else begin
          (* Both concrete i64: fast integer compare. *)
          let va' = coerce ctx ty_a va "i64" in
          let vb' = coerce ctx ty_b vb "i64" in
          emit ctx (Printf.sprintf "%s = icmp %s i64 %s, %s" cmp (int_cmp_pred f.Tir.v_name) va' vb')
        end;
        emit ctx (Printf.sprintf "%s = zext i1 %s to i64" r cmp);
        ("i64", r)
      in
      (* ADT structural equality: when both operands are heap-allocated ADT values
         (ty_a = "ptr", TCon type, not String) generate a structural comparison
         instead of the pointer comparison that icmp eq i64 would produce. *)
      let atom_adt_ty = function
        | Tir.AVar v -> (match v.Tir.v_ty with
          | Tir.TCon ("Atom", []) -> None
          | Tir.TCon _ as t -> Some t
          | (Tir.TTuple _ | Tir.TRecord _) as t -> Some t
          | _ -> None)
        | _ -> None
      in
      if ty_a = "ptr" && (f.Tir.v_name = "==" || f.Tir.v_name = "!=") then
        let adt_ty_opt = match atom_adt_ty a with
          | Some _ as t -> t
          | None -> atom_adt_ty b
        in
        (match adt_ty_opt with
         | Some adt_ty ->
           (match ensure_adt_eq_fn ctx adt_ty with
            | Some eq_fn ->
              let r = fresh ctx "ar" in
              let va_ptr = coerce ctx ty_a va "ptr" in
              let vb_ptr = coerce ctx ty_b vb "ptr" in
              emit ctx (Printf.sprintf "%s = call i64 @%s(ptr %s, ptr %s)" r eq_fn va_ptr vb_ptr);
              if f.Tir.v_name = "!=" then begin
                let nr = fresh ctx "nr" in
                emit ctx (Printf.sprintf "%s = xor i64 %s, 1" nr r);
                ("i64", nr)
              end else
                ("i64", r)
            | None -> fallback_cmp ())
         | None ->
           (* Polymorphic ptr comparison: the TIR type is TVar (e.g. the result
              of a polymorphic function like root_hash).  Pointer identity
              (fallback_cmp) compares addresses, not content — always false for
              two distinct string allocations with equal content.  Use
              march_poly_eq which checks string tags at runtime and delegates to
              march_string_eq for strings, giving correct content equality. *)
           let r = fresh ctx "ar" in
           let va_ptr = coerce ctx ty_a va "ptr" in
           let vb_ptr = coerce ctx ty_b vb "ptr" in
           emit ctx (Printf.sprintf "%s = call i64 @march_poly_eq(ptr %s, ptr %s)" r va_ptr vb_ptr);
           if f.Tir.v_name = "!=" then begin
             let nr = fresh ctx "nr" in
             emit ctx (Printf.sprintf "%s = xor i64 %s, 1" nr r);
             ("i64", nr)
           end else
             ("i64", r))
      else fallback_cmp ()
    end

(** Body of the `+. -. *. /.` arm. *)
let emit_float_arith ~emit_atom ctx (f : Tir.var) (a : Tir.atom) (b : Tir.atom)
  : string * string =
  let emit_atom_as ctx ty a =
    let (actual_ty, v) = emit_atom ctx a in coerce ctx actual_ty v ty
  in
    let va = emit_atom_as ctx "double" a in
    let vb = emit_atom_as ctx "double" b in
    let r  = fresh ctx "ar" in
    (* /. uses march_checked_fdiv for the same reason as / above. *)
    if f.Tir.v_name = "/." then
      emit ctx (Printf.sprintf "%s = call double @march_checked_fdiv(double %s, double %s)" r va vb)
    else begin
      let op = float_arith_op f.Tir.v_name in
      let op_str = if ctx.fast_math then op ^ " fast" else op in
      emit ctx (Printf.sprintf "%s = %s double %s, %s" r op_str va vb)
    end;
    ("double", r)

