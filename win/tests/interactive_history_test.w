import lib.assert
import win.browser

void history_record(string_builder* wire, int serial, int epoch, char* address, char* state):
	int at = wire.length
	for i in range(20): string_append_char(wire, 0)
	save_int32(wire.data + at, serial)
	save_int32(wire.data + at + 4, epoch)
	save_int32(wire.data + at + 12, strlen(address))
	save_int32(wire.data + at + 16, strlen(state))
	string_append(wire, address)
	string_append(wire, state)

string_builder* history_table():
	string_builder* wire = string_new()
	for i in range(8): string_append_char(wire, 0)
	save_int32(wire.data, 2)
	save_int32(wire.data + 4, 1)
	history_record(wire, 1, 1, c"http://example.test/old", c"null")
	history_record(wire, 3, 2, c"http://example.test/new", c"{\"x\":[\"\\ud800\",\"\\u0000\",true,-1.5e+2]}")
	return wire

void history_snapshot(win_interactive_worker* worker, string_builder* table, char* address):
	win_interactive_header(worker.incoming, 1, 103)
	save_int32(worker.incoming.data + 20, 3)
	for i in range(52): string_append_char(worker.incoming, 0)
	save_int32(worker.incoming.data + 36, 9)
	save_int32(worker.incoming.data + 40, 2)
	save_int32(worker.incoming.data + 44, 7)
	save_int32(worker.incoming.data + 48, 2)
	save_int32(worker.incoming.data + 52, 4)
	save_int32(worker.incoming.data + 64, 800)
	save_int32(worker.incoming.data + 68, 600)
	save_int32(worker.incoming.data + 72, table.length)
	string_append_bytes(worker.incoming, table.data, table.length)
	string_append(worker.incoming, address)
	string_append_char(worker.incoming, 0)
	string_append(worker.incoming, c"title")
	string_append_char(worker.incoming, 0)
	string_append(worker.incoming, c"<p>new</p>")
	string_append_char(worker.incoming, 0)

