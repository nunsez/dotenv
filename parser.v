module dotenv

import os

const export_prefix = 'export '

// ParseOptions controls the optional behaviour of the parser.
//
// Because it is marked `@[params]`, options can be passed as field shortcuts,
// e.g. `parse(s, allow_commands: true)`, or omitted entirely.
@[params]
pub struct ParseOptions {
pub:
	// allow_commands enables command substitution, e.g. `KEY=$(whoami)`.
	//
	// Disabled by default: parsing a `.env` file must not execute code. Enable
	// it explicitly only for files you trust, since it runs arbitrary commands
	// with the permissions of the current process.
	allow_commands bool
	// interp_env lets `${VAR}` fall back to the OS environment when the file
	// does not define `VAR` itself. A variable defined in the file always wins
	// over the environment - expressions are evaluated in the file's own
	// scope. This is parse-time expansion only and does not affect how values
	// are merged by `source` (where the environment overrides files).
	interp_env bool
}

// parse parses the contents of a `.env` file into a map of string values.
//
// The parser is strict: any malformed line produces a `LoadError` instead of
// being silently ignored. Values are returned as strings; numbers, booleans and
// other types are left untouched so that no information is lost.
pub fn parse(content string, opts ParseOptions) !map[string]string {
	mut p := Parser{
		data: content.bytes()
		vars: map[string]string{}
		opts: opts
		env:  if opts.interp_env { os.environ() } else { map[string]string{} }
	}

	p.find_key()!

	return p.vars
}

struct Parser {
mut:
	data []u8
	pos  int
	vars map[string]string
	opts ParseOptions
	env  map[string]string
}

fn (p Parser) at_end() bool {
	return p.pos >= p.data.len
}

fn (p Parser) cur() u8 {
	return p.data[p.pos]
}

// peek_str returns up to `n` bytes starting at the current position.
fn (p Parser) peek_str(n int) string {
	if p.pos + n > p.data.len { return '' }

	return p.data[p.pos..p.pos + n].bytestr()
}

// starts_with reports whether the input at the current position begins with
// `s`. Unlike `peek_str(s.len) == s` it does not allocate, so it is safe to
// call on every byte of a value.
fn (p Parser) starts_with(s string) bool {
	if p.pos + s.len > p.data.len { return false }

	for i in 0 .. s.len {
		if p.data[p.pos + i] != s[i] { return false }
	}

	return true
}

// skip_to_line_end advances past the next newline (or to the end of input).
fn (mut p Parser) skip_to_line_end() {
	for !p.at_end() {
		c := p.cur()
		p.pos++
		if c == `\n` { return }
	}
}

// accumulate_rest_of_line consumes the remainder of the current line, treating
// a `#` as the start of a comment. It stops after the newline.
fn (mut p Parser) accumulate_rest_of_line() string {
	mut acc := []u8{}

	for !p.at_end() {
		c := p.cur()

		if c == `\n` {
			p.pos++
			return acc.bytestr()
		}

		if c == `#` {
			p.skip_to_line_end()
			return acc.bytestr()
		}

		acc << c
		p.pos++
	}

	return acc.bytestr()
}

// acc_inner_value collects text up to (and consuming) the `stop` byte and
// returns it trimmed. Used for `${VAR}` and `$(cmd)`.
fn (mut p Parser) acc_inner_value(stop u8) !string {
	mut acc := []u8{}

	for !p.at_end() {
		c := p.cur()

		if c == stop {
			p.pos++
			return acc.bytestr().trim_space()
		}

		acc << c
		p.pos++
	}

	return p.fail('Stop sequence not found: "${stop.ascii_str()}"')
}

fn (p Parser) fail(reason string) IError {
	return error_at(reason, p.data, p.pos)
}

fn (p Parser) fail_at(reason string, pos int) IError {
	return error_at(reason, p.data, pos)
}

