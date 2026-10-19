import lib.assert
import win.script

int main():
	js_runtime* rt = js_runtime_new()
	win_script* script = new win_script()
	script.runtime = rt
	script.timers = new list[win_script_timer*]
	script.clock_injected = 1
	win_script* previous = win_active_script
	win_active_script = script
	list[js_value*] args = new list[js_value*]
	args.push(js_runtime_number(rt, 0.0))
	args.push(win_js_string(rt, c"var owned=1;"))
	args.push(js_runtime_number(rt, 0.0))
	for i in range(args.length): js_runtime_root(rt, args[i])
	js_runtime_root(rt, rt.undefined_value)
	int roots = rt.roots.length
	int values = rt.max_values
	int refused = 0
	int accepted = 0
	for allowance in range(6):
		js_runtime_begin(rt, 10000)
		js_runtime_collect(rt)
		rt.max_values = rt.heap.length + allowance
		int ids = script.timer_id
		js_value* result = win_script_timer_host(rt, args)
		if (rt.completion.status != 0):
			refused = refused + 1
			assert_equal(5, rt.completion.status)
			assert1(result == rt.undefined_value)
			assert_equal(ids, script.timer_id)
			assert_equal(0, script.timers.length)
			assert_equal(0, script.timer_source_bytes)
		else:
			accepted = accepted + 1
			assert_equal(1, script.timers.length)
			assert_equal(12, script.timer_source_bytes)
			assert1(script.timers[0].callback == rt.undefined_value)
			assert_equal(0, script.timers[0].args.length)
			script.timers[0].id = 0
			win_script_collect_timers(script)
			assert_equal(0, script.timer_source_bytes)
		rt.max_values = values
		assert_equal(roots, rt.roots.length)
		assert_equal(0, rt.undefined_value.host)
		assert_equal(0, rt.undefined_value.host_get)
	asserts(c"successful and failed source ownership", accepted > 0 && refused > 0)
	for i in range(args.length): js_runtime_unroot(rt, args[i])
	js_runtime_unroot(rt, rt.undefined_value)
	__w_list_free(cast(__w_list*, args))
	__w_list_free(cast(__w_list*, script.timers))
	js_runtime_free(rt)
	free(script)
	win_active_script = previous
	assert_equal(0, debug_alloc_report_leaks())
	println(c"Timer source allocation refusal, publication and cancellation ownership: OK")
	return 0
