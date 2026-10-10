# Static document layout for the first browser milestone. Parser nodes and
# attribute strings stay borrowed from the page's owned HTML document.
import libs.extras.html.html
import libs.extras.css.css
import graphics.ui.text
import lib.utf8

struct win_style:
	int size
	int bold
	int flags
	int hidden
	int pre
	ui_color color

struct win_run:
	char* text
	char* href
	float32 x
	float32 y
	float32 width
	float32 height
	int strike
	int flags
	ui_color color

struct win_anchor:
	char* id
	float32 y

struct win_page:
	html_document* html
	list[win_run*] runs
	list[win_anchor*] anchors
	char* title
	int width
	float32 height
	float32 x
	float32 y
	float32 left
	float32 right
	int line_start
	int ascent
	int descent
	int space
	int truncated

char* win_attr(html_node* node, char* name):
	html_attribute* attr = html_attribute_find(node.attributes, name)
	if (attr == 0): return c""
	return attr.value

int win_tag(html_node* node, char* name):
	return node.kind == HTML_START && strcmp(node.name, name) == 0

win_style win_default_style():
	win_style s
	s.size = 18
	s.bold = 0
	s.flags = 0
	s.hidden = 0
	s.pre = 0
	s.color = ui_color_new(0.12, 0.16, 0.20, 1.0)
	return s

int win_hex(int c):
	if (c >= '0' && c <= '9'): return c - '0'
	if (c >= 'a' && c <= 'f'): return c - 'a' + 10
	if (c >= 'A' && c <= 'F'): return c - 'A' + 10
	return -1

ui_color win_color(char* value, ui_color fallback):
	if (strcmp(value, c"red") == 0): return ui_color_new(0.8, 0.1, 0.1, 1.0)
	if (strcmp(value, c"blue") == 0): return ui_color_new(0.1, 0.3, 0.8, 1.0)
	if (strcmp(value, c"green") == 0): return ui_color_new(0.1, 0.5, 0.2, 1.0)
	if (strcmp(value, c"black") == 0): return ui_gray(0.0)
	if (strcmp(value, c"white") == 0): return ui_gray(1.0)
	int n = strlen(value)
	if (n != 3 && n != 6): return fallback
	int rgb = 0
	for i in range(n):
		int digit = win_hex(value[i])
		if (digit < 0): return fallback
		if (n == 3): rgb = rgb * 256 + digit * 17
		else: rgb = rgb * 16 + digit
	return ui_color_new(cast(float32, (rgb >> 16) & 255) / 255.0, cast(float32, (rgb >> 8) & 255) / 255.0, cast(float32, rgb & 255) / 255.0, 1.0)

# A deliberately small inline CSS subset. Full stylesheet cascade is M3.
win_style win_inline_style(html_node* node, win_style style):
	char* text = win_attr(node, c"style")
	if (text[0] == 0): return style
	css_document* css = css_parse_declarations_n(text, strlen(text), 0)
	if (css.failed == 0):
		for i in range(css.nodes.length):
			css_node* d = css.nodes[i]
			if (strcmp(d.kind, c"declaration") != 0 || d.last - d.first != 1): continue
			css_token* token = css.tokens[d.first]
			char* value = token.value
			if (strcmp(d.name, c"color") == 0):
				if (strcmp(token.kind, c"hash") == 0 || strcmp(value, c"red") == 0 || strcmp(value, c"blue") == 0 || strcmp(value, c"green") == 0 || strcmp(value, c"black") == 0 || strcmp(value, c"white") == 0): style.color = win_color(value, style.color)
			else if (strcmp(d.name, c"font-size") == 0 && strcmp(token.kind, c"dimension") == 0):
				int n = strlen(value)
				if (n > 2 && strcmp(value + n - 2, c"px") == 0):
					int integer = 1
					for k in range(n - 2):
						if (value[k] < '0' || value[k] > '9'): integer = 0
					int size = atoi(value)
					if (integer && size >= 8 && size <= 72): style.size = size
			else if (strcmp(d.name, c"font-weight") == 0 && strcmp(value, c"bold") == 0): style.bold = 1
			else if (strcmp(d.name, c"font-style") == 0 && strcmp(value, c"italic") == 0): style.flags = style.flags | UI_TEXT_ITALIC
			else if (strcmp(d.name, c"display") == 0 && strcmp(value, c"none") == 0): style.hidden = 1
	css_document_free(css)
	return style

void win_runs_clear(win_page* page):
	for i in range(page.runs.length):
		free(page.runs[i].text)
		free(page.runs[i])
	while (page.runs.length > 0): page.runs.pop()
	for i in range(page.anchors.length): free(page.anchors[i])
	while (page.anchors.length > 0): page.anchors.pop()

