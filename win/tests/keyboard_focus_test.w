import lib.assert
import win.app

html_node* kfocus_node(win_page* page, char* id):
	html_node* node = page.html.allocations
	while (node != 0):
		if (strcmp(win_attr(node, c"id"), id) == 0): return node
		node = node.allocation_next
	return 0

void kfocus_eval(win_script* script, char* source):
	int ok = win_script_eval(script, source, strlen(source))
	if (ok == 0):
		println(script.error)
		char* message = win_js_text(script.runtime.completion.value)
		println(message)
		free(message)
	asserts(c"keyboard focus script", ok)

void kfocus_feed(win_browser* browser, ui_context* ctx, int kind, int code, int mods):
	gfx_event event
	event.kind = kind
	event.code = code
	event.mods = mods
	ui_feed_event(ctx, &event)
	win_native_push(&browser.native_input, &event)

void kfocus_tab(win_browser* browser, ui_context* ctx, int reverse, char* expected):
	int mods = 0
	if (reverse): mods = GFX_MOD_SHIFT
	kfocus_feed(browser, ctx, GFX_EVENT_KEY_DOWN, 23, mods)
	kfocus_feed(browser, ctx, GFX_EVENT_CHAR, 9, mods)
	kfocus_feed(browser, ctx, GFX_EVENT_KEY_UP, 23, mods)
	win_browser_pointer_frame(browser, ctx, ui_rect_new(12.0, 138.0, 400.0, 300.0))
	assert_strings_equal(expected, win_attr(browser.script.active_focus, c"id"))
	assert_equal(0, ctx.char_count)

void test_keyboard_focus():
	char* source = c"<body><a id='link' href='#target'><span>nested link</span></a><div id='two' tabindex='2'>two</div><input id='one' tabindex='1'><button id='twoB' tabindex='2'>two b</button><button disabled id='disabled'>disabled</button><div hidden><a href='#' id='htmlhidden'>hidden</a></div><div style='display:none'><input id='displaynone'></div><div style='visibility:hidden'><button id='invisible'>hidden</button><a id='visible' href='#' style='visibility:visible'>visible</a></div><div id='negative' tabindex='-1'>negative</div><button id='none' style='pointer-events:none'>none</button><div id='zero' tabindex='0'>zero</div><div id='target' style='height:500px'>target</div></body>"
	win_browser browser
	win_browser_init(&browser, c"unused", c"unused")
	browser.page = win_page_parse(source, strlen(source))
	browser.forms = win_forms_new(browser.page)
	browser.script = win_script_new(browser.page)
	win_page_layout(browser.page, 400)
	ui_renderer renderer
	ui_render_init_headless(&renderer)
	ui_theme theme
	ui_theme_light(&theme)
	ui_context ctx
	ui_context_init(&ctx, &renderer, &theme)
	kfocus_eval(browser.script, c"let path='';document.addEventListener('focusin',function(e){path+=e.target.id+';';});const link=document.getElementById('link');const negative=document.getElementById('negative');")
	kfocus_tab(&browser, &ctx, 0, c"one")
	kfocus_tab(&browser, &ctx, 0, c"two")
	kfocus_tab(&browser, &ctx, 0, c"twoB")
	kfocus_tab(&browser, &ctx, 0, c"link")
	kfocus_tab(&browser, &ctx, 0, c"visible")
	kfocus_tab(&browser, &ctx, 0, c"none")
	kfocus_tab(&browser, &ctx, 0, c"zero")
	kfocus_tab(&browser, &ctx, 0, c"one")
	kfocus_tab(&browser, &ctx, 1, c"zero")
	kfocus_tab(&browser, &ctx, 1, c"none")
	kfocus_eval(browser.script, c"if(path!=='one;two;twoB;link;visible;none;zero;one;zero;none;')throw 'sequential order';negative.focus();if(document.activeElement!==negative)throw 'negative focus';")
	kfocus_tab(&browser, &ctx, 0, c"none")
	kfocus_eval(browser.script, c"document.getElementById('none').onkeydown=function(e){if(e.key==='Tab')e.preventDefault();};")
	kfocus_tab(&browser, &ctx, 0, c"none")
	kfocus_eval(browser.script, c"document.getElementById('none').onkeydown=null;link.focus();link.onkeydown=function(e){if(e.key==='Enter')e.preventDefault();};let clicks=0;link.onclick=function(e){if(!e.isTrusted)throw 'keyboard click trust';clicks++;e.preventDefault();};")
	kfocus_feed(&browser, &ctx, GFX_EVENT_KEY_DOWN, 36, 0)
	kfocus_feed(&browser, &ctx, GFX_EVENT_CHAR, 13, 0)
	kfocus_feed(&browser, &ctx, GFX_EVENT_KEY_UP, 36, 0)
	win_browser_pointer_frame(&browser, &ctx, ui_rect_new(12.0, 138.0, 400.0, 300.0))
	kfocus_eval(browser.script, c"if(clicks!==0)throw 'keydown cancellation';link.onkeydown=null;")
	kfocus_feed(&browser, &ctx, GFX_EVENT_CHAR, 13, 0)
	win_browser_pointer_frame(&browser, &ctx, ui_rect_new(12.0, 138.0, 400.0, 300.0))
	asserts(c"click cancellation suppresses navigation", browser.keyboard_href == 0)
	kfocus_eval(browser.script, c"if(clicks!==1)throw 'Enter click';link.onclick=function(){clicks++;link.setAttribute('href','#changed');};")
	kfocus_feed(&browser, &ctx, GFX_EVENT_CHAR, 13, 0)
	win_browser_pointer_frame(&browser, &ctx, ui_rect_new(12.0, 138.0, 400.0, 300.0))
	assert_strings_equal(c"#changed", browser.keyboard_href)
	assert_equal(0, browser.keyboard_new_tab)
	# Focus rings use descendant inline runs and viewport clipping.
	ui_begin(&ctx, 640, 480)
	int before = renderer.layer_vert_count[0]
	win_browser_focus_paint(&browser, &ctx, ui_rect_new(12.0, 138.0, 400.0, 300.0), 138.0)
	asserts(c"focused inline descendant emits visible ring", renderer.layer_vert_count[0] > before)
	ui_end(&ctx)
	# A pending navigation doesn't outlive stopping/loading a new page.
	win_stop(&browser)
	asserts(c"stop clears pending keyboard navigation", browser.keyboard_href == 0)
	kfocus_eval(browser.script, c"link.setAttribute('target','_blank');")
	kfocus_feed(&browser, &ctx, GFX_EVENT_CHAR, 13, 0)
	win_browser_pointer_frame(&browser, &ctx, ui_rect_new(12.0, 138.0, 400.0, 300.0))
	assert_equal(1, browser.keyboard_new_tab)
	win_browser_keyboard_navigate(&browser)
	assert_strings_equal(c"#changed", browser.new_tab)
	# DOM insertion/reordering, not allocation-list order, drives navigation.
	kfocus_eval(browser.script, c"const zero=document.getElementById('zero');document.body.insertBefore(zero,link);document.getElementById('twoB').focus();")
	kfocus_tab(&browser, &ctx, 0, c"zero")
	ctx.focus = 3
	kfocus_tab(&browser, &ctx, 0, c"one")
	assert_equal(0, browser.script.failures)
	win_browser_free(&browser)
	ui_render_destroy(&renderer)

int main():
	test_keyboard_focus()
	println(c"Sequential DOM focus, tabindex, visibility, native Enter and focus rings: OK")
	return 0
