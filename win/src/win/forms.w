# HTML form controls use native editing at the document's computed bounds.
# Values live in DOM attributes so scripts and submission share one source.
import win.document
import graphics.ui.widgets

const int WIN_FORM_LIMIT = 65536
const int WIN_CONTROL_LIMIT = 512

struct win_control:
	html_node* node
	ui_textarea_state editor
	char* initial_value
	int initial_checked
	int id

struct win_forms:
	win_page* page
	list[win_control*] controls
	html_node* clicked
	html_node* changed
	html_node* submitter
	char* error

int win_form_has(html_node* node, char* name):
	return html_attribute_find(node.attributes, name) != 0

void win_form_set(html_node* node, char* name, char* value):
	html_attribute* attr = html_attribute_find(node.attributes, name)
	if (attr == 0):
		attr = new html_attribute()
		attr.name = strclone(name)
		attr.next = node.attributes
		node.attributes = attr
	else: free(attr.value)
	attr.value = strclone(value)
	attr.value_length = strlen(value)

void win_form_unset(html_node* node, char* name):
	html_attribute* previous = 0
	html_attribute* attr = node.attributes
	while (attr != 0):
		if (strcmp(attr.name, name) == 0):
			if (previous == 0): node.attributes = attr.next
			else: previous.next = attr.next
			free(attr.name)
			free(attr.value)
			free(attr)
			return
		previous = attr
		attr = attr.next

void win_form_text_append(string_builder* out, html_node* node):
	if (out.length >= WIN_FORM_LIMIT): return
	if (node.kind == HTML_TEXT):
		int count = node.text_length
		if (count > WIN_FORM_LIMIT - out.length): count = WIN_FORM_LIMIT - out.length
		string_append_bytes(out, node.text, count)
	else:
		html_node* child = node.first_child
		while (child != 0):
			win_form_text_append(out, child)
			child = child.next_sibling

char* win_form_text(html_node* node):
	string_builder* out = string_new()
	win_form_text_append(out, node)
	char* result = strclone(out.data)
	string_free(out)
	return result

int win_form_control(html_node* node):
	return win_tag(node, c"input") || win_tag(node, c"textarea") || win_tag(node, c"select") || win_tag(node, c"button")

char* win_form_type(html_node* node):
	char* type = win_attr(node, c"type")
	if (type[0] == 0):
		if (win_tag(node, c"button")): return c"submit"
		return c"text"
	return type

int win_form_disabled(html_node* node):
	while (node != 0):
		if (win_form_has(node, c"disabled")): return 1
		node = node.parent
	return 0

html_node* win_form_owner(win_forms* forms, html_node* node):
	char* id = win_attr(node, c"form")
	if (id[0] != 0):
		html_node* candidate = forms.page.html.allocations
		while (candidate != 0):
			if (win_tag(candidate, c"form") && strcmp(win_attr(candidate, c"id"), id) == 0): return candidate
			candidate = candidate.allocation_next
		return 0
	node = node.parent
	while (node != 0):
		if (win_tag(node, c"form")): return node
		node = node.parent
	return 0

win_control* win_forms_find(win_forms* forms, html_node* node):
	for i in range(forms.controls.length):
		if (forms.controls[i].node == node): return forms.controls[i]
	return 0

void win_form_options(html_node* node, list[html_node*] options):
	html_node* child = node.first_child
	while (child != 0 && options.length < 256):
		if (win_tag(child, c"option")): options.push(child)
		else: win_form_options(child, options)
		child = child.next_sibling

char* win_form_option_value(html_node* option):
	if (win_form_has(option, c"value")): return strclone(win_attr(option, c"value"))
	return win_form_text(option)

