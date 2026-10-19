# Static document layout for the first browser milestone. Parser nodes and
# attribute strings stay borrowed from the page's owned HTML document.
import libs.extras.html.html
import win.style
import win.layout
import win.images
import graphics.ui.text
import lib.utf8

struct win_run:
	int fixed
	int hidden
	int pointer_none
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
	int fixed
	char* id
	float32 y

struct win_box:
	int author_paint
	ui_color text_color
	int fixed
	int hidden
	int pointer_none
	html_node* node
	float32 x
	float32 y
	float32 width
	float32 height
	ui_color color
	ui_color border_color
	int border

struct win_stylesheet:
	char* reference
	html_node* node
	css_document* css

# Per-layout intrinsic-height cache shared by temporary measurement pages.
struct win_height_measure:
	html_node* node
	float32 width
	float32 height

# Deferred fixed roots are laid out after normal flow. Their children share
# viewport coordinates, while nested fixed roots get a fresh containing block.
struct win_fixed_item:
	html_node* node
	win_style style
	char* href
	float32 x
	float32 y

struct win_page:
	list[win_fixed_item*] fixed_items
	html_node* positioned_root
	int fixed_context
	int measuring
	float32 scroll_y
	html_node* layout_node
	list[win_image*] images
	list[win_height_measure*] height_measures
	list[win_box*] boxes
	list[win_stylesheet*] stylesheets
	int align
	html_document* html
	list[win_run*] runs
	list[win_anchor*] anchors
	char* title
	int width
	int viewport_width
	int viewport_height
	int viewport_explicit
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
	if (page.fixed_items != 0):
		for i in range(page.fixed_items.length): free(page.fixed_items[i])
		while (page.fixed_items.length > 0): page.fixed_items.pop()
	for i in range(page.runs.length):
		free(page.runs[i].text)
		free(page.runs[i])
	while (page.runs.length > 0): page.runs.pop()
	for i in range(page.boxes.length): free(page.boxes[i])
	while (page.boxes.length > 0): page.boxes.pop()
	for i in range(page.anchors.length): free(page.anchors[i])
	while (page.anchors.length > 0): page.anchors.pop()

void win_height_measures_clear(win_page* page):
	for i in range(page.height_measures.length): free(page.height_measures[i])
	while (page.height_measures.length > 0): page.height_measures.pop()

void win_page_free(win_page* page):
	if (page == 0): return
	win_runs_clear(page)
	__w_list_free(cast(__w_list*, page.fixed_items))
	win_height_measures_clear(page)
	__w_list_free(cast(__w_list*, page.height_measures))
	win_images_free(page.images)
	for i in range(page.stylesheets.length):
		if (page.stylesheets[i].css != 0): css_document_free(page.stylesheets[i].css)
		free(page.stylesheets[i].reference)
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
	if (node != 0): sheet.reference = strclone(win_attr(node, c"href"))
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
		sheet.reference = strclone(win_attr(node, c"href"))
		sheet.css = 0
		page.stylesheets.push(sheet)
	html_node* child = node.first_child
	while (child != 0):
		win_page_collect_styles(page, child)
		child = child.next_sibling

# Reconcile DOM stylesheet order after tree/text mutations. Preserve completed
# external sheets by node and URL; detached or replaced rules release ownership.
void win_page_refresh_styles_walk(win_page* page, html_node* node, list[win_stylesheet*] previous):
	if (node == 0 || win_tag(node, c"template")): return
	int embedded = win_tag(node, c"style")
	int linked = win_tag(node, c"link") && win_class_has(win_attr(node, c"rel"), c"stylesheet")
	if ((embedded || linked) && html_attribute_find(node.attributes, c"disabled") == 0):
		win_stylesheet* retained = 0
		for i in range(previous.length):
			if (previous[i].node == node): retained = previous[i]
		if (embedded):
			string_builder* source = string_new()
			html_node* child = node.first_child
			while (child != 0):
				if (child.kind == HTML_TEXT): string_append_bytes(source, child.text, child.text_length)
				child = child.next_sibling
			if (retained != 0 && retained.css != 0 && retained.css.length == source.length && strcmp(retained.css.source, source.data) == 0): page.stylesheets.push(retained)
			else: win_page_add_stylesheet_for_node(page, node, source.data, source.length)
			string_free(source)
		else if (retained != 0 && retained.reference != 0 && strcmp(retained.reference, win_attr(node, c"href")) == 0): page.stylesheets.push(retained)
		else:
			win_stylesheet* sheet = new win_stylesheet()
			sheet.node = node
			sheet.reference = strclone(win_attr(node, c"href"))
			page.stylesheets.push(sheet)
	html_node* child = node.first_child
	while (child != 0):
		win_page_refresh_styles_walk(page, child, previous)
		child = child.next_sibling

void win_page_refresh_styles(win_page* page):
	list[win_stylesheet*] previous = page.stylesheets
	page.stylesheets = new list[win_stylesheet*]
	win_page_refresh_styles_walk(page, page.html.root, previous)
	for i in range(previous.length):
		win_stylesheet* sheet = previous[i]
		if (sheet.node == 0): page.stylesheets.push(sheet)
		int kept = 0
		for j in range(page.stylesheets.length):
			if (page.stylesheets[j] == sheet): kept = 1
		if (kept == 0):
			css_document_free(sheet.css)
			free(sheet.reference)
			free(sheet)
	__w_list_free(cast(__w_list*, previous))
	page.width = 0

# Ancestors contribute computed values, so a child override cannot rebind a
# variable reference that was already resolved on its parent.
list[win_css_custom*] win_node_custom(win_page* page, html_node* node):
	list[win_css_custom*] values = new list[win_css_custom*]
	if (node.parent != 0):
		__w_list_free(cast(__w_list*, values))
		values = win_node_custom(page, node.parent)
		win_css_custom_inherit(values)
	int order = 0
	for i in range(page.stylesheets.length):
		css_document* css = page.stylesheets[i].css
		if (css != 0): win_css_rules(css, css.nodes, node, page.width, 0, &order, values)
	char* text = win_attr(node, c"style")
	css_document* inline_css = css_parse_declarations_n(text, strlen(text), 0)
	if (inline_css.failed == 0):
		for i in range(inline_css.nodes.length):
			css_node* d = inline_css.nodes[i]
			order = order + 1
			win_css_custom_collect(values, inline_css, d, win_cascade_author(d.important, 1, win_specificity_zero(), order))
	css_document_free(inline_css)
	win_css_custom_finish(values)
	return values

