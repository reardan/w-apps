import lib.assert
import win.browser

int main():
	win_browser browser
	win_browser_init(&browser, c"unused", c"unused")
	char* html = c"<p>bounded history</p>"
	browser.page = win_page_parse(html, strlen(html))
	browser.document_generation = 1
	browser.script = win_script_new(browser.page)
	win_commit_address(&browser, c"http://example.test/", -1)
	win_script_bind_storage(browser.script, browser.local_storage, browser.session_storage, browser.address)
	win_browser_history_install(&browser)
	# One entry fits exactly; a second cannot fit and must leave state intact.
	browser.history_wire_limit = 28 + strlen(browser.address) + 4
	char* source = c"let old=history.state; try{history.pushState({x:1},'','?new');throw 'accepted';}catch(e){if(e.name!=='QuotaExceededError')throw e;} if(history.length!==1||history.state!==old||location.search!=='')throw 'partial mutation'; try{history.replaceState('longer than null','');throw 'accepted';}catch(e){if(e.name!=='QuotaExceededError')throw e;} if(history.state!==old)throw 'partial replace';"
	win_script_eval(browser.script, source, strlen(source))
	assert_equal(0, browser.script.failures)
	assert_equal(1, browser.history.length)
	win_navigate(&browser, c"#fragment", browser.address, -1)
	assert_equal(1, browser.history.length)
	assert_strings_equal(c"http://example.test/", browser.address)
	assert_strings_equal(c"Isolated history metadata limit reached", browser.status)
	# Same-size replacement remains usable after a rejected mutation.
	source = c"history.replaceState(null,''); if(history.state!==null||history.length!==1)throw 'recovery';"
	win_script_eval(browser.script, source, strlen(source))
	assert_equal(0, browser.script.failures)
	win_browser_free(&browser)
	win_network_state_clear()
	assert_equal(0, debug_alloc_report_leaks())
	println(c"Isolated history aggregate quota is atomic for mutation and fragments: OK")
	return 0
