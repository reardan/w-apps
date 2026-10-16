import win.document
import win.interactive_worker
import win.loader
import win.resources
import win.forms
import win.script
import win.fetch
import graphics.ui.widgets

struct win_history_entry:
	char* address
	float32 scroll

struct win_browser:
	int isolated
	win_interactive_worker* interactive
	int interactive_sequence
	int interactive_tick
	char* interactive_html
	win_page* page
	win_resources* resources
	win_forms* forms
	win_script* script
	win_fetch_context* fetches
	win_storage_context* local_storage
	win_storage_context* session_storage
	int owns_local_storage
	int script_failures
	int resource_failures
	int restore_pending
	int restore_history
	float32 restore_scroll
	char* new_tab
	win_load* load
	char* executable
	char* home
	char* address
	char* status
	list[win_history_entry*] history
	int current
	int pending_history
	int width
	int viewport_width
	int viewport_height
	int viewport_ready
	ui_textarea_state input
	ui_scroll_state scroll

void win_status(win_browser* browser, char* text):
	free(browser.status)
	browser.status = strclone(text)

void win_browser_init(win_browser* b, char* executable, char* home):
	b.isolated = 0
	b.interactive = 0
	b.interactive_sequence = -1
	b.interactive_tick = 0
	b.interactive_html = strclone(c"")
	b.page = 0
	b.resources = 0
	b.forms = 0
	b.script = 0
	b.fetches = 0
	b.local_storage = win_storage_new()
	b.session_storage = win_storage_new()
	b.owns_local_storage = 1
	b.script_failures = 0
	b.resource_failures = 0
	b.restore_pending = 0
	b.restore_history = 0
	b.restore_scroll = 0.0
	b.new_tab = 0
	b.load = 0
	b.executable = strclone(executable)
	b.home = strclone(home)
	b.address = strclone(c"")
	b.status = strclone(c"Open an HTML file or an http:// or https:// address")
	b.history = new list[win_history_entry*]
	b.current = -1
	b.pending_history = -1
	b.width = 920
	b.viewport_width = 920
	b.viewport_height = 600
	b.viewport_ready = 0
	ui_textarea_init(&b.input)
	ui_scroll_init(&b.scroll)

void win_browser_free(win_browser* b):
	win_interactive_free(b.interactive)
	free(b.interactive_html)
	win_load_free(b.load)
	free(b.new_tab)
	win_fetch_free(b.fetches)
	win_script_free(b.script)
	if (b.owns_local_storage): win_storage_free(b.local_storage)
	win_storage_free(b.session_storage)
	win_resources_free(b.resources)
	win_forms_free(b.forms)
	win_page_free(b.page)
	for i in range(b.history.length):
		free(b.history[i].address)
		free(b.history[i])
	__w_list_free(cast(__w_list*, b.history))
	ui_textarea_free(&b.input)
	free(b.executable)
	free(b.home)
	free(b.address)
	free(b.status)

void win_stop(win_browser* b):
	win_interactive_free(b.interactive)
	b.interactive = 0
	win_fetch_stop(b.fetches)
	win_resources_stop(b.resources)
	win_script_stop(b.script)
	win_load_free(b.load)
	b.load = 0
	win_status(b, c"Loading stopped")

void win_commit_address(win_browser* b, char* address, int target):
	free(b.address)
	b.address = strclone(address)
	if (target >= 0): b.current = target
	else if (target == -1):
		while (b.history.length > b.current + 1):
			win_history_entry* removed = b.history.pop()
			free(removed.address)
			free(removed)
		if (b.history.length == 128):
			free(b.history[0].address)
			free(b.history[0])
			for i in range(127): b.history[i] = b.history[i + 1]
			b.history.pop()
		win_history_entry* entry = new win_history_entry()
		entry.address = strclone(address)
		entry.scroll = 0.0
		b.history.push(entry)
		b.current = b.history.length - 1
	if (b.current >= 0):
		free(b.history[b.current].address)
		b.history[b.current].address = strclone(address)
	ui_textarea_set(&b.input, address)
	ui_textarea_set_caret(&b.input, strlen(address))

