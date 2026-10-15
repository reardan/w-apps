import lib.assert
import lib.args
import win.script_worker

void worker_test_frame(int declared, int reserved, char* payload):
	char[24] header
	for i in range(24): header[i] = 0
	char* magic = c"WINSW001"
	for i in range(8): header[i] = magic[i]
	save_int32(&header[8], declared)
	save_int32(&header[20], reserved)
	# Fragment headers deliberately: the receiver must tolerate short reads.
	write(1, &header[0], 7)
	process_sleep_ms(3)
	write(1, &header[7], 17)
	write(1, payload, strlen(payload))

int worker_test_child(char* mode):
	if (strcmp(mode, c"descendant") == 0):
		win_script_worker* child = win_script_worker_start(args_program(), c"hang", c"", 10000, 64)
		string_builder* pid = string_new()
		string_append_int(pid, child.child.pid)
		worker_test_frame(pid.length, 0, pid.data)
		process_sleep_ms(10000)
		win_script_worker_free(child)
		string_free(pid)
		return 0
	if (strcmp(mode, c"magic") == 0):
		write(1, c"BADSW001", 8)
		return 0
	if (strcmp(mode, c"nul") == 0):
		worker_test_frame(3, 0, c"ok")
		char zero = 0
		write(1, &zero, 1)
		return 0
	if (strcmp(mode, c"hang") == 0):
		process_sleep_ms(10000)
		return 0
	if (strcmp(mode, c"crash") == 0):
		kill(getpid(), 9)
		return 1
	if (strcmp(mode, c"oversize") == 0):
		worker_test_frame(10000000, 0, c"")
		process_sleep_ms(10000)
		return 0
	if (strcmp(mode, c"flood") == 0):
		worker_test_frame(1, 0, c"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
		return 0
	if (strcmp(mode, c"truncated") == 0):
		worker_test_frame(20, 0, c"short")
		return 0
	if (strcmp(mode, c"reserved") == 0):
		worker_test_frame(2, 1, c"ok")
		return 0
	if (strcmp(mode, c"extra") == 0):
		worker_test_frame(1, 0, c"ok")
		return 0
	if (strcmp(mode, c"badutf8") == 0):
		worker_test_frame(1, 0, c"\xff")
		return 0
	worker_test_frame(2, 0, c"ok")
	if (strcmp(mode, c"latefailure") == 0): return 1
	if (strcmp(mode, c"noexit") == 0):
		close(1)
		process_sleep_ms(10000)
	return 0

void worker_test_case(char* mode, int status):
	win_script_worker* worker = win_script_worker_start(args_program(), mode, c"", 150, 64)
	int pid = worker.child.pid
	while (win_script_worker_poll(worker) == 0):
		asserts(c"no partial text publication", worker.text == 0)
		process_sleep_ms(1)
	assert_equal(status, worker.status)
	asserts(c"worker reaped and closed", worker.child == 0)
	assert_equal(-10, wait4(pid, 0, 1, 0))
	if (status == 1): assert_strings_equal(c"ok", worker.text)
	else: asserts(c"failure has no output", worker.text == 0 && worker.error != 0)
	assert_equal(1, win_script_worker_poll(worker))
	win_script_worker_free(worker)

void test_worker_protocol():
	worker_test_case(c"good", 1)
	worker_test_case(c"hang", 2)
	worker_test_case(c"crash", 3)
	worker_test_case(c"latefailure", 3)
	worker_test_case(c"noexit", 2)
	worker_test_case(c"truncated", 4)
	worker_test_case(c"reserved", 4)
	worker_test_case(c"extra", 4)
	worker_test_case(c"badutf8", 4)
	worker_test_case(c"magic", 4)
	worker_test_case(c"nul", 4)
	worker_test_case(c"oversize", 5)
	worker_test_case(c"flood", 5)

void test_worker_cancel():
	int began = process_monotonic_ms()
	win_script_worker* worker = win_script_worker_start(args_program(), c"hang", c"", 5000, 64)
	asserts(c"start is asynchronous", process_monotonic_ms() - began < 1000)
	assert_equal(0, win_script_worker_poll(worker))
	int pid = worker.child.pid
	win_script_worker_cancel(worker)
	assert_equal(6, worker.status)
	assert_equal(-10, wait4(pid, 0, 1, 0))
	win_script_worker_cancel(worker)
	win_script_worker_free(worker)
	worker = win_script_worker_start(args_program(), c"hang", c"", 0, 64)
	assert_equal(7, worker.status)
	asserts(c"invalid limits do not spawn", worker.child == 0)
	win_script_worker_free(worker)
	worker = win_script_worker_start(args_program(), c"hang", c"", 100, WIN_SCRIPT_WORKER_LIMIT + 1)
	assert_equal(7, worker.status)
	win_script_worker_free(worker)
	worker = win_script_worker_start(args_program(), c"hang", c"", 5000, 64)
	pid = worker.child.pid
	win_script_worker_free(worker)
	assert_equal(-10, wait4(pid, 0, 1, 0))

void test_worker_descendant_cleanup():
	# Adopt orphaned grandchildren so this test can prove they exited and reap
	# them, even on containers whose PID 1 does not collect zombies promptly.
	assert_equal(0, syscall7(157, 36, 1, 0, 0, 0, 0))
	win_script_worker* worker = win_script_worker_start(args_program(), c"descendant", c"", 5000, 64)
	int started = process_monotonic_ms()
	while (worker.buffer.length <= 24):
		assert_equal(0, win_script_worker_poll(worker))
		asserts(c"descendant announces pid", process_monotonic_ms() - started < 3000)
		process_sleep_ms(1)
	int descendant = atoi(worker.buffer.data + 24)
	asserts(c"valid descendant pid", descendant > 1)
	asserts(c"complete frame without exit stays private", worker.text == 0)
	win_script_worker_cancel(worker)
	int status = 0
	int reaped = 0
	started = process_monotonic_ms()
	while (reaped == 0):
		reaped = wait4(descendant, &status, 1, 0)
		asserts(c"descendant is adopted and exits", reaped >= 0 && process_monotonic_ms() - started < 3000)
		if (reaped == 0): process_sleep_ms(1)
	assert_equal(descendant, reaped)
	assert_equal(137, process_decode_status(status))
	win_script_worker_free(worker)
	assert_equal(0, syscall7(157, 36, 0, 0, 0, 0, 0))

int main(int argc, int argv):
	if (win_script_worker_parent_guard() == 0): return 1
	args_init(argc, argv)
	args_declare_bool(c"script-worker")
	if (args_has_flag(c"script-worker")): return worker_test_child(args_value(c"page"))
	test_worker_protocol()
	test_worker_cancel()
	test_worker_descendant_cleanup()
	println(c"Script worker protocol, cancellation and descendant cleanup: OK")
	return 0
