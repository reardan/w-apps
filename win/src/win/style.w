# Author CSS cascade and block-flow styling. Unsupported syntax never matches.
import libs.extras.html.html
import libs.extras.css.css
import graphics.ui.text

struct win_style:
	int size
	int line_height
	float32 line_height_factor
	int bold
	int flags
	int hidden
	int pre
	int display
	int align
	int width
	int width_percent
	int height
	int max_width
	int max_width_percent
	int margin_top
	int margin_right
	int margin_bottom
	int margin_left
	int padding_top
	int padding_right
	int padding_bottom
	int padding_left
	int border
	int gap
	int flex_column
	int columns
	int box_sizing
	ui_color background
	ui_color border_color
	ui_color color

char* win_attr(html_node* node, char* name):
	html_attribute* attr = html_attribute_find(node.attributes, name)
	if (attr == 0): return c""
	return attr.value

int win_tag(html_node* node, char* name):
	return node.kind == HTML_START && strcmp(node.name, name) == 0

win_style win_default_style():
	win_style s
	s.size = 18
	s.line_height = 0
	s.line_height_factor = 0.0
	s.bold = 0
	s.flags = 0
	s.hidden = 0
	s.pre = 0
	s.display = -1
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
	s.padding_top = 0
	s.padding_right = 0
	s.padding_bottom = 0
	s.padding_left = 0
	s.border = 0
	s.gap = 0
	s.flex_column = 0
	s.columns = 1
	s.box_sizing = 0
	s.background = ui_color_new(0.0, 0.0, 0.0, 0.0)
	s.border_color = ui_gray(0.0)
	s.color = ui_color_new(0.12, 0.16, 0.20, 1.0)
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


int win_class_has(char* classes, char* name):
	int pos = 0
	int n = strlen(name)
	while (classes[pos] != 0):
		while (html_space(classes[pos])): pos = pos + 1
		int start = pos
		while (classes[pos] != 0 && html_space(classes[pos]) == 0): pos = pos + 1
		if (pos - start == n):
			int equal = 1
			for k in range(n):
				if (classes[start + k] != name[k]): equal = 0
			if (equal): return 1
	return 0

html_node* win_previous_element(html_node* node):
	if (node.parent == 0): return 0
	html_node* prev = 0
	html_node* child = node.parent.first_child
	while (child != 0 && child != node):
		if (child.kind == HTML_START): prev = child
		child = child.next_sibling
	return prev

int win_selector_match(css_document* css, int first, int last, html_node* node);

int win_selector_specificity(css_document* css, int first, int last):
	int score = 0
	int maximum = 0
	int pos = first
	while (pos < last):
		css_token* t = css.tokens[pos]
		if (css_delim(t, ',')):
			if (score > maximum): maximum = score
			score = 0
		else if (css_kind(t, c"hash")): score = score + 10000
		else if (css_delim(t, '.')):
			score = score + 100
			pos = pos + 1
		else if (css_delim(t, '[')):
			score = score + 100
			pos = css_next_component(css, pos, last)
			continue
		else if (css_delim(t, ':')):
			pos = pos + 1
			if (pos >= last): return score
			char* pseudo = css.tokens[pos].value
			if (pos + 1 < last && css_delim(css.tokens[pos + 1], '(')):
				int close = css.tokens[pos + 1].match
				if (close < 0): return score
				if (strcmp(pseudo, c"not") == 0 || strcmp(pseudo, c"is") == 0): score = score + win_selector_specificity(css, pos + 2, close)
				else if (strcmp(pseudo, c"where") != 0): score = score + 100
				pos = close
			else: score = score + 100
		else if (css_kind(t, c"ident")): score = score + 1
		pos = pos + 1
	if (score > maximum): maximum = score
	return maximum

