`[P3]` Hot reload: unload a reclaimed patch image once nothing points into it

Follow-up to `specs/progress/2026-10-13-hcr-reclaimed-patch-unmaps-live-closure-code.md`.

## Now

A reclaimed version's `.so` is never dlclosed (`march_dispatch_retain_image`,
runtime/march_dispatch.c): its closures, immortal statics and closure-drop
table entries (`march_clo_register_drops`) may still point into it, and
nothing counts them. So a long-lived node keeps one mapped image per deploy
until restart. `march_dispatch_retained_images()` counts the retained handle
references.

## To unload safely, all of these are needed

- Pin per closure: a per-image count of live closures whose apply lives in
  that image, bumped at allocation by patch code and dropped when the cell is
  freed, including through the generic `march_decrc` path, which does not know
  the cell is a closure. It must cost nothing in a build without `--hot-reload`.
- The image's other escapes: string literals and other immortal statics it
  returned (`MARCH_RC_IMMORTAL` cells in its data), actor dispatch trampolines,
  migrate functions kept for older epochs (`keep_for_older`).
- Remove its keys from the closure-drop table and the record shape-drop
  registry on unload, under the registry's lock-free lookup rules (an old
  table is never freed today).

Until then, a restart is the way to reclaim the memory. Only worth doing if a
node's deploy count makes the mapped size matter.
