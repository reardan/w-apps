# Hermetic fetch/realm/lifecycle regressions. Completed loaders model transport
# results without network timing; cancellation uses a real sleeping child.
# All failure regressions run by default. Optional fourth arguments select
# individual cases: --saturation, --heap, --browser-errors, --resume,
# --stop-saturation.
import lib.assert
import lib.args
import win.app

void fetch_eval(win_script* script, char* source):
	asserts(c"fetch test JavaScript succeeds", win_script_eval(script, source, strlen(source)))

win_script* fetch_script():
	char* source = c"<title>initial</title><p>fetch</p>"
	return win_script_new(win_page_parse(source, strlen(source)))

void fetch_destroy(win_script* script, win_fetch_context* context):
	win_page* page = script.page
	win_fetch_free(context)
	win_script_free(script)
	win_page_free(page)

win_fetch_request* fetch_result(win_fetch_context* context, char* body, int length, int status):
	win_fetch_request* request = new win_fetch_request()
	request.promise = js_runtime_promise_new(context.runtime)
	js_runtime_root(context.runtime, request.promise)
	request.load = new win_load()
	request.load.output = string_new()
	string_append_bytes(request.load.output, body, length)
	request.load.source = request.load.output.data
	request.load.length = length
	request.load.status = status
	request.load.address = strclone(c"https://example.test/data")
	request.load.finished = 1
	context.requests.push(request)
	return request

void fetch_expose(win_script* script, win_fetch_request* request):
	js_runtime_set(script.runtime, script.runtime.global, c"result", request.promise)

int fetch_rooted(js_runtime* rt, js_value* value):
	for i in range(rt.roots.length):
		if (rt.roots[i] == value): return 1
	return 0

void test_fetch_origins_and_arguments():
	asserts(c"origin normalizes case and default port", win_fetch_same_origin(c"HTTPS://EXAMPLE.test/a", c"https://example.test:443/b#c"))
	asserts(c"IPv6 normalization", win_fetch_same_origin(c"http://[::1]/", c"http://[0:0:0:0:0:0:0:1]:80/x"))
	asserts(c"scheme boundary", win_fetch_same_origin(c"https://example.test/", c"http://example.test:443/") == 0)
	asserts(c"port boundary", win_fetch_same_origin(c"https://example.test/", c"https://example.test:444/") == 0)
	asserts(c"host boundary", win_fetch_same_origin(c"https://example.test/", c"https://other.test/") == 0)
	asserts(c"userinfo rejected", win_fetch_same_origin(c"https://example.test/", c"https://example.test@other.test/") == 0)
	asserts(c"local files have no fetch origin", win_fetch_same_origin(c"/tmp/a", c"/tmp/b") == 0)
	win_script* script = fetch_script()
	win_fetch_context* context = win_fetch_new(script.runtime, c"/missing-win-fetch-executable", c"https://example.test/page")
	fetch_eval(script, c"let rejected=0; fetch().catch(function(){rejected++;}); fetch(3).catch(function(){rejected++;}); fetch('/data',{}).catch(function(){rejected++;}); fetch('https://other.test/x').catch(function(){rejected++;}); fetch('/x\\u0000y').catch(function(){rejected++;});")
	assert_equal(0, context.requests.length)
	win_script_checkpoint(script)
	fetch_eval(script, c"if(rejected!==5) throw 'argument/origin rejections';")
	fetch_destroy(script, context)

