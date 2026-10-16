import lib.assert
import win.app

void focus_eval(win_script* script, char* source):
	int ok = win_script_eval(script, source, strlen(source))
	if (ok == 0): println(script.error)
	asserts(c"native focus and selection", ok)

html_node* focus_node(win_page* page, char* id):
	html_node* node = page.html.allocations
	while (node != 0):
		if (strcmp(win_attr(node, c"id"), id) == 0): return node
		node = node.allocation_next
	return 0

int main():
	char* html = c"<html><body><canvas id='canvas' tabindex='0' width='200' height='100'></canvas><textarea id='editor'></textarea><input id='other'><input id='disabled' disabled><div id='plain'></div><div style='display:none'><input id='hidden'></div><div style='height:800px'></div><input id='bottom'><input id='unwrapped' value='abc'></body></html>"
	win_browser browser
	win_browser_init(&browser, c"unused", c"unused")
	browser.page = win_page_parse(html, strlen(html))
	browser.forms = win_forms_new(browser.page)
	browser.script = win_script_new(browser.page)
	win_script* script = browser.script
	win_page_layout(browser.page, 400)
	win_script_set_viewport(script, 400, 300, 1.0, 0.0, 0.0)
	ui_renderer renderer
	ui_render_init_headless(&renderer)
	ui_theme theme
	ui_theme_light(&theme)
	ui_context ctx
	ui_context_init(&ctx, &renderer, &theme)
	ui_rect viewport = ui_rect_new(12.0, 138.0, 400.0, 300.0)
	focus_eval(script, c"const canvas=document.getElementById('canvas');const editor=document.getElementById('editor');const other=document.getElementById('other');const disabled=document.getElementById('disabled');const hidden=document.getElementById('hidden');const plain=document.getElementById('plain');const bottom=document.getElementById('bottom');if(document.activeElement!==document.body)throw 'initial focus';let order='';canvas.addEventListener('focus',function(e){if(!e.isTrusted||e.bubbles||e.cancelable||e.relatedTarget!==null||document.activeElement!==canvas)throw 'focus fields';order+='F';});canvas.addEventListener('focusin',function(e){if(!e.bubbles)throw 'focusin bubbles';order+='I';});canvas.addEventListener('blur',function(e){if(e.bubbles||e.relatedTarget!==editor||document.activeElement!==document.body)throw 'blur fields';order+='B';});canvas.addEventListener('focusout',function(e){if(!e.bubbles||e.relatedTarget!==editor)throw 'focusout fields';order+='O';});editor.addEventListener('focus',function(e){if(e.relatedTarget===canvas)order+='E';});canvas.focus({preventScroll:true});canvas.focus();if(order!=='FI'||document.activeElement!==canvas)throw 'idempotent focus';disabled.focus();hidden.focus();plain.focus();if(document.activeElement!==canvas)throw 'ineligible focus';editor.focus({preventScroll:true});if(order!=='FIBOE'||document.activeElement!==editor)throw 'focus order';")
	win_input_before(script, browser.forms, &ctx)
	win_control* editor = win_forms_find(browser.forms, focus_node(browser.page, c"editor"))
	assert_equal(editor.id, ctx.focus)
	focus_eval(script, c"editor.value='A😀éZ';editor.setSelectionRange(1,4,'backward');editor.readOnly=true;if(!editor.readOnly||editor.getAttribute('readonly')!=='')throw 'readOnly reflection';editor.readOnly=false;")
	win_input_before(script, browser.forms, &ctx)
	assert_equal(1, ui_textarea_caret_offset(&editor.editor))
	assert_equal(7, editor.editor.sel_anchor)
	# Native caret movement updates UTF-16 selection, including direction.
	ui_textarea_set_caret(&editor.editor, 5)
	editor.editor.sel_anchor = 1
	win_input_after(script, browser.forms, &ctx)
	focus_eval(script, c"if(editor.selectionStart!==1||editor.selectionEnd!==3||editor.selectionDirection!=='forward')throw 'native UTF16 range';editor.setSelectionRange(2,2);")
	win_input_before(script, browser.forms, &ctx)
	assert_equal(1, ui_textarea_caret_offset(&editor.editor))
	win_input_after(script, browser.forms, &ctx)
	focus_eval(script, c"if(editor.selectionStart!==2||editor.selectionEnd!==2)throw 'idle surrogate range preserved';editor.setSelectionRange(1,3);editor.focus({preventScroll:true});")
	# Exercise the actual native text widget: replace the supplementary scalar.
	win_input_before(script, browser.forms, &ctx)
	gfx_event event
	event.kind = GFX_EVENT_CHAR
	event.code = 'Q'
	event.mods = 0
	event.x = 0
	event.y = 0
	assert_equal(editor.id, ctx.focus)
	assert_equal(0, win_form_has(editor.node, c"readonly"))
	ui_feed_event(&ctx, &event)
	ui_begin(&ctx, 640, 480)
	win_forms_draw(browser.forms, &ctx, 12.0, 138.0)
	win_input_after(script, browser.forms, &ctx)
	assert_strings_equal(c"AQéZ", win_attr(editor.node, c"value"))
	assert_equal(2, win_input_binding(script, editor.node).selection.start)
	assert_equal(2, win_input_binding(script, editor.node).selection.end)
	focus_eval(script, c"if(editor.value!=='AQéZ'||editor.selectionStart!==2||editor.selectionEnd!==2)throw 'native replacement';")
	ui_end(&ctx)
	# Native tab focus is visible to DOM listeners and programmatic redirection.
	win_input_before(script, browser.forms, &ctx)
	win_control* other = win_forms_find(browser.forms, focus_node(browser.page, c"other"))
	ctx.focus = other.id
	win_input_after(script, browser.forms, &ctx)
	focus_eval(script, c"if(document.activeElement!==other)throw 'native focus';let redirected=0;other.addEventListener('blur',function(){if(!redirected){redirected++;editor.focus({preventScroll:true});}});bottom.focus({preventScroll:true});if(document.activeElement!==editor||redirected!==1)throw 'reentrant focus';editor.blur();if(document.activeElement!==document.body)throw 'blur fallback';plain.tabIndex=-1;plain.focus({preventScroll:true});if(document.activeElement!==plain||plain.tabIndex!==-1)throw 'negative tabindex';plain.remove();if(document.activeElement!==document.body)throw 'detached active element';bottom.focus({preventScroll:true});")
	assert_equal(0, script.focus_scroll)
	win_browser_focus_scroll(&browser, viewport)
	asserts(c"preventScroll keeps document offset", browser.scroll.offset_y == 0.0)
	focus_eval(script, c"bottom.blur();bottom.focus();")
	win_browser_focus_scroll(&browser, viewport)
	asserts(c"ordinary focus reveals control", browser.scroll.offset_y > 0.0)
	# The first native focus of an unwrapped element must preserve its caret.
	win_control* unwrapped = win_forms_find(browser.forms, focus_node(browser.page, c"unwrapped"))
	win_input_before(script, browser.forms, &ctx)
	ctx.focus = unwrapped.id
	ui_textarea_set_caret(&unwrapped.editor, 2)
	win_input_after(script, browser.forms, &ctx)
	focus_eval(script, c"const unwrapped=document.getElementById('unwrapped');if(document.activeElement!==unwrapped||unwrapped.selectionStart!==2||unwrapped.selectionEnd!==2)throw 'first native focus caret';")
	assert_equal(0, script.failures)
	win_browser_free(&browser)
	ui_render_destroy(&renderer)
	println(c"Win focus events, native widget ownership and UTF-16 editor selection: OK")
	return 0
