module dotenv

import os

// ExportOptions controls how `export` writes into the OS environment.
@[params]
pub struct ExportOptions {
pub:
	// overwrite decides whether an OS variable that already exists in the
	// environment is replaced. It is false by default, so the real
	// environment wins - the usual dotenv contract.
	// Because the output of `source` already reflects the OS environment
	// (see `SourceOptions.include_env`), exporting it with the default is
	// idempotent: real variables keep their value and only missing ones are
	// added. Set `overwrite: true` only when you deliberately want a map to
	// win over the environment, e.g. one produced with `include_env: false`.
	overwrite bool
}

// source_and_export parses `files` with `source` and immediately writes the
// result into the OS environment, returning the keys that were actually
// written (sorted).
//
// It is a shortcut for
//
//	m := source(files, opts)!
//	export(m)
//
// i.e. it combines `SourceOptions` with the default export behaviour: real OS
// variables are never overwritten (see `ExportOptions.overwrite` - compose
// `source` and `export` directly when you need `overwrite: true`).
//
// This mutates the environment of the current process; errors from `source`
// propagate unchanged.
pub fn source_and_export(files []string, opts SourceOptions) ![]string {
	m := source(files, opts)!

	return export(m)
}

// export sets all key/value pairs of `m` into the OS environment of the
// current process and returns the keys that were actually written (sorted).
//
// This is an explicit, deliberate step with side effects: the variables
// become visible to `os.exec` children and to any code reading `os.environ()`.
// `parse` and `source` themselves stay pure.
//
// By default an existing OS variable is left untouched. Empty-string values
// are written as-is (`FOO=` yields an empty but set variable); a variable
// that is already set to an empty string still counts as "existing".
pub fn export(m map[string]string, opts ExportOptions) []string {
	mut written := []string{}
	env := os.environ()

	for k, v in m {
		if !opts.overwrite && k in env { continue }
		os.setenv(k, v, true)
		written << k
	}

	written.sort()

	return written
}
