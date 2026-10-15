# Geometry regressions for Win's bounded block, row-flex and grid layout.
import lib.assert
import win.document

html_node* layout_node(win_page* page, char* id):
	html_node* node = page.html.allocations
	while (node != 0):
		if (node.kind == HTML_START && strcmp(win_attr(node, c"id"), id) == 0): return node
		node = node.allocation_next
	asserts(c"fixture node exists", 0)
	return 0

win_box* layout_box(win_page* page, char* id):
	win_box* box = win_page_node_box(page, layout_node(page, id))
	asserts(c"fixture box exists", box != 0)
	return box

void layout_close(char* message, float32 expected, float32 actual):
	asserts(message, actual > expected - 0.01 && actual < expected + 0.01)

win_page* layout_page(char* source):
	win_page* page = win_page_parse(source, strlen(source))
	asserts(c"fixture parses", page != 0)
	win_page_layout(page, 800)
	return page

void test_controls_and_percentage_constraints():
	win_page* page = layout_page(c"<div style='display:flex;width:400px'><input id='input'></div><div style='display:flex;width:400px'><button id='button'>Go</button><input id='submit' type='submit'></div><div style='display:flex;width:400px'><textarea id='textarea'></textarea></div><div style='display:flex;width:400px'><select id='select'><option>A</option></select></div><div style='display:flex;width:400px'><div id='maximum' style='width:400px;max-width:50%;margin:0'></div></div><div style='display:flex;width:400px'><input id='percent' style='width:75%;max-width:50%'></div>")
	layout_close(c"auto flex input has intrinsic width", 220.0, layout_box(page, c"input").width)
	layout_close(c"auto flex input height", 34.0, layout_box(page, c"input").height)
	layout_close(c"button intrinsic width", 100.0, layout_box(page, c"button").width)
	layout_close(c"submit intrinsic width", 100.0, layout_box(page, c"submit").width)
	layout_close(c"textarea intrinsic width", 220.0, layout_box(page, c"textarea").width)
	layout_close(c"textarea intrinsic height", 80.0, layout_box(page, c"textarea").height)
	layout_close(c"select intrinsic width", 220.0, layout_box(page, c"select").width)
	layout_close(c"percentage max width resolves once against flex container", 200.0, layout_box(page, c"maximum").width)
	layout_close(c"control percentage width and maximum resolve once", 200.0, layout_box(page, c"percent").width)
	win_page_free(page)

void test_box_sizing():
	win_page* page = layout_page(c"<div style='display:flex;width:400px;gap:10px'><div id='border' style='margin:0;width:100px;height:50px;padding:10px;border:2px solid;box-sizing:border-box'></div><div id='content' style='margin:0;width:100px;height:50px;padding:10px;border:2px solid'></div></div><div style='display:flex;width:400px'><input id='control' style='width:100px;height:50px;padding:10px;border:2px solid;box-sizing:border-box'></div><div style='display:flex;width:400px'><div id='maximum' style='width:400px;max-width:50%;padding:10px;border:2px solid;box-sizing:border-box'></div></div><div style='display:flex;width:400px'><div id='maxcontent' style='width:400px;max-width:50%;padding:10px;border:2px solid'></div></div>")
	win_box* border = layout_box(page, c"border")
	win_box* content = layout_box(page, c"content")
	layout_close(c"border box flex width", 100.0, border.width)
	layout_close(c"border box flex height preserves original sizing", 50.0, border.height)
	layout_close(c"content box flex width", 124.0, content.width)
	layout_close(c"content box flex height", 74.0, content.height)
	layout_close(c"gap begins at border box edge", border.x + border.width + 10.0, content.x)
	layout_close(c"control border box width", 100.0, layout_box(page, c"control").width)
	layout_close(c"control border box height", 50.0, layout_box(page, c"control").height)
	layout_close(c"percentage max clamps border box", 200.0, layout_box(page, c"maximum").width)
	layout_close(c"percentage max clamps content box", 224.0, layout_box(page, c"maxcontent").width)
	win_page_free(page)

void layout_image(win_page* page, char* id, int width, int height):
	win_image* image = new win_image()
	image.node = layout_node(page, id)
	image.width = width
	image.height = height
	page.images.push(image)

win_run* layout_image_run(win_page* page, char* id):
	html_node* node = layout_node(page, id)
	for i in range(page.runs.length):
		if (page.runs[i].node == node && page.runs[i].image != 0): return page.runs[i]
	asserts(c"image run exists", 0)
	return 0