void test_fetch_rooting_and_response():
	win_script* script = fetch_script()
	win_fetch_context* context = win_fetch_new(script.runtime, c"unused", c"https://example.test/")
	int roots = script.runtime.roots.length
	win_fetch_request* request = fetch_result(context, c"payload", 7, 404)
	js_value* promise = request.promise
	asserts(c"pending request rooted", fetch_rooted(script.runtime, promise))
	fetch_expose(script, request)
	fetch_eval(script, c"result.then(function(r){if(r.status!==404||r.ok||r.bodyUsed) throw 'metadata'; document.title='response';}); result=null;")
	js_runtime_collect(script.runtime)
	assert_equal(1, win_fetch_pending(context))
	win_fetch_poll(context)
	assert_equal(0, win_fetch_pending(context))
	asserts(c"transport promise root released after settlement", fetch_rooted(script.runtime, promise) == 0)
	asserts(c"response and body retained for native callback", fetch_rooted(script.runtime, request.response) && fetch_rooted(script.runtime, request.body))
	js_runtime_collect(script.runtime)
	win_script_checkpoint(script)
	assert_strings_equal(c"response", script.page.title)
	js_runtime_set(script.runtime, script.runtime.global, c"response", request.response)
	fetch_eval(script, c"let receiverRejected=false; const read=response.text; read().catch(function(){receiverRejected=true;});")
	win_script_checkpoint(script)
	fetch_eval(script, c"if(!receiverRejected||response.bodyUsed) throw 'receiver check consumed body'; response.text().then(function(t){if(t!=='payload') throw 'body';document.title=t;}); response.text().catch(function(){document.title=document.title+'-once';}); if(!response.bodyUsed) throw 'bodyUsed';")
	js_runtime_collect(script.runtime)
	win_script_checkpoint(script)
	assert_strings_equal(c"payload-once", script.page.title)
	win_fetch_free(context)
	assert_equal(roots, script.runtime.roots.length)
	win_page* page = script.page
	win_script_free(script)
	win_page_free(page)

void test_fetch_budgets():
	win_script* script = fetch_script()
	win_fetch_context* context = win_fetch_new(script.runtime, c"unused", c"https://example.test/")
	string_builder* text = string_new()
	for i in range(65537): string_append_char(text, 'x')
	win_fetch_request* exact = fetch_result(context, text.data, 65536, 200)
	js_value* exact_promise = exact.promise
	js_runtime_set(script.runtime, script.runtime.global, c"exact", exact_promise)
	win_fetch_poll(context)
	assert_equal(2, exact_promise.promise_state)
	assert_equal(65536, context.bytes)
	assert_equal(65536, exact.body.text.units.length)
	win_fetch_request* large = fetch_result(context, text.data, 65537, 200)
	js_value* large_promise = large.promise
	js_runtime_set(script.runtime, script.runtime.global, c"large", large_promise)
	win_fetch_poll(context)
	assert_equal(3, large_promise.promise_state)
	assert_equal(65536, context.bytes)
	char[1] invalid
	invalid[0] = cast(char, 255)
	win_fetch_request* bad = fetch_result(context, &invalid[0], 1, 200)
	js_value* bad_promise = bad.promise
	js_runtime_set(script.runtime, script.runtime.global, c"bad", bad_promise)
	win_fetch_poll(context)
	assert_equal(3, bad_promise.promise_state)
	assert_equal(65536, context.bytes)
	context.bytes = 4194303
	win_fetch_request* last = fetch_result(context, c"x", 1, 200)
	js_value* last_promise = last.promise
	js_runtime_set(script.runtime, script.runtime.global, c"last", last_promise)
	win_fetch_poll(context)
	assert_equal(2, last_promise.promise_state)
	assert_equal(4194304, context.bytes)
	win_fetch_request* over = fetch_result(context, c"x", 1, 200)
	js_value* over_promise = over.promise
	js_runtime_set(script.runtime, script.runtime.global, c"over", over_promise)
	win_fetch_poll(context)
	assert_equal(3, over_promise.promise_state)
	assert_equal(4194304, context.bytes)
	string_free(text)
	fetch_destroy(script, context)

