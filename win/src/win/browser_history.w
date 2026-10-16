# https://html.spec.whatwg.org/multipage/nav-history-apis.html#the-history-interface
# state serialization is deliberately limited by history_state.w.
import win.browser

void win_browser_history_address(win_browser* b):
	if (b.script == 0): return
	free(b.script.address)
	b.script.address = strclone(b.address)
	if (b.fetches != 0):
		free(b.fetches.address)
		b.fetches.address = strclone(b.address)
	if (b.resources != 0):
		char* base = win_resolve(b.address, win_resources_base(b.page.html.root))
		if (base != 0):
			free(b.resources.base)
			b.resources.base = base
	if (b.script.modules != 0):
		free(b.script.modules.address)
		b.script.modules.address = strclone(b.address)

void win_browser_history_state(win_browser* b):
	if (b.script == 0 || b.history_object == 0 || b.current < 0): return
	js_runtime* rt = b.script.runtime
	int entered = rt.running == 0
	if (entered):
		if (js_runtime_begin(rt, b.script.execution_budget) == 0): return
		rt.running = 1
	js_value* value = win_history_decode(rt, b.history[b.current].state)
	if (rt.completion.status == 0): win_event_write(rt, b.history_object, c"state", value)
	if (entered):
		rt.running = 0
		win_script_result(b.script, rt.completion)

js_value* win_history_get(void* runtime, void* context, js_value* receiver, js_text* key):
	win_browser* b = cast(win_browser*, context)
	js_runtime* rt = cast(js_runtime*, runtime)
	if (receiver != b.history_object): return 0
	if (js_runtime_key_is(key, c"length")): return js_runtime_number(rt, cast(float64, b.history.length))
	return 0

int win_history_set(void* runtime, void* context, js_value* receiver, js_text* key, js_value* value):
	if (js_runtime_key_is(key, c"length") || js_runtime_key_is(key, c"state")): return -1
	return 0

int win_history_has(void* runtime, void* context, js_value* receiver, js_text* key):
	return js_runtime_key_is(key, c"length")

js_value* win_history_mutate(js_runtime* rt, win_browser* b, js_value* receiver, list[js_value*] args, int replace):
	if (receiver != b.history_object || args.length < 2 || b.current < 0):
		win_history_error(rt, c"TypeError", c"History mutation requires its receiver and two arguments")
		return rt.undefined_value
	char* encoded = win_history_encode(rt, args[0])
	if (encoded == 0): return rt.undefined_value
	char* address = 0
	if (args.length < 3 || args[2].kind == 0 || args[2].kind == 1): address = strclone(b.address)
	else if (args[2].kind == 4):
		int length = 0
		char* reference = win_web_usv_bytes(args[2].text, &length)
		if (reference != 0 && strlen(reference) == length):
			if (length == 0): address = strclone(b.address)
			else: address = win_resolve(win_browser_base(b), reference)
		free(reference)
	else: win_history_error(rt, c"TypeError", c"History URL must be a string")
	if (address == 0 || win_fetch_same_origin(b.address, address) == 0):
		free(address)
		free(encoded)
		win_history_error(rt, c"SecurityError", c"History URL must retain the HTTP(S) origin")
		return rt.undefined_value
	if (b.history_wire_limit > 0):
		int bytes = 8 + 20 + strlen(address) + strlen(encoded)
		int last = b.current + 1
		int first = 0
		if (replace): last = b.history.length
		else if (last == 128): first = 1
		for i in range(first, last):
			if (replace && i == b.current): continue
			bytes = bytes + 20 + strlen(b.history[i].address) + strlen(b.history[i].state)
		if (bytes > b.history_wire_limit || strlen(address) > 65536 || b.history_serial >= 2147483647):
			free(address)
			free(encoded)
			win_history_error(rt, c"QuotaExceededError", c"Isolated history metadata exceeds its bounded transport limit")
			return rt.undefined_value
	# Decode before changing URL/history so quota failures leave them untouched.
	js_value* snapshot = win_history_decode(rt, encoded)
	if (rt.completion.status == 0):
		b.history[b.current].scroll = b.scroll.offset_y
		int target = -1
		if (replace): target = b.current
		win_commit_address(b, address, target)
		free(b.history[b.current].state)
		b.history[b.current].state = encoded
		encoded = 0
		b.history[b.current].document_generation = b.document_generation
		win_event_write(rt, b.history_object, c"state", snapshot)
		b.restore_pending = 0
		win_browser_history_address(b)
	free(address)
	free(encoded)
	return rt.undefined_value