win_style win_computed_style(win_page* page, html_node* node, win_style style, win_style inherited):
	style.viewport_width = cast(float32, page.viewport_width)
	style.viewport_height = cast(float32, page.viewport_height)
	win_css_specified[42] winners
	for i in range(WIN_CSS_PROPERTY_COUNT): winners[i].present = 0
	int order = 0
	for i in range(page.stylesheets.length):
		css_document* css = page.stylesheets[i].css
		if (css != 0): win_css_rules(css, css.nodes, node, page.width, &winners[0], &order, 0)
	char* text = win_attr(node, c"style")
	css_document* inline_css = 0
	if (text[0] != 0):
		inline_css = css_parse_declarations_n(text, strlen(text), 0)
		if (inline_css.failed == 0):
			for i in range(inline_css.nodes.length):
				css_node* d = inline_css.nodes[i]
				order = order + 1
				win_css_collect(inline_css, d, win_cascade_author(d.important, 1, win_specificity_zero(), order), &winners[0])
	list[win_css_custom*] custom = new list[win_css_custom*]
	for p in range(WIN_CSS_PROPERTY_COUNT):
		if (winners[p].present && winners[p].pending != 0):
			__w_list_free(cast(__w_list*, custom))
			custom = win_node_custom(page, node)
			break
	list[css_document*] expanded = win_css_pending(&winners[0], custom)
	int root = node.kind == HTML_START && (node.parent == 0 || node.parent.kind == HTML_DOCUMENT)
	win_css_compute(&winners[0], &style, inherited, root)
	if (winners[0].present): style.author_paint = style.author_paint | WIN_PAINT_TEXT
	if (winners[8].present): style.author_paint = style.author_paint | WIN_PAINT_BACKGROUND
	if (winners[20].present || winners[21].present || winners[28].present): style.author_paint = style.author_paint | WIN_PAINT_BORDER
	# Paragraph UA block margins are 1em of the computed font size.
	if (win_tag(node, c"p")):
		if (winners[12].present == 0): style.margin_top = style.size
		if (winners[14].present == 0): style.margin_bottom = style.size
	for i in range(expanded.length): css_document_free(expanded[i])
	__w_list_free(cast(__w_list*, expanded))
	win_css_custom_free(custom)
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
	page.fixed_items = new list[win_fixed_item*]
	page.html = html
	page.images = new list[win_image*]
	page.height_measures = new list[win_height_measure*]
	page.boxes = new list[win_box*]
	page.stylesheets = new list[win_stylesheet*]
	win_page_collect_styles(page, html.root)
	page.runs = new list[win_run*]
	page.anchors = new list[win_anchor*]
	page.title = strclone(c"Untitled document")
	page.width = 0
	page.viewport_width = 920
	page.viewport_height = 600
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
			if (run.image != 0 || win_tag(run.node, c"canvas")): run.y = page.y + cast(float32, page.ascent) - run.height
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
	run.fixed = page.fixed_context
	run.hidden = style.hidden
	run.pointer_none = style.pointer_none
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
	box.fixed = page.fixed_context
	box.hidden = style.hidden
	box.pointer_none = style.pointer_none
	box.node = node
	box.x = x
	box.y = y
	box.width = width
	box.height = height
	box.author_paint = style.author_paint
	box.text_color = style.color
	box.color = style.background
	box.border_color = style.border_color
	box.border = style.border
	page.boxes.push(box)
	return box

win_style win_node_style(win_page* page, html_node* node, win_style inherited):
	win_style style = win_default_style()
	style.author_paint = inherited.author_paint & WIN_PAINT_TEXT
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
	style.pointer_none = inherited.pointer_none
	int block = win_block(node) || win_tag(node, c"html") || win_tag(node, c"body") || win_tag(node, c"form") || win_tag(node, c"fieldset") || win_tag(node, c"table") || win_tag(node, c"tr") || win_tag(node, c"hr")
	if (win_tag(node, c"h1") || win_tag(node, c"h2") || win_tag(node, c"h3") || win_tag(node, c"h4") || win_tag(node, c"h5") || win_tag(node, c"h6") || win_tag(node, c"ul") || win_tag(node, c"ol") || win_tag(node, c"blockquote") || win_tag(node, c"pre")):
		style.margin_top = 10
		style.margin_bottom = 8
	# Reader spacing is a UA body default, so author CSS can override it.
	if (win_tag(node, c"body")):
		style.margin_top = 20
		style.margin_right = 28
		style.margin_bottom = 28
		style.margin_left = 28
	if (win_tag(node, c"h1")): style.size = 36
	if (win_tag(node, c"h2")): style.size = 28
	if (win_tag(node, c"h3")): style.size = 23
	if (win_tag(node, c"h1") || win_tag(node, c"h2") || win_tag(node, c"h3") || win_tag(node, c"b") || win_tag(node, c"strong")): style.bold = 1
	if (win_tag(node, c"i") || win_tag(node, c"em")): style.flags = style.flags | UI_TEXT_ITALIC
	if (win_tag(node, c"pre")): style.pre = 1
	if (win_tag(node, c"a") && win_attr(node, c"href")[0] != 0):
		style.color = ui_color_new(0.08, 0.35, 0.72, 1.0)
		style.flags = style.flags | UI_TEXT_UNDERLINE
	style.display = 2
	if (block): style.display = 1
	return win_computed_style(page, node, style, inherited)

void win_layout_node_style(win_page* page, html_node* node, win_style style, char* href, float32 used_width);

