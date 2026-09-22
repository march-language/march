(** The one place forge decides whether it may touch the network.

    Every operation that can reach the network — a `git clone`, a registry
    metadata or tarball fetch, compiling the registry client (whose only purpose
    is to make such a fetch), a toolchain download, `npm install` — asks
    [permit] (or runs through [command], which asks it) immediately before it
    starts the process. Under offline mode [permit] refuses, so the guarantee
    "`--offline` starts no network process" is a property of this module rather
    than of every caller remembering an [if offline] check: a new fetch site
    that goes through here is covered automatically, and one that does not is a
    bug a reviewer can see by grepping for the process it starts.

    Offline mode is on when EITHER
    - the global [--offline] flag was given (main.ml strips it from argv before
      command dispatch and calls [set_offline true]), or
    - [FORGE_OFFLINE] is set to a truthy value ([1], [true], [yes], [on]; any
      other non-empty value except [0]/[false]/[no]/[off] also counts).
    There is no config-file setting and no way to force network access on from
    the command line: offline is a restriction, and the two sources only ever
    add it. `specs/2026-09-11-forge-offline-and-versioned-dep-cache-design.md`
    §3 is the contract. *)

let env_var = "FORGE_OFFLINE"

let flag = ref false

(** Called by the CLI when [--offline] is present. *)
let set_offline b = flag := b

(** How [FORGE_OFFLINE]'s value reads. Empty and the usual negatives are off,
    so `FORGE_OFFLINE=0 forge build` behaves like no variable at all. *)
let env_truthy v =
  match String.lowercase_ascii (String.trim v) with
  | "" | "0" | "false" | "no" | "off" -> false
  | _ -> true

let env_offline () =
  match Sys.getenv_opt env_var with
  | Some v -> env_truthy v
  | None -> false

let is_offline () = !flag || env_offline ()

(** Which source turned offline mode on, for messages. *)
let source () =
  if !flag then "--offline"
  else Printf.sprintf "%s=%s" env_var
      (Option.value ~default:"" (Sys.getenv_opt env_var))

(** Test hook: called with a description of every operation the gate
    PERMITS, just before it runs. A test sets it to fail when offline code
    reaches the network, which proves no fetch happened rather than inferring
    it from a successful result. *)
let on_permit : (string -> unit) ref = ref (fun _ -> ())

(** The refusal text. [what] is the operation in the infinitive ("clone depot
    from …"); [remedy] says what would make it unnecessary — normally which
    command, run WITH network access, populates the cache. *)
let refusal ~what ~remedy =
  Printf.sprintf
    "offline (%s): refusing to %s — that needs network access.\n  %s"
    (source ()) what remedy

(** Ask to perform a network operation. [Error msg] under offline mode. *)
let permit ~what ~remedy =
  if is_offline () then Error (refusal ~what ~remedy)
  else begin
    !on_permit what;
    Ok ()
  end

(** [Sys.command cmd] through the gate: [Ok exit_code], or [Error msg]
    without starting anything under offline mode. *)
let command ~what ~remedy cmd =
  match permit ~what ~remedy with
  | Error e -> Error e
  | Ok () -> Ok (Sys.command cmd)

(** Split the global [--offline] flag out of a command line. Returns whether
    it was present and the argv without it. Scanning stops at a bare [--]:
    everything after it belongs to the program `forge run` launches, not to
    forge. [argv.(0)] is never inspected. *)
let extract_flag (argv : string array) : bool * string array =
  let found = ref false in
  let after_dashdash = ref false in
  let kept =
    Array.to_list argv
    |> List.mapi (fun i a -> (i, a))
    |> List.filter (fun (i, a) ->
        if i = 0 || !after_dashdash then true
        else if a = "--" then (after_dashdash := true; true)
        else if a = "--offline" then (found := true; false)
        else true)
    |> List.map snd
  in
  (!found, Array.of_list kept)
