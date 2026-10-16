# Synthetic Event state stays on GC-owned values. host_context contains only
# flag bits, never an untraced pointer or a separately retained event allocation.
# https://dom.spec.whatwg.org/#interface-event
import win.web_host

int WIN_EVENT_DISPATCHING = 1
int WIN_EVENT_STOP = 2
int WIN_EVENT_IMMEDIATE = 4
int WIN_EVENT_PASSIVE = 8

js_value* win_event_get(void* runtime, void* context, js_value* receiver, js_text* key):
	return 0

int win_event_has(void* runtime, void* context, js_value* receiver, js_text* key):
	# Event state is entirely represented by ordinary readonly descriptors.
	return 0

int win_event_is(js_value* value):
	return value.kind == 5 && value.host_get == cast(int, win_event_get)

int win_event_flag(js_value* event, int flag):
	return (cast(int, event.host_context) & flag) != 0

void win_event_flag_set(js_value* event, int flag, int enabled):
	int flags = cast(int, event.host_context)
	if (enabled): flags = flags | flag
	else: flags = flags & ~flag
	event.host_context = cast(void*, flags)

# These descriptors are readonly to page code. Only the dispatch implementation
# updates the backing property; values remain visible to the ordinary GC tracer.
void win_event_write(js_runtime* rt, js_value* event, char* name, js_value* value):
	js_text* key = js_runtime_key(name)
	js_value* property = js_runtime_property(event, key)
	if (property != 0): property.value = value
	else: js_runtime_define_data(rt, event, key, value, 0, 1, 0)
	js_text_free(key)

int win_event_cancelled(js_value* event):
	# Dispatch cleanup must still observe cancellation after a terminal limit.
	# This native readonly data field needs no interpreter property access.
	js_text* key = js_runtime_key(c"defaultPrevented")
	js_value* property = js_runtime_property(event, key)
	js_text_free(key)
	return property != 0 && property.value != 0 && js_runtime_truth(property.value)

void win_event_prevent(js_runtime* rt, js_value* event):
	if (js_runtime_truth(js_runtime_get(rt, event, c"cancelable")) && win_event_flag(event, WIN_EVENT_PASSIVE) == 0):
		win_event_write(rt, event, c"defaultPrevented", js_runtime_boolean(rt, 1))

js_value* win_event_prevent_host(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	if (win_event_is(receiver) == 0): js_runtime_fail(rt, 2, c"Event method requires an Event receiver")
	else: win_event_prevent(rt, receiver)
	return rt.undefined_value

js_value* win_event_stop_host(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	if (win_event_is(receiver) == 0): js_runtime_fail(rt, 2, c"Event method requires an Event receiver")
	else:
		win_event_flag_set(receiver, WIN_EVENT_STOP, 1)
		if (context != 0): win_event_flag_set(receiver, WIN_EVENT_IMMEDIATE, 1)
	return rt.undefined_value

js_value* win_event_new(js_runtime* rt, js_value* type, int bubbles, int cancelable, int composed, float64 timestamp):
	js_value* event = js_runtime_alloc(rt, 5)
	win_event_write(rt, event, c"type", type)
	win_event_write(rt, event, c"bubbles", js_runtime_boolean(rt, bubbles))
	win_event_write(rt, event, c"cancelable", js_runtime_boolean(rt, cancelable))
	win_event_write(rt, event, c"composed", js_runtime_boolean(rt, composed))
	win_event_write(rt, event, c"defaultPrevented", js_runtime_boolean(rt, 0))
	win_event_write(rt, event, c"isTrusted", js_runtime_boolean(rt, 0))
	win_event_write(rt, event, c"target", js_runtime_alloc(rt, 1))
	win_event_write(rt, event, c"currentTarget", js_runtime_alloc(rt, 1))
	win_event_write(rt, event, c"eventPhase", js_runtime_number(rt, 0.0))
	win_event_write(rt, event, c"timeStamp", js_runtime_number(rt, timestamp))
	js_runtime_set(rt, event, c"preventDefault", js_runtime_host_callable(rt, 0, win_event_prevent_host))
	js_runtime_set(rt, event, c"stopPropagation", js_runtime_host_callable(rt, 0, win_event_stop_host))
	js_runtime_set(rt, event, c"stopImmediatePropagation", js_runtime_host_callable(rt, cast(void*, 1), win_event_stop_host))
	js_runtime_set_host_hooks(rt, event, 0, win_event_get, 0)
	js_runtime_set_host_has(rt, event, win_event_has)
	return event