void win_fixed_enqueue(win_page* page, html_node* node, win_style style, char* href):
	if (page.measuring): return
	if (page.fixed_items.length >= 20000):
		page.truncated = 1
		return
	win_fixed_item* item = new win_fixed_item()
	item.node = node
	item.style = style
	item.href = href
	item.x = page.x
	item.y = page.y
	page.fixed_items.push(item)

int win_layout_skipped(html_node* node):
	if (node.kind != HTML_START && node.kind != HTML_DOCUMENT): return 1
	if (win_tag(node, c"head") || win_tag(node, c"script") || win_tag(node, c"style") || win_tag(node, c"template")): return 1
	if (win_tag(node, c"input") && css_ascii_equal(win_attr(node, c"type"), c"hidden")): return 1
	return html_attribute_find(node.attributes, c"hidden") != 0

void win_layout_node(win_page* page, html_node* node, win_style inherited, char* href):
	if (node == 0 || page.truncated): return
	if (node.kind == HTML_TEXT):
		page.layout_node = node.parent
		win_text(page, node.text, node.text_length, inherited, href)
		return
	if (win_layout_skipped(node)): return
	win_layout_node_style(page, node, win_node_style(page, node, inherited), href, -1.0)

int win_layout_control(html_node* node):
	return win_tag(node, c"input") || win_tag(node, c"textarea") || win_tag(node, c"select") || win_tag(node, c"button")

# Canvas attributes are nonnegative integers; invalid/missing values use
# HTML defaults. The rendering layer independently bounds backing allocation.
int win_canvas_attribute(html_node* node, char* name, int fallback):
	char* text = win_attr(node, name)
	int i = 0
	while (html_space(text[i])): i = i + 1
	if (text[i] == '+'): i = i + 1
	if (text[i] < '0' || text[i] > '9'): return fallback
	int value = 0
	while (text[i] >= '0' && text[i] <= '9'):
		if (value > 100000): return 100000
		value = value * 10 + text[i] - '0'
		i = i + 1
	return min(value, 100000)

struct win_replaced_size:
	float32 width
	float32 height

# Return content dimensions. An indefinite containing width leaves percentages
# unresolved for intrinsic measurement; flex supplies its final used width.
win_replaced_size win_replaced_dimensions(win_page* page, html_node* node, win_style style, float32 containing_width, float32 used_width):
	win_replaced_size size
	size.width = 220.0
	size.height = 34.0
	int image_node = win_tag(node, c"img")
	int canvas_node = win_tag(node, c"canvas")
	float32 ratio_width = 0.0
	float32 ratio_height = 0.0
	win_image* image = win_image_find(page.images, node)
	int explicit_width = 0
	int explicit_height = 0
	if (canvas_node):
		size.width = cast(float32, win_canvas_attribute(node, c"width", 300))
		size.height = cast(float32, win_canvas_attribute(node, c"height", 150))
		ratio_width = size.width
		ratio_height = size.height
	elif (image_node):
		ratio_width = cast(float32, image.width)
		ratio_height = cast(float32, image.height)
		size.width = cast(float32, image.width)
		size.height = cast(float32, image.height)
		int width = atoi(win_attr(node, c"width"))
		int height = atoi(win_attr(node, c"height"))
		if (width > 100000): width = 100000
		if (height > 100000): height = 100000
		if (width > 0):
			size.width = cast(float32, width)
			explicit_width = 1
		if (height > 0):
			size.height = cast(float32, height)
			explicit_height = 1
	else:
		if (win_tag(node, c"button") || css_ascii_equal(win_attr(node, c"type"), c"submit")): size.width = 100.0
		if (win_tag(node, c"textarea")): size.height = 80.0
	if ((style.width >= 0.0 || style.width_percent) && (style.width_percent == 0 || containing_width >= 0.0)):
		size.width = win_css_used_size(style.width, style.width_percent, style.width_offset, containing_width)
		if (style.box_sizing): size.width = size.width - win_box_horizontal_extras(style)
		explicit_width = 1
	if (style.height >= 0.0):
		size.height = win_box_content_height(style)
		explicit_height = 1
	if (used_width >= 0.0):
		size.width = used_width
		explicit_width = 1
	if (size.width < 0.0): size.width = 0.0
	if ((image_node || canvas_node) && ratio_width > 0.0 && ratio_height > 0.0):
		if (explicit_width && explicit_height == 0): size.height = size.width * ratio_height / ratio_width
		if (explicit_height && explicit_width == 0): size.width = size.height * ratio_width / ratio_height
	if (used_width < 0.0 && (style.max_width >= 0.0 || style.max_width_percent) && (style.max_width_percent == 0 || containing_width >= 0.0)):
		float32 maximum = win_css_used_size(style.max_width, style.max_width_percent, style.max_width_offset, containing_width)
		if (style.box_sizing): maximum = maximum - win_box_horizontal_extras(style)
		if (maximum < 0.0): maximum = 0.0
		if (size.width > maximum):
			if ((image_node || canvas_node) && explicit_height == 0): size.height = size.height * maximum / size.width
			size.width = maximum
	return size

