(** Per-IO-capability DICTIONARY SHAPES, derived mechanically from
    [builtin_cap_table] and [builtin_bindings].

    An IO capability has no declaration site a user owns, so it cannot carry a
    `with <DictType>` clause the way a proof capability can.  Its dictionary
    shape is therefore derived from the compiler's own tables: the record of
    the operations that capability authorizes.

    {2 Why a structural [TRecord] and not a generated stdlib module}

    The first attempt generated `stdlib/io_ops.march`.  Two things killed it:
    the field types reference types owned by many different stdlib modules
    ([FileError], [Csv.CsvRow], [FileStat]), which a standalone module cannot
    name; and a module whose values call IO builtins must declare `needs` for
    them, and a module's `needs` propagate to its importers — so every program
    in the world would suddenly demand all fifteen IO capabilities.

    Building the record structurally, from the builtins' own [ty] values,
    sidesteps both: the types are already valid wherever the builtins are, and
    nothing is declared anywhere.  [render] still exists, but as human-readable
    DOCUMENTATION (`march --emit-io-ops`), not as a file the compiler reads.

    {2 Three shape decisions, each forced by a language property}

    FIELDS ARE [Option].  [None] means "not overridden — use the ambient
    implementation".  March records unify EXACTLY (no width subtyping — see the
    [TRecord]/[TRecord] arm of [Typecheck_unify.report_mismatch], which reports
    both surplus and absent fields), so a mock must supply every field.  An
    all-[None] base plus record update is what makes overriding one operation
    bearable.

    ZERO-ARG OPERATIONS TAKE AN EXPLICIT UNIT.  March auto-applies a zero-arg
    function the moment it is named, so `unix_time` has type [Float], not
    [() -> Float], and cannot be stored in a field at all.  Verified: even a
    named `fn seven() : Int` passed as a value is rejected as [Int] against
    [() -> Int].  So [unix_time] becomes a field of type [(()) -> Float] and
    the call site passes [()].

    POLYMORPHIC BUILTINS ARE EXCLUDED.  A dictionary field holding a
    polymorphic operation needs rank-2 types, which March's records do not
    have.  19 of the 91 cap-requiring builtins are polymorphic — the whole
    [vault_*] family (so [IO.Mut] has no dictionary at all) plus the
    [*_spawn*] family.  They can never be intercepted and always take the
    ambient path.  That is a real hole in a mock, so [excluded_ops] reports
    them and [render] prints them rather than letting them go silently
    missing. *)

open Typecheck_types

exception Unsupported of string

(** Builtin arrows are CURRIED ([TArrow (a, TArrow (b, c))]); March surface
    function types are UNCURRIED ([(A, B) -> C]).  Flatten the spine. *)
let rec flatten_arrow (t : ty) : ty list * ty =
  match repr t with
  | TArrow (a, b) -> let (args, ret) = flatten_arrow b in (a :: args, ret)
  | other -> ([], other)

(** Render [t] as March SURFACE syntax, for [render]'s documentation output.
    Not [pp_ty]: that prints arrows curried and infix ([String -> ()]), which
    is not what the parser accepts in a field annotation. *)
let rec march_ty (t : ty) : string =
  match repr t with
  | TCon (n, []) -> n
  | TCon (n, args) -> Printf.sprintf "%s(%s)" n (String.concat ", " (List.map march_ty args))
  | TTuple [] -> "()"
  | TTuple ts -> Printf.sprintf "(%s)" (String.concat ", " (List.map march_ty ts))
  | TArrow _ as a ->
    let (args, ret) = flatten_arrow a in
    Printf.sprintf "(%s) -> %s" (String.concat ", " (List.map march_ty args)) (march_ty ret)
  | TVar _ -> raise (Unsupported "type variable (needs rank-2 types)")
  | other -> raise (Unsupported (pp_ty other))

(** Every IO capability that owns at least one builtin, sorted. *)
let all_caps () : string list =
  List.map snd Typecheck_builtins.builtin_cap_table |> List.sort_uniq String.compare

