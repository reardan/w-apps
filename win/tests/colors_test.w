import lib.assert
import win.style

win_style colors_style(char* declarations):
	css_document* css = css_parse_declarations_n(declarations, strlen(declarations), 0)
	win_style style = win_default_style()
	style.color = ui_color_new(0.0, 0.0, 1.0, 1.0)
	win_style inherited = style
	int[28] winners
	for i in range(28): winners[i] = 0
	for i in range(css.nodes.length):
		win_css_declaration(css, css.nodes[i], i + 1, &winners[0], &style, inherited)
	css_document_free(css)
	return style

void colors_expect(char* declarations, float32 r, float32 g, float32 b, float32 a):
	ui_color color = colors_style(declarations).color
	asserts(declarations, fabs(color.r - r) < 0.0001 && fabs(color.g - g) < 0.0001 && fabs(color.b - b) < 0.0001 && fabs(color.a - a) < 0.0001)

void colors_invalid(char* declarations):
	colors_expect(declarations, 0.0, 0.0, 1.0, 1.0)

void test_rgb_colors():
	colors_expect(c"color:rgb(255, 0, 128)", 1.0, 0.0, 128.0 / 255.0, 1.0)
	colors_expect(c"color:rgba(100%, 0%, 50%, 25%)", 1.0, 0.0, 0.5, 0.25)
	colors_expect(c"color:rgb(255 0 50% / .5)", 1.0, 0.0, 0.5, 0.5)
	colors_expect(c"color:RGBA(255 0 0)", 1.0, 0.0, 0.0, 1.0)
	colors_expect(c"color:rgb(255,0,0,.25)", 1.0, 0.0, 0.0, 0.25)
	colors_expect(c"color:rgba(255,0,0)", 1.0, 0.0, 0.0, 1.0)
	colors_expect(c"color:rgb(+2.55e2 0 0 / 5e1%)", 1.0, 0.0, 0.0, 0.5)
	colors_expect(c"color:rgb(300 -5 0 / 150%)", 1.0, 0.0, 0.0, 1.0)
	colors_expect(c"color:rgb(1e999 -1e999 0 / -1)", 1.0, 0.0, 0.0, 0.0)
	colors_expect(c"color:rgb(255 /* channel */ 0 0 / 50%) /* end */", 1.0, 0.0, 0.0, 0.5)
	colors_expect(c"color:rgb(255/**/0/**/0)", 1.0, 0.0, 0.0, 1.0)
	colors_expect(c"color:rgb(255+0+0)", 1.0, 0.0, 0.0, 1.0)

void test_hsl_colors():
	colors_expect(c"color:hsl(0,100%,50%)", 1.0, 0.0, 0.0, 1.0)
	colors_expect(c"color:hsla(120,100%,50%,.5)", 0.0, 1.0, 0.0, 0.5)
	colors_expect(c"color:hsl(240deg 100% 50% / 25%)", 0.0, 0.0, 1.0, 0.25)
	colors_expect(c"color:hsl(.5turn 100 50)", 0.0, 1.0, 1.0, 1.0)
	colors_expect(c"color:hsl(200grad 100% 50)", 0.0, 1.0, 1.0, 1.0)
	colors_expect(c"color:HSL(3.141592653589793RAD 100% 50%)", 0.0, 1.0, 1.0, 1.0)
	colors_expect(c"color:hsl(-120 100% 50%)", 0.0, 0.0, 1.0, 1.0)
	colors_expect(c"color:hsla(480 100% 50%)", 0.0, 1.0, 0.0, 1.0)
	colors_expect(c"color:hsl(150 50% 40%)", 0.2, 0.6, 0.4, 1.0)
	colors_expect(c"color:hsl(120 100% 75%)", 0.5, 1.0, 0.5, 1.0)
	colors_expect(c"color:hsl(120 0% 25%)", 0.25, 0.25, 0.25, 1.0)
	colors_expect(c"color:hsl(120 -20% 50%)", 0.5, 0.5, 0.5, 1.0)
	colors_expect(c"color:hsl(0 200% 50% / 2)", 1.0, 0.0, 0.0, 1.0)
	colors_expect(c"color:hsl(0 100% -20%)", 0.0, 0.0, 0.0, 1.0)
	colors_expect(c"color:hsl(0 100% 200%)", 1.0, 1.0, 1.0, 1.0)
	colors_expect(c"color:hsl(1.2e2deg 1e2% 5e1%)", 0.0, 1.0, 0.0, 1.0)
	colors_expect(c"color:hsl(120\\64 eg 100% 50%)", 0.0, 1.0, 0.0, 1.0)
	colors_expect(c"color:hsl(1e30turn 100% 50%)", 1.0, 0.0, 0.0, 1.0)
	colors_expect(c"color:hsl(-1e999deg 100% 50%)", 1.0, 0.0, 0.0, 1.0)

