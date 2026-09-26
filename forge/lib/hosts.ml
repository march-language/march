(* Multi-host step drivers. See hosts.mli. *)

type host = {
  name : string;
  ssh : string;
  socket : string;
  pubkey : string;
  labels : string list;
}

let of_hot_reload_env (e : Project.hot_reload_env) =
  { name = e.Project.hre_name; ssh = e.Project.hre_ssh_host;
    socket = e.Project.hre_socket;
    pubkey = Option.value ~default:"" e.Project.hre_public_key; labels = [] }

let of_flat_config (hr : Project.hot_reload_config) =
  if hr.Project.hr_ssh_host = "" then None
  else Some { name = "default"; ssh = hr.Project.hr_ssh_host;
              socket = hr.Project.hr_socket;
              pubkey = Option.value ~default:"" hr.Project.hr_public_key; labels = [] }

let host_name target =
  match String.index_opt target '@' with
  | Some i -> String.sub target (i + 1) (String.length target - i - 1)
  | None -> target

let node_name ~pool target = pool ^ "-" ^ host_name target

let of_topology_host ~pool ~socket ~pubkey (h : Topology.host) =
  { name = node_name ~pool h.Topology.host; ssh = h.Topology.host; socket; pubkey;
    labels = h.Topology.labels }

type health = host -> bool

type strategy = [ `Rolling of health | `All ]

let default_on_skip h = Printf.printf "  skipping %s (prior step failed)\n%!" h.ssh

let run_on ?(on_skip = default_on_skip) ~(strategy : strategy) hosts step =
  match strategy with
  | `All -> List.map (fun h -> (h, step h)) hosts
  | `Rolling healthy ->
    let rec go acc = function
      | [] -> List.rev acc
      | h :: rest ->
        match step h with
        | Error _ as r -> List.iter on_skip rest; List.rev ((h, r) :: acc)
        | Ok _ as r ->
          if healthy h then go ((h, r) :: acc) rest
          else begin
            List.iter on_skip rest;
            List.rev ((h, Error "health_check_failed") :: acc)
          end
    in
    go [] hosts
