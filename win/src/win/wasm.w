# WebAssembly host objects backed by the bounded pure-W interpreter.
# Realm owns modules and host contexts; release before js_runtime_free.
import libs.extras.javascript.runtime
import libs.extras.wasm.runtime

struct win_wasm_object:
	void* realm
	wwasm* machine
	js_value* value
	js_value* buffer
	# module=1, instance=2, memory=3, table=4, global=5, function=6
	int kind
	int index
	int owns_machine

struct win_wasm_method:
	void* realm
	win_wasm_object* object
	int action
	js_value* imports
	js_value* callable
	int index

struct win_wasm_realm:
	js_runtime* rt
	list[win_wasm_object*] objects
	list[win_wasm_method*] methods
	int source_bytes
	int pages
	int machines

js_value* win_wasm_dispatch(void* runtime, void* context, js_value* receiver, list[js_value*] args);
js_value* win_wasm_get(void* runtime, void* context, js_value* receiver, js_text* key);
int win_wasm_set(void* runtime, void* context, js_value* receiver, js_text* key, js_value* value);

js_value* win_wasm_string(js_runtime* rt, char* source):
	js_text* text = js_runtime_key(source)
	js_value* result = js_runtime_string(rt, text)
	js_text_free(text)
	return result

js_value* win_wasm_error(js_runtime* rt, char* name, char* message):
	if (rt.completion.status != 0): return rt.undefined_value
	js_value* error = js_runtime_error_value(rt, message)
	if (error != rt.undefined_value):
		error.intrinsic_error_name = name
		js_runtime_set(rt, error, c"name", win_wasm_string(rt, name))
	js_runtime_throw(rt, error)
	return rt.undefined_value

win_wasm_object* win_wasm_lookup(win_wasm_realm* realm, js_value* value, int kind):
	for win_wasm_object* object in realm.objects:
		if (object.value == value && object.kind == kind): return object
	return 0

win_wasm_object* win_wasm_object_new(win_wasm_realm* realm, wwasm* m, int kind, int index):
	if (realm.rt.completion.status != 0): return 0
	if (realm.objects.length >= 4096):
		js_runtime_fail(realm.rt, 5, c"WebAssembly host object limit")
		return 0
	win_wasm_object* object = new win_wasm_object()
	object.realm = realm
	object.machine = m
	object.kind = kind
	object.index = index
	object.value = js_runtime_alloc(realm.rt, 5)
	if (object.value == realm.rt.undefined_value || realm.rt.completion.status != 0):
		free(object)
		return 0
	js_runtime_root(realm.rt, object.value)
	realm.objects.push(object)
	js_runtime_set_host_hooks(realm.rt, object.value, object, win_wasm_get, win_wasm_set)
	return object

js_value* win_wasm_method_new(win_wasm_realm* realm, win_wasm_object* object, int action, js_value* imports, int index):
	if (realm.rt.completion.status != 0): return realm.rt.undefined_value
	if (realm.methods.length >= 8192):
		js_runtime_fail(realm.rt, 5, c"WebAssembly host method limit")
		return realm.rt.undefined_value
	win_wasm_method* method = new win_wasm_method()
	method.realm = realm
	method.object = object
	method.action = action
	method.imports = imports
	method.index = index
	method.callable = js_runtime_host_callable(realm.rt, method, win_wasm_dispatch)
	if (method.callable == realm.rt.undefined_value || realm.rt.completion.status != 0):
		free(method)
		return realm.rt.undefined_value
	if (imports != 0): js_runtime_root(realm.rt, imports)
	js_runtime_root(realm.rt, method.callable)
	realm.methods.push(method)
	return method.callable

int win_wasm_memory_changed(void* context, wwasm* m, int delta):
	win_wasm_realm* realm = cast(win_wasm_realm*, context)
	if (delta > 1024 - realm.pages): return 0
	realm.pages = realm.pages + delta
	for win_wasm_object* object in realm.objects:
		if (object.machine == m && object.kind == 3 && object.buffer != 0):
			js_runtime_array_buffer_detach(realm.rt, object.buffer)
			js_runtime_unroot(realm.rt, object.buffer)
			object.buffer = 0
	return 1

