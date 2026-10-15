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

void test_declared_flex_sizes():
	win_page* page = layout_page(c"<div style='display:flex;width:400px;gap:10px'><div id='a' style='margin:0;flex:1;height:10px'></div><div id='b' style='margin:0;flex:3;height:10px'></div></div><div style='display:flex;width:400px'><div id='fraction' style='margin:0;flex:.25 1 0px'></div></div>")
	layout_close(c"grow factors allocate one quarter after gap", 97.5, layout_box(page, c"a").width)
	layout_close(c"grow factors allocate three quarters", 292.5, layout_box(page, c"b").width)
	layout_close(c"grow sum below one leaves unused space", 100.0, layout_box(page, c"fraction").width)
	win_page_free(page)
	page = layout_page(c"<div style='display:flex;width:500px'><div id='cap' style='margin:0;flex:1;max-width:100px'></div><div id='rest' style='margin:0;flex:1'></div></div><div style='display:flex;width:300px'><div id='large' style='margin:0;flex:1 1 400px;max-width:100px'></div><div id='small' style='margin:0;flex:1 1 100px'></div></div>")
	layout_close(c"growth freezes at maximum", 100.0, layout_box(page, c"cap").width)
	layout_close(c"growth redistributes after maximum freeze", 400.0, layout_box(page, c"rest").width)
	layout_close(c"hypothetical sizes select growth and freeze oversized base", 100.0, layout_box(page, c"large").width)
	layout_close(c"inflexible base cannot consume remaining growth", 200.0, layout_box(page, c"small").width)
	win_page_free(page)
	page = layout_page(c"<div style='display:flex;width:300px'><div id='a' style='margin:0;width:200px;flex-shrink:1'></div><div id='b' style='margin:0;width:200px;flex-shrink:3'></div></div><div style='display:flex;width:300px'><div id='fraction' style='margin:0;flex:0 .25 400px'></div></div><div style='display:flex;width:100px'><div id='fixed' style='margin:0;width:200px;flex:none'></div></div>")
	layout_close(c"shrink weights include declared factor", 175.0, layout_box(page, c"a").width)
	layout_close(c"larger shrink factor absorbs three quarters", 125.0, layout_box(page, c"b").width)
	layout_close(c"shrink sum below one permits remaining overflow", 375.0, layout_box(page, c"fraction").width)
	layout_close(c"flex none preserves fixed width despite overflow", 200.0, layout_box(page, c"fixed").width)
	win_page_free(page)
	page = layout_page(c"<div style='display:flex;width:400px'><div id='percent' style='margin:0;width:300px;flex:0 0 25%'></div><div id='auto' style='margin:0;width:80px;flex:0 0 auto'></div><div id='content' style='margin:0;width:90px;flex:0 0 content'></div></div><div style='display:flex;width:400px'><div id='border' style='margin:0;box-sizing:border-box;padding:10px;flex:0 0 25%'></div><div id='contentbox' style='margin:0;padding:10px;flex:0 0 25%'></div></div>")
	layout_close(c"percent basis overrides width and resolves against container", 100.0, layout_box(page, c"percent").width)
	layout_close(c"auto basis uses specified width", 80.0, layout_box(page, c"auto").width)
	layout_close(c"content basis ignores specified width", 0.0, layout_box(page, c"content").width)
	layout_close(c"basis respects border box sizing", 100.0, layout_box(page, c"border").width)
	layout_close(c"basis respects content box sizing", 120.0, layout_box(page, c"contentbox").width)
	win_page_free(page)
	page = layout_page(c"<div style='display:flex;width:300px'><div id='min' style='margin:0;flex:1 1 0px'><input style='width:200px'></div><div id='rest' style='margin:0;flex:1 1 0px'></div></div><div style='display:flex;width:400px;flex-grow:10'>word<span id='anonymousnext' style='width:20px'></span></div>")
	layout_close(c"growing item freezes at min content", 200.0, layout_box(page, c"min").width)
	layout_close(c"growth redistributes after minimum freeze", 100.0, layout_box(page, c"rest").width)
	asserts(c"anonymous flex factors do not inherit container grow", layout_box(page, c"anonymousnext").x < 150.0)
	win_page_free(page)

