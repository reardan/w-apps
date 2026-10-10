import lib.assert
import lib.args
import win.browser

int page_contains(win_page* page, char* text):
	for i in range(page.runs.length):
		if (strcmp(page.runs[i].text, text) == 0): return 1
	return 0

void wait_for_page(win_browser* browser):
	int start = time_monotonic_ms()
	while (browser.load != 0):
		win_browser_poll(browser)
		asserts(c"load finishes", time_monotonic_ms() - start < 14000)
		sleep_ms(1)

void test_document():
	char* text = c"<title>Title</title><h1>Heading</h1><p>one <b>two</b> <a href='next.html'>three</a></p><p id='end' style='color:#123456'>end</p><p style='display:none'>hidden</p><script>script</script>"
	win_page* page = win_page_parse(text, strlen(text))
	asserts(c"parse", page != 0)
	assert_strings_equal(c"Title", page.title)
	win_page_layout(page, 600)
	asserts(c"heading", page_contains(page, c"Heading"))
	asserts(c"bold text", page_contains(page, c"two"))
	asserts(c"hidden CSS", page_contains(page, c"hidden") == 0)
	asserts(c"metadata hidden", page_contains(page, c"Title") == 0)
	asserts(c"script hidden", page_contains(page, c"script") == 0)
	int found = 0
	for i in range(page.runs.length):
		win_run* run = page.runs[i]
		if (strcmp(run.text, c"three") == 0):
			assert_strings_equal(c"next.html", win_page_hit(page, run.x + 1.0, run.y + 1.0))
			asserts(c"underline", run.flags & UI_TEXT_UNDERLINE)
			found = 1
		if (strcmp(run.text, c"end") == 0): asserts(c"inline color", run.color.r < 0.1 && run.color.b > 0.3)
	asserts(c"link found", found)
	asserts(c"fragment location", win_page_anchor(page, c"end") > 0.0)
	win_page_free(page)
	text = c"<pre>a  b\nc</pre><p style='font-size:18.5px'>fractional</p>"
	page = win_page_parse(text, strlen(text))
	win_page_layout(page, 600)
	assert_equal(6, page.runs.length)
	assert_strings_equal(c" ", page.runs[1].text)
	assert_strings_equal(c" ", page.runs[2].text)
	asserts(c"preformatted newline", page.runs[4].y > page.runs[0].y)
	assert_equal(18, ui_font_strike_ppem(page.runs[5].strike))
	win_page_free(page)
	char[2] invalid
	invalid[0] = 255
	invalid[1] = 0
	asserts(c"invalid UTF-8 rejected", win_page_parse(&invalid[0], 1) == 0)
	text = c"<p>one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen</p>"
	page = win_page_parse(text, strlen(text))
	win_page_layout(page, 800)
	float32 wide = page.height
	win_page_layout(page, 180)
	asserts(c"narrow viewport wraps", page.height > wide)
	for i in range(page.runs.length):
		win_run* run = page.runs[i]
		asserts(c"run fits", run.x >= 28.0 && run.x + run.width <= 152.1)
	win_page_free(page)
	text = c"<p>abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz</p>"
	page = win_page_parse(text, strlen(text))
	win_page_layout(page, 160)
	asserts(c"long word splits", page.runs.length > 1)
	win_page_free(page)

void test_addresses():
	char* target = win_resolve(c"https://example.com/docs/a.html", c"../b.html#part")
	assert_strings_equal(c"https://example.com/b.html#part", target)
	free(target)
	target = win_resolve(c"/tmp/site/a.html", c"../b.html#part")
	assert_strings_equal(c"/tmp/b.html#part", target)
	free(target)
	target = win_resolve(c"/tmp/site/a.html", c"#part")
	assert_strings_equal(c"/tmp/site/a.html#part", target)
	free(target)
	asserts(c"script URLs rejected", win_resolve(c"https://example.com/", c"javascript:alert(1)") == 0)
	asserts(c"web cannot navigate local paths", win_resolve(c"https://example.com/", c"file:///etc/passwd") == 0)
	asserts(c"controls rejected", win_resolve(c"", c"bad\naddress") == 0)