int win_wasm_number_bits(js_runtime* rt, js_value* value, int kind):
	if (kind == 126):
		int bits = 0
		if (!js_runtime_bigint_bits(rt, value, &bits)): return 0
		return bits
	float64 n = js_binary_number(rt, value)
	if (kind == 125): return float_bits(cast(float, n))
	return wwasm_i32(js_binary_uint(n, 32))

js_value* win_wasm_bits_number(js_runtime* rt, int bits, int kind):
	if (kind == 0): return rt.undefined_value
	if (kind == 125): return js_runtime_number(rt, cast(float64, float_from_bits(bits)))
	if (kind == 126): return js_runtime_bigint_i64(rt, bits)
	return js_runtime_number(rt, cast(float64, wwasm_i32(bits)))

int win_wasm_import(void* context, wwasm* m, list[int] args):
	win_wasm_method* method = cast(win_wasm_method*, context)
	win_wasm_realm* realm = cast(win_wasm_realm*, method.realm)
	js_runtime* rt = realm.rt
	wwasm_type* type = m.types[m.functions[method.index].signature]
	list[js_value*] values = new list[js_value*]
	for i in range(args.length): values.push(win_wasm_bits_number(rt, args[i], type.params[i]))
	if (m.fuel < rt.remaining): rt.remaining = m.fuel
	js_value* value = rt.undefined_value
	if (rt.completion.status == 0): value = js_runtime_call_receiver(rt, method.imports, rt.undefined_value, values)
	__w_list_free(cast(__w_list*, values))
	int result = 0
	if (type.result && rt.completion.status == 0): result = win_wasm_number_bits(rt, value, type.result)
	if (rt.remaining < m.fuel): m.fuel = rt.remaining
	if (rt.completion.status != 0): wwasm_fail(m, c"JavaScript import threw")
	return result

js_value* win_wasm_function(win_wasm_realm* realm, wwasm* m, int index):
	for win_wasm_object* object in realm.objects:
		if (object.machine == m && object.kind == 6 && object.index == index): return object.value
	win_wasm_object* object = win_wasm_object_new(realm, m, 6, index)
	if (object == 0): return realm.rt.undefined_value
	js_runtime_unroot(realm.rt, object.value)
	object.value = win_wasm_method_new(realm, object, 20, 0, index)
	js_runtime_root(realm.rt, object.value)
	return object.value

js_value* win_wasm_export_object(win_wasm_realm* realm, wwasm* m, int kind, int index):
	if (kind == 0): return win_wasm_function(realm, m, index)
	int object_kind = 3
	if (kind == 1): object_kind = 4
	if (kind == 3): object_kind = 5
	for win_wasm_object* existing in realm.objects:
		if (existing.machine == m && existing.kind == object_kind && existing.index == index): return existing.value
	win_wasm_object* object = win_wasm_object_new(realm, m, object_kind, index)
	if (object == 0): return realm.rt.undefined_value
	js_runtime* rt = realm.rt
	if (kind == 2): js_runtime_set(rt, object.value, c"grow", win_wasm_method_new(realm, object, 21, 0, 0))
	if (kind == 1):
		js_runtime_set(rt, object.value, c"get", win_wasm_method_new(realm, object, 22, 0, 0))
		js_runtime_set(rt, object.value, c"set", win_wasm_method_new(realm, object, 23, 0, 0))
	if (kind == 3): js_runtime_set(rt, object.value, c"valueOf", win_wasm_method_new(realm, object, 24, 0, 0))
	return object.value

