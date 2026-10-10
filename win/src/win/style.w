# Author CSS cascade and block-flow styling. Unsupported syntax never matches.
import libs.extras.html.html
import libs.extras.css.css
import graphics.ui.text
import lib.format
import lib.fmath

# Installed only for synchronous DOM queries; stylesheet matching uses no JS
# budget. Nested filters/combinators must charge work as well as DOM traversal.
int* win_selector_budget

int win_selector_step():
	if (win_selector_budget == 0): return 1
	if (win_selector_budget[0] <= 0): return 0
	win_selector_budget[0] = win_selector_budget[0] - 1
	return 1

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
	int border_width
	int border_style
	int border_current_color
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
	s.border_width = 3
	s.border_style = 0
	s.border_current_color = 1
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
		if (win_selector_step() == 0): return 0
		if (child.kind == HTML_START): prev = child
		child = child.next_sibling
	return prev

# Attribute comparison is ASCII case-insensitive only when explicitly requested.
int win_selector_equal(char* left, char* right, int count, int insensitive):
	for i in range(count):
		int a = left[i] & 255
		int b = right[i] & 255
		if (insensitive):
			if (a >= 'A' && a <= 'Z'): a = a + 32
			if (b >= 'A' && b <= 'Z'): b = b + 32
		if (a != b): return 0
	return 1

int win_attribute_matches(char* actual, char* expected, int op, int insensitive):
	int length = strlen(actual)
	int count = strlen(expected)
	if (op == '='): return length == count && win_selector_equal(actual, expected, count, insensitive)
	if (op == '|'):
		return length >= count && win_selector_equal(actual, expected, count, insensitive) && (length == count || actual[count] == '-')
	# Empty substring and word operands never match.
	if (count == 0 || count > length): return 0
	if (op == '^'): return win_selector_equal(actual, expected, count, insensitive)
	if (op == '$'): return win_selector_equal(actual + length - count, expected, count, insensitive)
	if (op == '*'):
		for i in range(length - count + 1):
			if (win_selector_equal(actual + i, expected, count, insensitive)): return 1
		return 0
	if (op == '~'):
		for i in range(count):
			if (css_space(expected[i])): return 0
		int pos = 0
		while (pos < length):
			while (pos < length && css_space(actual[pos])): pos = pos + 1
			int start = pos
			while (pos < length && css_space(actual[pos]) == 0): pos = pos + 1
			if (pos - start == count && win_selector_equal(actual + start, expected, count, insensitive)): return 1
	return 0

# Count element siblings, optionally restricting the count to this element's type.
int win_sibling_index(html_node* node, int reverse, int of_type):
	int index = 1
	html_node* sibling = node.next_sibling
	if (reverse == 0):
		if (node.parent == 0): return 1
		sibling = node.parent.first_child
	while (sibling != 0):
		if (win_selector_step() == 0): return 0
		if (reverse == 0 && sibling == node): break
		if (sibling.kind == HTML_START && (of_type == 0 || css_ascii_equal(sibling.name, node.name))): index = index + 1
		sibling = sibling.next_sibling
	return index

# Parse the integer An+B grammar without atoi's partial-number acceptance.
# Coefficients are bounded to one billion to keep index arithmetic safe.
int win_nth_expression(char* expression, int index):
	int pos = 0
	while (css_space(expression[pos])): pos = pos + 1
	int end = strlen(expression)
	while (end > pos && css_space(expression[end - 1])): end = end - 1
	if (end - pos == 3 && win_selector_equal(expression + pos, c"odd", 3, 1)): return index % 2 == 1
	if (end - pos == 4 && win_selector_equal(expression + pos, c"even", 4, 1)): return index % 2 == 0
	int sign = 1
	if (expression[pos] == '+' || expression[pos] == '-'):
		if (expression[pos] == '-'): sign = -1
		pos = pos + 1
	int number = 0
	int digits = 0
	while (pos < end && css_digit(expression[pos])):
		int digit = expression[pos] - '0'
		if (number > (1000000000 - digit) / 10): return -1
		number = number * 10 + digit
		digits = digits + 1
		pos = pos + 1
	if (pos == end):
		if (digits == 0): return -1
		return index == sign * number
	if (expression[pos] != 'n' && expression[pos] != 'N'): return -1
	if (digits == 0): number = 1
	int coefficient = sign * number
	pos = pos + 1
	while (pos < end && css_space(expression[pos])): pos = pos + 1
	int offset = 0
	if (pos < end):
		sign = 1
		if (expression[pos] != '+' && expression[pos] != '-'): return -1
		if (expression[pos] == '-'): sign = -1
		pos = pos + 1
		while (pos < end && css_space(expression[pos])): pos = pos + 1
		digits = 0
		while (pos < end && css_digit(expression[pos])):
			int digit = expression[pos] - '0'
			if (offset > (1000000000 - digit) / 10): return -1
			offset = offset * 10 + digit
			digits = digits + 1
			pos = pos + 1
		if (digits == 0 || pos != end): return -1
		offset = sign * offset
	if (coefficient == 0): return index == offset
	int difference = index - offset
	return difference % coefficient == 0 && difference / coefficient >= 0

