import lib.args
import win.interactive_worker

int main(int argc, int argv):
	args_init(argc, argv)
	win_sandbox_root = args_value(c"root")
	win_sandbox_origin = args_value(c"origin")
	char* page = args_value(c"page")
	win_interactive_worker* worker = win_interactive_start_config(args_value(c"win"), page, page, 15000, WIN_INTERACTIVE_LIMIT, 0, 800, 600, WIN_EXECUTION_DEFAULT)
	int deadline = process_monotonic_ms() + 18000
	int success = 0
	while (process_monotonic_ms() < deadline):
		int before = process_monotonic_ms()
		int result = win_interactive_poll(worker)
		if (process_monotonic_ms() - before > 500):
			println2(c"Parent broker poll blocked")
			break
		if (result < 0):
			println2(worker.error)
			break
		if (result == 1):
			if (strcmp(worker.title, c"BROKER-PASS") == 0):
				println(worker.html)
				success = 1
				break
			win_interactive_request(worker, 1, 0, c"")
		process_sleep_ms(2)
	win_interactive_free(worker)
	if (success == 0): return 1
	return 0
