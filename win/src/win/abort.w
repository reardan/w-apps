# Bounded realm-owned AbortController/Signal. Native observers cancel transports
# before JavaScript listeners run; reasons and listeners remain traced by GC.
import win.events
import lib.time

type win_abort_callback = fn(void*) -> void
type win_abort_report = fn(void*, js_completion*) -> void

struct win_abort_observer:
	void* context
	win_abort_callback* callback

struct win_abort_listener:
	js_value* holder
	js_value* callback
	js_text* type
	int capture
	int once
	int passive
	int removed

struct win_abort_context:
	js_runtime* runtime
	void* owner
	win_abort_report* report
	list[void*] states

struct win_abort_state:
	win_abort_context* context
	js_value* controller
	js_value* signal
	js_value* reason
	list[win_abort_listener*] listeners
	list[win_abort_observer*] observers
	win_abort_listener* handler
	int aborted
	int dispatching

js_value* win_abort_signal_get(void* runtime, void* context, js_value* receiver, js_text* key):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_abort_state* state = cast(win_abort_state*, context)
	if (receiver != state.signal): return 0
	if (js_runtime_key_is(key, c"aborted")): return js_runtime_boolean(rt, state.aborted)
	if (js_runtime_key_is(key, c"reason")): return state.reason
	if (js_runtime_key_is(key, c"onabort")):
		if (state.handler != 0 && state.handler.removed == 0): return state.handler.callback
		return js_runtime_alloc(rt, 1)
	return 0

int win_abort_signal_has(void* runtime, void* context, js_value* receiver, js_text* key):
	win_abort_state* state = cast(win_abort_state*, context)
	if (receiver != state.signal): return 0
	return js_runtime_key_is(key, c"aborted") || js_runtime_key_is(key, c"reason") || js_runtime_key_is(key, c"onabort")

win_abort_state* win_abort_signal(js_value* value):
	if (value == 0 || value.host_get != cast(int, win_abort_signal_get)): return 0
	win_abort_state* state = cast(win_abort_state*, value.host_context)
	if (state.signal != value): return 0
	return state

void win_abort_collect(win_abort_state* state):
	if (state.dispatching): return
	int count = 0
	for i in range(state.listeners.length):
		win_abort_listener* listener = state.listeners[i]
		if (listener.removed):
			if (state.handler == listener): state.handler = 0
			js_runtime_unroot(state.context.runtime, listener.holder)
			js_text_free(listener.type)
			free(listener)
		else:
			state.listeners[count] = listener
			count = count + 1
	while (state.listeners.length > count): state.listeners.pop()

win_abort_listener* win_abort_add(win_abort_state* state, js_text* type, js_value* callback, int capture, int once, int passive):
	js_runtime* rt = state.context.runtime
	win_abort_collect(state)
	if (state.listeners.length >= 1024):
		js_runtime_fail(rt, 5, c"AbortSignal listener limit")
		return 0
	win_abort_listener* listener = new win_abort_listener()
	listener.holder = js_runtime_alloc(rt, 5)
	if (rt.completion.status == 0): js_runtime_set(rt, listener.holder, c"callback", callback)
	if (rt.completion.status != 0):
		free(listener)
		return 0
	js_runtime_root(rt, listener.holder)
	listener.callback = callback
	listener.type = js_text_clone(type)
	listener.capture = capture
	listener.once = once
	listener.passive = passive
	state.listeners.push(listener)
	return listener

int win_abort_signal_set(void* runtime, void* context, js_value* receiver, js_text* key, js_value* value):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_abort_state* state = cast(win_abort_state*, context)
	if (receiver != state.signal): return 0
	if (js_runtime_key_is(key, c"aborted") || js_runtime_key_is(key, c"reason")): return 1
	if (js_runtime_key_is(key, c"onabort") == 0): return 0
	if (js_runtime_callable(value) == 0):
		if (state.handler != 0): state.handler.removed = 1
		state.handler = 0
	else if (state.handler != 0 && state.handler.removed == 0):
		state.handler.callback = value
		js_runtime_set(rt, state.handler.holder, c"callback", value)
	else:
		js_text* type = js_runtime_key(c"abort")
		state.handler = win_abort_add(state, type, value, 0, 0, 0)
		js_text_free(type)
	win_abort_collect(state)
	return 1

