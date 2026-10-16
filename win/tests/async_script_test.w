import lib.assert
import lib.args
import win.script

void async_eval(win_script* script, char* source):
	assert1(win_script_eval(script, source, strlen(source)))

win_script* pending_script():
	char* source = c"<title>initial</title><script type='module'>document.title='waiting'; await new Promise(resolve=>{window.resume=resolve;}); document.title='done';</script>"
	win_page* page = win_page_parse(source, strlen(source))
	win_script* script = win_script_new(page)
	script.modules = win_modules_new(script.runtime, c"/missing-loader", c"/site/index.html")
	win_script_run_pending(script, 0)
	assert_strings_equal(c"waiting", page.title)
	assert_equal(0, script.ready)
	assert_equal(0, script.dom_ready)
	assert_equal(0, script.next_script)
	assert_equal(1, script.runtime.async_tasks.length)
	return script

void release_script(win_script* script):
	win_page* page = script.page
	win_script_free(script)
	win_page_free(page)

void test_complete():
	win_script* script = pending_script()
	js_runtime_collect(script.runtime)
	async_eval(script, c"window.resume();")
	assert_equal(0, script.runtime.async_tasks.length)
	win_script_run_pending(script, 0)
	win_script_run_pending(script, 0)
	assert_strings_equal(c"done", script.page.title)
	assert1(script.ready && script.dom_ready)
	assert_equal(0, script.failures)
	release_script(script)
void test_stop():
	win_script* script = pending_script()
	win_script_stop(script)
	assert_equal(0, script.runtime.async_tasks.length)
	assert1(script.ready)
	async_eval(script, c"window.resume();")
	assert_strings_equal(c"waiting", script.page.title)
	release_script(script)

void test_free():
	# Free pending module frames before any host wrapper or canvas is released.
	win_script* script = pending_script()
	release_script(script)

void test_handler():
	char* source = c"<title>handler</title><button id='button'>Run</button>"
	win_page* page = win_page_parse(source, strlen(source))
	win_script* script = win_script_new(page)
	async_eval(script, c"document.getElementById('button').addEventListener('click', async function(){await new Promise(resolve=>{window.finish=resolve;}); document.title='late';}); document.getElementById('button').dispatchEvent(new Event('click'));")
	assert_equal(1, script.runtime.async_tasks.length)
	win_script_stop(script)
	assert_equal(0, script.runtime.async_tasks.length)
	async_eval(script, c"window.finish();")
	assert_strings_equal(c"handler", page.title)
	release_script(script)

int main(int argc, int argv):
	args_init(argc, argv)
	int selected = 0
	if (args_value(c"case") != 0): selected = atoi(args_value(c"case"))
	if (selected == 0 || selected == 1): test_complete()
	if (selected == 0 || selected == 2): test_stop()
	if (selected == 0 || selected == 3): test_free()
	if (selected == 0 || selected == 4): test_handler()
	if (malloc_debug_mode): assert_equal(0, debug_alloc_report_leaks())
	println(c"async browser lifecycle: OK")
	return 0
