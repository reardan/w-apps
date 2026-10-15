# Adversarial binary validation and execution traps, all from wire bytes.
# Keep expected rejection/traps strict; valid controls prevent blanket rejection.
# Binary integer rules: https://webassembly.github.io/spec/core/binary/values.html
import lib.assert
import lib.process
import win.wasm

int wasm_validation_failures
int wasm_validation_cases

int wasm_validation_digit(int c):
	if (c >= '0' && c <= '9'): return c - '0'
	return c - 'a' + 10

string_builder* wasm_validation_bytes(char* hex):
	string_builder* bytes = string_new()
	int at = 0
	while (hex[at] != 0):
		int value = wasm_validation_digit(hex[at]) * 16 + wasm_validation_digit(hex[at + 1])
		string_append_char(bytes, value)
		at = at + 2
	return bytes

void wasm_validation_case(char* name, char* hex, int valid, char* trap, int expected, int fuel):
	string_builder* bytes = wasm_validation_bytes(hex)
	int start = process_monotonic_ms()
	wwasm* m = wwasm_load(bytes.data, bytes.length)
	int ok = m.valid == valid
	if (valid && m.valid):
		list[int] args = new list[int]
		int result = wwasm_call(m, 0, args, fuel)
		if (trap[0] != 0): ok = m.error != 0 && strcmp(m.error, trap) == 0
		else: ok = m.error == 0 && result == expected
		if (m.depth != 0): ok = 0
		__w_list_free(cast(__w_list*, args))
	else if (!valid && m.error == 0): ok = 0
	if (process_monotonic_ms() - start > 1000): ok = 0
	wasm_validation_cases = wasm_validation_cases + 1
	if (!ok):
		wasm_validation_failures = wasm_validation_failures + 1
		print(c"FAIL wasm validation: ")
		print(name)
		print(c"; observed ")
		if (m.error != 0): println(m.error)
		else: println(c"accepted without trap")
	wwasm_free(m)
	string_free(bytes)

void wasm_validation_truncation():
	string_builder* bytes = wasm_validation_bytes(c"0061736d010000000105016000017f030201000a06010400412a0b")
	for length in range(bytes.length):
		# Header-only and section-boundary prefixes may be valid empty modules.
		wwasm* m = wwasm_load(bytes.data, length)
		if (length != 8 && length != 15): asserts(c"truncated module rejected", !m.valid && m.error != 0)
		wwasm_free(m)
	string_free(bytes)


int wasm_validation_host_calls

int wasm_validation_reenter(void* context, wwasm* m, list[int] args):
	wasm_validation_host_calls = wasm_validation_host_calls + 1
	# Reentry may request more fuel, but cannot replenish an active call.
	return wwasm_call(m, 1, args, 1000000)

void wasm_validation_host_reentry():
	string_builder* bytes = wasm_validation_bytes(c"0061736d010000000105016000017f020701016d01660000030201000a0601040010000b")
	wwasm* m = wwasm_load(bytes.data, bytes.length)
	asserts(c"reentrant import module validates", m.valid)
	assert_equal(1, wwasm_bind(m, c"m", c"f", 0, wasm_validation_reenter))
	list[int] args = new list[int]
	wwasm_call(m, 1, args, 20)
	asserts(c"host reentry cannot replenish fuel", m.error != 0 && m.fuel <= 0)
	asserts(c"host reentry bounded before depth cap", wasm_validation_host_calls > 0 && wasm_validation_host_calls < 10)
	assert_equal(0, m.depth)
	# API index/arity checks must trap too, including a signed host index.
	wwasm_call(m, -1, args, 100)
	assert_strings_equal(c"invalid function call", m.error)
	args.push(1)
	wwasm_call(m, 1, args, 100)
	assert_strings_equal(c"argument count mismatch", m.error)
	__w_list_free(cast(__w_list*, args))
	wwasm_free(m)
	string_free(bytes)

