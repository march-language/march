(** Running one step on several hosts: the rolling and all-hosts drivers that
    [forge deploy hot] uses, extracted so other commands can use them
    ([forge deploy --plan], [forge host init], the ssh reconciler backend;
    specs/plans/2026-09-21-distributed-authority-and-deploys-plan.md, II.6).

    Both strategies run the hosts one after another. [`All] is named for what
    it does (every host is tried and reported), not for concurrency; the type
    leaves room for a concurrent variant. *)

type host = {
  name : string;
  ssh : string;          (** ssh target, e.g. "root@1.2.3.4" *)
  socket : string;       (** reload socket path on the host *)
  pubkey : string;       (** base64 ed25519 key the host verifies against; "" if none *)
  labels : string list;  (** placement labels: from the topology overlay; none from forge.toml *)
}

(** A host from one [[hot-reload.env]] entry. *)
val of_hot_reload_env : Project.hot_reload_env -> host

(** The single host of a flat [hot-reload] section (named "default"), if it
    names an ssh_host. *)
val of_flat_config : Project.hot_reload_config -> host option

(** The host part of an ssh target: ["root@web-1"] is ["web-1"]. *)
val host_name : string -> string

(** The node name of a pool's host in a topology: ["<pool>-<host name>"]
    (MARCH_NODE_NAME, unique across the cluster as long as a host serves
    one pool, which the ssh backend requires). *)
val node_name : pool:string -> string -> string

(** A host of a topology overlay ([[pool.<p>] hosts = [...]]), with its
    labels, as the ssh backend addresses it: [socket] is the reload socket
    on that host ([Host_layout.socket]), [pubkey] the deploy public key. *)
val of_topology_host :
  pool:string -> socket:string -> pubkey:string -> Topology.host -> host

(** A health gate, asked after a step succeeds on a host; [false] stops a
    rolling run. *)
type health = host -> bool

type strategy =
  [ `Rolling of health
    (** One host at a time; stop at the first failed step or failed health
        gate. Hosts after the stop are skipped and not reported. *)
  | `All
    (** Every host, each reported, whatever the others did. *) ]

(** [run_on ~strategy hosts step] runs [step] on [hosts] in order and returns
    each attempted host with its result. A health-gate failure is reported as
    [Error "health_check_failed"] for that host. [on_skip] is told about each
    host a rolling run skips. *)
val run_on :
  ?on_skip:(host -> unit) ->
  strategy:strategy -> host list -> (host -> ('a, string) result) ->
  (host * ('a, string) result) list
