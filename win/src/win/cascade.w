# Author and inline cascade. Borrowed token ranges stay alive until resolution.
# Origins and layers can extend this key without altering specificity semantics.
struct win_cascade_key:
	int important
	int inline_style
	win_specificity specificity
	int order

struct win_css_specified:
	int present
	win_cascade_key key
	css_document* css
	int first
	int last
	int wide
	# Synthetic shorthand values: 1 initial, 2 one, 3 zero (0px for basis).
	int reset

int win_cascade_compare(win_cascade_key a, win_cascade_key b):
	if (a.important != b.important): return a.important - b.important
	if (a.inline_style != b.inline_style): return a.inline_style - b.inline_style
	int specificity = win_specificity_compare(a.specificity, b.specificity)
	if (specificity != 0): return specificity
	return a.order - b.order

win_cascade_key win_cascade_author(int important, int inline_style, win_specificity specificity, int order):
	win_cascade_key key
	key.important = important
	key.inline_style = inline_style
	key.specificity = specificity
	key.order = order
	return key

void win_css_store(win_css_specified* winners, int property, css_document* css, int first, int last, win_cascade_key key, int reset):
	win_css_specified* slot = &winners[property]
	if (slot.present && win_cascade_compare(key, slot.key) < 0): return
	slot.present = 1
	slot.key = key
	slot.css = css
	slot.first = first
	slot.last = last
	slot.wide = 0
	if (reset == 0 && css_skip(css, first + 1, last) == last): slot.wide = win_css_wide(css.tokens[first])
	slot.reset = reset

int win_css_ident(css_token* token, char* name):
	return css_kind(token, c"ident") && css_ascii_equal(token.value, name)

int win_css_color_valid(css_token* token):
	char* value = token.value
	if (css_kind(token, c"hash")):
		int n = strlen(value)
		if (n != 3 && n != 4 && n != 6 && n != 8): return 0
		for i in range(n):
			if (win_hex(value[i]) < 0): return 0
	else:
		if (css_kind(token, c"ident") == 0): return 0
		if (css_ascii_equal(value, c"currentcolor")): return 1
		int hex = 1
		for i in range(strlen(value)):
			if (win_hex(value[i]) < 0): hex = 0
		if (hex): return 0
	return win_color(value, ui_color_new(0.0, 0.0, 0.0, -1.0)).a >= 0.0

int win_css_track(css_token* token):
	win_css_numeric n = win_css_number(token)
	return n.value >= 0.0 && (win_css_is_length(n) || n.unit == 5 || n.unit == 6) || win_css_ident(token, c"auto") || win_css_ident(token, c"min-content") || win_css_ident(token, c"max-content")

# The current layout only consumes a count, but accepts a declared, validated
# track-list grammar. Track sizing remains an explicit layout limitation.
int win_css_grid_columns(css_document* css, int first, int last):
	if (win_css_ident(css.tokens[first], c"none") && css_skip(css, first + 1, last) == last): return 1
	int pos = first
	int columns = 0
	while (pos < last):
		if (win_css_ident(css.tokens[pos], c"repeat")):
			int open = pos + 1
			if (open >= last || css_delim(css.tokens[open], '(') == 0 || css.tokens[pos].end != css.tokens[open].start): return 0
			int close = css.tokens[open].match
			if (close < open || close >= last): return 0
			int count = css_skip(css, open + 1, close)
			if (count >= close): return 0
			win_css_numeric n = win_css_number(css.tokens[count])
			if (n.unit != 1 || n.value < 1.0 || n.value > 12.0 || n.value != cast(float32, cast(int, n.value))): return 0
			# <integer> syntax excludes decimal and exponent representations.
			char* raw = css.tokens[count].value
			int digit = 0
			if (raw[0] == '+'): digit = 1
			while (css_digit(raw[digit])): digit = digit + 1
			if (raw[digit] != 0): return 0
			int comma = css_skip(css, count + 1, close)
			if (comma >= close || css_delim(css.tokens[comma], ',') == 0): return 0
			int track = css_skip(css, comma + 1, close)
			int tracks = 0
			while (track < close):
				if (win_css_track(css.tokens[track]) == 0): return 0
				tracks = tracks + 1
				track = css_skip(css, track + 1, close)
			if (tracks == 0): return 0
			columns = columns + cast(int, n.value) * tracks
			pos = css_skip(css, close + 1, last)
		else:
			if (win_css_track(css.tokens[pos]) == 0): return 0
			columns = columns + 1
			pos = css_skip(css, pos + 1, last)
		if (columns > 12): return 0
	return columns