let ops_of_cap (cap : string) : string list =
  List.filter_map (fun (name, c) -> if c = cap then Some name else None)
    Typecheck_builtins.builtin_cap_table
  |> List.sort_uniq String.compare

(** [field_ty_of_builtin op] is the [ty] a dictionary field for [op] carries,
    or [None] when [op] cannot be a field at all (polymorphic, or a shape
    [march_ty] cannot render).  A zero-arg builtin already has the shape
    [TArrow (TTuple [], r)], which is exactly the explicit-unit field type the
    call site needs — no adjustment required. *)
let field_ty_of_builtin (op : string) : ty option =
  match List.assoc_opt op Typecheck_builtins.builtin_bindings with
  | Some (Mono t) -> (try ignore (march_ty t); Some t with Unsupported _ -> None)
  | _ -> None

(** [dict_fields cap] is [cap]'s dictionary as sorted [(field, ty)] pairs.
    Sorted because [Typecheck_unify] asserts the invariant that every
    [TRecord] is built with sorted field names. *)
let dict_fields (cap : string) : (string * ty) list =
  ops_of_cap cap
  |> List.filter_map (fun op ->
      match field_ty_of_builtin op with
      | Some t -> Some (op, TCon ("Option", [ t ]))
      | None -> None)
  |> List.sort (fun (a, _) (b, _) -> String.compare a b)

(** [excluded_ops cap] is the operations of [cap] that CANNOT be intercepted,
    so a mock of [cap] silently does not cover them. *)
let excluded_ops (cap : string) : string list =
  ops_of_cap cap |> List.filter (fun op -> field_ty_of_builtin op = None)

(** [dict_ty cap] is the dictionary record type for IO capability [cap], or
    [None] when the capability has no interceptable operation at all
    ([IO.Mut], whose every builtin is polymorphic). *)
let dict_ty (cap : string) : ty option =
  match dict_fields cap with [] -> None | flds -> Some (TRecord flds)

(* ── human-readable documentation (`march --emit-io-ops`) ─────────────── *)

let render () : string =
  let b = Buffer.create 8192 in
  let p fmt = Printf.ksprintf (Buffer.add_string b) fmt in
  p "-- Per-capability dictionary shapes for the IO capabilities.\n";
  p "--\n";
  p "-- DOCUMENTATION, not a source file: these records are built structurally by\n";
  p "-- lib/typecheck/io_ops_gen.ml from the compiler's own `builtin_cap_table`,\n";
  p "-- because their field types name types owned by many different stdlib\n";
  p "-- modules and no single module could import them all.\n";
  p "--\n";
  p "-- Every field is an `Option`: `None` means \"not overridden, use the ambient\n";
  p "-- implementation\". Records unify exactly in March, so a mock supplies every\n";
  p "-- field -- start from the all-None base and override what you care about:\n";
  p "--\n";
  p "--   cap_impl(c, { cap_ops_empty(c) with println: Some(fn s -> capture(s)) })\n";
  p "--\n";
  p "-- A zero-argument operation takes an explicit unit, because March auto-applies\n";
  p "-- a zero-arg function as soon as it is named and so cannot store one:\n";
  p "-- `unix_time` is `(()) -> Float`, mocked as `fn _ -> 1234.0`.\n";
  List.iter
    (fun cap ->
       p "\n-- %s\n" cap;
       (match excluded_ops cap with
        | [] -> ()
        | ex ->
          p "--   NOT interceptable (polymorphic; a field would need rank-2 types):\n";
          List.iter (fun op -> p "--     %s\n" op) ex);
       match dict_fields cap with
       | [] -> p "--   (no interceptable operations - this capability has no dictionary)\n"
       | flds ->
         p "{\n";
         let n = List.length flds in
         List.iteri
           (fun i (name, t) ->
              let inner = match t with TCon ("Option", [ x ]) -> x | x -> x in
              p "  %s : Option(%s)%s\n" name (march_ty inner) (if i = n - 1 then "" else ","))
           flds;
         p "}\n")
    (all_caps ());
  Buffer.contents b