# Escapes decode inside identifiers; they must not manufacture signs or an
# integer coefficient that the token grammar does not permit.
int win_nth_token(css_token* token):
	char* value = token.value
	if (css_kind(token, c"ident") && (css_ascii_equal(value, c"odd") || css_ascii_equal(value, c"even"))): return 1
	int pos = 0
	if (css_kind(token, c"number") || css_kind(token, c"dimension")):
		if (value[pos] == '+' || value[pos] == '-'): pos = pos + 1
		int start = pos
		while (css_digit(value[pos])): pos = pos + 1
		if (pos == start): return 0
		if (css_kind(token, c"number")): return value[pos] == 0
	else if (css_kind(token, c"ident")):
		if (value[pos] == '-'): pos = pos + 1
	else: return 0
	if (value[pos] != 'n' && value[pos] != 'N'): return 0
	pos = pos + 1
	if (value[pos] == '-'):
		pos = pos + 1
		while (css_digit(value[pos])): pos = pos + 1
	return value[pos] == 0

int win_nth_matches(css_document* css, int first, int last, int index):
	string_builder* expression = string_new()
	int valid = 1
	for i in range(first, last):
		css_token* t = css.tokens[i]
		if (css_kind(t, c"space") || css_kind(t, c"comment")): string_append_char(expression, ' ')
		else if (win_nth_token(t) || css_delim(t, '+') || css_delim(t, '-')): string_append(expression, t.value)
		else: valid = 0
	int matched = -1
	if (valid): matched = win_nth_expression(expression.data, index)
	string_free(expression)
	return matched

# Return -2 for malformed syntax, -1 for a mismatch, and 1 for a match.
# A null node requests syntax validation only.
int win_attribute_selector(css_document* css, int pos, int last, html_node* node):
	int close = css.tokens[pos].match
	if (close < pos || close >= last): return -2
	int key = css_skip(css, pos + 1, close)
	if (key >= close || css_kind(css.tokens[key], c"ident") == 0): return -2
	html_attribute* attr = 0
	if (node != 0):
		attr = node.attributes
		while (attr != 0 && css_ascii_equal(css.tokens[key].value, attr.name) == 0): attr = attr.next
	int op = css_skip(css, key + 1, close)
	if (op < close):
		int operator = css.tokens[op].value[0]
		if (css_delim(css.tokens[op], '=') == 0):
			if (css_delim(css.tokens[op], '~') == 0 && css_delim(css.tokens[op], '|') == 0 && css_delim(css.tokens[op], '^') == 0 && css_delim(css.tokens[op], '$') == 0 && css_delim(css.tokens[op], '*') == 0): return -2
			op = op + 1
			if (op >= close || css_delim(css.tokens[op], '=') == 0): return -2
		int value = css_skip(css, op + 1, close)
		if (value >= close || (css_kind(css.tokens[value], c"string") == 0 && css_kind(css.tokens[value], c"ident") == 0)): return -2
		int flag = css_skip(css, value + 1, close)
		int insensitive = 0
		if (flag < close):
			if (css_kind(css.tokens[flag], c"ident") == 0 || css_skip(css, flag + 1, close) != close): return -2
			if (css_ascii_equal(css.tokens[flag].value, c"i")): insensitive = 1
			else if (css_ascii_equal(css.tokens[flag].value, c"s") == 0): return -2
		if (node != 0):
			if (attr == 0 || win_attribute_matches(attr.value, css.tokens[value].value, operator, insensitive) == 0): return -1
	if (node != 0 && attr == 0): return -1
	return 1

int win_selector_match(css_document* css, int first, int last, html_node* node);
int win_selector_valid(css_document* css, int first, int last);

