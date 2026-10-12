# two-node `control_certs`: "b died" flake was c's post-revocation view

**Symptom.** `scripts/two-node.sh control_certs` failed intermittently with
`two-node[control_certs]: b died` (2026-10-12, `march-ci-ubuntu-step6b`
container, `--cpus 2`, plain build: 2/8 runs on `p1/cert-mode-session-hang`,
3/8 on `p1/session-redial-hang`).

**Cause: the check, not the cluster.** The check after the revocation grepped
`app c: b dead` in `c.out`. Once c's certificates are revoked, a and b drop c's
links and c is cut off; c then legitimately declares a and b dead by SWIM
suspect timeout (`app c: b dead: suspect timeout`). Whether that line lands
before the grep is timing, hence the flake. The check's intent is that b stayed
healthy past its 40 s certificate's expiry, which c's view after it is cut off
says nothing about.

**Fix** (`test/two_node/control_certs/scenario.sh`). The scenario records
`c.out`'s line count just before delivering the revocation; after it, `a.out`
is checked whole (a is still linked to b) and `c.out` only up to that line. The
earlier check past the short certificate's expiry (a and c, before the
revocation) is unchanged.
