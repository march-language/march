# Code Formatter (`march fmt`)

## Overview

March includes a built-in source code formatter invoked as `march fmt`. It reformats `.march` source files in-place to a canonical style, similar to `gofmt` or `mix format`. A `--check` flag enables CI enforcement without modifying files.

## Implementation Status

**Complete.** Formatter is implemented and integrated into the compiler CLI.

**Implementation:** `lib/format/format.ml`, `bin/main.ml` (subcommand dispatch at lines ~430–445)

## Usage

```sh
# Format files in-place
march fmt file.march other.march

# Check formatting without modifying (exit 1 if any file differs)
march fmt --check file.march

# Format before compiling (--fmt flag on any compile invocation)
march --fmt file.march
```

## Architecture

The formatter is a **pretty-printer over the parsed AST**. It:

1. Parses the source with the full March parser
2. Rebuilds the source from the AST using a canonical layout algorithm
3. Writes the result back if it differs from the original

If parsing fails (syntax error), formatting is skipped and the original file is left unchanged.

### Key Files

| File | Purpose |
|---|---|
| `lib/format/format.ml` | Core formatter: `format_source ~filename src -> string` |
| `lib/format/dune` | Build target for the `march_format` library |
| `bin/main.ml:179–264` | `fmt_file` helper + `march fmt` subcommand implementation |

### Subcommand Dispatch (`bin/main.ml:430–445`)

The `march fmt` subcommand is detected before `Arg.parse` runs so it can handle variable-length file lists:

```ocaml
(* Handle "march fmt [--check] <targets...>" as a subcommand *)
if argv.(1) = "fmt" then begin
  let check_only = ... in
  let files = ... in
  List.iter (fun f ->
    let changed, formatted = fmt_file f in
    if check_only then (if changed then (eprintf "%s: not formatted\n" f; exit 1))
    else if changed then (write_file f formatted; printf "formatted %s\n" f)
  ) files;
  exit 0
end
```

## Formatting Rules

- `do ... end` blocks are indented 2 spaces
- Match arms: `| Pat -> body` — one arm per line, indented to align with `|`
- Function definitions: signature on one line when it fits; body indented
- Pipes `|>` kept at start of continuation line
- Trailing whitespace removed; single trailing newline

## Integration with `--fmt` Flag

Passing `--fmt` to any compile invocation formats the file before compiling:

```sh
march --fmt file.march   # format then compile
```

This enables editor integrations (e.g. format-on-save hooks) that just call the compiler.