# Only :is() and :where() use forgiving lists. Ordinary lists, :not(), and
# nth-child's filter reject the entire list if any branch is invalid.
int win_selector_list_valid(css_document* css, int first, int last):
	int start = first
	int end = first
	while (end <= last):
		if (win_selector_step() == 0): return 0
		if (end == last || css_delim(css.tokens[end], ',')):
			if (win_selector_valid(css, start, end) == 0): return 0
			start = end + 1
			end = end + 1
		else: end = css_next_component(css, end, last)
	return 1

int win_selector_list_match(css_document* css, int first, int last, html_node* node):
	int start = first
	int end = first
	int maximum = -1
	while (end <= last):
		if (win_selector_step() == 0): return -1
		if (end == last || css_delim(css.tokens[end], ',')):
			int score = win_selector_match(css, start, end, node)
			if (score > maximum): maximum = score
			start = end + 1
			end = end + 1
		else: end = css_next_component(css, end, last)
	return maximum

# Locate the optional filter without looking inside nested components.
int win_nth_filter(css_document* css, int first, int last):
	int pos = first
	while (pos < last):
		if (css_kind(css.tokens[pos], c"ident") && css_ascii_equal(css.tokens[pos].value, c"of")): return pos
		pos = css_next_component(css, pos, last)
	return last

int win_filtered_sibling_index(css_document* css, int first, int last, html_node* node, int reverse):
	if (win_selector_list_match(css, first, last, node) < 0): return 0
	int index = 1
	html_node* sibling = node.next_sibling
	if (reverse == 0):
		if (node.parent == 0): return 1
		sibling = node.parent.first_child
	while (sibling != 0):
		if (win_selector_step() == 0): return 0
		if (reverse == 0 && sibling == node): break
		if (sibling.kind == HTML_START && win_selector_list_match(css, first, last, sibling) >= 0): index = index + 1
		sibling = sibling.next_sibling
	return index

# Validate every branch before matching: unsupported syntax inside :not() must
# not turn into a successful negation. Commas are handled by the owning list.
int win_selector_valid(css_document* css, int first, int last):
	int pos = css_skip(css, first, last)
	last = css_trim(css, pos, last)
	int compound = 0
	int type_allowed = 1
	while (pos < last):
		if (win_selector_step() == 0): return 0
		css_token* t = css.tokens[pos]
		if (css_kind(t, c"comment")):
			pos = pos + 1
			continue
		if (css_kind(t, c"space")):
			pos = css_skip(css, pos + 1, last)
			if (pos < last && (css_delim(css.tokens[pos], '>') || css_delim(css.tokens[pos], '+') || css_delim(css.tokens[pos], '~'))): continue
			compound = 0
			type_allowed = 1
			continue
		if (css_delim(t, '>') || css_delim(t, '+') || css_delim(t, '~')):
			if (compound == 0): return 0
			compound = 0
			type_allowed = 1
			pos = css_skip(css, pos + 1, last)
			continue
		if (css_kind(t, c"ident") || css_delim(t, '*')):
			if (type_allowed == 0): return 0
		else if (css_kind(t, c"hash")):
			if (t.value[0] == 0): return 0
		else if (css_delim(t, '.')):
			pos = pos + 1
			if (pos >= last || css_kind(css.tokens[pos], c"ident") == 0): return 0
		else if (css_delim(t, '[')):
			if (win_attribute_selector(css, pos, last, 0) != 1): return 0
			pos = t.match
		else if (css_delim(t, ':')):
			pos = pos + 1
			if (pos >= last || css_kind(css.tokens[pos], c"ident") == 0): return 0
			char* pseudo = css.tokens[pos].value
			if (css_ascii_equal(pseudo, c"not") || css_ascii_equal(pseudo, c"is") || css_ascii_equal(pseudo, c"where")):
				int open = pos + 1
				if (open >= last || css_delim(css.tokens[open], '(') == 0): return 0
				int close = css.tokens[open].match
				if (close < open || close >= last): return 0
				if (css_ascii_equal(pseudo, c"not") && win_selector_list_valid(css, open + 1, close) == 0): return 0
				pos = close
			else if (css_ascii_equal(pseudo, c"nth-child") || css_ascii_equal(pseudo, c"nth-last-child") || css_ascii_equal(pseudo, c"nth-of-type") || css_ascii_equal(pseudo, c"nth-last-of-type")):
				int open = pos + 1
				if (open >= last || css_delim(css.tokens[open], '(') == 0): return 0
				int close = css.tokens[open].match
				if (close < open || close >= last): return 0
				int filter = win_nth_filter(css, open + 1, close)
				if (win_nth_matches(css, open + 1, filter, 1) < 0): return 0
				if (filter < close):
					if (css_ascii_equal(pseudo, c"nth-of-type") || css_ascii_equal(pseudo, c"nth-last-of-type")): return 0
					if (win_selector_list_valid(css, filter + 1, close) == 0): return 0
				pos = close
			else if (css_ascii_equal(pseudo, c"root") == 0 && css_ascii_equal(pseudo, c"first-child") == 0 && css_ascii_equal(pseudo, c"last-child") == 0 && css_ascii_equal(pseudo, c"only-child") == 0 && css_ascii_equal(pseudo, c"first-of-type") == 0 && css_ascii_equal(pseudo, c"last-of-type") == 0 && css_ascii_equal(pseudo, c"only-of-type") == 0 && css_ascii_equal(pseudo, c"link") == 0 && css_ascii_equal(pseudo, c"checked") == 0 && css_ascii_equal(pseudo, c"disabled") == 0): return 0
		else: return 0
		compound = 1
		type_allowed = 0
		pos = pos + 1
	return compound

