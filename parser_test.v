module dotenv

import os

fn test_simple() {
	m := parse('FOO=bar')!
	assert m['FOO'] == 'bar'
	assert m.len == 1
}

fn test_multiple_and_blank_lines() {
	m := parse('A=1\n\nB=2\n')!
	assert m['A'] == '1'
	assert m['B'] == '2'
	assert m.len == 2
}

fn test_export_prefix() {
	m := parse('export FOO=bar')!
	assert m['FOO'] == 'bar'
}

fn test_export_prefix_repeated() {
	m := parse('export export FOO=bar')!
	assert m['FOO'] == 'bar'
}

fn test_trim_surrounding_spaces_of_key_and_value() {
	m := parse('FOO = bar ')!
	assert m['FOO'] == 'bar'
}

fn test_comments_only_file_parses_to_empty_map() {
	content := "# This is a boring file meant to demonstrate\n\n# that files needn't contain\n\n# any key/value definitions at all.\n\n# Empty lines and comments are Ok."
	m := parse(content)!
	assert m.len == 0
}

fn test_full_line_comments_and_blank_lines() {
	m := parse('# comment\nFOO=bar\n   # another\n\n')!
	assert m['FOO'] == 'bar'
	assert m.len == 1
}

fn test_inline_comment_unquoted() {
	m := parse('FOO=bar # trailing')!
	assert m['FOO'] == 'bar'
}

fn test_hash_starts_comment_even_without_space() {
	m := parse('FOO=bar#baz')!
	assert m['FOO'] == 'bar'
}

fn test_double_quotes_fixture() {
	content := '# Shows what you can do with double quotes (single)\n\nA="apple"\nB=" boy " # with trailing comment; value should not be trimmed\nC="interpolated \${A}"\n'
	m := parse(content)!
	assert m['A'] == 'apple'
	assert m['B'] == ' boy '
	assert m['C'] == 'interpolated apple'
}

fn test_single_quotes_fixture() {
	content := "# Shows what you can do with single quotes\n\nA='apple'\nB=' boy ' # with trailing comment; value should not be trimmed\nC='non-interpolated \${A}'\n"
	m := parse(content)!
	assert m['A'] == 'apple'
	assert m['B'] == ' boy '
	assert m['C'] == 'non-interpolated \${A}'
}

fn test_single_quotes_do_not_interpolate() {
	m := parse("A=x\nB='\${A}'")!
	assert m['B'] == '\${A}'
}

fn test_single_quotes_do_not_process_escapes() {
	m := parse("B='a\\tb'")!
	assert m['B'] == 'a\\tb'
}

fn test_unquoted_fixture() {
	content := '# Demos valid unqoted values\nA=one-word\nB=  trim me # with trailing comment; value should be trimmed\nC=with spaces\nD=interpolated vars \${A}\n'
	m := parse(content)!
	assert m['A'] == 'one-word'
	assert m['B'] == 'trim me'
	assert m['C'] == 'with spaces'
	assert m['D'] == 'interpolated vars one-word'
}

fn test_unquoted_dollar_alone_is_literal() {
	m := parse('A=$\nABCDEFG_1234=$\nA456=\n')!
	assert m['A'] == '$'
	assert m['ABCDEFG_1234'] == '$'
	assert m['A456'] == ''
}

fn test_interpolation_multiple() {
	m := parse('A=1\nB=2\nC=\${A}-\${B}')!
	assert m['C'] == '1-2'
}

fn test_interpolation_in_double_quotes() {
	m := parse('A=1\nB="x\${A}y"')!
	assert m['B'] == 'x1y'
}

fn test_equals_inside_quoted_value() {
	m := parse('FOO="a=b"')!
	assert m['FOO'] == 'a=b'
}

fn test_escapes_full_sequence() {
	m := parse('A="\\n\\r\\t\\f\\b\\"\\\'\\\\\\uAAAA\\z"')!
	want := '\n\r\t\f\b"\'\\' + rune(0xaaaa).str() + 'z'
	assert m['A'] == want
}

fn test_unknown_escape_drops_backslash() {
	m := parse('B="a\\qb"')!
	assert m['B'] == 'aqb'
}

