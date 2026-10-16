import lib.args
import lib.assert
import win.browser

html_node* isolated_history_node(win_browser* browser, char* id):
	if (browser.page == 0): return 0
	html_node* node = browser.page.html.allocations
	while (node != 0):
		if (strcmp(win_attr(node, c"id"), id) == 0): return node
		node = node.allocation_next
	return 0

void isolated_history_ready(win_browser* browser, char* title):
	int started = process_monotonic_ms()
	while (1):
		win_browser_poll(browser)
		if (browser.interactive.child == 0): println(browser.status)
		assert1(browser.interactive.child != 0)
		assert_equal(0, browser.script_failures)
		assert_equal(0, browser.resource_failures)
		if (browser.page != 0 && strcmp(browser.page.title, title) == 0 && browser.interactive.busy == 0 && browser.interactive.input_queue.length == 0): break
		if (process_monotonic_ms() - started > 15000):
			println(browser.status)
			if (browser.page != 0): println(browser.page.title)
			println(title)
			assert1(0)
		sleep_ms(1)

void isolated_history_event(win_browser* browser, int kind, int code, int x, int y):
	win_interactive_worker* worker = browser.interactive
	win_interactive_input* input = new win_interactive_input()
	input.generation = worker.generation
	input.document = worker.document_generation
	input.width = browser.viewport_width
	input.height = browser.viewport_height
	input.mouse_x = x
	input.mouse_y = y
	gfx_event event
	event.kind = kind
	event.code = code
	event.x = x
	event.y = y
	event.mods = 0
	win_native_push(&input.native, &event)
	assert1(win_interactive_enqueue(worker, input))

void isolated_history_click(win_browser* browser):
	html_node* node = isolated_history_node(browser, c"push")
	assert1(node != 0)
	int x = atoi(win_attr(node, c"data-x"))
	int y = atoi(win_attr(node, c"data-y"))
	isolated_history_event(browser, GFX_EVENT_MOUSE_DOWN, 1, x, y)
	isolated_history_event(browser, GFX_EVENT_MOUSE_UP, 1, x, y)

int main(int argc, int argv):
	args_init(argc, argv)
	char* executable = args_value(c"win")
	char* origin = args_value(c"origin")
	if (executable == 0 || origin == 0): return 2
	win_browser browser
	win_browser_init(&browser, executable, origin)
	browser.isolated = 1
	win_browser_set_viewport(&browser, 800, 600)
	char* address = strjoin(origin, c"/first")
	win_navigate(&browser, address, c"", -1)
	free(address)
	isolated_history_ready(&browser, c"Ready")
	int child = browser.interactive.child.pid
	# The queue initially has no Back target. The click creates one before
	# Back executes; the following character must reach popstate's focus.
	isolated_history_click(&browser)
	win_history_go(&browser, -1)
	isolated_history_event(&browser, GFX_EVENT_CHAR, 'Z', 0, 0)
	isolated_history_ready(&browser, c"typed:Z")
	assert_equal(child, browser.interactive.child.pid)
	assert_equal(0, browser.current)
	assert_equal(2, browser.history.length)
	assert_strings_equal(c"Z", win_attr(isolated_history_node(&browser, c"name"), c"value"))
	assert_equal(1, browser.interactive.selection_start)
	assert_equal(1, browser.interactive.selection_end)
	win_history_go(&browser, 1)
	win_history_go(&browser, -1)
	isolated_history_ready(&browser, c"pop:0:3")
	assert_equal(child, browser.interactive.child.pid)
	assert_strings_equal(c"Z", win_attr(isolated_history_node(&browser, c"name"), c"value"))
	# A replaced worker has an external prefix. Earlier input can pushState,
	# changing Back from a cross-realm fallback into same-realm traversal.
	address = strjoin(origin, c"/second")
	win_navigate(&browser, address, c"", -1)
	free(address)
	isolated_history_ready(&browser, c"Ready")
	child = browser.interactive.child.pid
	isolated_history_click(&browser)
	win_history_go(&browser, -1)
	isolated_history_ready(&browser, c"pop:0:1")
	assert_equal(child, browser.interactive.child.pid)
	assert_equal(1, browser.current)
	# Now a plain Back crosses the retired realm and explicitly reloads.
	win_history_go(&browser, -1)
	isolated_history_ready(&browser, c"Ready")
	assert1(browser.interactive.child.pid != child)
	assert_equal(0, browser.current)
	assert_contains(browser.address, c"/first")
	# Child death never auto-restarts; explicit Forward uses reload fallback.
	child = browser.interactive.child.pid
	process_kill_group(browser.interactive.child, 9)
	int began = process_monotonic_ms()
	while (browser.interactive.child != 0 && process_monotonic_ms() - began < 10000):
		win_browser_poll(&browser)
		sleep_ms(1)
	assert1(browser.interactive.child == 0)
	win_history_go(&browser, 1)
	isolated_history_ready(&browser, c"Ready")
	assert1(browser.interactive.child.pid != child)
	assert_contains(browser.address, c"/second")
	win_browser_free(&browser)
	win_network_state_clear()
	println(c"Isolated history FIFO push/back/type, retained realm, cross-realm and crash fallback: OK")
	return 0
