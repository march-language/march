#!/usr/bin/env bash
# check-explainer.sh: the tests behind docs/protocol-to-cluster.md, the scrolling
# explainer for distributed March (specs/2026-11-05-distributed-explainer-design.md).
#
# Needs python3 and node, and no compiler: the generator's tests run on recorded
# fixtures (test/explainer/fixtures/), and a test that needs the compiler skips itself
# when none is built. doc-lint runs this; so does scripts/affected.sh for a change under
# examples/lab_app, docs/assets/explainer, docs/_data or test/explainer.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== explainer: generator tests =="
python3 test/explainer/test_gen.py

echo "== explainer: script tests =="
node --test test/explainer/*.test.js

echo "explainer checks passed"
