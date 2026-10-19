import lib.assert
import win.script

void window_eval(win_script* script, char* source):
	int ok = win_script_eval(script, source, strlen(source))
	if (ok == 0): println(script.error)
	asserts(c"Window global bindings", ok)

int main():
	char* html = c"<html><head><title>Globals</title></head><body><p id='p'>old</p></body></html>"
	win_page* page = win_page_parse(html, strlen(html))
	win_script* script = win_script_new(page)
	window_eval(script, c"if(self!==window||globalThis!==window||this!==window||parent!==window||top!==window||opener!==null)throw 'identity';if(window.Object!==Object||window.TypeError!==TypeError)throw 'intrinsics';self.exported=17;if(exported!==17)throw 'lookup';exported=18;if(window.exported!==18)throw 'write';")
	window_eval(script, c"let lexical=3;window.lexical=9;if(lexical!==3||window.lexical!==9)throw 'lexical';var reflected=4;function published(){return reflected;}if(window.reflected!==4||window.published!==published)throw 'declarations';window.reflected=8;if(published()!==8)throw 'live binding';")
	window_eval(script, c"const node=document.createElement('span');node.textContent='fresh';document.body.appendChild(node);if(node.ownerDocument!==document||node.textContent!=='fresh')throw 'host API';const tags=document.getElementsByTagName('span');if(tags.length!==1||tags[0]!==node)throw 'collection';")
	window_eval(script, c"var delivered=0;setTimeout(function(){window.delivered=1;document.getElementById('p').textContent='done';},0);")
	js_runtime_collect(script.runtime)
	win_script_poll_at(script, script.now_ms + 1)
	window_eval(script, c"if(delivered!==1||document.getElementById('p').textContent!=='done')throw 'timer roots';")
	win_script_set_viewport(script, 375, 667, 1.0, 0.0, 0.0)
	window_eval(script, c"if(innerWidth!==375||window.innerWidth!==375)throw 'viewport';")
	assert_equal(0, script.failures)
	win_script_free(script)
	win_page_free(page)
	println(c"Window identity, lexical precedence, global reflection and host callbacks: OK")
	return 0
