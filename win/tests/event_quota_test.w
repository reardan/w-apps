import lib.assert
import win.app

js_value* quota_callback(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	int* count = cast(int*, context)
	count[0] = count[0] + 1
	js_runtime* rt = cast(js_runtime*, runtime)
	return rt.undefined_value

void quota_observer(void* context):
	int* count = cast(int*, context)
	count[0] = count[0] + 1

void quota_listen(win_script* script, char* name, int* count):
	win_script_listener* listener = new win_script_listener()
	listener.node = script.window_node
	listener.event = strclone(name)
	listener.callback = js_runtime_host_callable(script.runtime, count, quota_callback)
	js_runtime_root(script.runtime, listener.callback)
	script.listeners.push(listener)

void quota_unchanged(js_runtime* rt, int roots, js_value* prototype):
	assert_equal(roots, rt.roots.length)
	int found = 0
	for i in range(rt.roots.length):
		if (rt.roots[i] == rt.undefined_value): found = 1
	asserts(c"caller owns undefined root", found)
	assert_equal(0, rt.undefined_value.host_get)
	assert_equal(0, rt.undefined_value.host_set)
	assert_equal(0, rt.undefined_value.host_has)
	assert_equal(0, cast(int, rt.undefined_value.host_context))
	assert_equal(0, rt.undefined_value.properties.length)
	assert1(rt.undefined_value.prototype == prototype)

void quota_dispatch(win_browser* browser, int kind):
	win_script* script = browser.script
	if (kind == 0):
		win_keyboard_packet packet
		packet.type = c"keydown"
		packet.scalar = 97
		win_keyboard_dispatch(script, script.window_node, &packet)
	else if (kind == 1): win_browser_history_event(browser)
	else if (kind == 2): win_script_focus_event(script, script.window_node, 0, c"focus", 0)
	else if (kind == 3): win_script_pointer_dispatch(script, script.window_node, c"pointerdown", 0, 0, 0)
	else: win_script_dispatch(script, script.window_node, c"click")

# The guarded path avoids the full browser's JavaScript bootstrap: its many
# transient compiler allocations exhaust Linux's guarded-mapping allowance.
# Full native caller delivery and recovery are exercised by the normal path.
void quota_guarded():
	js_runtime* rt = js_runtime_new()
	win_abort_context* context = new win_abort_context()
	context.runtime = rt
	context.states = new list[void*]
	list[js_value*] args = new list[js_value*]
	js_runtime_root(rt, rt.undefined_value)
	js_value* prototype = rt.undefined_value.prototype
	int values = rt.max_values
	int properties = rt.max_properties
	for kind in range(3):
		for allowance in range(21):
			js_runtime_begin(rt, 100000)
			js_runtime_collect(rt)
			int roots = rt.roots.length
			int states = context.states.length
			if (kind == 2): rt.max_properties = allowance
			else: rt.max_values = rt.heap.length + allowance
			js_value* result = rt.undefined_value
			if (kind == 0): result = win_event_new(rt, win_web_string(rt, c"event"), 1, 1, 0, 0.0)
			else: result = win_abort_construct(rt, context, rt.undefined_value, args)
			if (rt.completion.status != 0):
				assert_equal(5, rt.completion.status)
				assert1(result == rt.undefined_value)
				assert_equal(states, context.states.length)
				quota_unchanged(rt, roots, prototype)
			else if (kind != 0): quota_unchanged(rt, roots + 2, prototype)
			rt.max_values = values
			rt.max_properties = properties
	win_abort_free(context)
	quota_unchanged(rt, 1, prototype)
	__w_list_free(cast(__w_list*, args))
	js_runtime_free(rt)
	assert_equal(0, debug_alloc_report_leaks())

int main(int argc, char** argv):
	int guard = argc == 2 && strcmp(argv[1], c"memory") == 0
	if (guard):
		malloc_force_debug_mode()
		quota_guarded()
		println(c"Guarded Event and AbortController allocation rollback: OK")
		return 0
	win_browser browser
	win_browser_init(&browser, c"unused", c"unused")
	char* html = c"<body></body>"
	browser.page = win_page_parse(html, strlen(html))
	browser.script = win_script_new(browser.page)
	win_script* script = browser.script
	js_runtime* rt = script.runtime
	# This native history object is sufficient for popstate's state read.
	browser.history_object = js_runtime_alloc(rt, 5)
	js_runtime_set(rt, browser.history_object, c"state", rt.undefined_value)
	js_runtime_root(rt, browser.history_object)
	int calls = 0
	quota_listen(script, c"keydown", &calls)
	quota_listen(script, c"popstate", &calls)
	quota_listen(script, c"focus", &calls)
	quota_listen(script, c"pointerdown", &calls)
	quota_listen(script, c"click", &calls)
	js_runtime_root(rt, rt.undefined_value)
	js_value* prototype = rt.undefined_value.prototype
	int values = rt.max_values
	int properties = rt.max_properties
	int roots = rt.roots.length
	int initial_roots = roots
	# Refuse before the Event object and at several partially built stages.
	for kind in range(5):
		for allowance in range(9):
			js_runtime_begin(rt, 100000)
			js_runtime_collect(rt)
			rt.max_values = rt.heap.length + allowance
			quota_dispatch(&browser, kind)
			assert_equal(5, rt.completion.status)
			assert_equal(0, calls)
			quota_unchanged(rt, roots, prototype)
			rt.max_values = values
		js_runtime_begin(rt, 100000)
		quota_dispatch(&browser, kind)
		assert_equal(0, rt.completion.status)
		assert_equal(1, calls)
		calls = 0
		quota_unchanged(rt, roots, prototype)
	# Failed controller construction never publishes native owners or roots.
	list[js_value*] args = new list[js_value*]
	int refused = 0
	for mode in range(2):
		for allowance in range(21):
			js_runtime_begin(rt, 100000)
			js_runtime_collect(rt)
			int before = script.aborts.states.length
			int before_roots = rt.roots.length
			if (mode == 0): rt.max_values = rt.heap.length + allowance
			else: rt.max_properties = allowance
			js_value* result = win_abort_construct(rt, script.aborts, rt.undefined_value, args)
			if (rt.completion.status != 0):
				assert_equal(5, rt.completion.status)
				assert1(result == rt.undefined_value)
				assert_equal(before, script.aborts.states.length)
				quota_unchanged(rt, before_roots, prototype)
				refused = refused + 1
			else:
				assert_equal(before + 1, script.aborts.states.length)
				quota_unchanged(rt, before_roots + 2, prototype)
			rt.max_values = values
			rt.max_properties = properties
	asserts(c"constructor quota failures exercised", refused > 20)
	# Own constructor methods cannot invoke inherited setters and expose a
	# state that may subsequently fail. Test this without parsing JavaScript.
	js_runtime_begin(rt, 100000)
	js_value* setter = js_runtime_host_callable(rt, &calls, quota_callback)
	js_text* key = js_runtime_key(c"abort")
	js_runtime_define_accessor(rt, rt.object_prototype, key, 0, setter, 0, 1)
	js_text_free(key)
	js_value* controller = win_abort_construct(rt, script.aborts, rt.undefined_value, args)
	assert_equal(0, rt.completion.status)
	assert_equal(0, calls)
	asserts(c"own abort method", js_runtime_callable(js_runtime_get(rt, controller, c"abort")))
	# Native cancellation observers still run when JS Event allocation fails.
	# JS listeners do not run, and each signal retains the explicit reason.
	int observed = 0
	for allowance in range(9):
		js_runtime_begin(rt, 100000)
		controller = win_abort_construct(rt, script.aborts, rt.undefined_value, args)
		win_abort_state* state = win_abort_signal(js_runtime_get(rt, controller, c"signal"))
		assert1(state != 0)
		js_text* type = js_runtime_key(c"abort")
		win_abort_add(state, type, js_runtime_host_callable(rt, &calls, quota_callback), 0, 0, 0)
		js_text_free(type)
		win_abort_observe(state, &observed, quota_observer)
		js_value* reason = js_runtime_number(rt, 17.0)
		js_runtime_root(rt, reason)
		js_runtime_collect(rt)
		roots = rt.roots.length
		rt.max_values = rt.heap.length + allowance
		win_abort_fire(state, reason)
		assert_equal(5, rt.completion.status)
		assert_equal(1, state.aborted)
		assert1(state.reason == reason)
		assert_equal(allowance + 1, observed)
		assert_equal(0, calls)
		quota_unchanged(rt, roots, prototype)
		rt.max_values = values
		js_runtime_unroot(rt, reason)
	js_runtime_begin(rt, 100000)
	controller = win_abort_construct(rt, script.aborts, rt.undefined_value, args)
	win_abort_state* state = win_abort_signal(js_runtime_get(rt, controller, c"signal"))
	js_text* type = js_runtime_key(c"abort")
	win_abort_add(state, type, js_runtime_host_callable(rt, &calls, quota_callback), 0, 0, 0)
	js_text_free(type)
	win_abort_fire(state, js_runtime_number(rt, 19.0))
	assert_equal(0, rt.completion.status)
	assert_equal(1, calls)
	# Default-reason allocation refusal must not mutate the undefined sentinel.
	controller = win_abort_construct(rt, script.aborts, rt.undefined_value, args)
	state = win_abort_signal(js_runtime_get(rt, controller, c"signal"))
	js_runtime_collect(rt)
	roots = rt.roots.length
	rt.max_values = rt.heap.length
	win_abort_fire(state, rt.undefined_value)
	assert_equal(5, rt.completion.status)
	assert_equal(0, state.aborted)
	quota_unchanged(rt, roots, prototype)
	rt.max_values = values
	__w_list_free(cast(__w_list*, args))
	# Teardown cannot remove the caller's independent sentinel root.
	win_abort_free(script.aborts)
	script.aborts = 0
	quota_unchanged(rt, initial_roots, prototype)
	js_runtime_unroot(rt, rt.undefined_value)
	js_runtime_unroot(rt, browser.history_object)
	win_browser_free(&browser)
	win_network_state_clear()
	println(c"Event allocation refusal, root ownership, abort rollback and recovery: OK")
	return 0
