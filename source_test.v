module dotenv

import os

// fixture returns the absolute path of a `.env` test fixture.
fn fixture(name string) string {
	return os.join_path(os.dir(@FILE), 'testdata', name)
}

fn test_source_merges_files() {
	a := fixture('a.env')
	b := fixture('b.env')

	m := source([a, b], include_env: false)!
	assert m['A'] == 'second'
	assert m['ONLY_A'] == 'yes'
	assert m['ONLY_B'] == 'yes'
	assert m.len == 3
}

fn test_source_first_wins() {
	a := fixture('a.env')
	b := fixture('b.env')

	m := source([a, b], include_env: false, precedence: .first_wins)!
	assert m['A'] == 'first'
	assert m['ONLY_A'] == 'yes'
	assert m['ONLY_B'] == 'yes'
}

fn test_source_single_file() {
	m := source([fixture('one.env')], include_env: false)!
	assert m['A'] == 'one'
	assert m['B'] == 'two'
	assert m.len == 2
}

fn test_source_empty_file_list() {
	m := source([], include_env: false)!
	assert m.len == 0
}

fn test_source_skips_missing_files_by_default() {
	missing := fixture('missing.env')
	one := fixture('one.env')

	m := source([missing, one], include_env: false)!
	assert m['A'] == 'one'
}

fn test_source_require_files_errors_on_missing() {
	source([fixture('missing.env')], require_files: true) or {
		assert err.msg().contains('File not found')
		return
	}
	assert false
}

fn test_source_propagates_parse_errors() {
	source([fixture('one.env'), fixture('bad.env')]) or {
		assert err.msg().contains('Invalid variable name')
		return
	}
	assert false
}

fn test_source_does_not_interpolate_across_files() {
	source([fixture('a.env'), fixture('interp.env')]) or {
		assert err.msg().contains('variable undefined')
		return
	}
	assert false
}

fn test_source_env_included_by_default_and_wins() {
	os.setenv('FROM_ENV', 'system-val', true)
	defer { os.unsetenv('FROM_ENV') }

	m := source([fixture('conf.env')])!
	assert m['FROM_ENV'] == 'system-val'
	assert m['ONLY_FILE'] == 'yes'
	assert m.len >= 2
}

fn test_source_include_env_beats_files_even_with_first_wins() {
	os.setenv('FROM_ENV', 'system-val', true)
	defer { os.unsetenv('FROM_ENV') }

	m := source([fixture('conf.env')], include_env: true, precedence: .first_wins)!
	assert m['FROM_ENV'] == 'system-val'
}

fn test_source_env_excluded_with_include_env_false() {
	os.setenv('FROM_ENV', 'system-val', true)
	defer { os.unsetenv('FROM_ENV') }

	m := source([fixture('conf.env')], include_env: false)!
	assert m['FROM_ENV'] == 'file-val'
}

fn test_source_interpolation_from_env_disabled_by_default() {
	os.setenv('DOTENV_TEST_ENV_VAR', 'resolved', true)
	defer { os.unsetenv('DOTENV_TEST_ENV_VAR') }

	source([fixture('interp-env.env')], include_env: false) or {
		assert err.msg().contains('variable undefined')
		return
	}
	assert false
}

fn test_source_interpolation_from_env_enabled() {
	os.setenv('DOTENV_TEST_ENV_VAR', 'resolved', true)
	defer { os.unsetenv('DOTENV_TEST_ENV_VAR') }

	m := source([fixture('interp-env.env')], include_env: false, interp_env: true)!
	assert m['X'] == 'resolved'
}

fn test_source_command_substitution_disabled_by_default() {
	source([fixture('cmd.env')]) or {
		assert err.msg().contains('disabled')
		return
	}
	assert false
}

fn test_source_command_substitution_enabled() {
	m := source([fixture('cmd.env')], allow_commands: true, include_env: false)!
	assert m['FOO'] == 'hello'
}
