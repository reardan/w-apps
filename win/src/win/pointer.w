# Mouse Pointer Events from the native event queue. No touch/pen capabilities
# are inferred from mouse-compatible backend events.
import win.events
import graphics.event

struct win_pointer_state:
	html_node* capture
	html_node* pending
	html_node* pressed
	int buttons
	int cancelled
	int present
	int x
	int y
	int mods

struct win_native_input:
	gfx_event[64] events
	int count
	int overflow

void win_native_push(win_native_input* input, gfx_event* event):
	if (input.overflow): return
	if (input.count >= 64):
		input.count = 0
		input.overflow = 1
		return
	input.events[input.count] = event[0]
	input.count = input.count + 1

void win_native_clear(win_native_input* input):
	input.count = 0
	input.overflow = 0

int win_pointer_connected(win_page* page, html_node* node):
	for i in range(2048):
		if (node == page.html.root): return 1
		if (node == 0): return 0
		node = node.parent
	return 0

int win_pointer_button_mask(int button):
	if (button == 0): return 1
	if (button == 1): return 4
	if (button == 2): return 2
	return 0

void win_pointer_error(js_runtime* rt, char* name, char* message):
	js_value* error = js_runtime_error_value(rt, message)
	js_runtime_set(rt, error, c"name", win_web_string(rt, name))
	js_runtime_throw(rt, error)

js_value* win_pointer_event(js_runtime* rt, win_pointer_state* state, char* type, int button, win_web_viewport* viewport, float64 timestamp, int delta, int delta_mode):
	int wheel = strcmp(type, c"wheel") == 0
	int cancelable = wheel || strcmp(type, c"pointerdown") == 0 || strcmp(type, c"pointermove") == 0 || strcmp(type, c"pointerup") == 0
	js_value* event = win_event_new(rt, win_web_string(rt, type), 1, cancelable, 1, timestamp)
	if (rt.completion.status != 0): return event
	win_event_write(rt, event, c"isTrusted", js_runtime_boolean(rt, 1))
	win_event_write(rt, event, c"clientX", js_runtime_number(rt, cast(float64, state.x)))
	win_event_write(rt, event, c"clientY", js_runtime_number(rt, cast(float64, state.y)))
	win_event_write(rt, event, c"pageX", js_runtime_number(rt, cast(float64, state.x) + viewport.scroll_x))
	win_event_write(rt, event, c"pageY", js_runtime_number(rt, cast(float64, state.y) + viewport.scroll_y))
	win_event_write(rt, event, c"button", js_runtime_number(rt, cast(float64, button)))
	win_event_write(rt, event, c"buttons", js_runtime_number(rt, cast(float64, state.buttons)))
	win_event_write(rt, event, c"shiftKey", js_runtime_boolean(rt, state.mods & GFX_MOD_SHIFT))
	win_event_write(rt, event, c"ctrlKey", js_runtime_boolean(rt, state.mods & GFX_MOD_CTRL))
	win_event_write(rt, event, c"altKey", js_runtime_boolean(rt, state.mods & GFX_MOD_ALT))
	win_event_write(rt, event, c"metaKey", js_runtime_boolean(rt, state.mods & GFX_MOD_SUPER))
	if (wheel):
		win_event_write(rt, event, c"deltaX", js_runtime_number(rt, 0.0))
		win_event_write(rt, event, c"deltaY", js_runtime_number(rt, cast(float64, delta)))
		win_event_write(rt, event, c"deltaZ", js_runtime_number(rt, 0.0))
		win_event_write(rt, event, c"deltaMode", js_runtime_number(rt, cast(float64, delta_mode)))
	else:
		win_event_write(rt, event, c"pointerId", js_runtime_number(rt, 1.0))
		win_event_write(rt, event, c"pointerType", win_web_string(rt, c"mouse"))
		win_event_write(rt, event, c"isPrimary", js_runtime_boolean(rt, 1))
		win_event_write(rt, event, c"width", js_runtime_number(rt, 1.0))
		win_event_write(rt, event, c"height", js_runtime_number(rt, 1.0))
		float64 pressure = 0.0
		if (state.buttons): pressure = 0.5
		win_event_write(rt, event, c"pressure", js_runtime_number(rt, pressure))
	return event
