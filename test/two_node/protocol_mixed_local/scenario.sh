# One-node scenario "protocol_mixed_local" (distributed-deploys build step
# 9): sessions mixing two versions of a protocol, formed by access points on
# one ClusterNode, before the network version (protocol_evolve). node_a is
# version 2 of `Order`, compiled against the baseline version 1 writes
# (`--emit-protocols`), so its `Order_Msg.compat()` has Buyer accepting
# version 1. See node_a.march for the six cases.
mkdir -p "$work/base"
cp "$dir/v1.march" "$work/v1.march"
"$MARCH" --check --emit-protocols "$work/base" "$work/v1.march" > "$work/v1.log" 2>&1 \
  || { cat "$work/v1.log" >&2; fail "v1.march did not check"; }
COMPILE_FLAGS_a="--protocol-baseline $work/base/Order.json"
ORDERED=1
start_node a
wait_exit a
