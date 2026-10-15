# Per-page bounded JavaScript realm with synchronous host properties and stable
# DOM wrapper identity. Native mutation owns data until document teardown.
import win.document
import win.resources
import win.cssom
import libs.extras.javascript.runtime

struct win_dom_binding:
	html_node* node
	js_value* object
	void* context
	js_value* style

struct win_script_listener:
	html_node* node
	char* event
	js_value* callback
	int capture
	int once
	int passive

struct win_script:
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
	int prevented
	int stopped
	int immediate
	int passive
	int cancelable
	int failures
	char* error
	js_value* event
	int dom_bytes
	list[char*] console

# Installed only during synchronous bounded host entry, restored afterward.
win_script* win_active_script

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
	return c"border"

char* win_style_attribute(int index):
	if (index == 2): return c"background-color"
	if (index == 4): return c"font-size"
	if (index == 5): return c"font-weight"
	return win_style_property(index)

# All listed properties operate on native state at the property access itself.
# Unknown properties fall back to the runtime's ordinary object semantics.
js_value* win_dom_get(void* runtime, void* context, js_value* receiver, js_text* key):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_dom_binding* b = cast(win_dom_binding*, context)
	win_script* script = cast(win_script*, b.context)
	if (receiver != b.object): return 0
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

int win_style_set(void* runtime, void* context, js_value* receiver, js_text* key, js_value* value);

int win_dom_set(void* runtime, void* context, js_value* receiver, js_text* key, js_value* value):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_dom_binding* b = cast(win_dom_binding*, context)
	win_script* script = cast(win_script*, b.context)
	if (receiver != b.object): return 0
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
	for k in range(11):
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
	for k in range(11):
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
	js_runtime_set_host_hooks(rt, b.object, b, win_dom_get, win_dom_set)
	js_runtime_set_host_hooks(rt, b.style, b, win_style_get, win_style_set)
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
	else if (strcmp(operation, c"get") == 0):
		if (html_attribute_find(node.attributes, text) == 0): result = js_runtime_alloc(rt, 1)
		else: result = win_js_string(rt, win_attr(node, text))
	else if (strcmp(operation, c"set") == 0 && args.length > 3):
		char* value = win_js_text(args[3])
		if (strlen(text) <= 256 && strlen(value) <= 65536 && script.dom_bytes <= 4194304 - strlen(text) - strlen(value)):
			script.dom_bytes = script.dom_bytes + strlen(text) + strlen(value)
			win_dom_set_attr(node, text, value)
			script.dirty = 1
			if (win_tag(node, c"link") || win_tag(node, c"style")): script.styles_dirty = 1
		free(value)
	else if (strcmp(operation, c"removeAttr") == 0):
		win_dom_remove_attr(node, text)
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
	else if (strcmp(operation, c"prevent") == 0):
		if (args.length > 2 && args[2] == script.event && script.cancelable && script.passive == 0):
			script.prevented = 1
			js_runtime_set(rt, script.event, c"defaultPrevented", js_runtime_boolean(rt, 1))
	else if (strcmp(operation, c"stop") == 0 || strcmp(operation, c"stopImmediate") == 0):
		if (args.length > 2 && args[2] == script.event):
			script.stopped = 1
			if (strcmp(operation, c"stopImmediate") == 0): script.immediate = 1
	free(operation)
	free(text)
	return result

void win_script_result(win_script* script, js_completion* completion):
	if (completion == 0 || completion.status == 0): return
	script.failures = script.failures + 1
	free(script.error)
	script.error = strclone(completion.message)

int win_script_eval(win_script* script, char* source, int length):
	if (script == 0): return 0
	win_script* previous = win_active_script
	win_active_script = script
	js_runtime_collect(script.runtime)
	js_completion* result = js_runtime_eval(script.runtime, source, length, 100000)
	win_script_sync(script)
	win_script_result(script, result)
	win_script_collect_listeners(script)
	win_active_script = previous
	return result != 0 && result.status == 0

void win_script_collect_nodes(win_script* script, html_node* node):
	if (node == 0 || win_tag(node, c"template")): return
	if (win_tag(node, c"script")): script.scripts.push(node)
	html_node* child = node.first_child
	while (child != 0):
		win_script_collect_nodes(script, child)
		child = child.next_sibling

