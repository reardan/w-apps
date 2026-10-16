# CSS Variables 1: case-sensitive custom properties, computed inheritance and
# token-preserving substitution. Contexts own all strings and token documents.
# Limits: 256 names per element, 64 KiB per expansion, 128 dependency levels.
struct win_css_custom:
	char* name
	char* inherited
	char* value
	css_document* specified
	win_cascade_key key
	int local
	int state
	int cyclic

int win_css_custom_name(char* name):
	return name[0] == '-' && name[1] == '-' && name[2] != 0

int win_css_affects(char* name, int property):
	if (win_css_property(name) == property): return 1
	if (css_ascii_equal(name, c"margin")): return property >= 12 && property <= 15
	if (css_ascii_equal(name, c"padding")): return property >= 16 && property <= 19
	if (css_ascii_equal(name, c"flex")): return property >= 29 && property <= 31
	if (css_ascii_equal(name, c"border")): return property == 20 || property == 21 || property == 28
	return 0

int win_css_var(css_document* css, int pos, int last):
	return pos + 1 < last && win_css_ident(css.tokens[pos], c"var") && css_delim(css.tokens[pos + 1], '(') && css.tokens[pos].end == css.tokens[pos + 1].start

# Return 0 for malformed var(), 1 for no substitution, 2 for valid var().
int win_css_variables_valid(css_document* css, int first, int last, int depth):
	if (depth > 128): return 0
	int result = 1
	int pos = first
	while (pos < last):
		if (win_css_var(css, pos, last)):
			int close = css.tokens[pos + 1].match
			if (close < pos || close >= last): return 0
			int name = css_skip(css, pos + 2, close)
			if (name >= close || css_kind(css.tokens[name], c"ident") == 0 || win_css_custom_name(css.tokens[name].value) == 0): return 0
			int comma = css_skip(css, name + 1, close)
			if (comma < close):
				if (css_delim(css.tokens[comma], ',') == 0): return 0
				if (win_css_variables_valid(css, comma + 1, close, depth + 1) == 0): return 0
				int fallback = comma + 1
				while (fallback < close):
					if (css_delim(css.tokens[fallback], '!') || css_delim(css.tokens[fallback], ';')): return 0
					fallback = css_next_component(css, fallback, close)
			result = 2
			pos = close + 1
		else: pos = pos + 1
	return result

int win_css_custom_valid(css_document* css, int first, int last):
	if (win_css_variables_valid(css, first, last, 0) == 0): return 0
	int pos = first
	while (pos < last):
		if (css_delim(css.tokens[pos], '!') || css_delim(css.tokens[pos], ';')): return 0
		pos = css_next_component(css, pos, last)
	return 1

win_css_custom* win_css_custom_find(list[win_css_custom*] values, char* name):
	for i in range(values.length):
		if (strcmp(values[i].name, name) == 0): return values[i]
	return 0

void win_css_custom_collect(list[win_css_custom*] values, css_document* css, css_node* d, win_cascade_key key):
	if (win_css_custom_name(d.name) == 0 || win_css_custom_valid(css, d.first, d.last) == 0): return
	win_css_custom* entry = win_css_custom_find(values, d.name)
	if (entry == 0):
		if (values.length >= 256): return
		entry = new win_css_custom()
		entry.name = strclone(d.name)
		values.push(entry)
	if (entry.local && win_cascade_compare(key, entry.key) < 0): return
	entry.local = 1
	entry.key = key
	css_document_free(entry.specified)
	int first = css_skip(css, d.first, d.last)
	int last = css_trim(css, first, d.last)
	char* text = strclone(c"")
	if (first < last):
		free(text)
		text = substring(css.source, css.tokens[first].start, css.tokens[last - 1].end)
	entry.specified = css_tokenize_n(text, strlen(text), 0)
	free(text)

