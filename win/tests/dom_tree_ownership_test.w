import lib.assert
import win.script

js_value* tree_setter(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	int* calls = cast(int*, context)
	calls[0] = calls[0] + 1
	js_runtime* rt = cast(js_runtime*, runtime)
	return rt.undefined_value

void tree_sentinel(js_runtime* rt, int roots):
	assert_equal(roots, rt.roots.length)
	assert_equal(0, rt.undefined_value.host_get)
	assert_equal(0, rt.undefined_value.host_has)
	assert_equal(0, cast(int, rt.undefined_value.host_context))
	int found = 0
	for i in range(rt.roots.length):
		if (rt.roots[i] == rt.undefined_value): found = 1
	assert_equal(1, found)

int main():
	js_runtime* rt = js_runtime_new()
	win_script* script = new win_script()
	script.runtime = rt
	char* source = c"<?T data?><body></body>"
	win_page* page = win_page_parse(source, strlen(source))
	script.page = page
	win_dom_binding* binding = new win_dom_binding()
	binding.child_nodes = 0
	binding.object = 0
	binding.context = script
	binding.node = page.html.root.first_child
	assert_equal(HTML_PROCESSING_INSTRUCTION, binding.node.kind)
	js_runtime_root(rt, rt.undefined_value)
	int roots = rt.roots.length
	js_text* data = js_runtime_key(c"data")
	for i in range(100):
		js_runtime_begin(rt, 100000)
		js_value* value = win_dom_tree_get(binding, data)
		assert_equal(4, value.kind)
		assert_equal(4, value.text.units.length)
		js_runtime_collect(rt)
	int values = rt.max_values
	int properties = rt.max_properties
	# Both successful and refused reads release their temporary UTF-16 buffer.
	for i in range(5):
		js_runtime_begin(rt, 100000)
		rt.max_values = rt.heap.length
		assert1(win_dom_tree_get(binding, data) == rt.undefined_value)
		assert_equal(5, rt.completion.status)
		tree_sentinel(rt, roots)
		rt.max_values = values
	js_text_free(data)
	js_runtime_begin(rt, 100000)
	int calls = 0
	js_text* item = js_runtime_key(c"item")
	js_runtime_define_accessor(rt, rt.object_prototype, item, 0, js_runtime_host_callable(rt, &calls, tree_setter), 0, 1)
	js_text_free(item)
	js_text* children = js_runtime_key(c"childNodes")
	int refused = 0
	for allowance in range(12):
		js_runtime_begin(rt, 100000)
		js_runtime_collect(rt)
		rt.max_values = rt.heap.length + allowance
		js_value* result = win_dom_tree_get(binding, children)
		if (rt.completion.status != 0):
			refused = refused + 1
			assert_equal(5, rt.completion.status)
			assert1(result == rt.undefined_value)
			assert_equal(0, cast(int, binding.child_nodes))
		else:
			assert1(result == binding.child_nodes && result != rt.undefined_value)
			rt.max_values = values
			asserts(c"complete item method", js_runtime_callable(js_runtime_get(rt, result, c"item")))
			assert1(win_dom_tree_get(binding, children) == result)
			js_runtime_unroot(rt, result)
			binding.child_nodes = 0
		rt.max_values = values
		tree_sentinel(rt, roots)
	for cap in range(4):
		js_runtime_begin(rt, 100000)
		rt.max_properties = cap
		win_dom_tree_get(binding, children)
		if (rt.completion.status != 0):
			refused = refused + 1
			assert_equal(0, cast(int, binding.child_nodes))
		else:
			js_runtime_unroot(rt, binding.child_nodes)
			binding.child_nodes = 0
		tree_sentinel(rt, roots)
		rt.max_properties = properties
	asserts(c"allocation refusals covered", refused >= 3)
	assert_equal(0, calls)
	js_runtime_begin(rt, 100000)
	js_value* result = win_dom_tree_get(binding, children)
	assert1(result == binding.child_nodes && result != rt.undefined_value)
	assert_equal(roots + 1, rt.roots.length)
	js_runtime_unroot(rt, result)
	js_text_free(children)
	js_runtime_unroot(rt, rt.undefined_value)
	js_runtime_free(rt)
	win_page_free(page)
	free(binding)
	free(script)
	assert_equal(0, debug_alloc_report_leaks())
	println(c"Native DOM getter buffers and transactional childNodes ownership: OK")
	return 0
