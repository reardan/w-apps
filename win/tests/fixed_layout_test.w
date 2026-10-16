import lib.assert
import win.document
import win.cssom

html_node* fixed_node(win_page* page, char* id):
	html_node* node = page.html.allocations
	while (node != 0):
		if (node.kind == HTML_START && strcmp(win_attr(node, c"id"), id) == 0): return node
		node = node.allocation_next
	return 0

win_box* fixed_box(win_page* page, char* id):
	win_box* box = win_page_node_box(page, fixed_node(page, id))
	asserts(c"fixed fixture box exists", box != 0)
	return box

void fixed_close(char* message, float32 expected, float32 actual):
	asserts(message, actual > expected - 0.01 && actual < expected + 0.01)

win_page* fixed_page(char* content):
	string_builder* source = string_from(c"<style>body{margin:0}</style>")
	string_append(source, content)
	win_page* page = win_page_parse(source.data, source.length)
	string_free(source)
	win_page_set_viewport(page, 400, 300)
	win_page_layout(page, 388)
	return page

void fixed_flow_and_scroll():
	win_page* page = fixed_page(c"<div id='normal' style='height:800px'></div><div id='fixed' style='position:fixed;top:10px;left:20px;width:100px;height:40px'><a href='#target'>fixed link</a></div><textarea id='editor' style='position:fixed;top:900px;left:-10px;width:1px;height:1px;padding:0;border:0'></textarea>")
	fixed_close(c"generic containers have zero UA margin", 0.0, fixed_box(page, c"normal").y)
	fixed_close(c"fixed roots excluded from scroll extent", 800.0, page.height)
	fixed_close(c"fixed left", 20.0, fixed_box(page, c"fixed").x)
	fixed_close(c"fixed top", 10.0, fixed_box(page, c"fixed").y)
	fixed_close(c"negative insets retained", -10.0, fixed_box(page, c"editor").x)
	win_page_set_scroll(page, 120.0)
	fixed_close(c"fixed box follows page scroll transform", 130.0, fixed_box(page, c"fixed").y)
	fixed_close(c"normal geometry never translated", 0.0, fixed_box(page, c"normal").y)
	for i in range(page.runs.length):
		win_run* run = page.runs[i]
		if (run.href[0] != 0):
			assert1(run.fixed && run.y >= 130.0)
			asserts(c"hit and paint share fixed coordinates", strcmp(win_page_hit(page, run.x + 1.0, run.y + 1.0), c"#target") == 0)
	win_page_layout(page, 388)
	fixed_close(c"relayout preserves current scroll exactly once", 130.0, fixed_box(page, c"fixed").y)
	win_page_set_scroll(page, 0.0)
	fixed_close(c"scroll restore does not drift", 10.0, fixed_box(page, c"fixed").y)
	win_page_free(page)

void fixed_insets_and_resize():
	win_page* page = fixed_page(c"<div id='stretch' style='position:fixed;top:10%;bottom:20px;left:calc(25% - 10px);right:10px;padding:5px;border:2px solid'></div><div id='outer' style='position:fixed;right:10px;bottom:20px;width:100px;height:60px'><div id='inner' style='position:fixed;left:5px;top:7px;width:20px;height:10px'></div></div><div id='percent' style='position:fixed;left:10px;top:0;width:50%;height:10px'></div>")
	fixed_close(c"mixed percentage inset", 90.0, fixed_box(page, c"stretch").x)
	fixed_close(c"auto width stretches between insets", 300.0, fixed_box(page, c"stretch").width)
	fixed_close(c"percentage top uses viewport height", 30.0, fixed_box(page, c"stretch").y)
	fixed_close(c"auto height stretches including border and padding", 250.0, fixed_box(page, c"stretch").height)
	fixed_close(c"right anchor", 290.0, fixed_box(page, c"outer").x)
	fixed_close(c"bottom anchor", 220.0, fixed_box(page, c"outer").y)
	fixed_close(c"nested fixed x is viewport relative", 5.0, fixed_box(page, c"inner").x)
	fixed_close(c"nested fixed y is viewport relative", 7.0, fixed_box(page, c"inner").y)
	fixed_close(c"width percentage uses full viewport", 200.0, fixed_box(page, c"percent").width)
	fixed_close(c"only fixed content has no flow extent", 0.0, page.height)
	win_page_set_viewport(page, 600, 500)
	win_page_layout(page, 588)
	fixed_close(c"resize recomputes percentage inset", 140.0, fixed_box(page, c"stretch").x)
	fixed_close(c"resize recomputes auto stretch", 450.0, fixed_box(page, c"stretch").width)
	fixed_close(c"resize bottom anchor", 420.0, fixed_box(page, c"outer").y)
	win_page_free(page)

void fixed_flex_and_cascade():
	win_page* page = fixed_page(c"<div id='column' style='display:flex;flex-direction:column;height:100px;width:100px'><div id='a' style='flex:1 1 0px'></div><div id='b' style='position:fixed;left:0;top:0;width:900px;height:900px'></div><div id='c' style='flex:1 1 0px'></div></div><div id='grid' style='display:grid;grid-template-columns:1fr 1fr;width:100px'><div id='g1' style='height:20px'></div><div style='position:fixed;top:1000px;width:1000px;height:1000px'></div><div id='g2' style='height:20px'></div></div><div id='parent' style='position:fixed;top:20px;left:30px;width:100px'><div id='inherit' style='position:inherit;top:inherit;left:inherit;width:10px;height:10px'></div></div>")
	fixed_close(c"fixed flex child consumes no growth", 50.0, fixed_box(page, c"a").height)
	fixed_close(c"fixed flex child consumes no slot", 50.0, fixed_box(page, c"c").y)
	fixed_close(c"fixed grid child consumes no slot", fixed_box(page, c"g1").y, fixed_box(page, c"g2").y)
	fixed_close(c"flex grid measurement excludes fixed descendants", 120.0, page.height)
	fixed_close(c"CSS-wide position inherit", 30.0, fixed_box(page, c"inherit").x)
	fixed_close(c"CSS-wide inset inherit", 20.0, fixed_box(page, c"inherit").y)
	assert1(fixed_box(page, c"inherit").fixed)
	char* updated = win_cssom_edit(c"position:fixed;left:5px", c"left", c"calc(20% - 2px)", c"")
	char* value = win_cssom_get(updated, c"left", 0)
	assert1(strcmp(value, c"calc(20% - 2px)") == 0)
	free(value)
	free(updated)
	win_page_free(page)

int main():
	fixed_flow_and_scroll()
	fixed_insets_and_resize()
	fixed_flex_and_cascade()
	println(c"Viewport fixed layout: flow exclusion, insets, nested roots, scroll, resize and CSSOM: OK")
	return 0
