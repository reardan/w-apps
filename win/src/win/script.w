# Per-page bounded JavaScript realm and owned DOM bridge. Property mutations
# commit before host calls and at evaluation boundaries; wrappers keep identity.
import win.document
import win.resources
import libs.extras.javascript.runtime

struct win_dom_binding:
	html_node* node
	js_value* object
	list[js_value*] snapshots
	js_value* style
	list[js_value*] styles

struct win_script_listener:
	html_node* node
	char* event
	js_value* callback

struct win_script:
	win_page* page
	js_runtime* runtime
	list[win_dom_binding*] bindings
	list[win_script_listener*] listeners
	list[html_node*] scripts
	int next_script
	int ready
	int dirty
	int prevented
	int stopped
	int failures
	char* error
	js_value* title
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

void win_script_sync(win_script* script):
	js_runtime* rt = script.runtime
	for i in range(script.bindings.length):
		win_dom_binding* binding = script.bindings[i]
		for k in range(6):
			js_value* value = js_runtime_get(rt, binding.object, win_dom_property(k))
			if (value == binding.snapshots[k]): continue
			if (k >= 4):
				if (js_runtime_truth(value)): win_dom_set_attr(binding.node, win_dom_attribute(k), c"")
				else: win_dom_remove_attr(binding.node, win_dom_attribute(k))
			else:
				char* text = win_js_text(value)
				if (k == 0): win_dom_set_text(script, binding.node, text)
				else if (script.dom_bytes <= 4194304 - strlen(text)):
					script.dom_bytes = script.dom_bytes + strlen(text)
					win_dom_set_attr(binding.node, win_dom_attribute(k), text)
				else: js_runtime_fail(rt, 5, c"DOM mutation allocation limit")
				free(text)
			binding.snapshots[k] = value
			script.dirty = 1
		for k in range(11):
			js_value* value = js_runtime_get(rt, binding.style, win_style_property(k))
			if (value == binding.styles[k]): continue
			char* text = win_js_text(value)
			string_builder* css = string_new()
			if (k != 0):
				string_append(css, win_attr(binding.node, c"style"))
				string_append_char(css, ';')
				string_append(css, win_style_attribute(k))
				string_append_char(css, ':')
			string_append(css, text)
			if (css.length <= 65536 && script.dom_bytes <= 4194304 - css.length):
				win_dom_set_attr(binding.node, c"style", css.data)
				script.dom_bytes = script.dom_bytes + css.length
				script.dirty = 1
			else: js_runtime_fail(rt, 5, c"DOM style allocation limit")
			binding.styles[k] = value
			free(text)
			string_free(css)
	js_value* document = js_runtime_get(rt, rt.global, c"document")
	js_value* title = js_runtime_get(rt, document, c"title")
	if (title != script.title):
		free(script.page.title)
		script.page.title = win_js_text(title)
		script.title = title
		script.dirty = 1

void win_script_refresh_binding(win_script* script, win_dom_binding* b):
	js_runtime* rt = script.runtime
	for k in range(6):
		js_value* value = rt.undefined_value
		if (k >= 4): value = js_runtime_boolean(rt, html_attribute_find(b.node.attributes, win_dom_attribute(k)) != 0)
		else:
			char* text = 0
			if (k == 0): text = win_dom_text(b.node)
			else: text = strclone(win_attr(b.node, win_dom_attribute(k)))
			value = win_js_string(rt, text)
			free(text)
		js_runtime_set(rt, b.object, win_dom_property(k), value)
		b.snapshots[k] = value

void win_script_refresh(win_script* script):
	if (script == 0 || script.runtime.completion.status != 0): return
	for i in range(script.bindings.length): win_script_refresh_binding(script, script.bindings[i])

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
	b.snapshots = new list[js_value*]
	b.style = js_runtime_alloc(rt, 5)
	b.styles = new list[js_value*]
	js_runtime_set(rt, object, c"style", b.style)
	for k in range(11): b.styles.push(rt.undefined_value)
	for k in range(6): b.snapshots.push(rt.undefined_value)
	script.bindings.push(b)
	js_runtime_root(rt, object)
	win_script_refresh_binding(script, b)
	char* name = node.name
	if (name == 0): name = c"#document"
	js_runtime_set(rt, object, c"tagName", win_js_string(rt, name))
	return object

void win_dom_query(win_script* script, html_node* node, char* selector, int by_id, list[html_node*] found):
	if (node == 0 || found.length >= 1024): return
	if (script.runtime.remaining <= 0):
		js_runtime_fail(script.runtime, 5, c"DOM query budget")
		return
	script.runtime.remaining = script.runtime.remaining - 1
	int match = 0
	if (node.kind == HTML_START):
		if (by_id): match = strcmp(win_attr(node, c"id"), selector) == 0
		else: match = win_selector_matches(node, selector)
	if (match): found.push(node)
	html_node* child = node.first_child
	while (child != 0):
		win_dom_query(script, child, selector, by_id, found)
		child = child.next_sibling

