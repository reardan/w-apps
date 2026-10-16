# Logical keys come from portable CHAR/NAV records, never raw hardware codes.
import win.events
import graphics.event

struct win_keyboard_state:
	int[256] down
	int[256] scalar
	int[256] navigation
	int suppress_default
	int composing

struct win_keyboard_packet:
	char* type
	int scalar
	int navigation
	int key_code
	int repeat
	int mods
	int composing
	char* data
	int data_length
	char* input_type

char* win_keyboard_named(int scalar, int navigation):
	if (navigation == GFX_NAV_LEFT): return c"ArrowLeft"
	if (navigation == GFX_NAV_RIGHT): return c"ArrowRight"
	if (navigation == GFX_NAV_HOME): return c"Home"
	if (navigation == GFX_NAV_END): return c"End"
	if (navigation == GFX_NAV_UP): return c"ArrowUp"
	if (navigation == GFX_NAV_DOWN): return c"ArrowDown"
	if (navigation == GFX_NAV_PAGE_UP): return c"PageUp"
	if (navigation == GFX_NAV_PAGE_DOWN): return c"PageDown"
	if (navigation == GFX_NAV_DELETE): return c"Delete"
	if (scalar == 8): return c"Backspace"
	if (scalar == 9): return c"Tab"
	if (scalar == 13 || scalar == 10): return c"Enter"
	if (scalar == 27): return c"Escape"
	return c""

int win_keyboard_code(int scalar, int navigation):
	if (navigation == GFX_NAV_LEFT): return 37
	if (navigation == GFX_NAV_RIGHT): return 39
	if (navigation == GFX_NAV_UP): return 38
	if (navigation == GFX_NAV_DOWN): return 40
	if (navigation == GFX_NAV_HOME): return 36
	if (navigation == GFX_NAV_END): return 35
	if (navigation == GFX_NAV_PAGE_UP): return 33
	if (navigation == GFX_NAV_PAGE_DOWN): return 34
	if (navigation == GFX_NAV_DELETE): return 46
	if (scalar == 10): return 13
	if (scalar >= 'a' && scalar <= 'z'): return scalar - 'a' + 'A'
	if ((scalar >= '0' && scalar <= '9') || (scalar >= 'A' && scalar <= 'Z') || scalar == 8 || scalar == 9 || scalar == 13 || scalar == 27 || scalar == 32): return scalar
	return 0

js_value* win_keyboard_modifier(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	int mods = cast(int, context)
	if (args.length == 0 || args[0].kind != 4): return js_runtime_boolean(rt, 0)
	js_text* key = args[0].text
	int active = 0
	if (js_runtime_key_is(key, c"Shift")): active = mods & GFX_MOD_SHIFT
	if (js_runtime_key_is(key, c"Control")): active = mods & GFX_MOD_CTRL
	if (js_runtime_key_is(key, c"Alt")): active = mods & GFX_MOD_ALT
	if (js_runtime_key_is(key, c"Meta")): active = mods & GFX_MOD_SUPER
	if (js_runtime_key_is(key, c"AltGraph")): active = (mods & GFX_MOD_CTRL) != 0 && (mods & GFX_MOD_ALT) != 0 && (mods & GFX_MOD_SUPER) == 0
	return js_runtime_boolean(rt, active)

js_value* win_keyboard_event(js_runtime* rt, win_keyboard_packet* packet, float64 timestamp):
	int keyboard = strcmp(packet.type, c"keydown") == 0 || strcmp(packet.type, c"keyup") == 0
	int before = strcmp(packet.type, c"beforeinput") == 0
	int composition = strcmp(packet.type, c"compositionstart") == 0 || strcmp(packet.type, c"compositionupdate") == 0 || strcmp(packet.type, c"compositionend") == 0
	js_value* event = win_event_new(rt, win_web_string(rt, packet.type), 1, keyboard || before, 1, timestamp)
	if (rt.completion.status != 0): return event
	win_event_write(rt, event, c"isTrusted", js_runtime_boolean(rt, 1))
	if (keyboard):
		char* named = win_keyboard_named(packet.scalar, packet.navigation)
		char[5] key
		key[0] = 0
		if (named[0] == 0 && packet.scalar >= 32 && packet.scalar <= 1114111 && (packet.scalar < 55296 || packet.scalar > 57343)):
			int count = utf8_encode(&key[0], packet.scalar)
			key[count] = 0
			named = &key[0]
		if (named[0] == 0): named = c"Unidentified"
		win_event_write(rt, event, c"key", win_web_string(rt, named))
		win_event_write(rt, event, c"code", win_web_string(rt, c""))
		win_event_write(rt, event, c"keyCode", js_runtime_number(rt, cast(float64, packet.key_code)))
		win_event_write(rt, event, c"which", js_runtime_number(rt, cast(float64, packet.key_code)))
		win_event_write(rt, event, c"charCode", js_runtime_number(rt, 0.0))
		win_event_write(rt, event, c"location", js_runtime_number(rt, 0.0))
		win_event_write(rt, event, c"repeat", js_runtime_boolean(rt, packet.repeat))
		win_event_write(rt, event, c"shiftKey", js_runtime_boolean(rt, packet.mods & GFX_MOD_SHIFT))
		win_event_write(rt, event, c"ctrlKey", js_runtime_boolean(rt, packet.mods & GFX_MOD_CTRL))
		win_event_write(rt, event, c"altKey", js_runtime_boolean(rt, packet.mods & GFX_MOD_ALT))
		win_event_write(rt, event, c"metaKey", js_runtime_boolean(rt, packet.mods & GFX_MOD_SUPER))
		win_event_write(rt, event, c"getModifierState", js_runtime_host_callable(rt, cast(void*, packet.mods), win_keyboard_modifier))
	else:
		js_value* data = js_runtime_alloc(rt, 1)
		if (packet.data != 0):
			js_text* text = js_text_from_utf8(packet.data, packet.data_length)
			if (text != 0):
				data = js_runtime_string(rt, text)
				js_text_free(text)
		win_event_write(rt, event, c"data", data)
		if (composition == 0): win_event_write(rt, event, c"inputType", win_web_string(rt, packet.input_type))
	if (composition == 0): win_event_write(rt, event, c"isComposing", js_runtime_boolean(rt, packet.composing))
	return event
