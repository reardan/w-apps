# Selector matching and lexicographic specificity; no scalar score packing.
import libs.extras.html.html
import libs.extras.css.css

struct win_specificity:
	int ids
	int classes
	int types

win_specificity win_specificity_zero():
	win_specificity result
	result.ids = 0
	result.classes = 0
	result.types = 0
	return result

int win_specificity_compare(win_specificity a, win_specificity b):
	if (a.ids != b.ids): return a.ids - b.ids
	if (a.classes != b.classes): return a.classes - b.classes
	return a.types - b.types

win_specificity win_specificity_add(win_specificity a, win_specificity b):
	a.ids = a.ids + b.ids
	a.classes = a.classes + b.classes
	a.types = a.types + b.types
	return a

# Installed only for synchronous DOM queries; stylesheet matching uses no JS
# budget. Nested filters/combinators must charge work as well as DOM traversal.
int* win_selector_budget

int win_selector_step():
	if (win_selector_budget == 0): return 1
	if (win_selector_budget[0] <= 0): return 0
	win_selector_budget[0] = win_selector_budget[0] - 1
	return 1

char* win_attr(html_node* node, char* name):
	html_attribute* attr = html_attribute_find(node.attributes, name)
	if (attr == 0): return c""
	return attr.value

int win_tag(html_node* node, char* name):
	return node.kind == HTML_START && strcmp(node.name, name) == 0

# HTML disabled state is restricted to controls; disabled fieldsets exempt
# descendants of their first legend. Options also inherit from optgroups.
int win_control_disabled(html_node* node):
	if (win_tag(node, c"option")):
		if (html_attribute_find(node.attributes, c"disabled") != 0): return 1
		return node.parent != 0 && win_tag(node.parent, c"optgroup") && html_attribute_find(node.parent.attributes, c"disabled") != 0
	if (win_tag(node, c"optgroup")): return html_attribute_find(node.attributes, c"disabled") != 0
	if (win_tag(node, c"input") == 0 && win_tag(node, c"button") == 0 && win_tag(node, c"select") == 0 && win_tag(node, c"textarea") == 0 && win_tag(node, c"fieldset") == 0): return 0
	if (html_attribute_find(node.attributes, c"disabled") != 0): return 1
	html_node* ancestor = node.parent
	while (ancestor != 0):
		if (win_selector_step() == 0): return 0
		if (win_tag(ancestor, c"fieldset") && html_attribute_find(ancestor.attributes, c"disabled") != 0):
			html_node* legend = ancestor.first_child
			while (legend != 0 && win_tag(legend, c"legend") == 0): legend = legend.next_sibling
			html_node* child = node
			while (child != 0 && child != ancestor && child != legend): child = child.parent
			if (child != legend || legend == 0): return 1
		ancestor = ancestor.parent
	return 0

int win_control_checked(html_node* node):
	if (win_tag(node, c"option")): return html_attribute_find(node.attributes, c"selected") != 0
	if (win_tag(node, c"input") == 0): return 0
	char* type = win_attr(node, c"type")
	return (css_ascii_equal(type, c"checkbox") || css_ascii_equal(type, c"radio")) && html_attribute_find(node.attributes, c"checked") != 0

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
			if (t.hash_id == 0): return 0
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

win_specificity win_selector_specificity(css_document* css, int first, int last);

