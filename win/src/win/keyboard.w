# Ordered native key/default-edit tasks share the DOM dispatcher and editor.
import win.input

int win_keyboard_dispatch(win_script* script, html_node* node, win_keyboard_packet* packet):
	if (node == 0): return 1
	js_runtime* rt = script.runtime
	int nested = rt.running
	if (nested && rt.completion.status != 0): return 0
	win_script* previous = win_active_script
	win_active_script = script
	if (nested == 0):
		js_runtime_collect(rt)
		if (js_runtime_begin(rt, script.execution_budget) == 0):
			win_active_script = previous
			return 0
	rt.running = 1
	js_value* event = win_keyboard_event(rt, packet, cast(float64, time_monotonic_ms() - script.time_origin))
	js_runtime_root(rt, event)
	int allowed = 0
	if (rt.completion.status == 0): allowed = win_script_dispatch_event(script, node, event)
	js_runtime_unroot(rt, event)
	rt.running = nested
	if (nested == 0):
		win_script_result(script, rt.completion)
		if (rt.completion.status != 5): win_script_checkpoint(script)
	win_active_script = previous
	return allowed

# Remove only this record's native default; address/menu input already consumed
# by the shared UI pass is never re-injected into the document.
void win_keyboard_remove_default(ui_context* ctx, gfx_event* event):
	if (event.kind == GFX_EVENT_CHAR):
		for i in range(ctx.char_count):
			if (ctx.chars[i] == event.code && ctx.char_mods[i] == event.mods):
				for j in range(i + 1, ctx.char_count):
					ctx.chars[j - 1] = ctx.chars[j]
					ctx.char_mods[j - 1] = ctx.char_mods[j]
				ctx.char_count = ctx.char_count - 1
				return
	if (event.kind == GFX_EVENT_NAV):
		for i in range(ctx.nav_count):
			if (ctx.navs[i] == event.code && ctx.nav_mods[i] == event.mods):
				for j in range(i + 1, ctx.nav_count):
					ctx.navs[j - 1] = ctx.navs[j]
					ctx.nav_mods[j - 1] = ctx.nav_mods[j]
				ctx.nav_count = ctx.nav_count - 1
				return

# Backend END carries no commit text. Emit empty end data; separate CHAR
# records perform committed edits. Never infer a commit from old preedit.
void win_keyboard_composition_event(win_script* script, html_node* target, char* type, char* data, int length):
	if (target == 0 || win_pointer_connected(script.page, target) == 0): return
	win_keyboard_packet packet
	packet.type = type
	packet.data = data
	packet.data_length = length
	win_keyboard_dispatch(script, target, &packet)

void win_keyboard_composition_end(win_script* script):
	win_keyboard_state* state = &script.keyboard
	html_node* target = state.composition_target
	int active = state.composing
	state.composing = 0
	state.composition_target = 0
	state.preedit_length = 0
	if (active): win_keyboard_composition_event(script, target, c"compositionend", c"", 0)

void win_keyboard_preedit(win_script* script, ui_context* ctx, win_native_input* input, int index):
	gfx_event* event = &input.events[index]
	win_keyboard_state* state = &script.keyboard
	if (event.x != 0 && event.x != ctx.focus): return
	if (event.kind == GFX_EVENT_PREEDIT_END):
		win_keyboard_composition_end(script)
		return
	html_node* target = script.active_focus
	if (target == 0 || win_text_selection_applies(target) == 0 || win_form_disabled(target) || win_form_has(target, c"readonly")): return
	if (state.composing && state.composition_target != target): win_keyboard_composition_end(script)
	if (event.kind == GFX_EVENT_PREEDIT_BEGIN):
		state.preedit_length = 0
		state.preedit[0] = 0
		if (state.composing == 0):
			state.composing = 1
			state.composition_target = target
			win_keyboard_composition_event(script, target, c"compositionstart", c"", 0)
	else if (event.kind == GFX_EVENT_PREEDIT_TEXT && state.composing):
		int cp = event.code
		if (cp >= 32 && cp <= 1114111 && (cp < 55296 || cp > 57343)):
			char[4] bytes
			int length = utf8_encode(&bytes[0], cp)
			if (length >= 1024 - state.preedit_length):
				win_keyboard_composition_end(script)
				return
			for i in range(length): state.preedit[state.preedit_length + i] = bytes[i]
			state.preedit_length = state.preedit_length + length
			state.preedit[state.preedit_length] = 0
	if (state.composing && (index + 1 == input.count || input.events[index + 1].kind != GFX_EVENT_PREEDIT_TEXT)):
		win_keyboard_composition_event(script, target, c"compositionupdate", &state.preedit[0], state.preedit_length)

