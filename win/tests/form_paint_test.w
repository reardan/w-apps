import lib.assert
import win.browser

html_node* paint_node(win_page* page, char* id):
	html_node* node = page.html.allocations
	while (node != 0):
		if (strcmp(win_attr(node, c"id"), id) == 0): return node
		node = node.allocation_next
	return 0

int paint_color_vertices(ui_renderer* renderer, ui_color color):
	int count = 0
	float32* vertices = renderer.layer_verts[0]
	for i in range(renderer.layer_vert_count[0]):
		int at = i * 8
		if (vertices[at + 7] > 0.0 && fabs(vertices[at + 4] - color.r) < 0.005 && fabs(vertices[at + 5] - color.g) < 0.005 && fabs(vertices[at + 6] - color.b) < 0.005 && fabs(vertices[at + 7] - color.a) < 0.005): count = count + 1
	return count

void paint_controls(win_browser* browser, ui_context* ctx):
	ui_begin(ctx, 800, 600)
	win_browser_paint(browser, ctx, ui_rect_new(0.0, 0.0, 800.0, 600.0), 0.0)
	win_forms_draw(browser.forms, ctx, 0.0, 0.0)
	ui_end(ctx)

void test_form_paint(char* css, char* element, int background, int text, int border):
	char* prefix = strjoin(c"<style>body{margin:0}", css)
	char* source = strjoin(prefix, c"</style>")
	free(prefix)
	prefix = strjoin(source, element)
	free(source)
	win_browser browser
	browser.page = win_page_parse(prefix, strlen(prefix))
	free(prefix)
	browser.forms = win_forms_new(browser.page)
	win_page_layout(browser.page, 800)
	ui_renderer renderer
	ui_render_init_headless(&renderer)
	ui_theme theme
	ui_theme_light(&theme)
	ui_context ctx
	ui_context_init(&ctx, &renderer, &theme)
	win_box* box = win_page_node_box(browser.page, paint_node(browser.page, c"control"))
	assert1(box != 0)
	assert_equal(background, (box.author_paint & WIN_PAINT_BACKGROUND) != 0)
	assert_equal(text, (box.author_paint & WIN_PAINT_TEXT) != 0)
	assert_equal(border, (box.author_paint & WIN_PAINT_BORDER) != 0)
	paint_controls(&browser, &ctx)
	assert1(ctx.theme == &theme)
	if (background):
		assert_equal(0, paint_color_vertices(&renderer, theme.widget))
		assert_equal(0, paint_color_vertices(&renderer, theme.widget_hot))
		assert_equal(0, paint_color_vertices(&renderer, theme.disabled_widget))
		if (box.color.a > 0.0): assert_equal(6, paint_color_vertices(&renderer, box.color))
	else: assert1(paint_color_vertices(&renderer, theme.widget) + paint_color_vertices(&renderer, theme.widget_hot) > 0)
	if (text): assert1(paint_color_vertices(&renderer, box.text_color) > 0)
	if (border && box.border == 0): assert_equal(0, paint_color_vertices(&renderer, theme.border))
	# Recompute inherited variables on the same DOM; theme state is never cached
	# in a native widget or leaked back to browser chrome.
	if (starts_with(css, c":root")):
		html_node* node = paint_node(browser.page, c"control")
		win_form_set(node, c"style", c"--accent:#24634c")
		win_page_layout(browser.page, 800)
		paint_controls(&browser, &ctx)
		assert_equal(0, paint_color_vertices(&renderer, win_color(c"#245a78", ui_gray(0.0))))
		assert_equal(6, paint_color_vertices(&renderer, win_color(c"#24634c", ui_gray(0.0))))
		assert1(ctx.theme == &theme)
	ui_render_destroy(&renderer)
	win_forms_free(browser.forms)
	win_page_free(browser.page)

int main():
	test_form_paint(c"", c"<button id='control'>Default</button>", 0, 0, 0)
	test_form_paint(c":root{--accent:#245a78}button{background:var(--accent);color:white;border:0}", c"<button id='control'>Styled</button>", 1, 1, 1)
	test_form_paint(c"button{background:#ff000080;color:white;border:0}", c"<button disabled id='control'>Disabled</button>", 1, 1, 1)
	test_form_paint(c"button{background:transparent;color:red}", c"<button id='control'>Transparent</button>", 1, 1, 0)
	test_form_paint(c"body{color:green}", c"<button id='control'>Inherited</button>", 0, 1, 0)
	test_form_paint(c"input{background:#123456;color:white;border:0}", c"<input id='control' value='Text'>", 1, 1, 1)
	test_form_paint(c"textarea{background:#123456;color:white;border:0}", c"<textarea id='control'>Multiline</textarea>", 1, 1, 1)
	println(c"Form CSS paint, inherited text, transparent alpha and theme mutation: OK")
	return 0
