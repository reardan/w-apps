import lib.assert
import win.document

win_run* css_find(win_page* page, char* word):
	for i in range(page.runs.length):
		if (strcmp(page.runs[i].text, word) == 0): return page.runs[i]
	return 0

void test_selectors():
	char* source = c"<main id='main'><p class='one two' data-kind='yes'>first</p><p class='two'>second</p><span>third</span></main>"
	win_page* page = win_page_parse(source, strlen(source))
	win_page_layout(page, 600)
	html_node* one = css_find(page, c"first").node
	html_node* two = css_find(page, c"second").node
	asserts(c"compound selector", win_selector_matches(one, c"main#main > p.one.two[data-kind='yes']:first-child"))
	asserts(c"descendant selector", win_selector_matches(one, c"#main .one"))
	asserts(c"negation selector", win_selector_matches(two, c"p:not(.one)"))
	asserts(c"is selector", win_selector_matches(two, c":is(.one,.two)"))
	asserts(c"nth-child selector", win_selector_matches(two, c"p:nth-child(even)"))
	asserts(c"adjacent sibling selector", win_selector_matches(two, c".one + .two"))
	asserts(c"sibling selector", win_selector_matches(two, c".one ~ p"))
	asserts(c"unsupported pseudo does not match", win_selector_matches(two, c"p:hover") == 0)
	asserts(c"attribute mismatch", win_selector_matches(one, c"[data-kind=no]") == 0)
	win_page_free(page)

void test_cascade():
	char* source = c"<style>p { color:blue; font-size:20px } .item { color:green } #one { color:red } #two {color:blue!important} .item {font-weight:bold} main {font-size:24px} @media screen and (max-width:400px) { .item {font-size:12px} } @media print { p {display:none} }</style><main><p id='one' class='item'>first <span>inherited</span></p><p id='two' class='item' style='color:red'>important</p><p id='three' style='color:#123456!important'>inline</p><div style='display:none'>hidden</div></main>"
	win_page* page = win_page_parse(source, strlen(source))
	win_page_layout(page, 600)
	asserts(c"id specificity", css_find(page, c"first").color.r > 0.7)
	asserts(c"inherited color", css_find(page, c"inherited").color.r > 0.7)
	asserts(c"important beats inline", css_find(page, c"important").color.b > 0.7)
	asserts(c"inline important color", css_find(page, c"inline").color.r < 0.1)
	asserts(c"display none", css_find(page, c"hidden") == 0)
	assert_equal(20, ui_font_strike_ppem(css_find(page, c"first").strike))
	win_page_layout(page, 300)
	assert_equal(12, ui_font_strike_ppem(css_find(page, c"first").strike))
	win_page_free(page)

void test_boxes():
	char* source = c"<style>#box {width:200px; margin:0 auto; padding:10px 20px; border:2px solid red; background:#abcdef; text-align:center} #box span {font-size:20px}</style><div id='box'><span>center</span></div><input name='q'><textarea></textarea>"
	win_page* page = win_page_parse(source, strlen(source))
	win_page_layout(page, 600)
	win_run* run = css_find(page, c"center")
	win_box* box = win_page_node_box(page, run.node.parent)
	asserts(c"box exists", box != 0)
	asserts(c"content box width includes padding border", box.width == 244.0)
	asserts(c"auto margin centers", box.x == 178.0)
	asserts(c"padding and border top", run.y >= box.y + 12.0)
	asserts(c"text alignment", run.x > box.x + 22.0)
	asserts(c"background", box.color.b > 0.9)
	assert_equal(2, box.border)
	asserts(c"border color", box.border_color.r > 0.7)
	int controls = 0
	for i in range(page.boxes.length):
		if (win_tag(page.boxes[i].node, c"input") || win_tag(page.boxes[i].node, c"textarea")):
			asserts(c"control geometry", page.boxes[i].width == 220.0 && page.boxes[i].height >= 34.0)
			controls = controls + 1
	assert_equal(2, controls)
	win_page_free(page)

void test_external_order():
	char* source = c"<link rel='stylesheet' href='first.css'><style>p {color:green}</style><link rel='stylesheet' href='last.css'><p>word</p>"
	win_page* page = win_page_parse(source, strlen(source))
	assert_equal(3, page.stylesheets.length)
	char* last = c"p {color:blue}"
	char* first = c"p {color:red}"
	win_page_add_stylesheet_for_node(page, page.stylesheets[2].node, last, strlen(last))
	win_page_add_stylesheet_for_node(page, page.stylesheets[0].node, first, strlen(first))
	win_page_layout(page, 600)
	asserts(c"source order independent of load completion", css_find(page, c"word").color.b > 0.7)
	win_page_free(page)