void test_fetch_request_limits():
	win_script* script = fetch_script()
	win_fetch_context* context = win_fetch_new(script.runtime, c"unused", c"https://example.test/")
	for i in range(3): fetch_result(context, c"x", 1, 200)
	fetch_eval(script, c"let limited=false;fetch('/x').catch(function(){limited=true;});")
	assert_equal(3, context.requests.length)
	win_script_checkpoint(script)
	fetch_eval(script, c"if(!limited) throw 'pending cap';")
	win_fetch_poll(context)
	for i in range(61): fetch_result(context, c"x", 1, 200)
	win_fetch_poll(context)
	assert_equal(64, context.requests.length)
	assert_equal(0, win_fetch_pending(context))
	fetch_eval(script, c"limited=false;fetch('/x').catch(function(){limited=true;});")
	win_script_checkpoint(script)
	fetch_eval(script, c"if(!limited) throw 'lifetime cap';")
	assert_equal(64, context.requests.length)
	fetch_destroy(script, context)

int fetch_sleeping_child(win_fetch_request* request):
	request.load.finished = 0
	request.load.started = time_monotonic_ms()
	spawn_options* options = spawn_options_new()
	options.new_group = 1
	options.stdin_mode = process_null
	options.stdout_mode = process_pipe
	char*[3] argv
	argv[0] = c"/bin/sleep"
	argv[1] = c"30"
	argv[2] = 0
	request.load.child = process_spawn(argv[0], &argv[0], options)
	free(options)
	asserts(c"cancellation fixture starts child", request.load.child != 0)
	assert_equal(process_status_running, process_try_wait(request.load.child))
	return request.load.child.pid

void fetch_assert_reaped(int pid):
	# kill(pid, 0) must report ESRCH once process_free has killed and reaped it.
	assert_equal(-3, kill(pid, 0))

void test_fetch_stop():
	win_script* script = fetch_script()
	win_fetch_context* context = win_fetch_new(script.runtime, c"unused", c"https://example.test/")
	win_fetch_request* request = fetch_result(context, c"", 0, 200)
	int pid = fetch_sleeping_child(request)
	fetch_expose(script, request)
	fetch_eval(script, c"let aborted=0;result.catch(function(){aborted++;});")
	js_runtime_collect(script.runtime)
	win_fetch_stop(context)
	fetch_assert_reaped(pid)
	assert_equal(0, win_fetch_pending(context))
	win_fetch_stop(context)
	win_script_checkpoint(script)
	fetch_eval(script, c"if(aborted!==1) throw 'abort settlement';")
	assert_equal(1, context.requests.length)
	fetch_destroy(script, context)

void test_fetch_browser_lifecycle(char* executable, char* home):
	win_browser browser
	win_browser_init(&browser, executable, home)
	browser.script = fetch_script()
	browser.page = browser.script.page
	browser.fetches = win_fetch_new(browser.script.runtime, executable, c"https://example.test/")
	win_fetch_request* request = fetch_result(browser.fetches, c"", 0, 200)
	int pid = fetch_sleeping_child(request)
	asserts(c"pending fetch keeps browser loading", win_browser_loading(&browser))
	win_stop(&browser)
	fetch_assert_reaped(pid)
	asserts(c"stop makes browser idle", win_browser_loading(&browser) == 0)
	win_browser_free(&browser)
	win_app app
	win_app_init(&app, executable, home)
	for i in range(2):
		win_browser* tab = new win_browser()
		win_browser_init(tab, executable, home)
		tab.script = fetch_script()
		tab.page = tab.script.page
		tab.fetches = win_fetch_new(tab.script.runtime, executable, c"https://example.test/")
		app.tabs.push(tab)
	request = fetch_result(app.tabs[0].fetches, c"", 0, 200)
	pid = fetch_sleeping_child(request)
	win_app_close(&app, 0)
	fetch_assert_reaped(pid)
	assert_equal(1, app.tabs.length)
	assert_equal(0, app.tabs[0].fetches.requests.length)
	request = fetch_result(app.tabs[0].fetches, c"", 0, 200)
	pid = fetch_sleeping_child(request)
	win_navigate(app.tabs[0], home, c"", -1)
	fetch_assert_reaped(pid)
	assert_equal(0, win_fetch_pending(app.tabs[0].fetches))
	win_app_free(&app)

