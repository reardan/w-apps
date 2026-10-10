# Static document layout for the first browser milestone. Parser nodes and
# attribute strings stay borrowed from the page's owned HTML document.
import libs.extras.html.html
import win.style
import win.images
import graphics.ui.text
import lib.utf8

struct win_run:
	int hidden
	html_node* node
	win_image* image
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

struct win_box:
	int hidden
	html_node* node
	float32 x
	float32 y
	float32 width
	float32 height
	ui_color color
	ui_color border_color
	int border

struct win_stylesheet:
	html_node* node
	css_document* css

struct win_page:
	html_node* layout_node
	list[win_image*] images
	list[win_box*] boxes
	list[win_stylesheet*] stylesheets
	int align
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
	int line_height
	int ascent
	int descent
	int space
	int truncated

void win_runs_clear(win_page* page):
	for i in range(page.runs.length):
		free(page.runs[i].text)
		free(page.runs[i])
	while (page.runs.length > 0): page.runs.pop()
	for i in range(page.boxes.length): free(page.boxes[i])
	while (page.boxes.length > 0): page.boxes.pop()
	for i in range(page.anchors.length): free(page.anchors[i])
	while (page.anchors.length > 0): page.anchors.pop()

void win_page_free(win_page* page):
	if (page == 0): return
	win_runs_clear(page)
	win_images_free(page.images)
	for i in range(page.stylesheets.length):
		if (page.stylesheets[i].css != 0): css_document_free(page.stylesheets[i].css)
		free(page.stylesheets[i])
	__w_list_free(cast(__w_list*, page.stylesheets))
	__w_list_free(cast(__w_list*, page.boxes))
	__w_list_free(cast(__w_list*, page.runs))
	__w_list_free(cast(__w_list*, page.anchors))
	html_document_free(page.html)
	free(page.title)
	free(page)

void win_page_add_stylesheet_for_node(win_page* page, html_node* node, char* source, int length):
	css_document* css = css_parse_stylesheet_n(source, length, 0)
	if (css.failed):
		css_document_free(css)
		return
	for i in range(page.stylesheets.length):
		win_stylesheet* sheet = page.stylesheets[i]
		if (node != 0 && sheet.node == node):
			if (sheet.css != 0): css_document_free(sheet.css)
			sheet.css = css
			page.width = 0
			return
	win_stylesheet* sheet = new win_stylesheet()
	sheet.node = node
	sheet.css = css
	page.stylesheets.push(sheet)
	page.width = 0

void win_page_add_stylesheet(win_page* page, char* source, int length):
	win_page_add_stylesheet_for_node(page, 0, source, length)

void win_page_collect_styles(win_page* page, html_node* node):
	if (win_tag(node, c"style")):
		string_builder* source = string_new()
		html_node* child = node.first_child
		while (child != 0):
			if (child.kind == HTML_TEXT): string_append_bytes(source, child.text, child.text_length)
			child = child.next_sibling
		win_page_add_stylesheet_for_node(page, node, source.data, source.length)
		string_free(source)
	else if (win_tag(node, c"link") && win_class_has(win_attr(node, c"rel"), c"stylesheet")):
		win_stylesheet* sheet = new win_stylesheet()
		sheet.node = node
		sheet.css = 0
		page.stylesheets.push(sheet)
	html_node* child = node.first_child
	while (child != 0):
		win_page_collect_styles(page, child)
		child = child.next_sibling