void wasm_validation_start_budget():
	string_builder* bytes = wasm_validation_bytes(c"0061736d01000000010401600000030201000801000a0901070003400c000b0b")
	wwasm* m = wwasm_load(bytes.data, bytes.length)
	asserts(c"infinite start validates", m.valid)
	js_runtime* rt = js_runtime_new()
	rt.remaining = 100000
	win_wasm_realm* realm = win_wasm_install(rt)
	win_wasm_object* module = win_wasm_object_new(realm, m, 1, 0)
	asserts(c"module host object created", module != 0)
	module.owns_machine = 1
	rt.remaining = 32
	win_wasm_instantiate(realm, module, rt.undefined_value)
	asserts(c"start consumes caller fuel", rt.remaining <= 0)
	asserts(c"start reports trap through JS", rt.completion.status != 0)
	win_wasm_free(realm)
	js_runtime_free(rt)
	string_free(bytes)


void wasm_validation_u32(string_builder* bytes, int value):
	while (value >= 128):
		string_append_char(bytes, (value & 127) | 128)
		value = value >> 7
	string_append_char(bytes, value)

void wasm_validation_exports(int count, int duplicate):
	string_builder* payload = string_new()
	wasm_validation_u32(payload, count)
	for i in range(count):
		string_builder* name = string_new()
		string_append_char(name, 'e')
		int id = i
		if (duplicate && i == count - 1): id = 0
		string_append_int(name, id)
		wasm_validation_u32(payload, name.length)
		string_append_bytes(payload, name.data, name.length)
		string_append_char(payload, 2)
		string_append_char(payload, 0)
		string_free(name)
	# Empty memory, many distinct export names of the same memory object.
	string_builder* bytes = wasm_validation_bytes(c"0061736d010000000503010000")
	string_append_char(bytes, 7)
	wasm_validation_u32(bytes, payload.length)
	string_append_bytes(bytes, payload.data, payload.length)
	int start = process_monotonic_ms()
	wwasm* m = wwasm_load(bytes.data, bytes.length)
	asserts(c"export processing stays bounded", process_monotonic_ms() - start < 1000)
	if (count > 4096):
		assert_equal(0, m.valid)
		assert_strings_equal(c"export count limit", m.error)
	else if (duplicate):
		assert_equal(0, m.valid)
		assert_strings_equal(c"duplicate export", m.error)
	else:
		asserts(c"4096 unique names remain valid", m.valid && m.exports.length == count)
	wwasm_free(m)
	string_free(bytes)
	string_free(payload)

void wasm_validation_mutations():
	string_builder* bytes = wasm_validation_bytes(c"0061736d010000000105016000017f030201000a06010400412a0b")
	int start = process_monotonic_ms()
	for at in range(bytes.length):
		int original = bytes.data[at] & 255
		for bit in range(8):
			bytes.data[at] = original ^ (1 << bit)
			wwasm* m = wwasm_load(bytes.data, bytes.length)
			if (m.valid && m.functions.length > 0):
				list[int] args = new list[int]
				wwasm_type* signature = m.types[m.functions[0].signature]
				for i in range(signature.params.length): args.push(0)
				m.max_depth = 8
				wwasm_call(m, 0, args, 32)
				assert_equal(0, m.depth)
				__w_list_free(cast(__w_list*, args))
			wwasm_free(m)
		bytes.data[at] = original
	asserts(c"bounded mutation sweep", process_monotonic_ms() - start < 2000)
	string_free(bytes)


