---
layout: docs
title: "migrate_rename_suggested"
permalink: /docs/errors/migrate_rename_suggested/
---

# `migrate_rename_suggested`: a state field may have been renamed since the running version

A warning, given only when the build knows the running version's state (a
forge project's last hot deploy, or `--hcr-baseline`). The actor's state lost
exactly one field and gained exactly one of the same type, and there is no
`migrate` clause. That can be a rename, and a rename needs its data moved:
without a clause the deploy is refused, since the old field's live data would
otherwise be dropped.

## A program that triggers it

Against a running version whose state is `{ count : Int, label : String }`:

```march
mod Main do
  actor Counter do
    state { total : Int, label : String }
    init { total: 0, label: "" }
    on Inc() do { state with total: state.total + 1 } end
  end
  fn main() : Int do 0 end
end
```

## The fix

If `total` is `count` renamed, add the clause the warning proposes. The
compiler then writes the migration (and its proved reverse):

```march
mod Main do
  actor Counter do
    state { total : Int, label : String }
    init { total: 0, label: "" }
    migrate old -> { total: old.count }
    on Inc() do { state with total: state.total + 1 } end
  end
  fn main() : Int do 0 end
end
```

The fix is a guess (tier `maybe-incorrect`): `total` may really be new and
`count` really gone. It is offered in the editor and applied by
`forge fix --only migrate_rename_suggested`, never by plain `forge fix`. If the
old data should be discarded instead, deploy with `forge deploy hot --drop
Counter.count`.

See also: [the Hot Code Reload guide](https://march-lang.org/docs/hot-code-reload/#moving-data-the-migrate-clause).