# Specificity is bounded by parser depth; -1 means no match.
int win_selector_compound(css_document* css, int first, int last, html_node* node):
	if (node == 0 || node.kind != HTML_START): return -1
	int score = 0
	int pos = first
	while (pos < last):
		css_token* t = css.tokens[pos]
		if (css_kind(t, c"comment")):
			pos = pos + 1
			continue
		if (css_kind(t, c"ident")):
			if (css_ascii_equal(t.value, node.name) == 0): return -1
			score = score + 1
		else if (css_kind(t, c"hash")):
			if (strcmp(win_attr(node, c"id"), t.value) != 0): return -1
			score = score + 10000
		else if (css_delim(t, '.')):
			pos = pos + 1
			if (pos >= last || css_kind(css.tokens[pos], c"ident") == 0): return -1
			if (win_class_has(win_attr(node, c"class"), css.tokens[pos].value) == 0): return -1
			score = score + 100
		else if (css_delim(t, '[')):
			int close = t.match
			if (close < pos || close >= last): return -1
			int key = css_skip(css, pos + 1, close)
			if (key >= close || css_kind(css.tokens[key], c"ident") == 0): return -1
			html_attribute* attr = html_attribute_find(node.attributes, css.tokens[key].value)
			if (attr == 0): return -1
			int op = css_skip(css, key + 1, close)
			if (op < close):
				if (css_delim(css.tokens[op], '=') == 0): return -1
				int value = css_skip(css, op + 1, close)
				if (value >= close || css_skip(css, value + 1, close) != close): return -1
				if (strcmp(attr.value, css.tokens[value].value) != 0): return -1
			pos = close
			score = score + 100
		else if (css_delim(t, ':')):
			pos = pos + 1
			if (pos >= last): return -1
			char* pseudo = css.tokens[pos].value
			if (strcmp(pseudo, c"not") == 0 || strcmp(pseudo, c"is") == 0 || strcmp(pseudo, c"where") == 0):
				int open = pos + 1
				if (open >= last || css_delim(css.tokens[open], '(') == 0): return -1
				int close = css.tokens[open].match
				if (close < 0 || close >= last): return -1
				int start = open + 1
				int end = start
				int matched = 0
				int specificity = 0
				while (end <= close):
					if (end == close || css_delim(css.tokens[end], ',')):
						int nested = win_selector_match(css, start, end, node)
						if (nested >= 0): matched = 1
						if (nested > specificity): specificity = nested
						start = end + 1
						end = end + 1
					else: end = css_next_component(css, end, close)
				if (strcmp(pseudo, c"not") == 0):
					if (matched): return -1
					specificity = 100
				else if (matched == 0): return -1
				if (strcmp(pseudo, c"where") == 0): specificity = 0
				score = score + specificity
				pos = close + 1
				continue
			if (strcmp(pseudo, c"nth-child") == 0):
				int open = pos + 1
				if (open >= last || css_delim(css.tokens[open], '(') == 0): return -1
				int close = css.tokens[open].match
				int value = css_skip(css, open + 1, close)
				if (close < 0 || close >= last || value >= close || css_skip(css, value + 1, close) != close): return -1
				int index = 1
				html_node* previous = win_previous_element(node)
				while (previous != 0):
					index = index + 1
					previous = win_previous_element(previous)
				char* expression = css.tokens[value].value
				if (strcmp(expression, c"odd") == 0):
					if (index % 2 != 1): return -1
				else if (strcmp(expression, c"even") == 0):
					if (index % 2 != 0): return -1
				else if (index != atoi(expression)): return -1
				pos = close
			else if (strcmp(pseudo, c"root") == 0):
				if (node.parent != 0 && node.parent.kind != HTML_DOCUMENT): return -1
			else if (strcmp(pseudo, c"first-child") == 0):
				if (win_previous_element(node) != 0): return -1
			else if (strcmp(pseudo, c"last-child") == 0):
				html_node* next = node.next_sibling
				while (next != 0):
					if (next.kind == HTML_START): return -1
					next = next.next_sibling
			else if (strcmp(pseudo, c"link") == 0):
				if (win_tag(node, c"a") == 0 || win_attr(node, c"href")[0] == 0): return -1
			else if (strcmp(pseudo, c"disabled") == 0 || strcmp(pseudo, c"checked") == 0):
				if (html_attribute_find(node.attributes, pseudo) == 0): return -1
			else: return -1
			score = score + 100
		else if (css_delim(t, '*') == 0): return -1
		pos = pos + 1
	return win_selector_specificity(css, first, last)

