import lib.assert
import win.browser

void fixed_host_eval(win_script* script, char* source):
	if (win_script_eval(script, source, strlen(source)) == 0):
		println(script.error)
		char* error = win_js_text(script.runtime.completion.value)
		println(error)
		free(error)
		asserts(c"fixed geometry host script succeeds", 0)

int main():
	char* source = c"<style>body{margin:0}</style><div style='height:1000px'></div><div id='fixed'>text</div>"
	win_page* page = win_page_parse(source, strlen(source))
	win_script* script = win_script_new(page)
	win_browser browser
	browser.page = page
	browser.script = script
	browser.interactive = 0
	browser.viewport_width = 400
	browser.viewport_height = 300
	browser.width = 388
	browser.scroll.offset_y = 0.0
	win_browser_sync_viewport(&browser)
	fixed_host_eval(script, c"const fixed=document.getElementById('fixed'); fixed.style.position='fixed'; fixed.style.left='25px'; fixed.style.top='30px'; fixed.style.width='100px'; fixed.style.height='40px'; if(!('position' in fixed.style)||!('bottom' in fixed.style)||fixed.style.left!=='25px'||fixed.style.getPropertyValue('top')!=='30px') throw 'native style properties'; let r=fixed.getBoundingClientRect(); if(r.x!==25||r.y!==30||r.width!==100||r.height!==40) throw 'initial fixed rect';")
	browser.scroll.offset_y = 120.0
	win_browser_sync_viewport(&browser)
	fixed_host_eval(script, c"r=fixed.getBoundingClientRect(); if(r.x!==25||r.y!==30) throw 'scrolled fixed rect'; fixed.style.left='auto'; fixed.style.top='auto'; fixed.style.right='10px'; fixed.style.bottom='20px'; r=fixed.getBoundingClientRect(); if(r.x!==290||r.y!==240) throw 'right bottom fixed rect';")
	browser.viewport_width = 600
	browser.viewport_height = 500
	browser.width = 588
	win_browser_sync_viewport(&browser)
	fixed_host_eval(script, c"r=fixed.getBoundingClientRect(); if(r.x!==490||r.y!==440) throw 'resized fixed rect'; fixed.style.position='sticky'; if(fixed.style.position!=='fixed') throw 'unsupported position overwrote valid declaration';")
	asserts(c"native hit uses the same fixed rect", strcmp(win_attr(win_browser_node_hit(page, 491.0, 561.0), c"id"), c"fixed") == 0)
	fixed_host_eval(script, c"fixed.setAttribute('tabindex','0'); fixed.style.bottom='auto'; fixed.style.top='900px'; fixed.focus(); fixed.getBoundingClientRect();")
	win_browser_focus_scroll(&browser, ui_rect_new(0.0, 0.0, 600.0, 500.0))
	asserts(c"offscreen fixed focus cannot be revealed by scrolling the document", browser.scroll.offset_y == 120.0)
	win_script_free(script)
	win_page_free(page)
	println(c"Fixed CSSOM, viewport rectangles, resize and native hit coordinates: OK")
	return 0
