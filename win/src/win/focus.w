# Shared native/DOM focus eligibility and UTF-16-to-editor position conversion.
import win.forms
import win.pointer

int win_focus_explicit_index(html_node* node):
	char* text = win_attr(node, c"tabindex")
	int at = 0
	while (text[at] == ' ' || text[at] == '\t' || text[at] == '\n' || text[at] == '\r' || text[at] == 12): at = at + 1
	if (text[at] == '+' || text[at] == '-'): at = at + 1
	return text[at] >= '0' && text[at] <= '9'

int win_focus_tab_index(html_node* node):
	if (win_focus_explicit_index(node)):
		char* text = win_attr(node, c"tabindex")
		int at = 0
		while (html_space(text[at])): at = at + 1
		int negative = text[at] == '-'
		if (text[at] == '+' || text[at] == '-'): at = at + 1
		int value = 0
		while (text[at] >= '0' && text[at] <= '9'):
			int digit = text[at] - '0'
			if (value > 214748364 || value == 214748364 && digit > 7): value = 2147483647
			else: value = value * 10 + digit
			at = at + 1
		if (negative): value = 0 - value
		return value
	if (win_form_control(node) && css_ascii_equal(win_form_type(node), c"hidden") == 0): return 0
	if (win_tag(node, c"a") && win_form_has(node, c"href")): return 0
	return 0 - 1

int win_focus_eligible(win_page* page, html_node* node):
	if (node == 0 || node.kind != HTML_START || win_pointer_connected(page, node) == 0): return 0
	if (win_form_control(node) && (win_form_disabled(node) || css_ascii_equal(win_form_type(node), c"hidden"))): return 0
	if (win_focus_tab_index(node) < 0 && win_focus_explicit_index(node) == 0): return 0
	# Compute inherited visibility from root to target. A visible descendant
	# can override visibility:hidden; display:none removes its whole subtree.
	list[html_node*] ancestors = new list[html_node*]
	html_node* ancestor = node
	while (ancestor != 0 && ancestor != page.html.root && ancestors.length < 128):
		ancestors.push(ancestor)
		ancestor = ancestor.parent
	int eligible = ancestor == page.html.root
	win_style style = win_default_style()
	int i = ancestors.length - 1
	while (i >= 0 && eligible):
		ancestor = ancestors[i]
		if (win_layout_skipped(ancestor)): eligible = 0
		style = win_node_style(page, ancestor, style)
		if (style.display == 0): eligible = 0
		i = i - 1
	__w_list_free(cast(__w_list*, ancestors))
	return eligible && style.hidden == 0

html_node* win_focus_fallback(win_page* page):
	html_node* root = 0
	html_node* node = page.html.allocations
	while (node != 0):
		if (win_pointer_connected(page, node)):
			if (win_tag(node, c"body")): return node
			if (win_tag(node, c"html")): root = node
		node = node.allocation_next
	return root

# Native editing uses scalar UTF-8 boundaries. A JS selection between a
# surrogate pair maps to its leading boundary without changing the DOM range
# until an actual native caret/selection or value change is observed.
int win_focus_byte_offset(char* text, int units):
	int length = min(strlen(text), WIN_FORM_LIMIT)
	int at = 0
	int count = 0
	while (at < length && count < units):
		int cp = 0
		int bytes = utf8_scan(text + at, length - at, &cp)
		if (bytes == 0): break
		int width = 1
		if (cp > 65535): width = 2
		if (count + width > units): break
		count = count + width
		at = at + bytes
	return at

int win_focus_unit_offset(char* text, int offset):
	int length = min(strlen(text), WIN_FORM_LIMIT)
	int at = 0
	int count = 0
	while (at < length && at < offset):
		int cp = 0
		int bytes = utf8_scan(text + at, length - at, &cp)
		if (bytes == 0 || at + bytes > offset): break
		count = count + 1
		if (cp > 65535): count = count + 1
		at = at + bytes
	return count