int win_css_longhand_valid(int property, css_document* css, int first, int last):
	css_token* token = css.tokens[first]
	int single = css_skip(css, first + 1, last) == last
	if (single && win_css_wide(token)): return 1
	if (property == 0 || property == 8 || property == 21):
		if (single): return win_css_color_valid(token)
		return win_css_function_color(css, first, last).a >= 0.0
	if (property == 26): return win_css_grid_columns(css, first, last) > 0
	if (single == 0): return 0
	win_css_numeric n = win_css_number(token)
	int length = win_css_is_length(n)
	if (property == 1): return n.value >= 0.0 && (length || n.unit == 5)
	if (property == 2): return win_css_ident(token, c"normal") || win_css_ident(token, c"bold") || win_css_ident(token, c"bolder") || win_css_ident(token, c"lighter") || n.unit == 1 && n.value >= 1.0 && n.value <= 1000.0
	if (property == 3): return win_css_ident(token, c"normal") || win_css_ident(token, c"italic") || win_css_ident(token, c"oblique")
	if (property == 4): return win_css_ident(token, c"none") || win_css_ident(token, c"underline")
	if (property == 5): return win_css_ident(token, c"none") || win_css_ident(token, c"block") || win_css_ident(token, c"inline") || win_css_ident(token, c"inline-block") || win_css_ident(token, c"flex") || win_css_ident(token, c"grid") || win_css_ident(token, c"list-item")
	if (property == 6): return win_css_ident(token, c"normal") || win_css_ident(token, c"pre") || win_css_ident(token, c"pre-wrap")
	if (property == 7): return win_css_ident(token, c"left") || win_css_ident(token, c"right") || win_css_ident(token, c"center") || win_css_ident(token, c"start") || win_css_ident(token, c"end")
	if (property >= 9 && property <= 19 || property == 24):
		if (property >= 12 && property <= 15): return length || win_css_ident(token, c"auto")
		if ((property == 9 || property == 10) && win_css_ident(token, c"auto")): return 1
		if (property == 11 && win_css_ident(token, c"none")): return 1
		if ((property == 9 || property == 11) && n.unit == 5): return n.value >= 0.0
		return length && n.value >= 0.0
	if (property == 20): return length && n.value >= 0.0 || win_css_ident(token, c"thin") || win_css_ident(token, c"medium") || win_css_ident(token, c"thick")
	if (property == 22): return win_css_ident(token, c"border-box") || win_css_ident(token, c"content-box")
	if (property == 23): return win_css_ident(token, c"visible") || win_css_ident(token, c"hidden") || win_css_ident(token, c"collapse")
	if (property == 33): return win_css_ident(token, c"nowrap") || win_css_ident(token, c"wrap")
	if (property == 34 || property == 35): return win_css_ident(token, c"stretch") || win_css_ident(token, c"flex-start") || win_css_ident(token, c"flex-end") || win_css_ident(token, c"center") || property == 35 && win_css_ident(token, c"auto")
	if (property == 25): return win_css_ident(token, c"row") || win_css_ident(token, c"column")
	if (property == 27): return win_css_ident(token, c"normal") || n.value >= 0.0 && (length || n.unit == 1 || n.unit == 5)
	if (property == 32): return win_css_ident(token, c"flex-start") || win_css_ident(token, c"flex-end") || win_css_ident(token, c"center") || win_css_ident(token, c"space-between") || win_css_ident(token, c"space-around") || win_css_ident(token, c"space-evenly")
	if (property == 29 || property == 30): return n.unit == 1 && n.value >= 0.0
	if (property == 31): return n.value >= 0.0 && (length || n.unit == 5) || win_css_ident(token, c"auto") || win_css_ident(token, c"content")
	if (property == 28): return win_css_ident(token, c"none") || win_css_ident(token, c"hidden") || win_css_ident(token, c"solid")
	return 0

