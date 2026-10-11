module dotenv

import os

// fixture returns the absolute path of a `.env` test fixture.
fn fixture(name string) string {
	return os.join_path(os.dir(@FILE), 'testdata', name)
}

fn test_export_sets_variables() {
	os.unsetenv('DOTENV_EXPORT_TEST_1')
	os.unsetenv('DOTENV_EXPORT_TEST_2')
	defer { os.unsetenv('DOTENV_EXPORT_TEST_1') }
	defer { os.unsetenv('DOTENV_EXPORT_TEST_2') }

	before := export({
		'DOTENV_EXPORT_TEST_1': 'one'
		'DOTENV_EXPORT_TEST_2': 'two'
	})
	assert os.getenv('DOTENV_EXPORT_TEST_1') == 'one'
	assert os.getenv('DOTENV_EXPORT_TEST_2') == 'two'
	assert before == ['DOTENV_EXPORT_TEST_1', 'DOTENV_EXPORT_TEST_2']
}

fn test_export_skips_existing_by_default() {
	os.setenv('DOTENV_EXPORT_TEST_3', 'real', true)
	defer { os.unsetenv('DOTENV_EXPORT_TEST_3') }

	written := export({
		'DOTENV_EXPORT_TEST_3': 'file'
	})
	assert written == []
	assert os.getenv('DOTENV_EXPORT_TEST_3') == 'real'
}

fn test_export_overwrite_true() {
	os.setenv('DOTENV_EXPORT_TEST_4', 'real', true)
	defer { os.unsetenv('DOTENV_EXPORT_TEST_4') }

	written := export({
		'DOTENV_EXPORT_TEST_4': 'file'
	}, overwrite: true)
	assert written == ['DOTENV_EXPORT_TEST_4']
	assert os.getenv('DOTENV_EXPORT_TEST_4') == 'file'
}

fn test_export_existing_empty_value_counts_as_present() {
	os.setenv('DOTENV_EXPORT_TEST_5', '', true)
	defer { os.unsetenv('DOTENV_EXPORT_TEST_5') }

	written := export({
		'DOTENV_EXPORT_TEST_5': 'file'
	})
	assert written == []
	assert os.getenv('DOTENV_EXPORT_TEST_5') == ''
}

fn test_export_mixed_existing_and_new() {
	os.setenv('DOTENV_EXPORT_TEST_6', 'real', true)
	defer { os.unsetenv('DOTENV_EXPORT_TEST_6') }
	defer { os.unsetenv('DOTENV_EXPORT_TEST_7') }

	written := export({
		'DOTENV_EXPORT_TEST_6': 'file'
		'DOTENV_EXPORT_TEST_7': 'new'
	})
	assert written == ['DOTENV_EXPORT_TEST_7']
	assert os.getenv('DOTENV_EXPORT_TEST_6') == 'real'
	assert os.getenv('DOTENV_EXPORT_TEST_7') == 'new'
}

fn test_export_on_source_output() {
	os.setenv('FROM_ENV', 'system-val', true)
	defer { os.unsetenv('FROM_ENV') }
	defer { os.unsetenv('ONLY_FILE') }

	m := source([fixture('conf.env')])!
	export(m)
	assert os.getenv('FROM_ENV') == 'system-val'
	assert os.getenv('ONLY_FILE') == 'yes'
}

fn test_source_and_export_sets_file_keys_and_keeps_real_env() {
	os.setenv('FROM_ENV', 'system-val', true)
	defer { os.unsetenv('FROM_ENV') }
	defer { os.unsetenv('ONLY_FILE') }

	written := source_and_export([fixture('conf.env')])!
	assert written == ['ONLY_FILE']
	assert os.getenv('FROM_ENV') == 'system-val'
	assert os.getenv('ONLY_FILE') == 'yes'
}

fn test_source_and_export_require_files_errors_on_missing() {
	source_and_export([fixture('missing.env')], require_files: true) or {
		assert err.msg().contains('File not found')
		return
	}
	assert false
}

fn test_source_and_export_propagates_parse_errors() {
	source_and_export([fixture('bad.env')]) or {
		assert err.msg().contains('Invalid variable name')
		return
	}
	assert false
}
