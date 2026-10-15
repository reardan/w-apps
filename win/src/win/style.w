# Author CSS cascade and block-flow styling. Unsupported syntax never matches.
import libs.extras.html.html
import libs.extras.css.css
import graphics.ui.text
import lib.format
import lib.fmath
import win.selectors
import win.css_values

const int WIN_CSS_PROPERTY_COUNT = 36

struct win_style:
	float32 size
	float32 root_size
	float32 line_height
	float32 line_height_factor
	int bold
	int flags
	int hidden
	int pre
	int display
	int align
	float32 width
	int width_percent
	float32 height
	float32 max_width
	int max_width_percent
	float32 margin_top
	float32 margin_right
	float32 margin_bottom
	float32 margin_left
	int margin_left_auto
	int margin_right_auto
	float32 padding_top
	float32 padding_right
	float32 padding_bottom
	float32 padding_left
	float32 border
	float32 border_width
	int border_style
	int border_current_color
	float32 gap
	int flex_column
	int flex_wrap
	# Cross alignment: 0 stretch, 1 start, 2 end, 3 center; self -1 auto.
	int align_items
	int align_self
	int justify
	float32 flex_grow
	float32 flex_shrink
	# Basis: -1 auto, -2 content, otherwise length or percentage.
	float32 flex_basis
	int flex_basis_percent
	int columns
	int box_sizing
	ui_color background
	ui_color border_color
	ui_color color

win_style win_default_style():
	win_style s
	s.size = 18
	s.root_size = 18
	s.line_height = 0
	s.line_height_factor = 0.0
	s.bold = 0
	s.flags = 0
	s.hidden = 0
	s.pre = 0
	s.display = 2
	s.align = 0
	s.width = -1
	s.width_percent = 0
	s.height = -1
	s.max_width = -1
	s.max_width_percent = 0
	s.margin_top = 0
	s.margin_right = 0
	s.margin_bottom = 0
	s.margin_left = 0
	s.margin_left_auto = 0
	s.margin_right_auto = 0
	s.padding_top = 0
	s.padding_right = 0
	s.padding_bottom = 0
	s.padding_left = 0
	s.border = 0
	s.border_width = 3
	s.border_style = 0
	s.border_current_color = 1
	s.gap = 0
	s.flex_column = 0
	s.flex_wrap = 0
	s.align_items = 0
	s.align_self = -1
	s.justify = 0
	s.flex_grow = 0.0
	s.flex_shrink = 1.0
	s.flex_basis = -1.0
	s.flex_basis_percent = 0
	s.columns = 1
	s.box_sizing = 0
	s.background = ui_color_new(0.0, 0.0, 0.0, 0.0)
	s.border_color = ui_gray(0.0)
	s.color = ui_gray(0.0)
	return s

int win_hex(int c):
	if (c >= '0' && c <= '9'): return c - '0'
	if (c >= 'a' && c <= 'f'): return c - 'a' + 10
	if (c >= 'A' && c <= 'F'): return c - 'A' + 10
	return -1