void win_scroll_fragment(win_browser* b):
	b.scroll.offset_y = 0.0
	int index = win_fragment_index(b.address)
	if (b.address[index] == '#'):
		char* fragment = url_unquote(b.address + index + 1)
		if (fragment != 0):
			b.scroll.offset_y = win_page_anchor(b.page, fragment)
			free(fragment)

# target -1 adds history, -2 reloads, >=0 traverses an existing entry.
void win_navigate_request(win_browser* b, char* reference, char* base, int target, char* method, char* body):
	char* address = win_resolve(base, reference)
	if (address == 0):
		win_status(b, c"Use an HTML file path or a valid http:// or https:// URL")
		return
	if (b.current >= 0): b.history[b.current].scroll = b.scroll.offset_y
	if (b.isolated):
		if (strcmp(method, c"GET") != 0):
			win_status(b, c"Isolated navigation accepts GET; submit forms inside the worker")
			free(address)
			return
		win_stop(b)
		b.pending_history = target
		b.interactive_sequence = -1
		b.interactive = win_interactive_start(b.executable, address, b.home, 30000, WIN_INTERACTIVE_LIMIT)
		ui_textarea_set(&b.input, address)
		win_status(b, c"Loading isolated content…")
		free(address)
		return
	char* old_path = win_without_fragment(b.address)
	char* new_path = win_without_fragment(address)
	int same = b.page != 0 && strcmp(old_path, new_path) == 0 && target != -2 && strcmp(method, c"GET") == 0
	free(old_path)
	free(new_path)
	if (same):
		win_load_free(b.load)
		b.load = 0
		win_commit_address(b, address, target)
		win_scroll_fragment(b)
		if (target >= 0): b.scroll.offset_y = b.history[target].scroll
		b.restore_pending = win_resources_done(b.resources) == 0
		b.restore_history = target >= 0
		b.restore_scroll = b.scroll.offset_y
		win_status(b, c"Ready")
	else:
		win_stop(b)
		b.pending_history = target
		b.load = win_load_start_request(b.executable, address, method, body)
		ui_textarea_set(&b.input, address)
		win_status(b, c"Loading…")
	free(address)

void win_navigate(win_browser* b, char* reference, char* base, int target):
	win_navigate_request(b, reference, base, target, c"GET", c"")

void win_history_go(win_browser* b, int delta):
	int index = b.current + delta
	if (index < 0 || index >= b.history.length): return
	win_navigate(b, b.history[index].address, c"", index)

void win_browser_poll_document(win_browser* b):
	if (b.load == 0 || win_load_poll(b.load) == 0): return
	if (b.load.error != 0): win_status(b, b.load.error)
	else:
		win_page* page = win_page_parse(b.load.source, b.load.length)
		if (page == 0): win_status(b, c"Invalid UTF-8 or HTML document exceeds parser limits")
		else:
			win_fetch_free(b.fetches)
			b.fetches = 0
			win_script_free(b.script)
			win_resources_free(b.resources)
			win_forms_free(b.forms)
			win_page_free(b.page)
			b.page = page
			b.forms = win_forms_new(page)
			b.resources = win_resources_start(b.executable, page, b.load.address)
			b.script = win_script_new(page)
			b.script.modules = win_modules_new(b.script.runtime, b.executable, b.load.address)
			win_script_bind_storage(b.script, b.local_storage, b.session_storage, b.load.address)
			b.fetches = win_fetch_new(b.script.runtime, b.executable, b.load.address)
			b.script_failures = 0
			b.resource_failures = 0
			win_page_layout(page, b.width)
			win_commit_address(b, b.load.address, b.pending_history)
			win_scroll_fragment(b)
			if (b.pending_history >= 0): b.scroll.offset_y = b.history[b.current].scroll
			b.restore_pending = 1
			b.restore_history = b.pending_history >= 0
			b.restore_scroll = b.scroll.offset_y
			if (page.truncated): win_status(b, c"Display limit reached · showing the first 20,000 text runs")
			else: win_status(b, c"Ready")
	win_load_free(b.load)
	b.load = 0