void test_columns():
	char* source = c"<style>.flex {display:flex;gap:20px} .grid {display:grid;grid-template-columns:repeat(2,1fr);gap:10px} p {margin:0}</style><div class='flex'><p>left</p><p>right</p></div><div class='grid'><p>one</p><p>two</p><p>three</p></div>"
	win_page* page = win_page_parse(source, strlen(source))
	win_page_layout(page, 600)
	asserts(c"flex equal columns", css_find(page, c"left").y == css_find(page, c"right").y && css_find(page, c"right").x > css_find(page, c"left").x + 200.0)
	asserts(c"grid first row", css_find(page, c"one").y == css_find(page, c"two").y)
	asserts(c"grid second row", css_find(page, c"three").y > css_find(page, c"one").y && css_find(page, c"three").x == css_find(page, c"one").x)
	win_page_free(page)

void test_invalid_and_colors():
	char* source = c"<style>p {font-size:20px} #x {font-size:invalid} p {font-size:24px;color:rgba(255,0,0,0.5)} #x {margin:10px invalid}</style><p id='x'>rgb</p>"
	win_page* page = win_page_parse(source, strlen(source))
	win_page_layout(page, 600)
	win_run* run = css_find(page, c"rgb")
	assert_equal(24, ui_font_strike_ppem(run.strike))
	asserts(c"rgba color", run.color.r == 1.0 && run.color.g == 0.0 && run.color.a == 0.5)
	win_page_free(page)

void test_visibility_and_leading():
	char* source = c"<style>p {margin:0;line-height:3} .hidden {visibility:hidden} .hidden span {visibility:visible}</style><p class='hidden'>invisible <span>visible</span></p><p>after</p>"
	win_page* page = win_page_parse(source, strlen(source))
	win_page_layout(page, 600)
	win_run* hidden = css_find(page, c"invisible")
	win_run* visible = css_find(page, c"visible")
	win_run* after = css_find(page, c"after")
	asserts(c"visibility retains geometry", hidden != 0 && hidden.hidden && visible.hidden == 0 && visible.x > hidden.x)
	asserts(c"visibility box paint", win_page_node_box(page, hidden.node).hidden)
	asserts(c"unitless inherited line height", after.y - hidden.y >= 54.0)
	win_page_free(page)

void test_selector_recovery_cascade():
	char* source = c"<style>p{color:blue} p,:unknown{color:red!important} #one{color:blue} :is(.pick,#absent:unknown){color:red} :is(.pick,#absent){color:lime} #two{color:blue} :nth-child(2 of .pick,#absent){color:red} #three{color:blue} :where(.pick,#absent){color:red} :nth-child(3 of .pick){border:2px solid hsl(none 100% 50%)} #three{border:9px solid rgb(255,,0,0)!important}</style><main><p id='one' class='pick'>first</p><span></span><p id='two' class='pick'>second</p><p id='three' class='pick'>third</p><p>strict</p></main>"
	win_page* page = win_page_parse(source, strlen(source))
	win_page_layout(page, 600)
	asserts(c"valid unmatched ID branch determines is specificity", css_find(page, c"first").color.g == 1.0)
	asserts(c"nth filter adds maximum specificity", css_find(page, c"second").color.r == 1.0)
	asserts(c"where adds no specificity", css_find(page, c"third").color.b == 1.0)
	asserts(c"invalid ordinary list discards entire rule", css_find(page, c"strict").color.b == 1.0)
	win_box* box = win_page_node_box(page, css_find(page, c"third").node)
	asserts(c"functional border and invalid important shorthand fallback", box != 0 && box.border == 2 && box.border_color.r == 1.0 && box.border_color.g == 0.0)
	win_page_free(page)
	char* invalid = c"<style>#one{color:blue} :is(.pick,#absent:unknown){color:red} #one,{color:red!important}</style><p id='one' class='pick'>invalid</p>"
	page = win_page_parse(invalid, strlen(invalid))
	win_page_layout(page, 600)
	asserts(c"invalid branches have no specificity or cascade effect", css_find(page, c"invalid").color.b == 1.0)
	win_page_free(page)

int main():
	test_selectors()
	test_cascade()
	test_boxes()
	test_external_order()
	test_columns()
	test_invalid_and_colors()
	test_visibility_and_leading()
	test_selector_recovery_cascade()
	println(c"Win CSS selectors, cascade, media, boxes and stylesheet ordering: OK")
	return 0
