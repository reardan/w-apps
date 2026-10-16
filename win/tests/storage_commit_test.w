import lib.assert
import lib.args
import win.storage_rpc

void storage_wait(win_storage_context* store, win_storage_job* job):
	int start = process_monotonic_ms()
	while (job.done == 0):
		win_storage_job_poll(store)
		assert1(process_monotonic_ms() - start < 3000)
		sleep_ms(1)

int main(int argc, int argv):
	args_init(argc, argv)
	char* helper = args_value(c"storage-helper")
	if (helper != 0):
		int action = atoi(args_value(c"storage-action"))
		if (action == 2 || ends_with(helper, c"normal")): return win_storage_helper(helper, action)
		char[4] header
		if (win_storage_read_exact(0, &header[0], 4) == 0): return 1
		int length = load_le32(&header[0])
		if (length < 12 || length > 1060876): return 1
		char* data = cast(char*, malloc(length))
		if (win_storage_read_exact(0, data, length) == 0): return 1
		if (ends_with(helper, c"after") || ends_with(helper, c"alien")):
			fs_replace_report report
			if (ends_with(helper, c"alien")): data[0] = 'X'
			fs_replace_durable_mode(helper, data, length, 384, &report)
		free(data)
		if (ends_with(helper, c"timeout")): sleep_ms(2000)
		return 1 # no reply: parent cannot assume whether rename occurred
	char* pid = itoa(getpid())
	char* prefix = strjoin(c"/tmp/win-storage-job-", pid)
	free(pid)
	char*[5] modes
	modes[0] = c"normal"
	modes[1] = c"before"
	modes[2] = c"after"
	modes[3] = c"alien"
	modes[4] = c"timeout"
	for i in range(5):
		char* path = strjoin(prefix, modes[i])
		win_storage_context* store = win_storage_new()
		assert1(win_storage_open(store, path))
		win_storage_job* job = win_storage_job_start(store, args_program(), c"http://example.test:80", 1, c"key", c"value", -1)
		assert1(job != 0)
		assert1(store.pending != 0)
		assert_equal(0, store.entries.length)
		assert1(win_storage_job_start(store, args_program(), c"http://example.test:80", 1, c"other", c"x", -1) == 0)
		if (i == 4): job.timeout_ms = 100
		storage_wait(store, job)
		assert1(store.pending == 0)
		if (i == 0 || i == 2):
			assert_equal(1, store.entries.length)
			assert_strings_equal(c"value", store.entries[0].value)
		else: assert_equal(0, store.entries.length)
		if (i == 0): assert_equal(0, job.result.error)
		else: assert_equal(3, job.result.error)
		assert_equal(i == 3, store.poisoned)
		win_storage_job_release(job)
		# A closed content worker releases its reference; the accepted commit
		# remains owned and polled by the parent until publication completes.
		if (i == 0):
			job = win_storage_job_start(store, args_program(), c"http://example.test:80", 1, c"key", c"next", -1)
			win_storage_job_release(job)
			while (store.pending != 0):
				win_storage_job_poll(store)
				sleep_ms(1)
			assert_strings_equal(c"next", store.entries[0].value)
		win_storage_free(store)
		unlink(path)
		char* lock = strjoin(path, c".lock")
		unlink(lock)
		free(lock)
		free(path)
	free(prefix)
	# Header and payload validation rejects stale IDs, malformed UTF-8/NUL,
	# oversized allocation requests and operation/store selectors before access.
	string_builder* wire = string_new()
	win_storage_wire_header(wire, 1, WIN_STORAGE_REQUEST)
	for i in range(24): string_append_char(wire, 0)
	store_le32(wire.data + 8, 24)
	store_le32(wire.data + 24, 9)
	store_le32(wire.data + 36, -1)
	assert1(win_storage_request_valid(wire.data, wire.length, 9, 1))
	assert1(win_storage_request_valid(wire.data, wire.length, 10, 1) == 0)
	assert1(win_storage_request_valid(wire.data, wire.length, 9, 2) == 0)
	for i in range(wire.length): assert1(win_storage_request_valid(wire.data, i, 9, 1) == 0)
	store_le32(wire.data + 40, 2147483647)
	assert1(win_storage_request_valid(wire.data, wire.length, 9, 1) == 0)
	store_le32(wire.data + 40, 1)
	store_le32(wire.data + 8, 25)
	string_append_char(wire, 0)
	assert1(win_storage_request_valid(wire.data, wire.length, 9, 1) == 0)
	wire.data[48] = cast(char, 255)
	assert1(win_storage_request_valid(wire.data, wire.length, 9, 1) == 0)
	wire.data[48] = 'a'
	assert1(win_storage_request_valid(wire.data, wire.length, 9, 1))
	store_le32(wire.data + 28, 2)
	assert1(win_storage_request_valid(wire.data, wire.length, 9, 1) == 0)
	string_free(wire)
	println(c"parent storage commit/reconciliation and RPC bounds: OK")
	return 0
