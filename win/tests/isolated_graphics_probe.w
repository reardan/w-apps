# Opt-in unchanged-host acceptance: parent never owns a JS realm.
import lib.args
import lib.assert
import lib.metrics
import structures.json
import win.browser

int main(int argc, int argv):
	args_init(argc, argv)
	char* executable = args_value(c"browser")
	char* address = args_value(c"page")
	if (executable == 0 || address == 0): return 2
	gfx_window* window = gfx_window_open(c"Isolated frame acceptance", 800, 600)
	assert1(window != 0)
	ui_renderer renderer
	assert1(ui_render_init(&renderer))
	ui_context context
	context.rndr = &renderer
	win_browser browser
	win_browser_init(&browser, executable, address)
	browser.isolated = 1
	browser.execution_budget = win_execution_budget_parse(args_value(c"execution-budget"))
	int settled_fds = -1
	int maximum_poll = 0
	int maximum_paint = 0
	int frames = 0
	int paints = 0
	int changed = 0
	int first_frame = -1
	int test_start = time_monotonic_ms()
	for cycle in range(3):
		win_browser_set_viewport(&browser, 800, 600)
		win_navigate(&browser, address, c"", -2)
		assert1(browser.interactive != 0 && browser.interactive.child != 0)
		int child = browser.interactive.child.pid
		int started = time_monotonic_ms()
		int seen = -1
		int previous_hash = 0
		int count = 0
		while (count < 12 && time_monotonic_ms() - started < 30000):
			int before = time_monotonic_ms()
			win_browser_poll(&browser)
			maximum_poll = max(maximum_poll, time_monotonic_ms() - before)
			if (browser.interactive.child == 0): println(browser.status)
			assert1(browser.interactive.child != 0)
			assert1(browser.script == 0 && browser.fetches == 0)
			if (browser.interactive_sequence != seen && browser.interactive_sequence >= 0):
				seen = browser.interactive_sequence
				assert_equal(0, browser.script_failures)
				assert_equal(0, browser.resource_failures)
				assert_equal(1, browser.interactive.surfaces.length)
				win_frame_surface* surface = browser.interactive.surfaces[0]
				assert1(surface.pixels != 0)
				if (first_frame < 0): first_frame = time_monotonic_ms() - test_start
				int hash = 1
				int at = 0
				while (at < surface.width * surface.height * 4):
					hash = ((hash * 33) ^ (surface.pixels[at] & 255)) & 2147483647
					at = at + 251
				if (hash != previous_hash): changed = changed + 1
				previous_hash = hash
				int paint_started = time_monotonic_ms()
				ui_render_begin(&renderer, 800, 600)
				ui_render_rect(&renderer, ui_rect_new(0.0, 0.0, 800.0, 600.0), ui_gray(1.0))
				win_browser_paint(&browser, &context, ui_rect_new(0.0, 0.0, 800.0, 600.0), 0.0)
				ui_render_end(&renderer)
				maximum_paint = max(maximum_paint, time_monotonic_ms() - paint_started)
				assert1(surface.image != 0 && surface.pixels == 0)
				for win_run* run in browser.page.runs:
					if (atoi(win_attr(run.node, c"data-win-node")) == surface.node_id):
						int x = cast(int, run.x + run.width / 2.0)
						int y = cast(int, run.y + run.height / 2.0)
						if (x >= 0 && x < 800 && y >= 0 && y < 600):
							char[4] pixel
							glReadPixels(x, 599 - y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, &pixel[0])
							int color = (pixel[0] & 255) + (pixel[1] & 255) + (pixel[2] & 255)
							assert1(color > 50 && color < 740)
							paints = paints + 1
				count = count + 1
				frames = frames + 1
				if (count == 4): win_browser_set_viewport(&browser, 480, 360)
				if (count > 5):
					assert_equal(480, surface.width)
					assert_equal(360, surface.height)
			sleep_ms(2)
		assert_equal(12, count)
		# Crash after real GL startup; parent remains live and reaps the child.
		if (cycle == 0):
			assert_equal(0, process_kill(browser.interactive.child, sigkill))
			int deadline = time_monotonic_ms() + 2000
			while (browser.interactive.child != 0 && time_monotonic_ms() < deadline):
				win_browser_poll(&browser)
				sleep_ms(2)
			# A pending socket write can observe peer death before waitpid;
			# either path must fail promptly and reap the killed worker.
			assert1(browser.interactive.child == 0)
			if (browser.interactive.status != 3): assert_equal(4, browser.interactive.status)
		# Cancel while a real graphics frame is only partially transferred.
		else:
			assert1(win_interactive_request(browser.interactive, 1, 0, c""))
			int deadline = time_monotonic_ms() + 5000
			while (browser.interactive.decoder.pixel_count == 0 && time_monotonic_ms() < deadline):
				win_browser_poll(&browser)
				sleep_ms(2)
			assert1(browser.interactive.decoder.pixel_count > 0)
			assert1(browser.interactive.decoder.pixel_count < browser.interactive.decoder.header.length)
		int before = time_monotonic_ms()
		win_stop(&browser)
		assert1(time_monotonic_ms() - before < 500)
		assert_equal(-10, wait4(child, 0, 1, 0))
		ui_render_begin(&renderer, 800, 600)
		ui_render_end(&renderer)
		int fds = metrics_count_open_fds()
		if (settled_fds >= 0): assert_equal(settled_fds, fds)
		settled_fds = fds
	assert_equal(36, paints)
	assert1(changed >= 30)
	json_value* report = json_object()
	json_object_set(report, c"status", json_string(c"PASS"))
	json_object_set(report, c"frames", json_int(frames))
	json_object_set(report, c"painted_frames", json_int(paints))
	json_object_set(report, c"pixel_changes", json_int(changed))
	json_object_set(report, c"first_frame_ms", json_int(first_frame))
	json_object_set(report, c"max_parent_poll_ms", json_int(maximum_poll))
	json_object_set(report, c"max_parent_paint_ms", json_int(maximum_paint))
	json_object_set(report, c"elapsed_ms", json_int(time_monotonic_ms() - test_start))
	json_object_set(report, c"fds_after_stop", json_int(settled_fds))
	char* text = json_stringify(report)
	println(text)
	free(text)
	json_free(report)
	win_browser_free(&browser)
	win_network_state_clear()
	ui_render_destroy(&renderer)
	gfx_window_destroy(window)
	return 0
