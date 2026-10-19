# CSS UI 4: inherited exclusion from hit testing, not from event propagation.
import lib.assert
import win.app

html_node* pe_node(win_page* page, char* id):
	html_node* node = page.html.allocations
	while (node != 0):
		if (node.kind == HTML_START && strcmp(win_attr(node, c"id"), id) == 0): return node
		node = node.allocation_next
	return 0

void pe_eval(win_script* script, char* source):
	int ok = win_script_eval(script, source, strlen(source))
	if (ok == 0):
		println(script.error)
		char* exception = win_js_text(script.runtime.completion.value)
		println(exception)
		free(exception)
	asserts(c"pointer-events JavaScript", ok)

void test_pointer_cascade():
	char* source = c"<style>body{margin:0}#parent{pointer-events:none}#valid{pointer-events:auto!important}#invalid{pointer-events:auto;pointer-events:visiblePainted}#var{--hit:auto;pointer-events:var(--hit)}#missing{pointer-events:auto;pointer-events:var(--missing)}</style><div id='parent'><div id='inherit'></div><div id='valid' style='pointer-events:none'></div><div id='invalid'></div><div id='initial' style='pointer-events:initial'></div><div id='unset' style='pointer-events:unset'></div><div id='explicit' style='pointer-events:inherit'></div><div id='var'></div><div id='missing'></div></div>"
	win_page* page = win_page_parse(source, strlen(source))
	win_page_layout(page, 400)
	assert_equal(1, win_page_node_box(page, pe_node(page, c"parent")).pointer_none)
	assert_equal(1, win_page_node_box(page, pe_node(page, c"inherit")).pointer_none)
	assert_equal(0, win_page_node_box(page, pe_node(page, c"valid")).pointer_none)
	assert_equal(0, win_page_node_box(page, pe_node(page, c"invalid")).pointer_none)
	assert_equal(0, win_page_node_box(page, pe_node(page, c"initial")).pointer_none)
	assert_equal(1, win_page_node_box(page, pe_node(page, c"unset")).pointer_none)
	assert_equal(1, win_page_node_box(page, pe_node(page, c"explicit")).pointer_none)
	assert_equal(0, win_page_node_box(page, pe_node(page, c"var")).pointer_none)
	assert_equal(1, win_page_node_box(page, pe_node(page, c"missing")).pointer_none)
	win_page_free(page)

void test_pointer_replaced_and_link_descendants():
	char* source = c"<style>body{margin:0}#parent{pointer-events:none}</style><div id='parent'><canvas id='canvas' width='40' height='30'></canvas><a href='#restored'><span style='pointer-events:auto'>restored</span></a><a href='#excluded'>excluded</a></div>"
	win_page* page = win_page_parse(source, strlen(source))
	win_page_layout(page, 400)
	int replaced = 0
	int restored = 0
	int excluded = 0
	for i in range(page.runs.length):
		win_run* run = page.runs[i]
		if (run.node == pe_node(page, c"canvas")):
			replaced = replaced + 1
			assert_equal(1, run.pointer_none)
			asserts(c"inherited none excludes replaced run", win_page_node_hit(page, run.x + 1.0, run.y + 1.0) != run.node)
		if (strcmp(run.href, c"#restored") == 0):
			restored = restored + 1
			assert_equal(0, run.pointer_none)
			assert_strings_equal(c"#restored", win_page_hit(page, run.x + 1.0, run.y + 1.0))
		if (strcmp(run.href, c"#excluded") == 0):
			excluded = excluded + 1
			assert_equal(1, run.pointer_none)
			assert_strings_equal(c"", win_page_hit(page, run.x + 1.0, run.y + 1.0))
	assert_equal(1, replaced)
	assert_equal(1, restored)
	assert_equal(1, excluded)
	win_page_free(page)

void pe_feed(win_browser* browser, ui_context* ctx, ui_rect viewport, int kind, int x, int y):
	gfx_event event
	event.kind = kind
	event.code = 1
	event.x = x
	event.y = y
	ctx.input.mouse_x = x
	ctx.input.mouse_y = y
	ui_feed_event(ctx, &event)
	win_native_push(&browser.native_input, &event)
	win_browser_pointer_frame(browser, ctx, viewport)

