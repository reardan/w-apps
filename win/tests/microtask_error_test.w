import lib.assert
import win.script

void error_eval(win_script* script, char* source):
	asserts(c"microtask exception setup", win_script_eval(script, source, strlen(source)))

int main():
	char* html = c"<body></body>"
	win_page* page = win_page_parse(html, strlen(html))
	win_script* script = win_script_new(page)
	error_eval(script, c"const thrown={marker:19};let trace='';let saved;addEventListener('error',function(ev){if(ev.error!==thrown||ev.type!=='error'||ev.target!==window||ev.currentTarget!==window||!ev.isTrusted||ev.bubbles||!ev.cancelable)throw 'event';saved=ev;trace+='e';ev.preventDefault();queueMicrotask(function(){trace+='c';});},{once:true});queueMicrotask(function(){throw thrown;});queueMicrotask(function(){trace+='b';});")
	assert_equal(1, script.failures)
	assert_equal(1, script.reported_exceptions)
	assert_equal(0, script.runtime.completion.status)
	js_runtime_collect(script.runtime)
	error_eval(script, c"if(trace!=='ebc'||saved.error!==thrown||!saved.defaultPrevented||saved.currentTarget!==null||saved.eventPhase!==0)throw 'completion';")
	# Promise handler throws become rejections, not Window error events.
	error_eval(script, c"let rejection;Promise.resolve().then(function(){throw thrown;}).catch(function(e){rejection=e;});")
	error_eval(script, c"if(rejection!==thrown)throw 'promise rejection';")
	assert_equal(1, script.failures)
	# Listener exceptions remain a separate unreported diagnostic.
	error_eval(script, c"addEventListener('error',function(){throw 'listener';},{once:true});queueMicrotask(function(){throw 7;});queueMicrotask(function(){trace+='d';});")
	assert_equal(3, script.failures)
	assert_equal(2, script.reported_exceptions)
	error_eval(script, c"if(trace!=='ebcd')throw 'remaining jobs';")
	# Error and event lifetime roots do not accumulate across checkpoints.
	int roots = script.runtime.roots.length
	for i in range(3): error_eval(script, c"queueMicrotask(function(){throw null;});")
	assert_equal(roots, script.runtime.roots.length)
	assert_equal(6, script.failures)
	assert_equal(5, script.reported_exceptions)
	# Window onerror receives its five legacy arguments and true cancels the event.
	error_eval(script, c"let handlerCalled=0;onerror=function(message,filename,line,column,error){if(arguments.length!==5||this!==window||typeof message!=='string'||filename!==''||line!==0||column!==0||error!==thrown)throw 'onerror arguments';handlerCalled++;return true;};queueMicrotask(function(){throw thrown;});")
	error_eval(script, c"if(handlerCalled!==1)throw 'onerror call';onerror=null;")
	assert_equal(7, script.failures)
	assert_equal(6, script.reported_exceptions)
	# Construction defines own methods without prototype setters or write barriers.
	error_eval(script, c"let methodSetter=0;Object.defineProperty(Object.prototype,'preventDefault',{set:function(){methodSetter++;throw 'prototype setter';},configurable:true});Object.defineProperty(Object.prototype,'stopPropagation',{value:9,writable:false,configurable:true});const ownEvent=new Event('own',{cancelable:true});ownEvent.preventDefault();ownEvent.stopPropagation();if(methodSetter!==0||!ownEvent.defaultPrevented)throw 'event own methods';delete Object.prototype.preventDefault;delete Object.prototype.stopPropagation;")
	# An infinite chain of throwing jobs still shares one finite checkpoint budget.
	asserts(c"lower checkpoint budget", win_script_set_execution_budget(script, 3000))
	error_eval(script, c"function again(){queueMicrotask(again);throw 1;}queueMicrotask(again);")
	assert_equal(5, script.runtime.completion.status)
	asserts(c"bounded error reporting", script.reported_exceptions < 100)
	asserts(c"terminal limit remains unreported", script.failures > script.reported_exceptions)
	win_script_stop(script)
	win_script_free(script)
	win_page_free(page)
	# Event allocation refusal does not mark an undispatched error as reported,
	# remove a pre-existing host root, or replenish the execution budget.
	page = win_page_parse(html, strlen(html))
	script = win_script_new(page)
	js_value* retained = js_runtime_alloc(script.runtime, 5)
	js_runtime_root(script.runtime, retained)
	js_runtime_root(script.runtime, script.runtime.undefined_value)
	roots = script.runtime.roots.length
	js_runtime_throw(script.runtime, retained)
	script.runtime.max_values = script.runtime.heap.length
	script.runtime.remaining = 1000
	assert_equal(0, win_script_report_exception(script))
	assert_equal(5, script.runtime.completion.status)
	assert_equal(1, script.failures)
	assert_equal(0, script.reported_exceptions)
	assert_equal(roots, script.runtime.roots.length)
	int retained_root = 0
	for i in range(script.runtime.roots.length):
		if (script.runtime.roots[i] == retained): retained_root = 1
	asserts(c"preserve caller root after quota refusal", retained_root)
	assert_equal(0, script.runtime.undefined_value.host_get)
	assert_equal(0, script.runtime.undefined_value.host_has)
	assert_equal(0, cast(int, script.runtime.undefined_value.host_context))
	int undefined_root = 0
	for i in range(script.runtime.roots.length):
		if (script.runtime.roots[i] == script.runtime.undefined_value): undefined_root = 1
	asserts(c"preserve pre-existing undefined root", undefined_root)
	js_runtime_unroot(script.runtime, script.runtime.undefined_value)
	js_runtime_unroot(script.runtime, retained)
	win_script_free(script)
	win_page_free(page)
	println(c"Microtask exception event identity, lifetime, continuation and shared fuel: OK")
	return 0
