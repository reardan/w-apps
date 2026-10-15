# Native adaptations of CSS Cascade 5 value processing, Values 4 dimensions,
# Selectors 4 specificity/state, and CSS Syntax 3 recovery algorithms.
import lib.assert
import win.document

win_style foundation_style(char* source, win_style inherited, int root):
	css_document* css = css_parse_declarations_n(source, strlen(source), 0)
	win_css_specified[36] winners
	for i in range(WIN_CSS_PROPERTY_COUNT): winners[i].present = 0
	for i in range(css.nodes.length):
		css_node* d = css.nodes[i]
		win_css_collect(css, d, win_cascade_author(d.important, 0, win_specificity_zero(), i), &winners[0])
	win_style style = win_default_style()
	style.root_size = inherited.root_size
	win_css_compute(&winners[0], &style, inherited, root)
	css_document_free(css)
	return style

void test_deferred_lengths():
	win_style parent = win_default_style()
	win_style a = foundation_style(c"width:2em;padding:0.5em;border:.25em solid;gap:1em;line-height:1.5em;font-size:24px", parent, 0)
	win_style b = foundation_style(c"font-size:24px;line-height:1.5em;gap:1em;border:.25em solid;padding:0.5em;width:2em", parent, 0)
	asserts(c"declaration permutation uses winning font size", a.width == 48.0 && a.width == b.width && a.padding_top == 12.0 && a.padding_top == b.padding_top && a.border == 6.0 && a.border == b.border && a.gap == 24.0 && a.line_height == 36.0)
	a = foundation_style(c"font-size:1.5em;width:1e2PX;height:.5em;max-width:12.5%;padding:1.25px;line-height:1e0", parent, 0)
	asserts(c"fractions exponents case and percentages", a.size == 27 && a.width == 100.0 && a.height == 13.5 && a.max_width == 12.5 && a.max_width_percent && a.padding_top == 1.25 && a.line_height_factor == 1.0)
	a = foundation_style(c"font-size:1.25px;width:2em;margin-left:-2px;margin-right:auto", parent, 0)
	asserts(c"fractional fonts remain computed lengths and auto is tagged", a.size == 1.25 && a.width == 2.5 && a.margin_left == -2.0 && a.margin_left_auto == 0 && a.margin_right_auto)
	a = foundation_style(c"width:9px;width:.5;width:5quuxpx;width:1\\65 2px;height:2px;height:'3px';font-weight:normal;font-weight:700px", parent, 0)
	asserts(c"invalid tokens do not erase earlier winners", a.width == 9.0 && a.height == 2.0 && a.bold == 0)
	a = foundation_style(c"grid-template-columns:repeat(3,1fr);grid-template-columns:garbage garbage;grid-template-columns:repeat(2 junk)", parent, 0)
	asserts(c"invalid grid grammar retains valid track count", a.columns == 3)
	a = foundation_style(c"margin:2px;padding:3px;padding:4px -1px;margin:inherit 1px", parent, 0)
	asserts(c"invalid shorthands are atomic", a.padding_top == 3.0 && a.padding_right == 3.0 && a.margin_top == 2.0)
	parent.root_size = 30
	a = foundation_style(c"width:2rem;font-size:1rem", parent, 0)
	asserts(c"rem uses computed document root", a.width == 60.0 && a.size == 30)
	parent = win_default_style()
	a = foundation_style(c"width:2rem;font-size:24px", parent, 1)
	asserts(c"root rem lengths use root computed font", a.width == 48.0 && a.root_size == 24)
	a = foundation_style(c"font-size:2rem;width:1rem", parent, 1)
	asserts(c"root rem font-size uses initial font", a.size == 36 && a.width == 36.0)
	a = foundation_style(c"color:rgb(255 0 0", parent, 0)
	asserts(c"EOF implicitly closes color function", a.color.r == 1.0 && a.color.g == 0.0)

void test_wide_keywords():
	win_style parent = win_default_style()
	parent.display = 3
	parent.width = 42.5
	parent.hidden = 1
	parent.margin_top = 7.0
	parent.padding_left = 8.0
	parent.border_color = ui_color_new(1.0, 0.0, 0.0, 1.0)
	parent.border_current_color = 1
	win_style s = foundation_style(c"font-style:italic;font-style:inherit;display:block;display:inherit;width:inherit;visibility:unset;margin:inherit;padding:inherit;border-color:inherit;color:blue", parent, 0)
	asserts(c"inherit restores normal font style and parent display", (s.flags & UI_TEXT_ITALIC) == 0 && s.display == 3)
	asserts(c"inherit works for every supported longhand and shorthand", s.width == 42.5 && s.hidden && s.margin_top == 7.0 && s.padding_left == 8.0)
	asserts(c"inherited border color stays parent computed color", s.border_color.r == 1.0 && s.border_color.b == 0.0)
	s = foundation_style(c"font-style:italic;font-style:initial;display:block;display:unset;width:inherit;width:initial;border:5px solid red;border:initial", parent, 0)
	asserts(c"initial and unset reset non-inherited values", (s.flags & UI_TEXT_ITALIC) == 0 && s.display == 2 && s.width == -1.0 && s.border == 0.0)