js_value* win_history_push_host(void* rt, void* context, js_value* receiver, list[js_value*] args):
	return win_history_mutate(cast(js_runtime*, rt), cast(win_browser*, context), receiver, args, 0)

js_value* win_history_replace_host(void* rt, void* context, js_value* receiver, list[js_value*] args):
	return win_history_mutate(cast(js_runtime*, rt), cast(win_browser*, context), receiver, args, 1)

js_value* win_history_traverse(js_runtime* rt, win_browser* b, js_value* receiver, int delta):
	if (receiver != b.history_object): win_history_error(rt, c"TypeError", c"History traversal requires its receiver")
	else if (b.traversals.length >= 32): js_runtime_fail(rt, 5, c"History traversal queue limit")
	else: win_history_go(b, delta)
	return rt.undefined_value

js_value* win_history_back_host(void* rt, void* context, js_value* receiver, list[js_value*] args):
	return win_history_traverse(cast(js_runtime*, rt), cast(win_browser*, context), receiver, -1)

js_value* win_history_forward_host(void* rt, void* context, js_value* receiver, list[js_value*] args):
	return win_history_traverse(cast(js_runtime*, rt), cast(win_browser*, context), receiver, 1)

js_value* win_history_go_host(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	int delta = 0
	if (args.length > 0 && args[0].kind != 0):
		if (args[0].kind != 3 || js_builtin_finite(args[0].number) == 0 || args[0].number < -2147483648.0 || args[0].number > 2147483647.0):
			win_history_error(rt, c"TypeError", c"History delta requires a finite signed 32-bit number")
			return rt.undefined_value
		delta = cast(int, args[0].number)
	return win_history_traverse(rt, cast(win_browser*, context), receiver, delta)

void win_browser_history_install(win_browser* b):
	js_runtime* rt = b.script.runtime
	b.history_object = js_runtime_alloc(rt, 5)
	js_value* object = b.history_object
	js_runtime_set_host_hooks(rt, object, b, win_history_get, win_history_set)
	js_runtime_set_host_has(rt, object, win_history_has)
	js_runtime_set(rt, object, c"pushState", js_runtime_host_callable(rt, b, win_history_push_host))
	js_runtime_set(rt, object, c"replaceState", js_runtime_host_callable(rt, b, win_history_replace_host))
	js_runtime_set(rt, object, c"back", js_runtime_host_callable(rt, b, win_history_back_host))
	js_runtime_set(rt, object, c"forward", js_runtime_host_callable(rt, b, win_history_forward_host))
	js_runtime_set(rt, object, c"go", js_runtime_host_callable(rt, b, win_history_go_host))
	js_runtime_set(rt, rt.global, c"history", object)
	js_runtime_set(rt, win_script_wrap(b.script, b.script.window_node), c"history", object)
	win_browser_history_state(b)

void win_browser_history_event(win_browser* b):
	win_script* script = b.script
	js_runtime* rt = script.runtime
	win_script* previous = win_active_script
	win_active_script = script
	js_runtime_collect(rt)
	if (js_runtime_begin(rt, script.execution_budget)):
		rt.running = 1
		js_value* event = win_event_new(rt, win_js_string(rt, c"popstate"), 0, 0, 0, cast(float64, time_monotonic_ms() - script.time_origin))
		js_runtime_root(rt, event)
		win_event_write(rt, event, c"state", js_runtime_get(rt, b.history_object, c"state"))
		win_event_write(rt, event, c"isTrusted", js_runtime_boolean(rt, 1))
		if (rt.completion.status == 0): win_script_dispatch_event(script, script.window_node, event)
		rt.running = 0
		js_runtime_unroot(rt, event)
		win_script_result(script, rt.completion)
		if (rt.completion.status != 5): win_script_checkpoint(script)
	win_active_script = previous

void win_browser_history_poll(win_browser* b):
	if (b.traversals.length == 0 || b.load != 0): return
	int delta = b.traversals[0]
	for i in range(b.traversals.length - 1): b.traversals[i] = b.traversals[i + 1]
	b.traversals.pop()
	int target = b.current + delta
	if (target < 0 || target >= b.history.length): return
	char* address = strclone(b.history[target].address)
	if (delta != 0 && b.script != 0 && b.history[target].document_generation == b.document_generation):
		b.history[b.current].scroll = b.scroll.offset_y
		win_commit_address(b, address, target)
		b.scroll.offset_y = b.history[target].scroll
		b.restore_pending = 0
		win_browser_history_address(b)
		win_browser_history_state(b)
		win_browser_history_event(b)
	else:
		if (delta == 0): target = -2
		win_navigate(b, address, c"", target)
	free(address)

# Queue same-document chrome traversal at its position among native input.
# A dead/replaced realm is deliberately handled by the ordinary reload path.
int win_browser_history_isolated_go(win_browser* b, int delta):
	win_interactive_worker* worker = b.interactive
	if (b.isolated == 0 || worker == 0 || worker.child == 0 || worker.history.length == 0 || delta == 0 || delta < -127 || delta > 127): return 0
	win_interactive_input* control = new win_interactive_input()
	control.history_delta = delta
	control.generation = worker.generation
	control.document = worker.document_generation
	control.width = b.viewport_width
	control.height = b.viewport_height
	if (win_interactive_enqueue(worker, control) == 0):
		free(control)
		if (worker.child != 0): win_interactive_fail(worker, 5, c"Isolated history queue rejected traversal")
		win_status(b, worker.error)
	return 1

# Resolve the delta only after all preceding input and frame ACKs complete.
# A preceding click may push/truncate history. Cross-realm navigation uses this
# same queue position instead of overtaking already accepted native input.
int win_browser_history_isolated_dispatch(win_browser* b):
	win_interactive_worker* worker = b.interactive
	if (worker == 0 || worker.busy || worker.input_queue.length == 0): return 0
	win_interactive_input* control = worker.input_queue[0]
	if (control.history_delta == 0 || control.document != worker.document_generation): return 0
	int target = b.current + control.history_delta
	if (target >= 0 && target < b.history.length):
		win_history_entry* entry = b.history[target]
		if (entry.worker_generation == worker.generation): return 0
	for i in range(1, worker.input_queue.length): worker.input_queue[i - 1] = worker.input_queue[i]
	worker.input_queue.pop()
	free(control)
	if (target < 0 || target >= b.history.length): return 1
	char* address = strclone(b.history[target].address)
	win_navigate(b, address, c"", target)
	free(address)
	return 2

void win_browser_history_entry_free(win_history_entry* entry):
	free(entry.address)
	free(entry.state)
	free(entry)

# A worker owns a contiguous segment of tab history. Match stable entry IDs,
# not URLs: pushState may use the same URL and replaceState must not append.
void win_browser_history_snapshot(win_browser* b, int first):
	win_interactive_worker* worker = b.interactive
	if (worker.history.length == 0): return
	if (first):
		win_commit_address(b, worker.history[0].address, b.pending_history)
		b.history[b.current].worker_generation = worker.generation
		b.history[b.current].worker_serial = worker.history[0].serial
	int start = -1
	int end = -1
	for i in range(b.history.length):
		if (b.history[i].worker_generation == worker.generation):
			if (start < 0): start = i
			end = i + 1
	if (start < 0): return
	int changed = end - start != worker.history.length
	if (changed == 0):
		for i in range(worker.history.length):
			if (b.history[start + i].worker_serial != worker.history[i].serial): changed = 1
	list[win_history_entry*] next = new list[win_history_entry*]
	for i in range(start): next.push(b.history[i])
	for win_interactive_history_entry* remote in worker.history:
		win_history_entry* entry = new win_history_entry()
		entry.worker_generation = worker.generation
		entry.worker_serial = remote.serial
		entry.document_generation = remote.document
		entry.address = strclone(remote.address)
		entry.state = strclone(remote.state)
		entry.scroll = cast(float32, remote.scroll)
		next.push(entry)
	for i in range(start, end): win_browser_history_entry_free(b.history[i])
	for i in range(end, b.history.length):
		if (changed): win_browser_history_entry_free(b.history[i])
		else: next.push(b.history[i])
	__w_list_free(cast(__w_list*, b.history))
	b.history = next
	b.current = start + worker.history_current
	while (b.history.length > 128):
		win_browser_history_entry_free(b.history[0])
		for i in range(1, b.history.length): b.history[i - 1] = b.history[i]
		b.history.pop()
		b.current = b.current - 1
	b.document_generation = worker.document_generation
	free(b.address)
	b.address = strclone(worker.address)
	ui_textarea_set(&b.input, b.address)
	ui_textarea_set_caret(&b.input, strlen(b.address))