win_style win_computed_style(win_page* page, html_node* node, win_style style, win_style inherited):
	win_css_specified[29] winners
	for i in range(29): winners[i].present = 0
	int order = 0
	for i in range(page.stylesheets.length):
		css_document* css = page.stylesheets[i].css
		if (css != 0): win_css_rules(css, css.nodes, node, page.width, &winners[0], &order)
	char* text = win_attr(node, c"style")
	css_document* inline_css = 0
	if (text[0] != 0):
		inline_css = css_parse_declarations_n(text, strlen(text), 0)
		if (inline_css.failed == 0):
			for i in range(inline_css.nodes.length):
				css_node* d = inline_css.nodes[i]
				order = order + 1
				win_css_collect(inline_css, d, win_cascade_author(d.important, 1, win_specificity_zero(), order), &winners[0])
	int root = node.kind == HTML_START && (node.parent == 0 || node.parent.kind == HTML_DOCUMENT)
	win_css_compute(&winners[0], &style, inherited, root)
	css_document_free(inline_css)
	return style

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
	page.images = new list[win_image*]
	page.boxes = new list[win_box*]
	page.stylesheets = new list[win_stylesheet*]
	win_page_collect_styles(page, html.root)
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
		float32 shift = 0.0
		if (page.align == 1): shift = (page.right - page.x) / 2.0
		if (page.align == 2): shift = page.right - page.x
		if (shift < 0.0): shift = 0.0
		for i in range(page.line_start, page.runs.length):
			win_run* run = page.runs[i]
			run.x = run.x + shift
			if (run.image != 0): run.y = page.y + cast(float32, page.ascent) - run.height
			else: run.y = page.y + cast(float32, page.ascent - ui_font_strike_ascent(run.strike))
		int height = page.ascent + page.descent + 7
		if (page.line_height > height): height = page.line_height
		page.y = page.y + cast(float32, height)
	else if (force): page.y = page.y + 25.0
	page.x = page.left
	page.line_start = page.runs.length
	page.line_height = 0
	page.ascent = 0
	page.descent = 0
	page.space = 0

void win_word(win_page* page, char* word, win_style style, char* href):
	if (page.runs.length >= 20000):
		page.truncated = 1
		return
	int face = UI_FACE_REGULAR
	if (style.bold): face = UI_FACE_BOLD
	int ppem = cast(int, style.size)
	if (ppem < 4): ppem = 4
	if (ppem > 200): ppem = 200
	int strike = ui_font_strike(face, ppem)
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
	run.hidden = style.hidden
	run.node = page.layout_node
	run.image = 0
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
	int line_height = style.line_height
	if (style.line_height_factor > 0.0): line_height = cast(int, cast(float32, style.size) * style.line_height_factor)
	if (line_height > page.line_height): page.line_height = line_height
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

win_box* win_page_node_box(win_page* page, html_node* node):
	for i in range(page.boxes.length):
		if (page.boxes[i].node == node): return page.boxes[i]
	return 0

win_box* win_box_add(win_page* page, html_node* node, win_style style, float32 x, float32 y, float32 width, float32 height):
	win_box* box = new win_box()
	box.hidden = style.hidden
	box.node = node
	box.x = x
	box.y = y
	box.width = width
	box.height = height
	box.color = style.background
	box.border_color = style.border_color
	box.border = style.border
	page.boxes.push(box)
	return box