int win_selector_specificity(css_document* css, int first, int last);

# Only validated branches reach this scanner. Invalid forgiving branches can
# contain punctuation that would otherwise corrupt both scoring and list splits.
int win_selector_branch_specificity(css_document* css, int first, int last):
	int score = 0
	int pos = first
	while (pos < last):
		if (win_selector_step() == 0): return 0
		css_token* t = css.tokens[pos]
		if (css_kind(t, c"hash")): score = score + 10000
		else if (css_delim(t, '.')):
			score = score + 100
			pos = pos + 1
		else if (css_delim(t, '[')):
			score = score + 100
			pos = css_next_component(css, pos, last)
			continue
		else if (css_delim(t, ':')):
			pos = pos + 1
			char* pseudo = css.tokens[pos].value
			if (pos + 1 < last && css_delim(css.tokens[pos + 1], '(')):
				int close = css.tokens[pos + 1].match
				if (css_ascii_equal(pseudo, c"not") || css_ascii_equal(pseudo, c"is")): score = score + win_selector_specificity(css, pos + 2, close)
				else if (css_ascii_equal(pseudo, c"where") == 0):
					score = score + 100
					if (css_ascii_equal(pseudo, c"nth-child") || css_ascii_equal(pseudo, c"nth-last-child")):
						int filter = win_nth_filter(css, pos + 2, close)
						if (filter < close): score = score + win_selector_specificity(css, filter + 1, close)
				pos = close
			else: score = score + 100
		else if (css_kind(t, c"ident")): score = score + 1
		pos = pos + 1
	return score

int win_selector_specificity(css_document* css, int first, int last):
	int maximum = 0
	int start = first
	int end = first
	while (end <= last):
		if (win_selector_step() == 0): return 0
		if (end == last || css_delim(css.tokens[end], ',')):
			if (win_selector_valid(css, start, end)):
				int score = win_selector_branch_specificity(css, start, end)
				if (score > maximum): maximum = score
			start = end + 1
			end = end + 1
		else: end = css_next_component(css, end, last)
	return maximum

