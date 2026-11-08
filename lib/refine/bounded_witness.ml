(** Existential goals use a finite, deterministic set of source-derived
    candidates. The result is stronger than the original goal: failure is
    UNKNOWN, never a counterexample to the original existential. *)
open Smt

let limit = 32

let sort_of env = function
  | Const n -> List.assoc_opt n env
  | IntLit _ -> Some SInt
  | BoolLit _ -> Some SBool
  | FloatLit _ -> Some SFloat
  | Ctor (_, sort, _) -> Some sort
  | Add _ | Sub _ | Mul _ | MulLit _ | Neg _ | Div _ | Mod _ | DivLit _ | ModLit _ -> Some SInt
  | _ -> None

let candidates env sort terms =
  let rec collect acc t =
    let acc = if sort_of env t = Some sort
      && List.for_all (fun n -> List.mem_assoc n env) (free_names t)
      then t :: acc else acc in
    match t with Quant _ -> acc | _ -> List.fold_left collect acc (children t) in
  let terms = List.fold_left collect [] terms
    @ List.filter_map (fun (n, s) -> if s = sort then Some (Const n) else None) env in
  List.sort_uniq compare terms |> List.to_seq |> Seq.take limit |> List.of_seq

let expand (vc : vc) : term * bool =
  let changed = ref false in
  let rec quantified t = match t with Quant _ -> true | _ -> List.exists quantified (children t) in
  let rec go env positive t =
    match t with
    | Quant (false, n, sort, guard, body) when positive ->
      changed := true;
      let cs = candidates env sort (guard :: body :: vc.assumptions) in
      let arms = List.map (fun c ->
        let inst = substitute n c in
        go env true (And (inst guard, inst body))) cs in
      List.fold_left (fun a b -> Or (a, b)) (BoolLit false) arms
    | Quant (q, n, sort, guard, body) ->
      Quant (q, n, sort, guard, go ((n, sort) :: env) positive body)
    | And (a, b) -> And (go env positive a, go env positive b)
    | Or (a, b) -> Or (go env positive a, go env positive b)
    | Implies (a, b) -> Implies (go env (not positive) a, go env positive b)
    | Not a -> Not (go env (not positive) a)
    | Eq (a, b) when quantified a || quantified b ->
      go env positive (And (Implies (a, b), Implies (b, a)))
    | Ne (a, b) when quantified a || quantified b ->
      go env positive (Not (Eq (a, b)))
    | Ite (c, a, b) when quantified c ->
      go env positive (And (Implies (c, a), Implies (Not c, b)))
    | _ -> t in
  let goal = go vc.decls true vc.goal in
  (goal, !changed)
