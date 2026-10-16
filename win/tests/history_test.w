import lib.assert
import win.browser

void history_eval(win_browser* browser, char* source):
	int before = browser.script.failures
	win_script_eval(browser.script, source, strlen(source))
	if (browser.script.failures != before):
		println2(browser.script.error)
		char* error = win_js_text(browser.script.runtime.completion.value)
		println2(error)
		free(error)
		js_value* message = js_runtime_get(browser.script.runtime, browser.script.runtime.completion.value, c"message")
		error = win_js_text(message)
		println2(error)
		free(error)
	assert_equal(before, browser.script.failures)

int main():
	win_browser browser
	win_browser_init(&browser, c"unused", c"unused")
	char* html = c"<title>History</title><body><p>Page</p></body>"
	browser.page = win_page_parse(html, strlen(html))
	browser.document_generation = 1
	browser.script = win_script_new(browser.page)
	win_commit_address(&browser, c"http://example.test/app?view=form", -1)
	win_script_bind_storage(browser.script, browser.local_storage, browser.session_storage, browser.address)
	win_browser_history_install(&browser)
	history_eval(&browser, c"if(history!==window.history||history.length!==1||history.state!==null)throw 'initial'; let source={view:'form',nested:[1,'a']}; history.replaceState(source,''); if(history.state===source||history.state.nested===source.nested||history.state.nested[1]!=='a'||history.state!==history.state)throw 'clone'; source.nested[0]=9; if(history.state.nested[0]!==1)throw 'snapshot'; history.pushState({view:'settings'},'', '?view=settings'); if(history.length!==2||location.search!=='?view=settings'||history.state.view!=='settings')throw 'push'; let events=0; window.addEventListener('popstate',e=>{events++;if(e.state!==history.state||e.target!==window||e.bubbles||e.cancelable||!e.isTrusted)throw 'event';}); history.back(); if(location.search!=='?view=settings'||events!==0)throw 'synchronous traversal';")
	win_script* realm = browser.script
	win_browser_history_poll(&browser)
	assert1(realm == browser.script)
	history_eval(&browser, c"if(location.search!=='?view=form'||history.state.view!=='form'||events!==1)throw 'back'; history.forward();")
	win_browser_history_poll(&browser)
	history_eval(&browser, c"if(location.search!=='?view=settings'||events!==2)throw 'forward'; history.go(-1); history.go(1);")
	win_browser_history_poll(&browser)
	history_eval(&browser, c"if(events!==3||location.search!=='?view=form')throw 'queue first';")
	win_browser_history_poll(&browser)
	history_eval(&browser, c"if(events!==4||location.search!=='?view=settings')throw 'queue second'; let kept=history.state; try{history.pushState({},'', 'https://foreign.test/');throw 'accepted';}catch(e){if(e.name!=='SecurityError')throw e;} if(history.state!==kept||history.length!==2)throw 'failed mutation'; let cyclic={};cyclic.x=cyclic; for(const bad of [()=>0,cyclic,{x:undefined},NaN,-0]){try{history.replaceState(bad,'');throw 'accepted';}catch(e){if(e.name!=='DataCloneError')throw e;}} if(history.state!==kept)throw 'failed clone'; history.replaceState(undefined,'',null); if(history.state!==undefined||history.length!==2)throw 'undefined'; history.go(-99);")
	win_browser_history_poll(&browser)
	history_eval(&browser, c"if(events!==4)throw 'outside'; history.back();")
	win_browser_history_poll(&browser)
	history_eval(&browser, c"history.pushState({view:'new'},'', '?view=new'); if(history.length!==2||history.state.view!=='new')throw 'truncate forward';")
	# Bounded entry eviction must preserve current state and release old data.
	history_eval(&browser, c"for(let i=0;i<140;i++){history.pushState({n:i},'','?n='+String(i));} if(history.length!==128||history.state.n!==139)throw 'eviction';")
	assert_equal(127, browser.current)
	assert_equal(0, browser.script.failures)
	win_browser_free(&browser)
	win_network_state_clear()
	println(c"History same-document URLs, cloned state, queued traversal and bounds: OK")
	return 0