win_intrinsic_size win_intrinsic_node(win_page* page, html_node* node, win_style style):
	win_intrinsic_size result
	result.min_content = 0.0
	result.max_content = 0.0
	if (node.kind == HTML_TEXT): return win_intrinsic_text(node.text, node.text_length, style)
	win_image* image = win_image_find(page.images, node)
	if (win_layout_control(node) || win_tag(node, c"canvas") || (win_tag(node, c"img") && image != 0 && image.width > 0 && image.height > 0 && image.failed == 0)):
		win_style intrinsic_style = style
		intrinsic_style.width = -1.0
		intrinsic_style.max_width = -1.0
		win_replaced_size size = win_replaced_dimensions(page, node, intrinsic_style, -1.0, -1.0)
		result.min_content = size.width
		result.max_content = size.width
		return result
	if (win_tag(node, c"img")):
		char* alt = win_attr(node, c"alt")
		return win_intrinsic_text(alt, strlen(alt), style)
	html_node* child = node.first_child
	float32 inline_max = 0.0
	while (child != 0):
		win_style child_style = style
		int visible = child.kind == HTML_TEXT
		if (child.kind == HTML_START && win_layout_skipped(child) == 0):
			child_style = win_node_style(page, child, style)
			visible = child_style.display != 0 && child_style.position == 0
		if (visible):
			win_intrinsic_size size = win_intrinsic_node(page, child, child_style)
			if (child.kind == HTML_START):
				float32 extras = win_box_horizontal_extras(child_style)
				# Definite child widths contribute to their parent's intrinsic
				# size, while the child's own flex minimum stays content-based.
				if (child_style.width >= 0.0 && child_style.width_percent == 0):
					float32 preferred = child_style.width
					if (child_style.box_sizing): preferred = preferred - extras
					if (preferred < 0.0): preferred = 0.0
					size.min_content = preferred
					size.max_content = preferred
				if (child_style.max_width >= 0.0 && child_style.max_width_percent == 0):
					float32 maximum = child_style.max_width
					if (child_style.box_sizing): maximum = maximum - extras
					if (maximum < 0.0): maximum = 0.0
					if (size.min_content > maximum): size.min_content = maximum
					if (size.max_content > maximum): size.max_content = maximum
				size.min_content = size.min_content + extras
				size.max_content = size.max_content + extras
			if (size.min_content > result.min_content): result.min_content = size.min_content
			if (child.kind == HTML_START && child_style.display != 2):
				if (inline_max > result.max_content): result.max_content = inline_max
				inline_max = 0.0
				if (size.max_content > result.max_content): result.max_content = size.max_content
			else: inline_max = inline_max + size.max_content
		child = child.next_sibling
	if (inline_max > result.max_content): result.max_content = inline_max
	return result

list[win_layout_item*] win_layout_items_link(win_page* page, html_node* container, win_style style, char* href):
	list[win_layout_item*] items = new list[win_layout_item*]
	html_node* child = container.first_child
	while (child != 0):
		if (child.kind == HTML_START):
			if (win_layout_skipped(child) == 0):
				win_style computed = win_node_style(page, child, style)
				if (computed.display != 0 && computed.position): win_fixed_enqueue(page, child, computed, href)
				if (computed.display != 0 && computed.position == 0):
					win_layout_item* item = new win_layout_item()
					item.first = child
					item.end = child.next_sibling
					item.style = computed
					item.intrinsic = win_intrinsic_node(page, child, computed)
					items.push(item)
			child = child.next_sibling
		else:
			html_node* first = child
			string_builder* text = string_new()
			while (child != 0 && child.kind != HTML_START):
				if (child.kind == HTML_TEXT): string_append_bytes(text, child.text, child.text_length)
				child = child.next_sibling
			int visible = 0
			for i in range(text.length):
				if (html_space(text.data[i]) == 0): visible = 1
			if (visible):
				win_layout_item* item = new win_layout_item()
				item.first = first
				item.end = child
				item.anonymous = 1
				item.style = style
				# Anonymous items inherit text properties, not flex factors.
				item.style.flex_grow = 0.0
				item.style.flex_shrink = 1.0
				item.intrinsic = win_intrinsic_text(text.data, text.length, style)
				items.push(item)
			string_free(text)
	return items

list[win_layout_item*] win_layout_items(win_page* page, html_node* container, win_style style):
	return win_layout_items_link(page, container, style, c"")

# Translate all geometry emitted by an item together, preserving descendant
# painting, hit testing, form boxes and fragment anchors after alignment.
void win_flex_translate(win_page* page, win_layout_item* item, float32 dx, float32 dy):
	for i in range(item.box_first, item.box_end):
		page.boxes[i].x = page.boxes[i].x + dx
		page.boxes[i].y = page.boxes[i].y + dy
	for i in range(item.run_first, item.run_end):
		page.runs[i].x = page.runs[i].x + dx
		page.runs[i].y = page.runs[i].y + dy
	for i in range(item.anchor_first, item.anchor_end): page.anchors[i].y = page.anchors[i].y + dy

# Column cross sizes are determined before content-height measurement. The
# same width is used for final layout, so wrapping and replaced ratios agree.
float32 win_column_width(win_layout_item* item, win_style container, float32 available):
	win_style used = item.style
	int alignment = used.align_self
	if (alignment < 0 || item.anonymous): alignment = container.align_items
	float32 width = available
	if (item.anonymous == 0):
		width = win_box_border_width(used, available) - win_box_horizontal_extras(used)
		if (used.width < 0.0 && used.width_percent == 0 && (alignment != 0 || used.margin_left_auto || used.margin_right_auto)):
			if (width > item.intrinsic.max_content): width = item.intrinsic.max_content
	else if (alignment != 0 && width > item.intrinsic.max_content): width = item.intrinsic.max_content
	return width

float32 win_column_content_height(win_page* page, win_layout_item* item, float32 width, char* href):
	for i in range(page.height_measures.length):
		win_height_measure* cached = page.height_measures[i]
		if (cached.node == item.first && cached.width == width): return cached.height
	# Measurement owns geometry only; the HTML, images, styles and memo table
	# remain borrowed. Nothing from this pass enters painting or hit testing.
	win_page* probe = new win_page()
	probe.measuring = 1
	probe.html = page.html
	probe.images = page.images
	probe.stylesheets = page.stylesheets
	probe.height_measures = page.height_measures
	probe.width = page.width
	probe.viewport_width = page.viewport_width
	probe.viewport_height = page.viewport_height
	probe.runs = new list[win_run*]
	probe.boxes = new list[win_box*]
	probe.anchors = new list[win_anchor*]
	win_style measured = item.style
	measured.height = -1.0
	measured.margin_top = 0.0
	measured.margin_bottom = 0.0
	probe.right = width
	if (item.anonymous):
		html_node* text = item.first
		while (text != item.end):
			if (text.kind == HTML_TEXT): win_layout_node(probe, text, measured, href)
			text = text.next_sibling
	else:
		if (measured.display == 2): measured.display = 1
		probe.right = width + win_box_horizontal_extras(measured) + measured.margin_left + measured.margin_right
		win_layout_node_style(probe, item.first, measured, href, width)
	win_line_end(probe, 0)
	if (probe.truncated): page.truncated = 1
	float32 height = probe.y
	if (item.anonymous == 0): height = height - win_box_vertical_extras(measured)
	if (height < 0.0): height = 0.0
	win_runs_clear(probe)
	__w_list_free(cast(__w_list*, probe.runs))
	__w_list_free(cast(__w_list*, probe.boxes))
	__w_list_free(cast(__w_list*, probe.anchors))
	free(probe)
	if (page.height_measures.length < 20000): page.height_measures.push(new win_height_measure(item.first, width, height))
	return height

