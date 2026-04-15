(** Borrow Inference — Pre-Perceus Analysis Pass.

    Determines which function parameters are "borrowed" — only read within
    the callee and never stored, returned, or passed to an owning position.
    Borrowed parameters need no reference-counting:
    - At call sites: no EIncRC before passing a borrowed arg that is still live
    - In callees: no EDecRC when a borrowed param goes out of scope

    The analysis uses an optimistic fixpoint iteration over the module's
    functions, starting with all RC-needing parameters marked as borrowed and
    refining until no further parameters are found to be owned.

    Runs after Defun so that closures are already explicit EAlloc nodes —
    free-variable captures are visible as constructor arguments, making them
    conservatively owning.

    The key rule:
      A use is OWNING  if the value is stored (EAlloc / ETuple / ERecord /
                         EUpdate field), returned (EAtom(AVar)), or passed to
                         an unknown callee (ECallPtr) or an owned parameter of
                         a known callee.
      A use is BORROWING if the value is used as an ECase scrutinee, an EField
                         source, or passed to a borrowed parameter of a known
                         callee.

    After convergence, [is_borrowed m fn_name idx] returns true iff parameter
    [idx] of function [fn_name] is safe to borrow. *)

module StringMap = Map.Make (String)

(** Per-function borrow modes, indexed by parameter position.
    [true] = borrowed, [false] = owned. *)
type param_modes = bool array

(** Module-level borrow map: function name → per-parameter modes. *)
type borrow_map = param_modes StringMap.t

let empty : borrow_map = StringMap.empty

(** Hardcoded borrow table for C extern functions that borrow (read-only) their
    string/heap parameters without taking ownership.  Indexed by C name *or*
    TIR builtin name (the same name appears in EApp before LLVM mangling).

    Format: (function_name, bool list) where each bool indicates whether the
    corresponding positional parameter is borrowed. *)
let extern_borrow_table : (string * bool list) list = [
  (* ── IO ─────────────────────────────────────────────────────────────────── *)
  ("march_print",   [true]);
  ("march_println", [true]);
  ("print",         [true]);   (* TIR builtin name before LLVM mangling *)
  ("println",       [true]);
  (* ── Core string operations ─────────────────────────────────────────────── *)
  ("march_string_eq",          [true; true]);
  ("march_string_concat",      [true; true]);
  ("march_string_byte_length", [true]);
  ("march_string_grapheme_count", [true]);
  ("march_string_is_empty",    [true]);
  ("march_string_to_int",      [true]);
  ("march_string_to_float",    [true]);
  ("march_string_to_lowercase",[true]);
  ("march_string_to_uppercase",[true]);
  ("march_string_trim",        [true]);
  ("march_string_trim_start",  [true]);
  ("march_string_trim_end",    [true]);
  ("march_string_reverse",     [true]);
  (* ── 2-arg string × string ──────────────────────────────────────────────── *)
  ("march_string_contains",      [true; true]);
  ("march_string_starts_with",   [true; true]);
  ("march_string_ends_with",     [true; true]);
  ("march_string_split",         [true; true]);
  ("march_string_split_first",   [true; true]);
  ("march_string_index_of",      [true; true]);
  ("march_string_last_index_of", [true; true]);
  (* ── 3-arg string × string × string ────────────────────────────────────── *)
  ("march_string_replace",     [true; true; true]);
  ("march_string_replace_all", [true; true; true]);
  (* ── mixed-arity: string param(s) only ─────────────────────────────────── *)
  (* slice(s, int_start, int_len)  — only s is a string *)
  ("march_string_slice",     [true; false; false]);
  (* repeat(s, int_n)  — only s is a string *)
  ("march_string_repeat",    [true; false]);
  (* join(list, sep)  — list is heap-owned by caller; sep is borrowed string *)
  ("march_string_join",      [false; true]);
  (* pad_left/right(s, int_width, fill)  — s and fill are strings *)
  ("march_string_pad_left",  [true; false; true]);
  ("march_string_pad_right", [true; false; true]);
  (* ── TIR builtin names (pre-mangling) ───────────────────────────────────── *)
  ("string_eq",            [true; true]);
  ("string_concat",        [true; true]);
  ("++",                   [true; true]);
  ("string_byte_length",   [true]);
  ("string_grapheme_count",[true]);
  ("string_is_empty",      [true]);
  ("string_to_int",        [true]);
  ("string_to_float",      [true]);
  ("string_to_lowercase",  [true]);
  ("string_to_uppercase",  [true]);
  ("string_trim",          [true]);
  ("string_trim_start",    [true]);
  ("string_trim_end",      [true]);
  ("string_reverse",       [true]);
  ("string_contains",      [true; true]);
  ("string_starts_with",   [true; true]);
  ("string_ends_with",     [true; true]);
  ("string_split",         [true; true]);
  ("string_split_first",   [true; true]);
  ("string_index_of",      [true; true]);
  ("string_last_index_of", [true; true]);
  ("string_replace",       [true; true; true]);
  ("string_replace_all",   [true; true; true]);
  ("string_slice",         [true; false; false]);
  ("string_repeat",        [true; false]);
  ("string_join",          [false; true]);
  ("string_pad_left",      [true; false; true]);
  ("string_pad_right",     [true; false; true]);
  (* ── Synthetic C names used directly in lower.ml wrappers ──────────────── *)
  ("march_compare_string", [true; true]);
  ("march_hash_string",    [true]);
]

