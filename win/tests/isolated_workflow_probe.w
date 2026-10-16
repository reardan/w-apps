# Exercise unchanged Preact through the isolated worker native input pipeline.
# No eval/injected script changes application state. Queue entries use the same
# gfx_event -> ui_feed_event + win_native_push seam as win_app_begin_window.
import lib.args
import lib.assert
import lib.stream
import win.app

extern int XResizeWindow(int display, int window, int width, int height)

struct workflow_driver:
	win_browser browser
	ui_context ui
	ui_renderer renderer
	ui_theme theme
	gfx_window* window
	int width
	int height

void workflow_frame(workflow_driver* driver):
	win_browser_poll(&driver.browser)
	ui_begin(&driver.ui, driver.width, driver.height)
	win_browser_frame(&driver.browser, &driver.ui, driver.width, driver.height)
	ui_end(&driver.ui)
	asserts(c"isolated parent has no script realm", driver.browser.script == 0)
	if (driver.browser.interactive.child == 0): println(driver.browser.status)
	asserts(c"isolated workflow worker stays alive", driver.browser.interactive.child != 0)
	assert_equal(0, driver.browser.script_failures)
	assert_equal(0, driver.browser.resource_failures)
	gfx_window_swap(driver.window)

html_node* workflow_node(workflow_driver* driver, char* id):
	if (driver.browser.page == 0): return 0
	html_node* node = driver.browser.page.html.allocations
	while (node != 0):
		if (strcmp(win_attr(node, c"id"), id) == 0 && win_pointer_connected(driver.browser.page, node)): return node
		node = node.allocation_next
	return 0

void workflow_wait(workflow_driver* driver, char* id, char* text):
	int started = time_monotonic_ms()
	int found = 0
	while (time_monotonic_ms() - started < 30000 && found == 0):
		workflow_frame(driver)
		html_node* node = workflow_node(driver, id)
		if (node != 0):
			char* content = win_dom_text(node)
			found = text == 0 || strcmp(content, text) == 0
			free(content)
		if (found == 0): sleep_ms(5)
	if (found == 0):
		println(driver.browser.status)
		println(id)
		if (text != 0): println(text)
		html_node* actual = workflow_node(driver, id)
		if (actual != 0):
			char* content = win_dom_text(actual)
			println(content)
			free(content)
	asserts(c"unchanged workflow reaches expected visible state", found)

void workflow_event(workflow_driver* driver, int kind, int code, int mods, int x, int y):
	gfx_event event
	event.kind = kind
	event.code = code
	event.mods = mods
	event.x = x
	event.y = y
	ui_feed_event(&driver.ui, &event)
	win_native_push(&driver.browser.native_input, &event)

void workflow_settle(workflow_driver* driver):
	int started = time_monotonic_ms()
	while (driver.browser.interactive.busy || driver.browser.interactive.input_queue.length):
		workflow_frame(driver)
		asserts(c"isolated input settles behind frame ACK", time_monotonic_ms() - started < 30000)
		sleep_ms(2)

win_box* workflow_box(workflow_driver* driver, char* id):
	html_node* node = workflow_node(driver, id)
	assert1(node != 0)
	for win_box* box in driver.browser.page.boxes:
		if (box.node == node && box.hidden == 0 && box.width > 0.0 && box.height > 0.0): return box
	asserts(c"workflow control has visible layout", 0)
	return 0

void workflow_click(workflow_driver* driver, char* id):
	workflow_frame(driver)
	workflow_settle(driver)
	win_box* box = workflow_box(driver, id)
	if (box.y < driver.browser.scroll.offset_y || box.y + box.height > driver.browser.scroll.offset_y + cast(float32, driver.height - 182)):
		int desired = cast(int, box.y) - 20
		if (desired < 0): desired = 0
		int delta = desired - cast(int, driver.browser.scroll.offset_y)
		workflow_event(driver, GFX_EVENT_SCROLL_PIXELS, delta, 0, 24, 150)
		workflow_frame(driver)
		workflow_settle(driver)
		box = workflow_box(driver, id)
	int x = cast(int, 12.0 + box.x + box.width / 2.0)
	int y = cast(int, 138.0 + box.y - driver.browser.scroll.offset_y + box.height / 2.0)
	asserts(c"workflow click stays inside viewport", x >= 12 && x < driver.width - 12 && y >= 138 && y < driver.height - 44)
	workflow_event(driver, GFX_EVENT_MOUSE_DOWN, 1, 0, x, y)
	workflow_frame(driver)
	workflow_event(driver, GFX_EVENT_MOUSE_UP, 1, 0, x, y)
	workflow_frame(driver)
	workflow_settle(driver)

void workflow_type(workflow_driver* driver, char* text):
	workflow_click(driver, c"name")
	int focus = atoi(win_attr(workflow_node(driver, c"name"), c"data-win-node"))
	assert_equal(focus, driver.browser.interactive.focus_node)
	workflow_event(driver, GFX_EVENT_CHAR, 1, GFX_MOD_CTRL, 0, 0)
	for i in range(strlen(text)): workflow_event(driver, GFX_EVENT_CHAR, text[i], 0, 0, 0)
	workflow_frame(driver)
	workflow_settle(driver)
	assert_strings_equal(text, win_attr(workflow_node(driver, c"name"), c"value"))
	assert_equal(strlen(text), driver.browser.interactive.selection_start)
	assert_equal(strlen(text), driver.browser.interactive.selection_end)