ui_color win_color(char* value, ui_color fallback):
	if (value[0] == '#'): value = value + 1
	if (css_ascii_equal(value, c"transparent")): return ui_color_new(0.0, 0.0, 0.0, 0.0)
	if (css_ascii_equal(value, c"gray") || css_ascii_equal(value, c"grey")): return ui_gray(0.5)
	if (css_ascii_equal(value, c"yellow")): return ui_color_new(1.0, 1.0, 0.0, 1.0)
	if (css_ascii_equal(value, c"orange")): return ui_color_new(1.0, 0.647, 0.0, 1.0)
	if (css_ascii_equal(value, c"purple")): return ui_color_new(0.502, 0.0, 0.502, 1.0)
	if (css_ascii_equal(value, c"navy")): return ui_color_new(0.0, 0.0, 0.502, 1.0)
	if (css_ascii_equal(value, c"teal")): return ui_color_new(0.0, 0.502, 0.502, 1.0)
	if (css_ascii_equal(value, c"silver")): return ui_gray(0.753)
	if (css_ascii_equal(value, c"maroon")): return ui_color_new(0.502, 0.0, 0.0, 1.0)
	if (css_ascii_equal(value, c"olive")): return ui_color_new(0.502, 0.502, 0.0, 1.0)
	if (css_ascii_equal(value, c"lime")): return ui_color_new(0.0, 1.0, 0.0, 1.0)
	if (css_ascii_equal(value, c"aqua") || css_ascii_equal(value, c"cyan")): return ui_color_new(0.0, 1.0, 1.0, 1.0)
	if (css_ascii_equal(value, c"fuchsia") || css_ascii_equal(value, c"magenta")): return ui_color_new(1.0, 0.0, 1.0, 1.0)
	if (css_ascii_equal(value, c"red")): return ui_color_new(1.0, 0.0, 0.0, 1.0)
	if (css_ascii_equal(value, c"blue")): return ui_color_new(0.0, 0.0, 1.0, 1.0)
	if (css_ascii_equal(value, c"green")): return ui_color_new(0.0, 0.502, 0.0, 1.0)
	if (css_ascii_equal(value, c"black")): return ui_gray(0.0)
	if (css_ascii_equal(value, c"white")): return ui_gray(1.0)
	int n = strlen(value)
	if (n == 4 || n == 8):
		for i in range(n):
			if (win_hex(value[i]) < 0): return fallback
		int count = 3
		if (n == 8): count = 6
		char* rgb_value = substring(value, 0, count)
		ui_color result = win_color(rgb_value, fallback)
		free(rgb_value)
		int alpha = win_hex(value[count])
		if (alpha < 0): return fallback
		if (n == 4): alpha = alpha * 17
		else:
			int low = win_hex(value[count + 1])
			if (low < 0): return fallback
			alpha = alpha * 16 + low
		result.a = cast(float32, alpha) / 255.0
		return result
	if (n != 3 && n != 6): return fallback
	int rgb = 0
	for i in range(n):
		int digit = win_hex(value[i])
		if (digit < 0): return fallback
		if (n == 3): rgb = rgb * 256 + digit * 17
		else: rgb = rgb * 16 + digit
	return ui_color_new(cast(float32, (rgb >> 16) & 255) / 255.0, cast(float32, (rgb >> 8) & 255) / 255.0, cast(float32, rgb & 255) / 255.0, 1.0)


int win_css_property(char* name):
	if (css_ascii_equal(name, c"color")): return 0
	if (css_ascii_equal(name, c"font-size")): return 1
	if (css_ascii_equal(name, c"font-weight")): return 2
	if (css_ascii_equal(name, c"font-style")): return 3
	if (css_ascii_equal(name, c"text-decoration")): return 4
	if (css_ascii_equal(name, c"display")): return 5
	if (css_ascii_equal(name, c"white-space")): return 6
	if (css_ascii_equal(name, c"text-align")): return 7
	if (css_ascii_equal(name, c"background") || css_ascii_equal(name, c"background-color")): return 8
	if (css_ascii_equal(name, c"width")): return 9
	if (css_ascii_equal(name, c"height")): return 10
	if (css_ascii_equal(name, c"max-width")): return 11
	if (css_ascii_equal(name, c"margin-top")): return 12
	if (css_ascii_equal(name, c"margin-right")): return 13
	if (css_ascii_equal(name, c"margin-bottom")): return 14
	if (css_ascii_equal(name, c"margin-left")): return 15
	if (css_ascii_equal(name, c"padding-top")): return 16
	if (css_ascii_equal(name, c"padding-right")): return 17
	if (css_ascii_equal(name, c"padding-bottom")): return 18
	if (css_ascii_equal(name, c"padding-left")): return 19
	if (css_ascii_equal(name, c"border-width")): return 20
	if (css_ascii_equal(name, c"border-color")): return 21
	if (css_ascii_equal(name, c"box-sizing")): return 22
	if (css_ascii_equal(name, c"visibility")): return 23
	if (css_ascii_equal(name, c"gap") || css_ascii_equal(name, c"column-gap")): return 24
	if (css_ascii_equal(name, c"flex-wrap")): return 33
	if (css_ascii_equal(name, c"align-items")): return 34
	if (css_ascii_equal(name, c"align-self")): return 35
	if (css_ascii_equal(name, c"flex-direction")): return 25
	if (css_ascii_equal(name, c"grid-template-columns")): return 26
	if (css_ascii_equal(name, c"line-height")): return 27
	if (css_ascii_equal(name, c"border-style")): return 28
	if (css_ascii_equal(name, c"flex-grow")): return 29
	if (css_ascii_equal(name, c"flex-shrink")): return 30
	if (css_ascii_equal(name, c"flex-basis")): return 31
	if (css_ascii_equal(name, c"justify-content")): return 32
	return -1

float32 win_css_color_clamp(float32 value):
	if (value < 0.0): return 0.0
	if (value > 1.0): return 1.0
	return value

# Reduce finite hues without float-to-integer overflow or work proportional
# to the number of turns. An overflowed hue has the CSS infinite-angle value 0.
float32 win_css_hue_turn(float32 hue):
	if ((float_bits(hue) & 0x7f800000) == 0x7f800000): return 0.0
	int negative = hue < 0.0
	hue = fabs(hue)
	float32 divisor = 1.0
	while (divisor <= hue / 2.0): divisor = divisor * 2.0
	while (divisor >= 1.0):
		if (hue >= divisor): hue = hue - divisor
		divisor = divisor / 2.0
	if (negative && hue > 0.0): hue = 1.0 - hue
	return hue