// find_key scans for the next key until it reaches an `=`, then parses the
// associated value.
fn (mut p Parser) find_key() ! {
	mut acc := []u8{}
	mut key_start := 0

	for {
		if p.at_end() {
			if acc.bytestr().trim_space() == '' { return }
			return p.fail_at('Invalid syntax: variable missing value', key_start)
		}

		c := p.cur()

		if c == `#` {
			p.pos++
			p.skip_to_line_end()
			acc = []u8{}
			key_start = p.pos
			continue
		}

		if c == `=` {
			key := trim_export_prefix(acc.bytestr()).trim_space()

			if !is_valid_key(key) {
				return p.fail_at('Invalid variable name syntax: "${acc.bytestr()}"', key_start)
			}

			p.pos++
			p.parse_value(key, true, '')!
			acc = []u8{}
			key_start = p.pos
			continue
		}

		if c == `\n` {
			if acc.bytestr().trim_space() == '' {
				p.pos++
				acc = []u8{}
				key_start = p.pos
				continue
			}

			return p.fail_at('Invalid syntax for line. No equals sign for key: "${acc.bytestr()}"', key_start)
		}

		acc << c
		p.pos++
	}
}

// parse_value consumes a value and stores it under `key`.
//
// When `stop` is non-empty the parser is inside a quoted or heredoc value and
// looks for the matching terminator; `interp` controls whether `${}`/`$()`
// interpolation and backslash escapes are applied.
fn (mut p Parser) parse_value(key string, interp bool, stop string) ! {
	mut acc := []u8{}

	for {
		if p.at_end() {
			if stop != '' {
				return p.fail('Could not parse value for "${key}". Stop sequence not found: "${stop}"')
			}

			p.vars[key] = acc.bytestr().trim_space()
			return
		}

		if stop == '' {
			if p.starts_with("'''") || p.starts_with('"""') {
				three := p.peek_str(3)

				if acc.bytestr().trim_space() != '' {
					return p.fail('Key: ${key}: Improper syntax before opening heredoc: "${acc.bytestr()}"')
				}

				p.pos += 3
				rest := p.accumulate_rest_of_line()

				if rest.trim_space() != '' {
					return p.fail('Key: ${key}: heredoc allows only zero or more whitespace characters followed by a new line after ${three}')
				}

				p.parse_value(key, three == '"""', three)!
				return
			}
			c := p.cur()

			if c == `"` {
				if acc.bytestr().trim_space() != '' {
					return p.fail('Improper syntax before opening quote: "${acc.bytestr()}"')
				}

				p.pos++
				p.parse_value(key, true, '"')!
				return
			}

			if c == `'` {
				if acc.bytestr().trim_space() != '' {
					return p.fail('Improper syntax before opening quote: "${acc.bytestr()}"')
				}

				p.pos++
				p.parse_value(key, false, "'")!
				return
			}

			if c == `#` {
				p.skip_to_line_end()
				p.vars[key] = acc.bytestr().trim_space()
				return
			}

			if c == `\n` {
				p.pos++
				p.vars[key] = acc.bytestr().trim_space()
				return
			}
		}

		if stop.len == 3 && p.starts_with(stop) {
			p.pos += 3
			rest := p.accumulate_rest_of_line()

			if rest.trim_space() == '' {
				p.vars[key] = acc.bytestr()
				return
			}

			return p.fail('Invalid syntax following "${stop}": "${rest}"')
		}

		if interp {
			if p.starts_with('\${') {
				p.pos += 2
				name := p.acc_inner_value(`}`)!
				val := p.vars[name] or {
					p.env[name] or {
						return p.fail('Could not interpolate variable \${${name}}: variable undefined.')
					}
				}
				acc << val.bytes()
				continue
			}

			if p.starts_with('$(') {
				p.pos += 2
				inner := p.acc_inner_value(`)`)!
				cmd := parse_cmd_args(inner) or {
					return p.fail('Shell command missing arguments; \$() cannot be empty.')
				}
				out := p.run_command(cmd.cmd, cmd.args)!
				acc << out.bytes()
				continue
			}
		}

		if stop.len == 1 && p.cur() == stop[0] {
			p.pos++
			rest := p.accumulate_rest_of_line()

			if rest.trim_space() == '' {
				p.vars[key] = acc.bytestr()
				return
			}

			return p.fail('Invalid syntax for key ${key} following "${stop}": "${rest}"')
		}

		if interp && p.cur() == `\\` && p.pos + 1 < p.data.len {
			next := p.data[p.pos + 1]
			p.pos += 2

			match next {
				`u` {
					if p.pos + 4 > p.data.len {
						return p.fail('Invalid unicode format for key ${key}: incomplete')
					}

					hex := p.data[p.pos..p.pos + 4].bytestr()
					r := parse_hex4(hex) or {
						return p.fail('Invalid unicode format for key ${key}: \\u${hex}')
					}

					if is_surrogate(r) {
						return p.fail('Invalid unicode format for key ${key}: \\u${hex} is a surrogate code point')
					}

					acc << r.str().bytes()
					p.pos += 4
				}
				else {
					acc << unescape_byte(next)
				}
			}
			continue
		}

		acc << p.cur()
		p.pos++
	}
}

