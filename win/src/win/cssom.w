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

int win_cssom_winner(css_document* css, char* name):
	int winner = -1
	for i in range(css.nodes.length):
		css_node* d = css.nodes[i]
		if (win_cssom_equal(d.name, name) && win_css_declaration_supported(css, d)):
			if (winner < 0): winner = i
			else if (d.important >= css.nodes[winner].important): winner = i
	return winner

# Collapse duplicate properties once. The supported property set bounds this
# small list; repeated declarations do not cause quadratic source rescans.
list[int] win_cssom_winners(css_document* css):
	list[int] winners = new list[int]
	for i in range(css.nodes.length):
		css_node* d = css.nodes[i]
		if (win_css_declaration_supported(css, d) == 0): continue
		int found = -1
		for j in range(winners.length):
			if (win_cssom_equal(css.nodes[winners[j]].name, d.name)): found = j
		if (found < 0): winners.push(i)
		else if (d.important >= css.nodes[winners[found]].important): winners[found] = i
	return winners

void win_cssom_append(string_builder* out, char* name, char* value, int important):
	if (out.length > 0): string_append_char(out, ' ')
	char* normalized = win_cssom_name(name)
	string_append(out, normalized)
	free(normalized)
	string_append(out, c": ")
	string_append(out, value)
	if (important): string_append(out, c" !important")
	string_append_char(out, ';')

char* win_cssom_get(char* source, char* name, int priority):
	css_document* css = css_parse_declarations_n(source, strlen(source), 0)
	char* result = strclone(c"")
	if (css.failed == 0):
		int index = win_cssom_winner(css, name)
		if (index >= 0):
			free(result)
			if (priority):
				if (css.nodes[index].important): result = strclone(c"important")
				else: result = strclone(c"")
			else: result = win_cssom_value(css, css.nodes[index])
	css_document_free(css)
	return result

# A null name replaces cssText; an empty value removes the named declaration.
# A null result means an invalid property assignment must leave style unchanged.
char* win_cssom_edit(char* source, char* name, char* value, char* priority):
	int important = 0
	if (name != 0 && value[0] != 0):
		if (priority[0] != 0 && win_cssom_equal(priority, c"important") == 0): return 0
		important = priority[0] != 0
		string_builder* candidate = string_from(name)
		string_append_char(candidate, ':')
		string_append(candidate, value)
		css_document* parsed = css_parse_declarations_n(candidate.data, candidate.length, 0)
		int valid = parsed.failed == 0 && parsed.nodes.length == 1
		if (valid): valid = parsed.nodes[0].important == 0 && win_cssom_equal(parsed.nodes[0].name, name) && win_css_declaration_supported(parsed, parsed.nodes[0])
		css_document_free(parsed)
		string_free(candidate)
		if (valid == 0): return 0
	css_document* css = css_parse_declarations_n(source, strlen(source), 0)
	string_builder* out = string_new()
	int inserted = 0
	if (css.failed == 0):
		list[int] winners = win_cssom_winners(css)
		for i in range(winners.length):
			css_node* d = css.nodes[winners[i]]
			if (name != 0 && win_cssom_equal(d.name, name)):
				if (inserted == 0 && value[0] != 0): win_cssom_append(out, name, value, important)
				inserted = 1
			else:
				char* text = win_cssom_value(css, d)
				win_cssom_append(out, d.name, text, d.important)
				free(text)
		__w_list_free(cast(__w_list*, winners))
	if (name != 0 && inserted == 0 && value[0] != 0): win_cssom_append(out, name, value, important)
	css_document_free(css)
	char* result = out.data
	free(out)
	return result
