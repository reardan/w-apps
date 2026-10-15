import lib.assert
import win.script

void animation_eval(win_script* script, char* source):
	int ok = win_script_eval(script, source, strlen(source))
	if (ok == 0): println(script.error)
	assert_equal(1, ok)

int main():
	char* html = c"<p>frames</p>"
	win_page* page = win_page_parse(html, strlen(html))
	win_script* script = win_script_new(page)
	int origin = script.time_origin
	animation_eval(script, c"let order=''; let first=-1; let second=-1; let nested=0; const canceled=requestAnimationFrame(function(){throw 'canceled';}); cancelAnimationFrame(canceled); requestAnimationFrame(function(t){first=t; order+='a'; Promise.resolve().then(function(){order+='m';}); requestAnimationFrame(function(){nested++;});}); window.requestAnimationFrame(function(t){second=t; order+='b';});")
	win_script_poll_at(script, origin + 10)
	animation_eval(script, c"if(order!=='') throw 'poll ran frame';")
	assert_equal(2, win_script_frame_at(script, origin + 16))
	animation_eval(script, c"if(order!=='amb' || first!==16 || second!==16 || nested!==0) throw 'frame snapshot';")
	assert_equal(1, win_script_frame_at(script, origin + 32))
	animation_eval(script, c"if(nested!==1) throw 'nested frame'; let other=0; requestAnimationFrame(function(){cancelAnimationFrame(other);}); other=requestAnimationFrame(function(){throw 'late cancellation';});")
	assert_equal(1, win_script_frame_at(script, origin + 48))
	animation_eval(script, c"requestAnimationFrame(function(t){if(t!==48) throw 'clock reversal';});")
	assert_equal(1, win_script_frame_at(script, origin + 40))
	animation_eval(script, c"requestAnimationFrame(function(){throw 'stop failed';});")
	win_script_stop(script)
	assert_equal(0, win_script_frame_at(script, origin + 64))
	assert_equal(0, script.failures)
	win_script_free(script)
	win_page_free(page)
	return 0