void win_page_free(win_page* page):
	if (page == 0): return
	win_runs_clear(page)
	__w_list_free(cast(__w_list*, page.runs))
	__w_list_free(cast(__w_list*, page.anchors))
	html_document_free(page.html)
	free(page.title)
	free(page)

win_page* win_page_parse(char* source, int length):
	if (length > 1048576 || utf8_validate_bytes(source, length) == 0): return 0
	html_limits limits = html_default_limits()
	limits.input_bytes = 1048576
	limits.nodes = 20000
	limits.tokens = 30000
	limits.depth = 128
	html_document* html = html_parse_with_limits(source, length, &limits)
	if (html.failed):
		html_document_free(html)
		return 0
	win_page* page = new win_page()
	page.html = html
	page.runs = new list[win_run*]
	page.anchors = new list[win_anchor*]
	page.title = strclone(c"Untitled document")
	page.width = 0
	page.height = 0.0
	# The parser's allocation list also includes metadata hidden from layout.
	html_node* node = html.allocations
	while (node != 0):
		if (win_tag(node, c"title") && node.first_child != 0 && node.first_child.text != 0):
			free(page.title)
			page.title = strclone(node.first_child.text)
			node = 0
		else: node = node.allocation_next
	return page

void win_line_end(win_page* page, int force):
	if (page.runs.length > page.line_start):
		for i in range(page.line_start, page.runs.length):
			win_run* run = page.runs[i]
			run.y = page.y + cast(float32, page.ascent - ui_font_strike_ascent(run.strike))
		page.y = page.y + cast(float32, page.ascent + page.descent + 7)
	else if (force): page.y = page.y + 25.0
	page.x = page.left
	page.line_start = page.runs.length
	page.ascent = 0
	page.descent = 0
	page.space = 0

void win_word(win_page* page, char* word, win_style style, char* href):
	if (page.runs.length >= 20000):
		page.truncated = 1
		return
	int face = UI_FACE_REGULAR
	if (style.bold): face = UI_FACE_BOLD
	int strike = ui_font_strike(face, style.size)
	int base_strike = strike
	float32 skew = 0.0
	strike = ui_text_style_strike(strike, style.flags, &skew)
	float32 width = cast(float32, ui_text_width_strike(word, strike))
	float32 space = 0.0
	if (page.space && page.x > page.left): space = cast(float32, ui_text_width_strike(c" ", strike))
	if (page.x + space + width > page.right && page.x > page.left):
		win_line_end(page, 0)
		space = 0.0
	# Split oversized words at UTF-8 boundaries without quadratic scans.
	if (width > page.right - page.left && strlen(word) > 4):
		int start = 0
		int at = 0
		int part_width = 0
		int length = strlen(word)
		while (at < length):
			int cp = 0
			int end = ui_utf8_next(word, at, &cp)
			ui_glyph glyph = ui_font_glyph(strike, cp)
			if (at > start && cast(float32, part_width + glyph.advance) > page.right - page.left):
				char* part = substring(word, start, at)
				win_word(page, part, style, href)
				free(part)
				win_line_end(page, 0)
				start = at
				part_width = 0
			part_width = part_width + glyph.advance
			at = end
		char* tail = substring(word, start, length)
		win_word(page, tail, style, href)
		free(tail)
		return
	win_run* run = new win_run()
	run.text = strclone(word)
	run.href = href
	run.x = page.x + space
	run.y = page.y
	run.width = width
	run.height = cast(float32, ui_font_strike_ascent(strike) + ui_font_strike_descent(strike))
	run.strike = strike
	run.flags = style.flags
	# A selected true-italic face must not be synthetically slanted again.
	if (strike != base_strike): run.flags = run.flags & (0 - 1 - UI_TEXT_ITALIC)
	run.color = style.color
	page.runs.push(run)
	page.x = run.x + width
	int ascent = ui_font_strike_ascent(strike)
	int descent = ui_font_strike_descent(strike)
	if (ascent > page.ascent): page.ascent = ascent
	if (descent > page.descent): page.descent = descent
	page.space = 0

void win_text(win_page* page, char* text, int length, win_style style, char* href):
	int i = 0
	while (i < length && page.truncated == 0):
		if (html_space(text[i] & 255)):
			if (style.pre && text[i] == 10): win_line_end(page, 1)
			else if (style.pre):
				if (text[i] == 9): win_word(page, c"    ", style, href)
				else: win_word(page, c" ", style, href)
			else: page.space = 1
			i = i + 1
		else:
			int start = i
			while (i < length && html_space(text[i] & 255) == 0): i = i + 1
			char* word = substring(text, start, i)
			win_word(page, word, style, href)
			free(word)

