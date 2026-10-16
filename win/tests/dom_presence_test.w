import lib.assert
import win.script
import win.fetch

int main():
	char* html = c"<body><div id='div'></div><input id='input' type='number'><textarea id='text'></textarea><canvas id='canvas'></canvas></body>"
	win_page* page = win_page_parse(html, strlen(html))
	win_script* script = win_script_new(page)
	char* source = c"const div=document.getElementById('div');const input=document.getElementById('input');const text=document.getElementById('text');const canvas=document.getElementById('canvas');if(!('value' in input)||!('selectionStart' in input)||input.selectionStart!==null||!('selectionDirection' in text)||!('readOnly' in text)||('selectionStart' in div)||('readOnly' in div))throw 'control presence';if(!('width' in canvas)||!('height' in canvas)||('width' in div)||!('tabIndex' in div)||!('focus' in div)||!('setPointerCapture' in canvas))throw 'element presence';if(!('activeElement' in document)||!('readyState' in document)||!('title' in document)||('activeElement' in div))throw 'document presence';if(!('innerWidth' in window)||!('pageYOffset' in window)||!('Event' in window)||('visualViewport' in window)||('value' in window))throw 'window presence';if(!('cssText' in div.style)||!('display' in div.style)||!('getPropertyValue' in div.style)||('transform' in div.style))throw 'style presence';const computed=getComputedStyle(div);if(!('paddingTop' in computed)||!('padding-top' in computed)||!('fontSize' in computed)||('transform' in computed)||!('getPropertyValue' in computed))throw 'computed presence';let reads=0;function getter(){reads++;throw 'getter invoked';}div.expando=undefined;if(!('expando' in div))throw 'undefined expando';if(!('search' in location)||!('href' in location)||('host' in location)||!('length' in localStorage)||!('getItem' in localStorage))throw 'location/storage presence';const controller=new AbortController();if(!('reason' in controller.signal)||!('aborted' in controller.signal)||!('onabort' in controller.signal)||!('throwIfAborted' in controller.signal)||('timeout' in controller.signal))throw 'signal presence';const event=new Event('x');if(!('type' in event)||!('preventDefault' in event)||('pointerId' in event))throw 'Event descriptors';"
	int ok = win_script_eval(script, source, strlen(source))
	if (ok == 0): println(script.error)
	asserts(c"DOM property presence", ok)
	js_runtime* rt = script.runtime
	js_text* accessor_key = js_runtime_key(c"accessor")
	asserts(c"install ordinary native test descriptor", js_runtime_define_accessor(rt, js_runtime_get(rt, rt.global, c"div"), accessor_key, js_runtime_get(rt, rt.global, c"getter"), 0, 0, 1))
	js_text_free(accessor_key)
	char* accessors = c"if(!('accessor' in div)||('absent' in div)||reads!==0)throw 'ordinary descriptor presence';"
	asserts(c"presence skips getters", win_script_eval(script, accessors, strlen(accessors)))
	# Response presence is independent of its live body consumption state.
	win_fetch_request request
	request.consumed = 0
	request.status = 200
	request.response = js_runtime_alloc(rt, 5)
	js_runtime_root(rt, request.response)
	js_runtime_set_host_hooks(rt, request.response, &request, win_fetch_response_get, 0)
	js_runtime_set_host_has(rt, request.response, win_fetch_response_has)
	js_runtime_set(rt, rt.global, c"response", request.response)
	char* response_test = c"if(!('bodyUsed' in response)||!('status' in response)||!('ok' in response)||('headers' in response)||response.bodyUsed)throw 'response presence';"
	asserts(c"response native presence", win_script_eval(script, response_test, strlen(response_test)))
	request.consumed = 1
	char* consumed = c"if(!('bodyUsed' in response)||!response.bodyUsed)throw 'consumed presence';"
	asserts(c"consumed response presence", win_script_eval(script, consumed, strlen(consumed)))
	js_runtime_unroot(rt, request.response)
	# Presence of a layout-backed property must not flush layout.
	page.width = 123
	script.dirty = 1
	char* geometry = c"if(!('offsetWidth' in div)||!('clientHeight' in canvas)||!('paddingTop' in computed))throw 'geometry presence';"
	asserts(c"presence without layout effects", win_script_eval(script, geometry, strlen(geometry)))
	assert_equal(123, page.width)
	assert_equal(0, script.failures)
	win_script_free(script)
	win_page_free(page)
	println(c"Win DOM, CSS and Event property presence without getter effects: OK")
	return 0
