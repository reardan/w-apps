# CSS Flexbox 1 section 5.1: reverse main axes preserve DOM and paint order.
import lib.assert
import win.document

html_node* reverse_node(win_page* page, char* id):
	html_node* node = page.html.allocations
	while (node != 0):
		if (node.kind == HTML_START && strcmp(win_attr(node, c"id"), id) == 0): return node
		node = node.allocation_next
	return 0

win_box* reverse_box(win_page* page, char* id):
	win_box* box = win_page_node_box(page, reverse_node(page, id))
	asserts(c"reverse fixture box exists", box != 0)
	return box

void reverse_close(char* message, float32 expected, float32 actual):
	asserts(message, actual > expected - 0.01 && actual < expected + 0.01)

void test_reverse_rows():
	char* source = c"<style>body{margin:0}.row{display:flex;flex-direction:row-reverse;width:300px;gap:10px}.row>div{flex:0 0 50px;height:20px}</style><div id='row' class='row'><div id='a' style='margin-left:7px;margin-right:13px'></div><div id='b'></div></div><div class='row' style='justify-content:flex-end'><div id='end1'></div><div id='end2'></div></div><div class='row' style='justify-content:space-between'><div id='space1'></div><div id='space2'></div></div><div class='row'><div id='auto' style='margin-left:auto'></div><div id='after'></div></div><div class='row' style='width:120px;flex-wrap:wrap'><div id='wrap1'></div><div id='wrap2'></div><div id='wrap3'></div></div>"
	win_page* page = win_page_parse(source, strlen(source))
	win_page_layout(page, 600)
	reverse_close(c"reverse row retains physical right margin", 237.0, reverse_box(page, c"a").x)
	reverse_close(c"reverse row gap and left margin", 170.0, reverse_box(page, c"b").x)
	reverse_close(c"reverse flex-end aligns to left", 60.0, reverse_box(page, c"end1").x)
	reverse_close(c"reverse end last item at left", 0.0, reverse_box(page, c"end2").x)
	reverse_close(c"reverse space-between starts right", 250.0, reverse_box(page, c"space1").x)
	reverse_close(c"reverse space-between ends left", 0.0, reverse_box(page, c"space2").x)
	reverse_close(c"reverse left auto margin occupies middle", 250.0, reverse_box(page, c"auto").x)
	reverse_close(c"auto margin leaves final item at left", 0.0, reverse_box(page, c"after").x)
	reverse_close(c"wrapped first item starts right", 70.0, reverse_box(page, c"wrap1").x)
	reverse_close(c"wrapped second item uses gap", 10.0, reverse_box(page, c"wrap2").x)
	reverse_close(c"wrapped new line starts right", 70.0, reverse_box(page, c"wrap3").x)
	reverse_close(c"wrapping doesn't reverse cross direction", reverse_box(page, c"wrap1").y + 30.0, reverse_box(page, c"wrap3").y)
	int first_index = -1
	int second_index = -1
	for i in range(page.boxes.length):
		if (page.boxes[i].node == reverse_node(page, c"a")): first_index = i
		if (page.boxes[i].node == reverse_node(page, c"b")): second_index = i
	asserts(c"box emission stays in DOM order", first_index >= 0 && second_index > first_index)
	win_page_free(page)

void test_reverse_columns():
	char* source = c"<style>body{margin:0}.column{display:flex;flex-direction:column-reverse;width:200px;gap:10px}.column>div{flex:0 0 30px}</style><div id='col' class='column' style='height:160px'><div id='a' style='margin-top:7px;margin-bottom:13px'><a id='anchor' href='#hit'>link</a></div><div id='b'></div></div><div id='natural' class='column'><div id='n1'></div><div id='n2'></div></div><div id='end' class='column' style='height:160px;justify-content:flex-end'><div id='e1'></div><div id='e2'></div></div><div id='nested' class='column' style='height:200px'><div id='child' style='display:flex;flex-direction:column-reverse;flex:1 1 0px'><div id='top' style='flex:1 1 0px'></div><div id='bottom' style='flex:3 1 0px'></div></div></div>"
	win_page* page = win_page_parse(source, strlen(source))
	win_page_layout(page, 600)
	reverse_close(c"reverse column physical bottom margin", 117.0, reverse_box(page, c"a").y)
	reverse_close(c"reverse column gap and top margin", 70.0, reverse_box(page, c"b").y)
	reverse_close(c"natural reverse column height", 70.0, reverse_box(page, c"natural").height)
	reverse_close(c"natural reverse first item at bottom", reverse_box(page, c"natural").y + 40.0, reverse_box(page, c"n1").y)
	reverse_close(c"natural reverse last item at top", reverse_box(page, c"natural").y, reverse_box(page, c"n2").y)
	reverse_close(c"reverse column end aligns toward top", reverse_box(page, c"end").y + 40.0, reverse_box(page, c"e1").y)
	reverse_close(c"reverse column end last item at top", reverse_box(page, c"end").y, reverse_box(page, c"e2").y)
	reverse_close(c"nested reverse growth", 50.0, reverse_box(page, c"top").height)
	reverse_close(c"nested reverse last child grows", 150.0, reverse_box(page, c"bottom").height)
	reverse_close(c"nested reverse first child at bottom", reverse_box(page, c"child").y + 150.0, reverse_box(page, c"top").y)
	reverse_close(c"anchor follows translated text", reverse_box(page, c"a").y, win_page_anchor(page, c"anchor"))
	int hits = 0
	for i in range(page.runs.length):
		win_run* run = page.runs[i]
		if (run.href[0] != 0):
			assert_strings_equal(c"#hit", win_page_hit(page, run.x + 1.0, run.y + 1.0))
			hits = hits + 1
	assert_equal(1, hits)
	win_page_free(page)

void test_reverse_resize_and_inheritance():
	char* source = c"<style>body{margin:0}#outer{display:flex;flex-direction:row-reverse;width:200px;height:100px}#a,#b{flex:0 0 40px;height:20px}#a{display:flex;flex-direction:inherit}#inner{flex-direction:initial}@media(max-width:500px){#outer{flex-direction:column-reverse}}</style><div id='outer'><div id='a'><span id='inner'>word</span></div><div id='b'></div></div>"
	win_page* page = win_page_parse(source, strlen(source))
	win_page_layout(page, 800)
	reverse_close(c"row reverse before resize", 160.0, reverse_box(page, c"a").x)
	win_style inherited = win_node_style(page, reverse_node(page, c"outer"), win_default_style())
	win_style child = win_node_style(page, reverse_node(page, c"a"), inherited)
	assert_equal(1, child.flex_reverse)
	assert_equal(0, child.flex_column)
	win_style reset = win_node_style(page, reverse_node(page, c"inner"), child)
	assert_equal(0, reset.flex_reverse)
	assert_equal(0, reset.flex_column)
	win_page_layout(page, 400)
	reverse_close(c"resize recomputes reversed column main axis", 60.0, reverse_box(page, c"a").y)
	reverse_close(c"resize recomputes reversed sibling", 20.0, reverse_box(page, c"b").y)
	inherited = win_node_style(page, reverse_node(page, c"outer"), win_default_style())
	child = win_node_style(page, reverse_node(page, c"a"), inherited)
	assert_equal(1, child.flex_reverse)
	assert_equal(1, child.flex_column)
	win_page_free(page)

int main():
	test_reverse_rows()
	test_reverse_columns()
	test_reverse_resize_and_inheritance()
	println(c"Reverse flex geometry, wrapping, margins, nested growth and link hits: OK")
	return 0
