# Bounded same-origin Fetch subset. Network I/O runs in cancellable loaders;
# Promise reactions are drained by the page's normal microtask checkpoint.
import win.loader
import win.abort
import libs.extras.javascript.runtime
import libs.extras.javascript.runtime_json
import libs.extras.javascript.text_codecs

struct win_fetch_request:
	win_abort_state* signal
	win_abort_observer* observer
	win_load* load
	js_value* promise
	js_value* response
	char* bytes
	int length
	int consumed
	int status
	int wasm_mime
	char* failure

# Native response identity and metadata cannot be forged by assigning JS fields.
js_value* win_fetch_response_get(void* runtime, void* context, js_value* receiver, js_text* key):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_fetch_request* request = cast(win_fetch_request*, context)
	if (receiver != request.response): return 0
	if (js_runtime_key_is(key, c"bodyUsed")): return js_runtime_boolean(rt, request.consumed)
	if (js_runtime_key_is(key, c"status")): return js_runtime_number(rt, cast(float64, request.status))
	if (js_runtime_key_is(key, c"ok")): return js_runtime_boolean(rt, request.status >= 200 && request.status < 300)
	return 0

int win_fetch_response_has(void* runtime, void* context, js_value* receiver, js_text* key):
	win_fetch_request* request = cast(win_fetch_request*, context)
	if (receiver != request.response): return 0
	return js_runtime_key_is(key, c"bodyUsed") || js_runtime_key_is(key, c"status") || js_runtime_key_is(key, c"ok")

win_fetch_request* win_fetch_response(js_value* value):
	if (value == 0 || value.host_get != cast(int, win_fetch_response_get)): return 0
	win_fetch_request* request = cast(win_fetch_request*, value.host_context)
	if (request.response != value): return 0
	return request

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

int win_fetch_aborted(win_fetch_request* request):
	return request.signal != 0 && request.signal.aborted

js_value* win_fetch_abort_reject(js_runtime* rt, js_value* promise, win_fetch_request* request):
	js_runtime_promise_settle(rt, promise, request.signal.reason, 1)
	return promise

# No JS work here: every observer must kill/reap its child even when later
# listener execution or Promise settlement exhausts the realm's budgets.
void win_fetch_abort_transport(void* context):
	win_fetch_request* request = cast(win_fetch_request*, context)
	if (request.load == 0): return
	win_load_cancel(request.load)

