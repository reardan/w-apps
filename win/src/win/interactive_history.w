# Revision 3 history metadata and traversal controls. Native pointers never
# cross IPC; every entry and the complete table are bounded before publication.
import structures.string
import lib.utf8
import win.loader

const int WIN_HISTORY_WIRE_LIMIT = 1048576

struct win_interactive_history_entry:
	int serial
	int document
	int scroll
	char* address
	char* state

void win_interactive_history_clear(list[win_interactive_history_entry*] entries):
	if (entries == 0): return
	for win_interactive_history_entry* entry in entries:
		free(entry.address)
		free(entry.state)
		free(entry)
	while (entries.length): entries.pop()

# Syntax-only JSON validation preserves escaped UTF-16 (including lone
# surrogates) and avoids allocating a parent object tree for every snapshot.
struct win_history_json_cursor:
	char* data
	int length
	int at

void win_history_json_space(win_history_json_cursor* cursor):
	while (cursor.at < cursor.length):
		int c = cursor.data[cursor.at]
		if (c != 32 && c != 9 && c != 10 && c != 13): return
		cursor.at = cursor.at + 1

int win_history_json_string(win_history_json_cursor* cursor):
	if (cursor.at >= cursor.length || cursor.data[cursor.at] != 34): return 0
	cursor.at = cursor.at + 1
	while (cursor.at < cursor.length):
		int c = cursor.data[cursor.at] & 255
		cursor.at = cursor.at + 1
		if (c == 34): return 1
		if (c < 32): return 0
		if (c != 92): continue
		if (cursor.at == cursor.length): return 0
		c = cursor.data[cursor.at]
		cursor.at = cursor.at + 1
		if (c == 117):
			if (cursor.length - cursor.at < 4): return 0
			for i in range(4):
				int digit = cursor.data[cursor.at + i]
				if ((digit < 48 || digit > 57) && (digit < 65 || digit > 70) && (digit < 97 || digit > 102)): return 0
			cursor.at = cursor.at + 4
		else if (c != 34 && c != 92 && c != 47 && c != 98 && c != 102 && c != 110 && c != 114 && c != 116): return 0
	return 0

int win_history_json_value(win_history_json_cursor* cursor, int depth):
	win_history_json_space(cursor)
	if (depth > 33 || cursor.at >= cursor.length): return 0
	int c = cursor.data[cursor.at]
	if (c == 34): return win_history_json_string(cursor)
	if (c == 91 || c == 123):
		int end = 93
		if (c == 123): end = 125
		cursor.at = cursor.at + 1
		win_history_json_space(cursor)
		if (cursor.at < cursor.length && cursor.data[cursor.at] == end):
			cursor.at = cursor.at + 1
			return 1
		while (cursor.at < cursor.length):
			if (c == 123):
				if (win_history_json_string(cursor) == 0): return 0
				win_history_json_space(cursor)
				if (cursor.at >= cursor.length || cursor.data[cursor.at] != 58): return 0
				cursor.at = cursor.at + 1
			if (win_history_json_value(cursor, depth + 1) == 0): return 0
			win_history_json_space(cursor)
			if (cursor.at >= cursor.length): return 0
			int delimiter = cursor.data[cursor.at]
			cursor.at = cursor.at + 1
			if (delimiter == end): return 1
			if (delimiter != 44): return 0
			win_history_json_space(cursor)
		return 0
	char* literal = 0
	if (c == 110): literal = c"null"
	else if (c == 116): literal = c"true"
	else if (c == 102): literal = c"false"
	if (literal != 0):
		int length = strlen(literal)
		if (length > cursor.length - cursor.at): return 0
		for i in range(length):
			if (literal[i] != cursor.data[cursor.at + i]): return 0
		cursor.at = cursor.at + length
		return 1
	if (c == 45): cursor.at = cursor.at + 1
	if (cursor.at >= cursor.length): return 0
	c = cursor.data[cursor.at]
	if (c == 48): cursor.at = cursor.at + 1
	else:
		if (c < 49 || c > 57): return 0
		while (cursor.at < cursor.length && cursor.data[cursor.at] >= 48 && cursor.data[cursor.at] <= 57): cursor.at = cursor.at + 1
	if (cursor.at < cursor.length && cursor.data[cursor.at] == 46):
		cursor.at = cursor.at + 1
		int first = cursor.at
		while (cursor.at < cursor.length && cursor.data[cursor.at] >= 48 && cursor.data[cursor.at] <= 57): cursor.at = cursor.at + 1
		if (cursor.at == first): return 0
	if (cursor.at < cursor.length && (cursor.data[cursor.at] == 101 || cursor.data[cursor.at] == 69)):
		cursor.at = cursor.at + 1
		if (cursor.at < cursor.length && (cursor.data[cursor.at] == 43 || cursor.data[cursor.at] == 45)): cursor.at = cursor.at + 1
		int first = cursor.at
		while (cursor.at < cursor.length && cursor.data[cursor.at] >= 48 && cursor.data[cursor.at] <= 57): cursor.at = cursor.at + 1
		if (cursor.at == first): return 0
	return 1