int win_browser_loading(win_browser* b):
	if (b.isolated): return b.interactive != 0 && b.interactive.busy
	return b.load != 0 || win_resources_done(b.resources) == 0 || (b.script != 0 && b.script.ready == 0) || win_fetch_pending(b.fetches) != 0

# The snapshot is display-only: never create a script or fetch realm for it.
void win_browser_poll_interactive(win_browser* b):
	if (b.interactive == 0): return
	win_interactive_worker* worker = b.interactive
	int ready = win_interactive_poll(worker)
	if (ready < 0):
		win_status(b, worker.error)
		return
	if (ready == 0): return
	if (b.interactive_sequence != worker.sequence):
		int first = b.interactive_sequence < 0
		b.interactive_sequence = worker.sequence
		b.interactive_tick = process_monotonic_ms()
		if (first || strcmp(b.interactive_html, worker.html) != 0):
			win_page* page = win_page_parse(worker.html, strlen(worker.html))
			if (page == 0):
				win_interactive_fail(worker, 4, c"Invalid isolated display document")
				win_status(b, worker.error)
				return
			win_resources_free(b.resources)
			win_forms_free(b.forms)
			win_page_free(b.page)
			b.page = page
			b.forms = win_forms_new(page)
			b.resources = win_resources_start(b.executable, page, worker.address)
			free(b.interactive_html)
			b.interactive_html = strclone(worker.html)
			win_page_layout(page, b.width)
		free(b.page.title)
		b.page.title = strclone(worker.title)
		if (first || strcmp(b.address, worker.address) != 0):
			int target = -1
			if (first): target = b.pending_history
			win_commit_address(b, worker.address, target)
			win_scroll_fragment(b)
			if (target >= 0): b.scroll.offset_y = b.history[target].scroll
		b.script_failures = worker.script_failures
		b.resource_failures = worker.resource_failures
		win_status(b, c"Isolated content · canvas unavailable")
		if (b.script_failures || b.resource_failures): win_status(b, c"Isolated content completed with script or resource errors")
	if (win_resources_poll(b.resources) && b.page != 0): win_page_layout(b.page, b.width)
	# Leave a UI frame after each reply for input before scheduling another tick.
	if (process_monotonic_ms() - b.interactive_tick >= 100):
		win_interactive_request(worker, 1, 0, c"")

int win_browser_interactive_event(win_browser* b, html_node* node, int kind, char* value):
	if (b.interactive == 0 || node == 0): return 0
	int id = atoi(win_attr(node, c"data-win-node"))
	if (id <= 0 || win_interactive_request(b.interactive, kind, id, value) == 0):
		win_status(b, c"Isolated content busy · retry input when ready")
		return 0
	return 1

# Native X11 UI coordinates and framebuffer pixels are 1:1. Headless callers
# use the explicit initial 920x600 viewport; a GUI realm waits for its surface.
void win_browser_sync_viewport(win_browser* b):
	win_script_set_viewport(b.script, b.viewport_width, b.viewport_height, 1.0, 0.0, cast(float64, b.scroll.offset_y))
	if (b.script != 0): b.script.layout_width = b.width

void win_browser_set_viewport(win_browser* b, int width, int height):
	int resized = b.viewport_ready && (b.viewport_width != width || b.viewport_height != height)
	b.viewport_width = width
	b.viewport_height = height
	b.viewport_ready = 1
	b.width = max(160, width - 12)
	win_browser_sync_viewport(b)
	if (resized && b.script != 0): win_script_dispatch(b.script, b.script.window_node, c"resize")