void test_fetch_saturated_settlement():
	win_script* script = fetch_script()
	win_fetch_context* context = win_fetch_new(script.runtime, c"unused", c"https://example.test/")
	win_fetch_request* request = fetch_result(context, c"x", 1, 200)
	fetch_expose(script, request)
	js_value* promise = request.promise
	fetch_eval(script, c"result.then(function(){document.title='settled';});")
	script.runtime.max_microtasks = 0
	win_fetch_poll(context)
	# A failed settlement must remain owned for retry or be rejected, never
	# become an unowned pending promise with no transport left to poll.
	asserts(c"failed settlement retains pending ownership or settles", promise.promise_state != 1 || request.promise == promise && fetch_rooted(script.runtime, promise))
	script.runtime.max_microtasks = 10000
	win_fetch_poll(context)
	win_script_checkpoint(script)
	assert_strings_equal(c"settled", script.page.title)
	assert_equal(1, context.bytes)
	fetch_destroy(script, context)

void test_fetch_heap_failure():
	win_script* script = fetch_script()
	win_fetch_context* context = win_fetch_new(script.runtime, c"unused", c"https://example.test/")
	win_fetch_request* request = fetch_result(context, c"x", 1, 200)
	fetch_expose(script, request)
	js_value* promise = request.promise
	int maximum = script.runtime.max_values
	script.runtime.max_values = script.runtime.heap.length
	win_fetch_poll(context)
	asserts(c"allocation failure cannot fulfill with undefined response", promise.promise_state != 2 || promise.promise_result != script.runtime.undefined_value)
	asserts(c"allocation failure retains ownership or rejects", promise.promise_state == 3 || request.promise == promise && fetch_rooted(script.runtime, promise))
	script.runtime.max_values = maximum
	assert_equal(0, win_fetch_poll(context))
	assert_equal(3, promise.promise_state)
	assert_equal(0, win_fetch_pending(context))
	assert_equal(0, context.bytes)
	asserts(c"recovered allocation rejection releases root", fetch_rooted(script.runtime, promise) == 0)
	fetch_destroy(script, context)

void test_fetch_admission_heap_failure():
	win_script* script = fetch_script()
	js_runtime* rt = script.runtime
	win_fetch_context* context = win_fetch_new(rt, c"/missing-win-fetch-executable", c"https://example.test/")
	list[js_value*] arguments = new list[js_value*]
	arguments.push(win_fetch_string(rt, c"/data", 5))
	int maximum = rt.max_values
	int roots = rt.roots.length
	rt.max_values = rt.heap.length
	js_runtime_begin(rt, 100000)
	js_value* promise = win_fetch_host(rt, context, rt.global, arguments)
	asserts(c"admission reports failed Promise allocation", promise == rt.undefined_value && rt.completion.status == 5)
	assert_equal(0, context.requests.length)
	assert_equal(0, win_fetch_pending(context))
	assert_equal(roots, rt.roots.length)
	rt.max_values = maximum
	js_runtime_begin(rt, 100000)
	__w_list_free(cast(__w_list*, arguments))
	win_fetch_request* request = fetch_result(context, c"body", 4, 200)
	assert_equal(0, win_fetch_poll(context))
	arguments = new list[js_value*]
	roots = rt.roots.length
	rt.max_values = rt.heap.length
	js_runtime_begin(rt, 100000)
	promise = win_fetch_text(rt, request, request.response, arguments)
	asserts(c"text reports failed Promise allocation", promise == rt.undefined_value && rt.completion.status == 5)
	assert_equal(0, request.consumed)
	assert_equal(roots, rt.roots.length)
	rt.max_values = maximum
	js_runtime_begin(rt, 100000)
	asserts(c"failed text allocation leaves bodyUsed false", js_runtime_get(rt, request.response, c"bodyUsed").number == 0.0)
	promise = win_fetch_text(rt, request, request.response, arguments)
	assert_equal(2, promise.promise_state)
	asserts(c"body remains readable after allocation recovery", promise.promise_result == request.body)
	assert_equal(1, request.consumed)
	__w_list_free(cast(__w_list*, arguments))
	fetch_destroy(script, context)