js_value* win_wasm_get(void* runtime, void* context, js_value* receiver, js_text* key):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_wasm_object* object = cast(win_wasm_object*, context)
	if (object.value != receiver): return 0
	wwasm* m = object.machine
	if (object.kind == 3 && js_runtime_key_is(key, c"buffer")):
		if (object.buffer == 0):
			object.buffer = js_runtime_array_buffer_wrap(rt, cast(byte*, m.memory), m.pages * 65536)
			if (object.buffer == rt.undefined_value || rt.completion.status != 0):
				object.buffer = 0
				return rt.undefined_value
			js_runtime_root(rt, object.buffer)
		return object.buffer
	if (object.kind == 4 && js_runtime_key_is(key, c"length")): return js_runtime_number(rt, cast(float64, m.table.length))
	if (object.kind == 5 && js_runtime_key_is(key, c"value")): return win_wasm_bits_number(rt, m.globals[object.index].bits, m.globals[object.index].kind)
	return 0

int win_wasm_set(void* runtime, void* context, js_value* receiver, js_text* key, js_value* value):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_wasm_object* object = cast(win_wasm_object*, context)
	if (object.value != receiver): return 0
	if ((object.kind == 3 && js_runtime_key_is(key, c"buffer")) || (object.kind == 4 && js_runtime_key_is(key, c"length"))): return -1
	if (object.kind == 5 && js_runtime_key_is(key, c"value")):
		wwasm_global* g = object.machine.globals[object.index]
		if (!g.mutable):
			win_wasm_error(rt, c"TypeError", c"immutable WebAssembly global")
			return -1
		int bits = win_wasm_number_bits(rt, value, g.kind)
		if (rt.completion.status == 0): g.bits = bits
		return 1
	return 0

win_wasm_object* win_wasm_compile(win_wasm_realm* realm, js_value* bytes):
	js_runtime* rt = realm.rt
	byte* data = js_runtime_binary_data(rt, bytes)
	int length = js_runtime_binary_byte_length(rt, bytes)
	if (data == 0):
		win_wasm_error(rt, c"TypeError", c"WebAssembly requires a buffer source")
		return 0
	if (realm.machines >= 16 || length > 4194304 - realm.source_bytes):
		win_wasm_error(rt, c"CompileError", c"WebAssembly realm source limit")
		return 0
	wwasm* m = wwasm_load(cast(char*, data), length)
	if (m.pages > 1024 - realm.pages): wwasm_fail(m, c"WebAssembly realm memory limit")
	if (!m.valid || m.error != 0):
		win_wasm_error(rt, c"CompileError", m.error)
		wwasm_free(m)
		return 0
	win_wasm_object* object = win_wasm_object_new(realm, m, 1, 0)
	if (object == 0):
		wwasm_free(m)
		return 0
	object.owns_machine = 1
	realm.pages = realm.pages + m.pages
	realm.machines = realm.machines + 1
	realm.source_bytes = realm.source_bytes + length
	return object