int win_interactive_history_state_valid(char* data, int length):
	if (length == 0): return 1
	win_history_json_cursor cursor
	cursor.data = data
	cursor.length = length
	cursor.at = 0
	if (win_history_json_value(&cursor, 0) == 0): return 0
	win_history_json_space(&cursor)
	return cursor.at == length

int win_interactive_history_address_valid(char* data, int length):
	for i in range(length):
		if ((data[i] & 255) < 32 || data[i] == 127): return 0
	char* address = substring(data, 0, length)
	char* resolved = win_resolve(c"", address)
	free(address)
	if (resolved == 0): return 0
	free(resolved)
	return 1

# A complete validation pass precedes allocations or replacement of the
# previously published history. Strings are length-delimited scalar UTF-8.
int win_interactive_history_validate(char* data, int length, int document):
	if (length < 8 || length > WIN_HISTORY_WIRE_LIMIT): return 0
	int count = load_int32(data)
	int current = load_int32(data + 4)
	if (count < 1 || count > 128 || current < 0 || current >= count): return 0
	int at = 8
	int previous = 0
	for i in range(count):
		if (length - at < 20): return 0
		int serial = load_int32(data + at)
		int epoch = load_int32(data + at + 4)
		int scroll = load_int32(data + at + 8)
		int address = load_int32(data + at + 12)
		int state = load_int32(data + at + 16)
		at = at + 20
		if (serial <= previous || epoch < 1 || epoch > document || scroll < 0 || scroll > 16777216 || address < 1 || address > 65536 || state < 0 || state > 65536): return 0
		if (i == current && epoch != document): return 0
		if (address > length - at || state > length - at - address): return 0
		if (utf8_validate_bytes(data + at, address) == 0 || utf8_validate_bytes(data + at + address, state) == 0): return 0
		for j in range(address + state):
			if (data[at + j] == 0): return 0
		if (win_interactive_history_address_valid(data + at, address) == 0 || win_interactive_history_state_valid(data + at + address, state) == 0): return 0
		at = at + address + state
		previous = serial
	return at == length

int win_interactive_history_read_validated(list[win_interactive_history_entry*] entries, char* data):
	win_interactive_history_clear(entries)
	int count = load_int32(data)
	int at = 8
	for i in range(count):
		win_interactive_history_entry* entry = new win_interactive_history_entry()
		entry.serial = load_int32(data + at)
		entry.document = load_int32(data + at + 4)
		entry.scroll = load_int32(data + at + 8)
		int address = load_int32(data + at + 12)
		int state = load_int32(data + at + 16)
		at = at + 20
		entry.address = str_copy_range(data + at, 0, address)
		at = at + address
		entry.state = str_copy_range(data + at, 0, state)
		at = at + state
		entries.push(entry)
	return load_int32(data + 4)

string_builder* win_interactive_history_control(int generation, int document, int delta):
	if (generation < 1 || document < 1 || delta == 0 || delta < -127 || delta > 127): return 0
	string_builder* payload = string_new()
	for i in range(16): string_append_char(payload, 0)
	save_int32(payload.data, generation)
	save_int32(payload.data + 4, document)
	save_int32(payload.data + 8, delta)
	return payload

int win_interactive_history_delta(char* data, int length, int generation, int document):
	if (length != 16 || load_int32(data) != generation || load_int32(data + 4) != document || load_int32(data + 12) != 0): return 0
	int delta = load_int32(data + 8)
	if (delta < -127 || delta > 127): return 0
	return delta
