(** Where things live on a host the ssh backend manages (distributed-deploys
    plan, section 5 "Host setup"; build step 10b). [forge host init] creates
    this layout; the ssh reconciler backend and [forge deploy] use it. One
    project per [/opt/march/<project>], one systemd unit per pool.

    {v
    /opt/march/<project>/<binary>            the base build (one per build: shared, or an isolated pool's)
    /var/lib/march/<project>/                HOME of the service: $HOME/.march/cas is the CAS root,
                                             which holds the persisted patch stack (hcr_state/, plan 6.5)
    /var/lib/march/<project>/run/<pool>.sock the reload socket (MARCH_HOT_RELOAD_SOCKET)
    /var/lib/march/<project>/run/<pool>.status  what the node reports (MARCH_TOPOLOGY_STATUS)
    /etc/march/<project>/topology.json       the digest (MARCH_TOPOLOGY_FILE; SIGHUP re-reads it)
    /etc/march/<project>/<pool>.env          secrets (the cluster secret), mode 0640 root:march
    /etc/march/<project>/<pool>.policy       the node's capability policy (MARCH_DEPLOY_POLICY)
    /etc/march/<project>/deploy.pub          the deploy public key (the binary embeds its own copy)
    /etc/march/<project>/certs/<node>.{cert,key}, operator.pub   certificate mode (step 11a)
    /etc/march/<project>/firewall-<pool>.sh  the ufw rules generated from the connectivity graph
    /etc/systemd/system/march-<pool>.service the unit, from forge/templates/topology/systemd.service.tmpl
    v}

    [prefix] relocates every path under a directory: the forge tests run
    the host-init script against a scratch directory on this machine. *)

type t = { prefix : string; project : string }

let make ?(prefix = "") project = { prefix; project }

let user = "march"

let p l path = l.prefix ^ path

let code_dir l = p l ("/opt/march/" ^ l.project)
let state_dir l = p l ("/var/lib/march/" ^ l.project)
let run_dir l = state_dir l ^ "/run"
let etc_dir l = p l ("/etc/march/" ^ l.project)
let cert_dir l = etc_dir l ^ "/certs"

let socket l pool = run_dir l ^ "/" ^ pool ^ ".sock"
let status_file l pool = run_dir l ^ "/" ^ pool ^ ".status"
let topology_file l = etc_dir l ^ "/topology.json"
let env_file l pool = etc_dir l ^ "/" ^ pool ^ ".env"
let policy_file l pool = etc_dir l ^ "/" ^ pool ^ ".policy"
let deploy_pub l = etc_dir l ^ "/deploy.pub"
let firewall_file l pool = etc_dir l ^ "/firewall-" ^ pool ^ ".sh"
let cert_file l node = cert_dir l ^ "/" ^ node ^ ".cert"
let key_file l node = cert_dir l ^ "/" ^ node ^ ".key"
let operator_pub l = cert_dir l ^ "/operator.pub"

let unit_name pool = "march-" ^ pool ^ ".service"
let unit_file l pool = p l ("/etc/systemd/system/" ^ unit_name pool)

(** The base build a pool runs: the shared build, or an isolated pool's own
    (the name [Topology.Gen.binary_name] gives the systemd generator). *)
let binary l ~binary_name = code_dir l ^ "/" ^ binary_name