fn test_unicode_surrogate_escape_is_rejected() {
	parse('A="\\uD800"') or {
		assert err.msg().contains('surrogate code point')
		return
	}
	assert false
}

fn test_unicode_surrogate_range_is_rejected() {
	parse('A="\\uDFFF"') or {
		assert err.msg().contains('surrogate code point')
		return
	}
	assert false
}

fn test_large_heredoc_value() {
	body := 'x'.repeat(100_000)

	m := parse("D='''\n${body}\n'''\n")!
	assert m['D'] == body + '\n'
}

fn test_heredoc_single_literal() {
	m := parse("FOO='''\nline1\nline2\n'''\n")!
	assert m['FOO'] == 'line1\nline2\n'
}

fn test_heredoc_fixture() {
	content := 'A=\'\'\'\napple\n\'\'\'\nB=\'\'\'   \nNo substitution \${A}\n\'\'\' # Trailing comment\nC="""\nSubstitution \${A}\n"""\n'
	m := parse(content)!
	assert m['A'] == 'apple\n'
	assert m['B'] == 'No substitution \${A}\n'
	assert m['C'] == 'Substitution apple\n\n'
}

fn test_multiline_fixture() {
	content := 'MSG_A="\nHello from MSG_A\n"\n\nMSG_B="""\nHello from MSG_B\n"""\n\nMSG_C="""\nHello from MSG_C\n"""\n\nMSG_D="""\nHello from MSG_D interpolating "\${MSG_A}"\n"""\n\nMSG_E=\'\'\'\nHello from MSG_E without interpolating "\${MSG_B}"\n\'\'\'\n\nMSG_F=\'\nHello from MSG_F\n\'\n\nMSG_G=\'\nHello from MSG_G with\nlots of text\n\'\n'
	m := parse(content)!
	assert m['MSG_A'] == '\nHello from MSG_A\n'
	assert m['MSG_B'] == 'Hello from MSG_B\n'
	assert m['MSG_C'] == 'Hello from MSG_C\n'
	assert m['MSG_D'] == 'Hello from MSG_D interpolating "\nHello from MSG_A\n"\n'
	assert m['MSG_E'] == 'Hello from MSG_E without interpolating "\${MSG_B}"\n'
	assert m['MSG_F'] == '\nHello from MSG_F\n'
	assert m['MSG_G'] == '\nHello from MSG_G with\nlots of text\n'
}

fn test_command_substitution() {
	m := parse('FOO=$(echo hello)', allow_commands: true)!
	assert m['FOO'] == 'hello'
}

fn test_command_substitution_with_args() {
	m := parse('FOO=$(echo this-is-a-test)', allow_commands: true)!
	assert m['FOO'] == 'this-is-a-test'
}

// `$(...)` is read up to the first `)`, so a nested command is passed through
// literally instead of being executed.
fn test_command_substitution_stops_at_first_closing_paren() {
	m := parse('FOO=$(echo $(date))', allow_commands: true)!
	assert m['FOO'] == '\$(date)'
}

fn test_command_substitution_in_double_quotes() {
	m := parse('FOO="$(echo hello)"', allow_commands: true)!
	assert m['FOO'] == 'hello'
}

fn test_command_substitution_not_executed_in_single_quotes() {
	m := parse("FOO='\$(echo this-is-a-test)'")!
	assert m['FOO'] == '\$(echo this-is-a-test)'
}

fn test_command_substitution_disabled_by_default() {
	parse('FOO=$(echo hello)') or {
		assert err.msg().contains('disabled')
		return
	}
	assert false
}

fn test_command_substitution_explicitly_disabled() {
	parse('FOO=$(echo hello)', allow_commands: false) or {
		assert err.msg().contains('disabled')
		return
	}
	assert false
}

fn test_command_failure_errors() {
	parse('FOO=$(false)', allow_commands: true) or {
		assert err.msg().contains('non-zero exit status')
		return
	}
	assert false
}

fn test_error_offset_is_byte_based() {
	parse('A=Привет oops"quote') or {
		assert err is LoadError
		if err is LoadError {
			assert err.offset == 19
		}
		return
	}
	assert false
}