int main():
	char* valid = c" { \"a\": [null,true,false,0,-0,1.25e-9,\"\\ud800\\u0000\"], \"b\":{} } "
	assert1(win_interactive_history_state_valid(valid, strlen(valid)))
	char*[12] invalid
	invalid[0] = c" "
	invalid[1] = c"[1,]"
	invalid[2] = c"{\"x\":}"
	invalid[3] = c"{\"x\":1,}"
	invalid[4] = c"[01]"
	invalid[5] = c"1."
	invalid[6] = c"1e+"
	invalid[7] = c"nul"
	invalid[8] = c"true false"
	invalid[9] = c"\"\\u12x4\""
	invalid[10] = c"\"\\a\""
	invalid[11] = c"\"unterminated"
	for i in range(12): assert_equal(0, win_interactive_history_state_valid(invalid[i], strlen(invalid[i])))
	assert1(win_interactive_history_state_valid(c"", 0))
	string_builder* deep = string_new()
	for i in range(35): string_append_char(deep, '[')
	string_append_char(deep, '0')
	for i in range(35): string_append_char(deep, ']')
	assert_equal(0, win_interactive_history_state_valid(deep.data, deep.length))
	string_free(deep)
	string_builder* wire = history_table()
	assert1(win_interactive_history_validate(wire.data, wire.length, 2))
	assert_equal(0, win_interactive_history_validate(wire.data, wire.length - 1, 2))
	assert_equal(0, win_interactive_history_validate(wire.data, wire.length, 1))
	save_int32(wire.data + 4, 2)
	assert_equal(0, win_interactive_history_validate(wire.data, wire.length, 2))
	save_int32(wire.data + 4, 1)
	save_int32(wire.data + 8, 3)
	assert_equal(0, win_interactive_history_validate(wire.data, wire.length, 2))
	save_int32(wire.data + 8, 1)
	list[win_interactive_history_entry*] entries = new list[win_interactive_history_entry*]
	assert_equal(1, win_interactive_history_read_validated(entries, wire.data))
	assert_strings_equal(c"http://example.test/new", entries[1].address)
	assert_contains(entries[1].state, c"\\ud800")
	win_interactive_history_clear(entries)
	__w_list_free(cast(__w_list*, entries))
	string_builder* control = win_interactive_history_control(9, 2, -1)
	assert_equal(-1, win_interactive_history_delta(control.data, control.length, 9, 2))
	assert_equal(0, win_interactive_history_delta(control.data, control.length, 9, 3))
	assert_equal(0, win_interactive_history_delta(control.data, control.length - 1, 9, 2))
	save_int32(control.data + 12, 1)
	assert_equal(0, win_interactive_history_delta(control.data, control.length, 9, 2))
	string_free(control)
	assert1(win_interactive_history_control(9, 2, -128) == 0)
	# Decoding a future document cannot retag input acquired from old pixels.
	win_interactive_worker* worker = new win_interactive_worker()
	worker.incoming = string_new()
	worker.history = new list[win_interactive_history_entry*]
	worker.pending_history = new list[win_interactive_history_entry*]
	worker.generation = 9
	worker.document_generation = 1
	worker.focus_node = 3
	history_snapshot(worker, wire, c"http://example.test/new")
	assert1(win_interactive_validate(worker))
	assert_equal(1, worker.document_generation)
	assert_equal(3, worker.focus_node)
	assert_equal(0, worker.history.length)
	assert_equal(2, worker.pending_document_generation)
	win_interactive_publish(worker)
	assert_equal(2, worker.document_generation)
	assert_equal(7, worker.focus_node)
	assert_equal(2, worker.history.length)
	# The graphics lifecycle can request reload before any parent entry exists.
	win_browser browser
	win_browser_init(&browser, c"", c"")
	win_commit_address(&browser, c"http://example.test/initial", -2)
	assert_equal(1, browser.history.length)
	assert_equal(0, browser.current)
	win_commit_address(&browser, c"http://example.test/reloaded", -2)
	assert_equal(1, browser.history.length)
	assert_strings_equal(c"http://example.test/reloaded", browser.history[0].address)
	win_browser_free(&browser)
	win_browser_init(&browser, c"", c"")
	browser.interactive = worker
	browser.pending_history = -2
	win_browser_history_snapshot(&browser, 1)
	assert_equal(2, browser.history.length)
	assert_equal(1, browser.current)
	assert_equal(9, browser.history[0].worker_generation)
	assert_strings_equal(c"http://example.test/new", browser.address)
	# A later reload replaces the existing segment rather than adding entries.
	win_browser_history_snapshot(&browser, 1)
	assert_equal(2, browser.history.length)
	assert_equal(1, browser.current)
	browser.interactive = 0
	win_browser_free(&browser)
	history_snapshot(worker, wire, c"http://example.test/wrong")
	assert_equal(0, win_interactive_validate(worker))
	assert_equal(2, worker.history.length)
	assert_strings_equal(c"http://example.test/new", worker.history[1].address)
	history_snapshot(worker, wire, c"http://example.test/new")
	worker.document_generation = 3
	assert_equal(0, win_interactive_validate(worker))
	worker.document_generation = 2
	worker.require_history = 1
	save_int32(worker.incoming.data + 16, 102)
	save_int32(worker.incoming.data + 20, 2)
	assert_equal(0, win_interactive_validate(worker))
	win_interactive_history_clear(worker.history)
	win_interactive_history_clear(worker.pending_history)
	__w_list_free(cast(__w_list*, worker.history))
	__w_list_free(cast(__w_list*, worker.pending_history))
	string_free(worker.incoming)
	free(worker)
	string_free(wire)
	assert_equal(0, debug_alloc_report_leaks())
	println(c"Isolated history wire validation and atomic publication: OK")
	return 0
