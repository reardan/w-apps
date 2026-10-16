# Bounded text-control selection state, in UTF-16 code units. The browser owns
# native editing/focus and select/selectionchange task delivery separately.
# https://html.spec.whatwg.org/multipage/form-control-infrastructure.html#textFieldSelection
import win.web_host

struct win_text_selection:
	int start
	int end
	int direction

int win_text_selection_control(html_node* node):
	return win_tag(node, c"input") || win_tag(node, c"textarea")

int win_text_selection_applies(html_node* node):
	if (win_tag(node, c"textarea")): return 1
	if (win_tag(node, c"input") == 0): return 0
	char* type = win_attr(node, c"type")
	# Missing/invalid input types use the Text state.
	int denied = css_ascii_equal(type, c"hidden") || css_ascii_equal(type, c"email") || css_ascii_equal(type, c"number") || css_ascii_equal(type, c"date") || css_ascii_equal(type, c"month") || css_ascii_equal(type, c"week") || css_ascii_equal(type, c"time") || css_ascii_equal(type, c"datetime-local") || css_ascii_equal(type, c"range") || css_ascii_equal(type, c"color") || css_ascii_equal(type, c"checkbox") || css_ascii_equal(type, c"radio") || css_ascii_equal(type, c"file") || css_ascii_equal(type, c"submit") || css_ascii_equal(type, c"image") || css_ascii_equal(type, c"reset") || css_ascii_equal(type, c"button")
	return denied == 0

void win_text_selection_invalid(js_runtime* rt):
	js_value* error = js_runtime_alloc(rt, 5)
	js_runtime_set(rt, error, c"name", win_web_string(rt, c"InvalidStateError"))
	js_runtime_set(rt, error, c"message", win_web_string(rt, c"Input type does not support text selection"))
	js_runtime_throw(rt, error)

int win_text_selection_length(js_runtime* rt, char* value):
	int bytes = strlen(value)
	if (bytes > 65536 || bytes > rt.remaining):
		js_runtime_fail(rt, 5, c"Text selection value traversal budget")
		return -1
	rt.remaining = rt.remaining - bytes
	js_text* text = js_text_from_utf8(value, bytes)
	if (text == 0): return 0
	int length = text.units.length
	js_text_free(text)
	return length

# Web IDL unsigned long conversion (not clamping before modulo). Like the
# existing binary APIs, object and string numeric coercions are unsupported.
int win_text_selection_index(js_runtime* rt, js_value* value):
	return js_binary_uint(js_binary_number(rt, value), 32)

int win_text_selection_direction(js_value* value):
	if (value.kind == 4):
		if (js_runtime_key_is(value.text, c"forward")): return 1
		if (js_runtime_key_is(value.text, c"backward")): return 2
	return 0

char* win_text_selection_direction_name(int direction):
	if (direction == 1): return c"forward"
	if (direction == 2): return c"backward"
	return c"none"

void win_text_selection_range(win_text_selection* selection, int length, int start, int end, int direction):
	selection.end = min(length, end)
	selection.start = min(start, selection.end)
	selection.direction = direction

void win_text_selection_clamp(win_text_selection* selection, int length):
	win_text_selection_range(selection, length, selection.start, selection.end, selection.direction)
