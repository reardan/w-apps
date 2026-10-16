# Native geometry adaptations of CSS Flexbox 1 sections 4.5, 9.2 and 9.7.
import lib.assert
import win.document

html_node* column_node(win_page* page, char* id):
	html_node* node = page.html.allocations
	while (node != 0):
		if (node.kind == HTML_START && strcmp(win_attr(node, c"id"), id) == 0): return node
		node = node.allocation_next
	return 0

win_box* column_box(win_page* page, char* id):
	win_box* box = win_page_node_box(page, column_node(page, id))
	asserts(c"column fixture box exists", box != 0)
	return box

void column_close(char* message, float32 expected, float32 actual):
	asserts(message, actual > expected - 0.01 && actual < expected + 0.01)

win_page* column_page(char* content):
	string_builder* source = string_from(c"<style>div{margin:0;padding:0}.column{display:flex;flex-direction:column;width:200px}</style>")
	string_append(source, content)
	win_page* page = win_page_parse(source.data, source.length)
	string_free(source)
	win_page_layout(page, 800)
	return page

void test_column_factors():
	win_page* page = column_page(c"<div class='column' style='height:300px;gap:10px'><div id='a' style='flex:1 1 0px'></div><div id='b' style='flex:3 1 0px'></div></div><div class='column' style='height:120px'><div id='c' style='flex:0 1 100px'></div><div id='d' style='flex:0 1 200px'></div></div><div class='column' style='height:200px'><div id='fraction' style='flex:.25 0 0px'></div></div>")
	column_close(c"column growth accounts for gap", 72.5, column_box(page, c"a").height)
	column_close(c"column grow factors distribute remaining height", 217.5, column_box(page, c"b").height)
	column_close(c"column next item uses flexed height plus gap", column_box(page, c"a").y + 82.5, column_box(page, c"b").y)
	column_close(c"column shrink uses original scaled basis", 40.0, column_box(page, c"c").height)
	column_close(c"column shrink preserves basis ratio", 80.0, column_box(page, c"d").height)
	column_close(c"column fractional grow leaves unused height", 50.0, column_box(page, c"fraction").height)
	win_page_free(page)

void test_column_bases():
	win_page* page = column_page(c"<div class='column' style='height:300px'><div id='auto' style='height:80px;flex:0 0 auto'><div style='height:30px'></div></div><div id='content' style='height:80px;flex:0 0 content'><div style='height:30px'></div></div><div id='percent' style='flex:0 0 25%'></div></div><div id='indefinite' class='column'><div id='percentauto' style='height:80px;flex:1 1 25%'><div style='height:30px'></div></div><div id='lengthauto' style='flex:1 1 60px'></div></div><div class='column' style='height:200px'><div id='border' style='flex:0 0 80px;padding:10px;border:2px solid;box-sizing:border-box'></div><div id='boxcontent' style='flex:0 0 80px;padding:10px;border:2px solid'></div></div>")
	column_close(c"auto column basis uses specified height", 80.0, column_box(page, c"auto").height)
	column_close(c"content column basis ignores specified height", 30.0, column_box(page, c"content").height)
	column_close(c"percentage column basis uses definite content height", 75.0, column_box(page, c"percent").height)
	column_close(c"indefinite percentage basis becomes content", 30.0, column_box(page, c"percentauto").height)
	column_close(c"indefinite column honors length basis without growing", 60.0, column_box(page, c"lengthauto").height)
	column_close(c"indefinite column includes hypothetical child heights", 90.0, column_box(page, c"indefinite").height)
	column_close(c"column border box basis", 80.0, column_box(page, c"border").height)
	column_close(c"column content box basis", 104.0, column_box(page, c"boxcontent").height)
	win_page_free(page)

void test_column_minimum_and_nested_resize():
	win_page* page = column_page(c"<style>#outer{height:300px}@media(max-width:500px){#outer{height:180px}}</style><div class='column' style='height:100px'><div id='minimum' style='flex:1 1 0px'><div style='height:70px'></div></div><div id='remaining' style='flex:1 1 0px'></div></div><div id='outer' class='column'><div id='nested' class='column' style='flex:1 1 0px'><div id='top' style='flex:1 1 0px'></div><div id='bottom' style='flex:2 1 0px'><a id='target' href='#hit'>link</a></div></div></div>")
	column_close(c"column automatic minimum freezes at content height", 70.0, column_box(page, c"minimum").height)
	column_close(c"column redistributes growth after minimum freeze", 30.0, column_box(page, c"remaining").height)
	column_close(c"outer flex allocation reaches nested container", 300.0, column_box(page, c"nested").height)
	column_close(c"nested child flexes against allocated parent height", 100.0, column_box(page, c"top").height)
	column_close(c"nested sibling uses allocated height", 200.0, column_box(page, c"bottom").height)
	win_page_layout(page, 400)
	column_close(c"nested allocation recomputed after resize", 180.0, column_box(page, c"nested").height)
	column_close(c"nested growth recomputed", 60.0, column_box(page, c"top").height)
	int hits = 0
	for i in range(page.runs.length):
		win_run* run = page.runs[i]
		if (run.href[0] != 0):
			asserts(c"nested links retain painted hit geometry", strcmp(win_page_hit(page, run.x + 1.0, run.y + 1.0), c"#hit") == 0)
			hits = hits + 1
	asserts(c"measurement geometry is not emitted twice", hits == 1)
	column_close(c"anchor follows flexed sibling", column_box(page, c"bottom").y, win_page_anchor(page, c"target"))
	win_page_free(page)

int main():
	test_column_factors()
	test_column_bases()
	test_column_minimum_and_nested_resize()
	print(c"Column flex basis, grow, shrink and nested geometry: OK\n")
	return 0