int win_selector_match(css_document* css, int first, int last, html_node* node):
	first = css_skip(css, first, last)
	last = css_trim(css, first, last)
	if (first >= last || node == 0): return -1
	int split = -1
	int comb = 0
	int pos = first
	while (pos < last):
		css_token* t = css.tokens[pos]
		if (css_kind(t, c"space")):
			if (pos > first):
				split = pos
				comb = 0
		else if (css_delim(t, '>') || css_delim(t, '+') || css_delim(t, '~')):
			split = pos
			comb = t.value[0]
			pos = css_skip(css, pos + 1, last)
			continue
		pos = css_next_component(css, pos, last)
	if (split < 0): return win_selector_compound(css, first, last, node)
	int right = css_skip(css, split + 1, last)
	int local = win_selector_compound(css, right, last, node)
	if (local < 0): return -1
	int end = css_trim(css, first, split)
	html_node* candidate = node.parent
	if (comb == '+' || comb == '~'): candidate = win_previous_element(node)
	while (candidate != 0):
		int score = win_selector_match(css, first, end, candidate)
		if (score >= 0): return score + local
		if (comb == '>' || comb == '+'): return -1
		if (comb == '~'): candidate = win_previous_element(candidate)
		else: candidate = candidate.parent
	return -1

# Integer pixel lengths, em/rem and percentages for width; unsupported units
# are rejected. Fractional pixels round down consistently with font strikes.
int win_css_length(css_token* token, int size):
	char* value = token.value
	int n = strlen(value)
	if (css_kind(token, c"number") && atoi(value) == 0): return 0
	if (css_kind(token, c"dimension") == 0): return -1
	if (n > 2 && strcmp(value + n - 2, c"px") == 0): return atoi(value)
	if (n > 3 && strcmp(value + n - 3, c"rem") == 0): return atoi(value) * 18
	if (n > 2 && strcmp(value + n - 2, c"em") == 0): return atoi(value) * size
	return -1

int win_selector_matches(html_node* node, char* selector):
	css_document* css = css_parse_selectors_n(selector, strlen(selector), 0)
	int found = 0
	if (css.failed == 0):
		for i in range(css.nodes.length):
			if (win_selector_match(css, css.nodes[i].first, css.nodes[i].last, node) >= 0): found = 1
	css_document_free(css)
	return found

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
	if (css_ascii_equal(name, c"flex-direction")): return 25
	if (css_ascii_equal(name, c"grid-template-columns")): return 26
	if (css_ascii_equal(name, c"line-height")): return 27
	return -1

float32 win_css_decimal(char* value);