# flex: none | [ <grow> <shrink>? || <basis> ]. The factors must
# remain adjacent; a bare zero is a factor until both factors are present.
int win_css_flex(css_document* css, int first, int last, win_cascade_key key, win_css_specified* winners):
	int single = css_skip(css, first + 1, last) == last
	css_token* token = css.tokens[first]
	if (single && win_css_wide(token)):
		if (winners != 0):
			for p in range(29, 32): win_css_store(winners, p, css, first, last, key, 0)
		return 1
	if (single && win_css_ident(token, c"none")):
		if (winners != 0):
			win_css_store(winners, 29, css, first, last, key, 3)
			win_css_store(winners, 30, css, first, last, key, 3)
			win_css_store(winners, 31, css, first, last, key, 1)
		return 1
	int grow = -1
	int shrink = -1
	int basis = -1
	int after_basis = 0
	int pos = first
	while (pos < last):
		css_token* value = css.tokens[pos]
		if (win_css_wide(value)): return 0
		win_css_numeric n = win_css_number(value)
		if (n.unit == 1 && (grow < 0 || shrink < 0)):
			if (n.value < 0.0 || after_basis): return 0
			if (grow < 0): grow = pos
			else: shrink = pos
		else:
			if (basis >= 0 || win_css_longhand_valid(31, css, pos, pos + 1) == 0): return 0
			basis = pos
			if (grow >= 0): after_basis = 1
		pos = css_skip(css, pos + 1, last)
	if (winners != 0):
		int reset = 0
		if (grow < 0): reset = 2
		win_css_store(winners, 29, css, grow, grow + 1, key, reset)
		reset = 0
		if (shrink < 0): reset = 2
		win_css_store(winners, 30, css, shrink, shrink + 1, key, reset)
		reset = 0
		if (basis < 0): reset = 3
		win_css_store(winners, 31, css, basis, basis + 1, key, reset)
	return 1

# Validates the whole declaration before any longhand can become a winner.
# A null winners pointer is the public validation-only path for CSSOM.
int win_css_collect(css_document* css, css_node* d, win_cascade_key key, win_css_specified* winners):
	int first = css_skip(css, d.first, d.last)
	int last = css_trim(css, first, d.last)
	if (first >= last): return 0
	int property = win_css_property(d.name)
	if (property >= 0):
		if (win_css_longhand_valid(property, css, first, last) == 0): return 0
		if (winners != 0): win_css_store(winners, property, css, first, last, key, 0)
		return 1
	if (css_ascii_equal(d.name, c"flex")): return win_css_flex(css, first, last, key, winners)
	int base = -1
	if (css_ascii_equal(d.name, c"margin")): base = 12
	if (css_ascii_equal(d.name, c"padding")): base = 16
	if (base >= 0):
		int[4] values
		int count = 0
		int pos = first
		while (pos < last && count < 4):
			values[count] = pos
			count = count + 1
			pos = css_skip(css, pos + 1, last)
		if (pos < last): return 0
		if (count == 1): values[1] = values[0]
		if (count < 3): values[2] = values[0]
		if (count < 4): values[3] = values[1]
		for k in range(4):
			if (count > 1 && win_css_wide(css.tokens[values[k]])): return 0
			if (win_css_longhand_valid(base + k, css, values[k], values[k] + 1) == 0): return 0
		if (winners != 0):
			for k in range(4): win_css_store(winners, base + k, css, values[k], values[k] + 1, key, 0)
		return 1
	if (css_ascii_equal(d.name, c"border") == 0): return 0
	if (css_skip(css, first + 1, last) == last && win_css_wide(css.tokens[first])):
		if (winners != 0):
			win_css_store(winners, 20, css, first, last, key, 0)
			win_css_store(winners, 21, css, first, last, key, 0)
			win_css_store(winners, 28, css, first, last, key, 0)
		return 1
	int[3] starts
	int[3] ends
	for k in range(3): starts[k] = -1
	int pos = first
	while (pos < last):
		int end = pos + 1
		if (end < last && css_delim(css.tokens[end], '(')): end = css_next_component(css, end, last)
		int component = -1
		if (win_css_wide(css.tokens[pos])): return 0
		if (win_css_longhand_valid(20, css, pos, end)): component = 0
		else if (win_css_longhand_valid(28, css, pos, end)): component = 1
		else if (win_css_longhand_valid(21, css, pos, end)): component = 2
		if (component < 0 || starts[component] >= 0): return 0
		starts[component] = pos
		ends[component] = end
		pos = css_skip(css, end, last)
	if (winners != 0):
		for k in range(3):
			int target = 20
			if (k == 1): target = 28
			if (k == 2): target = 21
			win_css_store(winners, target, css, starts[k], ends[k], key, starts[k] < 0)
	return 1

int win_css_declaration_supported(css_document* css, css_node* declaration):
	return win_css_collect(css, declaration, win_cascade_author(0, 0, win_specificity_zero(), 0), 0)