(** True iff parameter [idx] of C extern / TIR builtin [fn_name] is borrowed
    according to the hardcoded ABI table.  Used as a fallback in [is_borrowed]
    when the function is not a March-defined function. *)
let is_extern_borrowed (fn_name : string) (param_idx : int) : bool =
  match List.assoc_opt fn_name extern_borrow_table with
  | Some borrows ->
    (match List.nth_opt borrows param_idx with Some b -> b | None -> false)
  | None -> false

(** True iff parameter [idx] of [fn_name] is marked borrowed in [m].
    Falls back to [is_extern_borrowed] for C externs / TIR builtins not
    present in the March borrow map. *)
let is_borrowed (m : borrow_map) (fn_name : string) (idx : int) : bool =
  match StringMap.find_opt fn_name m with
  | Some modes -> idx < Array.length modes && modes.(idx)
  | None -> is_extern_borrowed fn_name idx

(** Same predicate as [Perceus.needs_rc].  Duplicated here to avoid a cyclic
    module dependency: [Perceus] imports [Borrow], so [Borrow] must not import
    [Perceus]. *)
let needs_rc : Tir.ty -> bool = function
  | Tir.TCon ("Atom", []) -> false  (* atoms are i64 scalars, not heap-allocated *)
  | Tir.TCon _ | Tir.TString | Tir.TPtr _ -> true
  | Tir.TVar "_" -> true  (* lower.ml placeholder: conservatively treat as heap-carrying *)
  | Tir.TVar _ | Tir.TInt | Tir.TFloat | Tir.TBool | Tir.TUnit
  | Tir.TTuple _ | Tir.TRecord _ | Tir.TFn _ -> false

(** True iff atom [a] is a reference to the variable named [name]. *)
let atom_is (name : string) : Tir.atom -> bool = function
  | Tir.AVar v -> String.equal v.Tir.v_name name
  | _ -> false

(** [list_any_idx f xs] — true iff [f i xs[i]] holds for some index [i]. *)
let list_any_idx (f : int -> 'a -> bool) (xs : 'a list) : bool =
  let rec go i = function
    | []     -> false
    | x :: t -> if f i x then true else go (i + 1) t
  in
  go 0 xs

(** Returns true iff [e] contains an [EAlloc(TCon(ctor_name, _), _)] where
    [ctor_name] starts with [base_type ^ "."]. This detects "reconstruct"
    patterns where a case branch allocates a same-type constructor, indicating
    an FBIP reuse opportunity that requires ownership of the scrutinee. *)
let rec has_matching_alloc (base_type : string) (e : Tir.expr) : bool =
  let prefix = base_type ^ "." in
  let prefix_len = String.length prefix in
  let matches_type name =
    String.length name >= prefix_len
    && String.sub name 0 prefix_len = prefix
  in
  match e with
  | Tir.EAlloc (Tir.TCon (name, _), _) -> matches_type name
  | Tir.ELet (_, e1, e2) | Tir.ESeq (e1, e2) ->
    has_matching_alloc base_type e1 || has_matching_alloc base_type e2
  | Tir.ECase (_, branches, default) ->
    List.exists (fun br -> has_matching_alloc base_type br.Tir.br_body) branches
    || Option.fold ~none:false ~some:(has_matching_alloc base_type) default
  | Tir.ELetRec (fns, body) ->
    has_matching_alloc base_type body
    || List.exists (fun fn -> has_matching_alloc base_type fn.Tir.fn_body) fns
  | _ -> false