# Specificity is bounded by parser depth; -1 means no match.
int win_selector_compound(css_document* css, int first, int last, html_node* node):
	if (node == 0 || node.kind != HTML_START): return -1
	int score = 0
	int pos = first
	while (pos < last):
		if (win_selector_step() == 0): return -1
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
			if (win_attribute_selector(css, pos, last, node) != 1): return -1
			pos = t.match
			score = score + 100
		else if (css_delim(t, ':')):
			pos = pos + 1
			if (pos >= last): return -1
			char* pseudo = css.tokens[pos].value
			if (css_ascii_equal(pseudo, c"not") || css_ascii_equal(pseudo, c"is") || css_ascii_equal(pseudo, c"where")):
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
				if (css_ascii_equal(pseudo, c"not")):
					if (matched): return -1
					specificity = 100
				else if (matched == 0): return -1
				if (css_ascii_equal(pseudo, c"where")): specificity = 0
				score = score + specificity
				pos = close + 1
				continue
			if (css_ascii_equal(pseudo, c"nth-child") || css_ascii_equal(pseudo, c"nth-last-child") || css_ascii_equal(pseudo, c"nth-of-type") || css_ascii_equal(pseudo, c"nth-last-of-type")):
				int open = pos + 1
				if (open >= last || css_delim(css.tokens[open], '(') == 0): return -1
				int close = css.tokens[open].match
				if (close < 0 || close >= last): return -1
				int reverse = css_ascii_equal(pseudo, c"nth-last-child") || css_ascii_equal(pseudo, c"nth-last-of-type")
				int of_type = css_ascii_equal(pseudo, c"nth-of-type") || css_ascii_equal(pseudo, c"nth-last-of-type")
				int filter = win_nth_filter(css, open + 1, close)
				int index = 0
				if (filter < close): index = win_filtered_sibling_index(css, filter + 1, close, node, reverse)
				else: index = win_sibling_index(node, reverse, of_type)
				if (index == 0 || win_nth_matches(css, open + 1, filter, index) != 1): return -1
				pos = close
			else if (css_ascii_equal(pseudo, c"root")):
				if (node.parent != 0 && node.parent.kind != HTML_DOCUMENT): return -1
			else if (css_ascii_equal(pseudo, c"first-child")):
				if (win_sibling_index(node, 0, 0) != 1): return -1
			else if (css_ascii_equal(pseudo, c"last-child")):
				if (win_sibling_index(node, 1, 0) != 1): return -1
			else if (css_ascii_equal(pseudo, c"only-child")):
				if (win_sibling_index(node, 0, 0) != 1 || win_sibling_index(node, 1, 0) != 1): return -1
			else if (css_ascii_equal(pseudo, c"first-of-type")):
				if (win_sibling_index(node, 0, 1) != 1): return -1
			else if (css_ascii_equal(pseudo, c"last-of-type")):
				if (win_sibling_index(node, 1, 1) != 1): return -1
			else if (css_ascii_equal(pseudo, c"only-of-type")):
				if (win_sibling_index(node, 0, 1) != 1 || win_sibling_index(node, 1, 1) != 1): return -1
			else if (css_ascii_equal(pseudo, c"link")):
				if (win_tag(node, c"a") == 0 || win_attr(node, c"href")[0] == 0): return -1
			else if (css_ascii_equal(pseudo, c"disabled")):
				if (html_attribute_find(node.attributes, c"disabled") == 0): return -1
			else if (css_ascii_equal(pseudo, c"checked")):
				if (html_attribute_find(node.attributes, c"checked") == 0): return -1
			else: return -1
			score = score + 100
		else if (css_delim(t, '*') == 0): return -1
		pos = pos + 1
	return win_selector_specificity(css, first, last)

int win_selector_match(css_document* css, int first, int last, html_node* node):
	if (win_selector_valid(css, first, last) == 0): return -1
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
	if (css.failed == 0 && win_selector_list_valid(css, 0, css.tokens.length)):
		found = win_selector_list_match(css, 0, css.tokens.length, node) >= 0
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
	if (css_ascii_equal(name, c"border-style")): return 28
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
		else if (property == 20): s.border_width = n
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

int win_css_value_valid(int property, css_token* token, int size):
	char* value = token.value
	if (css_kind(token, c"ident") && css_ascii_equal(value, c"inherit") && property >= 0 && property <= 7): return 1
	if (property == 0 || property == 8 || property == 21):
		ui_color invalid = ui_color_new(0.0, 0.0, 0.0, -1.0)
		if (css_kind(token, c"hash")):
			int n = strlen(value)
			if (n != 3 && n != 4 && n != 6 && n != 8): return 0
			for i in range(n):
				if (win_hex(value[i]) < 0): return 0
		else:
			if (css_kind(token, c"ident") == 0): return 0
			int hex = 1
			for i in range(strlen(value)):
				if (win_hex(value[i]) < 0): hex = 0
			if (hex): return 0
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
	if (property == 28): return css_kind(token, c"ident") && (css_ascii_equal(value, c"none") || css_ascii_equal(value, c"hidden") || css_ascii_equal(value, c"solid"))
	return 1

# Resolve used border values after the entire cascade, so currentColor tracks
# color regardless of declaration order and width remains independent of style.
void win_css_resolve_border(win_style* style):
	style.border = 0
	if (style.border_style): style.border = style.border_width
	if (style.border_current_color): style.border_color = style.color

