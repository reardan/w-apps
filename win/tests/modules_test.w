import lib.assert
import lib.file
import win.modules

void module_source(win_modules* context, char* identifier, char* source):
	assert1(win_modules_add_inline(context, identifier, identifier, source, strlen(source)) != 0)

void module_js(js_runtime* rt, char* source):
	js_completion* result = js_runtime_eval(rt, source, strlen(source), 100000)
	if (result.status != 0): println(result.message)
	assert_equal(0, result.status)

void test_module_graph():
	js_runtime* rt = js_runtime_new()
	win_modules* context = win_modules_new(rt, c"/missing-loader", c"/site/index.html")
	module_source(context, c"/site/dep.mjs", c"export function answer({n = 40} = {}) { return n + 2; }")
	module_source(context, c"/site/root.mjs", c"import {answer} from './dep.mjs'; export const value = answer();")
	assert_equal(1, win_modules_poll(context))
	assert1(context.error == 0)
	js_module* root = win_modules_evaluate(context, c"/site/root.mjs", 100000)
	assert1(root != 0)
	assert1(js_modules_export(context.engine, root, c"value").number == 42.0)
	assert1(win_modules_evaluate(context, c"/site/root.mjs", 100000) == root)
	char* bare = win_modules_resolve(context, c"package", c"/site/root.mjs")
	assert1(bare == 0)
	win_modules_stop(context)
	assert1(win_modules_evaluate(context, c"/site/root.mjs", 100000) == 0)
	win_modules_free(context)
	js_runtime_free(rt)

void test_module_limits():
	js_runtime* rt = js_runtime_new()
	win_modules* context = win_modules_new(rt, c"/missing-loader", c"https://example.test/page")
	assert1(win_modules_resolve(context, c"https://other.test/a.mjs", context.address) == 0)
	assert1(win_modules_resolve(context, c"http://example.test/a.mjs", context.address) == 0)
	context.engine.max_bytes = 2
	assert1(win_modules_add_inline(context, c"inline", context.address, c"abc", 3) == 0)
	assert1(context.error != 0)
	assert_equal(1, win_modules_poll(context))
	win_modules_free(context)
	js_runtime_free(rt)

void test_unchanged_hosts():
	js_runtime* rt = js_runtime_new()
	win_modules* context = win_modules_new(rt, c"/missing-loader", c"/host/index.html")
	char* accessibility = file_read_text(c"w/tools/web/accessibility.mjs")
	char* webgl = file_read_text(c"w/tools/web/webgl_env.mjs")
	char* mobile = file_read_text(c"w/tools/web/mobile_input.mjs")
	assert1(accessibility != 0 && webgl != 0 && mobile != 0)
	module_source(context, c"/host/accessibility.mjs", accessibility)
	module_source(context, c"/host/webgl_env.mjs", webgl)
	module_source(context, c"/host/mobile_input.mjs", mobile)
	free(accessibility)
	free(webgl)
	free(mobile)
	assert_equal(1, win_modules_poll(context))
	assert1(context.error == 0)
	js_module* gl = win_modules_evaluate(context, c"/host/webgl_env.mjs", 1000000)
	if (gl == 0): println(rt.completion.message)
	assert1(gl != 0)
	js_runtime_set(rt, rt.global, c"makeEnv", js_modules_export(context.engine, gl, c"makeEnv"))
	module_js(rt, c"let cleared=0; const env=makeEnv({memory:()=>({buffer:new ArrayBuffer(65536)}),gl:{clear(mask){cleared=mask;}},host:{},log:()=>{}}); env.glClear(0x4000); if(cleared!==0x4000) throw 'clear'; if(env.gfx_access_begin(1,2,3)!==0) throw 'access';")
	js_module* input = win_modules_evaluate(context, c"/host/mobile_input.mjs", 1000000)
	assert1(input != 0)
	js_runtime_set(rt, rt.global, c"createEventQueue", js_modules_export(context.engine, input, c"createEventQueue"))
	module_js(rt, c"const queue=createEventQueue(); queue.push(3,65,0,0,0); queue.beginFrame(); if(queue.next().code!==65 || queue.next()!==null) throw 'queue'; queue.push(3,66,0,0,0); if(queue.next().code!==66) throw 'reused';")
	win_modules_free(context)
	js_runtime_free(rt)

int main():
	test_module_graph()
	test_module_limits()
	test_unchanged_hosts()
	println(c"module tests passed")
	return 0
