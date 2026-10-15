# Bounded same-origin Fetch subset. Network I/O runs in cancellable loaders;
# Promise reactions are drained by the page's normal microtask checkpoint.
import win.loader
import libs.extras.javascript.runtime

struct win_fetch_request:
	win_load* load
	js_value* promise
	js_value* response
	js_value* body
	int consumed
	char* failure

struct win_fetch_context:
	js_runtime* runtime
	char* executable
	char* address
	list[win_fetch_request*] requests
	int bytes

js_value* win_fetch_string(js_runtime* rt, char* text, int length):
	js_text* units = js_text_from_utf8(text, length)
	if (units == 0): return rt.undefined_value
	js_value* result = js_runtime_string(rt, units)
	js_text_free(units)
	return result

int win_fetch_same_origin(char* left, char* right):
	URL* a = url_parse(left)
	URL* b = url_parse(right)
	int same = a != 0 && b != 0
	if (same): same = strcmp(a.scheme, b.scheme) == 0 && strcmp(a.host, b.host) == 0 && a.port == b.port
	if (a != 0): url_free(a)
	if (b != 0): url_free(b)
	return same

js_value* win_fetch_reject(js_runtime* rt, js_value* promise, char* message):
	js_runtime_promise_settle(rt, promise, js_runtime_error_value(rt, message), 1)
	return promise

