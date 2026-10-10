import win.document
import win.loader
import graphics.ui.widgets

struct win_history_entry:
	char* address
	float32 scroll

struct win_browser:
	win_page* page
	win_load* load
	char* executable
	char* home
	char* address
	char* status
	list[win_history_entry*] history
	int current
	int pending_history
	int width
	ui_textarea_state input
	ui_scroll_state scroll

void win_status(win_browser* browser, char* text):
	free(browser.status)
	browser.status = strclone(text)

void win_browser_init(win_browser* b, char* executable, char* home):
	b.page = 0
	b.load = 0
	b.executable = strclone(executable)
	b.home = strclone(home)
	b.address = strclone(c"")
	b.status = strclone(c"Open an HTML file or an http:// or https:// address")
	b.history = new list[win_history_entry*]
	b.current = -1
	b.pending_history = -1
	b.width = 920
	ui_textarea_init(&b.input)
	ui_scroll_init(&b.scroll)

void win_browser_free(win_browser* b):
	win_load_free(b.load)
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
	if (b.load == 0): return
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
void win_navigate(win_browser* b, char* reference, char* base, int target):
	char* address = win_resolve(base, reference)
	if (address == 0):
		win_status(b, c"Use an HTML file path or a valid http:// or https:// URL")
		return
	if (b.current >= 0): b.history[b.current].scroll = b.scroll.offset_y
	win_stop(b)
	char* old_path = win_without_fragment(b.address)
	char* new_path = win_without_fragment(address)
	int same = b.page != 0 && strcmp(old_path, new_path) == 0 && target != -2
	free(old_path)
	free(new_path)
	if (same):
		win_commit_address(b, address, target)
		win_scroll_fragment(b)
		if (target >= 0): b.scroll.offset_y = b.history[target].scroll
		win_status(b, c"Ready · static HTML")
	else:
		b.pending_history = target
		b.load = win_load_start(b.executable, address)
		ui_textarea_set(&b.input, address)
		win_status(b, c"Loading…")
	free(address)

void win_history_go(win_browser* b, int delta):
	int index = b.current + delta
	if (index < 0 || index >= b.history.length): return
	win_navigate(b, b.history[index].address, c"", index)

void win_browser_poll(win_browser* b):
	if (b.load == 0 || win_load_poll(b.load) == 0): return
	if (b.load.error != 0): win_status(b, b.load.error)
	else:
		win_page* page = win_page_parse(b.load.source, b.load.length)
		if (page == 0): win_status(b, c"Invalid UTF-8 or HTML document exceeds parser limits")
		else:
			win_page_free(b.page)
			b.page = page
			win_page_layout(page, b.width)
			win_commit_address(b, b.load.address, b.pending_history)
			win_scroll_fragment(b)
			if (b.pending_history >= 0): b.scroll.offset_y = b.history[b.current].scroll
			if (page.truncated): win_status(b, c"Display limit reached · showing the first 20,000 text runs")
			else: win_status(b, c"Ready · static HTML · scripts are not executed")
	win_load_free(b.load)
	b.load = 0

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

void win_browser_frame(win_browser* b, ui_context* ctx, int width, int height):
	if (width < 360 || height < 240):
		ui_draw_text(ctx.rndr, 12.0, 12.0, c"Enlarge the window to browse", 2, ctx.theme.text)
		return
	float32 w = cast(float32, width)
	float32 h = cast(float32, height)
	ui_draw_text(ctx.rndr, 18.0, 15.0, c"win", 3, ctx.theme.text)
	ui_draw_text(ctx.rndr, 74.0, 18.0, c"A browser written in W", 2, ctx.theme.text_muted)
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
	if (b.load != 0): action = c"Stop"
	if (ui_button(ctx, action)):
		if (b.load != 0): win_stop(b)
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
	b.width = cast(int, viewport.w) - 12
	char* activate = 0
	if (b.page != 0):
		if (b.page.width != b.width): win_page_layout(b.page, b.width)
		ui_scroll_begin(ctx, viewport, &b.scroll)
		float32 y_offset = viewport.y - b.scroll.offset_y
		for i in range(b.page.runs.length):
			win_run* run = b.page.runs[i]
			float32 y = y_offset + run.y
			if (y + run.height < viewport.y || y > viewport.y + viewport.h): continue
			ui_draw_text_strike(ctx.rndr, viewport.x + run.x, y, run.text, run.strike, run.flags, run.color)
		ui_region_claim(ctx, ui_rect_new(viewport.x, y_offset, cast(float32, b.width), b.page.height))
		float32 mx = cast(float32, ctx.input.mouse_x)
		float32 my = cast(float32, ctx.input.mouse_y)
		if (ui_rect_contains(viewport, mx, my)):
			char* link = win_page_hit(b.page, mx - viewport.x, my - y_offset)
			if (link[0] != 0):
				ctx.pointer_mode = 1
				if (ctx.input.mouse_released && ui_rect_contains(viewport, cast(float32, ctx.input.press_x), cast(float32, ctx.input.press_y))):
					char* pressed = win_page_hit(b.page, cast(float32, ctx.input.press_x) - viewport.x, cast(float32, ctx.input.press_y) - y_offset)
					if (strcmp(pressed, link) == 0): activate = strclone(link)
		ui_scroll_end(ctx, &b.scroll)
	else:
		ui_draw_text(ctx.rndr, 40.0, 174.0, c"Open a document to begin", 3, ctx.theme.text)
		ui_draw_text(ctx.rndr, 40.0, 212.0, c"Enter a local HTML path or an HTTP/HTTPS address above.", 2, ctx.theme.text_muted)
	ui_clip_push(ctx.rndr, ui_rect_new(12.0, h - 34.0, w - 24.0, 28.0))
	ui_draw_text(ctx.rndr, 18.0, h - 29.0, b.status, 2, ctx.theme.text_muted)
	ui_clip_pop(ctx.rndr)
	if (activate != 0):
		win_navigate(b, activate, b.address, -1)
		free(activate)