win_script* win_script_new(win_page* page):
	win_script* script = new win_script()
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
	js_runtime_bind(script.runtime, c"__winHost", win_script_host)
	char* bootstrap = c"function __winNode(id) { return {style:{getPropertyValue:function(s){return __winHost(id,'styleGet',s);},getPropertyPriority:function(s){return __winHost(id,'stylePriority',s);},setProperty:function(s,v,p){return __winHost(id,'styleSet',s,v,p);},removeProperty:function(s){return __winHost(id,'styleRemove',s);}},classList:{add:function(s){return __winHost(id,'classAdd',s);},remove:function(s){return __winHost(id,'classRemove',s);},toggle:function(s,f){return __winHost(id,'classToggle',s,f);},contains:function(s){return __winHost(id,'classContains',s);}},getElementById:function(s){return __winHost(id,'id',s);},querySelector:function(s){return __winHost(id,'query',s);},querySelectorAll:function(s){return __winHost(id,'all',s);},matches:function(s){return __winHost(id,'matches',s);},closest:function(s){return __winHost(id,'closest',s);},getAttribute:function(s){return __winHost(id,'get',s);},setAttribute:function(s,v){return __winHost(id,'set',s,v);},removeAttribute:function(s){return __winHost(id,'removeAttr',s);},createElement:function(s){return __winHost(id,'create',s);},createTextNode:function(s){return __winHost(id,'text',s);},appendChild:function(n){return __winHost(id,'append',n);},remove:function(){return __winHost(id,'remove');},addEventListener:function(s,f,o){return __winHost(id,'listen',s,f,o);},removeEventListener:function(s,f,o){return __winHost(id,'unlisten',s,f,o);}}; } function __winEvent(){const e={preventDefault:function(){__winHost(0,'prevent',e);},stopPropagation:function(){__winHost(0,'stop',e);},stopImmediatePropagation:function(){__winHost(0,'stopImmediate',e);}}; return e;} const console={log:function(v){__winHost(0,'console',v);},warn:function(v){__winHost(0,'console',v);},error:function(v){__winHost(0,'console',v);}};"
	js_completion* completion = js_runtime_eval(script.runtime, bootstrap, strlen(bootstrap), 100000)
	win_script_result(script, completion)
	script.runtime.remaining = 100000
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
	list[html_node*] bodies = new list[html_node*]
	win_dom_query(script, page.html.root, c"body", 0, bodies)
	if (bodies.length > 0): js_runtime_set(script.runtime, document, c"body", win_script_wrap(script, bodies[0]))
	__w_list_free(cast(__w_list*, bodies))
	win_script_collect_nodes(script, page.html.root)
	return script

# Each invocation snapshots its listener list length. Registrations made during
# a callback can run at a later node/phase, but never in the current invocation.
int win_script_invoke_listeners(win_script* script, html_node* node, char* name, list[js_value*] args, int capture, int phase, int budget):
	js_runtime* rt = script.runtime
	js_runtime_begin(rt, budget)
	js_runtime_set(rt, script.event, c"currentTarget", win_script_wrap(script, node))
	js_runtime_set(rt, script.event, c"eventPhase", js_runtime_number(rt, cast(float64, phase)))
	budget = rt.remaining
	if (rt.completion.status != 0):
		win_script_result(script, rt.completion)
		return 0
	int count = script.listeners.length
	for i in range(count):
		win_script_listener* listener = script.listeners[i]
		if (script.immediate || budget <= 0): break
		if (listener.node != node || listener.capture != capture || strcmp(listener.event, name) != 0): continue
		if (listener.once): listener.node = 0
		script.passive = listener.passive
		js_completion* result = js_runtime_invoke_receiver(rt, listener.callback, win_script_wrap(script, node), args, budget)
		win_script_sync(script)
		budget = rt.remaining
		win_script_result(script, result)
		script.passive = 0
		if (result.status == 5): budget = 0
	if (capture || script.immediate || budget <= 0): return budget
	string_builder* property_text = string_from(c"on")
	string_append(property_text, name)
	js_runtime_begin(rt, budget)
	js_value* receiver = win_script_wrap(script, node)
	js_value* callback = js_runtime_get(rt, receiver, property_text.data)
	char* handler = win_attr(node, property_text.data)
	budget = rt.remaining
	if (callback.kind == 0 && handler[0] != 0):
		string_builder* source = string_from(c"(function(event){")
		string_append(source, handler)
		string_append(source, c"});")
		js_completion* compiled = js_runtime_eval(rt, source.data, source.length, budget)
		budget = rt.remaining
		win_script_result(script, compiled)
		if (compiled.status == 5): budget = 0
		if (compiled.status == 0):
			callback = compiled.value
			js_runtime_set(rt, receiver, property_text.data, callback)
		string_free(source)
	string_free(property_text)
	if ((callback.kind == 7 || callback.kind == 9) && budget > 0):
		js_completion* result = js_runtime_invoke_receiver(rt, callback, receiver, args, budget)
		if (script.cancelable && result.status == 0 && result.value.kind == 2 && result.value.number == 0.0): script.prevented = 1
		win_script_sync(script)
		win_script_result(script, result)
		budget = rt.remaining
		if (result.status == 5): budget = 0
		js_runtime_set(rt, script.event, c"defaultPrevented", js_runtime_boolean(rt, script.prevented))
	return budget

