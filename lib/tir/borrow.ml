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

(** True iff parameter [idx] of [fn_name] is marked borrowed in [m]. *)
let is_borrowed (m : borrow_map) (fn_name : string) (idx : int) : bool =
  match StringMap.find_opt fn_name m with
  | Some modes -> idx < Array.length modes && modes.(idx)
  | None -> false

(** Same predicate as [Perceus.needs_rc].  Duplicated here to avoid a cyclic
    module dependency: [Perceus] imports [Borrow], so [Borrow] must not import
    [Perceus]. *)
let needs_rc : Tir.ty -> bool = function
  | Tir.TCon _ | Tir.TString | Tir.TPtr _ -> true
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
  | Tir.ECase (_, branches, default) ->
    (* The scrutinee itself is a borrow use (read-only).
       Check branch bodies where the name might escape. *)
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
