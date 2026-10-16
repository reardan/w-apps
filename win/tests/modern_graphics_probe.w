# Unchanged original-host rendering, resize and repeated document replacement.
import lib.args
import lib.assert
import lib.file
import lib.metrics
import structures.json
import win.browser

# Count live W allocations without the guard allocator's per-block VMAs. These
# hooks deliberately use the production allocator backend and its block header;
# GL/driver allocations are measured separately by RSS, not claimed leak-free.
int graphics_live_blocks
int graphics_live_bytes

int graphics_block_size(void* pointer):
	if (pointer == 0): return 0
	int* header = cast(int*, cast(int, pointer) - 2 * __word_size__)
	return header[0]

void* graphics_malloc(int size):
	void* pointer = malloc_backend(size)
	if (pointer != 0):
		graphics_live_blocks = graphics_live_blocks + 1
		graphics_live_bytes = graphics_live_bytes + graphics_block_size(pointer)
	return pointer

int graphics_free(void* pointer):
	if (pointer != 0):
		graphics_live_blocks = graphics_live_blocks - 1
		graphics_live_bytes = graphics_live_bytes - graphics_block_size(pointer)
	return malloc_backend_free(pointer)

char* graphics_realloc(void* pointer, int old_length, int new_length):
	int old_size = graphics_block_size(pointer)
	char* result = malloc_backend_realloc(pointer, old_length, new_length)
	if (result != 0):
		if (pointer == 0): graphics_live_blocks = graphics_live_blocks + 1
		graphics_live_bytes = graphics_live_bytes + graphics_block_size(result) - old_size
	return result

int graphics_rss_pages():
	char* text = file_read_text(c"/proc/self/statm")
	if (text == 0): return -1
	int at = 0
	while (text[at] != 0 && text[at] != ' '): at = at + 1
	int pages = -1
	if (text[at] == ' '): pages = atoi(text + at + 1)
	free(text)
	return pages

win_canvas* graphics_canvas(win_browser* browser):
	if (browser.script == 0): return 0
	for i in range(browser.script.bindings.length):
		if (browser.script.bindings[i].canvas != 0): return browser.script.bindings[i].canvas
	return 0

int main(int argc, int argv):
	malloc_init_mode()
	assert_equal(0, malloc_debug_mode)
	malloc_hook_set(cast(int, graphics_malloc), cast(int, graphics_free), cast(int, graphics_realloc))
	args_init(argc, argv)
	char* executable = args_value(c"browser")
	char* address = args_value(c"page")
	char* blank = args_value(c"blank")
	if (executable == 0 || address == 0 || blank == 0): return 2
	gfx_window* window = gfx_window_open(c"Original graphics acceptance", 800, 600)
	assert1(window != 0)
	win_script_graphics_available = 1
	win_browser browser
	win_browser_init(&browser, executable, blank)
	json_value* report = json_object()
	json_value* cycles = json_array()
	json_object_set(report, c"cycles", cycles)
	int settled_fds = -1
	for cycle in range(3):
		int previous_blocks = graphics_live_blocks
		int previous_bytes = graphics_live_bytes
		win_browser_set_viewport(&browser, 800, 600)
		# Replace the history entry so deliberate history growth cannot hide
		# or be mistaken for retained page/realm allocations.
		win_navigate(&browser, address, c"", -2)
		int started = time_monotonic_ms()
		int first_frame = -1
		int callbacks = 0
		int changes = 0
		int last_hash = 0
		int maximum_poll = 0
		int maximum_frame = 0
		int frame_total = 0
		while (callbacks < 60 && time_monotonic_ms() - started < 20000):
			int before = time_monotonic_ms()
			win_browser_poll(&browser)
			maximum_poll = max(maximum_poll, time_monotonic_ms() - before)
			if (browser.script != 0):
				if (browser.script.failures): println(browser.script.error)
				assert_equal(0, browser.script.failures)
			before = time_monotonic_ms()
			int count = win_script_frame_at(browser.script, before)
			int duration = time_monotonic_ms() - before
			maximum_frame = max(maximum_frame, duration)
			frame_total = frame_total + duration
			if (count):
				if (first_frame < 0): first_frame = time_monotonic_ms() - started
				win_canvas* canvas = graphics_canvas(&browser)
				assert1(canvas != 0 && win_canvas_enter(canvas))
				glReadPixels(0, 0, canvas.width, canvas.height, GL_RGBA, GL_UNSIGNED_BYTE, canvas.pixels)
				win_canvas_leave(canvas)
				int hash = 1
				int at = 0
				while (at < canvas.width * canvas.height * 4):
					hash = ((hash * 33) ^ (canvas.pixels[at] & 255)) & 2147483647
					at = at + 251
				if (hash != last_hash): changes = changes + 1
				last_hash = hash
				callbacks = callbacks + count
				if (callbacks == 20): win_browser_set_viewport(&browser, 480, 360)
			sleep_ms(16)
		assert_equal(60, callbacks)
		assert1(changes >= 40)
		assert_equal(0, browser.resource_failures)
		assert_equal(0, browser.script.failures)
		assert_strings_equal(c"W graphics demo", browser.page.title)
		assert_equal(480, graphics_canvas(&browser).width)
		assert_equal(360, graphics_canvas(&browser).height)
		win_navigate(&browser, blank, c"", -2)
		started = time_monotonic_ms()
		while (win_browser_loading(&browser) && time_monotonic_ms() - started < 5000):
			win_browser_poll(&browser)
			sleep_ms(5)
		assert_equal(0, win_browser_loading(&browser))
		assert1(graphics_canvas(&browser) == 0)
		assert_equal(0, browser.script.runtime.async_tasks.length)
		assert_equal(0, browser.script.animation_frames.length)
		int descriptors = metrics_count_open_fds()
		if (settled_fds >= 0): assert_equal(settled_fds, descriptors)
		settled_fds = descriptors
		int retained_blocks = graphics_live_blocks - previous_blocks
		int retained_bytes = graphics_live_bytes - previous_bytes
		print_int(c"retained blocks: ", retained_blocks)
		print_int(c"retained bytes: ", retained_bytes)
		if (cycle > 0):
			assert_equal(0, retained_blocks)
			# Freelist reuse can return a slightly larger unsplit block. There
			# must be no retained allocation count or page-sized byte growth.
			assert1(retained_bytes < 4096)
		json_value* record = json_object()
		json_object_set(record, c"callbacks", json_int(callbacks))
		json_object_set(record, c"pixel_changes", json_int(changes))
		json_object_set(record, c"first_frame_ms", json_int(first_frame))
		json_object_set(record, c"max_poll_ms", json_int(maximum_poll))
		json_object_set(record, c"max_frame_ms", json_int(maximum_frame))
		json_object_set(record, c"frame_total_ms", json_int(frame_total))
		json_object_set(record, c"retained_w_blocks", json_int(retained_blocks))
		json_object_set(record, c"retained_w_bytes", json_int(retained_bytes))
		json_object_set(record, c"fds_after_navigation", json_int(descriptors))
		json_object_set(record, c"rss_pages_after_navigation", json_int(graphics_rss_pages()))
		json_array_push(cycles, record)
	win_browser_free(&browser)
	win_network_state_clear()
	win_script_graphics_available = 0
	gfx_window_destroy(window)
	json_object_set(report, c"status", json_string(c"PASS"))
	char* output = json_stringify(report)
	println(output)
	free(output)
	json_free(report)
	return 0