void win_keyboard_cancel(win_script* script):
	if (script == 0): return
	win_keyboard_composition_end(script)
	for i in range(256): script.keyboard.down[i] = 0
	script.keyboard.suppress_default = 0
	script.keyboard.composing = 0

void win_keyboard_key(win_script* script, win_native_input* input, int index, html_node* target):
	gfx_event* event = &input.events[index]
	win_keyboard_state* state = &script.keyboard
	int raw = event.code
	int tracked = raw >= 0 && raw < 256
	win_keyboard_packet packet
	packet.type = c"keydown"
	packet.scalar = 0
	packet.navigation = 0
	packet.repeat = 0
	packet.mods = event.mods
	packet.composing = state.composing
	if (event.kind == GFX_EVENT_KEY_UP):
		packet.type = c"keyup"
		if (tracked && state.down[raw]):
			packet.scalar = state.scalar[raw]
			packet.navigation = state.navigation[raw]
			state.down[raw] = 0
	else:
		# The next text/navigation record describes this hardware press. Never
		# guess a keyboard layout from raw X11/Cocoa/Win32 physical codes.
		for i in range(index + 1, input.count):
			gfx_event* next = &input.events[i]
			if (next.kind == GFX_EVENT_CHAR):
				packet.scalar = next.code
				break
			if (next.kind == GFX_EVENT_NAV):
				packet.navigation = next.code
				break
			if (next.kind != GFX_EVENT_PREEDIT_BEGIN && next.kind != GFX_EVENT_PREEDIT_TEXT && next.kind != GFX_EVENT_PREEDIT_END): break
		if ((event.mods & GFX_MOD_CTRL) && packet.scalar >= 1 && packet.scalar <= 26 && packet.scalar != 8 && packet.scalar != 9 && packet.scalar != 13):
			packet.scalar = packet.scalar - 1 + 'a'
			if (event.mods & GFX_MOD_SHIFT): packet.scalar = packet.scalar - 'a' + 'A'
		if (tracked):
			packet.repeat = state.down[raw]
			state.down[raw] = 1
			state.scalar[raw] = packet.scalar
			state.navigation[raw] = packet.navigation
	packet.key_code = win_keyboard_code(packet.scalar, packet.navigation)
	int allowed = win_keyboard_dispatch(script, target, &packet)
	if (event.kind == GFX_EVENT_KEY_DOWN): state.suppress_default = allowed == 0
	else: state.suppress_default = 0

