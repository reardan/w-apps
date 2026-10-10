import lib.assert
import win.forms

html_node* form_find(win_page* page, char* id):
	html_node* node = page.html.allocations
	while (node != 0):
		if (strcmp(win_attr(node, c"id"), id) == 0): return node
		node = node.allocation_next
	return 0

void test_form_data():
	char* source = c"<form id='f'><input name='q' value='a b&amp;é'><input name='same' value='1'><input name='same' value='2'><input disabled name='skip' value='no'><input type='checkbox' name='check' checked><input type='checkbox' name='unchecked'><input type='hidden' name='secret' value='yes'><textarea name='text'>a\nb</textarea><select name='choice'><option value='one'>One</option><option selected value='two'>Two</option></select><button id='send' name='action' value='go'>Go</button><button name='skip' value='no'>No</button><input id='required' required name='required'></form><input form='f' name='outside' value='ok'>"
	win_page* page = win_page_parse(source, strlen(source))
	win_forms* forms = win_forms_new(page)
	html_node* form = form_find(page, c"f")
	html_node* send = form_find(page, c"send")
	asserts(c"required blocks submit", win_forms_valid(forms, form) == 0)
	win_form_set(form_find(page, c"required"), c"value", c"done")
	asserts(c"required now valid", win_forms_valid(forms, form))
	char* data = win_forms_data(forms, form, send)
	assert_strings_equal(c"q=a+b%26%C3%A9&same=1&same=2&check=on&secret=yes&text=a%0D%0Ab&choice=two&action=go&required=done&outside=ok", data)
	free(data)
	win_forms_reset(forms, form)
	assert_strings_equal(c"", win_attr(form_find(page, c"required"), c"value"))
	win_forms_free(forms)
	win_page_free(page)

void test_radio_and_select():
	char* source = c"<form id='f'><input id='a' type='radio' name='r' value='a' checked><input id='b' type='radio' name='r' value='b' required><select id='s' name='s'><option value='a'>A</option><option disabled value='b'>B</option><option value='c'>C</option></select><input type='file' name='upload'></form>"
	win_page* page = win_page_parse(source, strlen(source))
	win_forms* forms = win_forms_new(page)
	html_node* form = form_find(page, c"f")
	html_node* a = form_find(page, c"a")
	html_node* b = form_find(page, c"b")
	asserts(c"radio group validation", win_forms_valid(forms, form))
	win_forms_toggle(forms, b)
	asserts(c"radio exclusive", win_form_has(a, c"checked") == 0 && win_form_has(b, c"checked"))
	html_node* select = form_find(page, c"s")
	assert_strings_equal(c"a", win_attr(select, c"value"))
	win_forms_select_next(select)
	assert_strings_equal(c"c", win_attr(select, c"value"))
	asserts(c"unsupported file submit explicit", win_forms_data(forms, form, b) == 0 && forms.error != 0)
	win_forms_reset(forms, form)
	asserts(c"radio reset", win_form_has(a, c"checked") && win_form_has(b, c"checked") == 0)
	win_forms_free(forms)
	win_page_free(page)

void test_form_widgets():
	char* source = c"<form><input id='text' value='a'><input id='check' type='checkbox'><textarea id='multi'>hello</textarea><input hidden><button id='send'>Send</button></form>"
	win_page* page = win_page_parse(source, strlen(source))
	win_forms* forms = win_forms_new(page)
	win_page_layout(page, 600)
	ui_renderer renderer
	ui_render_init_headless(&renderer)
	ui_theme theme
	ui_theme_light(&theme)
	ui_context ctx
	ui_context_init(&ctx, &renderer, &theme)
	html_node* text = form_find(page, c"text")
	win_control* control = win_forms_find(forms, text)
	ctx.focus = control.id
	gfx_event e
	e.kind = GFX_EVENT_CHAR
	e.code = 'z'
	e.mods = 0
	ui_feed_event(&ctx, &e)
	ui_begin(&ctx, 640, 480)
	win_forms_draw(forms, &ctx, 0.0, 0.0)
	ui_end(&ctx)
	assert_strings_equal(c"za", win_attr(text, c"value"))
	asserts(c"input event target", forms.changed == text)
	# Tab transfers focus to the checkbox, and Space activates it.
	e.code = 9
	ui_feed_event(&ctx, &e)
	ui_begin(&ctx, 640, 480)
	win_forms_draw(forms, &ctx, 0.0, 0.0)
	ui_end(&ctx)
	html_node* check = form_find(page, c"check")
	assert_equal(win_forms_find(forms, check).id, ctx.focus)
	e.code = 32
	ui_feed_event(&ctx, &e)
	ui_begin(&ctx, 640, 480)
	win_forms_draw(forms, &ctx, 0.0, 0.0)
	ui_end(&ctx)
	asserts(c"checkbox click target", forms.clicked == check)
	# Script changes are pulled into an existing editor without a new page.
	win_form_set(text, c"value", c"script")
	ui_begin(&ctx, 640, 480)
	win_forms_draw(forms, &ctx, 0.0, 0.0)
	ui_end(&ctx)
	assert_strings_equal(c"script", control.editor.buf.data)
	ui_render_destroy(&renderer)
	win_forms_free(forms)
	win_page_free(page)

int main():
	test_form_data()
	test_radio_and_select()
	test_form_widgets()
	println(c"Win form serialization, validation, reset and editing: OK")
	return 0