void win_browser_poll(win_browser* b):
	if (b.isolated):
		win_browser_poll_interactive(b)
		return
	win_browser_poll_document(b)
	int changed = win_resources_poll(b.resources)
	win_browser_sync_viewport(b)
	if (win_script_graphics_available && b.viewport_ready == 0): return
	win_script_run_pending(b.script, b.resources)
	if (win_fetch_poll(b.fetches) && b.script != 0): win_script_result(b.script, b.script.runtime.completion)
	win_script_poll(b.script)
	if (win_resources_refresh(b.resources)): changed = 1
	if (b.script != 0):
		if (b.script.dirty): changed = 1
		b.script.dirty = 0
		if (b.script.failures > b.script_failures):
			win_status(b, b.script.error)
			b.script_failures = b.script.failures
	if (b.resources != 0 && b.resources.failed > b.resource_failures):
		win_status(b, c"Page loaded with resource errors")
		b.resource_failures = b.resources.failed
	if (changed && b.page != 0): win_page_layout(b.page, b.width)
	if (b.page != 0 && b.restore_pending && (changed || win_browser_loading(b) == 0)):
		if (b.restore_history): b.scroll.offset_y = b.restore_scroll
		else: win_scroll_fragment(b)
		if (win_browser_loading(b) == 0): b.restore_pending = 0

char* win_browser_base(win_browser* b):
	if (b.resources != 0): return b.resources.base
	return b.address

# GET replaces the action query and preserves its fragment. POST sends the
# encoded body through the same cancellable loader as ordinary navigation.
void win_browser_submit(win_browser* b, html_node* submitter):
	if (b.forms == 0 || submitter == 0): return
	html_node* form = win_form_owner(b.forms, submitter)
	if (form == 0): return
	if (win_form_has(submitter, c"formnovalidate") == 0 && win_forms_valid(b.forms, form) == 0):
		win_status(b, b.forms.error)
		return
	if (win_script_dispatch(b.script, form, c"submit") == 0): return
	char* data = win_forms_data(b.forms, form, submitter)
	if (data == 0):
		win_status(b, b.forms.error)
		return
	char* method = win_attr(form, c"method")
	if (win_form_has(submitter, c"formmethod")): method = win_attr(submitter, c"formmethod")
	char* encoding = win_attr(form, c"enctype")
	if (win_form_has(submitter, c"formenctype")): encoding = win_attr(submitter, c"formenctype")
	char* action = win_attr(form, c"action")
	if (win_form_has(submitter, c"formaction")): action = win_attr(submitter, c"formaction")
	if (action[0] == 0): action = b.address
	char* address = win_resolve(win_browser_base(b), action)
	if (address == 0): win_status(b, c"Invalid form action")
	else if (encoding[0] != 0 && strcmp(encoding, c"application/x-www-form-urlencoded") != 0): win_status(b, c"Only URL-encoded forms are supported")
	else if (strcmp(method, c"post") == 0 || strcmp(method, c"POST") == 0):
		if (win_remote(address)): win_navigate_request(b, address, c"", -1, c"POST", data)
		else: win_status(b, c"POST forms require an HTTP or HTTPS address")
	else if (method[0] == 0 || strcmp(method, c"get") == 0 || strcmp(method, c"GET") == 0):
		if (win_remote(address) == 0): win_status(b, c"GET forms require an HTTP or HTTPS address")
		else:
			int end = win_fragment_index(address)
			int query = end
			for i in range(end):
				if (address[i] == '?' && query == end): query = i
			string_builder* target = string_new()
			string_append_bytes(target, address, query)
			string_append_char(target, '?')
			string_append(target, data)
			string_append(target, address + end)
			win_navigate(b, target.data, c"", -1)
			string_free(target)
	else: win_status(b, c"Unsupported form method")
	free(address)
	free(data)

