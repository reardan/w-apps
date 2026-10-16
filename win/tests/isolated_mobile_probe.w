# Real parent event seam and unchanged M2 worker host; no script injection.
import lib.args
import lib.assert
import win.app

struct isolated_mobile_driver:
	win_browser browser
	ui_context ui
	ui_renderer renderer
	ui_theme theme
	gfx_window* window
	int width
	int height
	int field_hash
	int seen

void isolated_mobile_frame(isolated_mobile_driver* driver):
	win_browser_poll(&driver.browser)
	win_interactive_worker* worker = driver.browser.interactive
	if (worker.child == 0): println(driver.browser.status)
	asserts(c"isolated worker stays alive", worker.child != 0)
	asserts(c"parent owns no JavaScript realm", driver.browser.script == 0)
	assert_equal(0, driver.browser.script_failures)
	assert_equal(0, driver.browser.resource_failures)
	if (driver.browser.interactive_sequence != driver.seen && worker.surfaces.length):
		driver.seen = driver.browser.interactive_sequence
		win_frame_surface* surface = worker.surfaces[0]
		if (surface.pixels != 0):
			int hash = 1
			for y in range(min(200, surface.height)):
				for x in range(min(390, surface.width) * 4): hash = ((hash * 33) ^ (surface.pixels[y * surface.width * 4 + x] & 255)) & 2147483647
			driver.field_hash = hash
	ui_begin(&driver.ui, driver.width + 24, driver.height + 182)
	win_browser_frame(&driver.browser, &driver.ui, driver.width + 24, driver.height + 182)
	ui_end(&driver.ui)
	gfx_window_swap(driver.window)

void isolated_mobile_wait(isolated_mobile_driver* driver, int sequence):
	int start = time_monotonic_ms()
	while (driver.browser.interactive_sequence < sequence || driver.browser.interactive.busy || driver.browser.interactive.input_queue.length):
		isolated_mobile_frame(driver)
		asserts(c"isolated input and ACKs settle", time_monotonic_ms() - start < 120000)
		sleep_ms(2)

void isolated_mobile_event(isolated_mobile_driver* driver, int kind, int code, int x, int y):
	gfx_event event
	event.kind = kind
	event.code = code
	event.x = x
	event.y = y
	event.mods = 0
	ui_feed_event(&driver.ui, &event)
	win_native_push(&driver.browser.native_input, &event)
	driver.ui.input.mouse_x = x
	driver.ui.input.mouse_y = y

html_node* isolated_mobile_editor(isolated_mobile_driver* driver):
	for win_control* control in driver.browser.forms.controls:
		if (strcmp(win_attr(control.node, c"id"), c"text-input") == 0): return control.node
	return 0

int main(int argc, int argv):
	args_init(argc, argv)
	char* executable = args_value(c"browser")
	char* address = args_value(c"page")
	if (executable == 0 || address == 0): return 2
	isolated_mobile_driver driver
	driver.width = 390
	driver.height = 720
	driver.seen = -1
	driver.window = gfx_window_open(c"Isolated mobile input acceptance", 504, 902)
	assert1(driver.window != 0)
	assert1(ui_render_init(&driver.renderer))
	ui_theme_light(&driver.theme)
	ui_context_init(&driver.ui, &driver.renderer, &driver.theme)
	win_browser_init(&driver.browser, executable, address)
	driver.browser.isolated = 1
	driver.browser.execution_budget = 200000000
	win_browser_set_viewport(&driver.browser, driver.width, driver.height)
	win_navigate(&driver.browser, address, c"", -1)
	isolated_mobile_wait(&driver, 1)
	assert_equal(1, driver.browser.interactive.surfaces.length)
	int canvas_id = driver.browser.interactive.surfaces[0].node_id
	win_run* run = 0
	for win_run* candidate in driver.browser.page.runs:
		if (atoi(win_attr(candidate.node, c"data-win-node")) == canvas_id): run = candidate
	assert1(run != 0)
	int x = 12 + cast(int, run.x) + 30
	int y = 138 + cast(int, run.y - driver.browser.scroll.offset_y) + 150
	isolated_mobile_event(&driver, GFX_EVENT_MOUSE_DOWN, 1, x, y)
	isolated_mobile_frame(&driver)
	# Queue the release while the press is still waiting/in flight.
	isolated_mobile_event(&driver, GFX_EVENT_MOUSE_UP, 1, x, y)
	isolated_mobile_frame(&driver)
	asserts(c"busy input retained", driver.browser.interactive.input_queue.length > 0)
	isolated_mobile_wait(&driver, driver.browser.interactive_sequence + 3)
	html_node* editor = isolated_mobile_editor(&driver)
	assert1(editor != 0)
	assert_equal(atoi(win_attr(editor, c"data-win-node")), driver.browser.interactive.focus_node)
	assert_strings_equal(c"​", win_attr(editor, c"value"))
	int before = driver.field_hash
	char* ascii = c"Native"
	for i in range(strlen(ascii)):
		isolated_mobile_event(&driver, GFX_EVENT_KEY_DOWN, 38 + i, x, y)
		isolated_mobile_event(&driver, GFX_EVENT_CHAR, ascii[i], x, y)
		isolated_mobile_event(&driver, GFX_EVENT_KEY_UP, 38 + i, x, y)
	isolated_mobile_event(&driver, GFX_EVENT_CHAR, 233, x, y)
	isolated_mobile_event(&driver, GFX_EVENT_CHAR, 128578, x, y)
	isolated_mobile_frame(&driver)
	isolated_mobile_wait(&driver, driver.browser.interactive_sequence + 2)
	editor = isolated_mobile_editor(&driver)
	assert_strings_equal(c"​", win_attr(editor, c"value"))
	assert_equal(atoi(win_attr(editor, c"data-win-node")), driver.browser.interactive.focus_node)
	assert_equal(1, driver.browser.interactive.selection_start)
	assert_equal(1, driver.browser.interactive.selection_end)
	asserts(c"isolated native input updates rendered Wasm field", driver.field_hash != before)
	int typed = driver.field_hash
	isolated_mobile_event(&driver, GFX_EVENT_KEY_DOWN, 22, x, y)
	isolated_mobile_event(&driver, GFX_EVENT_CHAR, 8, x, y)
	isolated_mobile_event(&driver, GFX_EVENT_KEY_UP, 22, x, y)
	isolated_mobile_frame(&driver)
	isolated_mobile_wait(&driver, driver.browser.interactive_sequence + 2)
	asserts(c"isolated Backspace changes rendered field", driver.field_hash != typed)
	driver.width = 480
	isolated_mobile_frame(&driver)
	isolated_mobile_wait(&driver, driver.browser.interactive_sequence + 2)
	assert_equal(480, driver.browser.interactive.surfaces[0].width)
	win_browser_interactive_cancel(&driver.browser)
	isolated_mobile_wait(&driver, driver.browser.interactive_sequence + 1)
	win_browser_free(&driver.browser)
	win_network_state_clear()
	ui_render_destroy(&driver.renderer)
	gfx_window_destroy(driver.window)
	println(c"Unchanged isolated M2 native pointer focus, queued Unicode editing, Backspace, selection and resize: OK")
	return 0
