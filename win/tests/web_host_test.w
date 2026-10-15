# Host primitives can be exercised without script.w integration or a window.
import lib.assert
import win.web_host

void web_text(js_value* value, char* expected):
	assert_equal(4, value.kind)
	js_text* text = js_runtime_key(expected)
	asserts(c"exact string", js_text_equal(value.text, text))
	js_text_free(text)

js_value* web_query(js_runtime* rt, char* query, char* key):
	js_text* q = js_runtime_key(query)
	js_text* k = js_runtime_key(key)
	js_value* result = win_web_search_get(rt, q, k)
	js_text_free(q)
	js_text_free(k)
	return result

void test_web_query():
	js_runtime* rt = js_runtime_new()
	rt.remaining = 100000
	web_text(web_query(rt, c"?module=one%2Ftwo.wasm&module=ignored", c"module"), c"one/two.wasm")
	web_text(web_query(rt, c"a+b=x+y%2Bz&x=1=2", c"a b"), c"x y+z")
	web_text(web_query(rt, c"x=1=2", c"x"), c"1=2")
	web_text(web_query(rt, c"&&empty&=blank&&", c"empty"), c"")
	web_text(web_query(rt, c"&&empty&=blank&&", c""), c"blank")
	assert_equal(1, web_query(rt, c"&&", c"").kind)
	assert_equal(1, web_query(rt, c"x=", c"missing").kind)
	web_text(web_query(rt, c"x=%GG%2#fragment", c"x"), c"%GG%2#fragment")
	web_text(web_query(rt, c"x=%E2%82%AC", c"x"), c"€")
	web_text(web_query(rt, c"x=%E2%82A", c"x"), c"�A")
	web_text(web_query(rt, c"x=%E0%80%80", c"x"), c"���")
	web_text(web_query(rt, c"x=%F0%9F%98%80", c"x"), c"😀")
	js_value* nul = web_query(rt, c"%00=a%00b", c"")
	assert_equal(1, nul.kind)
	js_text* query = js_runtime_key(c"%00=a%00b")
	js_text* key = js_text_new()
	key.units.push(0)
	nul = win_web_search_get(rt, query, key)
	assert_equal(3, nul.text.units.length)
	assert_equal(0, nul.text.units[1])
	js_text_free(query)
	js_text_free(key)
	query = js_runtime_key(c"x=")
	query.units.push(55296)
	key = js_runtime_key(c"x")
	web_text(win_web_search_get(rt, query, key), c"�")
	rt.remaining = 0
	win_web_search_get(rt, query, key)
	asserts(c"query respects budget", rt.completion.status != 0)
	js_text_free(query)
	js_text_free(key)
	js_runtime_free(rt)
	char* search = win_web_location_search(c"https://host/path?module=x%23y#?ignored")
	asserts(c"location excludes fragment", strcmp(search, c"?module=x%23y") == 0)
	free(search)
	search = win_web_location_search(c"file:///a#?not=query")
	assert_equal(0, strlen(search))
	free(search)
	search = win_web_location_search(c"https://host/?#f")
	assert_equal(0, strlen(search))
	free(search)

html_node* web_node(win_page* page, char* id):
	html_node* node = page.html.allocations
	while (node != 0):
		if (node.kind == HTML_START && strcmp(win_attr(node, c"id"), id) == 0): return node
		node = node.allocation_next
	asserts(c"fixture node exists", 0)
	return 0

js_value* web_computed(js_runtime* rt, win_page* page, html_node* node, char* name):
	js_text* key = js_runtime_key(name)
	js_value* result = win_web_computed_get(rt, page, node, key)
	js_text_free(key)
	return result

js_value* web_dimension(js_runtime* rt, win_page* page, html_node* node, char* name):
	js_text* key = js_runtime_key(name)
	js_value* result = win_web_dimension(rt, page, node, key)
	js_text_free(key)
	return result

void web_number(js_runtime* rt, js_value* object, char* key, float64 expected):
	js_value* value = js_runtime_get(rt, object, key)
	assert_equal(3, value.kind)
	asserts(key, value.number > expected - 0.001 && value.number < expected + 0.001)