void test_image_intrinsic_sizes():
	char* source = c"<div style='display:flex;width:400px'><img id='natural'></div><div style='display:flex;width:400px'><img id='attribute' height='40'></div><div style='display:flex;width:400px'><img id='percent' style='width:75%;max-width:50%'></div><div style='display:flex;width:400px'><img id='border' style='width:100px;padding:10px;border:2px solid;box-sizing:border-box'></div><div style='display:flex;width:400px'><div id='nested' style='margin:0'><img id='child'></div></div><div style='display:flex;width:400px'><img id='missing' alt='fallback'></div>"
	win_page* page = win_page_parse(source, strlen(source))
	layout_image(page, c"natural", 80, 40)
	layout_image(page, c"attribute", 120, 60)
	layout_image(page, c"percent", 800, 400)
	layout_image(page, c"border", 80, 40)
	layout_image(page, c"child", 90, 45)
	win_page_layout(page, 800)
	layout_close(c"natural image flex box width", 80.0, layout_box(page, c"natural").width)
	layout_close(c"natural image run width", 80.0, layout_image_run(page, c"natural").width)
	layout_close(c"height attribute transfers image aspect ratio", 80.0, layout_box(page, c"attribute").width)
	layout_close(c"image max width resolves once", 200.0, layout_box(page, c"percent").width)
	layout_close(c"image resized aspect ratio", 100.0, layout_image_run(page, c"percent").height)
	layout_close(c"image border box width", 100.0, layout_box(page, c"border").width)
	layout_close(c"image border box content width", 76.0, layout_image_run(page, c"border").width)
	layout_close(c"nested image contributes intrinsic width", 90.0, layout_box(page, c"nested").width)
	asserts(c"missing image contributes alt text intrinsic width", layout_box(page, c"missing").width > 0.0)
	win_page_free(page)

void test_anonymous_and_hidden_items():
	win_page* page = layout_page(c"<div id='row' style='display:flex;width:400px;gap:10px;margin:0'>word<!-- comment --> text<span id='none' style='display:none;width:300px'>none</span><input id='hidden' type='hidden'><span id='hiddenattr' hidden>hidden</span><span id='visible' style='width:20px'>v</span>   <span id='invisible' style='visibility:hidden;width:30px'>i</span></div>")
	html_node* node = layout_node(page, c"row")
	win_style style = win_node_style(page, node, win_default_style())
	list[win_layout_item*] items = win_layout_items(page, node, style)
	asserts(c"anonymous text grouped and whitespace-only/hidden items omitted", items.length == 3 && items[0].anonymous && items[1].first == layout_node(page, c"visible") && items[2].first == layout_node(page, c"invisible"))
	win_box* row = layout_box(page, c"row")
	win_box* visible = layout_box(page, c"visible")
	layout_close(c"anonymous text uses intrinsic width and one gap", row.x + items[0].intrinsic.max_content + 10.0, visible.x)
	layout_close(c"visibility hidden preserves width and gap", visible.x + 30.0, layout_box(page, c"invisible").x)
	asserts(c"visibility hidden keeps hidden geometry", layout_box(page, c"invisible").hidden)
	asserts(c"display none has no box", win_page_node_box(page, layout_node(page, c"none")) == 0)
	for i in range(items.length): free(items[i])
	__w_list_free(cast(__w_list*, items))
	win_page_free(page)

void test_flex_shrink_freezing():
	win_page* page = layout_page(c"<div id='row' style='display:flex;width:300px;gap:10px;margin:0'><div id='fixed' style='margin:0;width:100px'><input style='width:100px'></div><div id='shrunk' style='margin:0;width:300px'>a a a a a a a a a a</div></div>")
	win_box* fixed = layout_box(page, c"fixed")
	win_box* shrunk = layout_box(page, c"shrunk")
	layout_close(c"content minimum freezes first flex item", 100.0, fixed.width)
	layout_close(c"remaining deficit redistributes after freeze", 190.0, shrunk.width)
	layout_close(c"shrunk row fits after gap", layout_box(page, c"row").x + 300.0, shrunk.x + shrunk.width)
	win_page_free(page)
	page = layout_page(c"<div style='display:flex;width:500px'><input id='first' style='width:300px'><input id='second' style='width:300px'></div>")
	layout_close(c"specified control width can shrink toward intrinsic minimum", 250.0, layout_box(page, c"first").width)
	layout_close(c"control shrink weights share deficit", 250.0, layout_box(page, c"second").width)
	win_page_free(page)

void test_fixed_height_overflow():
	win_page* page = layout_page(c"<div id='outer' style='height:10px;margin:0;padding:5px;border:1px solid'><div id='child' style='height:120px;margin:0'>overflow</div></div><div id='next' style='height:5px;margin:0'></div>")
	win_box* outer = layout_box(page, c"outer")
	win_box* child = layout_box(page, c"child")
	layout_close(c"fixed height does not grow to fit contents", 22.0, outer.height)
	layout_close(c"next sibling follows fixed border box", outer.y + outer.height, layout_box(page, c"next").y)
	asserts(c"visible overflow contributes to document scroll height", page.height >= child.y + child.height + 28.0)
	win_page_free(page)

int main():
	test_controls_and_percentage_constraints()
	test_box_sizing()
	test_image_intrinsic_sizes()
	test_anonymous_and_hidden_items()
	test_flex_shrink_freezing()
	test_fixed_height_overflow()
	println(c"Win intrinsic sizing, flex allocation, box sizing and overflow: OK")
	return 0