void win_forms_discover(win_forms* forms, html_node* node):
	if (win_form_control(node) && win_forms_find(forms, node) == 0 && forms.controls.length < WIN_CONTROL_LIMIT):
		win_control* c = new win_control()
		c.node = node
		c.id = 1000 + forms.controls.length
		ui_textarea_init(&c.editor)
		if (win_tag(node, c"textarea") && win_form_has(node, c"value") == 0):
			char* text = win_form_text(node)
			win_form_set(node, c"value", text)
			free(text)
		if (win_tag(node, c"select") && win_form_has(node, c"value") == 0):
			list[html_node*] options = new list[html_node*]
			win_form_options(node, options)
			int selected = 0
			for i in range(options.length):
				if (win_form_has(options[i], c"selected")): selected = i
			if (options.length > 0):
				char* value = win_form_option_value(options[selected])
				win_form_set(node, c"value", value)
				free(value)
			__w_list_free(cast(__w_list*, options))
		c.initial_value = strclone(win_attr(node, c"value"))
		c.initial_checked = win_form_has(node, c"checked")
		ui_textarea_set(&c.editor, c.initial_value)
		forms.controls.push(c)
	html_node* child = node.first_child
	while (child != 0):
		win_forms_discover(forms, child)
		child = child.next_sibling

win_forms* win_forms_new(win_page* page):
	win_forms* forms = new win_forms()
	forms.page = page
	forms.controls = new list[win_control*]
	win_forms_discover(forms, page.html.root)
	return forms

void win_forms_free(win_forms* forms):
	if (forms == 0): return
	for i in range(forms.controls.length):
		win_control* c = forms.controls[i]
		ui_textarea_free(&c.editor)
		free(c.initial_value)
		free(c)
	__w_list_free(cast(__w_list*, forms.controls))
	free(forms.error)
	free(forms)

void win_forms_reset(win_forms* forms, html_node* form):
	for i in range(forms.controls.length):
		win_control* c = forms.controls[i]
		if (win_form_owner(forms, c.node) != form): continue
		win_form_set(c.node, c"value", c.initial_value)
		if (c.initial_checked): win_form_set(c.node, c"checked", c"")
		else: win_form_unset(c.node, c"checked")
		ui_textarea_set(&c.editor, c.initial_value)

void win_form_encode(string_builder* out, char* text):
	char* hex = c"0123456789ABCDEF"
	for i in range(strlen(text)):
		int ch = text[i] & 255
		if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '-' || ch == '_' || ch == '.' || ch == '*'): string_append_char(out, ch)
		else if (ch == ' '): string_append_char(out, '+')
		else:
			# Form line endings are CRLF, including textarea LF input.
			if (ch == 10 && (i == 0 || text[i - 1] != 13)): string_append(out, c"%0D")
			string_append_char(out, '%')
			string_append_char(out, hex[ch >> 4])
			string_append_char(out, hex[ch & 15])
			if (ch == 13 && text[i + 1] != 10): string_append(out, c"%0A")

void win_form_pair(string_builder* out, char* name, char* value):
	if (out.length != 0): string_append_char(out, '&')
	win_form_encode(out, name)
	string_append_char(out, '=')
	win_form_encode(out, value)

# Traverse DOM order, not the allocation list, preserving duplicate name order.
int win_form_collect(win_forms* forms, html_node* node, html_node* form, html_node* submitter, string_builder* out):
	if (win_form_control(node) && win_form_owner(forms, node) == form && win_form_disabled(node) == 0):
		char* type = win_form_type(node)
		char* name = win_attr(node, c"name")
		int skip = name[0] == 0 || strcmp(type, c"reset") == 0 || strcmp(type, c"button") == 0
		if ((strcmp(type, c"submit") == 0 || win_tag(node, c"button")) && node != submitter): skip = 1
		if ((strcmp(type, c"checkbox") == 0 || strcmp(type, c"radio") == 0) && win_form_has(node, c"checked") == 0): skip = 1
		if (skip == 0):
			if (strcmp(type, c"file") == 0 || strcmp(type, c"image") == 0 || win_form_has(node, c"multiple")):
				forms.error = strclone(c"File, image-submit and multiple-select forms are not supported yet")
				return 0
			char* value = win_attr(node, c"value")
			if ((strcmp(type, c"checkbox") == 0 || strcmp(type, c"radio") == 0) && win_form_has(node, c"value") == 0): value = c"on"
			if (strlen(value) > WIN_FORM_LIMIT || strlen(name) > WIN_FORM_LIMIT): return 0
			win_form_pair(out, name, value)
			if (out.length > WIN_FORM_LIMIT): return 0
	html_node* child = node.first_child
	while (child != 0):
		if (win_form_collect(forms, child, form, submitter, out) == 0): return 0
		child = child.next_sibling
	return 1