void win_css_value(win_style* s, win_style inherited, int property, css_token* t):
	char* value = t.value
	int inherit = css_ascii_equal(value, c"inherit")
	if (property == 0):
		if (inherit): s.color = inherited.color
		else: s.color = win_color(value, s.color)
	else if (property == 1):
		int size = win_css_length(t, inherited.size)
		if (inherit): size = inherited.size
		if (css_kind(t, c"percentage")): size = inherited.size * atoi(value) / 100
		if (size >= 8 && size <= 144): s.size = size
	else if (property == 2):
		if (inherit): s.bold = inherited.bold
		else if (css_ascii_equal(value, c"normal") || atoi(value) >= 100 && atoi(value) <= 500): s.bold = 0
		else if (css_ascii_equal(value, c"bold") || css_ascii_equal(value, c"bolder") || atoi(value) >= 600 && atoi(value) <= 900): s.bold = 1
	else if (property == 3):
		if (css_ascii_equal(value, c"normal")): s.flags = s.flags & (0 - 1 - UI_TEXT_ITALIC)
		else if (css_ascii_equal(value, c"italic") || css_ascii_equal(value, c"oblique")): s.flags = s.flags | UI_TEXT_ITALIC
	else if (property == 4):
		if (css_ascii_equal(value, c"none")): s.flags = s.flags & (0 - 1 - UI_TEXT_UNDERLINE)
		else if (css_ascii_equal(value, c"underline")): s.flags = s.flags | UI_TEXT_UNDERLINE
	else if (property == 5):
		if (css_ascii_equal(value, c"none")): s.display = 0
		else if (css_ascii_equal(value, c"block") || css_ascii_equal(value, c"list-item")): s.display = 1
		else if (css_ascii_equal(value, c"flex")): s.display = 3
		else if (css_ascii_equal(value, c"grid")): s.display = 4
		else if (css_ascii_equal(value, c"inline") || css_ascii_equal(value, c"inline-block")): s.display = 2
	else if (property == 6):
		if (inherit): s.pre = inherited.pre
		else if (css_ascii_equal(value, c"pre") || css_ascii_equal(value, c"pre-wrap")): s.pre = 1
		else if (css_ascii_equal(value, c"normal")): s.pre = 0
	else if (property == 7):
		if (inherit): s.align = inherited.align
		else if (css_ascii_equal(value, c"left") || css_ascii_equal(value, c"start")): s.align = 0
		else if (css_ascii_equal(value, c"center")): s.align = 1
		else if (css_ascii_equal(value, c"right") || css_ascii_equal(value, c"end")): s.align = 2
	else if (property == 8): s.background = win_color(value, s.background)
	else if (property >= 9 && property <= 20):
		int n = win_css_length(t, s.size)
		if (property == 11 && css_kind(t, c"percentage")):
			s.max_width = atoi(value)
			s.max_width_percent = 1
			return
		if (property == 9 && css_kind(t, c"percentage")):
			s.width = atoi(value)
			s.width_percent = 1
			return
		if ((property == 13 || property == 15) && css_ascii_equal(value, c"auto")): n = -2
		else if (n < 0 || n > 100000): return
		if (property == 9):
			s.width = n
			s.width_percent = 0
		else if (property == 10): s.height = n
		else if (property == 11):
			s.max_width = n
			s.max_width_percent = 0
		else if (property == 12): s.margin_top = n
		else if (property == 13): s.margin_right = n
		else if (property == 14): s.margin_bottom = n
		else if (property == 15): s.margin_left = n
		else if (property == 16): s.padding_top = n
		else if (property == 17): s.padding_right = n
		else if (property == 18): s.padding_bottom = n
		else if (property == 19): s.padding_left = n
		else if (property == 20): s.border = n
	else if (property == 21): s.border_color = win_color(value, s.border_color)
	else if (property == 22): s.box_sizing = css_ascii_equal(value, c"border-box")
	else if (property == 27):
		if (css_ascii_equal(value, c"inherit")):
			s.line_height = inherited.line_height
			s.line_height_factor = inherited.line_height_factor
		else if (css_ascii_equal(value, c"normal")):
			s.line_height = 0
			s.line_height_factor = 0.0
		else if (css_kind(t, c"number")):
			s.line_height_factor = win_css_decimal(value)
			s.line_height = 0
		else:
			s.line_height = win_css_length(t, s.size)
			s.line_height_factor = 0.0
	else if (property == 24):
		int n = win_css_length(t, s.size)
		if (n >= 0 && n <= 10000): s.gap = n
	else if (property == 25): s.flex_column = css_ascii_equal(value, c"column")
	else if (property == 23): s.hidden = css_ascii_equal(value, c"hidden") || css_ascii_equal(value, c"collapse")

float32 win_css_decimal(char* value):
	float32 result = 0.0
	float32 scale = 1.0
	int pos = 0
	int sign = 1
	if (value[0] == '-'):
		sign = -1
		pos = 1
	else if (value[0] == '+'): pos = 1
	int decimal = 0
	while (value[pos] != 0):
		int c = value[pos]
		if (c == '.'):
			decimal = 1
		else if (c >= '0' && c <= '9'):
			if (decimal):
				scale = scale / 10.0
				result = result + cast(float32, c - '0') * scale
			else: result = result * 10.0 + cast(float32, c - '0')
		else: break
		pos = pos + 1
	return result * cast(float32, sign)

ui_color win_css_function_color(css_document* css, int first, int last):
	ui_color invalid = ui_color_new(0.0, 0.0, 0.0, -1.0)
	if (css_ascii_equal(css.tokens[first].value, c"rgb") == 0 && css_ascii_equal(css.tokens[first].value, c"rgba") == 0): return invalid
	int open = first + 1
	if (open >= last || css_delim(css.tokens[open], '(') == 0): return invalid
	int close = css.tokens[open].match
	if (close < 0 || close != last - 1): return invalid
	float32[4] values
	values[3] = 1.0
	int count = 0
	for i in range(open + 1, close):
		css_token* t = css.tokens[i]
		if (css_trivia(t) || css_delim(t, ',') || css_delim(t, '/')): continue
		if (count >= 4 || css_kind(t, c"number") == 0 && css_kind(t, c"percentage") == 0): return invalid
		float32 component = win_css_decimal(t.value)
		if (css_kind(t, c"percentage")): component = component / 100.0
		else if (count < 3): component = component / 255.0
		if (component < 0.0): component = 0.0
		if (component > 1.0): component = 1.0
		values[count] = component
		count = count + 1
	if (count < 3): return invalid
	return ui_color_new(values[0], values[1], values[2], values[3])

