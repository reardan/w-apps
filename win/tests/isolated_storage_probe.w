import lib.args
import lib.assert
import win.interactive_worker

int storage_peak_poll

int storage_poll(win_interactive_worker* worker):
	int began = process_monotonic_ms()
	int result = win_interactive_poll(worker)
	int elapsed = process_monotonic_ms() - began
	if (elapsed > storage_peak_poll): storage_peak_poll = elapsed
	return result

void storage_ready(win_interactive_worker* worker):
	int began = process_monotonic_ms()
	while (worker.busy && worker.child != 0):
		storage_poll(worker)
		assert1(process_monotonic_ms() - began < 20000)
		sleep_ms(1)
	if (worker.status != 1): println(worker.error)
	assert_equal(1, worker.status)
	assert_equal(0, worker.script_failures)
	assert_equal(0, worker.resource_failures)

win_interactive_worker* storage_visit(char* executable, char* origin, char* route, win_storage_context* local_store, win_storage_context* session_store, char* title):
	char* address = strjoin(origin, route)
	win_interactive_worker* worker = win_interactive_start_owned(executable, address, c"", 20000, WIN_INTERACTIVE_LIMIT, 17, 200, 160, WIN_EXECUTION_DEFAULT, local_store, session_store)
	free(address)
	storage_ready(worker)
	if (strcmp(title, worker.title) != 0): println(worker.title)
	assert_strings_equal(title, worker.title)
	return worker

int main(int argc, int argv):
	args_init(argc, argv)
	char* executable = args_value(c"win")
	if (executable == 0): return 0 # Python owns HTTP fixture and X display.
	char* origin = args_value(c"origin")
	char* other = args_value(c"other")
	char* path = args_value(c"path")
	win_storage_context* local_store = win_storage_new()
	win_storage_context* session_a = win_storage_new()
	win_storage_context* session_b = win_storage_new()
	assert1(win_storage_open(local_store, path))
	win_interactive_worker* first = storage_visit(executable, origin, c"/write", local_store, session_a, c"written")
	win_interactive_worker* second = storage_visit(executable, origin, c"/read", local_store, session_b, c"green:null")
	win_interactive_free(first)
	first = storage_visit(executable, origin, c"/read", local_store, session_a, c"green:private")
	win_interactive_free(first)
	win_interactive_free(second)
	first = storage_visit(executable, other, c"/read", local_store, session_a, c"null:null")
	win_interactive_free(first)
	first = storage_visit(executable, other, c"/other", local_store, session_a, c"other")
	win_interactive_free(first)
	first = storage_visit(executable, origin, c"/unicode", local_store, session_a, c"value 😀")
	win_interactive_free(first)
	first = storage_visit(executable, origin, c"/bounds", local_store, session_a, c"bounds")
	win_interactive_free(first)
	# Concurrent children share the same serialized owner. Each RMW is two calls,
	# so test independent keys rather than promise atomic read/modify/write.
	char* address_a = strjoin(origin, c"/parallel-a")
	char* address_b = strjoin(origin, c"/parallel-b")
	first = win_interactive_start_owned(executable, address_a, c"", 20000, WIN_INTERACTIVE_LIMIT, 18, 200, 160, WIN_EXECUTION_DEFAULT, local_store, session_a)
	second = win_interactive_start_owned(executable, address_b, c"", 20000, WIN_INTERACTIVE_LIMIT, 19, 200, 160, WIN_EXECUTION_DEFAULT, local_store, session_b)
	int started = process_monotonic_ms()
	while (first.busy || second.busy):
		storage_poll(first)
		storage_poll(second)
		assert1(process_monotonic_ms() - started < 20000)
		sleep_ms(1)
	storage_ready(first)
	storage_ready(second)
	win_interactive_free(first)
	win_interactive_free(second)
	free(address_a)
	free(address_b)
	first = storage_visit(executable, origin, c"/parallel-read", local_store, session_a, c"A:B")
	win_interactive_free(first)
	# Redirects are checked before parsing/executing the destination, while
	# ordinary no-storage workers retain existing cross-origin navigation.
	first = storage_visit(executable, origin, c"/same", local_store, session_a, c"green:private")
	win_interactive_free(first)
	char* redirect = strjoin(origin, c"/cross")
	first = win_interactive_start_owned(executable, redirect, c"", 20000, WIN_INTERACTIVE_LIMIT, 20, 200, 160, WIN_EXECUTION_DEFAULT, local_store, session_a)
	while (first.busy && first.child != 0):
		storage_poll(first)
		sleep_ms(1)
	assert_equal(8, first.status)
	assert_strings_equal(c"Storage-enabled worker cannot navigate across origins", first.error)
	win_interactive_free(first)
	first = win_interactive_start_config(executable, redirect, c"", 20000, WIN_INTERACTIVE_LIMIT, 21, 200, 160, WIN_EXECUTION_DEFAULT)
	storage_ready(first)
	assert_strings_equal(c"cross-executed", first.title)
	win_interactive_free(first)
	free(redirect)
	win_storage_free(session_a)
	win_storage_free(session_b)
	win_storage_free(local_store)
	local_store = win_storage_new()
	assert1(win_storage_open(local_store, path))
	session_a = win_storage_new()
	first = storage_visit(executable, origin, c"/read", local_store, session_a, c"green:null")
	win_interactive_free(first)
	first = storage_visit(executable, other, c"/read", local_store, session_a, c"blue:null")
	win_interactive_free(first)
	win_storage_free(session_a)
	win_storage_free(local_store)
	print_int(c"storage parent peak poll milliseconds: ", storage_peak_poll)
	println(c"isolated storage shared tabs, sessions, restart and origins: OK")
	return 0
