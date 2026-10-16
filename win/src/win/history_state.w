# A bounded JSON-tree storage subset, not general structured clone. Reject
# unsupported values before mutation instead of silently dropping state.
import win.web_host

void win_history_error(js_runtime* rt, char* name, char* message):
	if (rt.completion.status != 0): return
	js_value* error = js_runtime_error_value(rt, message)
	js_runtime_set(rt, error, c"name", win_web_string(rt, name))
	js_runtime_throw(rt, error)

int win_history_tree(js_runtime* rt, js_value* value, list[js_value*] seen, int depth):
	if (js_runtime_compat_step(rt) == 0): return 0
	if (depth > 32 || seen.length >= 4096): return 0
	if (value.kind == 1 || value.kind == 2 || value.kind == 4): return 1
	if (value.kind == 3): return js_builtin_finite(value.number) && (value.number != 0.0 || 1.0 / value.number > 0.0)
	if (value.kind != 5 && value.kind != 6): return 0
	if (value.host_get || value.host_set || value.binary_kind || value.regexp != 0 || value.promise_state || value.intrinsic_error_name[0] != 0): return 0
	if (value.prototype != 0 && value.prototype != rt.array_prototype): return 0
	for i in range(seen.length):
		if (seen[i] == value): return 0
	seen.push(value)
	js_text* transform = js_runtime_key(c"toJSON")
	int transformed = js_runtime_property(value, transform) != 0
	if (value.prototype != 0 && js_runtime_property(value.prototype, transform) != 0): transformed = 1
	js_text_free(transform)
	if (transformed): return 0
	int elements = 0
	for i in range(value.properties.length):
		js_value* property = value.properties[i]
		if (property.enumerable == 0): continue
		if (property.accessor): return 0
		if (value.kind == 6):
			int index = js_runtime_array_index(property.key)
			if (index < 0 || index >= value.array_length): return 0
			elements = elements + 1
		if (win_history_tree(rt, property.value, seen, depth + 1) == 0): return 0
	if (value.kind == 6 && elements != value.array_length): return 0
	return 1

char* win_history_encode(js_runtime* rt, js_value* value):
	# Empty encoding distinguishes top-level undefined from initial null.
	if (value.kind == 0): return strclone(c"")
	list[js_value*] seen = new list[js_value*]
	int allowed = win_history_tree(rt, value, seen, 0)
	__w_list_free(cast(__w_list*, seen))
	if (allowed == 0):
		win_history_error(rt, c"DataCloneError", c"History state supports bounded JSON trees only")
		return 0
	list[js_value*] args = new list[js_value*]
	args.push(value)
	js_value* encoded = js_json_stringify_host(rt, 0, rt.undefined_value, args)
	__w_list_free(cast(__w_list*, args))
	if (rt.completion.status != 0 || encoded.kind != 4): return 0
	int length = 0
	char* bytes = js_text_to_utf8(encoded.text, &length)
	if (bytes == 0 || length > 65536):
		free(bytes)
		win_history_error(rt, c"DataCloneError", c"History state exceeds 64 KiB")
		return 0
	return bytes

js_value* win_history_decode(js_runtime* rt, char* text):
	if (text != 0 && text[0] == 0): return rt.undefined_value
	if (text == 0): return js_runtime_alloc(rt, 1)
	js_text* units = js_runtime_key(text)
	js_value* result = js_runtime_json_parse(rt, units)
	js_text_free(units)
	return result
