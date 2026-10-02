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