void win_browser_form_events(win_browser* b):
	if (b.forms == 0): return
	if (b.isolated):
		if (b.forms.changed != 0): win_browser_interactive_event(b, b.forms.changed, 3, win_attr(b.forms.changed, c"value"))
		else if (b.forms.clicked != 0): win_browser_interactive_event(b, b.forms.clicked, 2, c"")
		else if (b.forms.submitter != 0): win_browser_interactive_event(b, b.forms.submitter, 4, c"")
		return
	if (b.forms.changed != 0):
		win_script_dispatch(b.script, b.forms.changed, c"input")
		win_script_dispatch(b.script, b.forms.changed, c"change")
	html_node* clicked = b.forms.clicked
	if (clicked != 0 && win_script_dispatch(b.script, clicked, c"click")):
		char* type = win_form_type(clicked)
		int change = 0
		if (strcmp(type, c"checkbox") == 0 || strcmp(type, c"radio") == 0):
			win_forms_toggle(b.forms, clicked)
			change = 1
		else if (win_tag(clicked, c"select")):
			win_forms_select_next(clicked)
			change = 1
		else if (strcmp(type, c"reset") == 0):
			html_node* form = win_form_owner(b.forms, clicked)
			if (form != 0 && win_script_dispatch(b.script, form, c"reset")): win_forms_reset(b.forms, form)
		else if (strcmp(type, c"submit") == 0): win_browser_submit(b, clicked)
		if (change):
			win_script_dispatch(b.script, clicked, c"input")
			win_script_dispatch(b.script, clicked, c"change")
	if (b.forms.submitter != 0):
		html_node* submitter = b.forms.submitter
		html_node* form = win_form_owner(b.forms, submitter)
		for i in range(b.forms.controls.length):
			html_node* candidate = b.forms.controls[i].node
			if (win_form_owner(b.forms, candidate) == form && strcmp(win_form_type(candidate), c"submit") == 0 && win_form_disabled(candidate) == 0):
				submitter = candidate
				break
		if (submitter == b.forms.submitter || win_script_dispatch(b.script, submitter, c"click")): win_browser_submit(b, submitter)

html_node* win_browser_node_hit(win_page* page, float32 x, float32 y):
	int i = page.runs.length - 1
	while (i >= 0):
		win_run* run = page.runs[i]
		if (run.hidden == 0 && x >= run.x && x < run.x + run.width && y >= run.y && y < run.y + run.height): return run.node
		i = i - 1
	i = page.boxes.length - 1
	while (i >= 0):
		win_box* box = page.boxes[i]
		if (box.hidden == 0 && x >= box.x && x < box.x + box.width && y >= box.y && y < box.y + box.height): return box.node
		i = i - 1
	return 0

int win_address_editor(win_browser* b, ui_context* ctx, ui_rect area):
	int submitted = 0
	int id = ctx.next_id
	# W's dynamic text editor supplies caret, selection, and clipboard. Enter
	# submits this single-line use instead of entering a newline.
	int kept = 0
	for i in range(ctx.char_count):
		int ch = ctx.chars[i]
		if ((ctx.char_mods[i] & GFX_MOD_CTRL) && (ch == 12 || ch == 'l' || ch == 'L')):
			ctx.focus = id
			b.input.sel_anchor = 0
			ui_textarea_set_caret(&b.input, b.input.buf.length)
		else if (ctx.focus == id && (ch == 13 || ch == 10)): submitted = 1
		else:
			ctx.chars[kept] = ch
			ctx.char_mods[kept] = ctx.char_mods[i]
			kept = kept + 1
	ctx.char_count = kept
	ui_textarea(ctx, area, &b.input)
	return submitted

# The native canvas has 8-bit RGB channels. Round solid paint colors here,
# preserving float computed values and alpha until paint. Sending half-byte
# RGB values directly through interpolated GL varyings can round differently
# across triangles/drivers (for example 50% green versus #008000).
float32 win_paint_channel(float32 value):
	value = win_css_color_clamp(value)
	return cast(float32, cast(int, value * 255.0 + 0.5)) / 255.0

ui_color win_paint_color(ui_color color):
	return ui_color_new(win_paint_channel(color.r), win_paint_channel(color.g), win_paint_channel(color.b), color.a)

