import lib.assert
import lib.args
import win.app

void interactive_browser_wait(win_app* app, win_browser* browser):
	int start = process_monotonic_ms()
	while (win_browser_loading(browser)):
		win_app_poll(app)
		asserts(c"isolated page settles", process_monotonic_ms() - start < 10000)
		process_sleep_ms(1)
	asserts(c"snapshot exists", browser.page != 0)
	asserts(c"no parent script realm", browser.script == 0 && browser.fetches == 0)

int main(int argc, int argv):
	args_init(argc, argv)
	win_app app
	win_app_init(&app, args_get(1), args_get(2))
	app.isolated = 1
	assert_equal(1, win_app_open(&app, args_get(2), c""))
	win_browser* first = app.tabs[0]
	asserts(c"live child starts asynchronously", first.interactive != 0 && first.interactive.busy)
	asserts(c"no parent document loader", first.load == 0)
	interactive_browser_wait(&app, first)
	assert_strings_equal(c"Welcome to Win", first.page.title)
	int first_pid = first.interactive.child.pid
	assert_equal(1, win_interactive_request(first.interactive, 1, 0, c""))
	interactive_browser_wait(&app, first)
	assert_equal(first_pid, first.interactive.child.pid)
	assert_equal(1, win_app_open(&app, args_get(2), c""))
	int second_pid = app.tabs[1].interactive.child.pid
	asserts(c"tabs own separate children", second_pid != first_pid)
	win_app_close(&app, 1)
	assert_equal(-10, wait4(second_pid, 0, 1, 0))
	win_navigate(first, args_get(2), c"", -2)
	assert_equal(-10, wait4(first_pid, 0, 1, 0))
	interactive_browser_wait(&app, first)
	first_pid = first.interactive.child.pid
	win_stop(first)
	assert_equal(-10, wait4(first_pid, 0, 1, 0))
	asserts(c"stop detaches worker", first.interactive == 0)
	asserts(c"stopped snapshot remains displayable", first.page != 0)
	win_app_free(&app)
	println(c"Isolated browser tabs, inert snapshots, tick, reload, stop and reap: OK")
	return 0
