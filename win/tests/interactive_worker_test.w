import lib.assert
import lib.args
import win.interactive_worker

void interactive_test_reply(int sequence, int kind, int reserved, int declared):
	string_builder* frame = string_new()
	win_interactive_header(frame, sequence, kind)
	for i in range(8): string_append_char(frame, 0)
	string_append(frame, c"local")
	string_append_char(frame, 0)
	string_append(frame, c"title")
	string_append_char(frame, 0)
	string_append(frame, c"<p>ok</p>")
	string_append_char(frame, 0)
	save_int32(frame.data + 8, frame.length - 24)
	if (declared): save_int32(frame.data + 8, declared)
	save_int32(frame.data + 20, reserved)
	socket_send(0, frame.data, 7, 16384)
	process_sleep_ms(2)
	socket_send(0, frame.data + 7, frame.length - 7, 16384)
	string_free(frame)

int interactive_test_child(char* mode):
	if (strcmp(mode, c"hang") == 0):
		process_sleep_ms(5000)
		return 0
	if (strcmp(mode, c"crash") == 0): return 1
	int sequence = 0
	int kind = 100
	int reserved = 0
	int declared = 0
	if (strcmp(mode, c"sequence") == 0): sequence = 1
	if (strcmp(mode, c"kind") == 0): kind = 5
	if (strcmp(mode, c"reserved") == 0): reserved = 1
	if (strcmp(mode, c"oversize") == 0): declared = 10000000
	interactive_test_reply(sequence, kind, reserved, declared)
	if (strcmp(mode, c"disconnect") == 0): close(0)
	if (strcmp(mode, c"good") != 0):
		process_sleep_ms(5000)
		return 0
	char[28] request
	int at = 0
	while (at < 28):
		int count = read(0, &request[at], 28 - at)
		if (count <= 0): return 1
		at = at + count
	assert_equal(1, load_int32(&request[12]))
	interactive_test_reply(1, 100, 0, 0)
	process_sleep_ms(5000)
	return 0

int interactive_test_wait(win_interactive_worker* worker):
	int result = 0
	int polls = 0
	while (result == 0):
		int start = process_monotonic_ms()
		result = win_interactive_poll(worker)
		asserts(c"poll leaves UI responsive", process_monotonic_ms() - start < 100)
		polls = polls + 1
		asserts(c"bounded test watchdog", polls < 3000)
		process_sleep_ms(1)
	return result

void interactive_test_case(char* mode, int status):
	win_interactive_worker* worker = win_interactive_start(args_program(), mode, c"", 250, 1024)
	int pid = worker.child.pid
	assert_equal(-1, interactive_test_wait(worker))
	assert_equal(status, worker.status)
	asserts(c"failure clears published response", worker.html == 0 && worker.child == 0)
	assert_equal(-10, wait4(pid, 0, 1, 0))
	win_interactive_free(worker)

int main(int argc, int argv):
	args_init(argc, argv)
	args_declare_bool(c"interactive-worker")
	if (args_has_flag(c"interactive-worker")): return interactive_test_child(args_value(c"page"))
	interactive_test_case(c"hang", 2)
	interactive_test_case(c"crash", 3)
	interactive_test_case(c"sequence", 4)
	interactive_test_case(c"kind", 4)
	interactive_test_case(c"reserved", 4)
	interactive_test_case(c"oversize", 5)
	win_interactive_worker* worker = win_interactive_start(args_program(), c"good", c"", 1000, 1024)
	assert_equal(0, win_interactive_request(worker, 1, 0, c""))
	assert_equal(1, interactive_test_wait(worker))
	assert_strings_equal(c"<p>ok</p>", worker.html)
	assert_strings_equal(c"local", worker.address)
	assert_equal(1, win_interactive_request(worker, 1, 0, c""))
	asserts(c"new request invalidates borrowed response", worker.html == 0)
	assert_equal(0, win_interactive_request(worker, 2, 1, c""))
	assert_equal(1, interactive_test_wait(worker))
	assert_strings_equal(c"title", worker.title)
	int pid = worker.child.pid
	win_interactive_free(worker)
	assert_equal(-10, wait4(pid, 0, 1, 0))
	worker = win_interactive_start(args_program(), c"disconnect", c"", 1000, 1024)
	assert_equal(1, interactive_test_wait(worker))
	assert_equal(1, win_interactive_request(worker, 1, 0, c""))
	assert_equal(-1, interactive_test_wait(worker))
	assert_equal(4, worker.status)
	win_interactive_free(worker)
	worker = win_interactive_start(args_program(), c"good", c"", 0, 1024)
	assert_equal(7, worker.status)
	win_interactive_free(worker)
	println(c"Interactive transport framing, deadlines, busy bounds and cleanup: OK")
	return 0