void win_layout_flex(win_page* page, html_node* node, win_style style, char* href):
	list[win_layout_item*] items = win_layout_items_link(page, node, style, href)
	float32 left = page.left
	float32 right = page.right
	float32 top = page.y
	float32 available = right - left
	int vertical = style.flex_column
	if (vertical == 0): win_flex_sizes(items, available, style.gap, 0)
	else:
		for i in range(items.length):
			win_layout_item* item = items[i]
			item.content_height = win_column_content_height(page, item, win_column_width(item, style, available), href)
		float32 main_available = -1.0
		if (style.height >= 0.0): main_available = win_box_content_height(style)
		win_flex_sizes(items, main_available, style.gap, 1)
	int first = 0
	int line_count = 0
	float32 line_top = top
	while (first < items.length):
		int end = items.length
		if (vertical == 0 && style.flex_wrap): end = win_flex_line_end(items, first, available, style.gap)
		list[win_layout_item*] line = new list[win_layout_item*]
		for i in range(first, end): line.push(items[i])
		if (vertical == 0): win_flex_sizes(line, available, style.gap, 0)
		float32 remaining = available - style.gap * cast(float32, line.length - 1)
		int auto_margins = 0
		if (vertical == 0):
			for i in range(line.length):
				win_layout_item* item = line[i]
				remaining = remaining - item.main_size
				if (item.anonymous == 0):
					remaining = remaining - win_box_horizontal_extras(item.style) - item.style.margin_left - item.style.margin_right
					auto_margins = auto_margins + item.style.margin_left_auto + item.style.margin_right_auto
			if (remaining > 0.0 && auto_margins > 0):
				for i in range(line.length):
					win_layout_item* item = line[i]
					if (item.anonymous): continue
					if (item.style.margin_left_auto): item.style.margin_left = remaining / cast(float32, auto_margins)
					if (item.style.margin_right_auto): item.style.margin_right = remaining / cast(float32, auto_margins)
				remaining = 0.0
		float32 cursor = left
		float32 spacing = style.gap
		if (vertical == 0):
			cursor = cursor + win_flex_offset(style.justify, remaining, line.length)
			spacing = spacing + win_flex_spacing(style.justify, remaining, line.length)
		else: cursor = line_top
		float32 cross = 0.0
		for i in range(line.length):
			win_layout_item* item = line[i]
			win_style used = item.style
			int alignment = used.align_self
			if (alignment < 0 || item.anonymous): alignment = style.align_items
			float32 width = item.main_size
			if (vertical):
				width = win_column_width(item, style, available)
				# Feed the allocated height into descendant layout, including
				# nested flex containers, before emitting final geometry.
				used.height = item.main_size
				if (used.box_sizing): used.height = used.height + win_box_vertical_extras(used)
			float32 outer_width = width
			if (item.anonymous == 0): outer_width = outer_width + win_box_horizontal_extras(used) + used.margin_left + used.margin_right
			page.left = cursor
			page.y = line_top
			if (vertical):
				page.left = left
				page.y = cursor
			page.right = page.left + outer_width
			page.x = page.left
			item.main_position = cursor
			item.main_extent = outer_width
			item.line_index = line_count
			item.box_first = page.boxes.length
			item.run_first = page.runs.length
			item.anchor_first = page.anchors.length
			if (item.anonymous):
				html_node* text = item.first
				while (text != item.end):
					if (text.kind == HTML_TEXT): win_layout_node(page, text, style, href)
					text = text.next_sibling
			else:
				if (used.display == 2): used.display = 1
				# Margins were allocated by the flex container, not block flow.
				used.margin_left_auto = 0
				used.margin_right_auto = 0
				win_layout_node_style(page, item.first, used, href, width)
			win_line_end(page, 0)
			item.box_end = page.boxes.length
			item.run_end = page.runs.length
			item.anchor_end = page.anchors.length
			item.cross_size = page.y - line_top
			if (vertical):
				item.cross_size = outer_width
				item.main_extent = page.y - cursor
			if (item.cross_size > cross): cross = item.cross_size
			if (vertical): cursor = page.y + spacing
			else: cursor = cursor + outer_width + spacing
		if (vertical): cross = available
		else if (style.flex_wrap == 0 && style.height >= 0.0): cross = win_box_content_height(style)
		float32 main_offset = 0.0
		float32 main_spacing = 0.0
		if (vertical && style.height >= 0.0):
			float32 free_space = win_box_content_height(style) - (cursor - spacing - top)
			main_offset = win_flex_offset(style.justify, free_space, line.length)
			main_spacing = win_flex_spacing(style.justify, free_space, line.length)
		for i in range(line.length):
			win_layout_item* item = line[i]
			int alignment = item.style.align_self
			if (alignment < 0 || item.anonymous): alignment = style.align_items
			float32 free_cross = cross - item.cross_size
			float32 offset = 0.0
			if (alignment == 2): offset = free_cross
			if (alignment == 3): offset = free_cross / 2.0
			if (vertical && item.anonymous == 0 && (item.style.margin_left_auto || item.style.margin_right_auto)):
				offset = 0.0
				if (free_cross > 0.0 && item.style.margin_left_auto):
					offset = free_cross
					if (item.style.margin_right_auto): offset = free_cross / 2.0
			float32 main_shift = main_offset + main_spacing * cast(float32, i)
			if (style.flex_reverse):
				float32 origin = left
				float32 extent = available
				if (vertical):
					origin = top
					extent = cursor - spacing - top
					if (style.height >= 0.0): extent = win_box_content_height(style)
				# Reflect the outer margin box; descendants retain their own
				# orientation and DOM/paint order stays unchanged.
				main_shift = 2.0 * origin + extent - 2.0 * item.main_position - item.main_extent - main_shift
			if (vertical): win_flex_translate(page, item, offset, main_shift)
			else:
				if (alignment == 0 && item.anonymous == 0 && item.style.height < 0.0 && item.box_first < item.box_end):
					win_box* box = page.boxes[item.box_first]
					box.height = cross - item.style.margin_top - item.style.margin_bottom
					if (box.height < win_box_vertical_extras(item.style)): box.height = win_box_vertical_extras(item.style)
				win_flex_translate(page, item, main_shift, offset)
		__w_list_free(cast(__w_list*, line))
		if (vertical): line_top = cursor
		else: line_top = line_top + cross + style.gap
		first = end
		line_count = line_count + 1
	# The initial align-content value stretches wrapped lines equally when
	# the definite container cross size leaves positive space.
	if (vertical == 0 && style.flex_wrap && style.height >= 0.0 && line_count > 0):
		float32 extra = win_box_content_height(style) - (line_top - top - style.gap)
		if (extra > 0.0):
			extra = extra / cast(float32, line_count)
			for i in range(items.length):
				win_layout_item* item = items[i]
				int alignment = item.style.align_self
				if (alignment < 0 || item.anonymous): alignment = style.align_items
				float32 dy = extra * cast(float32, item.line_index)
				if (alignment == 2): dy = dy + extra
				if (alignment == 3): dy = dy + extra / 2.0
				if (alignment == 0 && item.anonymous == 0 && item.style.height < 0.0 && item.box_first < item.box_end): page.boxes[item.box_first].height = page.boxes[item.box_first].height + extra
				win_flex_translate(page, item, 0.0, dy)
	for i in range(items.length): free(items[i])
	__w_list_free(cast(__w_list*, items))
	page.left = left
	page.right = right
	page.x = left
	page.y = top
	if (first > 0): page.y = line_top - style.gap

