# Native adaptations of CSS Variables 1 sections 2.1, 2.3, 3 and 3.2.
# https://www.w3.org/TR/css-variables-1/ (16 June 2022 snapshot)
import lib.assert
import win.document
import win.cssom

html_node* custom_node(win_page* page, char* id):
	html_node* node = page.html.allocations
	while (node != 0):
		if (node.kind == HTML_START && strcmp(win_attr(node, c"id"), id) == 0): return node
		node = node.allocation_next
	return 0

win_style custom_style(win_page* page, char* id):
	return win_node_style(page, custom_node(page, id), win_default_style())

void test_custom_cascade():
	char* source = c"<style>:root{--Size:40px;--size:20px;--tone:red;--alias:var(--Size)} #a{--size:30px!important} .item{width:var(--size);height:var(--Size);color:var(--tone);padding:var(--pad,2px 4px)} #child{--Size:90px;width:var(--alias);height:var(--Size)} </style><div id='a' class='item' style='--size:70px;--tone:blue'><div id='child'></div></div><div id='b' class='item'></div>"
	win_page* page = win_page_parse(source, strlen(source))
	win_style a = custom_style(page, c"a")
	asserts(c"custom names are case sensitive and obey importance", a.width == 30.0 && a.height == 40.0)
	asserts(c"inline custom values and shorthand fallback", a.color.b == 1.0 && a.padding_top == 2.0 && a.padding_left == 4.0)
	win_style b = custom_style(page, c"b")
	asserts(c"sibling does not inherit preceding sibling values", b.width == 20.0 && b.color.r == 1.0)
	win_style child = custom_style(page, c"child")
	asserts(c"parent computes aliases before child inheritance", child.width == 40.0 && child.height == 90.0)
	win_page_free(page)

void test_custom_cycles():
	char* source = c"<style>#a{--x:var(--y,10px);--y:var(--x,20px);width:var(--x,31px);height:var(--y,32px)} #b{--valid:9px;--x:var(--valid,var(--y));--y:var(--x);width:var(--x,33px)} #c{--self:var(--self,1px);--ok:var(--self,34px);width:var(--ok);height:var(--absent,var(--other,35px))}</style><div id='a'></div><div id='b'></div><div id='c'></div>"
	win_page* page = win_page_parse(source, strlen(source))
	win_style a = custom_style(page, c"a")
	asserts(c"all cycle members invalid despite internal fallbacks", a.width == 31.0 && a.height == 32.0)
	asserts(c"unused fallback contributes cycle dependency", custom_style(page, c"b").width == 33.0)
	win_style c = custom_style(page, c"c")
	asserts(c"noncyclic dependent fallback and nested missing fallback", c.width == 34.0 && c.height == 35.0)
	win_page_free(page)

void test_custom_invalid():
	char* source = c"<style>:root{--n:12px;--empty:} #a{width:25px;width:var(--missing);height:26px;height:var(--n)px;padding:7px;padding:var(--n) red;color:blue;color:var(--missing)} #b{--n:initial;width:var(--n,27px);height:var(--empty,29px)} #c{--n:inherit;width:var(--n);height:var(--missing,)} #d{width:38px;width:var(n,9px);height:39px;height:var(--n extra)} #e{--n:unset;width:var(--n);height:var(--missing,41px)}</style><div id='a'></div><div id='b'></div><div id='c'></div><div id='d'></div><div id='e'></div>"
	win_page* page = win_page_parse(source, strlen(source))
	win_style a = custom_style(page, c"a")
	asserts(c"invalid computed values do not expose earlier declarations", a.width == -1.0 && a.height == -1.0 && a.padding_top == 0.0)
	asserts(c"invalid computed inherited value is unset", a.color.r == 0.0 && a.color.b == 0.0)
	win_style b = custom_style(page, c"b")
	asserts(c"initial is invalid, empty value suppresses fallback", b.width == 27.0 && b.height == -1.0)
	win_style c = custom_style(page, c"c")
	asserts(c"inherit and empty fallback", c.width == 12.0 && c.height == -1.0)
	win_style d = custom_style(page, c"d")
	asserts(c"malformed var is rejected before cascade", d.width == 38.0 && d.height == 39.0)
	win_style e = custom_style(page, c"e")
	asserts(c"custom unset inherits", e.width == 12.0 && e.height == 41.0)
	win_page_free(page)

void test_custom_cssom():
	char* source = c"--Size:20px!important;--size:30px;--Size:40px;width:var(--Size)"
	char* value = win_cssom_get(source, c"--Size", 0)
	asserts(c"CSSOM custom priority winner", strcmp(value, c"20px") == 0)
	free(value)
	value = win_cssom_get(source, c"--Size", 1)
	asserts(c"CSSOM custom priority", strcmp(value, c"important") == 0)
	free(value)
	char* edited = win_cssom_edit(source, c"--Size", c"50px", c"")
	asserts(c"CSSOM custom mutation accepted", edited != 0)
	value = win_cssom_get(edited, c"--Size", 0)
	asserts(c"CSSOM mutation replaces important custom declaration", strcmp(value, c"50px") == 0)
	free(value)
	value = win_cssom_get(edited, c"--size", 0)
	asserts(c"CSSOM custom names preserve case", strcmp(value, c"30px") == 0)
	free(value)
	char* removed = win_cssom_edit(edited, c"--Size", c"", c"")
	value = win_cssom_get(removed, c"--Size", 0)
	asserts(c"CSSOM custom removal", strcmp(value, c"") == 0)
	free(value)
	value = win_cssom_get(removed, c"width", 0)
	asserts(c"CSSOM retains unresolved property value", strcmp(value, c"var(--Size)") == 0)
	free(value)
	free(removed)
	free(edited)
	value = win_cssom_get(c"flex:var(--f)", c"flex", 0)
	asserts(c"pending flex shorthand serializes once", strcmp(value, c"var(--f)") == 0)
	free(value)
	edited = win_cssom_edit(c"--m:2px 4px;margin:var(--m)", c"margin-left", c"9px", c"")
	asserts(c"pending shorthand survives a component override", strcmp(edited, c"--m: 2px 4px; margin: var(--m); margin-left: 9px;") == 0)
	free(edited)


float32 custom_box_width(win_page* page, char* id):
	html_node* node = custom_node(page, id)
	for i in range(page.boxes.length):
		if (page.boxes[i].node == node): return page.boxes[i].width
	return -1.0

void test_custom_layout_resize():
	char* source = c"<style>:root{--w:40px} @media(min-width:600px){:root{--w:80px}} div{margin:0;padding:0} #outer{width:var(--w);height:40px;background:green} #inner{width:var(--w);height:20px;background:red}</style><div id='outer'><div id='inner'></div></div>"
	win_page* page = win_page_parse(source, strlen(source))
	win_page_layout(page, 500)
	asserts(c"custom dimensions reach nested layout", custom_box_width(page, c"outer") == 40.0 && custom_box_width(page, c"inner") == 40.0)
	win_page_layout(page, 700)
	asserts(c"media resize recomputes custom dependencies", custom_box_width(page, c"outer") == 80.0 && custom_box_width(page, c"inner") == 80.0)
	win_page_free(page)

int main():
	test_custom_cascade()
	test_custom_cycles()
	test_custom_invalid()
	test_custom_cssom()
	test_custom_layout_resize()
	print(c"CSS custom properties: OK\n")
	return 0
