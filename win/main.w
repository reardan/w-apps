import lib.args
import lib.stream
import win.app

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
	args_init(argc, argv)
	args_declare_bool(c"dump")
	args_declare_bool(c"help")
	if (args_has_flag(c"help")):
		println(c"win [--page PATH_OR_URL] [--dump] [--frames N --screenshot FILE.ppm]")
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
	win_app app
	win_app_init(&app, args_program(), home)
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
		return code
	gfx_window* window = gfx_window_open(c"Win — W browser", 1000, 760)
	if (window == 0):
		println2(c"Win needs an X11 display. Use --dump for headless document checks.")
		win_app_free(&app)
		return 1
	ui_renderer renderer
	if (ui_render_init(&renderer) == 0):
		gfx_window_destroy(window)
		win_app_free(&app)
		return 1
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
	while (gfx_window_poll(window)):
		win_app_poll(&app)
		ui_begin_window(&ctx, window)
		win_app_frame(&app, &ctx, window.width, window.height)
		ui_end(&ctx)
		frames = frames + 1
		int last = max_frames > 0 && frames >= max_frames
		if (last && screenshot != 0):
			glFinish()
			if (win_screenshot(screenshot, window.width, window.height) == 0): code = 1
		gfx_window_swap(window)
		if (last): break
		sleep_ms(16)
	win_app_free(&app)
	ui_render_destroy(&renderer)
	gfx_window_destroy(window)
	return code
