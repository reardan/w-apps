import lib.assert
import win.app

void keyboard_eval(win_script* script, char* source):
	int ok = win_script_eval(script, source, strlen(source))
	if (ok == 0): println(script.error)
	asserts(c"native keyboard/default edits", ok)

void keyboard_feed(win_browser* browser, ui_context* ctx, int kind, int code, int mods):
	gfx_event event
	event.kind = kind
	event.code = code
	event.mods = mods
	event.x = 0
	event.y = 0
	ui_feed_event(ctx, &event)
	win_native_push(&browser.native_input, &event)

int main():
	char* html = c"<body><textarea id='editor' style='position:fixed;width:1px;height:1px'></textarea><input id='other' value='old'></body>"
	win_browser browser
	win_browser_init(&browser, c"unused", c"unused")
	browser.page = win_page_parse(html, strlen(html))
	browser.forms = win_forms_new(browser.page)
	browser.script = win_script_new(browser.page)
	win_script* script = browser.script
	win_page_layout(browser.page, 400)
	ui_renderer renderer
	ui_render_init_headless(&renderer)
	ui_theme theme
	ui_theme_light(&theme)
	ui_context ctx
	ui_context_init(&ctx, &renderer, &theme)
	ui_rect viewport = ui_rect_new(12.0, 138.0, 400.0, 300.0)
	keyboard_eval(script, c"const editor=document.getElementById('editor');const other=document.getElementById('other');editor.focus({preventScroll:true});let log='';let keys=[];let values=[];editor.onkeydown=function(e){if(!e.isTrusted||!e.cancelable||!e.bubbles||e.code!==''||e.getModifierState('Shift')!==e.shiftKey)throw 'keyboard fields';keys.push(e);log+='K';if(e.key==='Backspace')e.preventDefault();};editor.onkeyup=function(e){keys.push(e);log+='U';};editor.onbeforeinput=function(e){if(!e.isTrusted||!e.cancelable||e.isComposing||e.inputType!=='insertText')throw 'beforeinput fields';log+='B';if(e.data==='X')e.preventDefault();};editor.oninput=function(e){if(!e.isTrusted||e.cancelable||e.isComposing||e.inputType!=='insertText')throw 'input fields';log+='I';values.push(editor.value);};")
	keyboard_feed(&browser, &ctx, GFX_EVENT_KEY_DOWN, 38, 0)
	keyboard_feed(&browser, &ctx, GFX_EVENT_CHAR, 'a', 0)
	keyboard_feed(&browser, &ctx, GFX_EVENT_KEY_UP, 38, 0)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	keyboard_eval(script, c"if(log!=='KBIU'||editor.value!=='a'||editor.selectionStart!==1||keys[0].key!=='a'||keys[0].keyCode!==65||keys[1].keyCode!==65||keys[0].repeat)throw 'logical key/default order';")
	assert_equal(0, ctx.char_count)
	# A canceled raw key suppresses its following CHAR default.
	keyboard_feed(&browser, &ctx, GFX_EVENT_KEY_DOWN, 22, 0)
	keyboard_feed(&browser, &ctx, GFX_EVENT_CHAR, 8, 0)
	keyboard_feed(&browser, &ctx, GFX_EVENT_KEY_UP, 22, 0)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	keyboard_eval(script, c"if(editor.value!=='a'||log!=='KBIUKU')throw 'keydown default prevention';")
	# Portable CHAR-only input is valid; each beforeinput/input sees one edit.
	keyboard_feed(&browser, &ctx, GFX_EVENT_CHAR, 'X', 0)
	keyboard_feed(&browser, &ctx, GFX_EVENT_CHAR, 233, 0)
	keyboard_feed(&browser, &ctx, GFX_EVENT_CHAR, 128578, 0)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	keyboard_eval(script, c"if(editor.value!=='aé🙂'||editor.selectionStart!==4||values.length!==3||values[1]!=='aé'||values[2]!=='aé🙂')throw 'scalar edits/cancellation';")
	# The unchanged mobile sink resets inside input; no later native redraw
	# may replay the queued CHAR records or replace its sentinel/caret.
	keyboard_eval(script, c"editor.value='​';editor.setSelectionRange(1,1);let committed='';editor.oninput=function(){committed+=editor.value.slice(1);editor.value='​';editor.setSelectionRange(1,1);};")
	keyboard_feed(&browser, &ctx, GFX_EVENT_CHAR, 233, 0)
	keyboard_feed(&browser, &ctx, GFX_EVENT_CHAR, 128578, 0)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	keyboard_eval(script, c"if(committed!=='é🙂'||editor.value!=='​'||editor.selectionStart!==1||document.activeElement!==editor)throw 'sink reset';")
	assert_equal(0, ctx.char_count)
	win_input_before(script, browser.forms, &ctx)
	ui_begin(&ctx, 640, 480)
	# Deliberately omit forms drawing: a tiny/offscreen editor retains focus.
	win_input_after(script, browser.forms, &ctx)
	ui_end(&ctx)
	keyboard_eval(script, c"if(document.activeElement!==editor)throw 'offscreen focus';other.focus({preventScroll:true});")
	keyboard_feed(&browser, &ctx, GFX_EVENT_CHAR, 1, GFX_MOD_CTRL)
	keyboard_feed(&browser, &ctx, GFX_EVENT_CHAR, 'N', 0)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	keyboard_eval(script, c"if(other.value!=='N'||other.selectionStart!==1)throw 'CHAR-only select all';")
	# Repeat and NAV mapping are logical and do not expose raw keycode 113.
	keyboard_eval(script, c"other.onkeydown=function(e){keys.push(e);e.preventDefault();};")
	keyboard_feed(&browser, &ctx, GFX_EVENT_KEY_DOWN, 113, 0)
	keyboard_feed(&browser, &ctx, GFX_EVENT_NAV, GFX_NAV_LEFT, 0)
	keyboard_feed(&browser, &ctx, GFX_EVENT_KEY_DOWN, 113, 0)
	keyboard_feed(&browser, &ctx, GFX_EVENT_NAV, GFX_NAV_LEFT, 0)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	keyboard_eval(script, c"const last=keys[keys.length-1];if(last.key!=='ArrowLeft'||last.keyCode!==37||!last.repeat)throw 'navigation/repeat';")
	assert_equal(0, ctx.nav_count)
	# An unmatched release does not reuse a previous press's logical key.
	keyboard_feed(&browser, &ctx, GFX_EVENT_KEY_UP, 113, 0)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	keyboard_eval(script, c"other.onkeyup=function(e){keys.push(e);};")
	keyboard_feed(&browser, &ctx, GFX_EVENT_KEY_UP, 113, 0)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	keyboard_eval(script, c"if(keys[keys.length-1].key!=='Unidentified')throw 'unmatched key release';other.onbeforeinput=function(){other.readOnly=true;};")
	keyboard_feed(&browser, &ctx, GFX_EVENT_CHAR, 'Q', 0)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	keyboard_eval(script, c"if(other.value!=='N')throw 'readonly changed by beforeinput';")
	keyboard_eval(script, c"other.readOnly=false;other.onbeforeinput=null;let composition='';other.oncompositionstart=function(e){if(!e.isTrusted||e.cancelable||!e.bubbles)throw 'composition fields';composition+='start:'+e.data+'|';};other.oncompositionupdate=function(e){composition+='update:'+e.data+'|';};other.oncompositionend=function(e){composition+='end:'+e.data+'|';};other.oninput=function(e){composition+='input:'+e.data+'|';};")
	keyboard_feed(&browser, &ctx, GFX_EVENT_PREEDIT_BEGIN, 0, 0)
	keyboard_feed(&browser, &ctx, GFX_EVENT_PREEDIT_TEXT, 233, 0)
	keyboard_feed(&browser, &ctx, GFX_EVENT_PREEDIT_TEXT, 128578, 0)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	keyboard_eval(script, c"if(composition!=='start:|update:é🙂|'||other.value!=='N')throw 'preedit is not commit';")
	keyboard_feed(&browser, &ctx, GFX_EVENT_PREEDIT_BEGIN, 0, 0)
	keyboard_feed(&browser, &ctx, GFX_EVENT_PREEDIT_TEXT, 233, 0)
	keyboard_feed(&browser, &ctx, GFX_EVENT_PREEDIT_END, 0, 0)
	keyboard_feed(&browser, &ctx, GFX_EVENT_CHAR, 233, 0)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	keyboard_eval(script, c"if(composition!=='start:|update:é🙂|update:é|end:|input:é|'||other.value!=='Né')throw 'composition commit order';")
	keyboard_feed(&browser, &ctx, GFX_EVENT_PREEDIT_BEGIN, 0, 0)
	keyboard_feed(&browser, &ctx, GFX_EVENT_PREEDIT_TEXT, 'x', 0)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	win_keyboard_cancel(script)
	win_keyboard_cancel(script)
	keyboard_eval(script, c"if(composition!=='start:|update:é🙂|update:é|end:|input:é|start:|update:x|end:|'||other.value!=='Né')throw 'composition cancellation';")
	keyboard_eval(script, c"other.value='abc';other.setSelectionRange(3,3);")
	keyboard_feed(&browser, &ctx, GFX_EVENT_NAV, GFX_NAV_LEFT, 0)
	keyboard_feed(&browser, &ctx, GFX_EVENT_CHAR, 'Q', 0)
	win_browser_pointer_frame(&browser, &ctx, viewport)
	keyboard_eval(script, c"if(other.value!=='abQc'||other.selectionStart!==3)throw 'ordered navigation before text';")
	assert_equal(0, script.failures)
	win_browser_free(&browser)
	ui_render_destroy(&renderer)
	println(c"Win portable logical keys and ordered cancelable native text editing: OK")
	return 0