int win_block(html_node* n):
	return win_tag(n, c"p") || win_tag(n, c"div") || win_tag(n, c"section") || win_tag(n, c"article") || win_tag(n, c"header") || win_tag(n, c"footer") || win_tag(n, c"main") || win_tag(n, c"nav") || win_tag(n, c"blockquote") || win_tag(n, c"ul") || win_tag(n, c"ol") || win_tag(n, c"li") || win_tag(n, c"pre") || win_tag(n, c"h1") || win_tag(n, c"h2") || win_tag(n, c"h3") || win_tag(n, c"h4") || win_tag(n, c"h5") || win_tag(n, c"h6")

void win_layout_node(win_page* page, html_node* node, win_style style, char* href):
	if (node == 0 || page.truncated): return
	if (node.kind == HTML_TEXT):
		win_text(page, node.text, node.text_length, style, href)
		return
	if (node.kind != HTML_START && node.kind != HTML_DOCUMENT): return
	if (win_tag(node, c"head") || win_tag(node, c"script") || win_tag(node, c"style") || win_tag(node, c"template")): return
	if (html_attribute_find(node.attributes, c"hidden") != 0): return
	int block = win_block(node)
	if (win_tag(node, c"h1")): style.size = 36
	if (win_tag(node, c"h2")): style.size = 28
	if (win_tag(node, c"h3")): style.size = 23
	if (win_tag(node, c"h1") || win_tag(node, c"h2") || win_tag(node, c"h3") || win_tag(node, c"b") || win_tag(node, c"strong")): style.bold = 1
	if (win_tag(node, c"i") || win_tag(node, c"em")): style.flags = style.flags | UI_TEXT_ITALIC
	if (win_tag(node, c"pre")): style.pre = 1
	if (win_tag(node, c"a") && win_attr(node, c"href")[0] != 0):
		href = win_attr(node, c"href")
		style.color = ui_color_new(0.08, 0.35, 0.72, 1.0)
		style.flags = style.flags | UI_TEXT_UNDERLINE
	style = win_inline_style(node, style)
	if (style.hidden): return
	if (block):
		win_line_end(page, 0)
		page.y = page.y + 10.0
	char* id = win_attr(node, c"id")
	if (id[0] != 0):
		win_anchor* anchor = new win_anchor()
		anchor.id = id
		anchor.y = page.y
		page.anchors.push(anchor)
	if (win_tag(node, c"br")):
		win_line_end(page, 1)
		return
	if (win_tag(node, c"img")):
		win_word(page, c"[image:", style, href)
		page.space = 1
		char* alt = win_attr(node, c"alt")
		win_text(page, alt, strlen(alt), style, href)
		win_word(page, c"]", style, href)
		return
	float32 left = page.left
	if (win_tag(node, c"ul") || win_tag(node, c"ol") || win_tag(node, c"blockquote")):
		page.left = page.left + 22.0
		if (page.left > page.right - 80.0): page.left = left
		page.x = page.left
	if (win_tag(node, c"li")):
		win_word(page, c"•", style, c"")
		page.space = 1
	html_node* child = node.first_child
	while (child != 0 && page.truncated == 0):
		win_layout_node(page, child, style, href)
		child = child.next_sibling
	if (block):
		win_line_end(page, 0)
		page.y = page.y + 8.0
	page.left = left
	if (block): page.x = left

void win_page_layout(win_page* page, int width):
	if (width < 160): width = 160
	win_runs_clear(page)
	page.width = width
	page.left = 28.0
	page.right = cast(float32, width) - 28.0
	page.x = page.left
	page.y = 20.0
	page.line_start = 0
	page.ascent = 0
	page.descent = 0
	page.space = 0
	page.truncated = 0
	win_layout_node(page, page.html.root, win_default_style(), c"")
	win_line_end(page, 0)
	page.height = page.y + 28.0

char* win_page_hit(win_page* page, float32 x, float32 y):
	for i in range(page.runs.length):
		win_run* r = page.runs[i]
		if (r.href[0] != 0 && x >= r.x && x < r.x + r.width && y >= r.y && y < r.y + r.height): return r.href
	return c""

float32 win_page_anchor(win_page* page, char* id):
	for i in range(page.anchors.length):
		if (strcmp(page.anchors[i].id, id) == 0): return page.anchors[i].y
	return 0.0