int win_css_value_valid(int property, css_token* token, int size):
	char* value = token.value
	if (css_ascii_equal(value, c"inherit") && property >= 0 && property <= 7): return 1
	if (property == 0 || property == 8 || property == 21):
		ui_color invalid = ui_color_new(0.0, 0.0, 0.0, -1.0)
		return win_color(value, invalid).a >= 0.0
	if (property == 1):
		int n = win_css_length(token, size)
		if (css_kind(token, c"percentage")): n = size * atoi(value) / 100
		return n >= 8 && n <= 144
	if (property == 2): return css_ascii_equal(value, c"normal") || css_ascii_equal(value, c"bold") || css_ascii_equal(value, c"bolder") || atoi(value) >= 100 && atoi(value) <= 900
	if (property == 3): return css_ascii_equal(value, c"normal") || css_ascii_equal(value, c"italic") || css_ascii_equal(value, c"oblique")
	if (property == 4): return css_ascii_equal(value, c"none") || css_ascii_equal(value, c"underline")
	if (property == 5): return css_ascii_equal(value, c"none") || css_ascii_equal(value, c"block") || css_ascii_equal(value, c"inline") || css_ascii_equal(value, c"inline-block") || css_ascii_equal(value, c"flex") || css_ascii_equal(value, c"grid") || css_ascii_equal(value, c"list-item")
	if (property == 6): return css_ascii_equal(value, c"normal") || css_ascii_equal(value, c"pre") || css_ascii_equal(value, c"pre-wrap")
	if (property == 7): return css_ascii_equal(value, c"left") || css_ascii_equal(value, c"right") || css_ascii_equal(value, c"center") || css_ascii_equal(value, c"start") || css_ascii_equal(value, c"end")
	if (property >= 9 && property <= 20 || property == 24):
		if ((property == 9 || property == 11) && css_kind(token, c"percentage")): return atoi(value) >= 0 && atoi(value) <= 100000
		if ((property == 13 || property == 15) && css_ascii_equal(value, c"auto")): return 1
		int n = win_css_length(token, size)
		return n >= 0 && n <= 100000
	if (property == 22): return css_ascii_equal(value, c"border-box") || css_ascii_equal(value, c"content-box")
	if (property == 23): return css_ascii_equal(value, c"visible") || css_ascii_equal(value, c"hidden") || css_ascii_equal(value, c"collapse")
	if (property == 27): return css_ascii_equal(value, c"normal") || css_ascii_equal(value, c"inherit") || css_kind(token, c"number") && win_css_decimal(value) >= 0.0 && win_css_decimal(value) <= 100.0 || win_css_length(token, size) >= 0
	if (property == 25): return css_ascii_equal(value, c"row") || css_ascii_equal(value, c"column")
	return 1