int win_css_inherited(int property):
	return property == 0 || property == 1 || property == 2 || property == 3 || property == 6 || property == 7 || property == 23 || property == 27

void win_css_copy(win_style* s, win_style from, int property):
	if (property == 0): s.color = from.color
	if (property == 1): s.size = from.size
	if (property == 2): s.bold = from.bold
	if (property == 3): s.flags = (s.flags & (0 - 1 - UI_TEXT_ITALIC)) | (from.flags & UI_TEXT_ITALIC)
	if (property == 4): s.flags = (s.flags & (0 - 1 - UI_TEXT_UNDERLINE)) | (from.flags & UI_TEXT_UNDERLINE)
	if (property == 5): s.display = from.display
	if (property == 6): s.pre = from.pre
	if (property == 7): s.align = from.align
	if (property == 8): s.background = from.background
	if (property == 9):
		s.width = from.width
		s.width_percent = from.width_percent
	if (property == 10): s.height = from.height
	if (property == 11):
		s.max_width = from.max_width
		s.max_width_percent = from.max_width_percent
	if (property == 12): s.margin_top = from.margin_top
	if (property == 13):
		s.margin_right = from.margin_right
		s.margin_right_auto = from.margin_right_auto
	if (property == 14): s.margin_bottom = from.margin_bottom
	if (property == 15):
		s.margin_left = from.margin_left
		s.margin_left_auto = from.margin_left_auto
	if (property == 16): s.padding_top = from.padding_top
	if (property == 17): s.padding_right = from.padding_right
	if (property == 18): s.padding_bottom = from.padding_bottom
	if (property == 19): s.padding_left = from.padding_left
	if (property == 20): s.border_width = from.border_width
	if (property == 21):
		s.border_color = from.border_color
		s.border_current_color = from.border_current_color
	if (property == 22): s.box_sizing = from.box_sizing
	if (property == 23): s.hidden = from.hidden
	if (property == 24): s.gap = from.gap
	if (property == 33): s.flex_wrap = from.flex_wrap
	if (property == 34): s.align_items = from.align_items
	if (property == 35): s.align_self = from.align_self
	if (property == 25): s.flex_column = from.flex_column
	if (property == 26): s.columns = from.columns
	if (property == 27):
		s.line_height = from.line_height
		s.line_height_factor = from.line_height_factor
	if (property == 28): s.border_style = from.border_style
	if (property == 32): s.justify = from.justify
	if (property == 29): s.flex_grow = from.flex_grow
	if (property == 30): s.flex_shrink = from.flex_shrink
	if (property == 31):
		s.flex_basis = from.flex_basis
		s.flex_basis_percent = from.flex_basis_percent

