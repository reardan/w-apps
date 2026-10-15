# Linux x64 headless execution boundary, NOT an OS sandbox. A fresh exec owns
# the page, interpreter and raw DOM pointers; only rendered UTF-8 text returns.
# Filesystem/network authority remains unchanged. Interactive pages still use
# the in-process realm. No preflight evaluation or DOM replay occurs here.
import win.browser
import lib.process
import lib.poll

const int WIN_SCRIPT_WORKER_LIMIT = 8388608
const int WIN_SCRIPT_WORKER_HEADER = 24

struct win_script_worker:
	process* child
	string_builder* buffer
	char* text                 # borrowed from buffer, published only on success
	char* error                # static diagnostic, never free separately
	int started
	int timeout_ms
	int limit
	int finished
	int eof
	int status                # 1 success, 2 timeout, 3 exit/crash, 4 protocol,
	                          # 5 size, 6 cancelled, 7 start/configuration
	int script_failures
	int resource_failures

# Linux PR_SET_PDEATHSIG covers separately grouped resource descendants too.
# The expected PID is supplied before exec, closing the parent-death race.
# This is lifecycle cleanup, not a privilege or syscall restriction.
int win_script_worker_parent_guard():
	char* expected = env_get(c"WIN_SCRIPT_WORKER_PARENT")
	if (expected == 0): return 1
	int parent = atoi(expected)
	if (parent <= 1): return 0
	if (syscall7(157, 1, sigkill, 0, 0, 0, 0) < 0): return 0
	return syscall(110, 0, 0, 0) == parent

char** win_script_worker_environment():
	string_builder* pid = string_new()
	string_append_int(pid, getpid())
	char** result = env_copy_with(env_current(), c"WIN_SCRIPT_WORKER_PARENT", pid.data)
	string_free(pid)
	return result

void win_script_worker_environment_free(char** env):
	for i in range(env_vector_count(env)):
		char* entry = env_entry_at(env, i)
		if (env_match_name(entry, c"WIN_SCRIPT_WORKER_PARENT") >= 0): free(entry)
	free(cast(void*, env))

void win_script_worker_fail(win_script_worker* worker, int status, char* error):
	worker.status = status
	worker.error = error
	worker.finished = 1
	worker.text = 0
	if (worker.child != 0):
		process_free(worker.child)
		worker.child = 0

# Nonblocking start; caller polls and may cancel/free at any time. Timeout is
# a total wall-clock deadline including loading, execution and response drain.
win_script_worker* win_script_worker_start(char* executable, char* address, char* home, int timeout_ms, int max_bytes):
	win_script_worker* worker = new win_script_worker()
	worker.buffer = string_new()
	worker.started = process_monotonic_ms()
	worker.timeout_ms = timeout_ms
	worker.limit = max_bytes
	if (timeout_ms <= 0 || timeout_ms > 120000 || max_bytes < 24 || max_bytes > WIN_SCRIPT_WORKER_LIMIT):
		win_script_worker_fail(worker, 7, c"Invalid script worker limits")
		return worker
	string_builder* limit = string_new()
	string_append_int(limit, max_bytes)
	spawn_options* options = spawn_options_new()
	options.stdin_mode = process_null
	options.stdout_mode = process_pipe
	options.stderr_mode = process_null
	options.new_group = 1
	options.env = win_script_worker_environment()
	char*[9] argv
	argv[0] = executable
	argv[1] = c"--script-worker"
	argv[2] = c"--page"
	argv[3] = address
	argv[4] = c"--home"
	argv[5] = home
	argv[6] = c"--worker-limit"
	argv[7] = limit.data
	argv[8] = 0
	worker.child = process_spawn(executable, &argv[0], options)
	win_script_worker_environment_free(options.env)
	free(options)
	string_free(limit)
	if (worker.child == 0): win_script_worker_fail(worker, 7, c"Cannot start script worker")
	return worker

# Versioned response: 8 magic bytes, four little-endian int32 fields
# (payload length, script failures, resource failures, reserved=0), then text.
# Declared lengths never drive allocations. Bound the pipe before decoding.
int win_script_worker_validate(win_script_worker* worker):
	char* data = worker.buffer.data
	int length = worker.buffer.length
	if (length < 24 || starts_with(data, c"WINSW001") == 0): return 0
	int count = load_int32(data + 8)
	int scripts = load_int32(data + 12)
	int resources = load_int32(data + 16)
	if (count < 0 || count != length - 24 || scripts < 0 || scripts > 100000 || resources < 0 || resources > 100000 || load_int32(data + 20) != 0): return 0
	if (utf8_validate_bytes(data + 24, count) == 0): return 0
	for i in range(count):
		if (data[24 + i] == 0): return 0
	worker.script_failures = scripts
	worker.resource_failures = resources
	return 1

