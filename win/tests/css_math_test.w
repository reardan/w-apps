# Native adaptations of finite CSS Values 4 calc arithmetic and viewport units.
import lib.assert
import win.document
import win.cssom

win_style math_style(char* source):
	css_document* css = css_parse_declarations_n(source, strlen(source), 0)
	win_css_specified[36] winners
	for i in range(WIN_CSS_PROPERTY_COUNT): winners[i].present = 0
	for i in range(css.nodes.length):
		css_node* d = css.nodes[i]
		win_css_collect(css, d, win_cascade_author(d.important, 0, win_specificity_zero(), i), &winners[0])
	win_style style = win_default_style()
	style.viewport_width = 800.0
	style.viewport_height = 600.0
	win_css_compute(&winners[0], &style, win_default_style(), 0)
	css_document_free(css)
	return style

void math_close(char* message, float32 expected, float32 actual):
	asserts(message, actual > expected - 0.01 && actual < expected + 0.01)

void test_math_types_and_precedence():
	win_style style = math_style(c"font-size:20px;width:calc(2em + 5px);height:calc((2 + 3) * 4px);padding:calc(3px + 2px) calc(2 * 4px);border:calc(10px / 2) solid green;flex:calc(2 - 1) calc(2 / 2) calc(20px + 5px)")
	math_close(c"calc em uses final computed font size", 45.0, style.width)
	math_close(c"calc parentheses and multiplication", 20.0, style.height)
	math_close(c"calc components in padding shorthand", 5.0, style.padding_top)
	math_close(c"calc second padding component", 8.0, style.padding_left)
	math_close(c"calc border width", 5.0, style.border)
	math_close(c"calc flex shorthand basis", 25.0, style.flex_basis)
	style = math_style(c"width:calc(2px + 3px * 4);height:calc(2 * calc(3px + 5px));margin-left:calc(2px - 5px);padding-top:calc(2px - 5px);flex-grow:calc(1 / 4)")
	math_close(c"calc multiplication precedes addition", 14.0, style.width)
	math_close(c"nested calc", 16.0, style.height)
	math_close(c"negative margin calc retained", -3.0, style.margin_left)
	math_close(c"negative padding calc clamps after computation", 0.0, style.padding_top)
	math_close(c"numeric calc for grow factor", 0.25, style.flex_grow)
	style = math_style(c"width:10vw;height:10VH;padding:1vmin 1vmax;line-height:calc(100% + 2px);font-size:calc(100% + 2px)")
	math_close(c"viewport width unit", 80.0, style.width)
	math_close(c"case insensitive viewport height unit", 60.0, style.height)
	math_close(c"smaller viewport axis", 6.0, style.padding_top)
	math_close(c"larger viewport axis", 8.0, style.padding_left)
	math_close(c"font calc percent uses inherited size", 20.0, style.size)
	math_close(c"line-height calc percent uses own size", 22.0, style.line_height)

void test_invalid_math():
	char*[10] bad
	bad[0] = c"calc(2px + 1)"
	bad[1] = c"calc(2px * 3px)"
	bad[2] = c"calc(2px / 1px)"
	bad[3] = c"calc(2px / 0)"
	bad[4] = c"calc(2px+ 3px)"
	bad[5] = c"calc(2px +3px)"
	bad[6] = c"calc(2px/**/+/**/3px)"
	bad[7] = c"calc()"
	bad[8] = c"calc(1e30 * 1e30 * 1px)"
	bad[9] = c"calc(0)"
	for i in range(10):
		string_builder* source = string_from(c"width:17px;width:")
		string_append(source, bad[i])
		win_style style = math_style(source.data)
		math_close(c"invalid dimensional math preserves earlier cascade winner", 17.0, style.width)
		string_free(source)
	win_style style = math_style(c"width:calc(2px /**/ +/**/ 3px);height:calc(-4px);padding:9px;padding:calc(10% + 1px)")
	math_close(c"comments do not erase surrounding whitespace", 5.0, style.width)
	math_close(c"negative height clamps to zero", 0.0, style.height)
	math_close(c"unsupported percentage padding does not win", 9.0, style.padding_left)
	style = math_style(c"width:calc(1e38em - 1e38rem)")
	math_close(c"large relative terms cancel without NaN geometry", 0.0, style.width)

html_node* math_node(win_page* page, char* id):
	html_node* node = page.html.allocations
	while (node != 0):
		if (node.kind == HTML_START && strcmp(win_attr(node, c"id"), id) == 0): return node
		node = node.allocation_next
	return 0

win_box* math_box(win_page* page, char* id):
	win_box* box = win_page_node_box(page, math_node(page, id))
	asserts(c"math fixture box exists", box != 0)
	return box

void test_math_geometry_and_resize():
	char* source = c"<style>div{margin:0;padding:0}:root{--inset:10px}#outer{width:50vw;height:50vh;display:flex;flex-direction:column}#a{width:calc(100% - var(--inset));flex:0 0 calc(50% - 10px)}#b{width:calc(100px - 10%);flex:0 0 calc(50% + 10px)}#c{width:calc(10px - 100%);height:5px}#d{width:300px;max-width:calc(100% - 20px);height:5px}</style><div id='outer'><div id='a'></div><div id='b'></div></div><div style='width:200px'><div id='c'></div><div id='d'></div></div>"
	win_page* page = win_page_parse(source, strlen(source))
	win_page_set_viewport(page, 800, 600)
	win_page_layout(page, 800)
	math_close(c"vw outer width", 400.0, math_box(page, c"outer").width)
	math_close(c"vh outer height", 300.0, math_box(page, c"outer").height)
	math_close(c"mixed calc percentage resolves against containing block", 390.0, math_box(page, c"a").width)
	math_close(c"mixed column basis percentage", 140.0, math_box(page, c"a").height)
	math_close(c"negative percent coefficient is not auto", 60.0, math_box(page, c"b").width)
	math_close(c"positive offset column basis", 160.0, math_box(page, c"b").height)
	math_close(c"negative used width clamps to zero", 0.0, math_box(page, c"c").width)
	math_close(c"mixed calc maximum", 180.0, math_box(page, c"d").width)
	win_page_set_viewport(page, 800, 400)
	asserts(c"height-only viewport resize invalidates layout", page.width == 0)
	win_page_layout(page, 800)
	math_close(c"height-only resize recomputes vh", 200.0, math_box(page, c"outer").height)
	math_close(c"height-only resize recomputes nested calc basis", 90.0, math_box(page, c"a").height)
	win_page_set_viewport(page, 400, 800)
	win_page_layout(page, 400)
	math_close(c"width resize recomputes vw", 200.0, math_box(page, c"outer").width)
	math_close(c"nested calc percentage recomputed once", 190.0, math_box(page, c"a").width)
	math_close(c"height resize recomputes mixed flex basis", 190.0, math_box(page, c"a").height)
	win_page_free(page)

int main():
	test_math_types_and_precedence()
	test_invalid_math()
	test_math_geometry_and_resize()
	print(c"CSS calc typed arithmetic, viewport units and responsive geometry: OK\n")
	return 0