int win_css_border_width(css_document* css, css_token* token, int size):
	if (css_kind(token, c"ident")):
		if (css_ascii_equal(token.value, c"thin")): return 1
		if (css_ascii_equal(token.value, c"medium")): return 3
		if (css_ascii_equal(token.value, c"thick")): return 5
		return -1
	if (css_kind(token, c"number") == 0 && css_kind(token, c"dimension") == 0): return -1
	int consumed = 0
	float32 value = parse_float(token.value, &consumed)
	if (consumed == 0 || consumed != css_number_end(css, token.start) - token.start || fis_nan(value) || value < 0.0): return -1
	if (css_kind(token, c"number")):
		if (value == 0.0): return 0
		return -1
	char* unit = token.value + consumed
	if (css_ascii_equal(unit, c"em")): value = value * cast(float32, size)
	else if (css_ascii_equal(unit, c"rem")): value = value * 18.0
	else if (css_ascii_equal(unit, c"px") == 0): return -1
	if (value > 100000.0): return -1
	return cast(int, value)

# The supported uniform border shorthand is parsed atomically. Invalid trailing
# tokens or duplicate components cannot partially replace earlier longhands.
void win_css_border(css_document* css, int first, int last, int priority, int* winners, win_style* style):
	int width = 3
	int visible = 0
	int current = 1
	ui_color color = style.color
	int have_width = 0
	int have_style = 0
	int have_color = 0
	int pos = first
	while (pos < last):
		css_token* t = css.tokens[pos]
		int end = pos + 1
		if (end < last && css_delim(css.tokens[end], '(')):
			end = css_next_component(css, end, last)
			ui_color parsed = win_css_function_color(css, pos, end)
			if (have_color || parsed.a < 0.0): return
			color = parsed
			current = 0
			have_color = 1
		else if (win_css_value_valid(28, t, style.size)):
			if (have_style): return
			visible = css_ascii_equal(t.value, c"solid")
			have_style = 1
		else if (win_css_border_width(css, t, style.size) >= 0):
			if (have_width): return
			width = win_css_border_width(css, t, style.size)
			have_width = 1
		else:
			if (have_color): return
			if (css_kind(t, c"ident") && css_ascii_equal(t.value, c"currentcolor")): current = 1
			else:
				if (win_css_value_valid(21, t, style.size) == 0): return
				color = win_color(t.value, color)
				current = 0
			have_color = 1
		pos = css_skip(css, end, last)
	if (priority >= winners[20]):
		style.border_width = width
		winners[20] = priority
	if (priority >= winners[28]):
		style.border_style = visible
		winners[28] = priority
	if (priority >= winners[21]):
		style.border_color = color
		style.border_current_color = current
		winners[21] = priority

void win_css_declaration(css_document* css, css_node* d, int priority, int* winners, win_style* style, win_style inherited):
	int first = css_skip(css, d.first, d.last)
	if (first >= d.last): return
	int property = win_css_property(d.name)
	if (property >= 0):
		if (property == 20):
			int width = win_css_border_width(css, css.tokens[first], style.size)
			if (width >= 0 && css_skip(css, first + 1, d.last) == d.last && priority >= winners[20]):
				style.border_width = width
				winners[20] = priority
			return
		if (property == 21 && css_skip(css, first + 1, d.last) == d.last && css_kind(css.tokens[first], c"ident") && css_ascii_equal(css.tokens[first].value, c"currentcolor")):
			if (priority >= winners[21]):
				style.border_current_color = 1
				winners[21] = priority
			return
		if ((property == 0 || property == 8 || property == 21) && first + 1 < d.last):
			ui_color color = win_css_function_color(css, first, d.last)
			if (color.a >= 0.0 && priority >= winners[property]):
				if (property == 0): style.color = color
				if (property == 8): style.background = color
				if (property == 21):
					style.border_color = color
					style.border_current_color = 0
				winners[property] = priority
			return
		if (win_css_value_valid(property, css.tokens[first], inherited.size) == 0): return
		if (property != 26 && css_skip(css, first + 1, d.last) != d.last): return
		if (priority >= winners[property]):
			if (property == 21): style.border_current_color = 0
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
			else if (property == 28): style.border_style = css_ascii_equal(css.tokens[first].value, c"solid")
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
		win_css_border(css, first, d.last, priority, winners, style)

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
		if (win_selector_list_valid(css, rule.first, rule.last) == 0): continue
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