char* win_forms_data(win_forms* forms, html_node* form, html_node* submitter):
	free(forms.error)
	forms.error = 0
	win_forms_discover(forms, forms.page.html.root)
	string_builder* out = string_new()
	char* result = 0
	if (win_form_collect(forms, forms.page.html.root, form, submitter, out)): result = strclone(out.data)
	else if (forms.error == 0): forms.error = strclone(c"Form data exceeds 64 KiB")
	string_free(out)
	return result

int win_forms_valid(win_forms* forms, html_node* form):
	if (win_form_has(form, c"novalidate")): return 1
	for i in range(forms.controls.length):
		html_node* n = forms.controls[i].node
		if (win_form_owner(forms, n) != form || win_form_disabled(n) || win_form_has(n, c"required") == 0): continue
		char* type = win_form_type(n)
		int missing = win_attr(n, c"value")[0] == 0
		if (strcmp(type, c"hidden") == 0 || strcmp(type, c"submit") == 0 || strcmp(type, c"reset") == 0 || win_form_has(n, c"readonly")): continue
		if (strcmp(type, c"checkbox") == 0): missing = win_form_has(n, c"checked") == 0
		if (strcmp(type, c"radio") == 0):
			missing = 1
			for j in range(forms.controls.length):
				html_node* other = forms.controls[j].node
				if (win_form_owner(forms, other) == form && strcmp(win_form_type(other), c"radio") == 0 && win_form_disabled(other) == 0 && strcmp(win_attr(other, c"name"), win_attr(n, c"name")) == 0 && win_form_has(other, c"checked")): missing = 0
		if (missing):
			free(forms.error)
			forms.error = strclone(c"Complete the required form fields before submitting")
			return 0
	return 1

void win_forms_toggle(win_forms* forms, html_node* node):
	char* type = win_form_type(node)
	if (strcmp(type, c"radio") == 0):
		html_node* owner = win_form_owner(forms, node)
		for i in range(forms.controls.length):
			html_node* other = forms.controls[i].node
			if (win_form_owner(forms, other) == owner && strcmp(win_form_type(other), c"radio") == 0 && strcmp(win_attr(other, c"name"), win_attr(node, c"name")) == 0): win_form_unset(other, c"checked")
		win_form_set(node, c"checked", c"")
	else if (win_form_has(node, c"checked")): win_form_unset(node, c"checked")
	else: win_form_set(node, c"checked", c"")

void win_forms_select_next(html_node* node):
	list[html_node*] options = new list[html_node*]
	win_form_options(node, options)
	int current = -1
	for i in range(options.length):
		char* value = win_form_option_value(options[i])
		if (strcmp(value, win_attr(node, c"value")) == 0): current = i
		free(value)
	for i in range(options.length):
		int next = (current + i + 1) % options.length
		if (win_form_disabled(options[next]) == 0):
			char* value = win_form_option_value(options[next])
			win_form_set(node, c"value", value)
			free(value)
			break
	__w_list_free(cast(__w_list*, options))