fn test_error_column_counts_characters_not_bytes() {
	parse('A=Привет oops"quote') or {
		assert err is LoadError
		if err is LoadError {
			assert err.column == 14
			assert err.msg_full().ends_with(' '.repeat(err.column - 1) + '^')
		}
		return
	}
	assert false
}

fn test_error_column_with_emoji() {
	parse('A=🎉 oops"quote') or {
		assert err is LoadError
		if err is LoadError {
			assert err.column == 9
			assert err.offset == 11
		}
		return
	}
	assert false
}

fn test_missing_value_at_eof_errors() {
	parse('FOO') or {
		assert err.msg().contains('variable missing value')
		return
	}
	assert false
}

fn test_key_without_value_on_line_errors() {
	parse('KEY_WITHOUT_VALUE\n') or {
		assert err.msg().contains('No equals sign')
		return
	}
	assert false
}

fn test_key_begins_with_number_errors() {
	parse('2bad=nope') or {
		assert err.msg().contains('Invalid variable name')
		return
	}
	assert false
}

fn test_key_contains_spaces_errors() {
	parse('NOT GOOD=') or {
		assert err.msg().contains('Invalid variable name')
		return
	}
	assert false
}

fn test_key_contains_unicode_errors() {
	parse('SÜPER=') or {
		assert err.msg().contains('Invalid variable name')
		return
	}
	assert false
}

fn test_key_contains_hyphen_errors() {
	parse('NOT-ALLOWED=') or {
		assert err.msg().contains('Invalid variable name')
		return
	}
	assert false
}

fn test_improper_sequence_before_double_quote_errors() {
	parse('KEY=oops"quoted"') or {
		assert err.msg().contains('before opening quote')
		return
	}
	assert false
}

fn test_improper_sequence_before_single_quote_errors() {
	parse("KEY=oops'quoted'") or {
		assert err.msg().contains('before opening quote')
		return
	}
	assert false
}

fn test_unterminated_quote_errors() {
	parse('KEY="missing-quote') or {
		assert err.msg().contains('Stop sequence not found')
		return
	}
	assert false
}

fn test_trailing_characters_after_quote_errors() {
	parse('A="apple" oops') or {
		assert err.msg().contains('Invalid syntax')
		return
	}
	assert false
}

fn test_interpolation_missing_closing_brace_errors() {
	parse('A=\${B') or {
		assert err.msg().contains('Stop sequence not found')
		return
	}
	assert false
}

fn test_interpolation_undefined_errors() {
	parse('A=\${B}') or {
		assert err.msg().contains('variable undefined')
		return
	}
	assert false
}

fn test_interpolation_undefined_in_double_quotes_errors() {
	parse('A="\${B}"') or {
		assert err.msg().contains('variable undefined')
		return
	}
	assert false
}

fn test_interpolation_from_env_disabled_by_default() {
	parse('A=\${HOME}') or {
		assert err.msg().contains('variable undefined')
		return
	}
	assert false
}

fn test_interpolation_from_env_enabled() {
	os.setenv('DOTENV_TEST_ENV_VAR', 'from-env', true)
	defer { os.unsetenv('DOTENV_TEST_ENV_VAR') }

	m := parse('A=\${DOTENV_TEST_ENV_VAR}!', interp_env: true)!
	assert m['A'] == 'from-env!'
}

fn test_interpolation_from_env_in_double_quotes() {
	os.setenv('DOTENV_TEST_ENV_VAR', 'from-env', true)
	defer { os.unsetenv('DOTENV_TEST_ENV_VAR') }

	m := parse('A="\${DOTENV_TEST_ENV_VAR}"', interp_env: true)!
	assert m['A'] == 'from-env'
}

fn test_interpolation_file_variable_beats_env() {
	os.setenv('CONFLICT', 'from-env', true)
	defer { os.unsetenv('CONFLICT') }

	m := parse('CONFLICT=from-file\nB=\${CONFLICT}x', interp_env: true)!
	assert m['CONFLICT'] == 'from-file'
	assert m['B'] == 'from-filex'
}