void test_flex_redistribution():
	win_page* large = layout_page(c"<div style='display:flex;width:300px'><div id='large' style='margin:0;flex:2e38 1 0px'></div><div id='small' style='margin:0;flex:1e38 1 0px'></div></div>")
	layout_close(c"large finite growth factors preserve their ratio", 200.0, layout_box(large, c"large").width)
	layout_close(c"large factor sums do not overflow allocation", 100.0, layout_box(large, c"small").width)
	win_page_free(large)
	win_page* page = layout_page(c"<div style='display:flex;width:400px'><div id='a' style='margin:0;flex:0 1 100px'><input style='width:100px'></div><div id='b' style='margin:0;flex:0 2 200px'></div><div id='c' style='margin:0;flex:0 1 300px'></div></div>")
	layout_close(c"first item freezes at intrinsic minimum", 100.0, layout_box(page, c"a").width)
	layout_close(c"redistribution uses original scaled shrink weight", 200.0 - 200.0 * 4.0 / 7.0, layout_box(page, c"b").width)
	layout_close(c"remaining shrink uses original third base", 300.0 - 200.0 * 3.0 / 7.0, layout_box(page, c"c").width)
	win_page_free(page)
	page = layout_page(c"<div style='display:flex;width:300px'><div id='min' style='margin:0;flex:1'><input style='width:120px'></div><div id='max' style='margin:0;flex:1;max-width:20px'></div><div id='rest' style='margin:0;flex:1'></div></div><div style='display:flex;width:100px'><div id='border' style='margin:0;padding:10px;box-sizing:border-box;flex:1 1 0px'></div><div style='margin:0;padding:10px;box-sizing:border-box;flex:1 1 0px'></div></div>")
	layout_close(c"negative total violation freezes max but not min", 140.0, layout_box(page, c"min").width)
	layout_close(c"max violation remains frozen", 20.0, layout_box(page, c"max").width)
	layout_close(c"remaining growth redistributes equally", 140.0, layout_box(page, c"rest").width)
	layout_close(c"negative inner border box bases survive until flexing", 50.0, layout_box(page, c"border").width)
	win_page_free(page)

void test_flex_alignment():
	win_page* page = layout_page(c"<div id='row' style='display:flex;width:400px;gap:20px;justify-content:space-between;margin:0'><div id='a' style='width:50px;margin:0'></div><div id='b' style='width:50px;margin:0'></div></div><div id='center' style='display:flex;width:400px;justify-content:center;margin:0'><div id='c' style='width:100px;margin:0'></div></div><div id='auto' style='display:flex;width:400px;justify-content:center;margin:0'><div id='d' style='width:100px;margin:0;margin-left:auto'></div></div><div id='even' style='display:flex;width:400px;justify-content:space-evenly;margin:0'><div id='e' style='width:100px;margin:0'></div><div id='f' style='width:100px;margin:0'></div></div>")
	layout_close(c"space between accounts for existing gap", layout_box(page, c"row").x + 350.0, layout_box(page, c"b").x)
	layout_close(c"center offsets row items", layout_box(page, c"center").x + 150.0, layout_box(page, c"c").x)
	layout_close(c"auto margin consumes space before justify content", layout_box(page, c"auto").x + 300.0, layout_box(page, c"d").x)
	layout_close(c"space evenly leading space", layout_box(page, c"even").x + 200.0 / 3.0, layout_box(page, c"e").x)
	layout_close(c"space evenly internal space", layout_box(page, c"e").x + 100.0 + 200.0 / 3.0, layout_box(page, c"f").x)
	win_page_free(page)
	page = layout_page(c"<div id='around' style='display:flex;width:400px;justify-content:space-around;margin:0'><div id='a' style='width:100px;margin:0'></div></div><div id='even' style='display:flex;width:400px;justify-content:space-evenly;margin:0'><div id='e' style='width:100px;margin:0'></div></div><div id='between' style='display:flex;width:400px;justify-content:space-between;margin:0'><div id='b' style='width:100px;margin:0'></div></div><div id='end' style='display:flex;width:400px;justify-content:flex-end;margin:0'><div id='f' style='width:100px;margin:0'></div></div>")
	layout_close(c"single space around item is centered", layout_box(page, c"around").x + 150.0, layout_box(page, c"a").x)
	layout_close(c"single space evenly item is centered", layout_box(page, c"even").x + 150.0, layout_box(page, c"e").x)
	layout_close(c"single space between item falls back to start", layout_box(page, c"between").x, layout_box(page, c"b").x)
	layout_close(c"flex end offsets item by free space", layout_box(page, c"end").x + 300.0, layout_box(page, c"f").x)
	win_page_free(page)
	page = layout_page(c"<div id='row' style='display:flex;width:100px;justify-content:center;margin:0'><div id='overflow' style='margin:0;width:200px;flex:none'></div></div><div id='safe' style='display:flex;width:100px;justify-content:space-around;margin:0'><div id='safechild' style='margin:0;width:200px;flex:none'></div></div><div id='safeeven' style='display:flex;width:100px;justify-content:space-evenly;margin:0'><div id='evenchild' style='margin:0;width:200px;flex:none'></div></div>")
	layout_close(c"center allows symmetric negative free space", layout_box(page, c"row").x - 50.0, layout_box(page, c"overflow").x)
	layout_close(c"distributed alignment falls back safely on overflow", layout_box(page, c"safe").x, layout_box(page, c"safechild").x)
	layout_close(c"space evenly falls back safely on overflow", layout_box(page, c"safeeven").x, layout_box(page, c"evenchild").x)
	win_page_free(page)

int main():
	test_declared_flex_sizes()
	test_flex_alignment()
	test_flex_redistribution()
	test_controls_and_percentage_constraints()
	test_box_sizing()
	test_image_intrinsic_sizes()
	test_anonymous_and_hidden_items()
	test_flex_shrink_freezing()
	test_fixed_height_overflow()
	println(c"Win intrinsic sizing, flex allocation, box sizing and overflow: OK")
	return 0