int win_dom_height(html_node* node):
	if (node == 0): return 0
	int height = 1
	html_node* child = node.first_child
	while (child != 0):
		int next = 1 + win_dom_height(child)
		if (next > height): height = next
		child = child.next_sibling
	return height

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
	if (strcmp(operation, c"id") == 0 || strcmp(operation, c"query") == 0 || strcmp(operation, c"all") == 0):
		list[html_node*] found = new list[html_node*]
		html_node* child = node.first_child
		while (child != 0):
			win_dom_query(script, child, text, strcmp(operation, c"id") == 0, found)
			child = child.next_sibling
		if (strcmp(operation, c"all") == 0):
			result = js_runtime_alloc(rt, 6)
			for i in range(found.length):
				char* key = itoa(i)
				js_runtime_set(rt, result, key, win_script_wrap(script, found[i]))
				free(key)
			result.array_length = found.length
		else if (found.length > 0): result = win_script_wrap(script, found[0])
		else: result = js_runtime_alloc(rt, 1)
		__w_list_free(cast(__w_list*, found))
	else if (strcmp(operation, c"get") == 0):
		if (html_attribute_find(node.attributes, text) == 0): result = js_runtime_alloc(rt, 1)
		else: result = win_js_string(rt, win_attr(node, text))
	else if (strcmp(operation, c"set") == 0 && args.length > 3):
		char* value = win_js_text(args[3])
		if (strlen(text) <= 256 && strlen(value) <= 65536 && script.dom_bytes <= 4194304 - strlen(text) - strlen(value)):
			script.dom_bytes = script.dom_bytes + strlen(text) + strlen(value)
			win_dom_set_attr(node, text, value)
			script.dirty = 1
		free(value)
	else if (strcmp(operation, c"removeAttr") == 0):
		win_dom_remove_attr(node, text)
		script.dirty = 1
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
			result = args[2]
	else if (strcmp(operation, c"remove") == 0):
		if (node != script.page.html.root): win_dom_detach(node)
		script.dirty = 1
	else if (strcmp(operation, c"listen") == 0 && args.length > 3 && (args[3].kind == 7 || args[3].kind == 9)):
		int duplicate = 0
		for i in range(script.listeners.length):
			win_script_listener* listener = script.listeners[i]
			if (listener.node == node && strcmp(listener.event, text) == 0 && listener.callback == args[3]): duplicate = 1
		if (duplicate == 0 && script.listeners.length < 1024):
			win_script_listener* listener = new win_script_listener()
			listener.node = node
			listener.event = strclone(text)
			listener.callback = args[3]
			js_runtime_root(rt, listener.callback)
			script.listeners.push(listener)
	else if (strcmp(operation, c"unlisten") == 0 && args.length > 3):
		for i in range(script.listeners.length):
			win_script_listener* listener = script.listeners[i]
			if (listener.node == node && strcmp(listener.event, text) == 0 && listener.callback == args[3]): listener.node = 0
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
	else if (strcmp(operation, c"console") == 0):
		if (script.console.length == 32):
			free(script.console[0])
			for i in range(31): script.console[i] = script.console[i + 1]
			script.console.pop()
		int length = strlen(text)
		if (length > 4096): length = 4096
		script.console.push(substring(text, 0, length))
	else if (strcmp(operation, c"prevent") == 0):
		script.prevented = 1
		if (script.event != 0): js_runtime_set(rt, script.event, c"defaultPrevented", js_runtime_boolean(rt, 1))
	else if (strcmp(operation, c"stop") == 0): script.stopped = 1
	free(operation)
	free(text)
	win_script_refresh(script)
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
	char* bootstrap = c"function __winNode(id) { return {classList:{add:function(s){return __winHost(id,'classAdd',s);},remove:function(s){return __winHost(id,'classRemove',s);},toggle:function(s,f){return __winHost(id,'classToggle',s,f);},contains:function(s){return __winHost(id,'classContains',s);}},getElementById:function(s){return __winHost(id,'id',s);},querySelector:function(s){return __winHost(id,'query',s);},querySelectorAll:function(s){return __winHost(id,'all',s);},getAttribute:function(s){return __winHost(id,'get',s);},setAttribute:function(s,v){return __winHost(id,'set',s,v);},removeAttribute:function(s){return __winHost(id,'removeAttr',s);},createElement:function(s){return __winHost(id,'create',s);},createTextNode:function(s){return __winHost(id,'text',s);},appendChild:function(n){return __winHost(id,'append',n);},remove:function(){return __winHost(id,'remove');},addEventListener:function(s,f){return __winHost(id,'listen',s,f);},removeEventListener:function(s,f){return __winHost(id,'unlisten',s,f);}}; } function __winEvent(){return {preventDefault:function(){__winHost(0,'prevent');},stopPropagation:function(){__winHost(0,'stop');}};} const console={log:function(v){__winHost(0,'console',v);},warn:function(v){__winHost(0,'console',v);},error:function(v){__winHost(0,'console',v);}};"
	js_completion* completion = js_runtime_eval(script.runtime, bootstrap, strlen(bootstrap), 100000)
	win_script_result(script, completion)
	script.runtime.remaining = 100000
	js_value* document = win_script_wrap(script, page.html.root)
	js_runtime_set(script.runtime, script.runtime.global, c"document", document)
	js_runtime_set(script.runtime, document, c"document", document)
	js_runtime_set(script.runtime, script.runtime.global, c"window", document)
	js_runtime_set(script.runtime, script.runtime.global, c"globalThis", document)
	script.title = win_js_string(script.runtime, page.title)
	js_runtime_set(script.runtime, document, c"title", script.title)
	js_runtime_set(script.runtime, document, c"readyState", win_js_string(script.runtime, c"loading"))
	list[html_node*] bodies = new list[html_node*]
	win_dom_query(script, page.html.root, c"body", 0, bodies)
	if (bodies.length > 0): js_runtime_set(script.runtime, document, c"body", win_script_wrap(script, bodies[0]))
	__w_list_free(cast(__w_list*, bodies))
	win_script_collect_nodes(script, page.html.root)
	return script