js_value* win_fetch_text(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_fetch_request* request = cast(win_fetch_request*, context)
	js_value* promise = js_runtime_promise_new(rt)
	if (rt.completion.status != 0): return promise
	if (receiver != request.response): return win_fetch_reject(rt, promise, c"Illegal Response receiver")
	if (request.consumed): return win_fetch_reject(rt, promise, c"Response body already consumed")
	request.consumed = 1
	js_runtime_set(rt, receiver, c"bodyUsed", js_runtime_boolean(rt, 1))
	js_runtime_promise_settle(rt, promise, request.body, 0)
	return promise

int win_fetch_pending(win_fetch_context* context):
	if (context == 0): return 0
	int count = 0
	for i in range(context.requests.length):
		if (context.requests[i].load != 0): count = count + 1
	return count

js_value* win_fetch_host(void* runtime, void* host, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_fetch_context* context = cast(win_fetch_context*, host)
	js_value* promise = js_runtime_promise_new(rt)
	if (rt.completion.status != 0): return promise
	if (args.length == 0 || args[0].kind != 4): return win_fetch_reject(rt, promise, c"fetch requires a URL string")
	# Unsupported options are rejected instead of silently changing semantics.
	if (args.length > 1 && args[1].kind != 0): return win_fetch_reject(rt, promise, c"Fetch options are not yet supported")
	if (context.requests.length >= 64 || win_fetch_pending(context) >= 3): return win_fetch_reject(rt, promise, c"Page fetch request limit")
	int length = 0
	char* reference = js_text_to_utf8(args[0].text, &length)
	if (reference == 0): return win_fetch_reject(rt, promise, c"Invalid fetch URL")
	char* address = 0
	if (strlen(reference) == length): address = win_resolve(context.address, reference)
	free(reference)
	if (address == 0): return win_fetch_reject(rt, promise, c"Invalid fetch URL")
	if (win_fetch_same_origin(context.address, address) == 0):
		free(address)
		return win_fetch_reject(rt, promise, c"Fetch requires a same-origin HTTP(S) URL")
	win_fetch_request* request = new win_fetch_request()
	request.promise = promise
	js_runtime_root(rt, promise)
	request.load = win_load_start_fetch(context.executable, address, context.address, c"GET", c"")
	context.requests.push(request)
	free(address)
	return promise

win_fetch_context* win_fetch_new(js_runtime* rt, char* executable, char* address):
	win_fetch_context* context = new win_fetch_context()
	context.runtime = rt
	context.executable = strclone(executable)
	context.address = strclone(address)
	context.requests = new list[win_fetch_request*]
	js_value* callable = js_runtime_host_callable(rt, context, win_fetch_host)
	js_runtime_set(rt, rt.global, c"fetch", callable)
	js_value* window = js_runtime_get(rt, rt.global, c"window")
	if (window.kind == 5): js_runtime_set(rt, window, c"fetch", callable)
	return context

# Returns 1 with a runtime failure still in completion, so the browser can
# record it before a checkpoint replaces completion. A failed settlement keeps
# its promise and loader rooted for retry; completed responses are built once.
int win_fetch_poll(win_fetch_context* context):
	if (context == 0): return 0
	js_runtime* rt = context.runtime
	for i in range(context.requests.length):
		win_fetch_request* request = context.requests[i]
		win_load* load = request.load
		if (load == 0): continue
		if (win_load_poll(load) == 0): continue
		js_runtime_begin(rt, 100000)
		if (load.error != 0): win_fetch_reject(rt, request.promise, load.error)
		else if (request.failure != 0): win_fetch_reject(rt, request.promise, request.failure)
		else if (load.length > 65536 || (request.response == 0 && context.bytes > 4194304 - load.length)): win_fetch_reject(rt, request.promise, c"Fetch response text budget exceeded")
		else if (utf8_validate_bytes(load.source, load.length) == 0): win_fetch_reject(rt, request.promise, c"Fetch response is not UTF-8")
		else:
			if (request.response == 0):
				request.body = win_fetch_string(rt, load.source, load.length)
				if (request.body != rt.undefined_value): js_runtime_root(rt, request.body)
				request.response = js_runtime_alloc(rt, 5)
				if (request.response != rt.undefined_value): js_runtime_root(rt, request.response)
				if (rt.completion.status == 0):
					js_runtime_set(rt, request.response, c"status", js_runtime_number(rt, cast(float64, load.status)))
					js_runtime_set(rt, request.response, c"ok", js_runtime_boolean(rt, load.status >= 200 && load.status < 300))
					js_runtime_set(rt, request.response, c"url", win_fetch_string(rt, load.address, strlen(load.address)))
					js_runtime_set(rt, request.response, c"bodyUsed", js_runtime_boolean(rt, 0))
					js_runtime_set(rt, request.response, c"text", js_runtime_host_callable(rt, request, win_fetch_text))
				if (rt.completion.status != 0):
					if (request.body != rt.undefined_value): js_runtime_unroot(rt, request.body)
					if (request.response != rt.undefined_value): js_runtime_unroot(rt, request.response)
					request.body = 0
					request.response = 0
					request.failure = c"Fetch response allocation failed"
					return 1
				context.bytes = context.bytes + load.length
			js_runtime_promise_settle(rt, request.promise, request.response, 0)
		if (rt.completion.status != 0): return 1
		js_runtime_unroot(rt, request.promise)
		request.promise = 0
		win_load_free(load)
		request.load = 0
	return 0

void win_fetch_stop(win_fetch_context* context):
	if (context == 0): return
	# Mark every request before attempting rejection: a saturated microtask
	# queue must not prevent other worker processes from being killed/reaped.
	for i in range(context.requests.length):
		win_fetch_request* request = context.requests[i]
		if (request.load == 0): continue
		win_load* load = request.load
		if (load.child != 0):
			process_free(load.child)
			load.child = 0
		free(load.error)
		load.error = strclone(c"Fetch aborted")
		load.finished = 1
	win_fetch_poll(context)

void win_fetch_free(win_fetch_context* context):
	if (context == 0): return
	for i in range(context.requests.length):
		win_fetch_request* request = context.requests[i]
		win_load_free(request.load)
		if (request.promise != 0): js_runtime_unroot(context.runtime, request.promise)
		if (request.response != 0): js_runtime_unroot(context.runtime, request.response)
		if (request.body != 0): js_runtime_unroot(context.runtime, request.body)
		free(request)
	__w_list_free(cast(__w_list*, context.requests))
	free(context.executable)
	free(context.address)
	free(context)