void test_pointer_targets_and_capture():
	win_browser browser
	win_browser_init(&browser, c"unused", c"unused")
	char* source = c"<style>body{margin:0}.layer{position:fixed;left:0;top:0;width:200px;height:100px}#cover{pointer-events:none;background:red}#override{pointer-events:auto;width:40px;height:30px}</style><a id='under' class='layer' href='#under'></a><div id='cover' class='layer'><a id='inherited' href='#wrong'>hidden hit</a><div id='override'></div></div><input id='field' style='pointer-events:none' value='keyboard'>"
	browser.page = win_page_parse(source, strlen(source))
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
	html_node* under = pe_node(browser.page, c"under")
	html_node* override = pe_node(browser.page, c"override")
	asserts(c"disabled overlay and inherited text click through", win_page_node_hit(browser.page, 5.0, 5.0) == under)
	assert_strings_equal(c"#under", win_page_hit(browser.page, 5.0, 5.0))
	asserts(c"native hit matches document target", win_browser_pointer_hit(&browser, viewport, 17, 143) == under)
	win_box* box = win_page_node_box(browser.page, override)
	int target_x = cast(int, box.x + viewport.x) + 2
	int target_y = cast(int, box.y + viewport.y) + 2
	asserts(c"auto descendant restores hit testing", win_browser_pointer_hit(&browser, viewport, target_x, target_y) == override)
	assert_strings_equal(c"", win_page_hit(browser.page, box.x + 2.0, box.y + 2.0))
	pe_eval(browser.script, c"const cover=document.getElementById('cover');const override=document.getElementById('override');const under=document.getElementById('under');let trace='';let got=0;let moves=0;let lost=0;under.addEventListener('pointerdown',function(e){if(e.target!==under)throw 'under target';trace+='U';});cover.addEventListener('pointerdown',function(e){if(e.target!==override)throw 'capture target';trace+='C';},true);cover.addEventListener('pointerdown',function(e){if(e.target!==override)throw 'bubble target';trace+='B';});override.addEventListener('pointerdown',function(e){trace+='D';override.setPointerCapture(e.pointerId);override.style.setProperty('pointer-events','none');});override.addEventListener('gotpointercapture',function(){got++;});override.addEventListener('pointermove',function(e){if(e.target!==override)throw 'captured move';moves++;});override.addEventListener('lostpointercapture',function(){lost++;});")
	pe_feed(&browser, &ctx, viewport, GFX_EVENT_MOUSE_DOWN, 17, 143)
	pe_feed(&browser, &ctx, viewport, GFX_EVENT_MOUSE_UP, 17, 143)
	pe_eval(browser.script, c"if(trace!=='U')throw 'click through dispatch';trace='';")
	pe_feed(&browser, &ctx, viewport, GFX_EVENT_MOUSE_DOWN, target_x, target_y)
	pe_eval(browser.script, c"if(trace!=='CDB')throw 'excluded ancestor event path';")
	win_page_layout(browser.page, 400)
	asserts(c"style mutation updates native target", win_browser_pointer_hit(&browser, viewport, target_x, target_y) == under)
	ctx.input.mouse_x = target_x + 1
	win_browser_pointer_frame(&browser, &ctx, viewport)
	pe_eval(browser.script, c"if(got!==1||moves!==1||!override.hasPointerCapture(1))throw 'none must retain capture';")
	pe_feed(&browser, &ctx, viewport, GFX_EVENT_MOUSE_UP, target_x + 1, target_y)
	pe_eval(browser.script, c"if(lost!==1||override.hasPointerCapture(1))throw 'capture release';const field=document.getElementById('field');field.focus();if(document.activeElement!==field)throw 'none must permit keyboard focus';let synthetic=0;cover.addEventListener('click',function(){synthetic++;});cover.dispatchEvent(new Event('click'));if(synthetic!==1)throw 'programmatic click';")
	assert_equal(0, browser.script.failures)
	win_browser_free(&browser)
	ui_render_destroy(&renderer)

void pe_widget_frame(win_forms* forms, ui_context* ctx, int kind, int code, int x, int y):
	gfx_event event
	event.kind = kind
	event.code = code
	event.x = x
	event.y = y
	ctx.input.mouse_x = x
	ctx.input.mouse_y = y
	ui_feed_event(ctx, &event)
	ui_begin(ctx, 640, 480)
	win_forms_draw(forms, ctx, 12.0, 138.0)
	ui_end(ctx)

