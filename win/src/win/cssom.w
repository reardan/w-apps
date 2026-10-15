# Inline declaration operations for the supported CSS property set. Values stay
# specified (not computed); validation is shared with the stylesheet cascade.
import win.style

char* win_cssom_name(char* name):
	string_builder* result = string_new()
	for i in range(strlen(name)):
		int c = name[i] & 255
		if (c >= 'A' && c <= 'Z'): c = c + 32
		string_append_char(result, c)
	char* text = result.data
	free(result)
	return text

int win_cssom_equal(char* a, char* b):
	int pos = 0
	while (a[pos] != 0 && b[pos] != 0):
		int left = a[pos] & 255
		int right = b[pos] & 255
		if (left >= 'A' && left <= 'Z'): left = left + 32
		if (right >= 'A' && right <= 'Z'): right = right + 32
		if (left != right): return 0
		pos = pos + 1
	return a[pos] == b[pos]

char* win_cssom_value(css_document* css, css_node* declaration):
	int first = css_skip(css, declaration.first, declaration.last)
	int last = css_trim(css, first, declaration.last)
	if (first == last): return strclone(c"")
	return substring(css.source, css.tokens[first].start, css.tokens[last - 1].end)

# The cascade already validates and expands the supported shorthands. Keep its
# specified token ranges here, rather than computing lengths or comparing only
# declaration names (which would lose shorthand/longhand relationships).
void win_cssom_collect(css_document* css, win_css_specified* winners):
	for i in range(33): winners[i].present = 0
	if (css.failed): return
	for i in range(css.nodes.length):
		css_node* d = css.nodes[i]
		win_css_collect(css, d, win_cascade_author(d.important, 0, win_specificity_zero(), i), winners)

int win_cssom_contains(char* name, int property):
	if (win_css_property(name) == property): return 1
	if (win_cssom_equal(name, c"margin")): return property >= 12 && property <= 15
	if (win_cssom_equal(name, c"padding")): return property >= 16 && property <= 19
	if (win_cssom_equal(name, c"flex")): return property >= 29 && property <= 31
	if (win_cssom_equal(name, c"border")): return property == 20 || property == 21 || property == 28
	return 0

char* win_cssom_longhand(int property):
	if (property == 12): return c"margin-top"
	if (property == 13): return c"margin-right"
	if (property == 14): return c"margin-bottom"
	if (property == 15): return c"margin-left"
	if (property == 16): return c"padding-top"
	if (property == 17): return c"padding-right"
	if (property == 18): return c"padding-bottom"
	if (property == 19): return c"padding-left"
	if (property == 20): return c"border-width"
	if (property == 21): return c"border-color"
	if (property == 29): return c"flex-grow"
	if (property == 30): return c"flex-shrink"
	if (property == 31): return c"flex-basis"
	return c"border-style"

char* win_cssom_specified(win_css_specified* slot, int property):
	if (slot.reset):
		if (slot.reset == 2): return strclone(c"1")
		if (slot.reset == 3):
			if (property == 31): return strclone(c"0px")
			return strclone(c"0")
		if (property == 31): return strclone(c"auto")
		if (property == 20): return strclone(c"medium")
		if (property == 21): return strclone(c"currentcolor")
		return strclone(c"none")
	return substring(slot.css.source, slot.css.tokens[slot.first].start, slot.css.tokens[slot.last - 1].end)

void win_cssom_append(string_builder* out, char* name, char* value, int important):
	if (out.length > 0): string_append_char(out, ' ')
	char* normalized = win_cssom_name(name)
	string_append(out, normalized)
	free(normalized)
	string_append(out, c": ")
	string_append(out, value)
	if (important): string_append(out, c" !important")
	string_append_char(out, ';')

