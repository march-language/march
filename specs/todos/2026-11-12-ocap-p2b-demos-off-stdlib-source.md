# Move the cluster demos off `--stdlib-source` (2026-11-12)

Ocap phase 2b, task 9 follow-up. The seven `demo/dune` programs (`hcr_server`, `hcr_client`, `load_server`, `load_client`, `two_node_server`, `two_node_client`, `two_node_rpc`) drive the raw-fd cluster plumbing (`NodeCall`, `NetKernel`, `ClusterConn`, ...) by hand, so task 9 compiled them with `--stdlib-source`. They are demos for users: they should show the supported API. Port them to `ClusterNode` and the typed node/session APIs and drop the flag from `demo/dune` (and from the patch compile in `scripts/rpc/hot-deploy.sh`).
