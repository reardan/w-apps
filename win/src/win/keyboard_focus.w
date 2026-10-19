# Sequential focus for this browser's light DOM, bounded by DOM/depth limits.
# Positive tabindex precedes zero/native entries; equal values keep DOM order.
import win.input

struct win_focus_entry:
	html_node* node
	int index
	int order

int win_focus_before(win_focus_entry* a, win_focus_entry* b):
	if (a.index > 0 && b.index == 0): return 1
	if (a.index == 0 && b.index > 0): return 0
	if (a.index != b.index): return a.index < b.index
	return a.order < b.order

void win_focus_collect(win_page* page, html_node* node, win_style inherited, int depth, int* visited, html_node* current, win_focus_entry* origin, list[win_focus_entry*] entries):
	if (node == 0 || depth >= 128 || visited[0] >= 20000): return
	visited[0] = visited[0] + 1
	if (node == current): origin.order = visited[0]
	if (win_layout_skipped(node)): return
	win_style style = inherited
	if (node.kind == HTML_START): style = win_node_style(page, node, inherited)
	if (style.display == 0): return
	int index = win_focus_tab_index(node)
	if (node.kind == HTML_START && index >= 0 && style.hidden == 0 && (win_form_control(node) == 0 || win_form_disabled(node) == 0)):
		entries.push(new win_focus_entry(node, index, visited[0]))
	html_node* child = node.first_child
	while (child != 0 && visited[0] < 20000):
		win_focus_collect(page, child, style, depth + 1, visited, current, origin, entries)
		child = child.next_sibling

html_node* win_focus_next(win_page* page, html_node* current, int reverse):
	list[win_focus_entry*] entries = new list[win_focus_entry*]
	win_focus_entry origin
	origin.node = current
	origin.index = 0
	origin.order = -1
	if (current != 0):
		origin.index = win_focus_tab_index(current)
		if (origin.index < 0): origin.index = 0
	int visited = 0
	win_focus_collect(page, page.html.root, win_default_style(), 0, &visited, current, &origin, entries)
	win_focus_entry* best = 0
	win_focus_entry* wrap = 0
	for win_focus_entry* entry in entries:
		int precedes = win_focus_before(entry, &origin)
		int follows = win_focus_before(&origin, entry)
		if (wrap == 0 || reverse == 0 && win_focus_before(entry, wrap) || reverse && win_focus_before(wrap, entry)): wrap = entry
		if (current == 0 || origin.order < 0): continue
		if (reverse == 0 && follows || reverse && precedes):
			if (best == 0 || reverse == 0 && win_focus_before(entry, best) || reverse && win_focus_before(best, entry)): best = entry
	if (best == 0): best = wrap
	html_node* result = 0
	if (best != 0): result = best.node
	for win_focus_entry* entry in entries: free(entry)
	__w_list_free(cast(__w_list*, entries))
	return result

int win_keyboard_tab(win_script* script, win_forms* forms, ui_context* ctx, gfx_event* event):
	if (event.kind != GFX_EVENT_CHAR || event.code != 9 || (event.mods & (GFX_MOD_CTRL | GFX_MOD_ALT | GFX_MOD_SUPER))): return 0
	html_node* current = script.active_focus
	if (ctx.focus > 0 && ctx.focus < 1000): current = 0
	html_node* next = win_focus_next(script.page, current, (event.mods & GFX_MOD_SHIFT) != 0)
	if (next != 0):
		win_script_focus_input(script, next, 0)
		if (forms != 0): win_input_apply_focus(script, forms, ctx)
	return 1

int win_focus_contains(html_node* ancestor, html_node* node):
	for i in range(128):
		if (node == 0): return 0
		if (node == ancestor): return 1
		node = node.parent
	return 0

void win_focus_ring(ui_renderer* renderer, ui_rect rect, ui_color color):
	if (rect.w <= 0.0 || rect.h <= 0.0): return
	float32 edge = 2.0
	ui_render_rect(renderer, ui_rect_new(rect.x - edge, rect.y - edge, rect.w + edge * 2.0, edge), color)
	ui_render_rect(renderer, ui_rect_new(rect.x - edge, rect.y + rect.h, rect.w + edge * 2.0, edge), color)
	ui_render_rect(renderer, ui_rect_new(rect.x - edge, rect.y, edge, rect.h), color)
	ui_render_rect(renderer, ui_rect_new(rect.x + rect.w, rect.y, edge, rect.h), color)