void workflow_screenshot(workflow_driver* driver, char* path):
	if (path == 0): return
	# Render again and read the back buffer before swapping.
	ui_begin(&driver.ui, driver.width, driver.height)
	win_browser_frame(&driver.browser, &driver.ui, driver.width, driver.height)
	ui_end(&driver.ui)
	glFinish()
	int width = driver.width - 24
	int height = driver.height - 182
	char* pixels = cast(char*, malloc(width * height * 4))
	glReadPixels(12, 44, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels)
	wstream* out = stream_open_write(path)
	assert1(out != 0)
	stream_write_cstr(out, c"P6\n")
	stream_write_int(out, width)
	stream_write_cstr(out, c" ")
	stream_write_int(out, height)
	stream_write_cstr(out, c"\n255\n")
	char* row = cast(char*, malloc(width * 3))
	int y = height - 1
	while (y >= 0):
		for x in range(width):
			for c in range(3): row[x * 3 + c] = pixels[(y * width + x) * 4 + c]
		stream_write(out, row, width * 3)
		y = y - 1
	io_result result
	assert_equal(IO_OK, stream_close_checked(out, &result))
	free(row)
	free(pixels)

void workflow_round(workflow_driver* driver):
	workflow_type(driver, c"Ada")
	workflow_click(driver, c"save")
	workflow_wait(driver, c"result", c"Saved: Ada")
	workflow_type(driver, c"error")
	workflow_click(driver, c"save")
	workflow_wait(driver, c"result", c"Failed: HTTP 503")
	workflow_type(driver, c"slow")
	workflow_click(driver, c"save")
	workflow_wait(driver, c"result", c"Saving")
	workflow_click(driver, c"cancel")
	workflow_wait(driver, c"result", c"Cancelled")
	int start = time_monotonic_ms()
	while (time_monotonic_ms() - start < 2300):
		workflow_frame(driver)
		sleep_ms(10)
	workflow_wait(driver, c"result", c"Cancelled")
	workflow_click(driver, c"settings-route")
	workflow_wait(driver, c"theme", 0)
	if (strcmp(win_attr(workflow_node(driver, c"theme"), c"value"), c"green")): workflow_click(driver, c"theme")
	assert_strings_equal(c"green", win_attr(workflow_node(driver, c"theme"), c"value"))
	int child = driver.browser.interactive.child.pid
	win_history_go(&driver.browser, -1)
	workflow_wait(driver, c"name", 0)
	assert_strings_equal(c"Workflow: form", driver.browser.page.title)
	assert_equal(child, driver.browser.interactive.child.pid)
	assert_strings_equal(c"slow", win_attr(workflow_node(driver, c"name"), c"value"))
	workflow_wait(driver, c"result", c"Cancelled")
	win_history_go(&driver.browser, 1)
	workflow_wait(driver, c"theme", 0)
	assert_strings_equal(c"Workflow: settings", driver.browser.page.title)
	assert_equal(child, driver.browser.interactive.child.pid)
	workflow_wait(driver, c"result", c"Cancelled")
	assert_strings_equal(c"green", win_attr(workflow_node(driver, c"theme"), c"value"))

int main(int argc, int argv):
	args_init(argc, argv)
	char* executable = args_value(c"browser")
	char* address = args_value(c"page")
	char* storage = args_value(c"storage")
	if (executable == 0 || address == 0 || storage == 0): return 2
	workflow_driver driver
	driver.width = 824
	driver.height = 782
	driver.window = gfx_window_open(c"Isolated unchanged Preact workflow acceptance", driver.width, driver.height)
	assert1(driver.window != 0)
	assert1(ui_render_init(&driver.renderer))
	ui_theme_light(&driver.theme)
	ui_context_init(&driver.ui, &driver.renderer, &driver.theme)
	win_browser_init(&driver.browser, executable, address)
	driver.browser.isolated = 1
	assert1(win_storage_open(driver.browser.local_storage, storage))
	win_navigate(&driver.browser, address, c"", -1)
	char* expected = args_value(c"check-theme")
	if (expected != 0):
		workflow_wait(&driver, c"theme", 0)
		assert_strings_equal(expected, win_attr(workflow_node(&driver, c"theme"), c"value"))
	else:
		workflow_wait(&driver, c"result", c"Ready")
		assert_strings_equal(c"Workflow: form", driver.browser.page.title)
		workflow_round(&driver)
		workflow_screenshot(&driver, args_value(c"screenshot"))
		driver.width = 384
		driver.height = 822
		XResizeWindow(driver.window.display, driver.window.window, driver.width, driver.height)
		XSync(driver.window.display, 0)
		assert1(gfx_window_poll(driver.window))
		workflow_frame(&driver)
		workflow_settle(&driver)
		workflow_frame(&driver)
		workflow_settle(&driver)
		assert_equal(360, driver.browser.viewport_width)
		assert_equal(640, driver.browser.viewport_height)
		assert_equal(driver.browser.width, driver.browser.page.width)
		for i in range(driver.browser.page.boxes.length):
			win_box* box = driver.browser.page.boxes[i]
			if (win_tag(box.node, c"main")): asserts(c"responsive main fits narrow viewport", box.width <= 360.0)
		workflow_click(&driver, c"form-route")
		workflow_wait(&driver, c"name", 0)
		workflow_round(&driver)
		win_navigate(&driver.browser, driver.browser.address, c"", -2)
		workflow_wait(&driver, c"theme", 0)
		assert_strings_equal(c"green", win_attr(workflow_node(&driver, c"theme"), c"value"))
		workflow_screenshot(&driver, args_value(c"narrow-screenshot"))
	assert_equal(0, driver.browser.script_failures)
	assert_equal(0, driver.browser.resource_failures)
	win_browser_free(&driver.browser)
	win_network_state_clear()
	ui_render_destroy(&driver.renderer)
	gfx_window_destroy(driver.window)
	println(c"{\"status\":\"PASS\",\"path\":\"unchanged Preact module, isolated native input pipeline\"}")
	return 0
