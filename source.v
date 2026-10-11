module dotenv

import os

// Precedence controls how duplicate keys are resolved when sourcing multiple
// files.
pub enum Precedence {
	// last_wins means later files override earlier ones for duplicate keys.
	// This is the default.
	last_wins
	// first_wins means the value of the earliest file is kept.
	first_wins
}

// SourceOptions controls how `source` reads and merges multiple `.env` files.
//
// Because it is marked `@[params]`, options can be passed as field shortcuts,
// e.g. `source(files, include_env: false)`, or omitted entirely.
@[params]
pub struct SourceOptions {
pub:
	// allow_commands is passed through to `parse` for every file;
	// see `ParseOptions`. Disabled by default.
	allow_commands bool
	// interp_env is passed through to `parse` for every file; see
	// `ParseOptions.interp_env`. Disabled by default.
	interp_env bool
	// precedence decides which file wins for a duplicated key.
	precedence Precedence = .last_wins
	// require_files makes `source` fail if any of the listed files is missing.
	// When false (the default), missing files are skipped.
	require_files bool
	// include_env merges the OS environment after all files. System variables
	// always take precedence over file values, regardless of `precedence`
	// (which only arbitrates file-vs-file conflicts) - the usual dotenv
	// contract that real environment overrides `.env` defaults.
	// Enabled by default; set `false` to read the files only.
	include_env bool = true
}

// source parses a list of `.env` files and merges them into a single map.
//
// Files are processed in order. Every file is parsed independently with
// `parse`, so `${VAR}` inside one file can only reference keys defined in that
// same file. With the default `last_wins` precedence later files override
// earlier ones for duplicate keys, while `first_wins` keeps the value of the
// earliest file. Missing files are skipped unless `require_files` is set;
// parse errors from existing files are never silenced.
//
// The OS environment is always merged last (see `SourceOptions.include_env`),
// so system variables win over file values. Use `include_env: false` to read
// the listed files only, without merging the environment.
pub fn source(files []string, opts SourceOptions) !map[string]string {
	mut acc := map[string]string{}

	for f in files {
		if !os.exists(f) {
			if opts.require_files {
				return SourceError{
					reason: 'File not found: "${f}"'
				}
			}
			continue
		}

		content := os.read_file(f) or {
			return SourceError{
				reason: 'Failed to read file: "${f}": ${err.msg()}'
			}
		}
		m := parse(content, allow_commands: opts.allow_commands, interp_env: opts.interp_env)!
		merge_into(mut acc, m, opts.precedence)
	}

	if opts.include_env {
		merge_into(mut acc, os.environ(), .last_wins)
	}

	return acc
}

fn merge_into(mut acc map[string]string, m map[string]string, p Precedence) {
	for k, v in m {
		if p == .first_wins && k in acc { continue }

		acc[k] = v
	}
}
