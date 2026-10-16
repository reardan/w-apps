# Per-page bounded JavaScript realm with synchronous host properties and stable
# DOM wrapper identity. Native mutation owns data until document teardown.
import win.document
import win.resources
import win.cssom
import win.storage
import win.modules
import win.canvas
import win.wasm
import win.web_host
import win.text_selection
import win.events
import win.event_handlers
import win.pointer
import win.focus
import win.keyboard_state
import win.abort
import lib.time
import libs.extras.javascript.runtime

struct win_dom_binding:
	js_value* child_nodes
	int selection_revision
	win_text_selection selection
	js_value* computed
	win_canvas* canvas
	js_value* gl
	html_node* node
	js_value* object
	void* context
	js_value* style

struct win_script_listener:
	int handler
	html_node* node
	char* event
	js_value* callback
	int capture
	int once
	int passive

struct win_script_timer:
	int id
	int due
	int interval
	js_value* holder
	js_value* callback
	list[js_value*] args

struct win_script:
	win_keyboard_state keyboard
	html_node* active_focus
	int focus_revision
	int focus_serial
	int focus_depth
	int focus_scroll
	int execution_budget
	win_pointer_state pointer
	win_abort_context* aborts
	win_web_viewport viewport
	int layout_width
	char* address
	win_wasm_realm* wasm
	win_modules* modules
	win_module_source* active_module
	js_module* evaluating_module
	list[win_script_timer*] animation_frames
	int animation_id
	int time_origin
	int frame_time
	win_script_timer* executing_timer
	int stopped_loading
	list[win_script_timer*] timers
	int timer_id
	int now_ms
	win_storage_context* local_store
	win_storage_context* session_store
	char* origin
	win_page* page
	js_runtime* runtime
	list[win_dom_binding*] bindings
	list[win_script_listener*] listeners
	list[html_node*] scripts
	int next_script
	int ready
	int dom_ready
	html_node* window_node
	int dirty
	int styles_dirty
	int failures
	char* error
	js_value* event
	int dom_bytes
	list[char*] console

# Installed only during synchronous bounded host entry, restored afterward.
win_script* win_active_script
int win_script_graphics_available

int win_script_set_execution_budget(win_script* script, int budget):
	if (script == 0 || budget < 1 || budget > WIN_EXECUTION_MAX): return 0
	if (script.runtime.running || script.runtime.async_tasks.length > 0): return 0
	script.execution_budget = budget
	script.wasm.execution_budget = budget
	return 1

void win_dom_set_attr(html_node* node, char* name, char* value):
	if (node == 0): return
	html_attribute* attr = html_attribute_find(node.attributes, name)
	if (attr == 0):
		attr = new html_attribute()
		attr.name = strclone(name)
		attr.next = node.attributes
		node.attributes = attr
	else: free(attr.value)
	attr.value = strclone(value)
	attr.value_length = strlen(value)

void win_dom_remove_attr(html_node* node, char* name):
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

void win_dom_text_append(html_node* node, string_builder* text):
	if (node == 0 || text.length >= 65536): return
	if (win_active_script != 0):
		if (win_active_script.runtime.remaining <= 0):
			js_runtime_fail(win_active_script.runtime, 5, c"DOM traversal budget")
			return
		win_active_script.runtime.remaining = win_active_script.runtime.remaining - 1
	if (node.kind == HTML_TEXT):
		int count = node.text_length
		if (count > 65536 - text.length): count = 65536 - text.length
		string_append_bytes(text, node.text, count)
	else:
		html_node* child = node.first_child
		while (child != 0):
			win_dom_text_append(child, text)
			child = child.next_sibling

char* win_dom_text(html_node* node):
	string_builder* text = string_new()
	win_dom_text_append(node, text)
	char* result = text.data
	free(text)
	return result

html_node* win_dom_create(win_script* script, int kind, char* text):
	html_document* doc = script.page.html
	if (doc.node_count >= 20000 || strlen(text) > 65536 || script.dom_bytes > 4194304 - strlen(text)):
		js_runtime_fail(script.runtime, 5, c"DOM node limit")
		return 0
	script.dom_bytes = script.dom_bytes + strlen(text)
	html_node* node = new html_node()
	node.kind = kind
	if (kind == HTML_TEXT):
		node.text = strclone(text)
		node.text_length = strlen(text)
	else: node.name = strclone(text)
	node.allocation_next = doc.allocations
	doc.allocations = node
	doc.node_count = doc.node_count + 1
	return node

void win_dom_detach(html_node* node):
	html_node* parent = node.parent
	if (parent == 0): return
	html_node* previous = 0
	html_node* child = parent.first_child
	while (child != 0):
		if (child == node):
			if (previous == 0): parent.first_child = child.next_sibling
			else: previous.next_sibling = child.next_sibling
			if (parent.last_child == child): parent.last_child = previous
			break
		previous = child
		child = child.next_sibling
	node.parent = 0
	node.next_sibling = 0

void win_dom_set_text(win_script* script, html_node* node, char* text):
	if (strlen(text) > 65536 || script.dom_bytes > 4194304 - strlen(text)):
		js_runtime_fail(script.runtime, 5, c"DOM text or mutation allocation limit")
		return
	if (node.kind == HTML_TEXT):
		script.dom_bytes = script.dom_bytes + strlen(text)
		free(node.text)
		node.text = strclone(text)
		node.text_length = strlen(text)
	else:
		html_node* replacement = win_dom_create(script, HTML_TEXT, text)
		if (replacement == 0): return
		while (node.first_child != 0): win_dom_detach(node.first_child)
		replacement.parent = node
		node.first_child = replacement
		node.last_child = replacement
	script.dirty = 1
	script.styles_dirty = 1

js_value* win_js_string(js_runtime* rt, char* text):
	js_text* units = js_runtime_key(text)
	if (units == 0): return rt.undefined_value
	js_value* value = js_runtime_string(rt, units)
	js_text_free(units)
	return value

char* win_js_text(js_value* value):
	if (value.kind == 4):
		int length = 0
		char* text = js_text_to_utf8(value.text, &length)
		if (text != 0 && strlen(text) == length): return text
		free(text)
		return strclone(c"")
	if (value.kind == 3):
		if (value.number == 0.0): return strclone(c"0")
		char* text = f64toa(value.number)
		int length = strlen(text)
		# DOM string conversion does not keep a redundant decimal suffix.
		if (length > 2 && text[length - 2] == '.' && text[length - 1] == '0'): text[length - 2] = 0
		return text
	if (value.kind == 2 && value.number != 0.0): return strclone(c"true")
	if (value.kind == 2): return strclone(c"false")
	if (value.kind == 1): return strclone(c"null")
	return strclone(c"undefined")

char* win_dom_property(int index):
	if (index == 0): return c"textContent"
	if (index == 1): return c"value"
	if (index == 2): return c"id"
	if (index == 3): return c"className"
	if (index == 4): return c"checked"
	return c"hidden"

char* win_dom_attribute(int index):
	if (index == 3): return c"class"
	return win_dom_property(index)

char* win_style_property(int index):
	if (index == 0): return c"cssText"
	if (index == 1): return c"color"
	if (index == 2): return c"backgroundColor"
	if (index == 3): return c"display"
	if (index == 4): return c"fontSize"
	if (index == 5): return c"fontWeight"
	if (index == 6): return c"width"
	if (index == 7): return c"height"
	if (index == 8): return c"margin"
	if (index == 9): return c"padding"
	if (index == 10): return c"border"
	if (index == 11): return c"flex"
	if (index == 12): return c"flexGrow"
	if (index == 13): return c"flexShrink"
	if (index == 14): return c"flexBasis"
	return c"justifyContent"

char* win_style_attribute(int index):
	if (index == 2): return c"background-color"
	if (index == 4): return c"font-size"
	if (index == 5): return c"font-weight"
	if (index == 12): return c"flex-grow"
	if (index == 13): return c"flex-shrink"
	if (index == 14): return c"flex-basis"
	if (index == 15): return c"justify-content"
	return win_style_property(index)

int win_dom_canvas_dimension(html_node* node, char* name):
	int fallback = 300
	if (strcmp(name, c"height") == 0): fallback = 150
	return min(4096, win_canvas_attribute(node, name, fallback))

void win_script_layout(win_script* script);

js_value* win_script_dispatch_host(void* runtime, void* context, js_value* receiver, list[js_value*] args);

void win_dom_hierarchy_error(js_runtime* rt):
	js_value* error = js_runtime_alloc(rt, 5)
	js_runtime_set(rt, error, c"name", win_js_string(rt, c"HierarchyRequestError"))
	js_runtime_set(rt, error, c"message", win_js_string(rt, c"Replacement would create an invalid DOM hierarchy"))
	js_runtime_throw(rt, error)

int win_dom_bounded_height(js_runtime* rt, html_node* node, int remaining_depth):
	if (remaining_depth <= 0 || rt.remaining <= 0):
		js_runtime_fail(rt, 5, c"Replacement DOM traversal limit")
		return 0
	rt.remaining = rt.remaining - 1
	int height = 1
	html_node* child = node.first_child
	while (child != 0 && rt.completion.status == 0):
		height = max(height, 1 + win_dom_bounded_height(rt, child, remaining_depth - 1))
		child = child.next_sibling
	return height