js_value* win_abort_listen(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_abort_state* state = win_abort_signal(receiver)
	if (state == 0):
		js_runtime_fail(rt, 2, c"Illegal AbortSignal receiver")
		return rt.undefined_value
	if (args.length < 2 || args[0].kind != 4):
		js_runtime_fail(rt, 2, c"AbortSignal listener requires type and callback")
		return rt.undefined_value
	if (args[1].kind == 0 || args[1].kind == 1): return rt.undefined_value
	if (js_runtime_callable(args[1]) == 0):
		js_runtime_fail(rt, 6, c"AbortSignal listener objects outside subset")
		return rt.undefined_value
	int capture = 0
	int once = 0
	int passive = 0
	if (args.length > 2):
		if (js_runtime_object(args[2])):
			capture = js_runtime_truth(js_runtime_get(rt, args[2], c"capture"))
			once = js_runtime_truth(js_runtime_get(rt, args[2], c"once"))
			passive = js_runtime_truth(js_runtime_get(rt, args[2], c"passive"))
			if (js_runtime_get(rt, args[2], c"signal").kind != 0):
				js_runtime_fail(rt, 6, c"Listener signal option outside subset")
		else: capture = js_runtime_truth(args[2])
	if (rt.completion.status != 0): return rt.undefined_value
	for i in range(state.listeners.length):
		win_abort_listener* listener = state.listeners[i]
		if (listener.removed == 0 && listener != state.handler && listener.callback == args[1] && listener.capture == capture && js_text_equal(listener.type, args[0].text)):
			if (context != 0): listener.removed = 1
			win_abort_collect(state)
			return rt.undefined_value
	if (context == 0): win_abort_add(state, args[0].text, args[1], capture, once, passive)
	return rt.undefined_value

void win_abort_dispatch(win_abort_state* state, js_value* event):
	js_runtime* rt = state.context.runtime
	js_value* zero = js_runtime_get(rt, event, c"eventPhase")
	js_value* null_value = js_runtime_get(rt, event, c"currentTarget")
	js_value* type = js_runtime_get(rt, event, c"type")
	win_event_write(rt, event, c"target", state.signal)
	win_event_write(rt, event, c"currentTarget", state.signal)
	win_event_write(rt, event, c"eventPhase", js_runtime_number(rt, 2.0))
	win_event_flag_set(event, WIN_EVENT_DISPATCHING, 1)
	state.dispatching = state.dispatching + 1
	list[js_value*] args = new list[js_value*]
	args.push(event)
	# At-target capture listeners run before ordinary listeners, with a fresh
	# snapshot for each phase as in the DOM dispatch algorithm.
	for phase in range(2):
		int count = state.listeners.length
		for i in range(count):
			if (rt.completion.status != 0 || win_event_flag(event, WIN_EVENT_IMMEDIATE)): break
			win_abort_listener* listener = state.listeners[i]
			if (listener.removed || listener.capture != 1 - phase || js_text_equal(listener.type, type.text) == 0): continue
			if (listener.once): listener.removed = 1
			win_event_flag_set(event, WIN_EVENT_PASSIVE, listener.passive)
			js_runtime_call_receiver(rt, listener.callback, state.signal, args)
			if (rt.completion.status != 0 && rt.completion.status != 5):
				if (state.context.report != 0): state.context.report(state.context.owner, rt.completion)
				rt.completion.status = 0
				rt.completion.value = rt.undefined_value
				rt.completion.message = c""
			win_event_flag_set(event, WIN_EVENT_PASSIVE, 0)
	__w_list_free(cast(__w_list*, args))
	state.dispatching = state.dispatching - 1
	win_event_write(rt, event, c"currentTarget", null_value)
	win_event_write(rt, event, c"eventPhase", zero)
	event.host_context = 0
	win_abort_collect(state)

js_value* win_abort_dispatch_host(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_abort_state* state = win_abort_signal(receiver)
	if (state == 0 || args.length == 0 || win_event_is(args[0]) == 0):
		js_runtime_fail(rt, 2, c"AbortSignal dispatchEvent requires signal and Event")
		return rt.undefined_value
	if (win_event_flag(args[0], WIN_EVENT_DISPATCHING)):
		js_value* error = js_runtime_error_value(rt, c"Event is already being dispatched")
		js_runtime_set(rt, error, c"name", win_web_string(rt, c"InvalidStateError"))
		js_runtime_throw(rt, error)
		return rt.undefined_value
	win_event_write(rt, args[0], c"isTrusted", js_runtime_boolean(rt, 0))
	win_abort_dispatch(state, args[0])
	return js_runtime_boolean(rt, js_runtime_truth(js_runtime_get(rt, args[0], c"defaultPrevented")) == 0)

js_value* win_abort_throw(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_abort_state* state = win_abort_signal(receiver)
	if (state == 0): js_runtime_fail(rt, 2, c"Illegal AbortSignal receiver")
	else if (state.aborted): js_runtime_throw(rt, state.reason)
	return rt.undefined_value

void win_abort_fire(win_abort_state* state, js_value* reason):
	if (state.aborted): return
	js_runtime* rt = state.context.runtime
	if (reason.kind == 0):
		reason = js_runtime_error_value(rt, c"The operation was aborted")
		if (reason == rt.undefined_value && rt.completion.status == 0): js_runtime_fail(rt, 5, c"Abort reason allocation limit")
		if (rt.completion.status != 0): return
		js_runtime_set(rt, reason, c"name", win_web_string(rt, c"AbortError"))
	if (rt.completion.status != 0): return
	state.reason = reason
	win_event_write(rt, state.signal, c"reason", reason)
	if (rt.completion.status != 0): return
	state.aborted = 1
	# Observer callbacks cannot invoke JS, allocate JS values, or mutate this list.
	for i in range(state.observers.length):
		win_abort_observer* observer = state.observers[i]
		if (observer.callback != 0): observer.callback(observer.context)
	js_value* event = win_event_new(rt, win_web_string(rt, c"abort"), 0, 0, 0, cast(float64, time_monotonic_ms()))
	if (rt.completion.status == 0 && win_event_is(event) && js_runtime_root(rt, event)):
		win_event_write(rt, event, c"isTrusted", js_runtime_boolean(rt, 1))
		if (rt.completion.status == 0): win_abort_dispatch(state, event)
		js_runtime_unroot(rt, event)

js_value* win_abort_abort(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_abort_state* state = cast(win_abort_state*, context)
	if (receiver != state.controller):
		js_runtime_fail(rt, 2, c"Illegal AbortController receiver")
		return rt.undefined_value
	js_value* reason = rt.undefined_value
	if (args.length > 0): reason = args[0]
	win_abort_fire(state, reason)
	return rt.undefined_value

js_value* win_abort_construct(void* runtime, void* host, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_abort_context* context = cast(win_abort_context*, host)
	if (context == 0):
		js_runtime_fail(rt, 2, c"Illegal AbortSignal constructor")
		return rt.undefined_value
	if (context.states.length >= 256):
		js_runtime_fail(rt, 5, c"AbortController realm limit")
		return rt.undefined_value
	js_value* controller = js_runtime_alloc(rt, 5)
	if (rt.completion.status != 0): return rt.undefined_value
	js_value* signal = js_runtime_alloc(rt, 5)
	if (rt.completion.status != 0): return rt.undefined_value
	win_abort_state* state = new win_abort_state()
	state.context = context
	state.controller = controller
	state.signal = signal
	state.reason = rt.undefined_value
	state.listeners = new list[win_abort_listener*]
	state.observers = new list[win_abort_observer*]
	js_runtime_root(rt, controller)
	js_runtime_root(rt, signal)
	# Own definitions cannot call prototype setters or expose a partial state.
	# Publish the native owner and its hooks only once every allocation succeeds.
	win_event_write(rt, controller, c"signal", signal)
	if (rt.completion.status == 0): win_event_write(rt, signal, c"reason", state.reason)
	if (rt.completion.status == 0): win_event_own_method(rt, controller, c"abort", state, win_abort_abort)
	if (rt.completion.status == 0): win_event_own_method(rt, signal, c"throwIfAborted", 0, win_abort_throw)
	if (rt.completion.status == 0): win_event_own_method(rt, signal, c"addEventListener", 0, win_abort_listen)
	if (rt.completion.status == 0): win_event_own_method(rt, signal, c"removeEventListener", cast(void*, 1), win_abort_listen)
	if (rt.completion.status == 0): win_event_own_method(rt, signal, c"dispatchEvent", 0, win_abort_dispatch_host)
	if (rt.completion.status != 0):
		js_runtime_unroot(rt, controller)
		js_runtime_unroot(rt, signal)
		__w_list_free(cast(__w_list*, state.listeners))
		__w_list_free(cast(__w_list*, state.observers))
		free(state)
		return rt.undefined_value
	js_runtime_set_host_hooks(rt, signal, state, win_abort_signal_get, win_abort_signal_set)
	js_runtime_set_host_has(rt, signal, win_abort_signal_has)
	context.states.push(state)
	return controller

win_abort_observer* win_abort_observe(win_abort_state* state, void* context, win_abort_callback* callback):
	if (state == 0): return 0
	win_abort_observer* observer = new win_abort_observer()
	observer.context = context
	observer.callback = callback
	state.observers.push(observer)
	return observer

void win_abort_unobserve(win_abort_state* state, win_abort_observer* observer):
	if (state == 0 || observer == 0): return
	for i in range(state.observers.length):
		if (state.observers[i] == observer):
			for j in range(i, state.observers.length - 1): state.observers[j] = state.observers[j + 1]
			state.observers.pop()
			free(observer)
			return

win_abort_context* win_abort_new(js_runtime* rt, js_value* window, void* owner, win_abort_report* report):
	win_abort_context* context = new win_abort_context()
	context.runtime = rt
	context.owner = owner
	context.report = report
	context.states = new list[void*]
	js_value* controller = js_runtime_host_callable(rt, context, win_abort_construct)
	js_value* signal = js_runtime_host_callable(rt, 0, win_abort_construct)
	controller.host_construct = 2
	signal.host_construct = 2
	js_runtime_set(rt, rt.global, c"AbortController", controller)
	js_runtime_set(rt, window, c"AbortController", controller)
	js_runtime_set(rt, rt.global, c"AbortSignal", signal)
	js_runtime_set(rt, window, c"AbortSignal", signal)
	return context

void win_abort_free(win_abort_context* context):
	if (context == 0): return
	for i in range(context.states.length):
		win_abort_state* state = cast(win_abort_state*, context.states[i])
		for j in range(state.listeners.length): state.listeners[j].removed = 1
		win_abort_collect(state)
		for j in range(state.observers.length): free(state.observers[j])
		__w_list_free(cast(__w_list*, state.listeners))
		__w_list_free(cast(__w_list*, state.observers))
		js_runtime_unroot(context.runtime, state.controller)
		js_runtime_unroot(context.runtime, state.signal)
		free(state)
	__w_list_free(cast(__w_list*, context.states))
	free(context)