# Adjacent in-flow block margins share their positive maximum and negative
# minimum. Parent/child and empty-block-through collapse are separate contracts.
float32 win_collapsed_margin(float32 before, float32 after):
	float32 positive = 0.0
	float32 negative = 0.0
	if (before > positive): positive = before
	if (after > positive): positive = after
	if (before < negative): negative = before
	if (after < negative): negative = after
	return positive + negative

void win_layout_normal_children(win_page* page, html_node* parent, win_style inherited, char* href):
	int adjoining = 0
	float32 previous_bottom = 0.0
	html_node* child = parent.first_child
	while (child != 0 && page.truncated == 0):
		if (child.kind == HTML_TEXT):
			int whitespace = inherited.pre == 0
			for i in range(child.text_length):
				if (html_space(child.text[i]) == 0): whitespace = 0
			if (whitespace == 0): adjoining = 0
			win_layout_node(page, child, inherited, href)
		else if (win_layout_skipped(child) == 0):
			win_style style = win_node_style(page, child, inherited)
			int block = style.display == 1 || style.display == 3 || style.display == 4
			if (style.display != 0 && style.position == 0):
				if (block && adjoining): page.y = page.y + win_collapsed_margin(previous_bottom, style.margin_top) - previous_bottom - style.margin_top
				adjoining = block
				previous_bottom = style.margin_bottom
			win_layout_node_style(page, child, style, href, -1.0)
		child = child.next_sibling

void win_layout_node_style(win_page* page, html_node* node, win_style style, char* href, float32 used_width):
	if (page.truncated || style.display == 0): return
	if (style.position && node != page.positioned_root):
		win_fixed_enqueue(page, node, style, href)
		return
	int block = style.display == 1 || style.display == 3 || style.display == 4
	if (win_tag(node, c"a") && html_attribute_find(node.attributes, c"href") != 0): href = win_attr(node, c"href")
	page.layout_node = node
	float32 left = page.left
	float32 right = page.right
	int align = page.align
	win_box* box = 0
	float32 content_top = page.y
	int control = win_layout_control(node)
	win_image* image = win_image_find(page.images, node)
	int replaced = control || win_tag(node, c"canvas") || (win_tag(node, c"img") && image != 0 && image.width > 0 && image.height > 0 && image.failed == 0)
	win_replaced_size dimensions
	if (replaced): dimensions = win_replaced_dimensions(page, node, style, right - left, used_width)
	if (block):
		win_line_end(page, 0)
		page.align = style.align
		page.y = page.y + cast(float32, style.margin_top)
		float32 ml = cast(float32, style.margin_left)
		float32 mr = cast(float32, style.margin_right)
		float32 width = win_box_border_width(style, right - left)
		if (used_width >= 0.0): width = used_width + win_box_horizontal_extras(style)
		if (replaced): width = dimensions.width + win_box_horizontal_extras(style)
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
		anchor.fixed = page.fixed_context
		anchor.id = id
		anchor.y = page.y
		page.anchors.push(anchor)
	if (win_tag(node, c"br")):
		win_line_end(page, 1)
		return
	if (control):
		win_line_end(page, 0)
		float32 width = dimensions.width + win_box_horizontal_extras(style)
		float32 height = dimensions.height + win_box_vertical_extras(style)
		if (box == 0): box = win_box_add(page, node, style, page.left, page.y, width, height)
		if (block): page.y = page.y + dimensions.height
		else: page.y = page.y + height + 6.0
	else if (win_tag(node, c"img") || win_tag(node, c"canvas")):
		if (replaced):
			float32 iw = dimensions.width
			float32 ih = dimensions.height
			if (page.x + iw > page.right && page.x > page.left): win_line_end(page, 0)
			win_run* run = new win_run()
			run.fixed = page.fixed_context
			run.hidden = style.hidden
			run.pointer_none = style.pointer_none
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
		if (style.display == 3):
			win_layout_flex(page, node, style, href)
		else if (style.display == 4):
			list[win_layout_item*] items = win_layout_items_link(page, node, style, href)
			int columns = style.columns
			if (columns < 1): columns = 1
			float32 row_left = page.left
			float32 row_right = page.right
			float32 row_top = page.y
			float32 row_bottom = row_top
			float32 cell_width = (row_right - row_left - style.gap * cast(float32, columns - 1)) / cast(float32, columns)
			if (cell_width < 0.0): cell_width = 0.0
			int column = 0
			float32 cursor = row_left
			float32 item_gap = style.gap
			for i in range(items.length):
				win_layout_item* item = items[i]
				float32 width = cell_width
				page.left = cursor
				page.right = page.left + width
				page.x = page.left
				page.y = row_top
				if (item.anonymous):
					html_node* text = item.first
					while (text != item.end):
						if (text.kind == HTML_TEXT): win_layout_node(page, text, style, href)
						text = text.next_sibling
				else:
					win_style item_style = item.style
					if (item_style.display == 2): item_style.display = 1
					win_layout_node_style(page, item.first, item_style, href, -1.0)
				win_line_end(page, 0)
				if (page.y > row_bottom): row_bottom = page.y
				cursor = cursor + width + item_gap
				column = column + 1
				if (column == columns):
					column = 0
					cursor = row_left
					row_top = row_bottom + style.gap
			for i in range(items.length): free(items[i])
			__w_list_free(cast(__w_list*, items))
			page.left = row_left
			page.right = row_right
			page.x = row_left
			page.y = row_bottom
		else: win_layout_normal_children(page, node, style, href)

	if (block):
		win_line_end(page, 0)
		if (style.height >= 0.0): page.y = content_top + win_box_content_height(style)
		page.y = page.y + cast(float32, style.padding_bottom + style.border)
		box.height = page.y - box.y
		page.y = page.y + cast(float32, style.margin_bottom)
	page.left = left
	page.right = right
	page.align = align
	if (block): page.x = left