# Shared page painting for the interactive viewport and native reftests.
void win_browser_paint(win_browser* b, ui_context* ctx, ui_rect viewport, float32 y_offset):
	for i in range(b.page.boxes.length):
		win_box* box = b.page.boxes[i]
		if (box.hidden): continue
		ui_rect rect = ui_rect_new(viewport.x + box.x, y_offset + box.y, box.width, box.height)
		ui_render_rect(ctx.rndr, rect, win_paint_color(box.color))
		if (box.border > 0.0):
			float32 edge = box.border
			ui_render_rect(ctx.rndr, ui_rect_new(rect.x, rect.y, rect.w, edge), win_paint_color(box.border_color))
			ui_render_rect(ctx.rndr, ui_rect_new(rect.x, rect.y + rect.h - edge, rect.w, edge), win_paint_color(box.border_color))
			ui_render_rect(ctx.rndr, ui_rect_new(rect.x, rect.y, edge, rect.h), win_paint_color(box.border_color))
			ui_render_rect(ctx.rndr, ui_rect_new(rect.x + rect.w - edge, rect.y, edge, rect.h), win_paint_color(box.border_color))
	for i in range(b.page.runs.length):
		win_run* run = b.page.runs[i]
		if (run.hidden): continue
		float32 y = y_offset + run.y
		if (y + run.height < viewport.y || y > viewport.y + viewport.h): continue
		if (win_tag(run.node, c"canvas") && b.script != 0):
			for j in range(b.script.bindings.length):
				win_dom_binding* binding = b.script.bindings[j]
				if (binding.node == run.node && binding.canvas != 0): win_canvas_draw(ctx.rndr, binding.canvas, ui_rect_new(viewport.x + run.x, y, run.width, run.height))
		else if (run.image != 0): win_image_draw(ctx.rndr, run.image, ui_rect_new(viewport.x + run.x, y, run.width, run.height))
		else: ui_draw_text_strike(ctx.rndr, viewport.x + run.x, y, run.text, run.strike, run.flags, win_paint_color(run.color))