char* win_css_custom_expand(list[win_css_custom*] values, css_document* css, int first, int last, int depth):
	if (depth > 128): return 0
	string_builder* out = string_new()
	int start = css.length
	if (first < last): start = css.tokens[first].start
	int end = start
	if (first < last): end = css.tokens[last - 1].end
	int pos = first
	int valid = 1
	while (pos < last && valid):
		if (win_css_var(css, pos, last)):
			int close = css.tokens[pos + 1].match
			int name = css_skip(css, pos + 2, close)
			win_css_custom* entry = win_css_custom_find(values, css.tokens[name].value)
			char* replacement = 0
			char* fallback = 0
			if (entry != 0): replacement = entry.value
			if (replacement == 0):
				int comma = css_skip(css, name + 1, close)
				if (comma < close): fallback = win_css_custom_expand(values, css, comma + 1, close, depth + 1)
				replacement = fallback
			if (replacement == 0): valid = 0
			else:
				int added = css.tokens[pos].start - start + strlen(replacement) + 8
				if (out.length + added > 65536): valid = 0
				else:
					string_append_bytes(out, css.source + start, css.tokens[pos].start - start)
					# Comments preserve token boundaries: var(--n)px is not a dimension.
					string_append(out, c"/**/")
					string_append(out, replacement)
					string_append(out, c"/**/")
			free(fallback)
			start = css.tokens[close].end
			pos = close + 1
		else: pos = pos + 1
	if (out.length + end - start > 65536): valid = 0
	if (valid): string_append_bytes(out, css.source + start, end - start)
	if (valid == 0):
		string_free(out)
		return 0
	char* result = out.data
	free(out)
	return result

# Every reference contributes an edge, including references in unused fallbacks.
# Mark exactly the active cycle; downstream references may still use fallback.
void win_css_custom_resolve(list[win_css_custom*] values, win_css_custom* entry, list[win_css_custom*] stack):
	if (entry.state == 2): return
	if (entry.state == 1):
		int cycle = 0
		for i in range(stack.length):
			if (stack[i] == entry): cycle = 1
			if (cycle): stack[i].cyclic = 1
		return
	entry.state = 1
	stack.push(entry)
	css_document* css = entry.specified
	if (css == 0):
		if (entry.inherited != 0): entry.value = strclone(entry.inherited)
	else:
		int first = css_skip(css, 0, css.tokens.length)
		int last = css_trim(css, first, css.tokens.length)
		int wide = 0
		if (first < last && css_skip(css, first + 1, last) == last): wide = win_css_wide(css.tokens[first])
		if (wide):
			if (wide != 2 && entry.inherited != 0): entry.value = strclone(entry.inherited)
		else if (stack.length <= 128 && css.failed == 0):
			for pos in range(first, last):
				if (win_css_var(css, pos, last)):
					int name = css_skip(css, pos + 2, css.tokens[pos + 1].match)
					win_css_custom* dependency = win_css_custom_find(values, css.tokens[name].value)
					if (dependency != 0): win_css_custom_resolve(values, dependency, stack)
			if (entry.cyclic == 0): entry.value = win_css_custom_expand(values, css, first, last, 0)
	stack.pop()
	entry.state = 2

void win_css_custom_finish(list[win_css_custom*] values):
	list[win_css_custom*] stack = new list[win_css_custom*]
	for i in range(values.length): win_css_custom_resolve(values, values[i], stack)
	__w_list_free(cast(__w_list*, stack))

void win_css_custom_inherit(list[win_css_custom*] values):
	for i in range(values.length):
		win_css_custom* entry = values[i]
		free(entry.inherited)
		entry.inherited = entry.value
		entry.value = 0
		css_document_free(entry.specified)
		entry.specified = 0
		entry.local = 0
		entry.state = 0
		entry.cyclic = 0

void win_css_custom_free(list[win_css_custom*] values):
	for i in range(values.length):
		win_css_custom* entry = values[i]
		free(entry.name)
		free(entry.inherited)
		free(entry.value)
		css_document_free(entry.specified)
		free(entry)
	__w_list_free(cast(__w_list*, values))