js_value* win_wasm_instantiate(win_wasm_realm* realm, win_wasm_object* module, js_value* imports):
	js_runtime* rt = realm.rt
	if (realm.machines >= 16 || module.machine.length > 4194304 - realm.source_bytes): return win_wasm_error(rt, c"LinkError", c"WebAssembly realm source limit")
	wwasm* m = wwasm_load(module.machine.bytes, module.machine.length)
	if (m.pages > 1024 - realm.pages): wwasm_fail(m, c"WebAssembly realm memory limit")
	if (!m.valid || m.error != 0):
		js_value* result = win_wasm_error(rt, c"CompileError", m.error)
		wwasm_free(m)
		return result
	win_wasm_object* instance = win_wasm_object_new(realm, m, 2, 0)
	if (instance == 0):
		wwasm_free(m)
		return rt.undefined_value
	instance.owns_machine = 1
	realm.pages = realm.pages + m.pages
	realm.machines = realm.machines + 1
	realm.source_bytes = realm.source_bytes + m.length
	m.grow_hook = cast(int, win_wasm_memory_changed)
	m.grow_context = realm
	for i in range(m.imports):
		wwasm_function* f = m.functions[i]
		js_value* namespace = js_runtime_get(rt, imports, f.module_name)
		js_value* function = js_runtime_get(rt, namespace, f.name)
		if (rt.completion.status != 0): return rt.undefined_value
		if (!js_runtime_callable(function)): return win_wasm_error(rt, c"LinkError", c"missing callable WebAssembly import")
		win_wasm_object* wasm_function = win_wasm_lookup(realm, function, 6)
		if (wasm_function != 0):
			wwasm_type* actual = wasm_function.machine.types[wasm_function.machine.functions[wasm_function.index].signature]
			if (!wwasm_type_equal(m.types[f.signature], actual)): return win_wasm_error(rt, c"LinkError", c"WebAssembly import signature mismatch")
		win_wasm_method_new(realm, instance, 0, function, i)
		if (rt.completion.status != 0): return rt.undefined_value
		win_wasm_method* method = realm.methods[realm.methods.length - 1]
		f.context = method
		f.callback = cast(int, win_wasm_import)
	js_value* exports = js_runtime_alloc(rt, 5)
	for wwasm_export* e in m.exports: js_runtime_set(rt, exports, e.name, win_wasm_export_object(realm, m, e.kind, e.index))
	js_runtime_set(rt, instance.value, c"exports", exports)
	if (m.start >= 0 && rt.completion.status == 0):
		list[int] args = new list[int]
		wwasm_call(m, m.start, args, rt.remaining)
		if (m.fuel < rt.remaining): rt.remaining = m.fuel
		__w_list_free(cast(__w_list*, args))
		if (m.error != 0): return win_wasm_error(rt, c"RuntimeError", m.error)
	return instance.value

int win_wasm_index(js_runtime* rt, js_value* value, int maximum):
	float64 number = js_binary_number(rt, value)
	if (f64is_nan(number) || number < 0.0 || number > cast(float64, maximum) || cast(float64, cast(int, number)) != number):
		win_wasm_error(rt, c"RangeError", c"WebAssembly index out of range")
		return -1
	return cast(int, number)

js_value* win_wasm_promise_result(js_runtime* rt, js_value* result):
	if (rt.completion.status != 0 && rt.completion.status != 2): return rt.undefined_value
	int rejected = rt.completion.status == 2
	if (rejected):
		result = rt.completion.value
		rt.completion.status = 0
		rt.completion.value = rt.undefined_value
	js_value* promise = js_runtime_promise_new(rt)
	js_runtime_promise_settle(rt, promise, result, rejected)
	return promise

