# Parent presentation never edits the worker's form state. Ordered native
# records wait behind the one outstanding request/frame ACK transaction.
import win.browser

void win_browser_interactive_focus(win_browser* b, ui_context* ctx):
	win_interactive_worker* worker = b.interactive
	if (worker == 0 || b.forms == 0 || (ctx.focus > 0 && ctx.focus < 1000)): return
	int focus = 0
	if (worker.focus_node): focus = 900000
	for win_control* control in b.forms.controls:
		if (atoi(win_attr(control.node, c"data-win-node")) != worker.focus_node): continue
		focus = control.id
		char* value = win_attr(control.node, c"value")
		if (strcmp(control.editor.buf.data, value)): ui_textarea_set(&control.editor, value)
		int first = win_focus_byte_offset(value, worker.selection_start)
		int last = win_focus_byte_offset(value, worker.selection_end)
		int caret = last
		int anchor = first
		if (worker.selection_direction == 2):
			caret = first
			anchor = last
		ui_textarea_set_caret(&control.editor, caret)
		control.editor.sel_anchor = anchor
	ctx.focus = focus

void win_browser_interactive_input(win_browser* b, ui_context* ctx, ui_rect viewport):
	win_interactive_worker* worker = b.interactive
	if (worker == 0 || worker.child == 0 || worker.document_generation == 0):
		win_native_clear(&b.native_input)
		return
	if (b.native_input.overflow):
		win_interactive_fail(worker, 5, c"Native input queue overflow; isolated content stopped")
		win_status(b, worker.error)
		win_native_clear(&b.native_input)
		return
	win_interactive_input* batch = new win_interactive_input()
	batch.generation = worker.generation
	batch.document = worker.document_generation
	batch.width = b.viewport_width
	batch.height = b.viewport_height
	batch.mouse_x = ctx.input.mouse_x - cast(int, viewport.x)
	batch.mouse_y = ctx.input.mouse_y - cast(int, viewport.y)
	batch.mods = ctx.input.mods
	int document_focus = ctx.focus == 0 || ctx.focus >= 1000
	for i in range(b.native_input.count):
		gfx_event event = b.native_input.events[i]
		int kind = event.kind
		if (kind == GFX_EVENT_MOUSE_DOWN || kind == GFX_EVENT_MOUSE_UP || kind == GFX_EVENT_SCROLL || kind == GFX_EVENT_SCROLL_PIXELS):
			int inside = ui_rect_contains(viewport, cast(float32, event.x), cast(float32, event.y))
			if (kind == GFX_EVENT_MOUSE_DOWN):
				if (inside):
					document_focus = 1
					ctx.focus = 900000
				else:
					document_focus = 0
					event.kind = GFX_EVENT_POINTER_CANCEL
					event.code = 0
			if ((kind == GFX_EVENT_SCROLL || kind == GFX_EVENT_SCROLL_PIXELS) && inside == 0): continue
			event.x = event.x - cast(int, viewport.x)
			event.y = event.y - cast(int, viewport.y)
		else if (kind != GFX_EVENT_POINTER_CANCEL && document_focus == 0): continue
		if (kind == GFX_EVENT_PREEDIT_BEGIN || kind == GFX_EVENT_PREEDIT_TEXT || kind == GFX_EVENT_PREEDIT_END): event.x = 0
		win_native_push(&batch.native, &event)
	win_native_clear(&b.native_input)
	int changed = batch.native.count || worker.input_present == 0 || worker.input_mouse_x != batch.mouse_x || worker.input_mouse_y != batch.mouse_y || worker.input_mods != batch.mods
	if (changed):
		int mouse_x = batch.mouse_x
		int mouse_y = batch.mouse_y
		int mods = batch.mods
		if (win_interactive_enqueue(worker, batch)):
			worker.input_present = 1
			worker.input_mouse_x = mouse_x
			worker.input_mouse_y = mouse_y
			worker.input_mods = mods
		else:
			free(batch)
			if (worker.child != 0): win_interactive_fail(worker, 5, c"Invalid native input; isolated content stopped")
			win_status(b, worker.error)
	else: free(batch)
	# Chrome has already consumed its own input. The remaining document
	# defaults belong exclusively to the worker, including scroll and caret.
	ctx.char_count = 0
	ctx.nav_count = 0
	ctx.input.mouse_pressed = 0
	ctx.input.mouse_released = 0
	ctx.input.mouse_down = 0
	ctx.input.mouse_right_pressed = 0
	ctx.input.scroll_y = 0
	ctx.input.scroll_pixels_y = 0
	ctx.active = 0
	win_browser_interactive_focus(b, ctx)

void win_browser_interactive_cancel(win_browser* b):
	win_interactive_worker* worker = b.interactive
	if (worker == 0 || worker.child == 0 || worker.document_generation == 0): return
	if (worker.input_present == 0 && worker.input_queue.length == 0): return
	# Discard unsent input when the tab loses ownership, then reliably send a
	# terminal cancellation after any already-in-flight request is acknowledged.
	int retained = 0
	for win_interactive_input* queued in worker.input_queue:
		if (queued.history_delta):
			worker.input_queue[retained] = queued
			retained = retained + 1
		else: free(queued)
	while (worker.input_queue.length > retained): worker.input_queue.pop()
	win_interactive_input* batch = new win_interactive_input()
	batch.generation = worker.generation
	batch.document = worker.document_generation
	batch.width = worker.viewport_width
	batch.height = worker.viewport_height
	batch.native.count = 1
	batch.native.events[0].kind = GFX_EVENT_POINTER_CANCEL
	if (win_interactive_enqueue(worker, batch) == 0): free(batch)
	worker.input_present = 0