void win_css_compute_value(win_css_specified* slot, int property, win_style* s, win_style inherited):
	if (slot.present == 0): return
	if (slot.reset > 1):
		float32 value = 0.0
		if (slot.reset == 2): value = 1.0
		if (property == 29): s.flex_grow = value
		if (property == 30): s.flex_shrink = value
		if (property == 31):
			s.flex_basis = value
			s.flex_basis_percent = 0
		return
	if (slot.wide || slot.reset):
		win_style from = win_default_style()
		# Initial display is inline; -1 is exclusively the HTML default marker.
		from.display = 2
		if (slot.wide == 1 || slot.wide == 3 && win_css_inherited(property)): from = inherited
		if (property == 21 && slot.wide == 1): from.border_current_color = 0
		win_css_copy(s, from, property)
		return
	css_document* css = slot.css
	css_token* token = css.tokens[slot.first]
	char* value = token.value
	win_css_numeric number = win_css_number(token)
	float32 size = s.size
	if (property == 1): size = inherited.size
	float32 n = win_css_resolve_length(number, size, s.root_size)
	# Keep finite used lengths bounded without float-to-int overflow.
	if (n > 1000000.0): n = 1000000.0
	if (n < -1000000.0): n = -1000000.0
	if (property == 0 || property == 8 || property == 21):
		ui_color color = s.color
		if (property == 0 && win_css_ident(token, c"currentcolor")): color = inherited.color
		else if (win_css_ident(token, c"currentcolor") == 0):
			if (css_skip(css, slot.first + 1, slot.last) == slot.last): color = win_color(value, color)
			else: color = win_css_function_color(css, slot.first, slot.last)
		if (property == 0): s.color = color
		if (property == 8): s.background = color
		if (property == 21):
			s.border_color = color
			s.border_current_color = win_css_ident(token, c"currentcolor")
	else if (property == 1):
		if (number.unit == 5): n = number.value * cast(float32, inherited.size) / 100.0
		if (n > 1000000.0): n = 1000000.0
		s.size = n
	else if (property == 2):
		s.bold = win_css_ident(token, c"bold") || win_css_ident(token, c"bolder") || number.unit == 1 && number.value >= 600.0
	else if (property == 3):
		s.flags = s.flags & (0 - 1 - UI_TEXT_ITALIC)
		if (win_css_ident(token, c"normal") == 0): s.flags = s.flags | UI_TEXT_ITALIC
	else if (property == 4):
		s.flags = s.flags & (0 - 1 - UI_TEXT_UNDERLINE)
		if (win_css_ident(token, c"underline")): s.flags = s.flags | UI_TEXT_UNDERLINE
	else if (property == 5):
		s.display = 2
		if (win_css_ident(token, c"none")): s.display = 0
		if (win_css_ident(token, c"block") || win_css_ident(token, c"list-item")): s.display = 1
		if (win_css_ident(token, c"flex")): s.display = 3
		if (win_css_ident(token, c"grid")): s.display = 4
	else if (property == 6): s.pre = win_css_ident(token, c"pre") || win_css_ident(token, c"pre-wrap")
	else if (property == 7):
		s.align = 0
		if (win_css_ident(token, c"center")): s.align = 1
		if (win_css_ident(token, c"right") || win_css_ident(token, c"end")): s.align = 2
	else if (property == 9):
		s.width = n
		s.width_percent = number.unit == 5
		if (win_css_ident(token, c"auto")): s.width = -1.0
	else if (property == 10):
		s.height = n
		if (win_css_ident(token, c"auto")): s.height = -1.0
	else if (property == 11):
		s.max_width = n
		s.max_width_percent = number.unit == 5
		if (win_css_ident(token, c"none")): s.max_width = -1.0
	else if (property >= 12 && property <= 15):
		if (win_css_ident(token, c"auto")):
			n = 0.0
		if (property == 12): s.margin_top = n
		if (property == 13):
			s.margin_right = n
			s.margin_right_auto = win_css_ident(token, c"auto")
		if (property == 14): s.margin_bottom = n
		if (property == 15):
			s.margin_left = n
			s.margin_left_auto = win_css_ident(token, c"auto")
	else if (property == 16): s.padding_top = n
	else if (property == 17): s.padding_right = n
	else if (property == 18): s.padding_bottom = n
	else if (property == 19): s.padding_left = n
	else if (property == 20):
		if (win_css_ident(token, c"thin")): n = 1.0
		if (win_css_ident(token, c"medium")): n = 3.0
		if (win_css_ident(token, c"thick")): n = 5.0
		s.border_width = n
	else if (property == 22): s.box_sizing = win_css_ident(token, c"border-box")
	else if (property == 23): s.hidden = win_css_ident(token, c"hidden") || win_css_ident(token, c"collapse")
	else if (property == 24): s.gap = n
	else if (property == 33): s.flex_wrap = win_css_ident(token, c"wrap")
	else if (property == 34 || property == 35):
		int alignment = 0
		if (win_css_ident(token, c"auto")): alignment = -1
		if (win_css_ident(token, c"flex-start")): alignment = 1
		if (win_css_ident(token, c"flex-end")): alignment = 2
		if (win_css_ident(token, c"center")): alignment = 3
		if (property == 34): s.align_items = alignment
		else: s.align_self = alignment
	else if (property == 25): s.flex_column = win_css_ident(token, c"column")
	else if (property == 26): s.columns = win_css_grid_columns(css, slot.first, slot.last)
	else if (property == 27):
		s.line_height_factor = 0.0
		s.line_height = n
		if (number.unit == 1):
			s.line_height_factor = number.value
			s.line_height = 0.0
		if (number.unit == 5): s.line_height = number.value * cast(float32, s.size) / 100.0
	else if (property == 28): s.border_style = win_css_ident(token, c"solid")
	else if (property == 32):
		s.justify = 0
		if (win_css_ident(token, c"flex-end")): s.justify = 1
		if (win_css_ident(token, c"center")): s.justify = 2
		if (win_css_ident(token, c"space-between")): s.justify = 3
		if (win_css_ident(token, c"space-around")): s.justify = 4
		if (win_css_ident(token, c"space-evenly")): s.justify = 5
	else if (property == 29): s.flex_grow = number.value
	else if (property == 30): s.flex_shrink = number.value
	else if (property == 31):
		s.flex_basis = n
		s.flex_basis_percent = number.unit == 5
		if (win_css_ident(token, c"auto")): s.flex_basis = -1.0
		if (win_css_ident(token, c"content")): s.flex_basis = -2.0