(** Returns true iff [name] has at least one *owning* use in [e].

    An owning use is any position where the value is stored, returned, or
    passed to a callee that is itself not known to borrow that parameter.
    Uses that only read the value (ECase scrutinee, EField source, EApp at a
    borrowed position, EReuse source) are considered borrowing.

    [bm] is the current (possibly incomplete) borrow map used for inter-
    procedural queries; it improves across fixpoint iterations. *)
let rec owned_in (name : string) (bm : borrow_map) (e : Tir.expr) : bool =
  match e with

  (* ── Atoms ────────────────────────────────────────────────────────────── *)
  | Tir.EAtom (Tir.AVar v) ->
    (* Value is returned directly — owning *)
    String.equal v.Tir.v_name name
  | Tir.EAtom _ -> false

  (* ── Storage ──────────────────────────────────────────────────────────── *)
  | Tir.EAlloc (_, args) | Tir.EStackAlloc (_, args) | Tir.ETuple args ->
    List.exists (atom_is name) args

  | Tir.ERecord fields ->
    List.exists (fun (_, a) -> atom_is name a) fields

  | Tir.EUpdate (_, fields) ->
    (* The base record is a borrow use; new field values being stored are owning *)
    List.exists (fun (_, a) -> atom_is name a) fields

  (* ── Calls ────────────────────────────────────────────────────────────── *)
  | Tir.ECallPtr (fn_a, args) ->
    (* Unknown callee — conservative: any arg use is owning *)
    atom_is name fn_a || List.exists (atom_is name) args

  | Tir.EApp (callee, args) ->
    (* Known callee — owning iff the corresponding parameter is NOT borrowed *)
    list_any_idx (fun i a ->
      atom_is name a && not (is_borrowed bm callee.Tir.v_name i)
    ) args
    (* Note: using [name] as the callee function itself is not a data-owning
       use — it is just an indirect reference, treated as borrowing. *)

  (* ── Binding forms ────────────────────────────────────────────────────── *)
  | Tir.ELet (v, e1, e2) ->
    owned_in name bm e1
    || (not (String.equal v.Tir.v_name name) && owned_in name bm e2)

  | Tir.ELetRec (fns, body) ->
    owned_in name bm body
    || List.exists (fun fn ->
         let shadowed =
           List.exists (fun p -> String.equal p.Tir.v_name name) fn.Tir.fn_params
         in
         not shadowed && owned_in name bm fn.Tir.fn_body
       ) fns

  (* ── Pattern matching ─────────────────────────────────────────────────── *)
  | Tir.ECase (scrutinee, branches, default) ->
    (* FBIP-aware: if the scrutinee IS our variable and any branch allocates
       a constructor of the same base type, this is a "reconstruct" pattern
       (e.g. match t { Leaf(n) -> Leaf(n+1) }).  FBIP needs ownership of the
       scrutinee to reuse its memory, so treat this as an owning use. *)
    let fbip_owns =
      atom_is name scrutinee &&
      (match scrutinee with
       | Tir.AVar v ->
         (match v.Tir.v_ty with
          | Tir.TCon (base_type, _) ->
            List.exists (fun br ->
              has_matching_alloc base_type br.Tir.br_body
            ) branches
          | _ -> false)
       | _ -> false)
    in
    (* Field-escape: if the scrutinee IS our variable (and its type is a heap
       constructor) and any branch uses any [br_var] in an owning position in
       the body, the scrutinee itself is an owning use.
       Pattern-match extraction gives the field's value without incrementing
       its refcount — the RC stays on the parent.  If the field then escapes
       (returned, stored, passed to an owning position), the caller receives
       an aliased pointer without ownership: the parent still holds the same
       rc, so the next read of the parent would double-free or
       use-after-free the child (this is the "second read returns None" /
       local RC underflow class of bug).
       Note we intentionally do NOT gate on the [br_var]'s own [v_ty]:
       [Lower] creates [br_vars] with a placeholder [TVar "_"] type even
       when the concrete constructor field is heap-carrying (e.g.
       [List(String)] inside [Box(...)]) and [needs_rc] returns false for
       [TVar _].
       For the same reason we also do NOT gate on the scrutinee's own type:
       closure-generated helpers (e.g. the [go] accumulator loop inside
       [List.map]) have their parameters typed as [TVar "_"] by Lower even
       after monomorphisation, so [needs_rc scrutinee.v_ty] would also be
       false for them — causing field-escape to be missed entirely. Since
       ECase is only generated for variant/tuple types that are always
       heap-allocated in March, any [AVar] scrutinee is conservatively safe
       to treat as potentially RC-carrying.
       We follow through simple let-aliasing ([let v = x in ...] where [x] is
       the name we are tracking): such lets merely rename the alias without
       escaping it.  This avoids over-promotion for the common pattern
       [match conn do | Conn(s) -> println(s) end] which compiles to
       [case conn of Conn($f) -> let s = $f in println(s)] — [$f] is
       assigned to [s] but [s] is then only borrowed, so no escape
       actually occurs. *)
    let rec escapes_through (name : string) (e : Tir.expr) : bool =
      match e with
      | Tir.ELet (v, Tir.EAtom (Tir.AVar src), body)
        when String.equal src.Tir.v_name name ->
        (* [let v = name in body]: the alias [v] carries [name]'s rc forward.
           Check whether [v] (or any further alias) escapes in [body]; also
           honour shadowing of [name]. *)
        escapes_through v.Tir.v_name body
        || (not (String.equal v.Tir.v_name name)
            && owned_in name bm body)
      | _ -> owned_in name bm e
    in
    let field_escape_owns =
      atom_is name scrutinee &&
      (match scrutinee with
       | Tir.AVar _ -> true  (* any var scrutinee: ECase only fires for heap variants *)
       | _ -> false) &&
      List.exists (fun br ->
        List.exists (fun bv ->
          escapes_through bv.Tir.v_name br.Tir.br_body
        ) br.Tir.br_vars
      ) branches
    in
    fbip_owns || field_escape_owns ||
    (* Check branch bodies where the name might escape. *)
    List.exists (fun br ->
      let shadowed =
        List.exists (fun v -> String.equal v.Tir.v_name name) br.Tir.br_vars
      in
      not shadowed && owned_in name bm br.Tir.br_body
    ) branches
    || Option.fold ~none:false ~some:(owned_in name bm) default

  (* ── Sequencing ───────────────────────────────────────────────────────── *)
  | Tir.ESeq (e1, e2) ->
    owned_in name bm e1 || owned_in name bm e2

  (* ── Read-only / RC management ────────────────────────────────────────── *)
  (* EField is a struct field read — not a storing use. *)
  (* EReuse is FBIP cell reuse — not treated as owning for the source value. *)
  | Tir.EField _ | Tir.EReuse _ | Tir.EFree _
  | Tir.EIncRC _ | Tir.EDecRC _ | Tir.EAtomicIncRC _ | Tir.EAtomicDecRC _ ->
    false

