import lib.assert
import win.app

void fixed_scroll_paint(ui_renderer* renderer, float32 flow_y):
	int red = 0
	int blue = 0
	for i in range(renderer.layer_vert_count[0]):
		float32* vertex = &renderer.layer_verts[0][i * 8]
		if (vertex[4] == 1.0 && vertex[5] == 0.0 && vertex[6] == 0.0):
			asserts(c"fixed paint stays at viewport top", vertex[1] == 138.0 || vertex[1] == 158.0)
			red = red + 1
		if (vertex[4] == 0.0 && vertex[5] == 0.0 && vertex[6] == 1.0):
			asserts(c"normal flow paint follows scroll", vertex[1] == flow_y || vertex[1] == flow_y + 20.0)
			blue = blue + 1
	assert_equal(6, red)
	assert_equal(6, blue)

int main():
	win_browser browser
	win_browser_init(&browser, c"unused", c"unused")
	char* source = c"<style>body{margin:0}</style><div style='height:200px'></div><div style='height:20px;background:blue'></div><div style='height:1380px'></div><div style='position:fixed;left:0;top:0;width:20px;height:20px;background:red'></div>"
	browser.page = win_page_parse(source, strlen(source))
	browser.forms = win_forms_new(browser.page)
	ui_renderer renderer
	ui_render_init_headless(&renderer)
	ui_theme theme
	ui_theme_light(&theme)
	ui_context ctx
	ui_context_init(&ctx, &renderer, &theme)
	ui_begin(&ctx, 824, 782)
	win_browser_frame(&browser, &ctx, 824, 782)
	ui_end(&ctx)
	gfx_event event
	event.kind = GFX_EVENT_SCROLL_PIXELS
	event.code = 100
	event.mods = 0
	event.x = 100
	event.y = 200
	ui_feed_event(&ctx, &event)
	win_native_push(&browser.native_input, &event)
	ui_begin(&ctx, 824, 782)
	win_browser_frame(&browser, &ctx, 824, 782)
	ui_end(&ctx)
	asserts(c"native wheel changes document scroll", browser.scroll.offset_y == 100.0)
	# ui_scroll_end commits wheel defaults after painting. Inspect both the
	# wheel frame and following frame: only ordinary flow may move.
	fixed_scroll_paint(&renderer, 338.0)
	ui_begin(&ctx, 824, 782)
	win_browser_frame(&browser, &ctx, 824, 782)
	ui_end(&ctx)
	fixed_scroll_paint(&renderer, 238.0)
	win_browser_free(&browser)
	ui_render_destroy(&renderer)
	println(c"Native wheel preserves fixed paint while ordinary content scrolls: OK")
	return 0