void win_css_resolve_border(win_style* style):
	style.border = 0.0
	if (style.border_style): style.border = style.border_width
	if (style.border_current_color): style.border_color = style.color

void win_css_compute(win_css_specified* winners, win_style* style, win_style inherited, int root):
	win_css_compute_value(&winners[1], 1, style, inherited)
	if (root): style.root_size = style.size
	# Color precedes background/currentColor; all lengths see the winning size.
	for property in range(WIN_CSS_PROPERTY_COUNT):
		if (property != 1): win_css_compute_value(&winners[property], property, style, inherited)
	win_css_resolve_border(style)

# Accepted media grammar: [only]? (screen|all) [and condition]* or condition
# [and condition]*, where condition is exactly (min/max-width: <length>).
int win_css_media(css_document* css, css_node* rule, int width):
	int pos = css_skip(css, rule.first, rule.last)
	int last = rule.last
	if (pos >= last): return 0
	int typed = 0
	if (win_css_ident(css.tokens[pos], c"only")):
		pos = css_skip(css, pos + 1, last)
		if (pos >= last || css_kind(css.tokens[pos], c"ident") == 0): return 0
	if (css_kind(css.tokens[pos], c"ident")):
		if (win_css_ident(css.tokens[pos], c"screen") == 0 && win_css_ident(css.tokens[pos], c"all") == 0): return 0
		typed = 1
		pos = css_skip(css, pos + 1, last)
	int conditions = 0
	int matched = 1
	while (pos < last):
		if (typed || conditions):
			if (win_css_ident(css.tokens[pos], c"and") == 0): return 0
			pos = css_skip(css, pos + 1, last)
		if (pos >= last || css_delim(css.tokens[pos], '(') == 0): return 0
		int close = css.tokens[pos].match
		if (close <= pos || close >= last): return 0
		int key = css_skip(css, pos + 1, close)
		int colon = css_skip(css, key + 1, close)
		int val = css_skip(css, colon + 1, close)
		if (val >= close || css_delim(css.tokens[colon], ':') == 0 || css_skip(css, val + 1, close) != close): return 0
		win_css_numeric number = win_css_number(css.tokens[val])
		if (win_css_is_length(number) == 0 || number.value < 0.0): return 0
		float32 n = win_css_resolve_length(number, 18, 18)
		if (win_css_ident(css.tokens[key], c"min-width")):
			if (cast(float32, width) < n): matched = 0
		else if (win_css_ident(css.tokens[key], c"max-width")):
			if (cast(float32, width) > n): matched = 0
		else: return 0
		conditions = conditions + 1
		pos = css_skip(css, close + 1, last)
	return matched

void win_css_rules(css_document* css, list[css_node*] rules, html_node* node, int width, win_css_specified* winners, int* order):
	for i in range(rules.length):
		css_node* rule = rules[i]
		if (strcmp(rule.kind, c"at-rule") == 0):
			if (css_ascii_equal(rule.name, c"media") && win_css_media(css, rule, width)): win_css_rules(css, rule.children, node, width, winners, order)
			continue
		if (strcmp(rule.kind, c"qualified-rule") != 0 || win_selector_list_valid(css, rule.first, rule.last) == 0): continue
		int matched = 0
		win_specificity specificity = win_specificity_zero()
		for j in range(rule.children.length):
			css_node* selector = rule.children[j]
			if (strcmp(selector.kind, c"selector") != 0): continue
			if (win_selector_match(css, selector.first, selector.last, node) < 0): continue
			win_specificity score = win_selector_specificity(css, selector.first, selector.last)
			if (matched == 0 || win_specificity_compare(score, specificity) > 0): specificity = score
			matched = 1
		if (matched == 0): continue
		for j in range(rule.children.length):
			css_node* d = rule.children[j]
			if (strcmp(d.kind, c"declaration") == 0):
				order[0] = order[0] + 1
				win_css_collect(css, d, win_cascade_author(d.important, 0, specificity, order[0]), winners)