struct Command {
	cmd  string
	args []string
}

// parse_cmd_args splits the inside of `$(...)` into a command and its arguments.
fn parse_cmd_args(s string) ?Command {
	if s == '' { return none }

	parts := split_keep_empty(s, ` `)
	if parts[0] == '' { return none }

	return Command{
		cmd:  parts[0]
		args: parts[1..]
	}
}

// run_command executes a `$(...)` command and returns its trimmed output.
fn (p Parser) run_command(cmd string, args []string) !string {
	if !p.opts.allow_commands {
		return p.fail('Command substitution is disabled; set ParseOptions.allow_commands to true to enable it')
	}

	mut argv := []string{cap: args.len + 1}
	argv << cmd
	argv << args
	res := os.exec(argv)

	if res.exit_code != 0 {
		return p.fail('Command "${cmd}" with args ${args} returned non-zero exit status: ${res.exit_code}')
	}

	return res.output.trim_space()
}

// split_keep_empty splits `s` by `sep`, preserving empty segments.
fn split_keep_empty(s string, sep u8) []string {
	mut out := []string{}
	mut start := 0

	for i in 0 .. s.len {
		if s[i] == sep {
			out << s[start..i]
			start = i + 1
		}
	}

	out << s[start..]

	return out
}

// unescape_byte maps the character following a backslash to the byte it stands
// for. Unknown escapes (including `"`, `'` and `\`) map to the character
// itself, dropping the backslash.
fn unescape_byte(c u8) u8 {
	return match c {
		`n` { u8(`\n`) }
		`r` { u8(`\r`) }
		`t` { u8(`\t`) }
		`f` { u8(`\f`) }
		`b` { u8(`\b`) }
		else { c }
	}
}

// parse_hex4 parses exactly four hexadecimal digits into a rune.
fn parse_hex4(s string) ?rune {
	if s.len != 4 { return none }

	mut value := u32(0)

	for i in 0 .. 4 {
		c := s[i]

		d := match true {
			c >= `0` && c <= `9` { u32(c - `0`) }
			c >= `a` && c <= `f` { u32(c - `a`) + 10 }
			c >= `A` && c <= `F` { u32(c - `A`) + 10 }
			else { return none }
		}

		value = value * 16 + d
	}

	return rune(value)
}

// is_surrogate reports whether `r` is a UTF-16 surrogate code point. Such code
// points are not valid Unicode scalar values and cannot be encoded as UTF-8,
// so a `\uXXXX` escape that decodes to one is rejected instead of silently
// producing an invalid UTF-8 string.
fn is_surrogate(r rune) bool {
	return r >= 0xD800 && r <= 0xDFFF
}

// trim_export_prefix removes any leading `export ` markers.
fn trim_export_prefix(s string) string {
	mut r := s

	for r.starts_with(export_prefix) {
		r = r[export_prefix.len..]
	}

	return r
}

// is_valid_key reports whether `key` matches `[a-zA-Z_][a-zA-Z0-9_]*`.
fn is_valid_key(key string) bool {
	if key == '' { return false }

	first := key[0]
	if !(is_alpha(first) || first == `_`) { return false }

	for i in 1 .. key.len {
		c := key[i]
		if !(is_alpha(c) || is_digit(c) || c == `_`) { return false }
	}

	return true
}

fn is_alpha(c u8) bool {
	return (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`)
}

fn is_digit(c u8) bool {
	return c >= `0` && c <= `9`
}
