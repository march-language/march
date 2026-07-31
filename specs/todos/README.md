# Open TODOs

One file per open item: `YYYY-MM-DD-slug.md`, where the date is when the item
was filed (not when it will be worked). This replaced a single monolithic
`specs/todos.md` that every PR touching any todo had to edit at the same spot,
which produced constant merge conflicts and a file too large to read cheaply.

- `ls specs/todos` for the full list; `grep -rl P0 specs/todos` for a priority.
- Items originally tracked in the old P0–P4 priority buckets keep a
  `` `[P0]` ``…`` `[P4]` `` tag as the first token of the file, so priority is
  still greppable even without the old bucket headings.
- When an item is finished, **move** the file into `specs/progress/` (`git mv`)
  rather than copying — a todo has exactly one lifecycle stage.
- File one item per file. If a PR resolves an item, delete or move its file in
  the same commit; don't leave stale open files behind.

See `specs/progress/README.md` for the completed-work log and root `CHANGELOG.md`
for the user-facing release digest.
