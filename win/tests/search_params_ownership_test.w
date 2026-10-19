# Small native ownership gate: also run with W_DEBUG_ALLOC=1. Avoid parsing a
# large script so the guard allocator can stay within Linux's VMA quota.
import lib.assert
import win.search_params

int main():
	js_runtime* rt = js_runtime_new()
	rt.remaining = 1000000
	rt.running = 1
	win_search_context* context = win_search_new(rt, rt.global)
	list[js_value*] args = new list[js_value*]
	args.push(win_web_string(rt, c"a=1&a=2&nul=%00"))
	js_value* original = win_search_construct(rt, context, rt.undefined_value, args)
	assert_equal(0, rt.completion.status)
	args[0] = original
	js_value* copy = win_search_construct(rt, context, rt.undefined_value, args)
	assert_equal(2, context.states.length)
	assert_equal(16, context.units)
	args[0] = win_web_string(rt, c"a")
	args.push(win_web_string(rt, c"replaced"))
	win_search_method(rt, cast(void*, 5), original, args)
	assert_equal(0, rt.completion.status)
	assert_equal(2, win_search_state_of(original).pairs.length)
	assert_equal(3, win_search_state_of(copy).pairs.length)
	args.pop()
	win_search_method(rt, cast(void*, 6), copy, args)
	assert_equal(1, win_search_state_of(copy).pairs.length)
	# Failed construction must release the valid first pair too.
	js_value* pairs = js_runtime_alloc(rt, 6)
	js_value* pair = js_runtime_alloc(rt, 6)
	js_runtime_array_append(rt, pair, win_web_string(rt, c"ok"))
	js_runtime_array_append(rt, pair, win_web_string(rt, c"value"))
	js_runtime_array_append(rt, pairs, pair)
	js_runtime_array_append(rt, pairs, js_runtime_alloc(rt, 6))
	args[0] = pairs
	int units = context.units
	win_search_construct(rt, context, rt.undefined_value, args)
	assert_equal(2, rt.completion.status)
	assert_equal(2, context.states.length)
	assert_equal(units, context.units)
	rt.completion.status = 0
	rt.completion.value = rt.undefined_value
	__w_list_free(cast(__w_list*, args))
	rt.running = 0
	asserts(c"collect host state", js_runtime_collect(rt) >= 0)
	rt.running = 1
	js_value* serialized = win_search_serialize(win_search_state_of(copy))
	js_text* expected = js_runtime_key(c"nul=%00")
	asserts(c"retained copy", js_text_equal(serialized.text, expected))
	js_text_free(expected)
	win_search_free(context)
	js_runtime_free(rt)
	if (malloc_debug_mode): assert_equal(0, debug_alloc_report_leaks())
	println(c"Win URLSearchParams native ownership and failed-constructor cleanup: OK")
	return 0