void test_web_geometry():
	char* source = c"<style>#box{padding:1em 3px 4px 5px!important}</style><div style='font-size:20px'><div id='box' style='width:100px;height:50px;border:2px solid;padding:99px'></div><canvas id='canvas' width='640' height='480' style='width:320px;height:240px'></canvas><span id='inline'>text</span><div id='hidden' style='display:none'>hidden</div></div>"
	win_page* page = win_page_parse(source, strlen(source))
	win_page_layout(page, 800)
	js_runtime* rt = js_runtime_new()
	rt.remaining = 100000
	html_node* node = web_node(page, c"box")
	web_text(web_computed(rt, page, node, c"paddingTop"), c"20px")
	web_text(web_computed(rt, page, node, c"padding-left"), c"5px")
	web_text(web_computed(rt, page, node, c"paddingRight"), c"3px")
	web_text(web_computed(rt, page, node, c"paddingBottom"), c"4px")
	web_text(web_computed(rt, page, node, c"fontSize"), c"20px")
	asserts(c"unsupported computed property is unhandled", web_computed(rt, page, node, c"transform") == 0)
	win_web_viewport viewport
	viewport.width = 800.0
	viewport.height = 600.0
	viewport.ratio = 1.5
	viewport.scroll_x = 3.0
	viewport.scroll_y = 10.0
	js_text* key = js_runtime_key(c"devicePixelRatio")
	asserts(c"surface ratio", win_web_viewport_get(rt, &viewport, key).number == 1.5)
	js_text_free(key)
	key = js_runtime_key(c"innerHeight")
	asserts(c"surface height", win_web_viewport_get(rt, &viewport, key).number == 600.0)
	viewport.height = 400.0
	asserts(c"viewport updates are live", win_web_viewport_get(rt, &viewport, key).number == 400.0)
	js_text_free(key)
	key = js_runtime_key(c"visualViewport")
	asserts(c"no invented visual viewport", win_web_viewport_get(rt, &viewport, key) == 0)
	js_text_free(key)
	win_box* box = win_page_node_box(page, node)
	asserts(c"layout box exists", box != 0)
	js_value* rect = win_web_rect(rt, page, node, &viewport)
	web_number(rt, rect, c"left", cast(float64, box.x) - 3.0)
	web_number(rt, rect, c"top", cast(float64, box.y) - 10.0)
	web_number(rt, rect, c"width", 112.0)
	web_number(rt, rect, c"height", 78.0)
	web_number(rt, rect, c"right", cast(float64, box.x) + 109.0)
	web_number(rt, rect, c"bottom", cast(float64, box.y) + 68.0)
	asserts(c"offset border box", web_dimension(rt, page, node, c"offsetWidth").number == 112.0)
	asserts(c"client excludes border", web_dimension(rt, page, node, c"clientWidth").number == 108.0)
	asserts(c"client padding height", web_dimension(rt, page, node, c"clientHeight").number == 74.0)
	asserts(c"scroll sizing unhandled", web_dimension(rt, page, node, c"scrollHeight") == 0)
	js_value* hidden = win_web_rect(rt, page, web_node(page, c"hidden"), &viewport)
	web_number(rt, hidden, c"x", 0.0)
	web_number(rt, hidden, c"width", 0.0)
	js_value* inline_rect = win_web_rect(rt, page, web_node(page, c"inline"), &viewport)
	asserts(c"inline text geometry", js_runtime_get(rt, inline_rect, c"width").number > 0.0)
	js_value* canvas = win_web_rect(rt, page, web_node(page, c"canvas"), &viewport)
	web_number(rt, canvas, c"width", 320.0)
	web_number(rt, canvas, c"height", 240.0)
	asserts(c"inline offset width uses text runs", web_dimension(rt, page, web_node(page, c"inline"), c"offsetWidth").number > 0.0)
	asserts(c"inline client width is zero", web_dimension(rt, page, web_node(page, c"inline"), c"clientWidth").number == 0.0)
	# A previous rectangle remains a snapshot when scrolling changes.
	viewport.scroll_y = 30.0
	js_value* after = win_web_rect(rt, page, node, &viewport)
	web_number(rt, after, c"y", cast(float64, box.y) - 30.0)
	web_number(rt, rect, c"y", cast(float64, box.y) - 10.0)
	assert_equal(0, rt.completion.status)
	js_runtime_free(rt)
	win_page_free(page)

int main():
	test_web_query()
	test_web_geometry()
	println(c"Win web host query, viewport, computed padding and geometry: OK")
	return 0
