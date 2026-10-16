# Unchanged M2 host + Wasm application, driven through the app's native queue.
# Assertions inspect the rendered Wasm field and memory, never mutate JS state.
import lib.args
import lib.assert
import lib.stream
import win.app

extern int XResizeWindow(int display, int window, int width, int height)

struct mobile_driver:
	win_browser browser
	ui_context ui
	ui_renderer renderer
	ui_theme theme
	gfx_window* window
	int width
	int height

void mobile_frame(mobile_driver* driver):
	win_browser_poll(&driver.browser)
	ui_begin(&driver.ui, driver.width, driver.height)
	win_browser_frame(&driver.browser, &driver.ui, driver.width, driver.height)
	ui_end(&driver.ui)
	if (driver.browser.script != 0):
		if (driver.browser.script.failures): println(driver.browser.script.error)
		assert_equal(0, driver.browser.script.failures)
	assert_equal(0, driver.browser.resource_failures)
	gfx_window_swap(driver.window)

void mobile_event(mobile_driver* driver, int kind, int code, int x, int y):
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

win_dom_binding* mobile_canvas(mobile_driver* driver):
	if (driver.browser.script == 0): return 0
	for i in range(driver.browser.script.bindings.length):
		win_dom_binding* binding = driver.browser.script.bindings[i]
		if (binding.canvas != 0 && binding.canvas.context != 0): return binding
	return 0

wwasm* mobile_machine(mobile_driver* driver):
	if (driver.browser.script == 0): return 0
	for i in range(driver.browser.script.wasm.objects.length):
		win_wasm_object* object = driver.browser.script.wasm.objects[i]
		if (object.kind == 2): return object.machine
	return 0

int mobile_memory_contains(wwasm* machine, char* text):
	int length = strlen(text) + 1
	int size = machine.pages * 65536
	for i in range(size - length):
		int found = 1
		for j in range(length):
			if (machine.memory[i + j] != text[j]):
				found = 0
				break
		if (found): return 1
	return 0

int mobile_field_pixels(win_canvas* canvas):
	asserts(c"rendered mobile canvas context", win_canvas_enter(canvas))
	int width = min(canvas.width, 390)
	int height = min(canvas.height, 200)
	int length = width * height * 4
	char* pixels = cast(char*, malloc(length))
	glReadPixels(0, canvas.height - height, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels)
	int hash = 1
	for i in range(length): hash = ((hash * 33) ^ (pixels[i] & 255)) & 0x7fffffff
	free(pixels)
	win_canvas_leave(canvas)
	return hash

void mobile_shot(win_canvas* canvas, char* path):
	if (path == 0): return
	assert1(win_canvas_enter(canvas))
	int width = canvas.width
	int height = canvas.height
	char* pixels = cast(char*, malloc(width * height * 4))
	glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels)
	win_canvas_leave(canvas)
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

