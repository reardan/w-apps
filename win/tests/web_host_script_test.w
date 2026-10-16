# End-to-end JS host wiring: no direct web_host helper calls.
import lib.assert
import win.browser

void web_script_eval(win_script* script, char* source):
	int ok = win_script_eval(script, source, strlen(source))
	if (ok == 0): println(script.error)
	asserts(c"web host JS API", ok)

void test_web_script():
	char* html = c"<body><style id='sheet'>#wrap{padding:1em 3px 4px 5px!important}</style><div style='font-size:20px'><div id='wrap' style='width:100px;height:50px;border:2px solid'><canvas id='canvas' width=' +640junk' height=' 480 ' style='width:320px;height:240px'></canvas></div><span id='inline'>word</span></div></body>"
	win_page* page = win_page_parse(html, strlen(html))
	win_script* script = win_script_new(page)
	assert_equal(0, script.failures)
	win_script_bind_storage(script, 0, 0, c"https://example.test/app?module=demo%2Fapp.wasm&module=ignored#fragment")
	win_script_set_viewport(script, 800, 600, 1.5, 0.0, 10.0)
	web_script_eval(script, c"if(location!==window.location || document.location!==location || location.search!=='?module=demo%2Fapp.wasm&module=ignored') throw 'location'; if(new URLSearchParams(location.search).get('module')!=='demo/app.wasm') throw 'module'; if(window.URLSearchParams!==URLSearchParams) throw 'constructor alias'; const q=new URLSearchParams('?x=a+b%2Bc&empty&nul=%00&utf=%E2%82A'); if(q.get('x')!=='a b+c'||q.get('empty')!==''||q.get('missing')!==null||q.get('nul')!=='\\u0000'||q.get('utf')!=='�A') throw 'query';")
	web_script_eval(script, c"if(innerWidth!==800 || window.innerWidth!==innerWidth || innerHeight!==600 || window.innerHeight!==600 || devicePixelRatio!==1.5 || window.devicePixelRatio!==1.5 || scrollY!==10 || window.pageYOffset!==10) throw 'viewport'; if(typeof window.visualViewport!=='undefined') throw 'unsupported viewport';")
	web_script_eval(script, c"const wrap=document.getElementById('wrap'); const canvas=document.getElementById('canvas'); const computed=getComputedStyle(wrap); if(window.getComputedStyle!==getComputedStyle || computed.paddingTop!=='20px'||computed.paddingLeft!=='5px'||computed.getPropertyValue('padding-bottom')!=='4px'||computed.getPropertyValue('unsupported')!=='') throw 'computed'; if(canvas.width!==640 || canvas.height!==480) throw 'HTML dimensions'; const rect=canvas.getBoundingClientRect(); if(rect.width!==320 || rect.height!==240 || rect.right-rect.left!==320 || rect.bottom-rect.top!==240 || rect.x!==rect.left || rect.y!==rect.top) throw 'canvas CSS bounds';")
	web_script_eval(script, c"canvas.style.width='123px'; canvas.style.height='45px'; const changed=canvas.getBoundingClientRect(); if(changed.width!==123||changed.height!==45||rect.width!==320) throw 'synchronous sizing'; document.getElementById('sheet').textContent='#wrap{padding:7px 8px 9px 10px}'; if(computed.paddingTop!=='7px'||computed.paddingLeft!=='10px'||computed.getPropertyValue('padding-right')!=='8px') throw 'live cascade'; if(wrap.offsetWidth!==122||wrap.clientWidth!==118) throw 'DOM sizing';")
	win_script_set_viewport(script, 420, 300, 2.0, 0.0, 30.0)
	web_script_eval(script, c"if(innerWidth!==420||window.innerWidth!==420||innerHeight!==300||devicePixelRatio!==2||window.scrollY!==30) throw 'updated viewport'; canvas.remove(); const detached=canvas.getBoundingClientRect(); if(detached.width!==0||detached.height!==0||detached.x!==0) throw 'detached'; let invalid=false; try {getComputedStyle({});} catch(e) {invalid=true;} if(!invalid) throw 'invalid element';")
	# Prefix parsing agrees with layout's HTML nonnegative integer algorithm.
	web_script_eval(script, c"canvas.setAttribute('width','-1'); canvas.setAttribute('height','999999'); if(canvas.width!==300||canvas.height!==4096) throw 'attribute bounds'; if(typeof WebAssembly!=='object'||window.WebAssembly!==WebAssembly) throw 'wasm namespace';")
	assert_equal(0, script.failures)
	win_script_free(script)
	win_page_free(page)

void test_browser_initial_viewport():
	win_browser browser
	win_browser_init(&browser, c"", c"")
	win_browser_set_viewport(&browser, 720, 480)
	char* html = c"<body><script>if(innerWidth!==720||innerHeight!==480||window.innerWidth!==720||devicePixelRatio!==1) throw 'initial viewport'; if(new URLSearchParams(location.search).get('module')!=='ready.wasm') throw 'initial location'; document.title='startup passed';</script></body>"
	browser.page = win_page_parse(html, strlen(html))
	browser.script = win_script_new(browser.page)
	win_script_bind_storage(browser.script, 0, 0, c"https://example.test/?module=ready.wasm")
	win_browser_poll(&browser)
	assert_equal(0, browser.script.failures)
	assert_strings_equal(c"startup passed", browser.page.title)
	web_script_eval(browser.script, c"let resized=0; window.addEventListener('resize',function(){if(innerWidth!==500||window.innerWidth!==500||innerHeight!==350) throw 'resize values'; resized+=1;});")
	win_browser_set_viewport(&browser, 500, 350)
	web_script_eval(browser.script, c"if(resized!==1) throw 'resize delivery';")
	win_browser_set_viewport(&browser, 500, 350)
	web_script_eval(browser.script, c"if(resized!==1) throw 'duplicate resize';")
	win_browser_free(&browser)

int main():
	test_web_script()
	test_browser_initial_viewport()
	println(c"Win JS location, URLSearchParams, viewport, computed style, canvas and geometry APIs: OK")
	return 0
