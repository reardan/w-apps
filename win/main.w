import lib.args
import lib.stream
import win.app
import win.script_worker

int win_screenshot(char* path, int width, int height):
	if (width <= 0 || height <= 0 || width > 4096 || height > 4096): return 0
	char* pixels = cast(char*, malloc(width * height * 4))
	glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels)
	wstream* out = stream_open_write(path)
	if (out == 0):
		free(pixels)
		return 0
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
	io_result closed
	int ok = stream_close_checked(out, &closed) == IO_OK
	free(row)
	free(pixels)
	return ok

int main(int argc, int argv):
	if (win_script_worker_parent_guard() == 0): return 1
	args_init(argc, argv)
	args_declare_bool(c"dump")
	args_declare_bool(c"isolated-dump")
	args_declare_bool(c"script-worker")
	args_declare_bool(c"interactive-worker")
	args_declare_bool(c"isolated-interactive")
	args_declare_bool(c"help")
	args_declare_bool(c"reftest")
	if (args_has_flag(c"help")):
		println(c"win [--page PATH_OR_URL] [--dump | --isolated-dump] [--worker-timeout MS] [--isolated-interactive] [--frames N --screenshot FILE.ppm] [--reftest]")
		return 0
	char* fetch = args_value(c"fetch")
	if (fetch != 0):
		char* method = args_value(c"method")
		char* body = args_value(c"body")
		if (method == 0): method = c"GET"
		if (body == 0): body = c""
		return win_fetch_request_worker(fetch, method, body)
	char* resource = args_value(c"resource")
	if (resource != 0):
		char* kind = args_value(c"kind")
		if (kind == 0): return 1
		return win_resource_worker(resource, kind)
	char* home = args_value(c"home")
	if (home == 0): home = c"win/fixtures/start.html"
	char* start = args_value(c"page")
	if (start == 0): start = home
	if (args_has_flag(c"interactive-worker")):
		char* limit = args_value(c"worker-limit")
		if (limit == 0): return 1
		return win_script_interactive_execute(args_program(), start, home, atoi(limit))
	if (args_has_flag(c"script-worker")):
		char* limit = args_value(c"worker-limit")
		if (limit == 0): return 1
		return win_script_worker_execute(args_program(), start, home, atoi(limit))
	if (args_has_flag(c"isolated-dump")):
		int timeout = 30000
		char* configured = args_value(c"worker-timeout")
		if (configured != 0): timeout = atoi(configured)
		win_script_worker* worker = win_script_worker_start(args_program(), start, home, timeout, WIN_SCRIPT_WORKER_LIMIT)
		while (win_script_worker_poll(worker) == 0): sleep_ms(2)
		int code = 1
		if (worker.status == 1):
			print(worker.text)
			if (worker.script_failures == 0 && worker.resource_failures == 0): code = 0
			else: println2(c"Isolated page completed with script or resource errors")
		else: println2(worker.error)
		win_script_worker_free(worker)
		return code
	win_app app
	win_app_init(&app, args_program(), home)
	app.isolated = args_has_flag(c"isolated-interactive")
	win_app_open(&app, start, c"")
	win_browser* browser = app.tabs[0]
	if (args_has_flag(c"dump")):
		while (win_browser_loading(browser)):
			win_app_poll(&app)
			sleep_ms(2)
		int code = 0
		if (browser.page == 0):
			println2(browser.status)
			code = 1
		else:
			println(browser.address)
			println(browser.page.title)
			for i in range(browser.page.runs.length):
				if (browser.page.runs[i].hidden): continue
				print(browser.page.runs[i].text)
				print(c" ")
			println(c"")
		win_app_free(&app)
		win_network_state_clear()
		return code
	# Reftests capture an 800x600 content viewport, excluding browser chrome.
	int reftest = args_has_flag(c"reftest")
	int window_width = 1000
	int window_height = 760
	if (reftest):
		window_width = 800
		window_height = 600
		browser.width = 800
	gfx_window* window = gfx_window_open(c"Win — W browser", window_width, window_height)
	if (window == 0):
		println2(c"Win needs an X11 display. Use --dump for headless document checks.")
		win_app_free(&app)
		win_network_state_clear()
		return 1
	ui_renderer renderer
	if (ui_render_init(&renderer) == 0):
		gfx_window_destroy(window)
		win_app_free(&app)
		win_network_state_clear()
		return 1
	win_script_graphics_available = 1
	if (reftest):
		win_browser_set_viewport(browser, 800, 600)
		browser.width = 800
	ui_theme theme
	ui_theme_light(&theme)
	theme.background = ui_color_new(0.92, 0.95, 0.97, 1.0)
	theme.accent = ui_color_new(0.12, 0.31, 0.42, 1.0)
	theme.accent_hot = ui_color_new(0.17, 0.39, 0.51, 1.0)
	ui_context ctx
	ui_context_init(&ctx, &renderer, &theme)
	int frames = 0
	int max_frames = 0
	char* count = args_value(c"frames")
	if (count != 0): max_frames = atoi(count)
	char* screenshot = args_value(c"screenshot")
	int code = 0
	int ready_frames = 0
	int captured = 0
	if (reftest):
		max_frames = 1200
		if (screenshot == 0):
			println2(c"--reftest requires --screenshot")
			code = 1
	while (code == 0 && gfx_window_poll(window)):
		win_app_poll(&app)
		ui_begin_window(&ctx, window)
		if (reftest):
			ui_rect viewport = ui_rect_new(0.0, 0.0, 800.0, 600.0)
			ui_render_rect(ctx.rndr, viewport, ui_gray(1.0))
			if (browser.page != 0):
				win_script_frame_at(browser.script, time_monotonic_ms())
				if (browser.script != 0 && browser.script.dirty):
					win_page_layout(browser.page, 800)
					browser.script.dirty = 0
				if (browser.page.width != 800): win_page_layout(browser.page, 800)
				win_browser_paint(browser, &ctx, viewport, 0.0)
				win_forms_draw(browser.forms, &ctx, 0.0, 0.0)
		else: win_app_frame(&app, &ctx, window.width, window.height)
		ui_end(&ctx)
		frames = frames + 1
		int last = max_frames > 0 && frames >= max_frames
		if (reftest):
			if (win_browser_loading(browser) == 0):
				if (browser.page == 0 || browser.script_failures != 0 || browser.resource_failures != 0 || browser.page.truncated):
					println2(c"Reftest load failed or content was truncated")
					code = 1
					break
			if (win_browser_loading(browser) == 0 && browser.page != 0): ready_frames = ready_frames + 1
			else: ready_frames = 0
			if (ready_frames >= 2): last = 1
			if (last && (ready_frames < 2 || browser.script_failures != 0 || browser.resource_failures != 0 || browser.page.truncated)):
				println2(c"Reftest load failed or did not settle")
				code = 1
				break
		if (last && screenshot != 0):
			glFinish()
			if (win_screenshot(screenshot, window.width, window.height) == 0): code = 1
			else: captured = 1
		gfx_window_swap(window)
		if (last): break
		sleep_ms(16)
	if (reftest && captured == 0): code = 1
	win_app_free(&app)
	win_network_state_clear()
	win_script_graphics_available = 0
	ui_render_destroy(&renderer)
	gfx_window_destroy(window)
	return code
