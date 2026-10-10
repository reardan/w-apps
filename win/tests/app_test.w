import lib.assert
import lib.args
import win.app

void app_wait(win_app* app):
	int start = time_monotonic_ms()
	int loading = 1
	while (loading):
		win_app_poll(app)
		loading = 0
		for i in range(app.tabs.length):
			if (win_browser_loading(app.tabs[i])): loading = 1
		asserts(c"tabs load within watchdog", time_monotonic_ms() - start < 14000)
		sleep_ms(1)

int main(int argc, int argv):
	args_init(argc, argv)
	assert_equal(3, argc)
	win_app app
	win_app_init(&app, args_get(1), args_get(2))
	asserts(c"open first", win_app_open(&app, args_get(2), c""))
	asserts(c"open second", win_app_open(&app, c"article.html", args_get(2)))
	app_wait(&app)
	assert_equal(2, app.tabs.length)
	assert_equal(1, app.selected)
	assert_strings_equal(c"Welcome to Win", app.tabs[0].page.title)
	assert_strings_equal(c"A browser built from W", app.tabs[1].page.title)
	assert_equal(1, app.tabs[0].history.length)
	assert_equal(1, app.tabs[1].history.length)
	asserts(c"distinct realms", app.tabs[0].script.runtime != app.tabs[1].script.runtime)
	app.tabs[0].scroll.offset_y = 100.0
	ui_textarea_set(&app.tabs[0].input, c"unfinished address")
	win_navigate(app.tabs[1], args_get(2), c"", -1)
	app_wait(&app)
	assert_equal(2, app.tabs[1].history.length)
	assert_equal(1, app.tabs[0].history.length)
	asserts(c"inactive scroll preserved", app.tabs[0].scroll.offset_y == 100.0)
	assert_strings_equal(c"unfinished address", app.tabs[0].input.buf.data)
	ui_renderer renderer
	ui_render_init_headless(&renderer)
	ui_theme theme
	ui_theme_light(&theme)
	ui_context ctx
	ui_context_init(&ctx, &renderer, &theme)
	gfx_event event
	event.kind = GFX_EVENT_MOUSE_DOWN
	event.code = 1
	event.x = 40
	event.y = 20
	event.mods = 0
	ui_feed_event(&ctx, &event)
	event.kind = GFX_EVENT_MOUSE_UP
	ui_feed_event(&ctx, &event)
	ui_begin(&ctx, 800, 600)
	win_app_frame(&app, &ctx, 800, 600)
	ui_end(&ctx)
	assert_equal(0, app.selected)
	assert_strings_equal(c"unfinished address", app.tabs[0].input.buf.data)
	# A live loader must be reaped when its tab closes.
	win_app_open(&app, args_get(2), c"")
	asserts(c"pending close", app.tabs[2].load != 0)
	win_app_close(&app, 2)
	assert_equal(2, app.tabs.length)
	win_app_close(&app, 0)
	assert_equal(1, app.tabs.length)
	assert_equal(0, app.selected)
	win_app_close(&app, 0)
	assert_equal(1, app.tabs.length)
	app_wait(&app)
	assert_strings_equal(c"Welcome to Win", app.tabs[0].page.title)
	ui_render_destroy(&renderer)
	win_app_free(&app)
	println(c"Win tab ownership, history, input, switching and cancellation: OK")
	return 0