# Serialize a shorthand only if all its supported components exist and have
# the same priority. A mixture of CSS-wide and ordinary values has no shorthand.
char* win_cssom_get(char* source, char* name, int priority):
	css_document* css = css_parse_declarations_n(source, strlen(source), 0)
	win_css_specified[33] winners
	win_cssom_collect(css, &winners[0])
	int[4] properties
	int count = 0
	int property = win_css_property(name)
	if (property >= 0):
		properties[0] = property
		count = 1
	else:
		for p in range(33):
			if (win_cssom_contains(name, p)):
				properties[count] = p
				count = count + 1
	# Border is conventionally serialized as width, style, color.
	if (count == 3 && win_cssom_equal(name, c"border")):
		properties[1] = 28
		properties[2] = 21
	int valid = count > 0
	int important = 0
	if (count > 0 && winners[properties[0]].present): important = winners[properties[0]].key.important
	for i in range(count):
		win_css_specified* slot = &winners[properties[i]]
		if (slot.present == 0 || slot.key.important != important): valid = 0
	string_builder* out = string_new()
	if (valid && priority):
		if (important): string_append(out, c"important")
	else if (valid):
		char*[4] values
		int wide = 0
		int same = 1
		for i in range(count):
			values[i] = win_cssom_specified(&winners[properties[i]], properties[i])
			if (winners[properties[i]].wide): wide = 1
			if (i > 0 && win_cssom_equal(values[i], values[0]) == 0): same = 0
		int length = count
		if (wide):
			length = 0
			if (same): length = 1
		else if (count == 4):
			if (strcmp(values[3], values[1]) == 0): length = 3
			if (length == 3 && strcmp(values[2], values[0]) == 0): length = 2
			if (length == 2 && strcmp(values[1], values[0]) == 0): length = 1
		for i in range(length):
			if (i > 0): string_append_char(out, ' ')
			string_append(out, values[i])
		for i in range(count): free(values[i])
	css_document_free(css)
	char* result = out.data
	free(out)
	return result

# Preserve a declaration when all its expanded components still win. Otherwise
# write only its surviving longhands, so removal cannot reveal an older value.
void win_cssom_serialize(string_builder* out, css_document* css, css_node* d, int order, win_css_specified* winners):
	int complete = 1
	int matches = 0
	for p in range(33):
		if (win_cssom_contains(d.name, p)):
			win_css_specified* slot = &winners[p]
			if (slot.present && slot.css == css && slot.key.order == order): matches = matches + 1
			else: complete = 0
	if (matches == 0): return
	if (complete):
		char* value = win_cssom_value(css, d)
		win_cssom_append(out, d.name, value, d.important)
		free(value)
	else:
		for p in range(33):
			win_css_specified* slot = &winners[p]
			if (slot.present && slot.css == css && slot.key.order == order):
				char* value = win_cssom_specified(slot, p)
				win_cssom_append(out, win_cssom_longhand(p), value, slot.key.important)
				free(value)

# A null name replaces cssText; an empty value removes every constituent
# longhand. Assignments replace their old priority, including important values.
# A null result means an invalid property assignment must leave style unchanged.
char* win_cssom_edit(char* source, char* name, char* value, char* priority):
	int important = 0
	css_document* parsed = 0
	if (name != 0 && value[0] != 0):
		if (priority[0] != 0 && win_cssom_equal(priority, c"important") == 0): return 0
		important = priority[0] != 0
		string_builder* candidate = string_from(name)
		string_append_char(candidate, ':')
		string_append(candidate, value)
		parsed = css_parse_declarations_n(candidate.data, candidate.length, 0)
		int valid = parsed.failed == 0 && parsed.nodes.length == 1
		if (valid): valid = parsed.nodes[0].important == 0 && win_cssom_equal(parsed.nodes[0].name, name) && win_css_declaration_supported(parsed, parsed.nodes[0])
		string_free(candidate)
		if (valid == 0):
			css_document_free(parsed)
			return 0
	css_document* css = css_parse_declarations_n(source, strlen(source), 0)
	win_css_specified[33] winners
	win_cssom_collect(css, &winners[0])
	if (name != 0):
		for p in range(33):
			if (win_cssom_contains(name, p)): winners[p].present = 0
	if (parsed != 0):
		parsed.nodes[0].important = important
		win_css_collect(parsed, parsed.nodes[0], win_cascade_author(important, 0, win_specificity_zero(), css.nodes.length), &winners[0])
	string_builder* out = string_new()
	if (css.failed == 0):
		for i in range(css.nodes.length): win_cssom_serialize(out, css, css.nodes[i], i, &winners[0])
	if (parsed != 0):
		win_cssom_serialize(out, parsed, parsed.nodes[0], css.nodes.length, &winners[0])
		css_document_free(parsed)
	css_document_free(css)
	char* result = out.data
	free(out)
	return result