js_value* win_fetch_text(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_fetch_request* request = cast(win_fetch_request*, context)
	js_value* promise = js_runtime_promise_new(rt)
	if (rt.completion.status != 0): return promise
	if (receiver != request.response): return win_fetch_reject(rt, promise, c"Illegal Response receiver")
	if (request.consumed): return win_fetch_reject(rt, promise, c"Response body already consumed")
	if (win_fetch_aborted(request)): return win_fetch_abort_reject(rt, promise, request)
	if (request.length > 65536): return win_fetch_reject(rt, promise, c"Fetch response text budget exceeded")
	if (utf8_validate_bytes(request.bytes, request.length) == 0): return win_fetch_reject(rt, promise, c"Fetch response is not UTF-8")
	js_value* body = win_fetch_string(rt, request.bytes, request.length)
	if (rt.completion.status != 0): return promise
	request.consumed = 1
	js_runtime_set(rt, receiver, c"bodyUsed", js_runtime_boolean(rt, 1))
	js_runtime_promise_settle(rt, promise, body, 0)
	return promise

# JSON consumes the body even when parsing fails. Decode uses the same forgiving
# UTF-8/BOM algorithm as TextDecoder; parsing never evaluates source code.
js_value* win_fetch_json(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_fetch_request* request = cast(win_fetch_request*, context)
	js_value* promise = js_runtime_promise_new(rt)
	if (rt.completion.status != 0): return promise
	if (receiver != request.response): return win_fetch_reject(rt, promise, c"Illegal Response receiver")
	if (request.consumed): return win_fetch_reject(rt, promise, c"Response body already consumed")
	if (win_fetch_aborted(request)): return win_fetch_abort_reject(rt, promise, request)
	request.consumed = 1
	if (request.length > 65536): return win_fetch_reject(rt, promise, c"Fetch response JSON budget exceeded")
	js_value* decoder = js_runtime_alloc(rt, 5)
	if (rt.completion.status != 0): return promise
	decoder.text_codec = 2
	list[js_value*] decode_args = new list[js_value*]
	decode_args.push(js_runtime_array_buffer_copy(rt, cast(byte*, request.bytes), request.length))
	js_value* text = rt.undefined_value
	if (rt.completion.status == 0): text = js_text_codec_decode(rt, 0, decoder, decode_args)
	__w_list_free(cast(__w_list*, decode_args))
	js_value* value = rt.undefined_value
	if (rt.completion.status == 0): value = js_runtime_json_parse(rt, text.text)
	if (rt.completion.status == 5): return promise
	int rejected = rt.completion.status != 0
	if (rejected):
		value = rt.completion.value
		rt.completion.status = 0
		rt.completion.value = rt.undefined_value
	js_runtime_promise_settle(rt, promise, value, rejected)
	return promise

js_value* win_fetch_array_buffer(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_fetch_request* request = cast(win_fetch_request*, context)
	js_value* promise = js_runtime_promise_new(rt)
	if (rt.completion.status != 0): return promise
	if (receiver != request.response): return win_fetch_reject(rt, promise, c"Illegal Response receiver")
	if (request.consumed): return win_fetch_reject(rt, promise, c"Response body already consumed")
	if (win_fetch_aborted(request)): return win_fetch_abort_reject(rt, promise, request)
	js_value* buffer = js_runtime_array_buffer_copy(rt, cast(byte*, request.bytes), request.length)
	if (rt.completion.status != 0): return promise
	request.consumed = 1
	js_runtime_set(rt, receiver, c"bodyUsed", js_runtime_boolean(rt, 1))
	js_runtime_promise_settle(rt, promise, buffer, 0)
	return promise

int win_fetch_pending(win_fetch_context* context):
	if (context == 0): return 0
	int count = 0
	for i in range(context.requests.length):
		if (context.requests[i].load != 0): count = count + 1
	return count

struct win_fetch_init:
	char* method
	char* body
	int length
	char* content_type
	char* accept
	win_abort_state* signal
	char* error

void win_fetch_init_free(win_fetch_init* init):
	free(init.method)
	free(init.body)
	free(init.content_type)
	free(init.accept)

char* win_fetch_option_string(js_runtime* rt, js_value* value):
	if (value.kind != 4): return 0
	int length = 0
	char* text = js_text_to_utf8(value.text, &length)
	if (text != 0 && strlen(text) != length):
		free(text)
		return 0
	return text

void win_fetch_parse_init(js_runtime* rt, js_value* options, win_fetch_init* init):
	init.length = 0
	init.signal = 0
	init.error = 0
	init.method = strclone(c"GET")
	init.content_type = strclone(c"")
	init.accept = strclone(c"*/*")
	init.body = strclone(c"")
	if (options.kind == 0 || options.kind == 1): return
	if (js_runtime_object(options) == 0):
		init.error = c"Fetch options require an object"
		return
	for i in range(options.properties.length):
		js_text* key = options.properties[i].key
		if (js_runtime_key_is(key, c"method") || js_runtime_key_is(key, c"body") || js_runtime_key_is(key, c"headers") || js_runtime_key_is(key, c"signal")): continue
		init.error = c"Fetch option outside subset"
		return
	js_value* method = js_runtime_get(rt, options, c"method")
	if (method.kind != 0):
		char* text = win_fetch_option_string(rt, method)
		if (text == 0 || win_fetch_method(text) == 0):
			free(text)
			init.error = c"Invalid or forbidden Fetch method"
			return
		# Fetch normalizes these six methods; extension tokens retain their case.
		if (win_net_equal(text, c"DELETE") || win_net_equal(text, c"GET") || win_net_equal(text, c"HEAD") || win_net_equal(text, c"OPTIONS") || win_net_equal(text, c"POST") || win_net_equal(text, c"PUT")):
			for i in range(strlen(text)):
				if (text[i] >= 'a' && text[i] <= 'z'): text[i] = text[i] - 32
		free(init.method)
		init.method = text
	js_value* body = js_runtime_get(rt, options, c"body")
	if (body.kind != 0 && body.kind != 1):
		if (strcmp(init.method, c"GET") == 0 || strcmp(init.method, c"HEAD") == 0):
			init.error = c"GET and HEAD cannot have a Fetch body"
			return
		if (body.kind == 4):
			free(init.body)
			init.body = win_web_usv_bytes(body.text, &init.length)
			free(init.content_type)
			init.content_type = strclone(c"text/plain;charset=UTF-8")
		else if (body.binary_kind != 0):
			byte* bytes = js_runtime_binary_data(rt, body)
			init.length = js_runtime_binary_byte_length(rt, body)
			if (rt.completion.status != 0): return
			if (init.length > WIN_FETCH_REQUEST_LIMIT):
				init.error = c"Fetch request body exceeds 64 KiB"
				return
			free(init.body)
			init.body = cast(char*, malloc(init.length + 1))
			for i in range(init.length): init.body[i] = cast(char, bytes[i])
			init.body[init.length] = 0
		else:
			init.error = c"Fetch body requires string or BufferSource"
			return
		if (init.length > WIN_FETCH_REQUEST_LIMIT):
			init.error = c"Fetch request body exceeds 64 KiB"
			return
	js_value* headers = js_runtime_get(rt, options, c"headers")
	if (headers.kind != 0):
		if (headers.kind != 5 || headers.binary_kind != 0 || headers.promise_state != 0 || headers.properties.length > 2):
			init.error = c"Fetch headers require a plain record"
			return
		int types = 0
		int accepts = 0
		for i in range(headers.properties.length):
			js_value* property = headers.properties[i]
			if (property.enumerable == 0): continue
			if (property.accessor):
				init.error = c"Fetch header accessors outside subset"
				return
			int length = 0
			char* key = js_text_to_utf8(property.key, &length)
			int is_type = strlen(key) == length && win_net_equal(key, c"Content-Type")
			int is_accept = strlen(key) == length && win_net_equal(key, c"Accept")
			free(key)
			if (is_type == 0 && is_accept == 0):
				init.error = c"Fetch header outside Content-Type/Accept subset"
				return
			js_value* value = js_runtime_member_read(rt, headers, property.key)
			char* text = win_fetch_option_string(rt, value)
			if (text == 0 || win_fetch_header_value(text, strlen(text)) == 0):
				free(text)
				init.error = c"Invalid Fetch header value"
				return
			if ((is_type && types) || (is_accept && accepts)):
				free(text)
				init.error = c"Duplicate Fetch header names outside subset"
				return
			if (is_type):
				free(init.content_type)
				init.content_type = text
				types = 1
			else:
				free(init.accept)
				init.accept = text
				accepts = 1
	js_value* signal = js_runtime_get(rt, options, c"signal")
	if (signal.kind != 0 && signal.kind != 1):
		init.signal = win_abort_signal(signal)
		if (init.signal == 0): init.error = c"Fetch signal requires AbortSignal"

js_value* win_fetch_host(void* runtime, void* host, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_fetch_context* context = cast(win_fetch_context*, host)
	js_value* promise = js_runtime_promise_new(rt)
	if (rt.completion.status != 0): return promise
	if (args.length == 0 || args[0].kind != 4): return win_fetch_reject(rt, promise, c"fetch requires a URL string")
	win_fetch_init init
	js_value* options = rt.undefined_value
	if (args.length > 1): options = args[1]
	win_fetch_parse_init(rt, options, &init)
	if (rt.completion.status != 0):
		win_fetch_init_free(&init)
		if (rt.completion.status == 5): return promise
		js_value* error = rt.completion.value
		rt.completion.status = 0
		rt.completion.value = rt.undefined_value
		rt.completion.message = c""
		js_runtime_promise_settle(rt, promise, error, 1)
		return promise
	if (init.error != 0):
		win_fetch_init_free(&init)
		return win_fetch_reject(rt, promise, init.error)
	if (context.requests.length >= 64 || win_fetch_pending(context) >= 3):
		win_fetch_init_free(&init)
		return win_fetch_reject(rt, promise, c"Page fetch request limit")
	int length = 0
	char* reference = js_text_to_utf8(args[0].text, &length)
	if (reference == 0):
		win_fetch_init_free(&init)
		return win_fetch_reject(rt, promise, c"Invalid fetch URL")
	char* address = 0
	if (strlen(reference) == length): address = win_resolve(context.address, reference)
	free(reference)
	if (address == 0):
		win_fetch_init_free(&init)
		return win_fetch_reject(rt, promise, c"Invalid fetch URL")
	if (win_fetch_same_origin(context.address, address) == 0):
		free(address)
		win_fetch_init_free(&init)
		return win_fetch_reject(rt, promise, c"Fetch requires a same-origin HTTP(S) URL")
	if (init.signal != 0 && init.signal.aborted):
		js_runtime_promise_settle(rt, promise, init.signal.reason, 1)
		free(address)
		win_fetch_init_free(&init)
		return promise
	win_fetch_request* request = new win_fetch_request()
	request.promise = promise
	request.signal = init.signal
	request.observer = win_abort_observe(init.signal, request, win_fetch_abort_transport)
	js_runtime_root(rt, promise)
	request.load = win_load_start_fetch_bytes(context.executable, address, context.address, init.method, init.body, init.length, init.content_type, init.accept)
	win_fetch_init_free(&init)
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
		# Resolution may call a user-defined then getter. Enter a bounded host
		# scope when idle; nested callers retain their existing execution budget.
		int was_running = rt.running
		if (was_running == 0): js_runtime_begin(rt, 100000)
		else if (rt.completion.status != 0): return 1
		rt.running = 1
		if (win_fetch_aborted(request)): win_fetch_abort_reject(rt, request.promise, request)
		else if (load.error != 0): win_fetch_reject(rt, request.promise, load.error)
		else if (request.failure != 0): win_fetch_reject(rt, request.promise, request.failure)
		else if (load.length > WIN_FETCH_LIMIT || (request.response == 0 && context.bytes > 4194304 - load.length)): win_fetch_reject(rt, request.promise, c"Fetch response byte budget exceeded")
		else:
			if (request.response == 0):
				request.response = js_runtime_alloc(rt, 5)
				if (request.response != rt.undefined_value): js_runtime_root(rt, request.response)
				if (rt.completion.status == 0):
					request.status = load.status
					request.wasm_mime = load.wasm_mime
					js_runtime_set_host_hooks(rt, request.response, request, win_fetch_response_get, 0)
					js_runtime_set_host_has(rt, request.response, win_fetch_response_has)
					js_runtime_set(rt, request.response, c"status", js_runtime_number(rt, cast(float64, load.status)))
					js_runtime_set(rt, request.response, c"ok", js_runtime_boolean(rt, load.status >= 200 && load.status < 300))
					js_runtime_set(rt, request.response, c"url", win_fetch_string(rt, load.address, strlen(load.address)))
					js_runtime_set(rt, request.response, c"bodyUsed", js_runtime_boolean(rt, 0))
					js_runtime_set(rt, request.response, c"text", js_runtime_host_callable(rt, request, win_fetch_text))
					js_runtime_set(rt, request.response, c"json", js_runtime_host_callable(rt, request, win_fetch_json))
					js_runtime_set(rt, request.response, c"arrayBuffer", js_runtime_host_callable(rt, request, win_fetch_array_buffer))
				if (rt.completion.status != 0):
					if (request.response != rt.undefined_value): js_runtime_unroot(rt, request.response)
					request.response = 0
					request.failure = c"Fetch response allocation failed"
					rt.running = was_running
					return 1
				request.bytes = cast(char*, malloc(load.length + 1))
				for j in range(load.length): request.bytes[j] = load.source[j]
				request.bytes[load.length] = 0
				request.length = load.length
				context.bytes = context.bytes + load.length
			js_runtime_promise_settle(rt, request.promise, request.response, 0)
		rt.running = was_running
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
		win_load_cancel(load)
		free(load.error)
		load.error = strclone(c"Fetch aborted")
	win_fetch_poll(context)

void win_fetch_free(win_fetch_context* context):
	if (context == 0): return
	for i in range(context.requests.length):
		win_fetch_request* request = context.requests[i]
		win_abort_unobserve(request.signal, request.observer)
		win_load_free(request.load)
		if (request.promise != 0): js_runtime_unroot(context.runtime, request.promise)
		if (request.response != 0): js_runtime_unroot(context.runtime, request.response)
		free(request.bytes)
		free(request)
	__w_list_free(cast(__w_list*, context.requests))
	free(context.executable)
	free(context.address)
	free(context)