js_value* win_dom_replace_children(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_dom_binding* binding = cast(win_dom_binding*, context)
	win_script* script = cast(win_script*, binding.context)
	html_node* parent = binding.node
	if (receiver != binding.object || parent.kind != HTML_START):
		js_runtime_fail(rt, 2, c"replaceChildren requires an Element receiver")
		return rt.undefined_value
	list[html_node*] nodes = new list[html_node*]
	for i in range(args.length):
		if (rt.completion.status != 0): break
		if (script.bindings.length > rt.remaining):
			js_runtime_fail(rt, 5, c"Replacement DOM wrapper lookup budget")
			break
		rt.remaining = rt.remaining - script.bindings.length
		html_node* node = 0
		for j in range(script.bindings.length):
			if (script.bindings[j].object == args[i]): node = script.bindings[j].node
		if (node == 0):
			if (args[i].kind >= 5):
				js_runtime_fail(rt, 6, c"replaceChildren object string conversion is unsupported")
				break
			char* text = 0
			if (args[i].kind == 4):
				int length = 0
				text = js_text_to_utf8(args[i].text, &length)
				if (text == 0 || strlen(text) != length):
					free(text)
					js_runtime_fail(rt, 6, c"DOM text requires scalar UTF-8 without NUL")
					break
			else: text = win_js_text(args[i])
			node = win_dom_create(script, HTML_TEXT, text)
			free(text)
			if (node == 0): break
		if (node.kind != HTML_START && node.kind != HTML_TEXT):
			win_dom_hierarchy_error(rt)
			break
		int depth = 0
		html_node* ancestor = parent
		while (ancestor != 0 && rt.completion.status == 0):
			if (ancestor == node):
				win_dom_hierarchy_error(rt)
				break
			if (depth >= 128 || rt.remaining <= 0):
				js_runtime_fail(rt, 5, c"Replacement DOM ancestry limit")
				break
			rt.remaining = rt.remaining - 1
			depth = depth + 1
			ancestor = ancestor.parent
		if (rt.completion.status != 0): break
		win_dom_bounded_height(rt, node, 128 - depth)
		if (rt.completion.status != 0): break
		nodes.push(node)
	# Reserve an upper bound for linked-list removal before changing the tree.
	# Conversion/validation failures leave the target's existing children intact.
	int cost = script.page.html.node_count * (nodes.length + 1)
	if (rt.completion.status == 0 && cost > rt.remaining): js_runtime_fail(rt, 5, c"Replacement DOM mutation budget")
	if (rt.completion.status == 0):
		rt.remaining = rt.remaining - cost
		while (parent.first_child != 0): win_dom_detach(parent.first_child)
		for i in range(nodes.length):
			html_node* node = nodes[i]
			win_dom_detach(node)
			node.parent = parent
			if (parent.last_child != 0): parent.last_child.next_sibling = node
			else: parent.first_child = node
			parent.last_child = node
		script.dirty = 1
		script.styles_dirty = 1
	__w_list_free(cast(__w_list*, nodes))
	return rt.undefined_value

# Selection methods retain their owning node but reject a forged receiver.
js_value* win_dom_selection_range(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_dom_binding* b = cast(win_dom_binding*, context)
	if (receiver != b.object || args.length < 2):
		js_runtime_fail(rt, 2, c"setSelectionRange requires a text control and two arguments")
		return rt.undefined_value
	if (win_text_selection_applies(b.node) == 0):
		win_text_selection_invalid(rt)
		return rt.undefined_value
	int start = win_text_selection_index(rt, args[0])
	int end = win_text_selection_index(rt, args[1])
	int direction = 0
	if (args.length > 2):
		if (args[2].kind >= 5):
			js_runtime_fail(rt, 6, c"Selection direction object coercion is unsupported")
			return rt.undefined_value
		direction = win_text_selection_direction(args[2])
	if (rt.completion.status != 0): return rt.undefined_value
	int length = win_text_selection_length(rt, win_attr(b.node, c"value"))
	if (length >= 0):
		win_text_selection_range(&b.selection, length, start, end, direction)
		b.selection_revision = b.selection_revision + 1
	return rt.undefined_value

int win_dom_selection_key(js_text* key):
	if (js_runtime_key_is(key, c"selectionStart")): return 1
	if (js_runtime_key_is(key, c"selectionEnd")): return 2
	if (js_runtime_key_is(key, c"selectionDirection")): return 3
	return 0

int win_dom_handler_supported(win_dom_binding* binding, int index):
	if (index < 0): return 0
	win_script* script = cast(win_script*, binding.context)
	if (binding.node.kind != HTML_START && binding.node.kind != HTML_DOCUMENT): return 0
	char* name = win_event_handler_property(index)
	if (strcmp(name, c"onpopstate") == 0): return binding.node == script.window_node
	if (strcmp(name, c"onvisibilitychange") == 0): return binding.node == script.page.html.root
	return 1

# Handler slots participate in registration order; their callback stays on the
# rooted wrapper so changing it does not disturb shared listener callback roots.
void win_dom_handler_register(win_dom_binding* binding, int index, int enabled):
	win_script* script = cast(win_script*, binding.context)
	char* property = win_event_handler_property(index)
	char* name = property + 2
	for i in range(script.listeners.length):
		win_script_listener* listener = script.listeners[i]
		if (listener.handler && listener.node == binding.node && strcmp(listener.event, name) == 0):
			if (enabled == 0): listener.node = 0
			return
	if (enabled == 0): return
	if (script.listeners.length >= 1024):
		js_runtime_fail(script.runtime, 5, c"DOM handler listener limit")
		return
	win_script_listener* listener = new win_script_listener()
	listener.node = binding.node
	listener.event = strclone(name)
	listener.callback = script.runtime.undefined_value
	listener.handler = 1
	script.listeners.push(listener)

js_value* win_dom_handler_get(js_runtime* rt, win_dom_binding* binding, js_text* key, int index):
	js_value* property = js_runtime_property(binding.object, key)
	if (property != 0): return property.value
	char* name = win_event_handler_property(index)
	html_attribute* attr = html_attribute_find(binding.node.attributes, name)
	if (attr == 0): return js_runtime_alloc(rt, 1)
	string_builder* source = string_from(c"(function(event){")
	string_append(source, attr.value)
	string_append(source, c"});")
	js_value* callback = js_runtime_compile_function(rt, source.data, source.length)
	string_free(source)
	if (rt.completion.status == 0): js_runtime_define_data(rt, binding.object, key, callback, 1, 1, 1)
	return callback

int win_dom_handler_set(js_runtime* rt, win_dom_binding* binding, js_text* key, js_value* value, int index):
	int callable = value.kind == 7 || value.kind == 9
	if (callable == 0): value = js_runtime_alloc(rt, 1)
	if (js_runtime_define_data(rt, binding.object, key, value, 1, 1, 1) == 0): return -1
	win_dom_handler_register(binding, index, callable)
	if (rt.completion.status != 0): return -1
	return 1

void win_dom_handler_attribute(win_dom_binding* binding, char* name, int present):
	int index = win_event_handler_attribute(name)
	if (win_dom_handler_supported(binding, index) == 0): return
	win_script* script = cast(win_script*, binding.context)
	js_runtime* rt = script.runtime
	js_text* key = js_runtime_key(name)
	if (present): js_runtime_delete(rt, binding.object, key)
	else: js_runtime_define_data(rt, binding.object, key, js_runtime_alloc(rt, 1), 1, 1, 1)
	js_text_free(key)
	win_dom_handler_register(binding, index, present)

# All listed properties operate on native state at the property access itself.
# Unknown properties fall back to the runtime's ordinary object semantics.
js_value* win_dom_focus(void* runtime, void* context, js_value* receiver, list[js_value*] args);
js_value* win_dom_blur(void* runtime, void* context, js_value* receiver, list[js_value*] args);
html_node* win_script_active_element(win_script* script);
js_value* win_script_wrap(win_script* script, html_node* node);

import win.dom_tree

js_value* win_dom_get(void* runtime, void* context, js_value* receiver, js_text* key):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_dom_binding* b = cast(win_dom_binding*, context)
	win_script* script = cast(win_script*, b.context)
	if (receiver != b.object): return 0
	js_value* tree_value = win_dom_tree_get(b, key)
	if (tree_value != 0): return tree_value
	int handler = win_event_handler_index(key)
	if (win_dom_handler_supported(b, handler)): return win_dom_handler_get(rt, b, key, handler)
	if (b.node == script.page.html.root && js_runtime_key_is(key, c"activeElement")): return win_script_wrap(script, win_script_active_element(script))
	if (b.node.kind == HTML_START && js_runtime_key_is(key, c"tabIndex")): return js_runtime_number(rt, cast(float64, win_focus_tab_index(b.node)))
	if (win_text_selection_control(b.node) && js_runtime_key_is(key, c"readOnly")): return js_runtime_boolean(rt, win_form_has(b.node, c"readonly"))
	if (win_text_selection_control(b.node) && win_dom_selection_key(key)):
		if (win_text_selection_applies(b.node) == 0): return js_runtime_alloc(rt, 1)
		int length = win_text_selection_length(rt, win_attr(b.node, c"value"))
		if (length < 0): return rt.undefined_value
		win_text_selection_clamp(&b.selection, length)
		if (win_dom_selection_key(key) == 1): return js_runtime_number(rt, cast(float64, b.selection.start))
		if (win_dom_selection_key(key) == 2): return js_runtime_number(rt, cast(float64, b.selection.end))
		return win_web_string(rt, win_text_selection_direction_name(b.selection.direction))
	if (b.node == script.window_node): return win_web_viewport_get(rt, &script.viewport, key)
	if (js_runtime_key_is(key, c"offsetWidth") || js_runtime_key_is(key, c"offsetHeight") || js_runtime_key_is(key, c"clientWidth") || js_runtime_key_is(key, c"clientHeight")):
		win_script_layout(script)
		return win_web_dimension(rt, script.page, b.node, key)
	if (win_tag(b.node, c"canvas")):
		if (js_runtime_key_is(key, c"width")): return js_runtime_number(rt, cast(float64, win_dom_canvas_dimension(b.node, c"width")))
		if (js_runtime_key_is(key, c"height")): return js_runtime_number(rt, cast(float64, win_dom_canvas_dimension(b.node, c"height")))
	if (js_runtime_key_is(key, c"style")): return b.style
	if (b.node == script.page.html.root):
		if (js_runtime_key_is(key, c"title")): return win_js_string(rt, script.page.title)
		if (js_runtime_key_is(key, c"readyState")):
			if (script.ready): return win_js_string(rt, c"complete")
			if (script.dom_ready): return win_js_string(rt, c"interactive")
			return win_js_string(rt, c"loading")
	for k in range(6):
		if (js_runtime_key_is(key, win_dom_property(k))):
			if (k >= 4): return js_runtime_boolean(rt, html_attribute_find(b.node.attributes, win_dom_attribute(k)) != 0)
			if (k == 0):
				if (b.node.kind == HTML_DOCUMENT): return js_runtime_alloc(rt, 1)
				char* text = win_dom_text(b.node)
				js_value* value = win_js_string(rt, text)
				free(text)
				return value
			return win_js_string(rt, win_attr(b.node, win_dom_attribute(k)))
	return 0

# Presence never reads values, flushes layout, or invokes a property getter.
int win_dom_has(void* runtime, void* context, js_value* receiver, js_text* key):
	win_dom_binding* b = cast(win_dom_binding*, context)
	win_script* script = cast(win_script*, b.context)
	if (receiver != b.object): return 0
	if (win_dom_tree_key(b, key) != 0): return 1
	if (win_dom_handler_supported(b, win_event_handler_index(key))): return 1
	if (b.node == script.window_node): return win_web_viewport_has(key)
	if (b.node == script.page.html.root):
		if (js_runtime_key_is(key, c"activeElement") || js_runtime_key_is(key, c"title") || js_runtime_key_is(key, c"readyState")): return 1
	if (b.node.kind == HTML_START && js_runtime_key_is(key, c"tabIndex")): return 1
	if (win_text_selection_control(b.node) && (win_dom_selection_key(key) || js_runtime_key_is(key, c"readOnly"))): return 1
	if (win_tag(b.node, c"canvas") && (js_runtime_key_is(key, c"width") || js_runtime_key_is(key, c"height"))): return 1
	if (js_runtime_key_is(key, c"style") || js_runtime_key_is(key, c"offsetWidth") || js_runtime_key_is(key, c"offsetHeight") || js_runtime_key_is(key, c"clientWidth") || js_runtime_key_is(key, c"clientHeight")): return 1
	for i in range(6):
		if (js_runtime_key_is(key, win_dom_property(i))): return 1
	return 0

int win_style_has(void* runtime, void* context, js_value* receiver, js_text* key):
	win_dom_binding* b = cast(win_dom_binding*, context)
	if (receiver != b.style): return 0
	for i in range(16):
		if (js_runtime_key_is(key, win_style_property(i))): return 1
	return 0

int win_style_set(void* runtime, void* context, js_value* receiver, js_text* key, js_value* value);

int win_dom_set(void* runtime, void* context, js_value* receiver, js_text* key, js_value* value):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_dom_binding* b = cast(win_dom_binding*, context)
	win_script* script = cast(win_script*, b.context)
	if (receiver != b.object): return 0
	int tree_result = win_dom_tree_set(b, key, value)
	if (tree_result != 0): return tree_result
	int handler = win_event_handler_index(key)
	if (win_dom_handler_supported(b, handler)): return win_dom_handler_set(rt, b, key, value, handler)
	if (b.node == script.page.html.root && js_runtime_key_is(key, c"activeElement")): return 1
	if (b.node.kind == HTML_START && js_runtime_key_is(key, c"tabIndex")):
		if (value.kind != 3):
			js_runtime_fail(rt, 6, c"tabIndex numeric coercion is unsupported")
			return -1
		int index = js_binary_uint(value.number, 32)
		if (index >= 2147483648.0): index = cast(int, cast(float64, index) - 4294967296.0)
		char* text = itoa(index)
		win_dom_set_attr(b.node, c"tabindex", text)
		free(text)
		return 1
	if (win_text_selection_control(b.node) && js_runtime_key_is(key, c"readOnly")):
		if (js_runtime_truth(value)): win_dom_set_attr(b.node, c"readonly", c"")
		else: win_form_unset(b.node, c"readonly")
		return 1
	int selection_key = win_dom_selection_key(key)
	if (win_text_selection_control(b.node) && selection_key):
		if (win_text_selection_applies(b.node) == 0):
			win_text_selection_invalid(rt)
			return -1
		int length = win_text_selection_length(rt, win_attr(b.node, c"value"))
		if (length < 0): return -1
		win_text_selection_clamp(&b.selection, length)
		int start = b.selection.start
		int end = b.selection.end
		int direction = b.selection.direction
		if (selection_key == 3):
			if (value.kind >= 5): js_runtime_fail(rt, 6, c"Selection direction object coercion is unsupported")
			direction = win_text_selection_direction(value)
		else:
			int index = win_text_selection_index(rt, value)
			if (selection_key == 1):
				start = index
				end = max(start, end)
			else: end = index
		if (rt.completion.status != 0): return -1
		win_text_selection_range(&b.selection, length, start, end, direction)
		b.selection_revision = b.selection_revision + 1
		return 1
	if (win_tag(b.node, c"canvas") && (js_runtime_key_is(key, c"width") || js_runtime_key_is(key, c"height"))):
		if (value.kind != 3 || value.number < 0.0 || value.number > 4096.0 || value.number != value.number):
			js_runtime_fail(rt, 2, c"Canvas dimension must be between 0 and 4096")
			return -1
		int dimension = cast(int, value.number)
		char* name = c"width"
		if (js_runtime_key_is(key, c"height")): name = c"height"
		int width = win_dom_canvas_dimension(b.node, c"width")
		int height = win_dom_canvas_dimension(b.node, c"height")
		if (strcmp(name, c"width") == 0): width = dimension
		else: height = dimension
		if (win_canvas_dimensions(width, height) == 0):
			js_runtime_fail(rt, 5, c"Canvas pixel budget")
			return -1
		if (b.canvas != 0 && win_canvas_resize(b.canvas, width, height) == 0): return -1
		char* text = itoa(dimension)
		win_dom_set_attr(b.node, name, text)
		free(text)
		script.dirty = 1
		return 1
	if (js_runtime_key_is(key, c"style")):
		js_text* css_text = js_runtime_key(c"cssText")
		int result = win_style_set(rt, context, b.style, css_text, value)
		js_text_free(css_text)
		return result
	if (b.node == script.page.html.root):
		if (js_runtime_key_is(key, c"readyState")): return 1
		if (js_runtime_key_is(key, c"title")):
			char* text = win_js_text(value)
			if (strlen(text) > 65536 || script.dom_bytes > 4194304 - strlen(text)):
				free(text)
				js_runtime_fail(rt, 5, c"DOM title allocation limit")
				return -1
			script.dom_bytes = script.dom_bytes + strlen(text)
			free(script.page.title)
			script.page.title = text
			script.dirty = 1
			return 1
	for k in range(6):
		if (js_runtime_key_is(key, win_dom_property(k))):
			if (k >= 4):
				if (js_runtime_truth(value)): win_dom_set_attr(b.node, win_dom_attribute(k), c"")
				else: win_dom_remove_attr(b.node, win_dom_attribute(k))
			else:
				char* text = win_js_text(value)
				if (k == 0):
					if (value.kind == 1): text[0] = 0
					if (b.node.kind != HTML_DOCUMENT): win_dom_set_text(script, b.node, text)
				else if (strlen(text) <= 65536 && script.dom_bytes <= 4194304 - strlen(text)):
					script.dom_bytes = script.dom_bytes + strlen(text)
					if (k == 1 && win_text_selection_applies(b.node) && strcmp(text, win_attr(b.node, c"value")) != 0):
						int length = win_text_selection_length(rt, text)
						if (length < 0):
							free(text)
							return -1
						win_text_selection_range(&b.selection, length, length, length, 0)
						b.selection_revision = b.selection_revision + 1
					win_dom_set_attr(b.node, win_dom_attribute(k), text)
				else: js_runtime_fail(rt, 5, c"DOM mutation allocation limit")
				free(text)
			script.dirty = 1
			if (rt.completion.status != 0): return -1
			return 1
	return 0

int win_style_store(win_dom_binding* b, char* text):
	win_script* script = cast(win_script*, b.context)
	if (text == 0): return 1
	int length = strlen(text)
	if (length > 65536 || script.dom_bytes > 4194304 - length):
		free(text)
		js_runtime_fail(script.runtime, 5, c"DOM style allocation limit")
		return -1
	win_dom_set_attr(b.node, c"style", text)
	script.dom_bytes = script.dom_bytes + length
	script.dirty = 1
	free(text)
	return 1

js_value* win_style_get(void* runtime, void* context, js_value* receiver, js_text* key):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_dom_binding* b = cast(win_dom_binding*, context)
	if (receiver != b.style): return 0
	for k in range(16):
		if (js_runtime_key_is(key, win_style_property(k))):
			char* text = 0
			if (k == 0): text = win_cssom_edit(win_attr(b.node, c"style"), 0, c"", c"")
			else: text = win_cssom_get(win_attr(b.node, c"style"), win_style_attribute(k), 0)
			js_value* result = win_js_string(rt, text)
			free(text)
			return result
	return 0

int win_style_set(void* runtime, void* context, js_value* receiver, js_text* key, js_value* value):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_dom_binding* b = cast(win_dom_binding*, context)
	if (receiver != b.style): return 0
	for k in range(16):
		if (js_runtime_key_is(key, win_style_property(k))):
			char* text = win_js_text(value)
			if (strlen(text) > 65536):
				free(text)
				js_runtime_fail(rt, 5, c"DOM style input limit")
				return -1
			char* updated = 0
			if (k == 0): updated = win_cssom_edit(text, 0, c"", c"")
			else: updated = win_cssom_edit(win_attr(b.node, c"style"), win_style_attribute(k), text, c"")
			free(text)
			return win_style_store(b, updated)
	return 0

# Retained compatibility entry points: properties no longer need synchronization.
void win_script_sync(win_script* script):
	if (script != 0 && script.styles_dirty):
		win_page_refresh_styles(script.page)
		script.styles_dirty = 0

js_value* win_dom_pointer_set(void* runtime, void* context, js_value* receiver, list[js_value*] args);
js_value* win_dom_pointer_release(void* runtime, void* context, js_value* receiver, list[js_value*] args);
js_value* win_dom_pointer_has(void* runtime, void* context, js_value* receiver, list[js_value*] args);

js_value* win_script_wrap(win_script* script, html_node* node):
	js_runtime* rt = script.runtime
	if (node == 0): return js_runtime_alloc(rt, 1)
	for i in range(script.bindings.length):
		if (script.bindings[i].node == node): return script.bindings[i].object
	if (script.bindings.length >= 1024):
		js_runtime_fail(rt, 5, c"DOM wrapper limit")
		return rt.undefined_value
	list[js_value*] args = new list[js_value*]
	args.push(js_runtime_number(rt, cast(float64, script.bindings.length)))
	js_value* object = js_runtime_call(rt, js_runtime_get(rt, rt.global, c"__winNode"), args)
	__w_list_free(cast(__w_list*, args))
	if (rt.completion.status != 0): return rt.undefined_value
	win_dom_binding* b = new win_dom_binding()
	b.node = node
	b.object = object
	b.context = script
	b.style = js_runtime_get(rt, object, c"style")
	script.bindings.push(b)
	js_runtime_root(rt, object)
	win_dom_tree_install(b)
	js_runtime_set(rt, object, c"dispatchEvent", js_runtime_host_callable(rt, b, win_script_dispatch_host))
	if (node.kind == HTML_START): js_runtime_set(rt, object, c"replaceChildren", js_runtime_host_callable(rt, b, win_dom_replace_children))
	if (node.kind == HTML_START):
		js_runtime_set(rt, object, c"focus", js_runtime_host_callable(rt, b, win_dom_focus))
		js_runtime_set(rt, object, c"blur", js_runtime_host_callable(rt, b, win_dom_blur))
		js_runtime_set(rt, object, c"setPointerCapture", js_runtime_host_callable(rt, b, win_dom_pointer_set))
		js_runtime_set(rt, object, c"releasePointerCapture", js_runtime_host_callable(rt, b, win_dom_pointer_release))
		js_runtime_set(rt, object, c"hasPointerCapture", js_runtime_host_callable(rt, b, win_dom_pointer_has))
	if (win_text_selection_control(node)):
		js_runtime_set(rt, object, c"setSelectionRange", js_runtime_host_callable(rt, b, win_dom_selection_range))
	js_runtime_set_host_hooks(rt, b.object, b, win_dom_get, win_dom_set)
	js_runtime_set_host_has(rt, b.object, win_dom_has)
	js_runtime_set_host_hooks(rt, b.style, b, win_style_get, win_style_set)
	js_runtime_set_host_has(rt, b.style, win_style_has)
	html_attribute* attr = node.attributes
	while (attr != 0):
		int handler = win_event_handler_attribute(attr.name)
		if (win_dom_handler_supported(b, handler)): win_dom_handler_register(b, handler, 1)
		attr = attr.next
	char* name = node.name
	if (name == 0): name = c"#document"
	js_runtime_set(rt, object, c"tagName", win_js_string(rt, name))
	return object

void win_dom_query_parsed(win_script* script, html_node* node, char* selector, css_document* css, list[html_node*] found):
	if (node == 0 || found.length >= 1024): return
	if (script.runtime.remaining <= 0):
		js_runtime_fail(script.runtime, 5, c"DOM query budget")
		return
	script.runtime.remaining = script.runtime.remaining - 1
	int match = 0
	if (node.kind == HTML_START):
		if (css == 0): match = strcmp(win_attr(node, c"id"), selector) == 0
		else: match = win_selector_list_match(css, 0, css.tokens.length, node) >= 0
	if (match): found.push(node)
	html_node* child = node.first_child
	while (child != 0):
		win_dom_query_parsed(script, child, selector, css, found)
		child = child.next_sibling

void win_dom_query(win_script* script, html_node* node, char* selector, int by_id, list[html_node*] found):
	css_document* css = 0
	if (by_id == 0):
		css = css_parse_selectors_n(selector, strlen(selector), 0)
		if (css.failed || win_selector_list_valid(css, 0, css.tokens.length) == 0):
			css_document_free(css)
			return
	win_dom_query_parsed(script, node, selector, css, found)
	if (css != 0): css_document_free(css)

js_value* win_script_select(win_script* script, html_node* node, char* operation, char* selector):
	js_runtime* rt = script.runtime
	int* previous_budget = win_selector_budget
	win_selector_budget = &rt.remaining
	css_document* css = 0
	if (strcmp(operation, c"id") != 0):
		css = css_parse_selectors_n(selector, strlen(selector), 0)
		if (css.failed || win_selector_list_valid(css, 0, css.tokens.length) == 0):
			css_document_free(css)
			win_selector_budget = previous_budget
			if (rt.remaining <= 0):
				js_runtime_fail(rt, 5, c"DOM selector budget")
				return rt.undefined_value
			js_value* error = js_runtime_alloc(rt, 5)
			js_runtime_set(rt, error, c"name", win_js_string(rt, c"SyntaxError"))
			js_runtime_set(rt, error, c"message", win_js_string(rt, c"Invalid or unsupported selector"))
			js_runtime_throw(rt, error)
			return rt.undefined_value
	js_value* result = js_runtime_alloc(rt, 1)
	if (strcmp(operation, c"matches") == 0 || strcmp(operation, c"closest") == 0):
		int self_only = strcmp(operation, c"matches") == 0
		if (self_only): result = js_runtime_boolean(rt, 0)
		html_node* candidate = node
		while (candidate != 0 && candidate.kind == HTML_START):
			if (rt.remaining <= 0):
				js_runtime_fail(rt, 5, c"DOM query budget")
				break
			rt.remaining = rt.remaining - 1
			if (win_selector_list_match(css, 0, css.tokens.length, candidate) >= 0):
				if (self_only): result = js_runtime_boolean(rt, 1)
				else: result = win_script_wrap(script, candidate)
				break
			if (self_only): break
			candidate = candidate.parent
	else:
		list[html_node*] found = new list[html_node*]
		html_node* child = node.first_child
		while (child != 0):
			win_dom_query_parsed(script, child, selector, css, found)
			child = child.next_sibling
		if (strcmp(operation, c"all") == 0):
			result = js_runtime_alloc(rt, 6)
			for i in range(found.length):
				char* key = itoa(i)
				js_runtime_set(rt, result, key, win_script_wrap(script, found[i]))
				free(key)
			result.array_length = found.length
		else if (found.length > 0): result = win_script_wrap(script, found[0])
		__w_list_free(cast(__w_list*, found))
	if (css != 0): css_document_free(css)
	win_selector_budget = previous_budget
	if (rt.remaining <= 0): js_runtime_fail(rt, 5, c"DOM selector budget")
	return result

int win_dom_height(html_node* node):
	if (node == 0): return 0
	int height = 1
	html_node* child = node.first_child
	while (child != 0):
		int next = 1 + win_dom_height(child)
		if (next > height): height = next
		child = child.next_sibling
	return height

# Removed entries remain stable while dispatch snapshots refer to their indices.
# Roots are shared by callback identity, so release only the final registration.
void win_script_collect_listeners(win_script* script):
	for i in range(script.listeners.length):
		win_script_listener* listener = script.listeners[i]
		if (listener.node == 0):
			int retained = 0
			for k in range(script.listeners.length):
				if (script.listeners[k].node != 0 && script.listeners[k].callback == listener.callback): retained = 1
			if (retained == 0): js_runtime_unroot(script.runtime, listener.callback)
	int kept = 0
	for i in range(script.listeners.length):
		win_script_listener* listener = script.listeners[i]
		if (listener.node != 0):
			script.listeners[kept] = listener
			kept = kept + 1
		else:
			free(listener.event)
			free(listener)
	while (script.listeners.length > kept): script.listeners.pop()

int win_script_capture(js_runtime* rt, list[js_value*] args):
	if (args.length <= 4): return 0
	js_value* options = args[4]
	if (options.kind >= 5 && options.kind <= 9): return js_runtime_truth(js_runtime_get(rt, options, c"capture"))
	return js_runtime_truth(options)

js_value* win_script_gl_host(void* context, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, context)
	win_script* script = win_active_script
	if (script == 0 || script.runtime != rt || args.length < 2 || args[0].kind != 3 || args[1].kind != 4): return rt.undefined_value
	if (args[0].number < 0.0 || args[0].number >= cast(float64, script.bindings.length)): return rt.undefined_value
	int index = cast(int, args[0].number)
	win_canvas* canvas = script.bindings[index].canvas
	if (canvas == 0): return rt.undefined_value
	list[js_value*] call_args = new list[js_value*]
	for i in range(2, args.length): call_args.push(args[i])
	char* method = win_js_text(args[1])
	js_value* result = win_canvas_call(canvas, rt, method, call_args)
	free(method)
	__w_list_free(cast(__w_list*, call_args))
	return result

js_value* win_script_host(void* context, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, context)
	win_script* script = win_active_script
	if (script == 0 || script.runtime != rt || args.length < 2 || args[0].kind != 3 || args[1].kind != 4): return rt.undefined_value
	int index = cast(int, args[0].number)
	if (index < 0 || index >= script.bindings.length): return rt.undefined_value
	html_node* node = script.bindings[index].node
	char* operation = win_js_text(args[1])
	char* text = strclone(c"")
	if (args.length > 2):
		free(text)
		text = win_js_text(args[2])
	win_script_sync(script)
	js_value* result = rt.undefined_value
	if (strcmp(operation, c"id") == 0 || strcmp(operation, c"query") == 0 || strcmp(operation, c"all") == 0 || strcmp(operation, c"matches") == 0 || strcmp(operation, c"closest") == 0):
		result = win_script_select(script, node, operation, text)
	else if (strcmp(operation, c"rect") == 0):
		win_script_layout(script)
		result = win_web_rect(rt, script.page, node, &script.viewport)
	else if (strcmp(operation, c"getContext") == 0):
		result = js_runtime_alloc(rt, 1)
		win_dom_binding* binding = script.bindings[index]
		if (win_tag(node, c"canvas") && strcmp(text, c"webgl2") == 0 && win_script_graphics_available):
			if (binding.canvas == 0):
				int count = 0
				for i in range(script.bindings.length):
					if (script.bindings[i].canvas != 0): count = count + 1
				if (count < 8): binding.canvas = win_canvas_new(node, win_dom_canvas_dimension(node, c"width"), win_dom_canvas_dimension(node, c"height"), 1)
			if (binding.canvas != 0 && binding.canvas.context != 0):
				if (binding.gl == 0):
					list[js_value*] call_args = new list[js_value*]
					call_args.push(js_runtime_number(rt, cast(float64, index)))
					binding.gl = js_runtime_call(rt, js_runtime_get(rt, rt.global, c"__winGLContext"), call_args)
					__w_list_free(cast(__w_list*, call_args))
					js_runtime_set(rt, binding.object, c"__context", binding.gl)
					js_runtime_set(rt, binding.gl, c"canvas", binding.object)
				result = binding.gl
	else if (strcmp(operation, c"get") == 0):
		if (html_attribute_find(node.attributes, text) == 0): result = js_runtime_alloc(rt, 1)
		else: result = win_js_string(rt, win_attr(node, text))
	else if (strcmp(operation, c"set") == 0 && args.length > 3):
		char* value = win_js_text(args[3])
		if (strlen(text) <= 256 && strlen(value) <= 65536 && script.dom_bytes <= 4194304 - strlen(text) - strlen(value)):
			script.dom_bytes = script.dom_bytes + strlen(text) + strlen(value)
			win_dom_set_attr(node, text, value)
			win_dom_handler_attribute(script.bindings[index], text, 1)
			if (win_tag(node, c"canvas") && (strcmp(text, c"width") == 0 || strcmp(text, c"height") == 0)):
				win_canvas* canvas = script.bindings[index].canvas
				if (canvas != 0):
					if (win_canvas_resize(canvas, win_dom_canvas_dimension(node, c"width"), win_dom_canvas_dimension(node, c"height")) == 0): js_runtime_fail(rt, 5, c"Canvas pixel budget")
			script.dirty = 1
			if (win_tag(node, c"link") || win_tag(node, c"style")): script.styles_dirty = 1
		free(value)
	else if (strcmp(operation, c"removeAttr") == 0):
		win_dom_remove_attr(node, text)
		win_dom_handler_attribute(script.bindings[index], text, 0)
		if (win_tag(node, c"canvas") && (strcmp(text, c"width") == 0 || strcmp(text, c"height") == 0)):
			win_canvas* canvas = script.bindings[index].canvas
			if (canvas != 0): win_canvas_resize(canvas, win_dom_canvas_dimension(node, c"width"), win_dom_canvas_dimension(node, c"height"))
		script.dirty = 1
		if (win_tag(node, c"link") || win_tag(node, c"style")): script.styles_dirty = 1
	else if (strcmp(operation, c"create") == 0 || strcmp(operation, c"text") == 0):
		int kind = HTML_START
		if (strcmp(operation, c"text") == 0): kind = HTML_TEXT
		result = win_script_wrap(script, win_dom_create(script, kind, text))
	else if (strcmp(operation, c"append") == 0 && args.length > 2):
		html_node* child = 0
		for i in range(script.bindings.length):
			if (script.bindings[i].object == args[2]): child = script.bindings[i].node
		int valid = child != 0 && child != script.page.html.root
		html_node* ancestor = node
		int depth = 0
		while (ancestor != 0):
			if (ancestor == child): valid = 0
			ancestor = ancestor.parent
			depth = depth + 1
		if (depth + win_dom_height(child) >= 128): valid = 0
		if (valid):
			win_dom_detach(child)
			child.parent = node
			if (node.last_child != 0): node.last_child.next_sibling = child
			else: node.first_child = child
			node.last_child = child
			script.dirty = 1
			script.styles_dirty = 1
			result = args[2]
	else if (strcmp(operation, c"remove") == 0):
		if (node != script.page.html.root): win_dom_detach(node)
		script.dirty = 1
		script.styles_dirty = 1
	else if (strcmp(operation, c"listen") == 0 && args.length > 3 && (args[3].kind == 7 || args[3].kind == 9)):
		int capture = win_script_capture(rt, args)
		int duplicate = 0
		for i in range(script.listeners.length):
			win_script_listener* listener = script.listeners[i]
			if (listener.node == node && strcmp(listener.event, text) == 0 && listener.callback == args[3] && listener.capture == capture): duplicate = 1
		if (duplicate == 0 && (script.listeners.length >= 1024 || strlen(text) > 65536 || script.dom_bytes > 4194304 - strlen(text))):
			js_runtime_fail(rt, 5, c"DOM listener allocation limit")
		else if (duplicate == 0):
			win_script_listener* listener = new win_script_listener()
			listener.node = node
			listener.event = strclone(text)
			script.dom_bytes = script.dom_bytes + strlen(text)
			listener.callback = args[3]
			listener.capture = capture
			if (args.length > 4 && args[4].kind >= 5 && args[4].kind <= 9):
				listener.once = js_runtime_truth(js_runtime_get(rt, args[4], c"once"))
				listener.passive = js_runtime_truth(js_runtime_get(rt, args[4], c"passive"))
			js_runtime_root(rt, listener.callback)
			script.listeners.push(listener)
	else if (strcmp(operation, c"unlisten") == 0 && args.length > 3):
		int capture = win_script_capture(rt, args)
		for i in range(script.listeners.length):
			win_script_listener* listener = script.listeners[i]
			if (listener.node == node && strcmp(listener.event, text) == 0 && listener.callback == args[3] && listener.capture == capture): listener.node = 0
		if (script.event == 0): win_script_collect_listeners(script)
	else if (strcmp(operation, c"classAdd") == 0 || strcmp(operation, c"classRemove") == 0 || strcmp(operation, c"classToggle") == 0 || strcmp(operation, c"classContains") == 0):
		char* classes = win_attr(node, c"class")
		int present = 0
		string_builder* kept = string_new()
		int at = 0
		while (classes[at] != 0):
			while (html_space(classes[at])): at = at + 1
			int start = at
			while (classes[at] != 0 && html_space(classes[at]) == 0): at = at + 1
			if (at == start): break
			if (at - start == strlen(text) && starts_with(classes + start, text)): present = 1
			else:
				if (kept.length != 0): string_append_char(kept, ' ')
				string_append_bytes(kept, classes + start, at - start)
		int enabled = strcmp(operation, c"classAdd") == 0 || (strcmp(operation, c"classToggle") == 0 && present == 0)
		if (strcmp(operation, c"classToggle") == 0 && args.length > 3 && args[3].kind != 0): enabled = js_runtime_truth(args[3])
		if (strcmp(operation, c"classContains") == 0): result = js_runtime_boolean(rt, present)
		else:
			if (enabled):
				if (kept.length != 0): string_append_char(kept, ' ')
				string_append(kept, text)
			if (kept.length <= 65536 && script.dom_bytes <= 4194304 - kept.length):
				win_dom_set_attr(node, c"class", kept.data)
				script.dom_bytes = script.dom_bytes + kept.length
				script.dirty = 1
			result = js_runtime_boolean(rt, enabled)
		string_free(kept)
	else if (strcmp(operation, c"styleGet") == 0 || strcmp(operation, c"stylePriority") == 0 || strcmp(operation, c"styleRemove") == 0):
		char* value = win_cssom_get(win_attr(node, c"style"), text, strcmp(operation, c"stylePriority") == 0)
		result = win_js_string(rt, value)
		free(value)
		if (strcmp(operation, c"styleRemove") == 0): win_style_store(script.bindings[index], win_cssom_edit(win_attr(node, c"style"), text, c"", c""))
	else if (strcmp(operation, c"styleSet") == 0 && args.length > 3):
		char* value = win_js_text(args[3])
		char* priority = strclone(c"")
		if (args.length > 4 && args[4].kind != 0):
			free(priority)
			priority = win_js_text(args[4])
		if (strlen(text) <= 256 && strlen(value) <= 65536 && strlen(priority) <= 16): win_style_store(script.bindings[index], win_cssom_edit(win_attr(node, c"style"), text, value, priority))
		else: js_runtime_fail(rt, 5, c"DOM style input limit")
		free(value)
		free(priority)
	else if (strcmp(operation, c"console") == 0):
		if (script.console.length == 32):
			free(script.console[0])
			for i in range(31): script.console[i] = script.console[i + 1]
			script.console.pop()
		int length = strlen(text)
		if (length > 4096): length = 4096
		script.console.push(substring(text, 0, length))

	free(operation)
	free(text)
	return result

void win_script_result(win_script* script, js_completion* completion):
	if (completion == 0 || completion.status == 0): return
	script.failures = script.failures + 1
	free(script.error)
	script.error = strclone(completion.message)

void win_script_checkpoint(win_script* script);

int win_script_eval(win_script* script, char* source, int length):
	if (script == 0): return 0
	win_script* previous = win_active_script
	win_active_script = script
	js_runtime_collect(script.runtime)
	js_completion* result = js_runtime_eval(script.runtime, source, length, script.execution_budget)
	win_script_sync(script)
	win_script_result(script, result)
	win_script_collect_listeners(script)
	int success = result != 0 && result.status == 0
	if (result != 0 && result.status != 5): win_script_checkpoint(script)
	win_active_script = previous
	return success

js_value* win_script_storage_host(void* context, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, context)
	win_script* script = win_active_script
	if (script == 0 || script.runtime != rt || args.length < 2): return rt.undefined_value
	win_storage_context* store = script.local_store
	if (args[0].number != 0.0): store = script.session_store
	if (store == 0 || script.origin[0] == 0):
		js_value* error = js_runtime_alloc(rt, 5)
		js_runtime_set(rt, error, c"name", win_js_string(rt, c"SecurityError"))
		js_runtime_throw(rt, error)
		return rt.undefined_value
	int operation = cast(int, args[1].number)
	win_storage_context* previous_storage = 0
	if (operation >= 1 && operation <= 3 && store.path != 0):
		previous_storage = win_storage_snapshot(store)
		if (previous_storage == 0):
			js_runtime_throw(rt, js_runtime_error_value(rt, c"Cannot snapshot persistent storage"))
			return rt.undefined_value
	char* key = strclone(c"undefined")
	if (args.length > 2):
		free(key)
		key = win_js_text(args[2])
	int found = -1
	int count = 0
	js_value* result = rt.undefined_value
	if (operation == 0 || operation == 4): result = js_runtime_alloc(rt, 1)
	for i in range(store.entries.length):
		win_storage_entry* entry = store.entries[i]
		if (strcmp(entry.origin, script.origin) != 0): continue
		if (strcmp(entry.key, key) == 0): found = i
		if (operation == 4 && args.length > 2 && args[2].kind == 3 && args[2].number == cast(float64, count)): result = win_js_string(rt, entry.key)
		count = count + 1
	if (operation == 5): result = js_runtime_number(rt, cast(float64, count))
	if (operation == 0 && found >= 0): result = win_js_string(rt, store.entries[found].value)
	if (operation == 2 && found >= 0): win_storage_remove(store, found)
	if (operation == 3):
		int i = store.entries.length - 1
		while (i >= 0):
			if (strcmp(store.entries[i].origin, script.origin) == 0): win_storage_remove(store, i)
			i = i - 1
	if (operation == 1):
		char* value = strclone(c"undefined")
		if (args.length > 3):
			free(value)
			value = win_js_text(args[3])
		int extra = strlen(value)
		if (found >= 0): extra = extra - strlen(store.entries[found].value)
		else: extra = extra + strlen(key) + strlen(script.origin)
		if (strlen(key) > 65536 || strlen(value) > 65536 || store.bytes + extra > 1048576 || (found < 0 && store.entries.length >= 1024)):
			js_value* error = js_runtime_alloc(rt, 5)
			js_runtime_set(rt, error, c"name", win_js_string(rt, c"QuotaExceededError"))
			js_runtime_throw(rt, error)
			free(value)
		else:
			win_storage_entry* entry = 0
			if (found >= 0):
				entry = store.entries[found]
				free(entry.value)
			else:
				entry = new win_storage_entry()
				entry.origin = strclone(script.origin)
				entry.key = strclone(key)
				store.entries.push(entry)
			entry.value = value
			store.bytes = store.bytes + extra
	if (previous_storage != 0):
		if (rt.completion.status == 0):
			int committed = win_storage_commit(store)
			if (committed <= 0):
				if (committed == 0): win_storage_swap(store, previous_storage)
				js_value* error = js_runtime_error_value(rt, c"Persistent storage write failed")
				char* name = c"QuotaExceededError"
				if (committed < 0): name = c"UnknownError"
				js_runtime_set(rt, error, c"name", win_js_string(rt, name))
				js_runtime_throw(rt, error)
		win_storage_free(previous_storage)
	free(key)
	return result

js_value* win_script_storage_get(void* runtime, void* context, js_value* receiver, js_text* key):
	if (js_runtime_key_is(key, c"length") == 0): return 0
	js_runtime* rt = cast(js_runtime*, runtime)
	win_script* script = cast(win_script*, context)
	list[js_value*] args = new list[js_value*]
	args.push(js_runtime_get(rt, receiver, c"__storeKind"))
	args.push(js_runtime_number(rt, 5.0))
	win_script* previous = win_active_script
	win_active_script = script
	js_value* result = win_script_storage_host(rt, args)
	win_active_script = previous
	__w_list_free(cast(__w_list*, args))
	return result

int win_script_storage_has(void* runtime, void* context, js_value* receiver, js_text* key):
	return js_runtime_key_is(key, c"length")

void win_script_bind_storage(win_script* script, win_storage_context* shared_store, win_storage_context* session_store, char* address):
	if (script == 0): return
	script.local_store = shared_store
	script.session_store = session_store
	free(script.origin)
	script.origin = win_storage_origin(address)
	free(script.address)
	script.address = strclone(address)

# Every timer owns a unique rooted object, so listener/job roots never alias.
void win_script_timer_free(win_script* script, win_script_timer* timer):
	js_runtime_unroot(script.runtime, timer.holder)
	__w_list_free(cast(__w_list*, timer.args))
	free(timer)

void win_script_collect_timers(win_script* script):
	int kept = 0
	for i in range(script.timers.length):
		if (script.timers[i].id == 0 && script.timers[i] != script.executing_timer): win_script_timer_free(script, script.timers[i])
		else:
			script.timers[kept] = script.timers[i]
			kept = kept + 1
	while (script.timers.length > kept): script.timers.pop()

js_value* win_script_timer_host(void* context, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, context)
	win_script* script = win_active_script
	if (script == 0 || script.runtime != rt || args.length < 2): return rt.undefined_value
	int operation = cast(int, args[0].number)
	if (operation == 2):
		for i in range(script.timers.length):
			win_script_timer* timer = script.timers[i]
			if (args[1].kind == 3 && cast(float64, timer.id) == args[1].number): timer.id = 0
		win_script_collect_timers(script)
		return rt.undefined_value
	if (args[1].kind != 7 && args[1].kind != 9):
		js_runtime_fail(rt, 2, c"Timer callback must be a function")
		return rt.undefined_value
	win_script_collect_timers(script)
	if (script.timers.length >= 256 || script.timer_id >= 2147483647):
		js_runtime_fail(rt, 5, c"Timer registration limit")
		return rt.undefined_value
	int delay = 0
	if (args.length > 2 && args[2].kind == 3 && args[2].number > 0.0):
		if (args[2].number >= 2147483647.0): delay = 2147483647
		else: delay = cast(int, args[2].number)
	if (operation == 1 && delay < 1): delay = 1
	win_script_timer* timer = new win_script_timer()
	script.timer_id = script.timer_id + 1
	timer.id = script.timer_id
	timer.due = script.now_ms + delay
	if (operation == 1): timer.interval = delay
	timer.callback = args[1]
	timer.args = new list[js_value*]
	timer.holder = js_runtime_alloc(rt, 5)
	js_runtime_root(rt, timer.holder)
	js_runtime_set(rt, timer.holder, c"callback", timer.callback)
	for i in range(args.length - 3):
		timer.args.push(args[i + 3])
		char* key = itoa(i)
		js_runtime_set(rt, timer.holder, key, args[i + 3])
		free(key)
	script.timers.push(timer)
	return js_runtime_number(rt, cast(float64, timer.id))

# Animation callbacks run only when the visible page is about to paint, never
# from network/timer polling. Snapshot ids defer nested registrations one frame.
js_value* win_script_animation_host(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_script* script = cast(win_script*, context)
	if (args.length == 0 || (args[0].kind != 7 && args[0].kind != 9)):
		js_runtime_fail(rt, 2, c"Animation callback must be a function")
		return rt.undefined_value
	if (script.animation_frames.length >= 256 || script.animation_id >= 2147483647):
		js_runtime_fail(rt, 5, c"Animation registration limit")
		return rt.undefined_value
	win_script_timer* frame = new win_script_timer()
	frame.args = new list[js_value*]
	frame.holder = js_runtime_alloc(rt, 5)
	if (rt.completion.status != 0):
		__w_list_free(cast(__w_list*, frame.args))
		free(frame)
		return rt.undefined_value
	js_runtime_root(rt, frame.holder)
	frame.callback = args[0]
	js_runtime_set(rt, frame.holder, c"callback", frame.callback)
	if (rt.completion.status != 0):
		win_script_timer_free(script, frame)
		return rt.undefined_value
	script.animation_id = script.animation_id + 1
	frame.id = script.animation_id
	script.animation_frames.push(frame)
	return js_runtime_number(rt, cast(float64, frame.id))

js_value* win_script_animation_cancel(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_script* script = cast(win_script*, context)
	if (args.length == 0 || args[0].kind != 3): return rt.undefined_value
	for i in range(script.animation_frames.length):
		win_script_timer* frame = script.animation_frames[i]
		if (cast(float64, frame.id) == args[0].number):
			win_script_timer_free(script, frame)
			for j in range(i, script.animation_frames.length - 1): script.animation_frames[j] = script.animation_frames[j + 1]
			script.animation_frames.pop()
			break
	return rt.undefined_value

int win_script_frame_at(win_script* script, int now_ms):
	if (script == 0): return 0
	if (now_ms < script.frame_time): now_ms = script.frame_time
	script.frame_time = now_ms
	int last_id = script.animation_id
	int budget = script.execution_budget
	int count = 0
	win_script* previous = win_active_script
	win_active_script = script
	while (script.animation_frames.length > 0 && budget > 0):
		win_script_timer* frame = script.animation_frames[0]
		if (frame.id > last_id): break
		for i in range(script.animation_frames.length - 1): script.animation_frames[i] = script.animation_frames[i + 1]
		script.animation_frames.pop()
		frame.args.push(js_runtime_number(script.runtime, cast(float64, now_ms - script.time_origin)))
		js_completion* result = js_runtime_invoke_receiver(script.runtime, frame.callback, win_script_wrap(script, script.window_node), frame.args, budget)
		budget = script.runtime.remaining
		win_script_result(script, result)
		if (result.status == 5): budget = 0
		win_script_timer_free(script, frame)
		if (budget > 0):
			result = js_runtime_drain_microtasks(script.runtime, budget)
			budget = script.runtime.remaining
			win_script_result(script, result)
			if (result.status == 5): budget = 0
		count = count + 1
	win_script_sync(script)
	win_script_collect_listeners(script)
	win_active_script = previous
	return count

void win_script_checkpoint(win_script* script):
	if (script == 0): return
	# A larger entry budget can exhaust the value heap before its fuel.
	# Reclaim unrooted temporaries at the next independent task boundary.
	js_runtime_collect(script.runtime)
	win_script* previous = win_active_script
	win_active_script = script
	js_completion* result = js_runtime_drain_microtasks(script.runtime, script.execution_budget)
	win_script_result(script, result)
	win_script_sync(script)
	win_script_collect_listeners(script)
	win_active_script = previous

void win_script_stop(win_script* script):
	if (script == 0): return
	js_runtime_async_cancel(script.runtime)
	for i in range(script.timers.length): win_script_timer_free(script, script.timers[i])
	while (script.timers.length > 0): script.timers.pop()
	for i in range(script.animation_frames.length): win_script_timer_free(script, script.animation_frames[i])
	while (script.animation_frames.length > 0): script.animation_frames.pop()
	win_modules_stop(script.modules)
	js_runtime_clear_microtasks(script.runtime)
	script.next_script = script.scripts.length
	script.stopped_loading = 1
	script.ready = 1

int win_script_has_tasks(win_script* script):
	if (script == 0): return 0
	for i in range(script.timers.length):
		if (script.timers[i].id != 0): return 1
	return 0

int win_script_poll_at(win_script* script, int now_ms):
	if (script == 0): return 0
	if (now_ms > script.now_ms): script.now_ms = now_ms
	win_script_checkpoint(script)
	win_script* previous = win_active_script
	win_active_script = script
	int count = 0
	int budget = script.execution_budget
	int last_id = script.timer_id
	while (count < 64 && budget > 0):
		win_script_timer* next = 0
		for i in range(script.timers.length):
			win_script_timer* timer = script.timers[i]
			if (timer.id == 0 || timer.id > last_id || timer.due > script.now_ms): continue
			if (next == 0): next = timer
			else if (timer.due < next.due || (timer.due == next.due && timer.id < next.id)): next = timer
		if (next == 0): break
		# Remove before invocation: callbacks can cancel or register timers safely.
		for i in range(script.timers.length):
			if (script.timers[i] == next):
				script.timers[i] = script.timers[script.timers.length - 1]
				script.timers.pop()
				break
		if (next.interval > 0):
			next.due = script.now_ms + next.interval
			script.timers.push(next)
		script.executing_timer = next
		js_completion* result = js_runtime_invoke_receiver(script.runtime, next.callback, win_script_wrap(script, script.window_node), next.args, budget)
		budget = script.runtime.remaining
		win_script_result(script, result)
		if (result.status == 5): budget = 0
		script.executing_timer = 0
		if (next.interval == 0): win_script_timer_free(script, next)
		if (budget > 0):
			result = js_runtime_drain_microtasks(script.runtime, budget)
			budget = script.runtime.remaining
			win_script_result(script, result)
			if (result.status == 5): budget = 0
		win_script_sync(script)
		count = count + 1
	win_script_collect_listeners(script)
	win_script_collect_timers(script)
	win_active_script = previous
	return count

int win_script_poll(win_script* script):
	return win_script_poll_at(script, time_monotonic_ms())

void win_script_collect_nodes(win_script* script, html_node* node):
	if (node == 0 || win_tag(node, c"template")): return
	if (win_tag(node, c"script")):
		int known = 0
		for i in range(script.scripts.length):
			if (script.scripts[i] == node): known = 1
		if (known == 0 && script.scripts.length < 512): script.scripts.push(node)
	html_node* child = node.first_child
	while (child != 0):
		win_script_collect_nodes(script, child)
		child = child.next_sibling

# Flush layout for synchronous CSSOM/geometry reads without clearing the
# browser's dirty flag (forms/resource discovery still need to observe it).
void win_script_layout(win_script* script):
	win_script_sync(script)
	int width = max(160, script.layout_width)
	if (script.dirty || script.page.width != width):
		if (script.runtime.remaining < script.page.html.node_count):
			js_runtime_fail(script.runtime, 5, c"DOM layout budget")
			return
		script.runtime.remaining = script.runtime.remaining - script.page.html.node_count
		win_page_layout(script.page, width)

void win_script_set_viewport(win_script* script, int width, int height, float64 ratio, float64 scroll_x, float64 scroll_y):
	if (script == 0): return
	script.viewport.width = cast(float64, width)
	script.viewport.height = cast(float64, height)
	script.viewport.ratio = ratio
	script.viewport.scroll_x = scroll_x
	script.viewport.scroll_y = scroll_y
	script.layout_width = width
	# Identifier lookup uses environment bindings rather than object hooks.
	char*[7] names
	names[0] = c"innerWidth"
	names[1] = c"innerHeight"
	names[2] = c"devicePixelRatio"
	names[3] = c"scrollX"
	names[4] = c"scrollY"
	names[5] = c"pageXOffset"
	names[6] = c"pageYOffset"
	for i in range(7):
		js_text* key = js_runtime_key(names[i])
		js_runtime_set(script.runtime, script.runtime.global, names[i], win_web_viewport_get(script.runtime, &script.viewport, key))
		js_text_free(key)

js_value* win_script_location_get(void* runtime, void* context, js_value* receiver, js_text* key):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_script* script = cast(win_script*, context)
	if (js_runtime_key_is(key, c"search")):
		char* search = win_web_location_search(script.address)
		js_value* result = win_js_string(rt, search)
		free(search)
		return result
	if (js_runtime_key_is(key, c"href")): return win_js_string(rt, script.address)
	return 0

int win_script_location_has(void* runtime, void* context, js_value* receiver, js_text* key):
	return js_runtime_key_is(key, c"search") || js_runtime_key_is(key, c"href")

int win_script_location_set(void* runtime, void* context, js_value* receiver, js_text* key, js_value* value):
	if (js_runtime_key_is(key, c"search") || js_runtime_key_is(key, c"href")):
		js_runtime_fail(cast(js_runtime*, runtime), 6, c"Location navigation is not supported")
		return -1
	return 0

js_value* win_script_computed_get(void* runtime, void* context, js_value* receiver, js_text* key):
	win_dom_binding* binding = cast(win_dom_binding*, context)
	win_script* script = cast(win_script*, binding.context)
	win_script_layout(script)
	return win_web_computed_get(cast(js_runtime*, runtime), script.page, binding.node, key)

int win_script_computed_has(void* runtime, void* context, js_value* receiver, js_text* key):
	return win_web_computed_index(key) >= 0

int win_script_computed_set(void* runtime, void* context, js_value* receiver, js_text* key, js_value* value):
	js_runtime_fail(cast(js_runtime*, runtime), 2, c"Computed style is read-only")
	return -1

js_value* win_script_computed_property(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	if (args.length == 0 || args[0].kind != 4):
		js_runtime_fail(rt, 2, c"getPropertyValue requires a property name")
		return rt.undefined_value
	js_value* result = win_script_computed_get(runtime, context, receiver, args[0].text)
	if (result == 0): return win_js_string(rt, c"")
	return result

js_value* win_script_get_computed(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_script* script = cast(win_script*, context)
	if (args.length > 1 && args[1].kind != 0 && args[1].kind != 1):
		if (args[1].kind != 4 || args[1].text.units.length != 0):
			js_runtime_fail(rt, 6, c"Pseudo-element computed style is unsupported")
			return rt.undefined_value
	if (args.length > 0):
		for i in range(script.bindings.length):
			win_dom_binding* binding = script.bindings[i]
			if (binding.object == args[0] && binding.node.kind == HTML_START):
				if (binding.computed == 0):
					binding.computed = js_runtime_alloc(rt, 5)
					js_runtime_root(rt, binding.computed)
					js_runtime_set(rt, binding.computed, c"getPropertyValue", js_runtime_host_callable(rt, binding, win_script_computed_property))
					js_runtime_set_host_hooks(rt, binding.computed, binding, win_script_computed_get, win_script_computed_set)
					js_runtime_set_host_has(rt, binding.computed, win_script_computed_has)
				return binding.computed
	js_runtime_fail(rt, 2, c"getComputedStyle requires an Element")
	return rt.undefined_value

js_value* win_script_search_get(void* context, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, context)
	if (args.length < 2 || args[0].kind != 4): return rt.undefined_value
	js_text* name = 0
	if (args[1].kind == 4): name = js_text_clone(args[1].text)
	else if (args[1].kind < 4):
		char* text = win_js_text(args[1])
		name = js_runtime_key(text)
		free(text)
	else:
		js_runtime_fail(rt, 6, c"URLSearchParams object coercion is unsupported")
		return rt.undefined_value
	js_value* result = win_web_search_get(rt, args[0].text, name)
	js_text_free(name)
	return result

js_value* win_script_search_new(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	js_value* query = win_js_string(rt, c"")
	if (args.length > 0 && args[0].kind != 0 && args[0].kind != 1):
		if (args[0].kind == 4): query = args[0]
		else if (args[0].kind < 4):
			char* text = win_js_text(args[0])
			query = win_js_string(rt, text)
			free(text)
		else:
			js_runtime_fail(rt, 6, c"URLSearchParams supports string initialization only")
			return rt.undefined_value
	if (query.text.units.length > 65536):
		js_runtime_fail(rt, 5, c"URLSearchParams input limit")
		return rt.undefined_value
	list[js_value*] call_args = new list[js_value*]
	call_args.push(query)
	js_value* result = js_runtime_call(rt, js_runtime_get(rt, rt.global, c"__winSearchObject"), call_args)
	__w_list_free(cast(__w_list*, call_args))
	return result

js_value* win_script_event_new(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_script* script = cast(win_script*, context)
	if (args.length == 0):
		js_runtime_fail(rt, 2, c"Event requires a type")
		return rt.undefined_value
	js_value* type = args[0]
	if (type.kind != 4):
		if (type.kind >= 5):
			js_runtime_fail(rt, 6, c"Event type object coercion is unsupported")
			return rt.undefined_value
		char* text = win_js_text(type)
		type = win_js_string(rt, text)
		free(text)
	if (type.text.units.length > 65536):
		js_runtime_fail(rt, 5, c"Event type length limit")
		return rt.undefined_value
	int bubbles = 0
	int cancelable = 0
	int composed = 0
	if (args.length > 1 && args[1].kind != 0 && args[1].kind != 1):
		if (js_runtime_object(args[1]) == 0):
			js_runtime_fail(rt, 2, c"Event options must be a dictionary")
			return rt.undefined_value
		bubbles = js_runtime_truth(js_runtime_get(rt, args[1], c"bubbles"))
		cancelable = js_runtime_truth(js_runtime_get(rt, args[1], c"cancelable"))
		composed = js_runtime_truth(js_runtime_get(rt, args[1], c"composed"))
	if (rt.completion.status != 0): return rt.undefined_value
	return win_event_new(rt, type, bubbles, cancelable, composed, cast(float64, time_monotonic_ms() - script.time_origin))

void win_script_abort_report(void* context, js_completion* completion):
	win_script_result(cast(win_script*, context), completion)

void win_script_web_install(win_script* script, js_value* window):
	js_runtime* rt = script.runtime
	script.aborts = win_abort_new(rt, window, script, win_script_abort_report)
	js_value* event_constructor = js_runtime_host_callable(rt, script, win_script_event_new)
	event_constructor.host_construct = 2
	js_runtime_set(rt, rt.global, c"Event", event_constructor)
	js_runtime_set(rt, window, c"Event", event_constructor)
	js_runtime_bind(rt, c"__winSearchGet", win_script_search_get)
	char* source = c"function __winSearchObject(query){return {get:function(name){return __winSearchGet(query,name);}};}"
	win_script_result(script, js_runtime_eval(rt, source, strlen(source), script.execution_budget))
	js_value* constructor = js_runtime_host_callable(rt, script, win_script_search_new)
	constructor.host_construct = 1
	js_runtime_set(rt, rt.global, c"URLSearchParams", constructor)
	js_runtime_set(rt, window, c"URLSearchParams", constructor)
	js_value* computed = js_runtime_host_callable(rt, script, win_script_get_computed)
	js_runtime_set(rt, rt.global, c"getComputedStyle", computed)
	js_runtime_set(rt, window, c"getComputedStyle", computed)
	js_value* location = js_runtime_alloc(rt, 5)
	js_runtime_set_host_hooks(rt, location, script, win_script_location_get, win_script_location_set)
	js_runtime_set_host_has(rt, location, win_script_location_has)
	js_runtime_set(rt, rt.global, c"location", location)
	js_runtime_set(rt, window, c"location", location)
	js_runtime_set(rt, js_runtime_get(rt, rt.global, c"document"), c"location", location)
	win_script_set_viewport(script, cast(int, script.viewport.width), cast(int, script.viewport.height), script.viewport.ratio, 0.0, 0.0)

win_script* win_script_new(win_page* page):
	win_script* script = new win_script()
	script.execution_budget = WIN_EXECUTION_DEFAULT
	script.timers = new list[win_script_timer*]
	script.animation_frames = new list[win_script_timer*]
	script.now_ms = time_monotonic_ms()
	script.time_origin = script.now_ms
	script.frame_time = script.now_ms
	script.origin = strclone(c"")
	script.address = strclone(c"about:blank")
	script.viewport.ratio = 1.0
	script.layout_width = page.width
	script.viewport.width = cast(float64, page.width)
	script.page = page
	script.runtime = js_runtime_new()
	script.runtime.max_properties = 65536
	script.runtime.max_depth = 128
	script.runtime.max_source_bytes = 262144
	script.runtime.max_scripts = 512
	script.bindings = new list[win_dom_binding*]
	script.listeners = new list[win_script_listener*]
	script.scripts = new list[html_node*]
	script.error = strclone(c"")
	script.console = new list[char*]
	js_runtime_bind(script.runtime, c"__winStorage", win_script_storage_host)
	js_runtime_bind(script.runtime, c"__winTimer", win_script_timer_host)
	js_runtime_bind(script.runtime, c"__winHost", win_script_host)
	js_runtime_bind(script.runtime, c"__winGL", win_script_gl_host)
	char* bootstrap = c"function __winStorageObject(k){return {__storeKind:k,getItem:function(n){return __winStorage(k,0,n);},setItem:function(n,v){return __winStorage(k,1,n,v);},removeItem:function(n){return __winStorage(k,2,n);},clear:function(){return __winStorage(k,3);},key:function(i){return __winStorage(k,4,i);}};} function setTimeout(f,d,a,b,c){return __winTimer(0,f,d,a,b,c);} function setInterval(f,d,a,b,c){return __winTimer(1,f,d,a,b,c);} function clearTimeout(id){__winTimer(2,id);} function clearInterval(id){__winTimer(2,id);} function __winNode(id) { return {getBoundingClientRect:function(){return __winHost(id,'rect');},getContext:function(k){return __winHost(id,'getContext',k);},style:{getPropertyValue:function(s){return __winHost(id,'styleGet',s);},getPropertyPriority:function(s){return __winHost(id,'stylePriority',s);},setProperty:function(s,v,p){return __winHost(id,'styleSet',s,v,p);},removeProperty:function(s){return __winHost(id,'styleRemove',s);}},classList:{add:function(s){return __winHost(id,'classAdd',s);},remove:function(s){return __winHost(id,'classRemove',s);},toggle:function(s,f){return __winHost(id,'classToggle',s,f);},contains:function(s){return __winHost(id,'classContains',s);}},getElementById:function(s){return __winHost(id,'id',s);},querySelector:function(s){return __winHost(id,'query',s);},querySelectorAll:function(s){return __winHost(id,'all',s);},matches:function(s){return __winHost(id,'matches',s);},closest:function(s){return __winHost(id,'closest',s);},getAttribute:function(s){return __winHost(id,'get',s);},setAttribute:function(s,v){return __winHost(id,'set',s,v);},removeAttribute:function(s){return __winHost(id,'removeAttr',s);},createElement:function(s){return __winHost(id,'create',s);},createTextNode:function(s){return __winHost(id,'text',s);},appendChild:function(n){return __winHost(id,'append',n);},remove:function(){return __winHost(id,'remove');},addEventListener:function(s,f,o){return __winHost(id,'listen',s,f,o);},removeEventListener:function(s,f,o){return __winHost(id,'unlisten',s,f,o);}}; } const console={log:function(v){__winHost(0,'console',v);},warn:function(v){__winHost(0,'console',v);},error:function(v){__winHost(0,'console',v);}};"
	js_completion* completion = js_runtime_eval(script.runtime, bootstrap, strlen(bootstrap), script.execution_budget)
	win_script_result(script, completion)
	char* gl_source = win_canvas_bootstrap()
	win_script_result(script, js_runtime_eval(script.runtime, gl_source, strlen(gl_source), script.execution_budget))
	script.runtime.remaining = script.execution_budget
	js_value* document = win_script_wrap(script, page.html.root)
	js_runtime_set(script.runtime, script.runtime.global, c"document", document)
	js_runtime_set(script.runtime, document, c"document", document)
	script.window_node = win_dom_create(script, HTML_DOCUMENT, c"window")
	js_value* window = win_script_wrap(script, script.window_node)
	js_runtime_set(script.runtime, window, c"document", document)
	js_runtime_set(script.runtime, window, c"window", window)
	js_runtime_set(script.runtime, window, c"globalThis", window)
	js_runtime_set(script.runtime, script.runtime.global, c"window", window)
	js_runtime_set(script.runtime, script.runtime.global, c"globalThis", window)
	js_runtime_set(script.runtime, window, c"setTimeout", js_runtime_get(script.runtime, script.runtime.global, c"setTimeout"))
	js_runtime_set(script.runtime, window, c"setInterval", js_runtime_get(script.runtime, script.runtime.global, c"setInterval"))
	js_runtime_set(script.runtime, window, c"clearTimeout", js_runtime_get(script.runtime, script.runtime.global, c"clearTimeout"))
	js_runtime_set(script.runtime, window, c"clearInterval", js_runtime_get(script.runtime, script.runtime.global, c"clearInterval"))
	js_runtime_set(script.runtime, window, c"queueMicrotask", js_runtime_get(script.runtime, script.runtime.global, c"queueMicrotask"))
	js_runtime_set(script.runtime, window, c"Promise", js_runtime_get(script.runtime, script.runtime.global, c"Promise"))
	js_value* animation = js_runtime_host_callable(script.runtime, script, win_script_animation_host)
	js_value* cancel_animation = js_runtime_host_callable(script.runtime, script, win_script_animation_cancel)
	js_runtime_set(script.runtime, window, c"requestAnimationFrame", animation)
	js_runtime_set(script.runtime, script.runtime.global, c"requestAnimationFrame", animation)
	js_runtime_set(script.runtime, window, c"cancelAnimationFrame", cancel_animation)
	js_runtime_set(script.runtime, script.runtime.global, c"cancelAnimationFrame", cancel_animation)
	for k in range(2):
		list[js_value*] storage_args = new list[js_value*]
		storage_args.push(js_runtime_number(script.runtime, cast(float64, k)))
		js_value* storage = js_runtime_call(script.runtime, js_runtime_get(script.runtime, script.runtime.global, c"__winStorageObject"), storage_args)
		__w_list_free(cast(__w_list*, storage_args))
		js_runtime_set_host_hooks(script.runtime, storage, script, win_script_storage_get, 0)
		js_runtime_set_host_has(script.runtime, storage, win_script_storage_has)
		char* name = c"localStorage"
		if (k == 1): name = c"sessionStorage"
		js_runtime_set(script.runtime, script.runtime.global, name, storage)
		js_runtime_set(script.runtime, window, name, storage)
	list[html_node*] bodies = new list[html_node*]
	win_dom_query(script, page.html.root, c"body", 0, bodies)
	if (bodies.length > 0): js_runtime_set(script.runtime, document, c"body", win_script_wrap(script, bodies[0]))
	__w_list_free(cast(__w_list*, bodies))
	script.wasm = win_wasm_install(script.runtime)
	js_runtime_set(script.runtime, window, c"WebAssembly", js_runtime_get(script.runtime, script.runtime.global, c"WebAssembly"))
	win_script_web_install(script, window)
	win_script_collect_nodes(script, page.html.root)
	return script

# Listener exceptions are reported at the host boundary, not propagated into
# dispatchEvent's caller. Terminal limits remain terminal and share its budget.
void win_script_event_result(win_script* script):
	js_runtime* rt = script.runtime
	if (rt.completion.status != 5):
		win_script_result(script, rt.completion)
		rt.completion.status = 0
		rt.completion.value = rt.undefined_value
		rt.completion.message = c""

# Each invocation snapshots its listener list length. Registrations made during
# a callback can run at a later node/phase, but never in the current invocation.
void win_script_invoke_listeners(win_script* script, html_node* node, char* name, list[js_value*] args, int capture, int phase):
	js_runtime* rt = script.runtime
	js_value* event = script.event
	js_value* receiver = win_script_wrap(script, node)
	win_event_write(rt, event, c"currentTarget", receiver)
	win_event_write(rt, event, c"eventPhase", js_runtime_number(rt, cast(float64, phase)))
	if (rt.completion.status != 0): return
	int count = script.listeners.length
	for i in range(count):
		win_script_listener* listener = script.listeners[i]
		if (win_event_flag(event, WIN_EVENT_IMMEDIATE) || rt.remaining <= 0 || rt.completion.status == 5): break
		if (listener.node != node || listener.capture != capture || strcmp(listener.event, name) != 0): continue
		if (listener.once): listener.node = 0
		win_event_flag_set(event, WIN_EVENT_PASSIVE, listener.passive)
		js_value* callback = listener.callback
		if (listener.handler):
			string_builder* property = string_from(c"on")
			string_append(property, name)
			callback = js_runtime_get(rt, receiver, property.data)
			string_free(property)
		if (rt.completion.status == 0 && (callback.kind == 7 || callback.kind == 9)):
			js_value* result = js_runtime_call_receiver(rt, callback, receiver, args)
			if (listener.handler && rt.completion.status == 0 && result.kind == 2):
				int cancel = result.number == 0.0
				if (node == script.window_node && strcmp(name, c"error") == 0): cancel = result.number != 0.0
				if (cancel): win_event_prevent(rt, event)
		win_script_sync(script)
		win_script_event_result(script)
		win_event_flag_set(event, WIN_EVENT_PASSIVE, 0)
	for i in range(WIN_EVENT_HANDLER_COUNT):
		if (strcmp(name, win_event_handler_property(i) + 2) == 0): return
	if (capture || win_event_flag(event, WIN_EVENT_IMMEDIATE) || rt.remaining <= 0 || rt.completion.status == 5): return
	string_builder* property_text = string_from(c"on")
	string_append(property_text, name)
	js_value* callback = js_runtime_get(rt, receiver, property_text.data)
	char* handler = win_attr(node, property_text.data)
	if (rt.completion.status == 0 && callback.kind == 0 && handler[0] != 0):
		string_builder* source = string_from(c"(function(event){")
		string_append(source, handler)
		string_append(source, c"});")
		js_value* compiled = js_runtime_compile_function(rt, source.data, source.length)
		if (rt.completion.status == 0):
			callback = compiled
			js_runtime_set(rt, receiver, property_text.data, callback)
		win_script_event_result(script)
		string_free(source)
	string_free(property_text)
	if (rt.completion.status != 0):
		win_script_event_result(script)
		return
	if (callback.kind == 7 || callback.kind == 9):
		js_value* result = js_runtime_call_receiver(rt, callback, receiver, args)
		if (rt.completion.status == 0 && result.kind == 2 && result.number == 0.0): win_event_prevent(rt, event)
		win_script_sync(script)
		win_script_event_result(script)

# One algorithm for trusted browser events and dispatchEvent. It runs inside
# the active execution scope: no collection, fresh budget or microtask checkpoint.
int win_script_dispatch_event(win_script* script, html_node* node, js_value* event):
	js_runtime* rt = script.runtime
	if (win_event_flag(event, WIN_EVENT_DISPATCHING)):
		js_value* error = js_runtime_alloc(rt, 5)
		js_runtime_set(rt, error, c"name", win_js_string(rt, c"InvalidStateError"))
		js_runtime_set(rt, error, c"message", win_js_string(rt, c"Event is already being dispatched"))
		js_runtime_throw(rt, error)
		return 0
	js_value* type = js_runtime_get(rt, event, c"type")
	int length = 0
	char* name = js_text_to_utf8(type.text, &length)
	if (name == 0 || strlen(name) != length):
		free(name)
		js_runtime_fail(rt, 6, c"Event type must be representable by the host listener table")
		return 0
	js_value* completed_target = js_runtime_get(rt, event, c"currentTarget")
	js_value* completed_phase = js_runtime_get(rt, event, c"eventPhase")
	js_value* previous_event = script.event
	script.event = event
	win_event_flag_set(event, WIN_EVENT_DISPATCHING, 1)
	win_event_write(rt, event, c"target", win_script_wrap(script, node))
	int bubbles = js_runtime_truth(js_runtime_get(rt, event, c"bubbles"))
	list[js_value*] args = new list[js_value*]
	args.push(event)
	# Snapshot ancestry before callbacks mutate or detach nodes.
	list[html_node*] path = new list[html_node*]
	html_node* current = node
	while (current != 0 && rt.remaining > 0):
		rt.remaining = rt.remaining - 1
		path.push(current)
		current = current.parent
	if (path.length > 0 && path[path.length - 1] == script.page.html.root && strcmp(name, c"load") != 0): path.push(script.window_node)
	int index = path.length - 1
	while (index >= 0 && win_event_flag(event, WIN_EVENT_STOP) == 0 && rt.remaining > 0 && rt.completion.status == 0):
		int phase = 1
		if (index == 0): phase = 2
		win_script_invoke_listeners(script, path[index], name, args, 1, phase)
		index = index - 1
	index = 0
	while (index < path.length && win_event_flag(event, WIN_EVENT_STOP) == 0 && rt.remaining > 0 && rt.completion.status == 0):
		if (index > 0 && bubbles == 0): break
		int phase = 3
		if (index == 0): phase = 2
		win_script_invoke_listeners(script, path[index], name, args, 0, phase)
		index = index + 1
	# Reuse completed-state values so heap-limit cleanup does not allocate.
	win_event_write(rt, event, c"currentTarget", completed_target)
	win_event_write(rt, event, c"eventPhase", completed_phase)
	win_event_flag_set(event, WIN_EVENT_DISPATCHING | WIN_EVENT_STOP | WIN_EVENT_IMMEDIATE | WIN_EVENT_PASSIVE, 0)
	script.event = previous_event
	# Outer snapshots use stable list indices; compact only at the outer boundary.
	if (previous_event == 0): win_script_collect_listeners(script)
	__w_list_free(cast(__w_list*, path))
	__w_list_free(cast(__w_list*, args))
	free(name)
	if (rt.remaining <= 0 && rt.completion.status == 0): js_runtime_fail(rt, 5, c"Event dispatch execution limit")
	return js_runtime_truth(js_runtime_get(rt, event, c"defaultPrevented")) == 0

js_value* win_script_dispatch_host(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_dom_binding* binding = cast(win_dom_binding*, context)
	win_script* script = cast(win_script*, binding.context)
	if (receiver != binding.object || args.length == 0 || win_event_is(args[0]) == 0):
		js_runtime_fail(rt, 2, c"dispatchEvent requires an Event and its EventTarget receiver")
		return rt.undefined_value
	if (win_event_flag(args[0], WIN_EVENT_DISPATCHING) == 0): win_event_write(rt, args[0], c"isTrusted", js_runtime_boolean(rt, 0))
	int allowed = win_script_dispatch_event(script, binding.node, args[0])
	return js_runtime_boolean(rt, allowed)

html_node* win_script_active_element(win_script* script):
	if (script.active_focus != 0 && win_pointer_connected(script.page, script.active_focus) == 0):
		script.active_focus = 0
		script.focus_revision = script.focus_revision + 1
		script.focus_serial = script.focus_serial + 1
	if (script.active_focus != 0): return script.active_focus
	return win_focus_fallback(script.page)

void win_script_focus_event(win_script* script, html_node* node, html_node* related, char* name, int bubbles):
	js_runtime* rt = script.runtime
	if (rt.completion.status != 0): return
	js_value* event = win_event_new(rt, win_web_string(rt, name), bubbles, 0, 1, cast(float64, time_monotonic_ms() - script.time_origin))
	js_runtime_root(rt, event)
	win_event_write(rt, event, c"isTrusted", js_runtime_boolean(rt, 1))
	win_event_write(rt, event, c"relatedTarget", win_script_wrap(script, related))
	if (rt.completion.status == 0): win_script_dispatch_event(script, node, event)
	js_runtime_unroot(rt, event)

void win_script_focus_inner(win_script* script, html_node* node, int prevent_scroll):
	js_runtime* rt = script.runtime
	if (rt.completion.status != 0): return
	win_script_sync(script)
	if (node != 0 && win_focus_eligible(script.page, node) == 0): return
	win_script_active_element(script)
	if (script.active_focus == node): return
	if (script.focus_depth >= 32 || rt.remaining < script.page.html.node_count):
		js_runtime_fail(rt, 5, c"Focus transition budget")
		return
	rt.remaining = rt.remaining - script.page.html.node_count
	html_node* previous = script.active_focus
	script.focus_serial = script.focus_serial + 1
	int serial = script.focus_serial
	script.active_focus = 0
	script.focus_revision = script.focus_revision + 1
	if (previous != 0):
		win_script_focus_event(script, previous, node, c"blur", 0)
		if (serial != script.focus_serial || rt.completion.status != 0): return
		win_script_focus_event(script, previous, node, c"focusout", 1)
		if (serial != script.focus_serial || rt.completion.status != 0): return
	if (node != 0 && win_focus_eligible(script.page, node)):
		script.active_focus = node
		script.focus_revision = script.focus_revision + 1
		script.focus_scroll = prevent_scroll == 0
		win_script_focus_event(script, node, previous, c"focus", 0)
		if (serial != script.focus_serial || rt.completion.status != 0): return
		win_script_focus_event(script, node, previous, c"focusin", 1)

# JS focus shares its caller's task. Native widget changes enter one bounded
# task, keeping reentrant focus events and their microtasks in the same scope.
void win_script_focus_input(win_script* script, html_node* node, int prevent_scroll):
	if (script == 0): return
	js_runtime* rt = script.runtime
	int nested = rt.running
	win_script* previous = win_active_script
	win_active_script = script
	if (nested == 0):
		js_runtime_collect(rt)
		if (js_runtime_begin(rt, script.execution_budget) == 0):
			win_active_script = previous
			return
	rt.running = 1
	script.focus_depth = script.focus_depth + 1
	win_script_focus_inner(script, node, prevent_scroll)
	script.focus_depth = script.focus_depth - 1
	rt.running = nested
	if (nested == 0):
		win_script_result(script, rt.completion)
		if (rt.completion.status != 5): win_script_checkpoint(script)
	win_active_script = previous

js_value* win_dom_focus(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_dom_binding* b = cast(win_dom_binding*, context)
	if (receiver != b.object):
		js_runtime_fail(rt, 2, c"focus requires its Element receiver")
		return rt.undefined_value
	int prevent_scroll = 0
	if (args.length > 0 && args[0].kind != 0 && args[0].kind != 1):
		if (js_runtime_object(args[0]) == 0):
			js_runtime_fail(rt, 2, c"focus options require a dictionary")
			return rt.undefined_value
		prevent_scroll = js_runtime_truth(js_runtime_get(rt, args[0], c"preventScroll"))
	if (rt.completion.status == 0): win_script_focus_input(cast(win_script*, b.context), b.node, prevent_scroll)
	return rt.undefined_value

js_value* win_dom_blur(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_dom_binding* b = cast(win_dom_binding*, context)
	if (receiver != b.object):
		js_runtime_fail(rt, 2, c"blur requires its Element receiver")
		return rt.undefined_value
	win_script* script = cast(win_script*, b.context)
	if (script.active_focus == b.node): win_script_focus_input(script, 0, 1)
	return rt.undefined_value

# Capture ownership is pending until the next pointer event; hasPointerCapture
# observes that pending override immediately, as required by Pointer Events.
js_value* win_dom_pointer_capture(js_runtime* rt, win_dom_binding* binding, js_value* receiver, list[js_value*] args, int operation):
	win_script* script = cast(win_script*, binding.context)
	if (receiver != binding.object || args.length == 0 || args[0].kind != 3):
		js_runtime_fail(rt, 2, c"Pointer capture requires an Element and pointer ID")
		return rt.undefined_value
	int id = js_binary_uint(args[0].number, 32)
	if (operation == 2): return js_runtime_boolean(rt, id == 1 && script.pointer.pending == binding.node)
	if (id != 1 || script.pointer.present == 0):
		win_pointer_error(rt, c"NotFoundError", c"Pointer is not active")
		return rt.undefined_value
	if (operation == 1):
		if (script.pointer.pending == binding.node): script.pointer.pending = 0
	else:
		if (win_pointer_connected(script.page, binding.node) == 0):
			win_pointer_error(rt, c"InvalidStateError", c"Capture target is disconnected")
			return rt.undefined_value
		if (script.pointer.buttons != 0): script.pointer.pending = binding.node
	return rt.undefined_value

js_value* win_dom_pointer_set(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	return win_dom_pointer_capture(cast(js_runtime*, runtime), cast(win_dom_binding*, context), receiver, args, 0)

js_value* win_dom_pointer_release(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	return win_dom_pointer_capture(cast(js_runtime*, runtime), cast(win_dom_binding*, context), receiver, args, 1)

js_value* win_dom_pointer_has(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	return win_dom_pointer_capture(cast(js_runtime*, runtime), cast(win_dom_binding*, context), receiver, args, 2)

int win_script_pointer_dispatch(win_script* script, html_node* node, char* name, int button, int delta, int delta_mode):
	if (script == 0 || node == 0): return 1
	if (script.runtime.running && script.runtime.completion.status != 0): return 0
	js_runtime* rt = script.runtime
	int nested = rt.running
	win_script* previous = win_active_script
	win_active_script = script
	if (nested == 0):
		js_runtime_collect(rt)
		if (js_runtime_begin(rt, script.execution_budget) == 0):
			win_active_script = previous
			return 0
	rt.running = 1
	js_value* event = win_pointer_event(rt, &script.pointer, name, button, &script.viewport, cast(float64, time_monotonic_ms() - script.time_origin), delta, delta_mode)
	js_runtime_root(rt, event)
	int allowed = 0
	if (rt.completion.status == 0): allowed = win_script_dispatch_event(script, node, event)
	js_runtime_unroot(rt, event)
	rt.running = nested
	if (nested == 0):
		win_script_result(script, rt.completion)
		if (rt.completion.status != 5): win_script_checkpoint(script)
	win_active_script = previous
	return allowed

void win_script_pointer_capture_update(win_script* script):
	win_pointer_state* state = &script.pointer
	if (state.pending != 0 && win_pointer_connected(script.page, state.pending) == 0): state.pending = 0
	html_node* pending = state.pending
	html_node* previous = state.capture
	if (pending == previous): return
	state.capture = pending
	if (previous != 0):
		if (win_pointer_connected(script.page, previous) == 0): previous = script.page.html.root
		win_script_pointer_dispatch(script, previous, c"lostpointercapture", 0 - 1, 0, 0)
	if (pending != 0 && win_pointer_connected(script.page, pending)):
		win_script_pointer_dispatch(script, pending, c"gotpointercapture", 0 - 1, 0, 0)

void win_script_pointer_cancel_inner(win_script* script):
	if (script == 0): return
	win_pointer_state* state = &script.pointer
	html_node* target = state.capture
	if (target == 0): target = state.pressed
	int buttons = state.buttons
	state.buttons = 0
	state.cancelled = 1
	state.pressed = 0
	if (buttons && target != 0): win_script_pointer_dispatch(script, target, c"pointercancel", 0 - 1, 0, 0)
	state.pending = 0
	win_script_pointer_capture_update(script)
	state.capture = 0
	state.present = 0

# One native pointer sample owns capture transitions, dispatch and checkpoint.
# kind zero is the backend's latest motion snapshot; queued edges retain order.
int win_script_pointer_input(win_script* script, html_node* hit, int kind, int code, int x, int y, int mods):
	if (script == 0): return 1
	js_runtime* rt = script.runtime
	int nested = rt.running
	win_script* previous = win_active_script
	win_active_script = script
	if (nested == 0):
		js_runtime_collect(rt)
		if (js_runtime_begin(rt, script.execution_budget) == 0):
			win_active_script = previous
			return 0
	rt.running = 1
	win_pointer_state* state = &script.pointer
	state.x = x
	state.y = y
	state.mods = mods
	int allowed = 1
	if (kind == GFX_EVENT_POINTER_CANCEL): win_script_pointer_cancel_inner(script)
	else:
		state.present = 1
		if (kind == GFX_EVENT_SCROLL || kind == GFX_EVENT_SCROLL_PIXELS):
			int delta = code
			int mode = 0
			if (kind == GFX_EVENT_SCROLL):
				delta = 0 - code
				mode = 1
			allowed = win_script_pointer_dispatch(script, hit, c"wheel", 0, delta, mode)
		else:
			int button = code - 1
			int mask = win_pointer_button_mask(button)
			int before = state.buttons
			char* name = c"pointermove"
			if (kind == GFX_EVENT_MOUSE_DOWN && mask):
				state.cancelled = 0
				state.buttons = state.buttons | mask
				if (before == 0):
					state.pressed = hit
					name = c"pointerdown"
			else if (kind == GFX_EVENT_MOUSE_UP && mask):
				state.buttons = state.buttons & ~mask
				if (state.buttons == 0): name = c"pointerup"
				if ((before & mask) == 0): name = 0
			else: button = 0 - 1
			win_script_pointer_capture_update(script)
			html_node* target = state.capture
			if (target == 0): target = hit
			if (rt.completion.status == 0 && name != 0): allowed = win_script_pointer_dispatch(script, target, name, button, 0, 0)
			if (kind == GFX_EVENT_MOUSE_UP && state.buttons == 0):
				state.pressed = 0
				state.pending = 0
				win_script_pointer_capture_update(script)
	rt.running = nested
	if (nested == 0):
		win_script_result(script, rt.completion)
		if (rt.completion.status != 5): win_script_checkpoint(script)
	win_active_script = previous
	return allowed

void win_script_pointer_cancel(win_script* script):
	if (script == 0): return
	if (script.pointer.buttons == 0 && script.pointer.capture == 0 && script.pointer.pending == 0):
		script.pointer.present = 0
		script.pointer.cancelled = 1
		return
	win_script_pointer_input(script, 0, GFX_EVENT_POINTER_CANCEL, 0, script.pointer.x, script.pointer.y, script.pointer.mods)

# Native entry owns the task boundary. JS dispatchEvent shares its enclosing task.
int win_script_dispatch(win_script* script, html_node* node, char* name):
	if (script == 0 || node == 0): return 1
	js_runtime* rt = script.runtime
	win_script* previous = win_active_script
	win_active_script = script
	js_runtime_collect(rt)
	if (js_runtime_begin(rt, script.execution_budget) == 0):
		win_active_script = previous
		return 1
	rt.running = 1
	int cancelable = strcmp(name, c"click") == 0 || strcmp(name, c"submit") == 0 || strcmp(name, c"reset") == 0
	js_value* event = win_event_new(rt, win_js_string(rt, name), strcmp(name, c"load") != 0, cancelable, 0, cast(float64, time_monotonic_ms() - script.time_origin))
	js_runtime_root(rt, event)
	win_event_write(rt, event, c"isTrusted", js_runtime_boolean(rt, 1))
	int allowed = 1
	if (rt.completion.status == 0): allowed = win_script_dispatch_event(script, node, event)
	rt.running = 0
	js_runtime_unroot(rt, event)
	win_script_result(script, rt.completion)
	if (rt.completion.status != 5): win_script_checkpoint(script)
	win_active_script = previous
	return allowed

void win_script_dom_ready(win_script* script):
	if (script.dom_ready): return
	script.dom_ready = 1
	win_script_dispatch(script, script.page.html.root, c"DOMContentLoaded")

void win_script_ready(win_script* script):
	if (script.ready): return
	win_script_dom_ready(script)
	script.ready = 1
	win_script_dispatch(script, script.window_node, c"load")

int win_script_run_pending(win_script* script, win_resources* resources):
	if (script == 0 || script.stopped_loading): return 0
	win_script_collect_nodes(script, script.page.html.root)
	if (resources != 0 && resources.page != 0): win_resources_refresh(resources)
	int before = script.next_script
	# At most one script per poll keeps rendering/input responsive between jobs.
	if (script.next_script < script.scripts.length):
		html_node* node = script.scripts[script.next_script]
		html_node* connected = node
		while (connected.parent != 0): connected = connected.parent
		if (connected != script.page.html.root):
			script.next_script = script.next_script + 1
			return 1
		char* type = win_attr(node, c"type")
		if (strcmp(type, c"module") == 0):
			if (script.modules == 0):
				script.failures = script.failures + 1
				free(script.error)
				script.error = strclone(c"Module loader is unavailable")
			else:
				if (script.active_module == 0 && script.modules.error == 0):
					char* src = win_attr(node, c"src")
					if (src[0] != 0):
						char* resolved = win_resolve(script.modules.address, src)
						if (resolved != 0): script.active_module = win_modules_request(script.modules, resolved, script.modules.address)
						else: win_modules_fail(script.modules, c"Invalid module script URL")
						free(resolved)
					else:
						string_builder* source = string_new()
						html_node* child = node.first_child
						while (child != 0 && source.length <= 262144):
							if (child.kind == HTML_TEXT): string_append_bytes(source, child.text, child.text_length)
							child = child.next_sibling
						string_builder* identifier = string_new()
						string_append(identifier, script.modules.address)
						string_append(identifier, c"#win-inline-")
						string_append_int(identifier, script.next_script)
						script.active_module = win_modules_add_inline(script.modules, identifier.data, script.modules.address, source.data, source.length)
						string_free(identifier)
						string_free(source)
				if (win_modules_poll(script.modules) == 0): return 0
				if (script.modules.error != 0):
					script.failures = script.failures + 1
					free(script.error)
					script.error = strclone(script.modules.error)
				else if (script.active_module != 0):
					win_script* previous = win_active_script
					win_active_script = script
					if (script.evaluating_module == 0):
						script.evaluating_module = win_modules_evaluate_async(script.modules, script.active_module.source.identifier, script.execution_budget)
						if (script.evaluating_module == 0): win_script_result(script, script.runtime.completion)
					win_script_sync(script)
					win_script_checkpoint(script)
					win_active_script = previous
					js_module* evaluated = script.evaluating_module
					# Keep the script pending while timers, Fetch and Promise jobs
					# continue through the ordinary browser event loop.
					if (evaluated != 0 && evaluated.state == 2): return 0
					if (evaluated != 0 && evaluated.state == 4):
						script.failures = script.failures + 1
						free(script.error)
						script.error = strclone(evaluated.error_message)
					script.evaluating_module = 0
				script.active_module = 0
			script.next_script = script.next_script + 1
			return 1
		if (type[0] != 0 && strcmp(type, c"text/javascript") != 0 && strcmp(type, c"application/javascript") != 0):
			script.next_script = script.next_script + 1
			return 1
		if (win_attr(node, c"src")[0] != 0):
			win_resource* resource = win_resources_script(resources, node)
			if (resource != 0 && resource.finished == 0): return 0
			if (resource != 0 && resource.error == 0 && resource.source != 0): win_script_eval(script, resource.source, resource.length)
			else:
				script.failures = script.failures + 1
				free(script.error)
				script.error = strclone(c"External script failed to load")
		else:
			string_builder* source = string_new()
			html_node* child = node.first_child
			while (child != 0 && source.length <= 262144):
				if (child.kind == HTML_TEXT): string_append_bytes(source, child.text, child.text_length)
				child = child.next_sibling
			win_script_eval(script, source.data, source.length)
			string_free(source)
		script.next_script = script.next_script + 1
	if (script.next_script == script.scripts.length):
		win_script_dom_ready(script)
		if (resources == 0 || win_resources_done(resources)): win_script_ready(script)
	return script.next_script != before || script.dirty

void win_script_free(win_script* script):
	if (script == 0): return
	# Suspended frames must unwind while every host record is still alive.
	js_runtime_async_cancel(script.runtime)
	for i in range(script.timers.length): win_script_timer_free(script, script.timers[i])
	__w_list_free(cast(__w_list*, script.timers))
	for i in range(script.animation_frames.length): win_script_timer_free(script, script.animation_frames[i])
	__w_list_free(cast(__w_list*, script.animation_frames))
	free(script.origin)
	free(script.address)
	for i in range(script.bindings.length):
		win_canvas_free(script.bindings[i].canvas)
		free(script.bindings[i])
	for i in range(script.listeners.length):
		free(script.listeners[i].event)
		free(script.listeners[i])
	__w_list_free(cast(__w_list*, script.bindings))
	__w_list_free(cast(__w_list*, script.listeners))
	__w_list_free(cast(__w_list*, script.scripts))
	for i in range(script.console.length): free(script.console[i])
	__w_list_free(cast(__w_list*, script.console))
	win_modules_free(script.modules)
	win_wasm_free(script.wasm)
	win_abort_free(script.aborts)
	js_runtime_free(script.runtime)
	free(script.error)
	free(script)