int main(int argc, int argv):
	args_init(argc, argv)
	char* executable = args_value(c"browser")
	char* address = args_value(c"page")
	if (executable == 0 || address == 0): return 2
	mobile_driver driver
	driver.width = 414
	driver.height = 902
	driver.window = gfx_window_open(c"Unchanged mobile native input acceptance", 414, 902)
	assert1(driver.window != 0)
	assert1(ui_render_init(&driver.renderer))
	ui_theme_light(&driver.theme)
	ui_context_init(&driver.ui, &driver.renderer, &driver.theme)
	win_script_graphics_available = 1
	win_browser_init(&driver.browser, executable, address)
	driver.browser.execution_budget = 200000000
	win_browser_set_viewport(&driver.browser, 390, 720)
	win_navigate(&driver.browser, address, c"", -1)
	int started = time_monotonic_ms()
	while ((mobile_canvas(&driver) == 0 || mobile_machine(&driver) == 0) && time_monotonic_ms() - started < 120000):
		mobile_frame(&driver)
		sleep_ms(16)
	win_dom_binding* binding = mobile_canvas(&driver)
	wwasm* machine = mobile_machine(&driver)
	asserts(c"unchanged mobile application starts", binding != 0 && machine != 0)
	mobile_frame(&driver)
	win_run* run = 0
	for i in range(driver.browser.page.runs.length):
		if (driver.browser.page.runs[i].node == binding.node): run = driver.browser.page.runs[i]
	asserts(c"canvas rendered in document geometry", run != 0)
	int x = 12 + cast(int, run.x) + 30
	int y = 138 + cast(int, run.y - driver.browser.scroll.offset_y) + 150
	mobile_event(&driver, GFX_EVENT_MOUSE_DOWN, 1, x, y)
	mobile_frame(&driver)
	mobile_event(&driver, GFX_EVENT_MOUSE_UP, 1, x, y)
	mobile_frame(&driver)
	html_node* editor = driver.browser.script.active_focus
	asserts(c"W field requests real native editor focus", editor != 0 && strcmp(win_attr(editor, c"id"), c"text-input") == 0)
	assert_strings_equal(c"​", win_attr(editor, c"value"))
	int before = mobile_field_pixels(binding.canvas)
	asserts(c"unique text absent before native typing", mobile_memory_contains(machine, c"Nativeé🙂") == 0)
	char* ascii = c"Native"
	for i in range(strlen(ascii)):
		mobile_event(&driver, GFX_EVENT_KEY_DOWN, 38 + i, x, y)
		mobile_event(&driver, GFX_EVENT_CHAR, ascii[i], x, y)
		mobile_event(&driver, GFX_EVENT_KEY_UP, 38 + i, x, y)
	mobile_event(&driver, GFX_EVENT_CHAR, 233, x, y)
	mobile_event(&driver, GFX_EVENT_CHAR, 128578, x, y)
	mobile_frame(&driver)
	mobile_frame(&driver)
	assert_strings_equal(c"​", win_attr(editor, c"value"))
	asserts(c"native text reaches real Wasm UTF-8 field", mobile_memory_contains(machine, c"Nativeé🙂"))
	asserts(c"native text changes the rendered Wasm field", mobile_field_pixels(binding.canvas) != before)
	asserts(c"native sink retains focus across frames", driver.browser.script.active_focus == editor)
	mobile_event(&driver, GFX_EVENT_KEY_DOWN, 22, x, y)
	mobile_event(&driver, GFX_EVENT_CHAR, 8, x, y)
	mobile_event(&driver, GFX_EVENT_KEY_UP, 22, x, y)
	mobile_frame(&driver)
	mobile_frame(&driver)
	asserts(c"native Backspace edits Wasm field by a Unicode scalar", mobile_memory_contains(machine, c"Nativeé"))
	assert_strings_equal(c"​", win_attr(editor, c"value"))
	mobile_shot(binding.canvas, args_value(c"screenshot"))
	driver.width = 384
	driver.height = 542
	XResizeWindow(driver.window.display, driver.window.window, driver.width, driver.height)
	XSync(driver.window.display, 0)
	assert1(gfx_window_poll(driver.window))
	for i in range(3): mobile_frame(&driver)
	assert_equal(360, driver.browser.viewport_width)
	assert_equal(360, driver.browser.viewport_height)
	assert_equal(360, binding.canvas.width)
	assert_equal(360, binding.canvas.height)
	mobile_shot(binding.canvas, args_value(c"narrow-screenshot"))
	# Wheel delivery must reach the inner wasm scroll region and cancel the
	# outer page's default scroll. Coordinates remain inside the resized canvas.
	int outer_scroll = cast(int, driver.browser.scroll.offset_y)
	ui_rect viewport = ui_rect_new(12.0, 138.0, 360.0, 360.0)
	asserts(c"wheel coordinate hits native canvas", win_browser_pointer_hit(&driver.browser, viewport, 100, 300) == binding.node)
	for i in range(10): mobile_event(&driver, GFX_EVENT_SCROLL, -1, 100, 300)
	for i in range(3): mobile_frame(&driver)
	assert_equal(outer_scroll, cast(int, driver.browser.scroll.offset_y))
	mobile_shot(binding.canvas, args_value(c"scrolled-screenshot"))
	for i in range(30): mobile_frame(&driver)
	asserts(c"text survives resize and continued rendering", mobile_memory_contains(machine, c"Nativeé"))
	assert_equal(0, driver.browser.script.failures)
	win_browser_free(&driver.browser)
	win_network_state_clear()
	win_script_graphics_available = 0
	ui_render_destroy(&driver.renderer)
	gfx_window_destroy(driver.window)
	println(c"Unchanged M2 native input: pointer focus, Unicode rendered field, sink reset, Backspace, resize, scrolling, sustained frames: OK")
	return 0