# 1 permits the browser's default action; 0 means preventDefault/return false.
int win_script_dispatch(win_script* script, html_node* node, char* name):
	if (script == 0 || node == 0): return 1
	js_runtime* rt = script.runtime
	win_script* previous = win_active_script
	win_active_script = script
	js_runtime_collect(rt)
	js_runtime_begin(rt, 100000)
	win_script_refresh(script)
	script.prevented = 0
	script.stopped = 0
	list[js_value*] args = new list[js_value*]
	js_value* event = js_runtime_call(rt, js_runtime_get(rt, rt.global, c"__winEvent"), args)
	js_runtime_root(rt, event)
	script.event = event
	js_runtime_set(rt, event, c"type", win_js_string(rt, name))
	js_runtime_set(rt, event, c"target", win_script_wrap(script, node))
	js_runtime_set(rt, event, c"defaultPrevented", js_runtime_boolean(rt, 0))
	args.push(event)
	html_node* current = node
	int count = script.listeners.length
	int budget = rt.remaining
	while (current != 0 && script.stopped == 0 && budget > 0):
		js_runtime_begin(rt, budget)
		js_runtime_set(rt, event, c"currentTarget", win_script_wrap(script, current))
		budget = rt.remaining
		for i in range(count):
			win_script_listener* listener = script.listeners[i]
			if (listener.node != current || strcmp(listener.event, name) != 0): continue
			js_completion* result = js_runtime_invoke(rt, listener.callback, args, budget)
			budget = rt.remaining
			win_script_sync(script)
			win_script_result(script, result)
			js_runtime_set(rt, event, c"defaultPrevented", js_runtime_boolean(rt, script.prevented))
			if (budget <= 0): break
		string_builder* property_text = string_from(c"on")
		string_append(property_text, name)
		char* property = strclone(property_text.data)
		string_free(property_text)
		js_runtime_begin(rt, budget)
		js_value* receiver = win_script_wrap(script, current)
		js_value* callback = js_runtime_get(rt, receiver, property)
		char* handler = win_attr(current, property)
		if (callback.kind == 0 && handler[0] != 0):
			string_builder* source = string_from(c"(function(event){")
			string_append(source, handler)
			string_append(source, c"});")
			js_completion* compiled = js_runtime_eval(rt, source.data, source.length, budget)
			budget = rt.remaining
			win_script_result(script, compiled)
			if (compiled.status == 0):
				callback = compiled.value
				js_runtime_set(rt, receiver, property, callback)
			string_free(source)
		free(property)
		if ((callback.kind == 7 || callback.kind == 9) && budget > 0):
			js_completion* result = js_runtime_invoke(rt, callback, args, budget)
			budget = rt.remaining
			win_script_result(script, result)
			if (result.status == 0 && result.value.kind == 2 && result.value.number == 0.0): script.prevented = 1
			win_script_sync(script)
		if (strcmp(name, c"load") == 0): break
		current = current.parent
	script.event = 0
	js_runtime_unroot(rt, event)
	__w_list_free(cast(__w_list*, args))
	win_active_script = previous
	return script.prevented == 0

void win_script_ready(win_script* script):
	if (script.ready): return
	script.ready = 1
	js_runtime* rt = script.runtime
	js_value* document = js_runtime_get(rt, rt.global, c"document")
	js_runtime_set(rt, document, c"readyState", win_js_string(rt, c"interactive"))
	win_script_dispatch(script, script.page.html.root, c"DOMContentLoaded")
	js_runtime_set(rt, document, c"readyState", win_js_string(rt, c"complete"))
	win_script_dispatch(script, script.page.html.root, c"load")

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
	if (script.next_script == script.scripts.length && (resources == 0 || win_resources_done(resources))): win_script_ready(script)
	return script.next_script != before || script.dirty

void win_script_free(win_script* script):
	if (script == 0): return
	for i in range(script.bindings.length):
		__w_list_free(cast(__w_list*, script.bindings[i].styles))
		__w_list_free(cast(__w_list*, script.bindings[i].snapshots))
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