void test_invalid_colors():
	colors_invalid(c"color:rgb(255,,0,0)")
	colors_invalid(c"color:rgb(255,0,0,)")
	colors_invalid(c"color:rgb(255 0 0 /)")
	colors_invalid(c"color:rgb(255,0,0 / .5)")
	colors_invalid(c"color:rgb(255 0 0,.5)")
	colors_invalid(c"color:rgb(255 0 0 .5)")
	colors_invalid(c"color:rgb(255,0 0)")
	colors_invalid(c"color:rgb(255/0/0)")
	colors_invalid(c"color:rgb(255,0%,0)")
	colors_invalid(c"color:rgb(255 0)")
	colors_invalid(c"color:rgb(255 0 0 / .5 / .5)")
	colors_invalid(c"color:rgb(255 0 0 / .5 0)")
	colors_invalid(c"color:rgb(255 0 0) junk")
	colors_invalid(c"color:rgb (255,0,0)")
	colors_invalid(c"color:'rgb'(255,0,0)")
	colors_invalid(c"color:rgb(255 0 0px)")
	colors_invalid(c"color:rgb(255 0 0")
	colors_invalid(c"color:hsl(0%,100%,50%)")
	colors_invalid(c"color:hsl(0,100,50)")
	colors_invalid(c"color:hsl(0px 100% 50%)")
	colors_invalid(c"color:hsl(1\\65 2turn 100% 50%)")
	colors_invalid(c"color:hsl(0 100deg 50%)")
	colors_invalid(c"color:hsl(0 100% 50% / 1px)")
	colors_invalid(c"color:hsl(none 100% 50%)")
	colors_invalid(c"color:rgb(calc(255) 0 0)")
	colors_invalid(c"color:'red'")
	colors_invalid(c"color:fff")
	colors_invalid(c"color:123")
	colors_invalid(c"color:#red")
	colors_invalid(c"color:#blue")
	colors_invalid(c"color:#12")
	colors_invalid(c"color:#12345")
	colors_invalid(c"color:blue; color:rgb(255,,0,0)!important")

void test_existing_colors_and_properties():
	colors_expect(c"color:#f008", 1.0, 0.0, 0.0, 136.0 / 255.0)
	colors_expect(c"color:#ff000080", 1.0, 0.0, 0.0, 128.0 / 255.0)
	colors_expect(c"color:#f00", 1.0, 0.0, 0.0, 1.0)
	colors_expect(c"color:#ff0000", 1.0, 0.0, 0.0, 1.0)
	colors_expect(c"color:ReD", 1.0, 0.0, 0.0, 1.0)
	colors_expect(c"color:transparent", 0.0, 0.0, 0.0, 0.0)
	win_style style = colors_style(c"background-color:hsl(120 100% 50% / .25); border-color:rgb(255 0 0 / .5)")
	asserts(c"background and border functions", style.background.g == 1.0 && style.background.a == 0.25 && style.border_color.r == 1.0 && style.border_color.a == 0.5)
	style = colors_style(c"background:rgb(255 0 0);background:hsl(0,100,50);border-color:blue;border-color:rgb(255,0 0)")
	asserts(c"invalid functions preserve background and border", style.background.r == 1.0 && style.border_color.b == 1.0)

int main():
	test_rgb_colors()
	test_hsl_colors()
	test_invalid_colors()
	test_existing_colors_and_properties()
	println(c"Win RGB/HSL colors, syntax validation and cascade fallback: OK")
	return 0