# Store fixed geometry in document coordinates so existing painting, native
# hit testing, selection and DOM rectangles all use the same scroll transform.
void win_page_set_scroll(win_page* page, float32 scroll):
	if (page == 0): return
	float32 delta = scroll - page.scroll_y
	if (delta == 0.0): return
	for i in range(page.boxes.length):
		if (page.boxes[i].fixed): page.boxes[i].y = page.boxes[i].y + delta
	for i in range(page.runs.length):
		if (page.runs[i].fixed): page.runs[i].y = page.runs[i].y + delta
	for i in range(page.anchors.length):
		if (page.anchors[i].fixed): page.anchors[i].y = page.anchors[i].y + delta
	page.scroll_y = scroll

float32 win_fixed_inset(win_inset inset, float32 extent):
	if (inset.percent): return win_css_bound_length(cast(float64, inset.value) * cast(float64, extent) / 100.0 + cast(float64, inset.offset))
	return inset.value

void win_layout_fixed(win_page* page, win_fixed_item* item):
	win_page saved = page[0]
	win_style style = item.style
	float32 width = cast(float32, page.viewport_width)
	float32 height = cast(float32, page.viewport_height)
	float32 top = win_fixed_inset(style.insets[0], height)
	float32 right = win_fixed_inset(style.insets[1], width)
	float32 bottom = win_fixed_inset(style.insets[2], height)
	float32 left = win_fixed_inset(style.insets[3], width)
	int has_top = style.insets[0].specified
	int has_right = style.insets[1].specified
	int has_bottom = style.insets[2].specified
	int has_left = style.insets[3].specified
	float32 available = width
	if (has_left): available = available - left
	if (has_right): available = available - right
	if (available < 0.0): available = 0.0
	# Percentages always resolve against the viewport, not the inset-reduced
	# available space. An auto width stretches only with both sides specified.
	if (style.width_percent):
		style.width = win_css_bound_length(cast(float64, style.width) * cast(float64, width) / 100.0 + cast(float64, style.width_offset))
		if (style.width < 0.0): style.width = 0.0
		style.width_percent = 0
		style.width_offset = 0.0
	if (style.max_width_percent):
		style.max_width = win_css_bound_length(cast(float64, style.max_width) * cast(float64, width) / 100.0 + cast(float64, style.max_width_offset))
		if (style.max_width < 0.0): style.max_width = 0.0
		style.max_width_percent = 0
		style.max_width_offset = 0.0
	if (style.width < 0.0 && (has_left == 0 || has_right == 0)):
		win_intrinsic_size intrinsic = win_intrinsic_node(page, item.node, style)
		float32 content = available - win_box_horizontal_extras(style) - style.margin_left - style.margin_right
		if (content < intrinsic.min_content): content = intrinsic.min_content
		if (content > intrinsic.max_content): content = intrinsic.max_content
		style.width = content
		if (style.box_sizing): style.width = style.width + win_box_horizontal_extras(style)
	int replaced = win_layout_control(item.node) || win_tag(item.node, c"canvas") || win_tag(item.node, c"img")
	if (style.height < 0.0 && has_top && has_bottom && replaced == 0):
		style.height = height - top - bottom - style.margin_top - style.margin_bottom
		if (style.box_sizing == 0): style.height = style.height - win_box_vertical_extras(style)
		if (style.height < 0.0): style.height = 0.0
	if (style.display == 2): style.display = 1
	page.positioned_root = item.node
	page.fixed_context = 1
	page.left = 0.0
	if (has_left): page.left = left
	else if (has_right == 0): page.left = item.x
	page.right = page.left + available
	page.x = page.left
	page.y = 0.0
	if (has_top): page.y = top
	else if (has_bottom == 0): page.y = item.y
	page.line_start = page.runs.length
	page.line_height = 0
	page.ascent = 0
	page.descent = 0
	page.space = 0
	int box_first = page.boxes.length
	int run_first = page.runs.length
	int anchor_first = page.anchors.length
	int fixed_first = page.fixed_items.length
	win_layout_node_style(page, item.node, style, item.href, -1.0)
	win_line_end(page, 0)
	win_box* root = page.boxes[box_first]
	float32 dx = 0.0
	float32 dy = 0.0
	if (has_left == 0 && has_right): dx = width - right - style.margin_right - root.width - root.x
	if (has_top == 0 && has_bottom): dy = height - bottom - style.margin_bottom - root.height - root.y
	for i in range(box_first, page.boxes.length):
		page.boxes[i].x = page.boxes[i].x + dx
		page.boxes[i].y = page.boxes[i].y + dy
	for i in range(run_first, page.runs.length):
		page.runs[i].x = page.runs[i].x + dx
		page.runs[i].y = page.runs[i].y + dy
	for i in range(anchor_first, page.anchors.length): page.anchors[i].y = page.anchors[i].y + dy
	# Only static-position fallback follows a moved ancestor. Explicit nested
	# fixed insets remain relative to the viewport.
	for i in range(fixed_first, page.fixed_items.length):
		page.fixed_items[i].x = page.fixed_items[i].x + dx
		page.fixed_items[i].y = page.fixed_items[i].y + dy
	int truncated = page.truncated
	page[0] = saved
	page.truncated = truncated