float32 win_css_hsl_channel(float32 hue, float32 low, float32 high):
	if (hue < 0.0): hue = hue + 1.0
	if (hue >= 1.0): hue = hue - 1.0
	if (hue < 1.0 / 6.0): return low + (high - low) * hue * 6.0
	if (hue < 0.5): return high
	if (hue < 2.0 / 3.0): return low + (high - low) * (2.0 / 3.0 - hue) * 6.0
	return low

ui_color win_css_function_color(css_document* css, int first, int last):
	ui_color invalid = ui_color_new(0.0, 0.0, 0.0, -1.0)
	if (first < 0 || first >= last || last > css.tokens.length): return invalid
	css_token* name = css.tokens[first]
	if (css_kind(name, c"ident") == 0): return invalid
	int hsl = css_ascii_equal(name.value, c"hsl") || css_ascii_equal(name.value, c"hsla")
	if (hsl == 0 && css_ascii_equal(name.value, c"rgb") == 0 && css_ascii_equal(name.value, c"rgba") == 0): return invalid
	int open = first + 1
	if (open >= last || css_delim(css.tokens[open], '(') == 0 || name.end != css.tokens[open].start): return invalid
	int close = css.tokens[open].match
	if (close < open || close >= last || css_skip(css, close + 1, last) != last): return invalid
	int legacy = 0
	for i in range(open + 1, close):
		if (css_delim(css.tokens[i], ',')): legacy = 1
	float32[4] values
	values[3] = 1.0
	int count = 0
	int rgb_percent = -1
	int pos = css_skip(css, open + 1, close)
	while (pos < close):
		if (count >= 4): return invalid
		css_token* t = css.tokens[pos]
		int percentage = css_kind(t, c"percentage")
		int number = css_kind(t, c"number")
		int dimension = css_kind(t, c"dimension")
		int missing = legacy == 0 && css_kind(t, c"ident") && css_ascii_equal(t.value, c"none")
		if (missing == 0 && number == 0 && percentage == 0 && (hsl == 0 || count != 0 || dimension == 0)): return invalid
		int consumed = 0
		float32 component = 0.0
		if (missing == 0): component = parse_float(t.value, &consumed)
		# A decoded unit beginning with e must not become a numeric exponent.
		if (missing == 0 && (consumed == 0 || consumed != css_number_end(css, t.start) - t.start || fis_nan(component))): return invalid
		if (missing): component = 0.0
		else if (hsl && count == 0):
			if (percentage): return invalid
			char* unit = t.value + consumed
			if (number || css_ascii_equal(unit, c"deg")): component = component / 360.0
			else if (css_ascii_equal(unit, c"grad")): component = component / 400.0
			else if (css_ascii_equal(unit, c"rad")): component = component / 6.283185307179586
			else if (css_ascii_equal(unit, c"turn") == 0): return invalid
			component = win_css_hue_turn(component)
		else:
			if (count < 3 && hsl):
				if (legacy && percentage == 0): return invalid
				component = component / 100.0
			else if (percentage): component = component / 100.0
			else if (count < 3): component = component / 255.0
			if (legacy && hsl == 0 && count < 3):
				if (rgb_percent >= 0 && percentage != rgb_percent): return invalid
				rgb_percent = percentage
			component = win_css_color_clamp(component)
		values[count] = component
		count = count + 1
		int next = css_skip(css, pos + 1, close)
		if (next == close): break
		if (count == 4): return invalid
		if (legacy):
			if (css_delim(css.tokens[next], ',') == 0): return invalid
			pos = css_skip(css, next + 1, close)
		else if (count == 3):
			if (css_delim(css.tokens[next], '/') == 0): return invalid
			pos = css_skip(css, next + 1, close)
		else:
			# CSS component whitespace is optional when tokenization already
			# separates the values (including comments and signed numbers).
			pos = next
		if (pos >= close): return invalid
	if (count < 3): return invalid
	if (hsl):
		float32 high = values[2] * (1.0 + values[1])
		if (values[2] >= 0.5): high = values[2] + values[1] - values[2] * values[1]
		float32 low = 2.0 * values[2] - high
		return ui_color_new(win_css_hsl_channel(values[0] + 1.0 / 3.0, low, high), win_css_hsl_channel(values[0], low, high), win_css_hsl_channel(values[0] - 1.0 / 3.0, low, high), values[3])
	return ui_color_new(values[0], values[1], values[2], values[3])


import win.cascade