js_value* win_wasm_dispatch(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_wasm_method* method = cast(win_wasm_method*, context)
	win_wasm_realm* realm = cast(win_wasm_realm*, method.realm)
	int action = method.action
	js_value* first = rt.undefined_value
	js_value* second = rt.undefined_value
	if (args.length > 0): first = args[0]
	if (args.length > 1): second = args[1]
	if (action == 1 || action == 5 || action == 6):
		if (action == 6):
			byte* data = js_runtime_binary_data(rt, first)
			if (data == 0): return win_wasm_error(rt, c"TypeError", c"WebAssembly requires a buffer source")
			wwasm* checked = wwasm_load(cast(char*, data), js_runtime_binary_byte_length(rt, first))
			int valid = checked.valid
			wwasm_free(checked)
			return js_runtime_boolean(rt, valid)
		win_wasm_object* module = win_wasm_compile(realm, first)
		js_value* result = rt.undefined_value
		if (module != 0): result = module.value
		if (action == 5): return win_wasm_promise_result(rt, result)
		return result
	if (action == 2 || action == 7):
		win_wasm_object* module = win_wasm_lookup(realm, first, 1)
		int compiled = 0
		if (module == 0 && action == 7):
			module = win_wasm_compile(realm, first)
			compiled = 1
		js_value* result = rt.undefined_value
		if (module == 0): win_wasm_error(rt, c"TypeError", c"WebAssembly.Instance requires Module")
		else:
			result = win_wasm_instantiate(realm, module, second)
			if (compiled && rt.completion.status == 0):
				js_value* pair = js_runtime_alloc(rt, 5)
				js_runtime_set(rt, pair, c"module", module.value)
				js_runtime_set(rt, pair, c"instance", result)
				result = pair
		if (action == 7): return win_wasm_promise_result(rt, result)
		return result
	if (action == 3):
		if (realm.machines >= 16): return win_wasm_error(rt, c"RangeError", c"WebAssembly machine limit")
		int initial = win_wasm_index(rt, js_runtime_get(rt, first, c"initial"), 256)
		js_value* max_value = js_runtime_get(rt, first, c"maximum")
		int maximum = 256
		if (max_value.kind != 0): maximum = win_wasm_index(rt, max_value, 65536)
		if (maximum > 256): maximum = 256
		if (rt.completion.status != 0): return rt.undefined_value
		if (initial > maximum): return win_wasm_error(rt, c"RangeError", c"initial exceeds maximum")
		wwasm* m = wwasm_load(c"\x00asm\x01\x00\x00\x00", 8)
		m.has_memory = 1
		m.max_pages = maximum
		m.grow_hook = cast(int, win_wasm_memory_changed)
		m.grow_context = realm
		if (wwasm_grow(m, initial) < 0):
			wwasm_free(m)
			return win_wasm_error(rt, c"RangeError", c"WebAssembly realm memory limit")
		realm.machines = realm.machines + 1
		js_value* value = win_wasm_export_object(realm, m, 2, 0)
		win_wasm_object* object = win_wasm_lookup(realm, value, 3)
		if (object != 0): object.owns_machine = 1
		else: wwasm_free(m)
		return value
	if (action == 8 || action == 9 || action == 30):
		# Buffered Response compatibility: consume arrayBuffer, then compile.
		# No MIME verification or incremental compilation is claimed here.
		js_value* promise = js_runtime_promise_new(rt)
		js_runtime_promise_settle(rt, promise, first, 0)
		int next_action = 31
		if (action == 8 || action == 9): next_action = 30
		js_value* imports = second
		int operation = action
		if (action == 30):
			imports = method.imports
			operation = method.index
			list[js_value*] empty = new list[js_value*]
			js_value* buffer = js_runtime_call_receiver(rt, js_runtime_get(rt, first, c"arrayBuffer"), first, empty)
			__w_list_free(cast(__w_list*, empty))
			if (rt.completion.status != 0): return rt.undefined_value
			promise = js_runtime_promise_new(rt)
			js_runtime_promise_settle(rt, promise, buffer, 0)
		js_value* callback = win_wasm_method_new(realm, 0, next_action, imports, operation)
		js_value* result = js_runtime_promise_new(rt)
		js_runtime_promise_reaction(rt, promise, result, callback, rt.undefined_value)
		return result
	if (action == 31):
		list[js_value*] forwarded = new list[js_value*]
		forwarded.push(first)
		forwarded.push(method.imports)
		win_wasm_method nested
		nested.realm = realm
		nested.action = 5
		if (method.index == 9): nested.action = 7
		js_value* result = win_wasm_dispatch(rt, &nested, rt.undefined_value, forwarded)
		__w_list_free(cast(__w_list*, forwarded))
		return result
	win_wasm_object* object = method.object
	if (object == 0): return win_wasm_error(rt, c"TypeError", c"invalid WebAssembly method")
	wwasm* m = object.machine
	if (action != 20 && receiver != object.value): return win_wasm_error(rt, c"TypeError", c"invalid WebAssembly receiver")
	if (action == 20):
		wwasm_type* type = m.types[m.functions[object.index].signature]
		list[int] values = new list[int]
		for i in range(type.params.length):
			js_value* arg = rt.undefined_value
			if (i < args.length): arg = args[i]
			values.push(win_wasm_number_bits(rt, arg, type.params[i]))
		int result = 0
		if (rt.completion.status == 0):
			int fuel = rt.remaining
			if (fuel > 1000000): fuel = 1000000
			if (m.depth > 0): fuel = m.fuel
			result = wwasm_call(m, object.index, values, fuel)
			if (m.fuel < rt.remaining): rt.remaining = m.fuel
		__w_list_free(cast(__w_list*, values))
		if (m.error != 0): return win_wasm_error(rt, c"RuntimeError", m.error)
		if (rt.completion.status != 0): return rt.undefined_value
		return win_wasm_bits_number(rt, result, type.result)
	if (action == 21):
		int delta = win_wasm_index(rt, first, 65536)
		if (delta < 0): return rt.undefined_value
		int previous = wwasm_grow(m, delta)
		if (previous < 0): return win_wasm_error(rt, c"RangeError", c"WebAssembly memory maximum exceeded")
		return js_runtime_number(rt, cast(float64, previous))
	if (action == 22 || action == 23):
		int index = win_wasm_index(rt, first, m.table.length - 1)
		if (index < 0): return rt.undefined_value
		if (action == 22):
			if (m.table[index] < 0): return js_runtime_alloc(rt, 1)
			return win_wasm_function(realm, m, m.table[index])
		if (second.kind == 1): m.table[index] = -1
		else:
			win_wasm_object* function = win_wasm_lookup(realm, second, 6)
			if (function == 0 || function.machine != m): return win_wasm_error(rt, c"TypeError", c"table requires same-instance WebAssembly function")
			m.table[index] = function.index
		return rt.undefined_value
	if (action == 24): return win_wasm_bits_number(rt, m.globals[object.index].bits, m.globals[object.index].kind)
	return win_wasm_error(rt, c"TypeError", c"unsupported WebAssembly operation")

win_wasm_realm* win_wasm_install(js_runtime* rt):
	win_wasm_realm* realm = new win_wasm_realm()
	realm.rt = rt
	realm.objects = new list[win_wasm_object*]
	realm.methods = new list[win_wasm_method*]
	js_value* namespace = js_runtime_alloc(rt, 5)
	if (namespace == rt.undefined_value || rt.completion.status != 0): return realm
	js_value* module = win_wasm_method_new(realm, 0, 1, 0, 0)
	if (module != rt.undefined_value): module.host_construct = 1
	js_runtime_set(rt, namespace, c"Module", module)
	js_value* instance = win_wasm_method_new(realm, 0, 2, 0, 0)
	if (instance != rt.undefined_value): instance.host_construct = 1
	js_runtime_set(rt, namespace, c"Instance", instance)
	js_value* memory = win_wasm_method_new(realm, 0, 3, 0, 0)
	if (memory != rt.undefined_value): memory.host_construct = 1
	js_runtime_set(rt, namespace, c"Memory", memory)
	js_runtime_set(rt, namespace, c"compile", win_wasm_method_new(realm, 0, 5, 0, 0))
	js_runtime_set(rt, namespace, c"validate", win_wasm_method_new(realm, 0, 6, 0, 0))
	js_runtime_set(rt, namespace, c"instantiate", win_wasm_method_new(realm, 0, 7, 0, 0))
	js_runtime_set(rt, namespace, c"compileStreaming", win_wasm_method_new(realm, 0, 8, 0, 0))
	js_runtime_set(rt, namespace, c"instantiateStreaming", win_wasm_method_new(realm, 0, 9, 0, 0))
	js_runtime_set(rt, rt.global, c"WebAssembly", namespace)
	return realm

void win_wasm_free(win_wasm_realm* realm):
	if (realm == 0): return
	for win_wasm_object* object in realm.objects:
		if (object.buffer != 0):
			js_runtime_array_buffer_detach(realm.rt, object.buffer)
			js_runtime_unroot(realm.rt, object.buffer)
		js_runtime_unroot(realm.rt, object.value)
	for win_wasm_method* method in realm.methods:
		js_runtime_unroot(realm.rt, method.callable)
		if (method.imports != 0): js_runtime_unroot(realm.rt, method.imports)
		free(method)
	for win_wasm_object* object in realm.objects:
		if (object.owns_machine): wwasm_free(object.machine)
		free(object)
	__w_list_free(cast(__w_list*, realm.objects))
	__w_list_free(cast(__w_list*, realm.methods))
	free(realm)