void test_fetch_browser_error_reporting(char* executable, char* home):
	win_browser browser
	win_browser_init(&browser, executable, home)
	browser.script = fetch_script()
	browser.page = browser.script.page
	browser.script.ready = 1
	browser.fetches = win_fetch_new(browser.script.runtime, executable, c"https://example.test/")
	win_fetch_request* request = fetch_result(browser.fetches, c"x", 1, 200)
	fetch_expose(browser.script, request)
	fetch_eval(browser.script, c"result.then(function(){document.title='settled';});")
	browser.script.runtime.max_microtasks = 0
	win_browser_poll(&browser)
	asserts(c"fetch runtime failure is reported before checkpoint clears it", browser.script.failures > 0)
	win_browser_free(&browser)

void test_fetch_after_stop():
	win_script* script = fetch_script()
	win_fetch_context* context = win_fetch_new(script.runtime, c"unused", c"https://example.test/")
	win_fetch_stop(context)
	# Cache makes admission and completion hermetic without a live server.
	win_cache_clear()
	win_cache_store(c"https://example.test/resume", c"fetch", c"resumed", 7, time_now() + 60)
	fetch_eval(script, c"fetch('/resume').then(function(r){return r.text();}).then(function(t){document.title=t;});")
	assert_equal(1, context.requests.length)
	win_fetch_poll(context)
	win_script_checkpoint(script)
	assert_strings_equal(c"resumed", script.page.title)
	win_cache_clear()
	fetch_destroy(script, context)

void test_fetch_stop_saturation():
	win_script* script = fetch_script()
	win_fetch_context* context = win_fetch_new(script.runtime, c"unused", c"https://example.test/")
	win_fetch_request* request = fetch_result(context, c"", 0, 200)
	int pid = fetch_sleeping_child(request)
	fetch_expose(script, request)
	js_value* promise = request.promise
	fetch_eval(script, c"result.catch(function(){document.title='aborted';});")
	script.runtime.max_microtasks = 0
	win_fetch_stop(context)
	fetch_assert_reaped(pid)
	asserts(c"stop must not lose failed rejection ownership", promise.promise_state != 1 || request.promise == promise && fetch_rooted(script.runtime, promise))
	script.runtime.max_microtasks = 10000
	win_fetch_poll(context)
	win_script_checkpoint(script)
	assert_strings_equal(c"aborted", script.page.title)
	fetch_destroy(script, context)

int main(int argc, int argv):
	args_init(argc, argv)
	asserts(c"pass browser executable and fixture", argc >= 3)
	if (argc > 3 && strcmp(args_get(3), c"--saturation") == 0):
		test_fetch_saturated_settlement()
		return 0
	if (argc > 3 && strcmp(args_get(3), c"--heap") == 0):
		test_fetch_heap_failure()
		return 0
	if (argc > 3 && strcmp(args_get(3), c"--browser-errors") == 0):
		test_fetch_browser_error_reporting(args_get(1), args_get(2))
		return 0
	if (argc > 3 && strcmp(args_get(3), c"--resume") == 0):
		test_fetch_after_stop()
		return 0
	if (argc > 3 && strcmp(args_get(3), c"--stop-saturation") == 0):
		test_fetch_stop_saturation()
		return 0
	test_fetch_saturated_settlement()
	test_fetch_heap_failure()
	test_fetch_admission_heap_failure()
	test_fetch_browser_error_reporting(args_get(1), args_get(2))
	test_fetch_after_stop()
	test_fetch_stop_saturation()
	test_fetch_origins_and_arguments()
	test_fetch_rooting_and_response()
	test_fetch_budgets()
	test_fetch_request_limits()
	test_fetch_stop()
	test_fetch_browser_lifecycle(args_get(1), args_get(2))
	println(c"Win fetch origin, budgets, roots, cancellation, lifecycle and allocation recovery: OK")
	return 0