void win_page_set_viewport(win_page* page, int width, int height):
	if (page == 0): return
	page.viewport_explicit = 1
	if (width < 0): width = 0
	if (height < 0): height = 0
	if (page.viewport_width != width || page.viewport_height != height): page.width = 0
	page.viewport_width = width
	page.viewport_height = height

# Root/body solid backgrounds propagate to the document canvas. Remove the
# source box's paint to avoid compositing translucent backgrounds twice.
# https://www.w3.org/TR/css-backgrounds-3/#special-backgrounds
void win_page_canvas_background(win_page* page, html_node* root, win_style root_style, html_node* body, win_style body_style):
	if (root == 0 || root_style.display == 0): return
	html_node* source = root
	win_style canvas = root_style
	if (canvas.background.a == 0.0 && body != 0):
		source = body
		canvas = body_style
	if (canvas.display == 0 || canvas.background.a == 0.0): return
	win_box* source_box = win_page_node_box(page, source)
	if (source_box != 0): source_box.color.a = 0.0
	win_style paint = win_default_style()
	paint.background = canvas.background
	float32 width = cast(float32, page.width)
	if (page.viewport_width > page.width): width = cast(float32, page.viewport_width)
	float32 height = page.height
	if (height < cast(float32, page.viewport_height)): height = cast(float32, page.viewport_height)
	win_box* background = win_box_add(page, page.html.root, paint, 0.0, 0.0, width, height)
	int at = page.boxes.length - 1
	while (at > 0):
		page.boxes[at] = page.boxes[at - 1]
		at = at - 1
	page.boxes[0] = background

void win_page_layout(win_page* page, int width):
	if (width < 160): width = 160
	win_runs_clear(page)
	win_height_measures_clear(page)
	float32 scroll = page.scroll_y
	page.scroll_y = 0.0
	page.width = width
	if (page.viewport_explicit == 0): page.viewport_width = width
	page.left = 0.0
	page.right = cast(float32, width)
	page.x = page.left
	page.y = 0.0
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
	html_node* root = page.html.root.first_child
	while (root != 0 && win_tag(root, c"html") == 0): root = root.next_sibling
	html_node* body = 0
	win_style root_style = win_default_style()
	win_style body_style = win_default_style()
	if (root != 0):
		root_style = win_node_style(page, root, root_style)
		body = root.first_child
		while (body != 0 && win_tag(body, c"body") == 0): body = body.next_sibling
		if (body != 0): body_style = win_node_style(page, body, root_style)
	float32 bottom = 0.0
	for i in range(page.boxes.length):
		# The root's flow height already includes the body's bottom margin.
		if (page.boxes[i].node != root && page.boxes[i].y + page.boxes[i].height > bottom): bottom = page.boxes[i].y + page.boxes[i].height
	for i in range(page.runs.length):
		if (page.runs[i].y + page.runs[i].height > bottom): bottom = page.runs[i].y + page.runs[i].height
	if (body != 0 && body_style.display != 0 && bottom > 0.0): bottom = bottom + body_style.margin_bottom
	page.height = page.y
	if (bottom > page.height): page.height = bottom
	win_page_canvas_background(page, root, root_style, body, body_style)
	int fixed = 0
	while (fixed < page.fixed_items.length && page.truncated == 0):
		win_layout_fixed(page, page.fixed_items[fixed])
		fixed = fixed + 1
	win_page_set_scroll(page, scroll)

# Follow the painter's reverse run/box order. pointer-events is inherited
# during style computation, so descendants can explicitly restore auto.
html_node* win_page_node_hit(win_page* page, float32 x, float32 y):
	int i = page.runs.length - 1
	while (i >= 0):
		win_run* run = page.runs[i]
		if (run.hidden == 0 && run.pointer_none == 0 && x >= run.x && x < run.x + run.width && y >= run.y && y < run.y + run.height): return run.node
		i = i - 1
	i = page.boxes.length - 1
	while (i >= 0):
		win_box* box = page.boxes[i]
		if (box.hidden == 0 && box.pointer_none == 0 && x >= box.x && x < box.x + box.width && y >= box.y && y < box.y + box.height): return box.node
		i = i - 1
	return 0

char* win_page_hit(win_page* page, float32 x, float32 y):
	html_node* node = win_page_node_hit(page, x, y)
	while (node != 0):
		if (win_tag(node, c"a") && win_attr(node, c"href")[0] != 0): return win_attr(node, c"href")
		node = node.parent
	return c""

float32 win_page_anchor(win_page* page, char* id):
	for i in range(page.anchors.length):
		if (strcmp(page.anchors[i].id, id) == 0): return page.anchors[i].y
	return 0.0