void test_navigation(char* executable, char* home):
	win_browser b
	win_browser_init(&b, executable, home)
	win_navigate(&b, home, c"", -1)
	wait_for_page(&b)
	asserts(c"initial page", b.page != 0)
	assert_strings_equal(c"Welcome to Win", b.page.title)
	assert_equal(1, b.history.length)
	win_navigate(&b, c"article.html", b.address, -1)
	wait_for_page(&b)
	assert_strings_equal(c"A browser built from W", b.page.title)
	assert_equal(2, b.history.length)
	b.scroll.offset_y = 120.0
	win_navigate(&b, c"#navigation", b.address, -1)
	asserts(c"fragment does not refetch", b.load == 0)
	asserts(c"fragment scrolls", b.scroll.offset_y > 0.0)
	win_history_go(&b, -1)
	asserts(c"back restores scroll", b.scroll.offset_y == 120.0)
	win_history_go(&b, -1)
	wait_for_page(&b)
	assert_strings_equal(c"Welcome to Win", b.page.title)
	win_history_go(&b, 1)
	wait_for_page(&b)
	assert_strings_equal(c"A browser built from W", b.page.title)
	asserts(c"cross-document scroll restored", b.scroll.offset_y == 120.0)
	win_navigate(&b, b.address, c"", -2)
	wait_for_page(&b)
	assert_equal(3, b.history.length)
	win_navigate(&b, c"definitely-missing.html", b.address, -1)
	wait_for_page(&b)
	assert_strings_equal(c"A browser built from W", b.page.title)
	assert_strings_equal(c"Cannot open local file.", b.status)
	win_navigate(&b, home, c"", -1)
	win_stop(&b)
	asserts(c"stop clears loader", b.load == 0)
	assert_strings_equal(c"A browser built from W", b.page.title)
	# A replacement navigation must never consume the previous pipe's result.
	win_navigate(&b, home, c"", -1)
	win_navigate(&b, c"article.html", home, -1)
	wait_for_page(&b)
	assert_strings_equal(c"A browser built from W", b.page.title)
	ui_renderer renderer
	ui_render_init_headless(&renderer)
	ui_theme theme
	ui_theme_light(&theme)
	ui_context ctx
	ui_context_init(&ctx, &renderer, &theme)
	ui_begin(&ctx, 640, 480)
	win_browser_frame(&b, &ctx, 640, 480)
	ui_end(&ctx)
	asserts(c"browser emits paint", renderer.commands.length > 0)
	assert_equal(604, b.page.width)
	ui_begin(&ctx, 50, 50)
	win_browser_frame(&b, &ctx, 50, 50)
	ui_end(&ctx)
	# Dispatch a real widget click on the Back button through W's input API.
	gfx_event down
	down.kind = GFX_EVENT_MOUSE_DOWN
	down.code = 1
	down.x = 35
	down.y = 60
	down.mods = 0
	ui_feed_event(&ctx, &down)
	down.kind = GFX_EVENT_MOUSE_UP
	ui_feed_event(&ctx, &down)
	int previous = b.current
	ui_begin(&ctx, 640, 480)
	win_browser_frame(&b, &ctx, 640, 480)
	ui_end(&ctx)
	wait_for_page(&b)
	assert_equal(previous - 1, b.current)
	win_navigate(&b, home, c"", -1)
	wait_for_page(&b)
	ui_begin(&ctx, 640, 480)
	win_browser_frame(&b, &ctx, 640, 480)
	ui_end(&ctx)
	# Find a visible article link and activate it through the page viewport.
	int clicked = 0
	for i in range(b.page.runs.length):
		win_run* run = b.page.runs[i]
		if (strcmp(run.href, c"article.html") == 0 && clicked == 0):
			b.scroll.offset_y = run.y - 20.0
			down.x = cast(int, run.x + 13.0)
			down.y = 159
			clicked = 1
	asserts(c"article link exists", clicked)
	down.kind = GFX_EVENT_MOUSE_DOWN
	ui_feed_event(&ctx, &down)
	down.kind = GFX_EVENT_MOUSE_UP
	ui_feed_event(&ctx, &down)
	ui_begin(&ctx, 640, 480)
	win_browser_frame(&b, &ctx, 640, 480)
	ui_end(&ctx)
	wait_for_page(&b)
	assert_strings_equal(c"A browser built from W", b.page.title)
	# Wheel input changes the actual viewport state.
	b.scroll.offset_y = 0.0
	down.kind = GFX_EVENT_SCROLL
	down.code = -2
	down.x = 100
	down.y = 200
	ui_feed_event(&ctx, &down)
	ui_begin(&ctx, 640, 480)
	win_browser_frame(&b, &ctx, 640, 480)
	ui_end(&ctx)
	asserts(c"wheel scrolls", b.scroll.offset_y > 0.0)
	# Ctrl+L focuses/selects the editor; Enter submits a replacement address.
	down.kind = GFX_EVENT_CHAR
	down.code = 12
	down.mods = GFX_MOD_CTRL
	ui_feed_event(&ctx, &down)
	ui_begin(&ctx, 640, 480)
	win_browser_frame(&b, &ctx, 640, 480)
	ui_end(&ctx)
	assert_equal(0, b.input.sel_anchor)
	ui_textarea_set(&b.input, home)
	down.code = 13
	down.mods = 0
	ui_feed_event(&ctx, &down)
	ui_begin(&ctx, 640, 480)
	win_browser_frame(&b, &ctx, 640, 480)
	ui_end(&ctx)
	wait_for_page(&b)
	assert_strings_equal(c"Welcome to Win", b.page.title)
	ui_render_destroy(&renderer)
	win_browser_free(&b)

void test_slow_request(char* executable, char* address):
	win_browser b
	win_browser_init(&b, executable, c"")
	ui_renderer renderer
	ui_render_init_headless(&renderer)
	ui_theme theme
	ui_theme_light(&theme)
	ui_context ctx
	ui_context_init(&ctx, &renderer, &theme)
	win_navigate(&b, address, c"", -1)
	int start = time_monotonic_ms()
	for i in range(30):
		win_browser_poll(&b)
		ui_begin(&ctx, 640, 480)
		win_browser_frame(&b, &ctx, 640, 480)
		ui_end(&ctx)
		sleep_ms(10)
	asserts(c"slow request pending", b.load != 0)
	asserts(c"UI keeps drawing while loading", time_monotonic_ms() - start < 2000)
	start = time_monotonic_ms()
	win_stop(&b)
	asserts(c"stop bounded", time_monotonic_ms() - start < 1000)
	asserts(c"stopped child cleared", b.load == 0)
	ui_render_destroy(&renderer)
	win_browser_free(&b)
	println(c"Win slow-request UI and cancellation: OK")

int main(int argc, int argv):
	args_init(argc, argv)
	if (argc == 4 && strcmp(args_get(1), c"--slow") == 0):
		test_slow_request(args_get(2), args_get(3))
		return 0
	asserts(c"test arguments", argc == 3)
	test_document()
	test_addresses()
	test_navigation(args_get(1), args_get(2))
	println(c"Win document, layout, navigation, and UI tests: OK")
	return 0
