import lib.assert
import win.wasm

void wasm_eval(js_runtime* rt, char* source):
	js_completion* result = js_runtime_eval(rt, source, strlen(source), 1000000)
	if (result.status != 0):
		print(result.message)
		print(c"\n")
	assert_equal(0, result.status)

void wasm_expect(js_runtime* rt, char* source):
	wasm_eval(rt, source)
	asserts(source, js_runtime_truth(rt.completion.value))

void wasm_js_test():
	js_runtime* rt = js_runtime_new()
	win_wasm_realm* realm = win_wasm_install(rt)
	wasm_expect(rt, c"let mem = new WebAssembly.Memory({initial:1,maximum:2}); let old = mem.buffer; let view = new Uint8Array(old); view[8]=42; mem.grow(1) === 1 && old.byteLength === 0 && view.length === 0 && mem.buffer.byteLength === 131072 && new Uint8Array(mem.buffer)[8] === 42;")
	wasm_expect(rt, c"let current = mem.buffer; mem.grow(0) === 2 && current.byteLength === 0;")
	wasm_expect(rt, c"let growthError = false; try { mem.grow(1); } catch(e) { growthError=e.name==='RangeError'; } growthError && mem.buffer.byteLength === 131072;")
	# [] -> i32 function exported as f returns 42.
	wasm_expect(rt, c"let bytes = new Uint8Array([0,97,115,109,1,0,0,0,1,5,1,96,0,1,127,3,2,1,0,7,5,1,1,102,0,0,10,6,1,4,0,65,42,11]); let mod = new WebAssembly.Module(bytes); let ins = new WebAssembly.Instance(mod); WebAssembly.validate(bytes) && ins.exports.f() === 42;")
	wasm_expect(rt, c"let bad = new Uint8Array([0,97,115,109,1,0,0,0,1,5,1,96,0,1,125,3,2,1,0,10,6,1,4,0,65,42,11]); !WebAssembly.validate(bad);")
	wasm_expect(rt, c"let compileError = false; try { new WebAssembly.Module(bad); } catch(e) { compileError = e.name==='CompileError'; } compileError;")
	wasm_eval(rt, c"let asynchronous = 0; WebAssembly.instantiate(bytes).then(function(pair) { asynchronous = pair.instance.exports.f(); });")
	assert_equal(0, js_runtime_drain_microtasks(rt, 1000000).status)
	wasm_expect(rt, c"asynchronous === 42;")
	wasm_eval(rt, c"let streaming = 0; WebAssembly.instantiateStreaming(Promise.resolve({arrayBuffer:function(){return Promise.resolve(bytes.buffer);}})).then(function(pair){streaming=pair.instance.exports.f();});")
	assert_equal(0, js_runtime_drain_microtasks(rt, 1000000).status)
	wasm_expect(rt, c"streaming === 42;")
	# Import+export roundtrip of signed i64, preserving precision and type.
	wasm_expect(rt, c"let wideBytes=new Uint8Array([0,97,115,109,1,0,0,0,1,6,1,96,1,126,1,126,2,7,1,1,101,1,102,0,0,3,2,1,0,7,5,1,1,102,0,1,10,8,1,6,0,32,0,16,0,11]); let wideType=''; let wide=new WebAssembly.Instance(new WebAssembly.Module(wideBytes),{e:{f:function(x){wideType=typeof x;return x;}}}); let huge=BigInt('9007199254740993'); wide.exports.f(huge) === huge && wideType === 'bigint';")
	wasm_expect(rt, c"let numberRejected=false; try{wide.exports.f(1);}catch(e){numberRejected=e.name==='TypeError';} numberRejected;")
	wasm_expect(rt, c"let negative=BigInt('-9223372036854775808'); wide.exports.f(negative) === negative;")
	win_wasm_free(realm)
	js_runtime_free(rt)

void wasm_allocation_test():
	js_runtime* rt = js_runtime_new()
	win_wasm_realm* realm = win_wasm_install(rt)
	wwasm* machine = wwasm_load(c"\x00asm\x01\x00\x00\x00", 8)
	rt.max_values = rt.heap.length
	int objects = realm.objects.length
	int methods = realm.methods.length
	assert1(win_wasm_object_new(realm, machine, 2, 0) == 0)
	assert_equal(objects, realm.objects.length)
	assert_equal(0, rt.undefined_value.host_get)
	rt.completion.status = 0
	assert1(win_wasm_method_new(realm, 0, 1, 0, 0) == rt.undefined_value)
	assert_equal(methods, realm.methods.length)
	wwasm_free(machine)
	win_wasm_free(realm)
	js_runtime_free(rt)

void wasm_aggregate_test():
	js_runtime* rt = js_runtime_new()
	win_wasm_realm* realm = win_wasm_install(rt)
	wasm_expect(rt, c"let a = new WebAssembly.Memory({initial:256}); let b = new WebAssembly.Memory({initial:256}); let c = new WebAssembly.Memory({initial:256}); let d = new WebAssembly.Memory({initial:256}); let bounded = false; try {new WebAssembly.Memory({initial:1});} catch(e) {bounded=e.name==='RangeError';} bounded;")
	assert_equal(1024, realm.pages)
	win_wasm_free(realm)
	js_runtime_free(rt)

int main():
	wasm_js_test()
	wasm_allocation_test()
	wasm_aggregate_test()
	print(c"wasm_test: OK\n")
	return 0