int win_script_worker_poll(win_script_worker* worker):
	if (worker.finished): return 1
	if (process_monotonic_ms() - worker.started >= worker.timeout_ms):
		win_script_worker_fail(worker, 2, c"Script worker timed out")
		return 1
	char[8192] chunk
	# Drain at most 64 KiB per call, keeping a parent event loop responsive.
	for i in range(8):
		if (worker.eof): break
		int ready = poll_single(worker.child.stdout_fd, poll_in, 0)
		if (ready == 0 || ready == -4): break
		if (ready < 0):
			win_script_worker_fail(worker, 4, c"Script worker pipe failed")
			return 1
		int count = read(worker.child.stdout_fd, &chunk[0], 8192)
		if (count == -4): break
		if (count < 0):
			win_script_worker_fail(worker, 4, c"Script worker read failed")
			return 1
		if (count == 0):
			worker.eof = 1
			break
		if (count > worker.limit - worker.buffer.length):
			win_script_worker_fail(worker, 5, c"Script worker response exceeds limit")
			return 1
		string_append_bytes(worker.buffer, &chunk[0], count)
		if (worker.buffer.length >= 24):
			int declared = load_int32(worker.buffer.data + 8)
			if (declared < 0 || declared > worker.limit - 24):
				win_script_worker_fail(worker, 5, c"Script worker declared size exceeds limit")
				return 1
	if (worker.eof == 0): return 0
	int status = process_try_wait(worker.child)
	if (status == process_status_running): return 0
	if (status != 0):
		win_script_worker_fail(worker, 3, c"Script worker exited unsuccessfully")
		return 1
	if (win_script_worker_validate(worker) == 0):
		win_script_worker_fail(worker, 4, c"Invalid script worker response")
		return 1
	process_free(worker.child)
	worker.child = 0
	worker.text = worker.buffer.data + 24
	worker.status = 1
	worker.finished = 1
	return 1

void win_script_worker_cancel(win_script_worker* worker):
	if (worker == 0 || worker.finished): return
	win_script_worker_fail(worker, 6, c"Script worker cancelled")

void win_script_worker_free(win_script_worker* worker):
	if (worker == 0): return
	win_script_worker_cancel(worker)
	string_free(worker.buffer)
	free(worker)

int win_script_worker_append(string_builder* output, char* text, int limit):
	int count = strlen(text)
	if (count > limit - output.length): return 0
	string_append_bytes(output, text, count)
	return 1

# Child-only entry. All parsing/loading/interpreter/layout work lives here.
# External scripts use the ordinary bounded loader and resource policy.
int win_script_worker_execute(char* executable, char* address, char* home, int limit):
	if (limit < 24 || limit > WIN_SCRIPT_WORKER_LIMIT): return 2
	char** previous = env_current()
	char** environment = win_script_worker_environment()
	environ_ptr = cast(int, environment)
	win_browser browser
	win_browser_init(&browser, executable, home)
	win_navigate(&browser, address, c"", -1)
	while (win_browser_loading(&browser)):
		win_browser_poll(&browser)
		sleep_ms(2)
	int code = 1
	if (browser.page != 0 && browser.page.truncated == 0):
		string_builder* output = string_new()
		for i in range(24): string_append_char(output, 0)
		char* magic = c"WINSW001"
		for i in range(8): output.data[i] = magic[i]
		int ok = win_script_worker_append(output, browser.address, limit)
		if (ok): ok = win_script_worker_append(output, c"\n", limit)
		if (ok): ok = win_script_worker_append(output, browser.page.title, limit)
		if (ok): ok = win_script_worker_append(output, c"\n", limit)
		for i in range(browser.page.runs.length):
			if (ok == 0): break
			if (browser.page.runs[i].hidden): continue
			ok = win_script_worker_append(output, browser.page.runs[i].text, limit)
			if (ok): ok = win_script_worker_append(output, c" ", limit)
		if (ok): ok = win_script_worker_append(output, c"\n", limit)
		if (ok):
			save_int32(output.data + 8, output.length - 24)
			save_int32(output.data + 12, browser.script_failures)
			save_int32(output.data + 16, browser.resource_failures)
			int at = 0
			while (at < output.length):
				int count = write(1, output.data + at, output.length - at)
				if (count == -4): continue
				if (count <= 0): break
				at = at + count
			if (at == output.length): code = 0
		string_free(output)
	win_browser_free(&browser)
	win_network_state_clear()
	environ_ptr = cast(int, previous)
	win_script_worker_environment_free(environment)
	return code