fn test_interpolation_undefined_still_errors_with_env_lookup() {
	parse('A=\${DOTENV_TEST_NEVER_SET}', interp_env: true) or {
		assert err.msg().contains('variable undefined')
		return
	}
	assert false
}

fn test_invalid_unicode_too_many_hex_errors() {
	parse('FOO="\\uZZZZoops"') or {
		assert err.msg().contains('Invalid unicode')
		return
	}
	assert false
}

fn test_invalid_unicode_non_base16_errors() {
	parse('FOO="\\uXÜ9foo"') or {
		assert err.msg().contains('Invalid unicode')
		return
	}
	assert false
}

fn test_incomplete_unicode_errors() {
	parse('FOO="\\uAB"') or {
		assert err.msg().contains('incomplete')
		return
	}
	assert false
}

fn test_empty_command_errors() {
	parse('FOO=$()', allow_commands: true) or {
		assert err.msg().contains('missing arguments')
		return
	}
	assert false
}

fn test_heredoc_text_after_opening_errors() {
	parse("A=''' \\t\nExample\n'''\n") or {
		assert err.msg().contains('heredoc allows only')
		return
	}
	assert false
}

fn test_heredoc_text_after_opening_double_quotes_errors() {
	parse('A=""" \\t\nExample\n"""\n') or {
		assert err.msg().contains('heredoc allows only')
		return
	}
	assert false
}

fn test_heredoc_open_preceded_by_text_single_errors() {
	parse("A= oops '''\nExample\n'''\n") or {
		assert err.msg().contains('before opening heredoc')
		return
	}
	assert false
}

fn test_heredoc_open_preceded_by_text_double_errors() {
	parse('A= oops """\nExample\n"""\n') or {
		assert err.msg().contains('before opening heredoc')
		return
	}
	assert false
}

fn test_heredoc_text_after_closing_single_errors() {
	parse("A='''\nExample\n''' oops\n") or {
		assert err.msg().contains('Invalid syntax following')
		return
	}
	assert false
}

fn test_heredoc_text_after_closing_double_errors() {
	parse('A="""\nExample\n""" oops\n') or {
		assert err.msg().contains('Invalid syntax following')
		return
	}
	assert false
}

fn test_unclosed_heredoc_errors() {
	parse("A='''\nExample\n") or {
		assert err.msg().contains('Stop sequence not found')
		return
	}
	assert false
}

fn test_error_position_fields() {
	parse('A=1\n1BAD=x') or {
		if err is LoadError {
			assert err.line == 2
			assert err.column == 1
			assert err.line_text == '1BAD=x'
			assert err.offset == 4
			assert err.msg_full().contains('^')
		} else {
			assert false
		}
		return
	}
	assert false
}

fn test_error_message_carries_position() {
	parse('A=1\nBAD\n') or {
		assert err.msg().contains('No equals sign')
		assert err.msg().contains('line 2')
		return
	}
	assert false
}

// fixture_path returns the absolute path of a `.env` test fixture.
fn fixture_path(name string) string {
	return os.join_path(os.dir(@FILE), 'testdata', name)
}

fn test_unicode_fixture() {
	content := os.read_file(fixture_path('unicode.env')) or { panic(err.msg()) }
	m := parse(content)!
	assert m['GREET'] == 'Привет мир'
	assert m['EMOJI'] == '🎉 party'
	assert m['QUOTED'] == 'Эмодзи 📦 в кавычках'
	assert m['SINGLE'] == 'Кириллица в single quotes 🔥'
	assert m['ESCAPED'] == 'Привет'
	assert m['INTERP'] == 'Привет мир!'
	assert m['DOC'] == 'Строка с эмодзи 🚀\nвторая строка\n'
}

fn test_interpolation_from_env_with_unicode_value() {
	os.setenv('DOTENV_TEST_ENV_VAR', 'значение 🎉', true)
	defer { os.unsetenv('DOTENV_TEST_ENV_VAR') }

	m := parse('A=\${DOTENV_TEST_ENV_VAR}!', interp_env: true)!
	assert m['A'] == 'значение 🎉!'
}
