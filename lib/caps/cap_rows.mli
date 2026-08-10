(** Per-function capability ROWS — R1 stage C.

    See [specs/2026-08-10-r1-stage-c-effect-rows-design.md]. A row is what a
    function's capability closure becomes once it has to answer for function
    values it did not create:

      {[ row(f) = { caps    : what f's static reach performs
                  ; deps    : f's parameters whose value f may invoke
                  ; unknown : f's reach invokes a value of untraceable origin }
      ]}

    [caps] is EXACTLY the flat transitive closure that shipped with R1 stages
    A/B — [Typecheck.fn_transitive_capability_closures_tbl] is now the caps
    projection of [solve], not a second implementation, so the two cannot
    drift (this codebase's "two-tables-drift" failure mode).

    {2 Why [deps] and [unknown] exist at all}

    The flat closure is already SOUND and precise for first-order code, for a
    reason that is easy to miss: edges come from [free_vars_expr], so a
    parameter contributes no edge (hence [List.map]'s entry is the empty set,
    NOT a union over call sites) and a callback supplied BY NAME is charged to
    the supplier through the supplier's own free-variable edge. Whole-program
    discharge at [main] therefore never needed rows.

    Per-FUNCTION discharge does. [fn worker(cap : Cap(IO.Console), job)]
    invoking [job()] has an empty caps row and would certify as console-only.
    That certification is correct but CONDITIONAL, and the two new components
    say so precisely:

    - [deps] records the conditional part. It is descriptive at discharge
      (never itself an error): the caller that supplies [job] is charged for
      it by the free-variable edge, and that caller is in turn under some
      discharge point on the chain from [main].
    - [unknown] records where the conditional part cannot be discharged by
      anyone, because the invoked value has no traceable creation site — it
      came out of a record field, a ref, a list. A narrow grant over such a
      function is REFUSED rather than granted, the same way stage B refuses
      to certify a narrow grant over [IO.Foreign].

    {2 Why an [ASOpaque] ARGUMENT does not set [unknown]}

    Only invoking an untraceable head sets [unknown]; passing an untraceable
    value to someone else does not. This is deliberate and is what keeps the
    refusal from flooding: any actual INVOCATION of such a value is flagged at
    whichever function performs it, and [unknown] propagates along reference
    edges, so a discharge point that can reach the invoker still gets refused.
    A discharge point that cannot reach the invoker genuinely does not perform
    that invocation within its static reach. Charging every opaque argument
    would instead refuse every function that passes a string to a callback. *)

(** How an argument at one call-site position was written. Only positions the
    callee's row marks as a dep are ever consulted. *)
type arg_shape =
  | ASParams of string list
      (** the argument is (an alias of) these parameters of the CALLER *)
  | ASName of string  (** a name that may resolve to a known function *)
  | ASInline  (** a lambda literal — its body is already charged to the caller *)
  | ASOpaque  (** anything else: a field, an application result, a literal *)

(** What one function's own bodies contribute before the fixpoint. *)
type seed = {
  sd_params : string list;
      (** the owner's parameter names in order, so a call-site position can be
          mapped to the callee's dep names *)
  sd_deps : string list;  (** parameters invoked directly in the owner's body *)
  sd_unknown : bool;
      (** the owner invokes a head whose origin this walk cannot classify *)
  sd_calls : (string * arg_shape list) list;
      (** calls to named callees, with each argument's shape *)
}

val empty_seed : seed

val merge_seed : seed -> seed -> seed
(** Union of both seeds. [sd_params] takes the longer list — clauses of one
    function may differ in arity only through desugar's arity mangling, where
    the longer list is the more informative one. *)

val seed_of_bodies : (string list * March_ast.Ast.expr) list -> seed
(** [seed_of_bodies bodies] classifies each [(params, body)] pair exactly the
    way [Typecheck.record_fn_refs] pairs a clause's parameter names with its
    body. Head classification, in order:

    - a parameter of the owner            → [sd_deps]
    - a lambda literal                    → nothing (its body is walked)
    - a local [let]-bound name            → its RHS's classification
    - any other name                      → an entry in [sd_calls]
    - anything else (field, app result…)  → [sd_unknown]

    A local bound to the result of a named call is treated as ALREADY CHARGED
    rather than opaque: everything reachable from it was charged at the call
    that built it ([let m = map(g)] charges [g] where [g] is supplied), so
    invoking it later adds nothing. *)

(** A solved row. [caps] is lattice-normalized. *)
type row = { caps : string list; deps : string list; unknown : bool }

val empty_row : row

val solve :
  own_caps:(string, string list) Hashtbl.t ->
  refs:(string, string list) Hashtbl.t ->
  seeds:(string, seed) Hashtbl.t ->
  (string, row) Hashtbl.t
(** Fixpoint over the reference graph. [own_caps] seeds [caps], [refs] carries
    both [caps] and [unknown] upward, [seeds] supplies [deps]/[unknown]/calls.

    Passing an empty [seeds] table yields exactly the pre-stage-C flat closure
    in the [caps] projection — that equivalence is the reason this function
    owns the caps fixpoint rather than duplicating it. *)