# Only validated branches reach this scanner. Invalid forgiving branches can
# contain punctuation that would otherwise corrupt both scoring and list splits.
win_specificity win_selector_branch_specificity(css_document* css, int first, int last):
	win_specificity score = win_specificity_zero()
	int pos = first
	while (pos < last):
		if (win_selector_step() == 0): return win_specificity_zero()
		css_token* t = css.tokens[pos]
		if (css_kind(t, c"hash")): score.ids = score.ids + 1
		else if (css_delim(t, '.')):
			score.classes = score.classes + 1
			pos = pos + 1
		else if (css_delim(t, '[')):
			score.classes = score.classes + 1
			pos = css_next_component(css, pos, last)
			continue
		else if (css_delim(t, ':')):
			pos = pos + 1
			char* pseudo = css.tokens[pos].value
			if (pos + 1 < last && css_delim(css.tokens[pos + 1], '(')):
				int close = css.tokens[pos + 1].match
				if (css_ascii_equal(pseudo, c"not") || css_ascii_equal(pseudo, c"is")): score = win_specificity_add(score, win_selector_specificity(css, pos + 2, close))
				else if (css_ascii_equal(pseudo, c"where") == 0):
					score.classes = score.classes + 1
					if (css_ascii_equal(pseudo, c"nth-child") || css_ascii_equal(pseudo, c"nth-last-child")):
						int filter = win_nth_filter(css, pos + 2, close)
						if (filter < close): score = win_specificity_add(score, win_selector_specificity(css, filter + 1, close))
				pos = close
			else: score.classes = score.classes + 1
		else if (css_kind(t, c"ident")): score.types = score.types + 1
		pos = pos + 1
	return score

win_specificity win_selector_specificity(css_document* css, int first, int last):
	win_specificity maximum = win_specificity_zero()
	int start = first
	int end = first
	while (end <= last):
		if (win_selector_step() == 0): return win_specificity_zero()
		if (end == last || css_delim(css.tokens[end], ',')):
			if (win_selector_valid(css, start, end)):
				win_specificity score = win_selector_branch_specificity(css, start, end)
				if (win_specificity_compare(score, maximum) > 0): maximum = score
			start = end + 1
			end = end + 1
		else: end = css_next_component(css, end, last)
	return maximum

# Matching returns 0 on success, -1 on mismatch; specificity is a separate tuple.
int win_selector_compound(css_document* css, int first, int last, html_node* node):
	if (node == 0 || node.kind != HTML_START): return -1
	int pos = first
	while (pos < last):
		if (win_selector_step() == 0): return -1
		css_token* t = css.tokens[pos]
		if (css_kind(t, c"comment")):
			pos = pos + 1
			continue
		if (css_kind(t, c"ident")):
			if (css_ascii_equal(t.value, node.name) == 0): return -1
		else if (css_kind(t, c"hash")):
			if (strcmp(win_attr(node, c"id"), t.value) != 0): return -1
		else if (css_delim(t, '.')):
			pos = pos + 1
			if (pos >= last || css_kind(css.tokens[pos], c"ident") == 0): return -1
			if (win_class_has(win_attr(node, c"class"), css.tokens[pos].value) == 0): return -1
		else if (css_delim(t, '[')):
			if (win_attribute_selector(css, pos, last, node) != 1): return -1
			pos = t.match
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
				while (end <= close):
					if (end == close || css_delim(css.tokens[end], ',')):
						int nested = win_selector_match(css, start, end, node)
						if (nested >= 0): matched = 1
						start = end + 1
						end = end + 1
					else: end = css_next_component(css, end, close)
				if (css_ascii_equal(pseudo, c"not")):
					if (matched): return -1
				else if (matched == 0): return -1
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
				if ((win_tag(node, c"a") == 0 && win_tag(node, c"area") == 0) || html_attribute_find(node.attributes, c"href") == 0): return -1
			else if (css_ascii_equal(pseudo, c"disabled")):
				if (win_control_disabled(node) == 0): return -1
			else if (css_ascii_equal(pseudo, c"checked")):
				if (win_control_checked(node) == 0): return -1
			else: return -1
		else if (css_delim(t, '*') == 0): return -1
		pos = pos + 1
	return 0

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
		if (score >= 0): return 0
		if (comb == '>' || comb == '+'): return -1
		if (comb == '~'): candidate = win_previous_element(candidate)
		else: candidate = candidate.parent
	return -1

int win_selector_matches(html_node* node, char* selector):
	css_document* css = css_parse_selectors_n(selector, strlen(selector), 0)
	int found = 0
	if (css.failed == 0 && win_selector_list_valid(css, 0, css.tokens.length)):
		found = win_selector_list_match(css, 0, css.tokens.length, node) >= 0
	css_document_free(css)
	return found

