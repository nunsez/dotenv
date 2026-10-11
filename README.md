# dotenv

A strict parser and loader for `.env` files, written in [V](https://vlang.io).

Malformed input is an error, never silently ignored, and nothing is executed or
read implicitly - command substitution is opt-in.

## Install

```sh
v install --git https://github.com/nunsez/dotenv.git
```

## Quick start

```v
import dotenv

fn main() {
	written := dotenv.source_and_export(['.env', '.env.local'])!
	println(written) // keys written to the environment
}
```

`source_and_export` parses the files, merges them (with the OS environment on
top) and writes the result into the process environment (see below).

## File format

- `KEY=value` - unquoted (`#` starts a comment; the value is trimmed)
- `KEY="quoted"` - double quotes: interpolation and escapes
- `KEY='quoted'` - single quotes: everything literal
- `export KEY=value` - repeated `export` prefixes are tolerated
- Escapes: `\n \r \t \f \b \" \' \\ \uXXXX`. Any other `\X` yields `X` (the backslash is dropped).
- `\uXXXX` takes four hex digits and covers the BMP only; surrogate code points such as `\uD800`
  and surrogate pairs like `\uD83D\uDE00` raise a `LoadError` rather than producing invalid
  UTF-8 - write an astral character such as an emoji literally instead
- Heredocs: `KEY=''' ... '''` (raw: no interpolation) and `KEY=""" ... """` (interpolated)
- Interpolation: `"${VAR}"` - resolved from the file itself (only keys defined
  above the reference), and optionally from the OS environment
- Command substitution: `KEY=$(command args)` - executed directly, without a shell

A malformed key (`2BAD=`, `NOT GOOD=`, `SÜPER=`), an unclosed quote, an undefined variable,
a surrogate `\uXXXX` escape or a failed command all raise a `LoadError` instead of being skipped.

## API

### `source(files []string, opts SourceOptions) !map[string]string`

Parses files in order and merges them; the OS environment is merged last and
always wins over file values.

| Option | Default | Meaning |
|--------|---------|---------|
| `precedence` | `.last_wins` | How duplicate keys across files are resolved. With `.first_wins`, the earliest value is kept. |
| `include_env` | `true` | When `false`, skip the OS-environment merge and use only the values read from files. |
| `require_files` | `false` | When `true`, fail if any of the listed files is missing. Otherwise missing files are silently skipped. |
| `allow_commands` | `false` | When `true`, enable command substitution such as `KEY=$(whoami)`. Disabled by default, since parsing must not execute code. |
| `interp_env` | `false` | When `true`, let `${VAR}` fall back to the OS environment when `VAR` is not defined in the file. Parse-time only - does not affect how `source` merges the environment. |

```v
m := dotenv.source(['.env', '.env.local'], precedence: .first_wins, include_env: false)!
```

Within a single file the last assignment to a key wins, and `${VAR}` only sees
keys defined above it. Across files no substitution happens - each file is
parsed independently.

### `export(m map[string]string, opts ExportOptions) []string`

Writes every pair of `m` into the OS environment of the current process and
returns the keys that were actually written (sorted). Existing variables are
left untouched by default, so the real environment wins.

| Option | Default | Meaning |
|--------|---------|---------|
| `overwrite` | `false` | When `true`, replace OS variables that already exist. |

```v
m := dotenv.source(['.env', '.env.local'])!
dotenv.export(m, overwrite: true)
```

### `source_and_export(files []string, opts SourceOptions) ![]string`

A one-call shortcut for `source` followed by `export`: parses `files` and
immediately writes the result into the OS environment, returning the keys that
were actually written (sorted).

```v
written := dotenv.source_and_export(['.env', '.env.local'])!
```

It uses the default `overwrite: false`, so real OS variables always win.
Errors from `source` propagate unchanged. This is an explicit, side-effectful
step - variables become visible to child processes and to `os.environ()`.
Compose `source` and `export` directly when you need `overwrite: true`.

## Tests

```sh
v test .
```