void test_pointer_native_forms():
	char* source = c"<body style='margin:0'><div style='pointer-events:none'><button id='excluded'>excluded</button><button id='restored' style='pointer-events:auto'>restored</button><input id='text' value='a'></div></body>"
	win_page* page = win_page_parse(source, strlen(source))
	win_forms* forms = win_forms_new(page)
	win_page_layout(page, 400)
	ui_renderer renderer
	ui_render_init_headless(&renderer)
	ui_theme theme
	ui_theme_light(&theme)
	ui_context ctx
	ui_context_init(&ctx, &renderer, &theme)
	html_node* excluded = pe_node(page, c"excluded")
	html_node* restored = pe_node(page, c"restored")
	html_node* text = pe_node(page, c"text")
	win_box* box = win_page_node_box(page, excluded)
	int x = cast(int, box.x) + 14
	int y = cast(int, box.y) + 140
	pe_widget_frame(forms, &ctx, GFX_EVENT_MOUSE_DOWN, 1, x, y)
	asserts(c"excluded native button does not gain active state", ctx.active != win_forms_find(forms, excluded).id)
	pe_widget_frame(forms, &ctx, GFX_EVENT_MOUSE_UP, 1, x, y)
	asserts(c"excluded native button cannot click", forms.clicked == 0)
	asserts(c"excluded native button cannot mouse focus", ctx.focus != win_forms_find(forms, excluded).id)
	box = win_page_node_box(page, restored)
	x = cast(int, box.x) + 14
	y = cast(int, box.y) + 140
	pe_widget_frame(forms, &ctx, GFX_EVENT_MOUSE_DOWN, 1, x, y)
	pe_widget_frame(forms, &ctx, GFX_EVENT_MOUSE_UP, 1, x, y)
	asserts(c"restored native button activates", forms.clicked == restored)
	ctx.focus = 0
	pe_widget_frame(forms, &ctx, GFX_EVENT_CHAR, 9, x, y)
	assert_equal(win_forms_find(forms, excluded).id, ctx.focus)
	pe_widget_frame(forms, &ctx, GFX_EVENT_CHAR, 32, x, y)
	asserts(c"excluded button retains keyboard activation", forms.clicked == excluded)
	box = win_page_node_box(page, text)
	x = cast(int, box.x) + 14
	y = cast(int, box.y) + 140
	ctx.focus = 0
	pe_widget_frame(forms, &ctx, GFX_EVENT_MOUSE_DOWN, 1, x, y)
	pe_widget_frame(forms, &ctx, GFX_EVENT_MOUSE_UP, 1, x, y)
	asserts(c"excluded text field cannot mouse focus", ctx.focus != win_forms_find(forms, text).id)
	ctx.focus = win_forms_find(forms, text).id
	pe_widget_frame(forms, &ctx, GFX_EVENT_CHAR, 'z', x, y)
	assert_strings_equal(c"za", win_attr(text, c"value"))
	ui_render_destroy(&renderer)
	win_forms_free(forms)
	win_page_free(page)

void test_pointer_cssom():
	char* source = c"<div id='parent' style='pointer-events:none;flex-direction:column-reverse'><div id='child'></div></div>"
	win_page* page = win_page_parse(source, strlen(source))
	win_script* script = win_script_new(page)
	pe_eval(script, c"const parent=document.getElementById('parent');const child=document.getElementById('child');if(parent.style.pointerEvents!=='none'||getComputedStyle(child).pointerEvents!=='none')throw 'pointer property read';child.style.pointerEvents='auto';if(child.style.getPropertyValue('pointer-events')!=='auto'||getComputedStyle(child).getPropertyValue('pointer-events')!=='auto')throw 'pointer property write';child.style.pointerEvents='visiblePainted';if(child.style.pointerEvents!=='auto')throw 'invalid pointer value';if(child.style.removeProperty('pointer-events')!=='auto'||getComputedStyle(child).pointerEvents!=='none')throw 'pointer property remove';if(parent.style.flexDirection!=='column-reverse'||getComputedStyle(parent).flexDirection!=='column-reverse')throw 'reverse property read';parent.style.flexDirection='row-reverse';if(getComputedStyle(parent).getPropertyValue('flex-direction')!=='row-reverse')throw 'reverse property write';child.style.flexDirection='inherit';if(getComputedStyle(child).flexDirection!=='row-reverse')throw 'reverse property inherit';parent.style.removeProperty('flex-direction');if(getComputedStyle(parent).flexDirection!=='row'||getComputedStyle(child).flexDirection!=='row')throw 'reverse property remove';")
	assert_equal(0, script.failures)
	win_script_free(script)
	win_page_free(page)

int main():
	test_pointer_cascade()
	test_pointer_replaced_and_link_descendants()
	test_pointer_targets_and_capture()
	test_pointer_native_forms()
	test_pointer_cssom()
	println(c"CSS pointer-events cascade, click-through, native event path, capture and focus: OK")
	return 0
