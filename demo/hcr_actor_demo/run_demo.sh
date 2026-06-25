#!/usr/bin/env bash
# HCR Phase 5 Demo: Actor state migration
#
# Demonstrates that running Counter actors (from counter_v1.march) survive
# a hot reload to counter_v2.march with their count preserved and a new
# history field added — all without restarting.
#
# Prerequisites:
#   - march compiler built: dune build (in the march repo)
#   - A running march server on a remote host with hot-reload configured
#     (see docs/hot-code-reload.md for server setup)
#   - forge.toml with [hot-reload] section (ssh_host, socket, public_key)
#
# Usage:
#   cd <march-project-with-forge.toml>
#   bash path/to/demo/hcr_actor_demo/run_demo.sh

set -euo pipefail

MARCH="${MARCH_BIN:-march}"
DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKDIR="${TMPDIR:-/tmp}/hcr_actor_demo_$$"
mkdir -p "$WORKDIR"
trap "rm -rf $WORKDIR" EXIT

echo "=== HCR Phase 5: Actor State Migration Demo ==="
echo ""

# Step 1: Build v1 as a hot-reload .so
echo "--- Step 1: Building Counter v1 ---"
"$MARCH" "$DEMO_DIR/counter_v1.march" \
    --hot-reload MyApp \
    --compile-so \
    -o "$WORKDIR/counter_v1.so"
echo "Built: $WORKDIR/counter_v1.so"
echo ""

# Step 2: Show v1 schema
if [ -f "$WORKDIR/counter_v1.so.schemas.json" ]; then
    echo "--- v1 schema ---"
    cat "$WORKDIR/counter_v1.so.schemas.json"
    echo ""
fi

# Step 3: Build v2 as a hot-reload .so
echo "--- Step 2: Building Counter v2 ---"
"$MARCH" "$DEMO_DIR/counter_v2.march" \
    --hot-reload MyApp \
    --compile-so \
    -o "$WORKDIR/counter_v2.so"
echo "Built: $WORKDIR/counter_v2.so"
echo ""

# Step 4: Show v2 schema and diff
if [ -f "$WORKDIR/counter_v2.so.schemas.json" ]; then
    echo "--- v2 schema ---"
    cat "$WORKDIR/counter_v2.so.schemas.json"
    echo ""
fi

# Step 5: Check __migrate_Counter is exported
echo "--- Checking migrate symbol export ---"
if nm -D "$WORKDIR/counter_v2.so" 2>/dev/null | grep -q "__migrate_Counter"; then
    echo "✓ __migrate_Counter exported from v2 .so"
else
    echo "⚠ __migrate_Counter not found"
    nm -D "$WORKDIR/counter_v2.so" 2>/dev/null | grep __migrate || true
fi
echo ""

echo "=== Demo build complete ==="
echo ""
echo "To deploy v1 to a running server:"
echo "  forge deploy hot --so $WORKDIR/counter_v1.so"
echo ""
echo "Then deploy v2 (triggers state migration):"
echo "  forge deploy hot --so $WORKDIR/counter_v2.so"
echo ""
echo "Actors will receive MARCH_MIGRATE_TAG messages and call migrate_state"
echo "to upgrade their state from v1 layout to v2 layout — no restart needed."
