# Native asynchronous WPT execution seam. No assertion replacement.
import lib.args
import lib.file
import lib.time
import structures.json
import win.script

char* wpt_payload = 0
int wpt_completions = 0

js_value* wpt_complete(void* context, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, context)
	wpt_completions = wpt_completions + 1
	if (args.length != 1 || args[0].kind != 4):
		js_runtime_fail(rt, 6, c"invalid WPT completion payload")
		return rt.undefined_value
	int length = 0
	if (wpt_payload == 0):
		wpt_payload = js_text_to_utf8(args[0].text, &length)
		if (length > 1048576 || strlen(wpt_payload) != length):
			free(wpt_payload)
			wpt_payload = 0
			js_runtime_fail(rt, 6, c"invalid WPT completion bytes or size")
	return rt.undefined_value

void wpt_unsupported_node(json_value* messages, js_node* node):
	if (node == 0 || js_runtime_supported(node)): return
	int failed_child = 0
	for i in range(node.children.length):
		if (js_runtime_supported(node.children[i]) == 0):
			failed_child = 1
			wpt_unsupported_node(messages, node.children[i])
	if (failed_child == 0):
		json_value* diagnostic = json_object()
		json_object_set(diagnostic, c"message", json_string(c"Unsupported runtime AST node"))
		json_object_set(diagnostic, c"kind", json_string(node.kind))
		json_object_set(diagnostic, c"operation", json_string(node.text))
		json_object_set(diagnostic, c"offset", json_int(node.offset))
		json_array_push(messages, diagnostic)

void wpt_diagnostics(json_value* messages, char* source, char* filename):
	pg_parse_result* parsed = js_parse(source, strlen(source), filename, 0)
	js_node* tree = js_lower(parsed)
	wpt_unsupported_node(messages, tree)
	js_node_free(tree)
	for pg_diagnostic* item in parsed.diagnostics.items:
		json_value* diagnostic = json_object()
		json_object_set(diagnostic, c"message", json_string(item.message))
		json_object_set(diagnostic, c"line", json_int(item.line))
		json_object_set(diagnostic, c"column", json_int(item.column))
		json_array_push(messages, diagnostic)
	pg_parse_result_free(parsed)

int main(int argc, int argv):
	args_init(argc, argv)
	if (argc < 3): return 2
	int timeout = atoi(args_get(1))
	if (timeout < 1 || timeout > 60000): return 2
	char* html = c"<!doctype html><html><head><title>WPT</title></head><body></body></html>"
	win_page* page = win_page_parse(html, strlen(html))
	win_script* script = win_script_new(page)
	# The upstream harness is larger than the product per-source limit. This
	# automation-only limit admits the original bytes; product limits stay fixed.
	script.runtime.max_source_bytes = 1048576
	js_runtime_bind(script.runtime, c"__wptComplete", wpt_complete)
	int start = time_monotonic_ms()
	int failed_source = -1
	json_value* diagnostics = json_array()
	for i in range(2, argc):
		char* source = file_read_text(args_get(i))
		if (source == 0):
			failed_source = i - 2
			break
		script.now_ms = time_monotonic_ms()
		int success = win_script_eval(script, source, strlen(source))
		if (success == 0):
			wpt_diagnostics(diagnostics, source, args_get(i))
			free(source)
			failed_source = i - 2
			break
		free(source)
	if (failed_source < 0): win_script_run_pending(script, 0)
	while (failed_source < 0 && script.failures == 0 && wpt_completions == 0 && time_monotonic_ms() - start < timeout):
		win_script_poll(script)
		sleep_ms(1)
	# One final checkpoint observes duplicate completion and queued failures.
	if (wpt_completions > 0 && script.failures == 0): win_script_poll(script)
	json_value* report = json_object()
	json_object_set(report, c"protocol", json_int(1))
	json_object_set(report, c"diagnostics", diagnostics)
	json_object_set(report, c"completions", json_int(wpt_completions))
	json_object_set(report, c"script_failures", json_int(script.failures))
	json_object_set(report, c"failed_source", json_int(failed_source))
	json_object_set(report, c"message", json_string(script.error))
	json_object_set(report, c"elapsed_ms", json_int(time_monotonic_ms() - start))
	if (wpt_payload != 0): json_object_set(report, c"payload", json_string(wpt_payload))
	char* output = json_stringify(report)
	println(output)
	free(output)
	json_free(report)
	free(wpt_payload)
	win_script_free(script)
	win_page_free(page)
	return 0