void win_forms_draw(win_forms* forms, ui_context* ctx, float32 x, float32 y):
	forms.clicked = 0
	forms.changed = 0
	forms.submitter = 0
	win_forms_discover(forms, forms.page.html.root)
	# Tab order follows visible document boxes; widget IDs remain stable even
	# after a preceding control is hidden or a new DOM node is appended.
	int kept = 0
	for k in range(ctx.char_count):
		if (ctx.chars[k] == 9 && (ctx.char_mods[k] & GFX_MOD_CTRL) == 0):
			list[win_control*] order = new list[win_control*]
			int selected = -1
			for j in range(forms.page.boxes.length):
				win_control* candidate = win_forms_find(forms, forms.page.boxes[j].node)
				if (forms.page.boxes[j].hidden == 0 && candidate != 0 && win_form_disabled(candidate.node) == 0 && strcmp(win_attr(candidate.node, c"tabindex"), c"-1") != 0):
					if (candidate.id == ctx.focus): selected = order.length
					order.push(candidate)
			if (order.length > 0):
				int next = (selected + 1) % order.length
				if (ctx.char_mods[k] & GFX_MOD_SHIFT): next = (selected + order.length - 1) % order.length
				ctx.focus = order[next].id
			__w_list_free(cast(__w_list*, order))
		else:
			ctx.chars[kept] = ctx.chars[k]
			ctx.char_mods[kept] = ctx.char_mods[k]
			kept = kept + 1
	ctx.char_count = kept
	int saved_id = ctx.next_id
	for i in range(forms.page.boxes.length):
		win_box* box = forms.page.boxes[i]
		if (box.hidden): continue
		win_control* c = win_forms_find(forms, box.node)
		if (c == 0): continue
		html_node* node = c.node
		char* type = win_form_type(node)
		if (strcmp(type, c"hidden") == 0): continue
		ctx.next_id = c.id
		ui_rect area = ui_rect_new(x + box.x, y + box.y, box.width, box.height)
		ui_disable(ctx, win_form_disabled(node))
		int choice = strcmp(type, c"checkbox") == 0 || strcmp(type, c"radio") == 0
		int button = win_tag(node, c"button") || strcmp(type, c"submit") == 0 || strcmp(type, c"reset") == 0 || strcmp(type, c"button") == 0 || choice || win_tag(node, c"select")
		if (button):
			int clicked = ui_click_behavior(ctx, c.id, area)
			if (clicked):
				forms.clicked = node
				ctx.focus = c.id
			ui_render_rect(ctx.rndr, area, ui_widget_fill(ctx, c.id))
			char* label = 0
			if (choice):
				if (win_form_has(node, c"checked")): label = strclone(c"[x]")
				else: label = strclone(c"[ ]")
			else if (win_tag(node, c"button")): label = win_form_text(node)
			else:
				char* value = win_attr(node, c"value")
				if (value[0] == 0): value = type
				label = strclone(value)
			ui_clip_push(ctx.rndr, area)
			ui_draw_text(ctx.rndr, area.x + 7.0, area.y + 6.0, label, 2, ui_text_color(ctx))
			ui_clip_pop(ctx.rndr)
			free(label)
			if (ctx.focus == c.id && ctx.disabled == 0):
				for k in range(ctx.char_count):
					if (ctx.chars[k] == 13 || ctx.chars[k] == 32): forms.clicked = node
		else:
			if (strcmp(win_attr(node, c"value"), c.editor.buf.data) != 0): ui_textarea_set(&c.editor, win_attr(node, c"value"))
			if (win_form_has(node, c"readonly") || strcmp(type, c"file") == 0): ui_disable(ctx, 1)
			if (ctx.focus == c.id && win_tag(node, c"textarea") == 0):
				int kept = 0
				for k in range(ctx.char_count):
					if (ctx.chars[k] == 13 || ctx.chars[k] == 10): forms.submitter = node
					else:
						ctx.chars[kept] = ctx.chars[k]
						ctx.char_mods[kept] = ctx.char_mods[k]
						kept = kept + 1
				ctx.char_count = kept
			if (ui_textarea(ctx, area, &c.editor)):
				int limit = WIN_FORM_LIMIT
				if (win_form_has(node, c"maxlength")):
					int declared = atoi(win_attr(node, c"maxlength"))
					if (declared >= 0 && declared < limit): limit = declared
				if (c.editor.buf.length > limit): ui_textarea_set(&c.editor, win_attr(node, c"value"))
				else:
					win_form_set(node, c"value", c.editor.buf.data)
					forms.changed = node
			if (strcmp(type, c"password") == 0):
				ui_rect mask = ui_rect_inset(area, 3.0)
				ui_render_rect(ctx.rndr, mask, ctx.theme.widget)
				string_builder* hidden = string_new()
				int count = c.editor.buf.length
				if (count > 256): count = 256
				for k in range(count): string_append_char(hidden, '*')
				ui_clip_push(ctx.rndr, mask)
				ui_draw_text(ctx.rndr, area.x + 7.0, area.y + 6.0, hidden.data, 2, ui_text_color(ctx))
				ui_clip_pop(ctx.rndr)
				string_free(hidden)
		ui_disable(ctx, 0)
	ctx.next_id = saved_id