void win_keyboard_edit_inner(win_script* script, win_forms* forms, ui_context* ctx, gfx_event* event, html_node* target):
	win_control* control = win_forms_find(forms, target)
	if (control == 0 || win_text_selection_applies(target) == 0): return
	if (win_form_disabled(target)): return
	if (event.kind == GFX_EVENT_CHAR && (event.mods & (GFX_MOD_CTRL | GFX_MOD_SUPER)) && (event.mods & GFX_MOD_ALT) == 0 && (event.code == 1 || event.code == 'a' || event.code == 'A')):
		win_keyboard_remove_default(ctx, event)
		win_input_before(script, forms, ctx)
		ui_textarea_set_caret(&control.editor, control.editor.buf.length)
		control.editor.sel_anchor = 0
		win_input_after(script, forms, ctx)
		return
	if (event.kind == GFX_EVENT_NAV && event.code != GFX_NAV_DELETE):
		win_keyboard_remove_default(ctx, event)
		win_input_before(script, forms, ctx)
		ui_textarea_nav(&control.editor, event.code, event.mods, win_tag(target, c"textarea"))
		win_input_after(script, forms, ctx)
		return
	if (win_form_has(target, c"readonly")): return
	char* input_type = c"insertText"
	char[5] text
	int length = 0
	int text_data = 0
	if (event.kind == GFX_EVENT_NAV):
		if (event.code != GFX_NAV_DELETE): return
		input_type = c"deleteContentForward"
	else if (event.code == 8): input_type = c"deleteContentBackward"
	else if (event.code == 10 || event.code == 13):
		if (win_tag(target, c"textarea") == 0): return
		input_type = c"insertLineBreak"
	else if (event.code >= 32 && event.code <= 1114111 && (event.code < 55296 || event.code > 57343) && ui_char_is_typing(event.mods)):
		length = utf8_encode(&text[0], event.code)
		text_data = 1
	else: return
	win_keyboard_remove_default(ctx, event)
	win_keyboard_packet packet
	packet.type = c"beforeinput"
	packet.input_type = input_type
	packet.data = 0
	packet.data_length = length
	packet.composing = script.keyboard.composing
	if (text_data): packet.data = &text[0]
	if (win_keyboard_dispatch(script, target, &packet) == 0): return
	if (script.active_focus != target || win_pointer_connected(script.page, target) == 0): return
	if (win_form_disabled(target) || win_form_has(target, c"readonly")): return
	win_input_before(script, forms, ctx)
	char* old_value = win_attr(target, c"value")
	int old_caret = ui_textarea_caret_offset(&control.editor)
	int old_anchor = control.editor.sel_anchor
	if (event.kind == GFX_EVENT_NAV): ui_textarea_nav(&control.editor, GFX_NAV_DELETE, event.mods, 1)
	else if (event.code == 8): ui_textarea_backspace(&control.editor)
	else if (event.code == 10 || event.code == 13): ui_textarea_type(&control.editor, 10)
	else: ui_textarea_type(&control.editor, event.code)
	int limit = WIN_FORM_LIMIT
	if (win_form_has(target, c"maxlength")):
		int declared = atoi(win_attr(target, c"maxlength"))
		if (declared >= 0 && declared < limit): limit = declared
	int units = win_focus_unit_offset(control.editor.buf.data, control.editor.buf.length)
	if (control.editor.buf.length > WIN_FORM_LIMIT || units > limit):
		ui_textarea_set(&control.editor, old_value)
		ui_textarea_set_caret(&control.editor, old_caret)
		control.editor.sel_anchor = old_anchor
		return
	if (strcmp(old_value, control.editor.buf.data) == 0): return
	win_form_set(target, c"value", control.editor.buf.data)
	win_input_after(script, forms, ctx)
	packet.type = c"input"
	win_keyboard_dispatch(script, target, &packet)

void win_keyboard_edit(win_script* script, win_forms* forms, ui_context* ctx, gfx_event* event, html_node* target):
	js_runtime* rt = script.runtime
	int nested = rt.running
	if (nested && rt.completion.status != 0): return
	win_script* previous = win_active_script
	win_active_script = script
	if (nested == 0):
		js_runtime_collect(rt)
		if (js_runtime_begin(rt, script.execution_budget) == 0):
			win_active_script = previous
			return
	rt.running = 1
	win_keyboard_edit_inner(script, forms, ctx, event, target)
	rt.running = nested
	if (nested == 0):
		win_script_result(script, rt.completion)
		if (rt.completion.status != 5): win_script_checkpoint(script)
	win_active_script = previous

void win_keyboard_record(win_script* script, win_forms* forms, ui_context* ctx, win_native_input* input, int index):
	gfx_event* event = &input.events[index]
	html_node* target = script.active_focus
	if (target == 0 || (ctx.focus > 0 && ctx.focus < 1000)): return
	if (win_pointer_connected(script.page, target) == 0): return
	if (event.kind == GFX_EVENT_KEY_DOWN || event.kind == GFX_EVENT_KEY_UP):
		win_keyboard_key(script, input, index, target)
	else if (event.kind == GFX_EVENT_PREEDIT_BEGIN || event.kind == GFX_EVENT_PREEDIT_TEXT || event.kind == GFX_EVENT_PREEDIT_END):
		win_keyboard_preedit(script, ctx, input, index)
	else if (event.kind == GFX_EVENT_CHAR || event.kind == GFX_EVENT_NAV):
		if (script.keyboard.suppress_default): win_keyboard_remove_default(ctx, event)
		else if (forms != 0): win_keyboard_edit(script, forms, ctx, event, target)
