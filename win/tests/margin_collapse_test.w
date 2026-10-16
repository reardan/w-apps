import lib.assert
import win.document

html_node* margin_node(win_page* page, char* id):
	html_node* node = page.html.allocations
	while (node != 0):
		if (node.kind == HTML_START && strcmp(win_attr(node, c"id"), id) == 0): return node
		node = node.allocation_next
	return 0

win_box* margin_box(win_page* page, char* id):
	win_box* box = win_page_node_box(page, margin_node(page, id))
	assert1(box != 0)
	return box

win_page* margin_page(char* source):
	string_builder* html = string_from(c"<style>body{margin:0}div{height:10px}</style>")
	string_append(html, source)
	win_page* page = win_page_parse(html.data, html.length)
	string_free(html)
	win_page_set_viewport(page, 400, 300)
	win_page_layout(page, 400)
	return page

void margin_close(float32 expected, float32 actual):
	assert1(actual > expected - 0.01 && actual < expected + 0.01)

void margin_pair(char* source, float32 gap):
	win_page* page = margin_page(source)
	win_box* a = margin_box(page, c"a")
	win_box* b = margin_box(page, c"b")
	margin_close(gap, b.y - a.y - a.height)
	win_page_free(page)

void test_margin_pairs():
	margin_pair(c"<div id=a style='margin-bottom:12px'></div><div id=b style='margin-top:20px'></div>", 20.0)
	margin_pair(c"<div id=a style='margin-bottom:20px'></div> \n<!-- comment --><div hidden></div><div style='display:none'></div><div id=b style='margin-top:12px'></div>", 20.0)
	margin_pair(c"<div id=a style='margin-bottom:20px'></div><div id=b style='margin-top:-7px'></div>", 13.0)
	margin_pair(c"<div id=a style='margin-bottom:-7px'></div><div id=b style='margin-top:-12px'></div>", -12.0)
	margin_pair(c"<div id=a style='margin-bottom:20px'></div><div style='position:fixed;top:0;height:99px'></div><div id=b style='margin-top:12px'></div>", 20.0)
	margin_pair(c"<div id=a style='margin-bottom:20px;border:2px solid;padding:3px'></div><div id=b style='margin-top:12px;border:2px solid;padding:3px'></div>", 20.0)

void test_margin_contexts():
	margin_pair(c"<section style='display:flex;flex-direction:column'><div id=a style='margin-bottom:20px'></div><div id=b style='margin-top:12px'></div></section>", 32.0)
	margin_pair(c"<section style='display:grid;grid-template-columns:1fr'><div id=a style='margin-bottom:20px'></div><div id=b style='margin-top:12px'></div></section>", 32.0)
	win_page* page = margin_page(c"<div id=a style='margin-bottom:20px'></div><span>line</span><div id=b style='margin-top:12px'></div>")
	win_box* a = margin_box(page, c"a")
	assert1(margin_box(page, c"b").y - a.y - a.height > 32.0)
	win_page_free(page)

void test_paragraph_defaults():
	win_page* page = margin_page(c"<p id=a style='font-size:24px;height:10px'></p><p id=b style='font-size:24px;height:10px'></p><p id=c style='margin:0;height:10px'></p>")
	win_box* a = margin_box(page, c"a")
	win_box* b = margin_box(page, c"b")
	margin_close(24.0, a.y)
	margin_close(24.0, b.y - a.y - a.height)
	margin_close(24.0, margin_box(page, c"c").y - b.y - b.height)
	win_style style = win_node_style(page, margin_node(page, c"c"), win_default_style())
	margin_close(0.0, style.margin_top)
	margin_close(0.0, style.margin_bottom)
	win_page_free(page)

int main():
	test_margin_pairs()
	test_margin_contexts()
	test_paragraph_defaults()
	println(c"Adjacent normal-block margins and paragraph UA defaults: OK")
	return 0
