module dotenv

// LoadError describes a malformed `.env` file. It carries both the byte offset
// and the human-readable position of the offending character.
pub struct LoadError {
	Error
pub:
	// reason is a short, human-readable description of what went wrong.
	reason string
	// offset is the zero-based byte offset of the offending character.
	offset int
	// line is the one-based line number.
	line int
	// column is the one-based column number.
	column int
	// line_text is the full text of the offending line, without a trailing newline.
	line_text string
}

// msg implements the `IError` interface.
pub fn (e LoadError) msg() string {
	return '${e.reason} on line ${e.line}, column ${e.column}'
}

// msg_full returns a multi-line message that points at the offending character.
pub fn (e LoadError) msg_full() string {
	prefix := ' ${e.line} | '
	pad := ' '.repeat(prefix.len)
	spaces := ' '.repeat(e.column - 1)
	caret := '${pad}${spaces}^'

	return '${e.reason}:\n${prefix}${e.line_text}\n${caret}'
}

// SourceError describes a failure of `source` that has no position inside a
// parsed file, e.g. a missing file when `require_files` is enabled.
pub struct SourceError {
	Error
pub:
	reason string
}

// msg implements the `IError` interface.
pub fn (e SourceError) msg() string {
	return e.reason
}

// error_at builds a LoadError for the given byte offset.
fn error_at(reason string, data []u8, pos int) IError {
	mut line := 1
	mut last_newline := -1

	for i in 0 .. pos {
		if data[i] == `\n` {
			line++
			last_newline = i
		}
	}

	return LoadError{
		reason:    reason
		offset:    pos
		line:      line
		column:    char_column(data, last_newline + 1, pos)
		line_text: line_text_at(data, pos)
	}
}

// char_column counts UTF-8 characters (runes) between `start` (included) and
// `end` (excluded), so error columns and carets stay aligned on lines that
// contain multibyte text.
fn char_column(data []u8, start int, end int) int {
	mut col := 1

	for i := start; i < end; {
		if data[i] < 0x80 {
			i++
		} else if data[i] < 0xC0 {
			i++ // stray continuation byte counts as its own unit
		} else if data[i] < 0xE0 {
			i += 2
		} else if data[i] < 0xF0 {
			i += 3
		} else {
			i += 4
		}

		col++
	}

	return col
}

// line_text_at returns the contents of the line containing `pos`.
fn line_text_at(data []u8, pos int) string {
	mut start := pos

	for start > 0 && data[start - 1] != `\n` {
		start--
	}

	mut end := pos

	for end < data.len && data[end] != `\n` {
		end++
	}

	return data[start..end].bytestr()
}
