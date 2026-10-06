(** Client for a node's observe socket ([runtime/march_observe.c]).

    One request line out, one line of JSON back, then the node closes the
    connection.  Every reply is an envelope
    [{"proto":"march.observe/1","node":…,"at_ms":…,"took_us":…,"truncated":…,
      "data":…}], or the same with ["error":"<code>"] in place of [data].

    The observe socket sits beside the host's reload socket at
    ["<socket>.observe"] (the default the runtime derives when only
    [MARCH_HOT_RELOAD_SOCKET] is set), so the same [Remote] transport reaches
    it: a local path directly, or the remote path through an ssh tunnel.

    R0 of specs/plans/2026-09-28-observe-recon-shell-plan.md. *)

let protocol = "march.observe/1"

(** The observe socket that sits beside [h]'s reload socket. *)
let socket_of (h : Hosts.host) : string = h.Hosts.socket ^ ".observe"

(** Parse one reply line.  [Error] for anything that is not an observe
    envelope, and for an envelope carrying ["error"] (its code, e.g.
    ["observe: busy"]). *)
let parse_reply (line : string) : (Yojson.Safe.t, string) result =
  match Yojson.Safe.from_string line with
  | exception Yojson.Json_error m -> Error ("observe: malformed reply: " ^ m)
  | `Assoc fields as reply ->
    (match List.assoc_opt "proto" fields with
     | Some (`String p) when p = protocol ->
       (match List.assoc_opt "error" fields with
        | Some (`String code) -> Error ("observe: " ^ code)
        | Some _ -> Error "observe: malformed error field"
        | None -> Ok reply)
     | Some (`String p) -> Error ("observe: unsupported protocol " ^ p)
     | _ -> Error "observe: reply has no protocol field")
  | _ -> Error "observe: reply is not a JSON object"

(** The [data] member of a parsed reply ([`Null] if absent or truncated). *)
let data_of (reply : Yojson.Safe.t) : Yojson.Safe.t =
  match reply with
  | `Assoc fields -> (match List.assoc_opt "data" fields with Some d -> d | None -> `Null)
  | _ -> `Null

(** True when the node reported that the data did not fit and was dropped. *)
let truncated (reply : Yojson.Safe.t) : bool =
  match reply with
  | `Assoc fields -> List.assoc_opt "truncated" fields = Some (`Bool true)
  | _ -> false

let single_line request =
  if String.contains request '\n' || String.contains request '\r' then
    Error "observe: a request is a single line"
  else Ok ()

let exchange request conn =
  Cmd_deploy_hot.send_line conn request;
  parse_reply (Cmd_deploy_hot.recv_line conn)

(** Send [request] (a verb and its arguments, one line) to [h]'s observe
    socket over [transport] and return the parsed reply. *)
let query (transport : Remote.transport) (h : Hosts.host) (request : string)
  : (Yojson.Safe.t, string) result =
  match single_line request with
  | Error _ as e -> e
  | Ok () ->
    transport.Remote.with_socket { h with Hosts.socket = socket_of h } (exchange request)

(** [query] against an observe socket on this machine, by its own path
    (MARCH_OBSERVE_SOCKET), not derived from a reload socket. *)
let query_socket (path : string) (request : string) : (Yojson.Safe.t, string) result =
  match single_line request with
  | Error _ as e -> e
  | Ok () -> Remote.use_socket path (exchange request)

(* ── Signed debug requests (R4) ──────────────────────────────────────── *)

(** How long a signed debug request stays valid.  The node refuses one whose
    [not_after_ms] has passed or is more than 60 s ahead of its own clock, so
    this tolerates up to 30 s of clock skew either way. *)
let debug_window_ms = 30_000

(** [signed_request ~sk ~nonce ~now_ms verb fields]: the request line for a
    debug verb, e.g. [STATE <sig> nonce:… not_after_ms:… pid:7].  The
    signature covers the line without its signature word, which is what
    runtime/march_observe_debug.c verifies.  Pure, for tests. *)
let signed_request ~(sk : bytes) ~(nonce : string) ~(now_ms : int)
    (verb : string) (fields : string list) : string =
  let body =
    String.concat " "
      (Printf.sprintf "nonce:%s" nonce
       :: Printf.sprintf "not_after_ms:%d" (now_ms + debug_window_ms)
       :: fields) in
  let sig_b64 =
    March_ed25519.Ed25519.sig_to_base64
      (March_ed25519.Ed25519.sign_str (verb ^ " " ^ body) sk) in
  Printf.sprintf "%s %s %s" verb sig_b64 body

(** 16 random bytes as hex: unique per request, which is all a nonce needs. *)
let fresh_nonce () : string =
  let ic = open_in_bin "/dev/urandom" in
  let b = really_input_string ic 16 in
  close_in ic;
  String.concat "" (List.init 16 (fun i -> Printf.sprintf "%02x" (Char.code b.[i])))

(** A debug verb's refusal, said in words an operator can act on. *)
let explain_debug_error (m : string) : string =
  let code =
    match String.rindex_opt m ':' with
    | Some i -> String.trim (String.sub m (i + 1) (String.length m - i - 1))
    | None -> m in
  match code with
  | "signing_not_configured" ->
    m ^ " (the node was not built with --hot-reload and --signing-pubkey, so it accepts no debug request)"
  | "bad_signature" -> m ^ " (the node's key is not this machine's ~/.march/ed25519_secret.key)"
  | "expired" -> m ^ " (the node's clock is more than 30 s ahead of this machine's)"
  | "not_after_too_far" -> m ^ " (the node's clock is more than 30 s behind this machine's)"
  | "policy" -> m ^ " (the verb is not listed in the node's $MARCH_DEBUG_POLICY file)"
  | "replay" -> m ^ " (the node has already seen this request's nonce)"
  | _ -> m