js_value* wasm_validation_js_cost(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	# Simulate seven units of work performed by a JavaScript import.
	rt.remaining = rt.remaining - 7
	return js_runtime_number(rt, 1.0)

void wasm_validation_import_budget():
	string_builder* bytes = wasm_validation_bytes(c"0061736d010000000105016000017f020701016d01660000030201000a2201200010001a01010101010101010101010101010101010101010101010101412a0b")
	wwasm* m = wwasm_load(bytes.data, bytes.length)
	asserts(c"import budget module validates", m.valid)
	js_runtime* rt = js_runtime_new()
	rt.remaining = 100000
	win_wasm_realm* realm = win_wasm_install(rt)
	win_wasm_object* module = win_wasm_object_new(realm, m, 1, 0)
	module.owns_machine = 1
	js_value* imports = js_runtime_alloc(rt, 5)
	js_value* namespace = js_runtime_alloc(rt, 5)
	js_runtime_set(rt, namespace, c"f", js_runtime_host_callable(rt, 0, wasm_validation_js_cost))
	js_runtime_set(rt, imports, c"m", namespace)
	js_value* instance = win_wasm_instantiate(realm, module, imports)
	win_wasm_object* object = win_wasm_lookup(realm, instance, 2)
	asserts(c"import budget instance links", object != 0 && rt.completion.status == 0)
	list[int] args = new list[int]
	# 32 units suffice for this function only if the JS import is free.
	wwasm_call(object.machine, 1, args, 32)
	asserts(c"JS import work charged against active Wasm fuel", object.machine.error != 0 && object.machine.fuel <= 0)
	assert_equal(0, object.machine.depth)
	__w_list_free(cast(__w_list*, args))
	win_wasm_free(realm)
	js_runtime_free(rt)
	string_free(bytes)

int main():
	wasm_validation_case(c"constant result", c"0061736d010000000105016000017f030201000a06010400412a0b", 1, c"", 42, 100)
	wasm_validation_case(c"header version", c"0061736d02000000", 0, c"", 0, 100)
	wasm_validation_case(c"section length overflow", c"0061736d0100000001ffffffff0f", 0, c"", 0, 100)
	wasm_validation_case(c"section length invalid LEB", c"0061736d0100000001ffffffff10", 0, c"", 0, 100)
	wasm_validation_case(c"type count huge", c"0061736d010000000105ffffffff0f", 0, c"", 0, 100)
	wasm_validation_case(c"type count more than payload", c"0061736d01000000010402600000", 0, c"", 0, 100)
	wasm_validation_case(c"duplicate type section", c"0061736d01000000010100010100", 0, c"", 0, 100)
	wasm_validation_case(c"section out of order", c"0061736d01000000050100010100", 0, c"", 0, 100)
	wasm_validation_case(c"function unknown signature", c"0061736d0100000003020100", 0, c"", 0, 100)
	wasm_validation_case(c"missing code section", c"0061736d0100000001040160000003020100", 0, c"", 0, 100)
	wasm_validation_case(c"code count mismatch", c"0061736d01000000010401600000030201000a0100", 0, c"", 0, 100)
	wasm_validation_case(c"export invalid function index", c"0061736d0100000007050101660000", 0, c"", 0, 100)
	wasm_validation_case(c"export invalid memory index", c"0061736d01000000070501016d0200", 0, c"", 0, 100)
	wasm_validation_case(c"start invalid index", c"0061736d01000000080100", 0, c"", 0, 100)
	wasm_validation_case(c"invalid global mutability", c"0061736d010000000606017f0241000b", 0, c"", 0, 100)
	wasm_validation_case(c"invalid initializer type", c"0061736d010000000606017f0042000b", 0, c"", 0, 100)
	wasm_validation_case(c"memory min exceeds max", c"0061736d01000000050401010201", 0, c"", 0, 100)
	wasm_validation_case(c"memory initial huge", c"0061736d0100000005070100ffffffff0f", 0, c"", 0, 100)
	wasm_validation_case(c"table initial huge", c"0061736d010000000408017000ffffffff0f", 0, c"", 0, 100)
	wasm_validation_case(c"data outside memory", c"0061736d0100000005030100010b090100418080040b01aa", 0, c"", 0, 100)
	wasm_validation_case(c"data negative offset", c"0061736d0100000005030100010b070100417f0b01aa", 0, c"", 0, 100)
	wasm_validation_case(c"data payload truncated", c"0061736d0100000005030100010b07010041000b02aa", 0, c"", 0, 100)
	wasm_validation_case(c"element function invalid", c"0061736d010000000404017000010907010041000b0100", 0, c"", 0, 100)
	wasm_validation_case(c"element offset outside table", c"0061736d010000000404017000010906010041020b00", 0, c"", 0, 100)
	wasm_validation_case(c"call index huge", c"0061736d010000000105016000017f030201000a0a01080010ffffffff0f0b", 0, c"", 0, 100)
	wasm_validation_case(c"call nonexistent", c"0061736d010000000105016000017f030201000a0601040010010b", 0, c"", 0, 100)
	wasm_validation_case(c"local index huge", c"0061736d010000000105016000017f030201000a0a01080020ffffffff0f0b", 0, c"", 0, 100)
	wasm_validation_case(c"local nonexistent", c"0061736d010000000105016000017f030201000a0601040020000b", 0, c"", 0, 100)
	wasm_validation_case(c"global index huge", c"0061736d010000000105016000017f030201000a0a01080023ffffffff0f0b", 0, c"", 0, 100)
	wasm_validation_case(c"branch depth huge", c"0061736d010000000105016000017f030201000a0a0108000cffffffff0f0b", 0, c"", 0, 100)
	wasm_validation_case(c"branch nonexistent", c"0061736d010000000105016000017f030201000a060104000c010b", 0, c"", 0, 100)
	wasm_validation_case(c"branch table invalid default", c"0061736d010000000105016000017f030201000a0901070041000e00010b", 0, c"", 0, 100)
	wasm_validation_case(c"branch table huge vector", c"0061736d010000000105016000017f030201000a0d010b0041000effffffff0f000b", 0, c"", 0, 100)
	wasm_validation_case(c"stack underflow", c"0061736d010000000105016000017f030201000a050103006a0b", 0, c"", 0, 100)
	wasm_validation_case(c"wrong result type", c"0061736d010000000105016000017f030201000a0601040042000b", 0, c"", 0, 100)
	wasm_validation_case(c"wrong operand type", c"0061736d010000000105016000017f030201000a09010700420041006a0b", 0, c"", 0, 100)
	wasm_validation_case(c"extra result", c"0061736d010000000105016000017f030201000a08010600410041010b", 0, c"", 0, 100)
	wasm_validation_case(c"select type mismatch", c"0061736d010000000105016000017f030201000a0b0109004100420041001b0b", 0, c"", 0, 100)
	wasm_validation_case(c"if wrong condition type", c"0061736d010000000105016000017f030201000a0e010c004200047f41000541010b0b", 0, c"", 0, 100)
	wasm_validation_case(c"if missing else with result", c"0061736d010000000105016000017f030201000a0b0109004100047f41000b0b", 0, c"", 0, 100)
	wasm_validation_case(c"if inconsistent arms", c"0061736d010000000105016000017f030201000a0e010c004100047f41000542010b0b", 0, c"", 0, 100)
	wasm_validation_case(c"stray else", c"0061736d010000000105016000017f030201000a070105000541000b", 0, c"", 0, 100)
	wasm_validation_case(c"repeated else", c"0061736d010000000105016000017f030201000a11010f004100047f41000541000541000b0b", 0, c"", 0, 100)
	wasm_validation_case(c"unterminated block", c"0061736d010000000105016000017f030201000a08010600027f41000b", 0, c"", 0, 100)
	wasm_validation_case(c"trailing function instructions", c"0061736d010000000105016000017f030201000a0701050041000b01", 0, c"", 0, 100)
	wasm_validation_case(c"malformed signed i32 LEB", c"0061736d010000000105016000017f030201000a0a0108004180808080080b", 0, c"", 0, 100)
	wasm_validation_case(c"too long signed i32 LEB", c"0061736d010000000105016000017f030201000a0b010900418080808080000b", 0, c"", 0, 100)
	wasm_validation_case(c"malformed signed i64 LEB", c"0061736d010000000105016000017f030201000a1201100042808080808080808080021a41000b", 0, c"", 0, 100)
	wasm_validation_case(c"load missing memory", c"0061736d010000000105016000017f030201000a0901070041002802000b", 0, c"", 0, 100)
	wasm_validation_case(c"indirect missing table", c"0061736d010000000105016000017f030201000a0901070041001100000b", 0, c"", 0, 100)
	wasm_validation_case(c"unreachable still checks index", c"0061736d010000000105016000017f030201000a0b0109000020ffffffff0f0b", 0, c"", 0, 100)
	wasm_validation_case(c"unreachable concrete type mismatch", c"0061736d010000000105016000017f030201000a080106000042006a0b", 0, c"", 0, 100)
	wasm_validation_case(c"locals count huge", c"0061736d010000000105016000017f030201000a0c010a01ffffffff0f7f41000b", 0, c"", 0, 100)
	wasm_validation_case(c"locals unknown type", c"0061736d010000000105016000017f030201000a08010601017b41000b", 0, c"", 0, 100)
	wasm_validation_case(c"local set type mismatch", c"0061736d010000000105016000017f030201000a0c010a01017f4200210041000b", 0, c"", 0, 100)
	wasm_validation_case(c"load over-aligned", c"0061736d010000000105016000017f0302010005030100010a0901070041002803000b", 0, c"", 0, 100)
	wasm_validation_case(c"store wrong value type", c"0061736d010000000105016000017f0302010005030100010a0d010b004100420036020041000b", 0, c"", 0, 100)
	wasm_validation_case(c"memory size wrong index", c"0061736d010000000105016000017f0302010005030100010a060104003f010b", 0, c"", 0, 100)
	wasm_validation_case(c"memory grow wrong type", c"0061736d010000000105016000017f0302010005030100010a08010600420040000b", 0, c"", 0, 100)
	wasm_validation_case(c"indirect invalid type", c"0061736d010000000105016000017f030201000404017000010a0d010b00410011ffffffff0f000b", 0, c"", 0, 100)
	wasm_validation_case(c"indirect invalid table", c"0061736d010000000105016000017f030201000404017000010a0901070041001100010b", 0, c"", 0, 100)
	wasm_validation_case(c"immutable global set", c"0061736d010000000105016000017f030201000606017f0041000b0a0a0108004100240041000b", 0, c"", 0, 100)
	wasm_validation_case(c"start wrong signature", c"0061736d010000000105016000017f030201000801000a0601040041000b", 0, c"", 0, 100)
	wasm_validation_case(c"last byte load succeeds", c"0061736d010000000105016000017f0302010005030100010a0b01090041ffff032d00000b", 1, c"", 0, 100)
	wasm_validation_case(c"four byte end load succeeds", c"0061736d010000000105016000017f0302010005030100010a0b01090041fcff032802000b", 1, c"", 0, 100)
	wasm_validation_case(c"load crossing boundary", c"0061736d010000000105016000017f0302010005030100010a0b01090041ffff032802000b", 1, c"memory access out of bounds", 0, 100)
	wasm_validation_case(c"store crossing boundary", c"0061736d010000000105016000017f0302010005030100010a0f010d0041ffff03410136020041000b", 1, c"memory access out of bounds", 0, 100)
	wasm_validation_case(c"negative load address", c"0061736d010000000105016000017f0302010005030100010a09010700417f2d00000b", 1, c"memory access out of bounds", 0, 100)
	wasm_validation_case(c"offset plus address cannot wrap", c"0061736d010000000105016000017f0302010005030100010a0d010b0041012d00ffffffff0f0b", 1, c"memory access out of bounds", 0, 100)
	wasm_validation_case(c"load zero page memory", c"0061736d010000000105016000017f0302010005030100000a0901070041002d00000b", 1, c"memory access out of bounds", 0, 100)
	wasm_validation_case(c"indirect OOB", c"0061736d010000000105016000017f030201000404017000010a0901070041011100000b", 1, c"table access out of bounds", 0, 100)
	wasm_validation_case(c"indirect uninitialized", c"0061736d010000000105016000017f030201000404017000010a0901070041001100000b", 1, c"uninitialized table element", 0, 100)
	wasm_validation_case(c"i32 division remainder zero 6d", c"0061736d010000000105016000017f030201000a09010700410141006d0b", 1, c"integer divide by zero", 0, 100)
	wasm_validation_case(c"i32 division remainder zero 6e", c"0061736d010000000105016000017f030201000a09010700410141006e0b", 1, c"integer divide by zero", 0, 100)
	wasm_validation_case(c"i32 division remainder zero 6f", c"0061736d010000000105016000017f030201000a09010700410141006f0b", 1, c"integer divide by zero", 0, 100)
	wasm_validation_case(c"i32 division remainder zero 70", c"0061736d010000000105016000017f030201000a0901070041014100700b", 1, c"integer divide by zero", 0, 100)
	wasm_validation_case(c"signed division overflow", c"0061736d010000000105016000017f030201000a0d010b00418080808078417f6d0b", 1, c"integer overflow", 0, 100)
	wasm_validation_case(c"signed remainder minimum by minus one", c"0061736d010000000105016000017f030201000a0d010b00418080808078417f6f0b", 1, c"", 0, 100)
	wasm_validation_case(c"i64 unsigned division remainder zero 80", c"0061736d010000000105016000017e030201000a0901070042014200800b", 1, c"integer divide by zero", 0, 100)
	wasm_validation_case(c"i64 unsigned division remainder zero 82", c"0061736d010000000105016000017e030201000a0901070042014200820b", 1, c"integer divide by zero", 0, 100)
	wasm_validation_case(c"infinite loop fuel", c"0061736d010000000105016000017f030201000a0b01090003400c000b41000b", 1, c"WebAssembly instruction limit", 0, 32)
	wasm_validation_case(c"recursion depth", c"0061736d010000000105016000017f030201000a0601040010000b", 1, c"WebAssembly execution limit", 0, 100000)
	wasm_validation_case(c"zero fuel", c"0061736d010000000105016000017f030201000a0601040041000b", 1, c"WebAssembly execution limit", 0, 0)
	wasm_validation_case(c"negative fuel", c"0061736d010000000105016000017f030201000a0601040041000b", 1, c"WebAssembly execution limit", 0, -1)
	wasm_validation_case(c"explicit unreachable", c"0061736d010000000105016000017f030201000a05010300000b", 1, c"unreachable", 0, 100)
	wasm_validation_case(c"growth exceeds maximum", c"0061736d010000000105016000017f030201000504010101010a08010600410240000b", 1, c"", -1, 100)
	wasm_validation_case(c"negative growth cannot wrap", c"0061736d010000000105016000017f0302010005030100010a08010600417f40000b", 1, c"", -1, 100)
	wasm_validation_case(c"custom section missing name", c"0061736d010000000000", 0, c"", 0, 100)
	wasm_validation_case(c"custom section truncated name", c"0061736d0100000000020278", 0, c"", 0, 100)
	wasm_validation_case(c"custom section invalid UTF8 name", c"0061736d01000000000201ff", 0, c"", 0, 100)
	wasm_validation_case(c"memory maximum beyond wasm32 limit", c"0061736d010000000506010100818004", 0, c"", 0, 100)
	wasm_validation_case(c"indirect signature mismatch", c"0061736d010000000109026000017f6000017e030201000404017000010907010041000b01000a0a0108004100110100a70b", 1, c"indirect call type mismatch", 0, 100)
	wasm_validation_truncation()
	wasm_validation_host_reentry()
	wasm_validation_start_budget()
	wasm_validation_import_budget()
	wasm_validation_exports(4096, 0)
	wasm_validation_exports(4096, 1)
	wasm_validation_exports(20000, 0)
	wasm_validation_mutations()
	assert_equal(0, wasm_validation_failures)
	print_int(c"WebAssembly adversarial binary cases: ", wasm_validation_cases)
	println(c"WebAssembly truncation, host reentry and shared start fuel: OK")
	return 0
