# March Debugger for VS Code

Debug March programs from VS Code using the interpreter's built-in debugger,
exposed over the Debug Adapter Protocol (DAP).

## Features (v1)

- **Breakpoints** on any source line (gutter clicks).
- **Step over / into / out**, continue, and pause.
- **Call stack** and **Locals** inspection while paused.
- **Evaluate on hover** for in-scope variable names.

## Requirements

The `march` binary must be on your `PATH` (or set `marchPath` in the launch
configuration). The adapter is the binary's `dap` subcommand — the extension
launches `march dap` and speaks DAP to it over stdio.

## Usage

1. Install this extension (during development: open this folder in VS Code and
   press F5, or `vsce package` then install the `.vsix`).
2. Open a `.march` file.
3. Set a breakpoint in the gutter.
4. Run → Start Debugging (F5). With no `launch.json`, the active file is used.

A minimal `launch.json`:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "march",
      "request": "launch",
      "name": "Debug March file",
      "program": "${file}",
      "stopOnEntry": false
    }
  ]
}
```

### Configuration

| Field         | Default   | Description                                   |
| ------------- | --------- | --------------------------------------------- |
| `program`     | `${file}` | Path to the `.march` file to debug.           |
| `stopOnEntry` | `false`   | Stop at the first evaluated expression.       |
| `marchPath`   | `march`   | Path to the `march` binary (`march dap`).     |

## How it works

The debugger runs the program through the March interpreter under a debug
context. A line-breakpoint/step hook in `lib/eval/eval.ml` pauses evaluation; a
DAP server (`lib/dap/`) runs the program on a worker thread and answers protocol
requests on the main thread, rendezvousing through a mutex/condition. This
extension only tells VS Code how to launch the adapter — there is no
TypeScript debug logic to maintain.

## Not yet (v2)

Reverse debugging (the engine already records a full trace — `stepBack` /
`reverseContinue` are a thin DAP mapping away), conditional/hit-count
breakpoints, watch expressions, structured-value expansion in the Variables
pane, and per-actor "threads".