void win_css_declaration(css_document* css, css_node* d, int priority, int* winners, win_style* style, win_style inherited):
	int first = css_skip(css, d.first, d.last)
	if (first >= d.last): return
	int property = win_css_property(d.name)
	if (property >= 0):
		if ((property == 0 || property == 8 || property == 21) && first + 1 < d.last):
			ui_color color = win_css_function_color(css, first, d.last)
			if (color.a >= 0.0 && priority >= winners[property]):
				if (property == 0): style.color = color
				if (property == 8): style.background = color
				if (property == 21): style.border_color = color
				winners[property] = priority
			return
		if (win_css_value_valid(property, css.tokens[first], inherited.size) == 0): return
		if (property != 26 && css_skip(css, first + 1, d.last) != d.last): return
		if (priority >= winners[property]):
			if (property == 26):
				int columns = 0
				int pos = first
				if (css_ascii_equal(css.tokens[first].value, c"repeat") && first + 2 < d.last):
					columns = atoi(css.tokens[first + 2].value)
				else:
					while (pos < d.last):
						if (css_trivia(css.tokens[pos]) == 0): columns = columns + 1
						pos = css_next_component(css, pos, d.last)
				if (columns >= 1 && columns <= 12): style.columns = columns
			else: win_css_value(style, inherited, property, css.tokens[first])
			winners[property] = priority
		return
	int base = -1
	if (css_ascii_equal(d.name, c"margin")): base = 12
	if (css_ascii_equal(d.name, c"padding")): base = 16
	if (base >= 0):
		int[4] values
		int count = 0
		int pos = first
		while (pos < d.last && count < 4):
			values[count] = pos
			count = count + 1
			pos = css_skip(css, pos + 1, d.last)
		if (pos < d.last): return
		if (count == 1): values[1] = values[0]
		if (count < 3): values[2] = values[0]
		if (count < 4): values[3] = values[1]
		for k in range(4):
			if (win_css_value_valid(base + k, css.tokens[values[k]], style.size) == 0): return
		for k in range(4):
			if (priority >= winners[base + k]):
				win_css_value(style, inherited, base + k, css.tokens[values[k]])
				winners[base + k] = priority
	else if (css_ascii_equal(d.name, c"border")):
		for i in range(first, d.last):
			css_token* t = css.tokens[i]
			if (css_trivia(t)): continue
			int prop = 21
			if (win_css_length(t, style.size) >= 0): prop = 20
			if (css_ascii_equal(t.value, c"none")):
				if (priority >= winners[20]):
					style.border = 0
					winners[20] = priority
			else if (win_css_value_valid(prop, t, style.size) && priority >= winners[prop]):
				win_css_value(style, inherited, prop, t)
				winners[prop] = priority

int win_css_media(css_document* css, css_node* rule, int width):
	# Support screen/all and min/max-width conjunctions. Unknown media queries
	# are false, so print styles and unsupported conditions never leak in.
	int pos = rule.first
	while (pos < rule.last):
		css_token* t = css.tokens[pos]
		if (css_trivia(t)):
			pos = pos + 1
			continue
		if (css_kind(t, c"ident")):
			if (css_ascii_equal(t.value, c"screen") == 0 && css_ascii_equal(t.value, c"all") == 0 && css_ascii_equal(t.value, c"and") == 0 && css_ascii_equal(t.value, c"only") == 0): return 0
		else if (css_delim(t, '(')):
			int close = t.match
			if (close < 0): return 0
			int key = css_skip(css, pos + 1, close)
			int colon = css_skip(css, key + 1, close)
			int val = css_skip(css, colon + 1, close)
			if (val >= close || css_delim(css.tokens[colon], ':') == 0): return 0
			int n = win_css_length(css.tokens[val], 18)
			if (n < 0): return 0
			if (css_ascii_equal(css.tokens[key].value, c"min-width")):
				if (width < n): return 0
			else if (css_ascii_equal(css.tokens[key].value, c"max-width")):
				if (width > n): return 0
			else: return 0
			pos = close
		else: return 0
		pos = pos + 1
	return 1

void win_css_rules(css_document* css, list[css_node*] rules, html_node* node, int width, int* winners, win_style* style, win_style inherited):
	for i in range(rules.length):
		css_node* rule = rules[i]
		if (strcmp(rule.kind, c"at-rule") == 0):
			if (css_ascii_equal(rule.name, c"media") && win_css_media(css, rule, width)): win_css_rules(css, rule.children, node, width, winners, style, inherited)
			continue
		if (strcmp(rule.kind, c"qualified-rule") != 0): continue
		int specificity = -1
		for j in range(rule.children.length):
			css_node* selector = rule.children[j]
			if (strcmp(selector.kind, c"selector") != 0): continue
			int score = win_selector_match(css, selector.first, selector.last, node)
			if (score > specificity): specificity = score
		if (specificity < 0): continue
		for j in range(rule.children.length):
			css_node* d = rule.children[j]
			if (strcmp(d.kind, c"declaration") == 0): win_css_declaration(css, d, specificity + d.important * 10000000, winners, style, inherited)
