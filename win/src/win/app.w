# Each tab owns its document, pending loads, history, form state and JS realm.
import win.browser

const int WIN_MAX_TABS = 32

struct win_app:
	int isolated
	list[win_browser*] tabs
	int32 selected
	ui_tab_state strip
	char* executable
	char* home
	win_storage_context* local_storage

void win_app_init(win_app* app, char* executable, char* home):
	app.isolated = 0
	app.tabs = new list[win_browser*]
	app.selected = 0
	ui_tab_init(&app.strip)
	app.executable = strclone(executable)
	app.home = strclone(home)
	app.local_storage = win_storage_new()

int win_app_open(win_app* app, char* address, char* base):
	if (app.tabs.length >= WIN_MAX_TABS): return 0
	win_browser* tab = new win_browser()
	win_browser_init(tab, app.executable, app.home)
	tab.isolated = app.isolated
	win_storage_free(tab.local_storage)
	tab.local_storage = app.local_storage
	tab.owns_local_storage = 0
	app.tabs.push(tab)
	app.selected = app.tabs.length - 1
	win_navigate(tab, address, base, -1)
	return 1

void win_app_close(win_app* app, int index):
	if (index < 0 || index >= app.tabs.length): return
	win_browser_free(app.tabs[index])
	free(app.tabs[index])
	for i in range(index, app.tabs.length - 1): app.tabs[i] = app.tabs[i + 1]
	app.tabs.pop()
	if (app.selected > index): app.selected = app.selected - 1
	if (app.selected >= app.tabs.length): app.selected = app.tabs.length - 1
	if (app.tabs.length == 0): win_app_open(app, app.home, c"")

void win_app_poll(win_app* app):
	for i in range(app.tabs.length): win_browser_poll(app.tabs[i])

void win_app_free(win_app* app):
	for i in range(app.tabs.length):
		win_browser_free(app.tabs[i])
		free(app.tabs[i])
	__w_list_free(cast(__w_list*, app.tabs))
	win_storage_free(app.local_storage)
	free(app.executable)
	free(app.home)

void win_app_frame(win_app* app, ui_context* ctx, int width, int height):
	int previous = app.selected
	# Reserve independent ID ranges for browser controls and the tab strip.
	# Opening/closing a tab must not move the focused address/form widget ID.
	if (ui_shortcut(ctx, GFX_MOD_CTRL, 't')):
		win_app_open(app, app.home, c"")
		ctx.focus = 0
		ctx.active = 0
		ctx.popup_depth = 0
	if (ui_shortcut(ctx, GFX_MOD_CTRL, 'w')):
		win_app_close(app, app.selected)
		ctx.focus = 0
		ctx.active = 0
		ctx.popup_depth = 0
	if (ui_shortcut(ctx, GFX_MOD_CTRL, 9)):
		app.selected = (app.selected + 1) % app.tabs.length
	if (ui_shortcut(ctx, GFX_MOD_CTRL | GFX_MOD_SHIFT, 9)):
		app.selected = (app.selected + app.tabs.length - 1) % app.tabs.length
	if (width >= 360 && height >= 240):
		ctx.next_id = 100000
		ui_tabs_begin(ctx, ui_rect_new(12.0, 6.0, cast(float32, width) - 74.0, 34.0), &app.strip, &app.selected)
		for i in range(app.tabs.length):
			char* title = c"Loading…"
			if (app.tabs[i].page != 0): title = app.tabs[i].page.title
			else if (app.tabs[i].load == 0): title = c"New tab"
			ui_tab(ctx, &app.strip, title, 1)
		int closed = ui_tabs_end(ctx, &app.strip)
		if (closed >= 0):
			win_app_close(app, closed)
			ctx.focus = 0
			ctx.active = 0
		ui_region_push(ctx, ui_rect_new(cast(float32, width) - 54.0, 6.0, 42.0, 34.0))
		ui_disable(ctx, app.tabs.length >= WIN_MAX_TABS)
		if (ui_button(ctx, c"+")): win_app_open(app, app.home, c"")
		ui_disable(ctx, 0)
		ui_region_pop(ctx)
	if (previous != app.selected):
		ctx.focus = 0
		ctx.active = 0
		ctx.popup_depth = 0
	ctx.next_id = 1
	win_browser* tab = app.tabs[app.selected]
	win_browser_frame(tab, ctx, width, height)
	if (tab.new_tab != 0):
		win_app_open(app, tab.new_tab, win_browser_base(tab))
		free(tab.new_tab)
		tab.new_tab = 0
		ctx.focus = 0