void win_layout_node(win_page* page, html_node* node, win_style inherited, char* href):
	if (node == 0 || page.truncated): return
	if (node.kind == HTML_TEXT):
		page.layout_node = node.parent
		win_text(page, node.text, node.text_length, inherited, href)
		return
	if (node.kind != HTML_START && node.kind != HTML_DOCUMENT): return
	if (win_tag(node, c"head") || win_tag(node, c"script") || win_tag(node, c"style") || win_tag(node, c"template")): return
	if (html_attribute_find(node.attributes, c"hidden") != 0): return
	win_style style = win_default_style()
	style.size = inherited.size
	style.root_size = inherited.root_size
	style.line_height = inherited.line_height
	style.line_height_factor = inherited.line_height_factor
	style.bold = inherited.bold
	style.flags = inherited.flags
	style.color = inherited.color
	style.pre = inherited.pre
	style.align = inherited.align
	style.hidden = inherited.hidden
	int block = win_block(node) || win_tag(node, c"body") || win_tag(node, c"form") || win_tag(node, c"fieldset") || win_tag(node, c"table") || win_tag(node, c"tr") || win_tag(node, c"hr")
	if (block && win_tag(node, c"body") == 0):
		style.margin_top = 10
		style.margin_bottom = 8
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
	style.display = 2
	if (block): style.display = 1
	style = win_computed_style(page, node, style, inherited)
	if (style.display == 0): return
	if (style.display == 1 || style.display == 3 || style.display == 4): block = 1
	if (style.display == 2): block = 0
	page.layout_node = node
	float32 left = page.left
	float32 right = page.right
	int align = page.align
	win_box* box = 0
	float32 content_top = page.y
	if (block):
		win_line_end(page, 0)
		page.align = style.align
		page.y = page.y + cast(float32, style.margin_top)
		float32 ml = cast(float32, style.margin_left)
		float32 mr = cast(float32, style.margin_right)
		if (ml < 0.0): ml = 0.0
		if (mr < 0.0): mr = 0.0
		float32 extras = cast(float32, style.padding_left + style.padding_right + style.border * 2)
		float32 width = right - left - ml - mr
		if (style.width >= 0):
			width = cast(float32, style.width)
			if (style.width_percent): width = (right - left) * width / 100.0
			if (style.box_sizing == 0): width = width + extras
		float32 maximum = cast(float32, style.max_width)
		if (style.max_width_percent): maximum = (right - left) * maximum / 100.0
		if (style.box_sizing == 0): maximum = maximum + extras
		if (style.max_width >= 0 && width > maximum): width = maximum
		if (width < extras + 1.0): width = extras + 1.0
		float32 available = right - left - width - ml - mr
		if (available > 0.0 && style.margin_left_auto):
			ml = available
			if (style.margin_right_auto): ml = available / 2.0
		box = win_box_add(page, node, style, left + ml, page.y, width, 0.0)
		page.left = box.x + cast(float32, style.padding_left + style.border)
		page.right = box.x + width - cast(float32, style.padding_right + style.border)
		page.y = page.y + cast(float32, style.padding_top + style.border)
		page.x = page.left
		content_top = page.y
	char* id = win_attr(node, c"id")
	if (id[0] != 0):
		win_anchor* anchor = new win_anchor()
		anchor.id = id
		anchor.y = page.y
		page.anchors.push(anchor)
	if (win_tag(node, c"br")):
		win_line_end(page, 1)
		return
	int control = win_tag(node, c"input") || win_tag(node, c"textarea") || win_tag(node, c"select") || win_tag(node, c"button")
	if (control && strcmp(win_attr(node, c"type"), c"hidden") != 0):
		win_line_end(page, 0)
		float32 width = 220.0
		float32 height = 34.0
		if (win_tag(node, c"button") || strcmp(win_attr(node, c"type"), c"submit") == 0): width = 100.0
		if (win_tag(node, c"textarea")): height = 80.0
		if (style.width >= 0): width = cast(float32, style.width)
		if (style.width_percent): width = (page.right - page.left) * width / 100.0
		if (style.height >= 0): height = cast(float32, style.height)
		if (width > page.right - page.left): width = page.right - page.left
		if (box == 0): box = win_box_add(page, node, style, page.left, page.y, width, height)
		else:
			box.width = width
			box.height = height
		page.y = page.y + height + 6.0
	else if (win_tag(node, c"img")):
		win_image* image = win_image_find(page.images, node)
		if (image != 0 && image.width > 0 && image.failed == 0):
			float32 iw = cast(float32, image.width)
			float32 ih = cast(float32, image.height)
			int width = atoi(win_attr(node, c"width"))
			int height = atoi(win_attr(node, c"height"))
			if (style.width >= 0): width = style.width
			if (style.width_percent): width = cast(int, (page.right - page.left) * cast(float32, width) / 100.0)
			if (style.height >= 0): height = style.height
			if (width > 100000): width = 100000
			if (height > 100000): height = 100000
			if (width > 0):
				iw = cast(float32, width)
				ih = iw * cast(float32, image.height) / cast(float32, image.width)
			if (height > 0):
				ih = cast(float32, height)
				if (width <= 0): iw = ih * cast(float32, image.width) / cast(float32, image.height)
			float32 maximum = cast(float32, style.max_width)
			if (style.max_width_percent): maximum = (page.right - page.left) * maximum / 100.0
			if (style.max_width >= 0 && iw > maximum):
				ih = ih * maximum / iw
				iw = maximum
			if (page.x + iw > page.right && page.x > page.left): win_line_end(page, 0)
			win_run* run = new win_run()
			run.hidden = style.hidden
			run.node = node
			run.image = image
			run.text = strclone(c"")
			run.href = href
			run.x = page.x
			run.y = page.y
			run.width = iw
			run.height = ih
			run.strike = 0
			run.flags = 0
			page.runs.push(run)
			page.x = page.x + iw
			if (cast(int, ih) > page.ascent): page.ascent = cast(int, ih)
		else:
			char* alt = win_attr(node, c"alt")
			win_text(page, alt, strlen(alt), style, href)
	else if (control == 0):
		if (win_tag(node, c"ul") || win_tag(node, c"ol") || win_tag(node, c"blockquote")):
			if (page.left + 22.0 < page.right - 40.0): page.left = page.left + 22.0
			page.x = page.left
		if (win_tag(node, c"li")):
			win_word(page, c"•", style, c"")
			page.space = 1
		html_node* child = node.first_child
		if (style.display == 4 || style.display == 3 && style.flex_column == 0):
			int columns = style.columns
			if (style.display == 3):
				columns = 0
				while (child != 0):
					if (child.kind == HTML_START): columns = columns + 1
					child = child.next_sibling
				child = node.first_child
			if (columns < 1): columns = 1
			float32 row_left = page.left
			float32 row_right = page.right
			float32 row_top = page.y
			float32 row_bottom = row_top
			float32 cell_width = (row_right - row_left - cast(float32, style.gap * (columns - 1))) / cast(float32, columns)
			if (cell_width < 1.0): cell_width = 1.0
			int column = 0
			while (child != 0 && page.truncated == 0):
				if (child.kind == HTML_START):
					page.left = row_left + cast(float32, column) * (cell_width + cast(float32, style.gap))
					page.right = page.left + cell_width
					page.x = page.left
					page.y = row_top
					win_layout_node(page, child, style, href)
					win_line_end(page, 0)
					if (page.y > row_bottom): row_bottom = page.y
					column = column + 1
					if (column == columns):
						column = 0
						row_top = row_bottom + cast(float32, style.gap)
				child = child.next_sibling
			page.left = row_left
			page.right = row_right
			page.x = row_left
			page.y = row_bottom
		else:
			while (child != 0 && page.truncated == 0):
				win_layout_node(page, child, style, href)
				child = child.next_sibling
	if (block):
		win_line_end(page, 0)
		if (style.height >= 0 && page.y < content_top + cast(float32, style.height)): page.y = content_top + cast(float32, style.height)
		page.y = page.y + cast(float32, style.padding_bottom + style.border)
		box.height = page.y - box.y
		page.y = page.y + cast(float32, style.margin_bottom)
	page.left = left
	page.right = right
	page.align = align
	if (block): page.x = left

void win_page_layout(win_page* page, int width):
	if (width < 160): width = 160
	win_runs_clear(page)
	page.width = width
	page.left = 28.0
	page.right = cast(float32, width) - 28.0
	page.x = page.left
	page.y = 20.0
	page.align = 0
	page.layout_node = 0
	page.line_start = 0
	page.line_height = 0
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
		if (r.hidden == 0 && r.href[0] != 0 && x >= r.x && x < r.x + r.width && y >= r.y && y < r.y + r.height): return r.href
	return c""

float32 win_page_anchor(win_page* page, char* id):
	for i in range(page.anchors.length):
		if (strcmp(page.anchors[i].id, id) == 0): return page.anchors[i].y
	return 0.0
