# Native, unchanged-application diagnostic probe. This is an acceptance aid,
# not a conformance test: an unsupported application exits unsuccessfully.
import lib.args
import structures.json
import win.browser

int main(int argc, int argv):
	args_init(argc, argv)
	char* executable = args_value(c"browser")
	char* address = args_value(c"page")
	if (executable == 0 || address == 0): return 2
	gfx_window* window = gfx_window_open(c"Unchanged host probe", 800, 600)
	if (window == 0): return 2
	win_script_graphics_available = 1
	win_browser browser
	win_browser_init(&browser, executable, address)
	browser.execution_budget = win_execution_budget_parse(args_value(c"execution-budget"))
	if (browser.execution_budget == 0): return 2
	win_browser_set_viewport(&browser, 800, 600)
	win_navigate(&browser, address, c"", -1)
	int started = time_monotonic_ms()
	int callbacks = 0
	int first_frame = -1
	int resized = 0
	int canvas_pixels = 0
	int changed_frames = 0
	int last_hash = 0
	int duration = 5000
	if (browser.execution_budget > WIN_EXECUTION_DEFAULT): duration = 30000
	while (time_monotonic_ms() - started < duration):
		win_browser_poll(&browser)
		int count = win_script_frame_at(browser.script, time_monotonic_ms())
		callbacks = callbacks + count
		if (count > 0 && first_frame < 0): first_frame = time_monotonic_ms() - started
		if (browser.script != 0):
			if (browser.script.failures > 0): break
			for win_dom_binding* binding in browser.script.bindings:
				win_canvas* canvas = binding.canvas
				if (canvas == 0 || canvas.context == 0 || canvas.dirty == 0): continue
				if (win_canvas_enter(canvas)):
					char[4] pixel
					glReadPixels(canvas.width / 2, canvas.height / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, &pixel[0])
					int hash = (pixel[0] & 255) * 65536 + (pixel[1] & 255) * 256 + (pixel[2] & 255)
					if (hash != last_hash): changed_frames = changed_frames + 1
					last_hash = hash
					if (hash != 0): canvas_pixels = 1
					win_canvas_leave(canvas)
		if (callbacks >= 20 && resized == 0):
			win_browser_set_viewport(&browser, 480, 360)
			resized = 1
		if (callbacks >= 60): break
		if (win_browser_loading(&browser) == 0 && browser.script == 0): break
		sleep_ms(16)
	json_value* report = json_object()
	json_object_set(report, c"address", json_string(address))
	json_object_set(report, c"execution_budget", json_int(browser.execution_budget))
	json_object_set(report, c"status", json_string(browser.status))
	json_object_set(report, c"title", json_string(c""))
	if (browser.page != 0): json_object_set(report, c"title", json_string(browser.page.title))
	int failures = browser.script_failures
	if (browser.script != 0): failures = browser.script.failures
	json_object_set(report, c"script_failures", json_int(failures))
	json_object_set(report, c"resource_failures", json_int(browser.resource_failures))
	json_object_set(report, c"animation_callbacks", json_int(callbacks))
	json_object_set(report, c"first_frame_ms", json_int(first_frame))
	json_object_set(report, c"resized", json_bool(resized))
	json_object_set(report, c"canvas_nonblack_center", json_bool(canvas_pixels))
	json_object_set(report, c"center_pixel_changes", json_int(changed_frames))
	if (browser.script != 0 && browser.script.error != 0): json_object_set(report, c"script_error", json_string(browser.script.error))
	if (browser.page != 0):
		html_node* node = browser.page.html.allocations
		while (node != 0):
			if (strcmp(win_attr(node, c"id"), c"log") == 0):
				char* log = win_dom_text(node)
				json_object_set(report, c"host_log", json_string(log))
				free(log)
				break
			node = node.allocation_next
	json_value* console = json_array()
	if (browser.script != 0):
		for i in range(browser.script.console.length): json_array_push(console, json_string(browser.script.console[i]))
	json_object_set(report, c"console", console)
	char* result = json_stringify(report)
	println(result)
	free(result)
	json_free(report)
	win_browser_free(&browser)
	win_network_state_clear()
	win_script_graphics_available = 0
	gfx_window_destroy(window)
	if (failures || callbacks == 0): return 1
	return 0