# 1 permits the browser's default action; 0 means a cancelable event was canceled.
int win_script_dispatch(win_script* script, html_node* node, char* name):
	if (script == 0 || node == 0): return 1
	js_runtime* rt = script.runtime
	win_script* previous = win_active_script
	win_active_script = script
	js_runtime_collect(rt)
	js_runtime_begin(rt, 100000)
	script.prevented = 0
	script.stopped = 0
	script.immediate = 0
	script.passive = 0
	script.cancelable = strcmp(name, c"click") == 0 || strcmp(name, c"submit") == 0 || strcmp(name, c"reset") == 0
	int bubbles = strcmp(name, c"load") != 0
	list[js_value*] args = new list[js_value*]
	js_value* event = js_runtime_call(rt, js_runtime_get(rt, rt.global, c"__winEvent"), args)
	js_runtime_root(rt, event)
	script.event = event
	js_runtime_set(rt, event, c"type", win_js_string(rt, name))
	js_runtime_set(rt, event, c"target", win_script_wrap(script, node))
	js_runtime_set(rt, event, c"defaultPrevented", js_runtime_boolean(rt, 0))
	js_runtime_set(rt, event, c"bubbles", js_runtime_boolean(rt, bubbles))
	js_runtime_set(rt, event, c"cancelable", js_runtime_boolean(rt, script.cancelable))
	args.push(event)
	# Snapshot the ancestry before callbacks mutate or detach nodes.
	list[html_node*] path = new list[html_node*]
	html_node* current = node
	while (current != 0):
		path.push(current)
		current = current.parent
	if (path.length > 0 && path[path.length - 1] == script.page.html.root && strcmp(name, c"load") != 0): path.push(script.window_node)
	int budget = rt.remaining
	if (rt.completion.status != 0):
		win_script_result(script, rt.completion)
		budget = 0
	int index = path.length - 1
	while (index >= 0 && script.stopped == 0 && budget > 0):
		int phase = 1
		if (index == 0): phase = 2
		budget = win_script_invoke_listeners(script, path[index], name, args, 1, phase, budget)
		index = index - 1
	index = 0
	while (index < path.length && script.stopped == 0 && budget > 0):
		if (index > 0 && bubbles == 0): break
		int phase = 3
		if (index == 0): phase = 2
		budget = win_script_invoke_listeners(script, path[index], name, args, 0, phase, budget)
		index = index + 1
	# Retained events expose the completed state after dispatch.
	js_runtime_set(rt, event, c"currentTarget", js_runtime_alloc(rt, 1))
	js_runtime_set(rt, event, c"eventPhase", js_runtime_number(rt, 0.0))
	js_runtime_set(rt, event, c"defaultPrevented", js_runtime_boolean(rt, script.prevented))
	script.event = 0
	js_runtime_unroot(rt, event)
	win_script_collect_listeners(script)
	__w_list_free(cast(__w_list*, path))
	__w_list_free(cast(__w_list*, args))
	win_active_script = previous
	return script.prevented == 0

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
	if (script == 0 || script.ready): return 0
	int before = script.next_script
	# At most one script per poll keeps rendering/input responsive between jobs.
	if (script.next_script < script.scripts.length):
		html_node* node = script.scripts[script.next_script]
		char* type = win_attr(node, c"type")
		if (type[0] != 0 && strcmp(type, c"text/javascript") != 0 && strcmp(type, c"application/javascript") != 0):
			if (strcmp(type, c"module") == 0):
				script.failures = script.failures + 1
				free(script.error)
				script.error = strclone(c"JavaScript modules are not supported")
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
	for i in range(script.bindings.length):
		free(script.bindings[i])
	for i in range(script.listeners.length):
		free(script.listeners[i].event)
		free(script.listeners[i])
	__w_list_free(cast(__w_list*, script.bindings))
	__w_list_free(cast(__w_list*, script.listeners))
	__w_list_free(cast(__w_list*, script.scripts))
	for i in range(script.console.length): free(script.console[i])
	__w_list_free(cast(__w_list*, script.console))
	js_runtime_free(script.runtime)
	free(script.error)
	free(script)
