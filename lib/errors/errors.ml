(** March error reporting.

    Errors carry provenance (source spans) and are designed
    to produce clear, non-cascading diagnostics with
    expected-vs-found framing. *)

type severity = Error | Warning | Hint [@@deriving show]

type diagnostic = {
  severity : severity;
  span : March_ast.Ast.span;
  message : string;
  labels : label list;     (** Additional labeled source spans *)
  notes : string list;      (** Extra context / suggestions *)
}
[@@deriving show]

and label = {
  lbl_span : March_ast.Ast.span;
  lbl_message : string;
}
[@@deriving show]

(** Accumulator for diagnostics — allows error recovery. *)
type ctx = { mutable diagnostics : diagnostic list }

let create () = { diagnostics = [] }

let report ctx diag = ctx.diagnostics <- diag :: ctx.diagnostics

let error ctx ~span message =
  report ctx
    { severity = Error; span; message; labels = []; notes = [] }

let warning ctx ~span message =
  report ctx
    { severity = Warning; span; message; labels = []; notes = [] }

let hint ctx ~span message =
  report ctx
    { severity = Hint; span; message; labels = []; notes = [] }

let has_errors ctx =
  List.exists (fun d -> d.severity = Error) ctx.diagnostics

let has_diagnostics ctx = ctx.diagnostics <> []

let has_hints ctx =
  List.exists (fun d -> d.severity = Hint) ctx.diagnostics

let sorted ctx =
  List.sort
    (fun a b ->
      let c = compare a.span.start_line b.span.start_line in
      if c <> 0 then c else compare a.span.start_col b.span.start_col)
    ctx.diagnostics
