import lib.assert
import win.script

void string_timer_eval(win_script* script, char* source):
	int ok = win_script_eval(script, source, strlen(source))
	if (ok == 0): println(script.error)
	asserts(c"string timer contract", ok)

int main():
	win_page* page = win_page_parse(c"<body></body>", 13)
	win_script* script = win_script_new(page)
	win_script_set_clock(script, 1000)
	string_timer_eval(script, c"var order='';function register(){let local='wrong';setTimeout({toString:function(){order+='s';setTimeout(\"order+='i';\",5);return \"var timerGlobal=7;order+='o';\";}},{valueOf:function(){order+='d';return 5;}},'ignored');}register();if(order!=='sd')throw 'conversion order';")
	assert_equal(2, script.timers.length)
	asserts(c"native sources retained", script.timer_source_bytes > 0)
	js_runtime_collect(script.runtime)
	assert_equal(0, win_script_poll_at(script, 1004))
	assert_equal(2, win_script_poll_at(script, 1005))
	assert_equal(0, script.timer_source_bytes)
	string_timer_eval(script, c"if(order!=='sdio'||timerGlobal!==7||window.timerGlobal!==7)throw 'global script';let same={};let caught=false;try{setTimeout({toString:function(){throw same;}},0);}catch(e){caught=e===same;}if(!caught)throw 'conversion exception';caught=false;try{setTimeout('order+=1',{valueOf:function(){throw same;}});}catch(e){caught=e===same;}if(!caught)throw 'delay exception';const canceled=setTimeout('order+=2',0);clearTimeout(canceled);")
	assert_equal(0, script.timer_source_bytes)
	assert_equal(0, script.timers.length)
	string_timer_eval(script, c"var repeats=0;var stringInterval=setInterval('repeats++;if(repeats===2)clearInterval(stringInterval);',0);setTimeout('',0);setTimeout(undefined,0);")
	assert_equal(3, win_script_poll_at(script, 1005))
	assert_equal(1, win_script_poll_at(script, 1005))
	assert_equal(0, script.timer_source_bytes)
	assert_equal(0, script.timers.length)
	string_timer_eval(script, c"if(repeats!==2)throw 'interval';var token={};var reported=0;onerror=function(message,url,line,column,error){if(error!==token)throw 'identity';reported++;return true;};setTimeout('throw token;',0);setTimeout('order+=\"z\";',0);")
	assert_equal(2, win_script_poll_at(script, 1005))
	string_timer_eval(script, c"if(reported!==1||order!=='sdioz')throw 'reporting';")
	assert_equal(1, script.failures)
	assert_equal(1, script.reported_exceptions)
	# A registration budget failure owns no source and consumes no task id.
	int ids = script.timer_id
	script.timer_source_bytes = 4194304
	char* rejected = c"setTimeout('order+=3',0);"
	assert_equal(0, win_script_eval(script, rejected, strlen(rejected)))
	assert_equal(5, script.runtime.completion.status)
	assert_equal(ids, script.timer_id)
	assert_equal(0, script.timers.length)
	script.timer_source_bytes = 0
	string_timer_eval(script, c"setTimeout('while(true){}',0);setTimeout('order+=4',0);")
	script.execution_budget = 1000
	assert_equal(1, win_script_poll_at(script, 1005))
	assert_equal(5, script.runtime.completion.status)
	win_script_stop(script)
	assert_equal(0, script.timer_source_bytes)
	# Repeated source execution retains the runtime AST budget; no wrapper bypass.
	string_timer_eval(script, c"setInterval('var bounded=1;',0);")
	script.runtime.max_scripts = script.runtime.scripts.length
	assert_equal(1, win_script_poll_at(script, 1005))
	assert_equal(5, script.runtime.completion.status)
	win_script_stop(script)
	assert_equal(0, script.timer_source_bytes)
	win_script_free(script)
	win_page_free(page)
	println(c"String timer coercion, global execution, cancellation, error identity and bounded fuel: OK")
	return 0
