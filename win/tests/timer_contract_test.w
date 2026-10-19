import lib.assert
import win.script

void timer_eval(win_script* script, char* source):
	int ok = win_script_eval(script, source, strlen(source))
	if (ok == 0): println(script.error)
	asserts(c"timer contract", ok)

void timer_quota(win_script* script, int allowance):
	js_runtime* rt = script.runtime
	list[js_value*] args = new list[js_value*]
	args.push(js_runtime_number(rt, 0.0))
	args.push(js_runtime_get(rt, rt.global, c"callback"))
	args.push(js_runtime_number(rt, 0.0))
	args.push(rt.undefined_value)
	int values = rt.max_values
	int properties = rt.max_properties
	int roots = rt.roots.length
	int ids = script.timer_id
	int count = script.timers.length
	if (allowance >= 0): rt.max_values = rt.heap.length + allowance
	else: rt.max_properties = 1
	rt.remaining = 100000
	win_script* previous = win_active_script
	win_active_script = script
	win_script_timer_host(rt, args)
	win_active_script = previous
	assert_equal(5, rt.completion.status)
	assert_equal(roots, rt.roots.length)
	assert_equal(ids, script.timer_id)
	assert_equal(count, script.timers.length)
	rt.max_values = values
	rt.max_properties = properties
	rt.completion.status = 0
	rt.completion.value = rt.undefined_value
	__w_list_free(cast(__w_list*, args))
	timer_eval(script, c"var retry=setTimeout(callback,0);clearTimeout(retry);")
	assert_equal(roots, rt.roots.length)

int main():
	win_page* page = win_page_parse(c"<body></body>", 13)
	win_script* script = win_script_new(page)
	# Simulate an old task timestamp; real registration must sample current time.
	script.now_ms = 0
	int before = time_monotonic_ms()
	timer_eval(script, c"var hits=0;function callback(){hits++;}const real=setTimeout(callback,50);")
	int after = time_monotonic_ms()
	assert_equal(1, script.timers.length)
	asserts(c"registration clock lower bound", script.timers[0].due >= before + 50)
	asserts(c"registration clock upper bound", script.timers[0].due <= after + 50)
	timer_eval(script, c"clearTimeout(real);")
	win_script_set_clock(script, 1000)
	timer_eval(script, c"let order='';setTimeout(function(){'use strict';if(arguments.length!==0)throw 'padded';order+='a';},'5');setTimeout(function(a,b,c,d,e){'use strict';if(arguments.length!==5||e!==5)throw 'truncated';order+='b';},4294967301,1,2,3,4,5);setTimeout(function(){order+='c';},2147483648);const canceled=setTimeout(callback,0);clearTimeout({valueOf:function(){return canceled;}});")
	assert_equal(1, win_script_poll_at(script, 1000))
	assert_equal(0, win_script_poll_at(script, 1004))
	assert_equal(2, win_script_poll_at(script, 1005))
	assert_equal(0, script.failures)
	timer_eval(script, c"if(order!=='cab'||hits!==0)throw 'long conversion';let converted=0;setTimeout(function(){order+='d';},{valueOf:function(){converted++;return 2;}});if(converted!==1)throw 'conversion';")
	assert_equal(0, win_script_poll_at(script, 1006))
	assert_equal(1, win_script_poll_at(script, 1007))
	timer_eval(script, c"let caught=false;try{setTimeout(callback,{valueOf:function(){throw 'delay';}});}catch(e){caught=e==='delay';}if(!caught)throw 'lost exception';")
	timer_quota(script, 0)
	timer_quota(script, 1)
	timer_quota(script, -1)
	timer_eval(script, c"let setters=0;Object.defineProperty(Object.prototype,'callback',{set:function(){setters++;},configurable:true});const safe=setTimeout(callback,0);clearTimeout(safe);delete Object.prototype.callback;if(setters!==0)throw 'private setter';")
	assert_equal(0, script.failures)
	int ids = script.timer_id
	char* reentry = c"for(let i=0;i<255;i++){setTimeout(callback,0);}setTimeout(callback,{valueOf:function(){setTimeout(callback,0);return 0;}});"
	assert_equal(0, win_script_eval(script, reentry, strlen(reentry)))
	assert_equal(5, script.runtime.completion.status)
	assert_equal(256, script.timers.length)
	assert_equal(ids + 256, script.timer_id)
	win_script_stop(script)
	assert_equal(0, script.timers.length)
	win_script_free(script)
	win_page_free(page)
	println(c"Timer registration clock, Web IDL delay, arguments and quota rollback: OK")
	return 0
