import lib.assert
import win.document

html_node* root_test_node(win_page* page, char* name):
	html_node* node = page.html.allocations
	while (node != 0):
		if (win_tag(node, name)): return node
		node = node.allocation_next
	return 0

win_page* root_test_page(char* source):
	win_page* page = win_page_parse(source, strlen(source))
	win_page_set_viewport(page, 800, 600)
	win_page_layout(page, 800)
	return page

void root_test_defaults():
	win_page* page = root_test_page(c"<div style='margin:0;width:40px;height:30px'></div>")
	html_node* root = root_test_node(page, c"html")
	html_node* body = root_test_node(page, c"body")
	win_style root_style = win_node_style(page, root, win_default_style())
	win_style body_style = win_node_style(page, body, root_style)
	assert1(root_style.display == 1 && root_style.margin_top == 0.0 && root_style.margin_left == 0.0)
	assert1(body.implied && body_style.margin_top == 20.0 && body_style.margin_left == 28.0 && body_style.margin_bottom == 28.0)
	win_box* box = win_page_node_box(page, root_test_node(page, c"div"))
	assert1(box.x == 28.0 && box.y == 20.0 && page.height == 78.0)
	assert1(win_page_node_box(page, root).x == 0.0 && win_page_node_box(page, root).width == 800.0)
	win_page_free(page)
	page = root_test_page(c"<style>body{margin:0}</style><div style='margin:0;width:100%;height:100vh'></div>")
	box = win_page_node_box(page, root_test_node(page, c"div"))
	assert1(box.x == 0.0 && box.y == 0.0 && box.width == 800.0 && box.height == 600.0 && page.height == 600.0)
	win_page_free(page)
	page = root_test_page(c"<body style='margin:3px 4px 5px 6px'><div style='margin:0;height:7px'></div></body>")
	box = win_page_node_box(page, root_test_node(page, c"div"))
	assert1(box.x == 6.0 && box.y == 3.0 && box.width == 790.0 && page.height == 15.0)
	win_page_free(page)
	page = root_test_page(c"<style>body{margin:initial}</style><canvas style='display:block' width='800' height='600'></canvas>")
	assert1(page.runs[0].x == 0.0 && page.runs[0].y == 0.0 && page.runs[0].width == 800.0)
	win_page_free(page)

void root_test_backgrounds():
	win_page* page = root_test_page(c"<style>body{background:rgba(255,0,0,.5)}</style><p>text</p>")
	win_box* background = page.boxes[0]
	assert1(background.node == page.html.root && background.x == 0.0 && background.y == 0.0 && background.width == 800.0 && background.height == 600.0)
	assert1(background.color.r == 1.0 && background.color.a == 0.5)
	assert1(win_page_node_box(page, root_test_node(page, c"body")).color.a == 0.0)
	win_style computed = win_node_style(page, root_test_node(page, c"body"), win_default_style())
	assert1(computed.background.a == 0.5)
	win_page_free(page)
	page = root_test_page(c"<style>html{margin:11px;background:blue}body{background:red;margin:0;height:20px}</style>")
	assert1(page.boxes[0].color.b == 1.0 && page.boxes[0].height == 600.0)
	assert1(win_page_node_box(page, root_test_node(page, c"html")).color.a == 0.0)
	assert1(win_page_node_box(page, root_test_node(page, c"body")).color.r == 1.0)
	win_page_free(page)
	page = root_test_page(c"<body style='display:none;background:red'></body>")
	assert1(page.boxes.length == 1 && page.boxes[0].color.a == 0.0)
	win_page_free(page)
	page = root_test_page(c"<html style='display:none;background:red'><body>hidden</body></html>")
	assert_equal(0, page.boxes.length)
	win_page_free(page)

int main():
	root_test_defaults()
	root_test_backgrounds()
	println(c"Root layout: overridable UA body margins, viewport background and alpha ownership: OK")
	return 0
