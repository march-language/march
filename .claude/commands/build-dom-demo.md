---
description: Compile dom_demo to JS with forge and copy runtimes
allowed-tools: Bash
---

# Build DOM Demo

Compile `demo_app/dom_demo` to JavaScript using `forge build --target=js` (with the
dev march binary from `dune build`), then copy the runtimes alongside `index.html`
so the page works in a browser.

## Steps

Run `bash demo_app/dom_demo/build.sh` from the march repo root. The script:
1. Runs `dune build` to build dev march/forge binaries
2. Creates a temporary `march` wrapper script that sets `MARCH_STDLIB` explicitly
   (a symlink won't work — macOS `Sys.executable_name` follows symlinks but
    `find_stdlib_dir` would search from the wrong directory)
3. Calls `forge build --target=js` with the wrapper on PATH
4. Copies `dom_demo.mjs`, `march_runtime.mjs`, and `march_dom.mjs` into the demo dir

```bash
bash demo_app/dom_demo/build.sh
```

Then report success and remind the user to open `demo_app/dom_demo/index.html`.

$ARGUMENTS
