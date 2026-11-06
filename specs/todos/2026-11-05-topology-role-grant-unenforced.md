# A role served through a topology file is not checked against its grant

`role R needs ...` is enforced by a walk from each call of a `<P>_Run` entry point
(`check_role_grants`, `lib/typecheck/typecheck.ml`). For a role bound in a topology file's
`[roles]` it reports nothing, for two independent reasons.

1. **The roots are not found.** `role_front_of` recognises `run_`, `cluster_`, `offer_`,
   `initiate_`, `host_`, `offer_hosted_` and `cluster_hosted_`. The generated `main` calls
   `offer_work_<R>` and `offer_work_hosted_<R>` (since "enter compatible work epochs for
   generated service callbacks"); `offer_work_Stock` matches `offer_` as a role named
   `work_Stock`, which has no grant line, so the call is skipped. The same omission empties
   `--dump-role-authority` for these roles, and with it the hot-deploy manifest's `ROLE`
   lines.
2. **The diagnostics are dropped.** With the two prefixes added the roots are found and
   `role_grant_exceeded` is raised, but its span is in the generated `main` (file
   `<topology>`), and `user_diag` in `bin/main.ml` filters that file on purpose: the root's
   reach includes the pool hook's, through the `topology_env` closure the body captures
   (`Topology.hook`), which is not the role's code and not the author's to fix.

Reproduction, on `examples/lab_app`: `Order.Stock` is granted `IO.Mut`. Add
`File.write("/tmp/x", "y")` to `LabApp.Work.stock` and `needs IO.FileWrite` to `mod Work`;
`march --check --topology .forge/topology.json src/lab_app.march` exits 0. With the
prefixes added, `--dump-role-authority` shows `Order.Stock` reaching `IO.FileWrite` and the
check still exits 0.

What a fix has to settle:

- separate the role body's own reach from what it captures from the hook, so the error can
  be raised without the noise the filter exists to hide (the report already prints the two
  apart: `reaches` and `closures`);
- give the error a span in the author's file (the `body = "M.f"` function, or the `[roles]`
  entry) instead of the generated `main`;
- what adding the roots does to the hot-deploy manifest and the role policy gate
  (`test/two_node/hcr_role_policy`) before turning it on.

Not a hidden write: the module must still declare `needs IO.FileWrite`, and the pool's
derived capabilities include it. What goes unenforced is the per-role line.