html_node* foundation_node(win_page* page, char* id):
	html_node* node = page.html.allocations
	while (node != 0):
		if (node.kind == HTML_START && strcmp(win_attr(node, c"id"), id) == 0): return node
		node = node.allocation_next
	return 0

void test_cascade_keys():
	string_builder* source = string_new()
	string_append(source, c"<style>#target{color:red} ")
	for i in range(101): string_append(source, c".x")
	string_append(source, c"{color:blue} .x{width:2em;font-size:24px} #target{font-size:30px} </style><p id='target' class='x'>text</p>")
	win_page* page = win_page_parse(source.data, source.length)
	win_style style = win_computed_style(page, foundation_node(page, c"target"), win_default_style(), win_default_style())
	asserts(c"101 classes cannot outrank one ID", style.color.r == 1.0 && style.color.b == 0.0)
	asserts(c"relative width sees font size from a different rule", style.width == 60.0)
	win_page_free(page)
	string_free(source)
	char* text = c"<style>#target{color:red!important;width:10px!important} #target{color:blue!important}</style><p id='target' style='color:green;width:20px!important'></p>"
	page = win_page_parse(text, strlen(text))
	style = win_computed_style(page, foundation_node(page, c"target"), win_default_style(), win_default_style())
	asserts(c"importance then inline then source order", style.color.b == 1.0 && style.width == 20.0)
	win_page_free(page)
	win_specificity id = win_specificity_zero()
	id.ids = 1
	win_specificity classes = win_specificity_zero()
	classes.classes = 100000
	asserts(c"tuple ordering has no numeric spill", win_specificity_compare(id, classes) > 0)

void test_selector_states_and_recovery():
	char* text = c"<style>p{color:blue}bad; p{color:red}</style><a id='123' href='' disabled checked></a><input id='check' type='checkbox' checked><input id='plain' checked><fieldset disabled><legend><input id='exempt'></legend><input id='disabled'></fieldset><select><option id='selected' selected></option></select><p id='target'>text</p>"
	win_page* page = win_page_parse(text, strlen(text))
	html_node* anchor = foundation_node(page, c"123")
	asserts(c"unrestricted hash cannot be ID selector", win_selector_matches(anchor, c"#123") == 0 && win_selector_matches(anchor, c"#\\31 23"))
	asserts(c"empty href still links; attributes do not make arbitrary controls", win_selector_matches(anchor, c":link") && win_selector_matches(anchor, c":disabled") == 0 && win_selector_matches(anchor, c":checked") == 0)
	asserts(c"checked is restricted to checkable controls and selected options", win_selector_matches(foundation_node(page, c"check"), c":checked") && win_selector_matches(foundation_node(page, c"plain"), c":checked") == 0 && win_selector_matches(foundation_node(page, c"selected"), c":checked"))
	asserts(c"fieldset disabled and first legend exemption", win_selector_matches(foundation_node(page, c"disabled"), c":disabled") && win_selector_matches(foundation_node(page, c"exempt"), c":disabled") == 0)
	win_style style = win_computed_style(page, foundation_node(page, c"target"), win_default_style(), win_default_style())
	asserts(c"qualified prelude retains invalid semicolon", style.color.b == 1.0 && style.color.r == 0.0)
	win_page_free(page)

void media_expect(char* query, int expected):
	string_builder* source = string_new()
	string_append(source, c"@media ")
	string_append(source, query)
	string_append(source, c"{p{color:red}}")
	css_document* css = css_parse_stylesheet_n(source.data, source.length, 0)
	asserts(query, css.nodes.length == 1 && win_css_media(css, css.nodes[0], 400) == expected)
	css_document_free(css)
	string_free(source)

