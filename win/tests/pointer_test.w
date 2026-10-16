# Headless native queue tests; use real browser hit testing and viewport offsets.
import lib.assert
import win.app

void pointer_eval(win_script* script, char* source):
	int ok = win_script_eval(script, source, strlen(source))
	if (ok == 0): println(script.error)
	asserts(c"native pointer bridge", ok)

void pointer_feed(win_browser* browser, ui_context* ctx, int kind, int code, int x, int y, int mods):
	gfx_event event
	event.kind = kind
	event.code = code
	event.x = x
	event.y = y
	event.mods = mods
	ctx.input.mouse_x = x
	ctx.input.mouse_y = y
	ui_feed_event(ctx, &event)
	win_native_push(&browser.native_input, &event)

int main():
	win_browser browser
	win_browser_init(&browser, c"unused", c"unused")
	char* html = c"<body style='margin:0'><canvas id='canvas' width='200' height='100'></canvas><div id='other' style='height:100px'>other</div></body>"
	browser.page = win_page_parse(html, strlen(html))
	browser.script = win_script_new(browser.page)
	win_page_layout(browser.page, 400)
	win_script_set_viewport(browser.script, 400, 300, 1.0, 0.0, 0.0)
	ui_renderer renderer
	ui_render_init_headless(&renderer)
	ui_theme theme
	ui_theme_light(&theme)
	ui_context ctx
	ui_context_init(&ctx, &renderer, &theme)
	ui_rect viewport = ui_rect_new(12.0, 138.0, 400.0, 300.0)
	pointer_eval(browser.script, c"const canvas=document.getElementById('canvas');const other=document.getElementById('other');let order='';let seen=null;let unexpected=0;try {canvas.setPointerCapture(1);}catch(e){if(e.name==='NotFoundError')unexpected++;}if(unexpected!==1 || canvas.hasPointerCapture(1))throw 'inactive pointer';canvas.addEventListener('pointerdown',function(e){order+='D';seen=e;if(!e.isTrusted||e.pointerId!==1||e.pointerType!=='mouse'||!e.isPrimary||e.button!==0||e.buttons!==1||e.clientX!==38||e.clientY!==40||!e.shiftKey||e.ctrlKey)throw 'native fields';canvas.setPointerCapture(e.pointerId);if(!canvas.hasPointerCapture(1))throw 'pending capture';});canvas.addEventListener('gotpointercapture',function(e){order+='G';if(e.target!==canvas||e.cancelable)throw 'got capture';});canvas.addEventListener('pointermove',function(e){order+='M';if(e.target!==canvas)throw 'captured move target';});canvas.addEventListener('pointerup',function(e){order+='U';if(e.target!==canvas||e.buttons!==0||e.button!==0)throw 'captured up';canvas.releasePointerCapture(1);});canvas.addEventListener('lostpointercapture',function(e){order+='L';if(canvas.hasPointerCapture(1)||e.cancelable)throw 'lost capture';});")
	assert_strings_equal(c"canvas", win_browser_pointer_hit(&browser, viewport, 50, 178).name)
	pointer_feed(&browser, &ctx, GFX_EVENT_MOUSE_DOWN, 1, 50, 178, GFX_MOD_SHIFT)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	pointer_eval(browser.script, c"document.title=order;")
	assert_strings_equal(c"D", browser.page.title)
	pointer_eval(browser.script, c"if(order!=='D'||seen.currentTarget!==null)throw new Error('native down order='+order+' target='+String(seen));")
	ctx.input.mouse_x = 500
	ctx.input.mouse_y = 500
	win_browser_pointer_frame(&browser, &ctx, viewport)
	pointer_eval(browser.script, c"if(order!=='DGM')throw 'capture before outside motion';")
	pointer_feed(&browser, &ctx, GFX_EVENT_MOUSE_UP, 1, 500, 500, 0)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	pointer_eval(browser.script, c"if(order!=='DGMUL'||canvas.hasPointerCapture(1))throw 'implicit release';")
	# Native wheel fields and preventDefault reach the existing scroll default.
	pointer_eval(browser.script, c"let wheels=0;canvas.addEventListener('wheel',function(e){if(!e.isTrusted||e.deltaMode!==1||e.deltaY!==-2||e.clientX!==38||e.clientY!==40)throw 'wheel fields';e.preventDefault();wheels++;},{passive:false});")
	ctx.input.scroll_y = 0
	pointer_feed(&browser, &ctx, GFX_EVENT_SCROLL, 2, 50, 178, 0)
	ctx.input.mouse_x = 50
	ctx.input.mouse_y = 178
	win_browser_pointer_frame(&browser, &ctx, viewport)
	assert_equal(0, ctx.input.scroll_y)
	pointer_eval(browser.script, c"if(wheels!==1)throw 'wheel missing';")
	# Multiple press/release edges within a frame retain arrival ordering.
	pointer_eval(browser.script, c"order='';")
	for i in range(2):
		pointer_feed(&browser, &ctx, GFX_EVENT_MOUSE_DOWN, 1, 50, 178, GFX_MOD_SHIFT)
		pointer_feed(&browser, &ctx, GFX_EVENT_MOUSE_UP, 1, 50, 178, 0)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	pointer_eval(browser.script, c"if(order!=='DGULDGUL')throw 'edge queue order';let cancellations=0;canvas.addEventListener('pointercancel',function(e){if(e.cancelable||e.buttons!==0)throw 'cancel fields';cancellations++;});")
	pointer_feed(&browser, &ctx, GFX_EVENT_MOUSE_DOWN, 1, 50, 178, GFX_MOD_SHIFT)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	# Flush pending capture with a native motion, then cancel without a release.
	ctx.input.mouse_x = 51
	win_browser_pointer_frame(&browser, &ctx, viewport)
	pointer_feed(&browser, &ctx, GFX_EVENT_POINTER_CANCEL, 0, 51, 178, 0)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	pointer_eval(browser.script, c"if(cancellations!==1||canvas.hasPointerCapture(1))throw 'cancel release';")
	# Queue overflow fails closed and releases the previous active capture.
	pointer_feed(&browser, &ctx, GFX_EVENT_MOUSE_DOWN, 1, 50, 178, GFX_MOD_SHIFT)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	for i in range(65): pointer_feed(&browser, &ctx, GFX_EVENT_KEY_DOWN, 1, 50, 178, 0)
	assert_equal(1, browser.native_input.overflow)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	pointer_eval(browser.script, c"if(cancellations!==2||canvas.hasPointerCapture(1))throw 'overflow cancellation';")
	assert_equal(0, browser.native_input.count)
	# A release following cancellation cannot synthesize a fresh pointerup.
	pointer_eval(browser.script, c"order='';")
	pointer_feed(&browser, &ctx, GFX_EVENT_MOUSE_UP, 1, 50, 178, 0)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	pointer_eval(browser.script, c"if(order.indexOf('U')!==-1)throw 'orphan release';")
	assert_equal(1, browser.script.pointer.cancelled)
	# Client coordinates exclude browser chrome; page coordinates include scroll.
	browser.scroll.offset_y = 30.0
	win_script_set_viewport(browser.script, 400, 300, 1.0, 0.0, 30.0)
	pointer_eval(browser.script, c"let scrolled=false;canvas.addEventListener('pointermove',function(e){if(e.clientX===39&&e.clientY===40&&e.pageX===39&&e.pageY===70)scrolled=true;});")
	ctx.input.mouse_x = 51
	win_browser_pointer_frame(&browser, &ctx, viewport)
	pointer_eval(browser.script, c"if(!scrolled)throw 'scrolled coordinates';")
	browser.scroll.offset_y = 0.0
	win_script_set_viewport(browser.script, 400, 300, 1.0, 0.0, 0.0)
	html_node* other_node = browser.page.html.allocations
	while (other_node != 0 && strcmp(win_attr(other_node, c"id"), c"other") != 0): other_node = other_node.allocation_next
	win_box* other_box = win_page_node_box(browser.page, other_node)
	asserts(c"other fixture has layout", other_box != 0)
	int other_x = cast(int, viewport.x + other_box.x) + 2
	int other_y = cast(int, viewport.y + other_box.y) + 2
	asserts(c"native box hit", win_browser_pointer_hit(&browser, viewport, other_x, other_y) == other_node)
	# Chording changes buttons via pointermove, with down/up only at contact edges.
	pointer_eval(browser.script, c"let chord='';function record(e){chord+=e.type+':'+String(e.button)+':'+String(e.buttons)+';';}other.addEventListener('pointerdown',record);other.addEventListener('pointermove',record);other.addEventListener('pointerup',record);")
	pointer_feed(&browser, &ctx, GFX_EVENT_MOUSE_DOWN, 2, other_x, other_y, 0)
	pointer_feed(&browser, &ctx, GFX_EVENT_MOUSE_DOWN, 3, other_x, other_y, 0)
	pointer_feed(&browser, &ctx, GFX_EVENT_MOUSE_UP, 2, other_x, other_y, 0)
	pointer_feed(&browser, &ctx, GFX_EVENT_MOUSE_UP, 3, other_x, other_y, 0)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	assert_strings_equal(c"", browser.script.error)
	assert_equal(0, browser.script.failures)
	pointer_eval(browser.script, c"document.title=chord;")
	assert_strings_equal(c"pointerdown:1:4;pointermove:2:6;pointermove:1:2;pointerup:2:0;", browser.page.title)
	pointer_eval(browser.script, c"if(chord!=='pointerdown:1:4;pointermove:2:6;pointermove:1:2;pointerup:2:0;')throw 'chord order';")
	# Switching away cancels before the tab stops receiving native samples.
	pointer_feed(&browser, &ctx, GFX_EVENT_MOUSE_DOWN, 1, 50, 178, GFX_MOD_SHIFT)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	win_app app
	app.tabs = new list[win_browser*]
	app.tabs.push(&browser)
	app.selected = 1
	win_app_cancel_background_input(&app)
	__w_list_free(cast(__w_list*, app.tabs))
	pointer_eval(browser.script, c"if(cancellations!==3||canvas.hasPointerCapture(1))throw 'background cancel';")
	# A captured node detached during a contact releases capture at document.
	pointer_feed(&browser, &ctx, GFX_EVENT_MOUSE_DOWN, 1, 50, 178, GFX_MOD_SHIFT)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	ctx.input.mouse_x = 51
	win_browser_pointer_frame(&browser, &ctx, viewport)
	pointer_eval(browser.script, c"let detachedLost=0;document.addEventListener('lostpointercapture',function(e){if(e.target===document)detachedLost++;});canvas.remove();")
	win_page_layout(browser.page, 400)
	ctx.input.mouse_x = 52
	win_browser_pointer_frame(&browser, &ctx, viewport)
	pointer_eval(browser.script, c"if(detachedLost!==1||canvas.hasPointerCapture(1))throw 'detached capture';")
	win_stop(&browser)
	assert_equal(0, browser.script.failures)
	win_browser_free(&browser)
	ui_render_destroy(&renderer)
	println(c"Win ordered mouse Pointer Events, capture, wheel and cancellation: OK")
	return 0
