import lib.assert
import win.script

void task_eval(win_script* script, char* source):
	int ok = win_script_eval(script, source, strlen(source))
	if (ok == 0): println(script.error)
	asserts(c"task exception setup", ok)

int main():
	char* html = c"<body></body>"
	win_page* page = win_page_parse(html, strlen(html))
	win_script* script = win_script_new(page)
	win_script_set_clock(script, 100)
	task_eval(script, c"const thrown={marker:23};let trace='',saved;addEventListener('error',function(e){if(e.error!==thrown||!e.isTrusted||e.target!==window)throw 'error identity';saved=e;e.preventDefault();trace+='e';queueMicrotask(function(){trace+='m';});},{once:true});setTimeout(function(){trace+='t';queueMicrotask(function(){trace+='q';});throw thrown;},0);setTimeout(function(){trace+='b';},0);")
	assert_equal(2, win_script_poll_at(script, 100))
	assert_equal(1, script.failures)
	assert_equal(1, script.reported_exceptions)
	js_runtime_collect(script.runtime)
	task_eval(script, c"if(trace!=='teqmb'||saved.error!==thrown||!saved.defaultPrevented)throw 'timer checkpoint';let repeated=0;const interval=setInterval(function(){repeated++;throw thrown;},0);onerror=function(message,file,line,column,error){if(error!==thrown)throw 'interval error';clearInterval(interval);return true;};")
	assert_equal(1, win_script_poll_at(script, 100))
	assert_equal(0, win_script_poll_at(script, 100))
	assert_equal(2, script.failures)
	assert_equal(2, script.reported_exceptions)
	task_eval(script, c"if(repeated!==1)throw 'interval cancellation';onerror=null;trace='';addEventListener('error',function(e){if(e.error!==thrown)throw 'frame identity';trace+='e';e.preventDefault();requestAnimationFrame(function(){trace+='n';});},{once:true});requestAnimationFrame(function(){trace+='a';queueMicrotask(function(){trace+='q';});throw thrown;});requestAnimationFrame(function(){trace+='b';});")
	assert_equal(2, win_script_frame_at(script, script.frame_time + 16))
	task_eval(script, c"if(trace!=='aeqb')throw 'frame continuation';")
	assert_equal(1, win_script_frame_at(script, script.frame_time + 16))
	task_eval(script, c"if(trace!=='aeqbn')throw 'next frame';")
	assert_equal(3, script.failures)
	assert_equal(3, script.reported_exceptions)
	# Error listeners consume the callback's remaining fuel and stop this batch.
	asserts(c"bounded task fuel", win_script_set_execution_budget(script, 3000))
	task_eval(script, c"let late=false;onerror=function(){while(true){}};setTimeout(function(){throw thrown;},0);setTimeout(function(){late=true;},0);")
	assert_equal(1, win_script_poll_at(script, 100))
	assert_equal(5, script.runtime.completion.status)
	assert_equal(3, script.reported_exceptions)
	asserts(c"terminal exception remains unreported", script.failures > script.reported_exceptions)
	task_eval(script, c"if(late)throw 'fuel was replenished';")
	win_script_stop(script)
	win_script_free(script)
	win_page_free(page)
	println(c"Timer and animation exception identity, continuation, cancellation and shared fuel: OK")
	return 0
