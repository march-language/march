(** Named switches for the OPTIONAL TIR passes (A4: [--disable-pass],
    [--bisect-pass]).

    Every pass named here runs only under [opt] in {!Contract_pipeline.run},
    so [--no-opt] already proves that skipping all of them yields a correct
    program; skipping any one of them is the same promise, narrower.  The
    mandatory passes (lower, TRMC, mono, defun, Perceus, drop, escape, the
    pre-emit rewrites) have no switch: a build without them is not a March
    build.  [opt.<p>] names one pass of {!Opt}'s fixed-point loop; [opt]
    names the whole loop.

    The disabled set is part of the CAS key ([cas_tag], read by the driver):
    a build with a pass off must never be satisfied by a cached build with it
    on, or the bisector would be measuring the cache. *)

let known : (string * string) list = [
  "fusion",          "Fusion.run: list map/filter/fold chain fusion (pre-defun)";
  "nativearr-fusion","Fusion.run_nativearr: NativeArray map chain fusion";
  "hof-spec",        "Hof_spec: higher-order specialisation and its unboxed redirect";
  "known-call-pre",  "Known_call before Perceus";
  "beta-adt-pre",    "Beta_adt: case-of-known-constructor before Perceus";
  "join-points-pre", "Join_points.run_pre: let-floating before Perceus";
  "simplify-pre",    "Simplify before Perceus";
  "opt",             "the whole post-Perceus Opt fixed-point loop";
  "opt.join-points", "Opt loop: Join_points";
  "opt.known-call",  "Opt loop: Known_call";
  "opt.inline",      "Opt loop: Inline";
  "opt.single-use-inline", "Opt loop: Single_use_inline";
  "opt.cprop",       "Opt loop: constant propagation";
  "opt.fold",        "Opt loop: constant folding";
  "opt.simplify",    "Opt loop: Simplify";
  "opt.fusion",      "Opt loop: record-update fusion";
  "opt.dce",         "Opt loop: dead-code elimination";
]

(** In pipeline order: the order [--bisect-pass] reports in. *)
let names = List.map fst known

let disabled : string list ref = ref []

(** Replace the disabled set.  [Error] names every unknown pass. *)
let set (ps : string list) : (unit, string) result =
  let ps = List.sort_uniq compare (List.filter (fun s -> s <> "") ps) in
  match List.filter (fun p -> not (List.mem_assoc p known)) ps with
  | [] -> disabled := ps; Ok ()
  | bad ->
    Error (Printf.sprintf "unknown pass%s %s (known: %s)"
             (if List.length bad > 1 then "es" else "")
             (String.concat ", " bad) (String.concat ", " names))

(** [MARCH_DISABLE_PASS=a,b], read once by the driver. *)
let of_env () =
  match Sys.getenv_opt "MARCH_DISABLE_PASS" with
  | None | Some "" -> Ok ()
  | Some s -> set (String.split_on_char ',' s)

let split_list s = List.map String.trim (String.split_on_char ',' s)

let on (name : string) = not (List.mem name !disabled)

let cas_tag () =
  match !disabled with [] -> None | ps -> Some ("nopass:" ^ String.concat "," ps)