(* ── Fixpoint inference ───────────────────────────────────────────────────── *)

(** Infer the borrow map for all functions in [m].

    Algorithm:
    1. Initialise all RC-needing parameters as borrowed (optimistic).
    2. For each function, for each currently-borrowed parameter, check whether
       any owning use exists in the function body using the current borrow_map.
       If so, flip the parameter to owned.
    3. Repeat until the map reaches a fixpoint (no more flips occur).

    Termination: parameters only transition borrowed → owned, never back.
    The iteration is bounded by the total number of RC-needing parameters.

    Params whose types do not [needs_rc] are left as [false] (owned / not
    relevant); the RC pass will not attempt to increment/decrement them
    regardless. *)
let infer_module (m : Tir.tir_module) : borrow_map =
  (* Initialise: params that need RC start as borrowed; others are false. *)
  let init =
    List.fold_left (fun acc fn ->
      let n = List.length fn.Tir.fn_params in
      let modes = Array.init n (fun i ->
        needs_rc (List.nth fn.Tir.fn_params i).Tir.v_ty
      ) in
      StringMap.add fn.Tir.fn_name modes acc
    ) StringMap.empty m.Tir.tm_fns
  in
  (* Fixpoint loop *)
  let rec iterate (bm : borrow_map) : borrow_map =
    let changed = ref false in
    let bm' =
      List.fold_left (fun acc fn ->
        let modes =
          match StringMap.find_opt fn.Tir.fn_name acc with
          | Some m -> Array.copy m
          | None   -> Array.make 0 false
        in
        List.iteri (fun i p ->
          if modes.(i) then begin  (* currently borrowed — check for owning uses *)
            if owned_in p.Tir.v_name acc fn.Tir.fn_body then begin
              modes.(i) <- false;
              changed := true
            end
          end
        ) fn.Tir.fn_params;
        StringMap.add fn.Tir.fn_name modes acc
      ) bm m.Tir.tm_fns
    in
    if !changed then iterate bm' else bm'
  in
  iterate init