void test_media_grammar():
	media_expect(c"screen and (min-width:1px)", 1)
	media_expect(c"only screen and (max-width:400PX)", 1)
	media_expect(c"(min-width:399.5px) and (max-width:4e2px)", 1)
	media_expect(c"screen screen and (min-width:1px garbage)", 0)
	media_expect(c"screen and (min-width:1px garbage)", 0)
	media_expect(c"screen (min-width:1px)", 0)
	media_expect(c"and (min-width:1px)", 0)
	media_expect(c"only (min-width:1px)", 0)
	media_expect(c"screen and", 0)
	media_expect(c"screen and (min-width:.5)", 0)
	media_expect(c"screen and (min-width:400.5px)", 0)

void test_flex_values():
	win_style parent = win_default_style()
	win_style s = foundation_style(c"flex:2", parent, 0)
	asserts(c"numeric shorthand supplies shrink and zero basis", s.flex_grow == 2.0 && s.flex_shrink == 1.0 && s.flex_basis == 0.0)
	s = foundation_style(c"flex:3 2 25%", parent, 0)
	asserts(c"three component flex preserves percent basis", s.flex_grow == 3.0 && s.flex_shrink == 2.0 && s.flex_basis == 25.0 && s.flex_basis_percent)
	s = foundation_style(c"flex:2em 3 4;font-size:20px", parent, 0)
	asserts(c"basis first and deferred font relative basis", s.flex_grow == 3.0 && s.flex_shrink == 4.0 && s.flex_basis == 40.0 && s.flex_basis_percent == 0)
	s = foundation_style(c"flex:2 0", parent, 0)
	asserts(c"unitless second zero is shrink", s.flex_grow == 2.0 && s.flex_shrink == 0.0 && s.flex_basis == 0.0)
	s = foundation_style(c"flex:none", parent, 0)
	asserts(c"none is zero zero auto", s.flex_grow == 0.0 && s.flex_shrink == 0.0 && s.flex_basis == -1.0)
	s = foundation_style(c"flex:auto", parent, 0)
	asserts(c"auto is one one auto", s.flex_grow == 1.0 && s.flex_shrink == 1.0 && s.flex_basis == -1.0)
	s = foundation_style(c"flex:content", parent, 0)
	asserts(c"content is explicit content basis", s.flex_grow == 1.0 && s.flex_shrink == 1.0 && s.flex_basis == -2.0)
	s = foundation_style(c"flex:2 3 40px;flex:1 -2 5px;flex:1 2px 3;flex:inherit 2;flex:1 2 3;flex:1 2 3px 4px;flex-grow:-1;flex-shrink:3px;flex-basis:-1px", parent, 0)
	asserts(c"invalid flex declarations preserve all earlier components", s.flex_grow == 2.0 && s.flex_shrink == 3.0 && s.flex_basis == 40.0)
	s = foundation_style(c"flex-grow:4!important;flex:2 3 50%;flex-basis:auto", parent, 0)
	asserts(c"shorthand components independently compete with longhands", s.flex_grow == 4.0 && s.flex_shrink == 3.0 && s.flex_basis == -1.0 && s.flex_basis_percent == 0)
	parent = s
	s = foundation_style(c"flex:inherit;justify-content:space-evenly;justify-content:garbage", parent, 0)
	asserts(c"flex inherit copies all components", s.flex_grow == 4.0 && s.flex_shrink == 3.0 && s.flex_basis == -1.0 && s.justify == 5)
	s = foundation_style(c"flex:2 3 40px;flex:unset", parent, 0)
	asserts(c"flex unset restores noninherited defaults", s.flex_grow == 0.0 && s.flex_shrink == 1.0 && s.flex_basis == -1.0)

void test_cross_alignment_values():
	win_style parent = win_default_style()
	win_style s = foundation_style(c"flex-wrap:wrap;align-items:center;align-self:flex-end;flex-wrap:wrap-reverse;align-items:baseline;align-self:garbage", parent, 0)
	asserts(c"unsupported alignment leaves earlier declarations intact", s.flex_wrap == 1 && s.align_items == 3 && s.align_self == 2)
	parent = s
	s = foundation_style(c"flex-wrap:inherit;align-items:inherit;align-self:inherit", parent, 0)
	asserts(c"explicit alignment inheritance", s.flex_wrap == 1 && s.align_items == 3 && s.align_self == 2)
	s = foundation_style(c"flex-wrap:unset;align-items:initial;align-self:auto", parent, 0)
	asserts(c"alignment defaults are not inherited", s.flex_wrap == 0 && s.align_items == 0 && s.align_self == -1)

int main():
	test_cross_alignment_values()
	test_flex_values()
	test_deferred_lengths()
	test_wide_keywords()
	test_cascade_keys()
	test_selector_states_and_recovery()
	test_media_grammar()
	println(c"Win CSS specified values, cascade tuples, units and recovery: OK")
	return 0
