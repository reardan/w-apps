# Synchronize the DOM's UTF-16 selection/focus with native widget state.
import win.script
import win.forms

win_dom_binding* win_input_binding(win_script* script, html_node* node):
	for i in range(script.bindings.length):
		if (script.bindings[i].node == node): return script.bindings[i]
	return 0

html_node* win_input_focus_node(win_forms* forms, int id):
	for i in range(forms.controls.length):
		if (forms.controls[i].id == id): return forms.controls[i].node
	return 0

void win_input_apply_focus(win_script* script, win_forms* forms, ui_context* ctx):
	if (forms.focus_revision == script.focus_revision): return
	win_control* control = win_forms_find(forms, script.active_focus)
	if (control != 0): ctx.focus = control.id
	else if (script.active_focus != 0 || ctx.focus >= 1000): ctx.focus = 0
	forms.focus_revision = script.focus_revision
	forms.native_focus = ctx.focus

void win_input_before(win_script* script, win_forms* forms, ui_context* ctx):
	if (script == 0 || forms == 0): return
	win_forms_discover(forms, forms.page.html.root)
	win_script_active_element(script)
	if (script.active_focus != 0 && win_focus_eligible(script.page, script.active_focus) == 0): win_script_focus_input(script, 0, 1)
	if (forms.focus_revision == script.focus_revision && ctx.focus != forms.native_focus):
		win_script_focus_input(script, win_input_focus_node(forms, ctx.focus), 1)
	win_input_apply_focus(script, forms, ctx)
	for i in range(forms.controls.length):
		win_control* control = forms.controls[i]
		win_dom_binding* binding = win_input_binding(script, control.node)
		if (binding == 0 || win_text_selection_applies(control.node) == 0): continue
		char* value = win_attr(control.node, c"value")
		int changed = strcmp(value, control.editor.buf.data) != 0
		if (changed): ui_textarea_set(&control.editor, value)
		if (changed || binding.selection_revision != control.selection_revision):
			int start = win_focus_byte_offset(value, binding.selection.start)
			int end = win_focus_byte_offset(value, binding.selection.end)
			int caret = end
			int anchor = start
			if (binding.selection.direction == 2):
				caret = start
				anchor = end
			ui_textarea_set_caret(&control.editor, caret)
			control.editor.caret_goal_col = control.editor.caret_col
			control.editor.sel_anchor = anchor
			control.selection_revision = binding.selection_revision
		control.native_caret = ui_textarea_caret_offset(&control.editor)
		control.native_anchor = control.editor.sel_anchor
		control.native_length = control.editor.buf.length
	forms.native_focus = ctx.focus

void win_input_after(win_script* script, win_forms* forms, ui_context* ctx):
	if (script == 0 || forms == 0): return
	if (ctx.focus != forms.native_focus):
		win_script_focus_input(script, win_input_focus_node(forms, ctx.focus), 1)
	# A focus handler can redirect native focus or change the DOM value/range.
	# Its changes take precedence over the widget frame that triggered focus.
	win_input_apply_focus(script, forms, ctx)
	for i in range(forms.controls.length):
		win_control* control = forms.controls[i]
		win_dom_binding* binding = win_input_binding(script, control.node)
		if (binding == 0 || win_text_selection_applies(control.node) == 0): continue
		if (control.selection_revision == -1 && binding.selection_revision == 0): control.selection_revision = 0
		if (binding.selection_revision != control.selection_revision): continue
		char* value = win_attr(control.node, c"value")
		if (strcmp(value, control.editor.buf.data) != 0): continue
		int caret = ui_textarea_caret_offset(&control.editor)
		int anchor = control.editor.sel_anchor
		if (anchor < 0): anchor = caret
		int old_anchor = control.native_anchor
		if (old_anchor < 0): old_anchor = control.native_caret
		if (caret == control.native_caret && anchor == old_anchor && control.editor.buf.length == control.native_length): continue
		int first = win_focus_unit_offset(value, min(caret, anchor))
		int last = win_focus_unit_offset(value, max(caret, anchor))
		binding.selection.start = first
		binding.selection.end = last
		binding.selection.direction = 0
		if (first != last):
			binding.selection.direction = 1
			if (caret < anchor): binding.selection.direction = 2
		binding.selection_revision = binding.selection_revision + 1
		control.selection_revision = binding.selection_revision
	forms.native_focus = ctx.focus