void win_browser_frame(win_browser* b, ui_context* ctx, int width, int height):
	if (width < 360 || height < 240):
		ui_draw_text(ctx.rndr, 12.0, 12.0, c"Enlarge the window to browse", 2, ctx.theme.text)
		return
	float32 w = cast(float32, width)
	float32 h = cast(float32, height)
	ui_region_push(ctx, ui_rect_new(12.0, 48.0, w - 24.0, 32.0))
	ui_disable(ctx, b.current <= 0)
	if (ui_button(ctx, c"Back")): win_history_go(b, -1)
	ui_disable(ctx, 0)
	ui_same_line(ctx)
	ui_disable(ctx, b.current + 1 >= b.history.length)
	if (ui_button(ctx, c"Forward")): win_history_go(b, 1)
	ui_disable(ctx, 0)
	ui_same_line(ctx)
	if (ui_button(ctx, c"Home")): win_navigate(b, b.home, c"", -1)
	ui_same_line(ctx)
	char* action = c"Reload"
	if (win_browser_loading(b)): action = c"Stop"
	if (ui_button(ctx, action)):
		if (win_browser_loading(b)): win_stop(b)
		else if (b.address[0] != 0): win_navigate(b, b.address, c"", -2)
	ui_region_pop(ctx)
	# A separate row keeps the address useful even in a narrow window.
	if (win_address_editor(b, ctx, ui_rect_new(12.0, 88.0, w - 92.0, 38.0))):
		win_navigate(b, b.input.buf.data, c"", -1)
	ui_region_push(ctx, ui_rect_new(w - 70.0, 91.0, 60.0, 32.0))
	if (ui_button(ctx, c"Go")): win_navigate(b, b.input.buf.data, c"", -1)
	ui_region_pop(ctx)
	ui_rect viewport = ui_rect_new(12.0, 138.0, w - 24.0, h - 182.0)
	if (viewport.w < 160.0): viewport.w = 160.0
	if (viewport.h < 40.0): viewport.h = 40.0
	ui_render_rect(ctx.rndr, viewport, ui_gray(1.0))
	win_browser_set_viewport(b, cast(int, viewport.w), cast(int, viewport.h))
	char* activate = 0
	html_node* click_target = 0
	if (b.page != 0):
		win_script_frame_at(b.script, time_monotonic_ms())
		if (b.script != 0 && b.script.dirty):
			win_page_layout(b.page, b.width)
			b.script.dirty = 0
		if (b.page.width != b.width): win_page_layout(b.page, b.width)
		if ((ctx.input.scroll_y != 0 || ctx.input.scroll_pixels_y != 0) && ui_rect_contains(viewport, cast(float32, ctx.input.scroll_at_x), cast(float32, ctx.input.scroll_at_y))): b.restore_pending = 0
		if (ctx.input.mouse_pressed && cast(float32, ctx.input.press_x) >= viewport.x + viewport.w - 16.0 && ui_rect_contains(viewport, cast(float32, ctx.input.press_x), cast(float32, ctx.input.press_y))): b.restore_pending = 0
		ui_scroll_begin(ctx, viewport, &b.scroll)
		float32 y_offset = viewport.y - b.scroll.offset_y
		win_browser_paint(b, ctx, viewport, y_offset)
		ui_region_claim(ctx, ui_rect_new(viewport.x, y_offset, cast(float32, b.width), b.page.height))
		float32 mx = cast(float32, ctx.input.mouse_x)
		float32 my = cast(float32, ctx.input.mouse_y)
		if (ui_rect_contains(viewport, mx, my)):
			char* link = win_page_hit(b.page, mx - viewport.x, my - y_offset)
			if (link[0] != 0): ctx.pointer_mode = 1
			if (ctx.input.mouse_released && ui_rect_contains(viewport, cast(float32, ctx.input.press_x), cast(float32, ctx.input.press_y))):
				html_node* target = win_browser_node_hit(b.page, mx - viewport.x, my - y_offset)
				html_node* pressed = win_browser_node_hit(b.page, cast(float32, ctx.input.press_x) - viewport.x, cast(float32, ctx.input.press_y) - y_offset)
				if (target != 0 && target == pressed && win_form_control(target) == 0):
					click_target = target
					if (link[0] != 0): activate = strclone(link)
		win_forms_draw(b.forms, ctx, viewport.x, y_offset)
		ui_scroll_end(ctx, &b.scroll)
		win_browser_sync_viewport(b)
	else:
		ui_draw_text(ctx.rndr, 40.0, 174.0, c"Open a document to begin", 3, ctx.theme.text)
		ui_draw_text(ctx.rndr, 40.0, 212.0, c"Enter a local HTML path or an HTTP/HTTPS address above.", 2, ctx.theme.text_muted)
	ui_clip_push(ctx.rndr, ui_rect_new(12.0, h - 34.0, w - 24.0, 28.0))
	ui_draw_text(ctx.rndr, 18.0, h - 29.0, b.status, 2, ctx.theme.text_muted)
	ui_clip_pop(ctx.rndr)
	win_browser_form_events(b)
	if (b.isolated):
		if (click_target != 0): win_browser_interactive_event(b, click_target, 2, c"")
		free(activate)
		return
	if (click_target != 0 && win_script_dispatch(b.script, click_target, c"click") == 0):
		free(activate)
		activate = 0
	int new_tab = (ctx.input.mods & GFX_MOD_CTRL) != 0
	html_node* ancestor = click_target
	while (ancestor != 0):
		if (win_tag(ancestor, c"a") && strcmp(win_attr(ancestor, c"target"), c"_blank") == 0): new_tab = 1
		ancestor = ancestor.parent
	if (activate != 0):
		if (new_tab):
			free(b.new_tab)
			b.new_tab = strclone(activate)
		else: win_navigate(b, activate, win_browser_base(b), -1)
		free(activate)
	if (b.script != 0 && b.script.dirty):
		win_page_layout(b.page, b.width)
		b.script.dirty = 0
