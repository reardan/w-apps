# Bounded HTML Node tree operations. DOM Standard Node/pre-insert/pre-remove:
# https://dom.spec.whatwg.org/#interface-node
# https://dom.spec.whatwg.org/#concept-node-pre-insert
# Same-document HTML elements/text/fragments; no adoption or XML tree.
import win.script

int win_dom_tree_charge(js_runtime* rt, int cost):
	if (cost > rt.remaining):
		js_runtime_fail(rt, 5, c"DOM tree traversal budget")
		return 0
	rt.remaining = rt.remaining - cost
	return 1

void win_dom_tree_error(js_runtime* rt, char* name, char* message):
	js_value* error = js_runtime_alloc(rt, 5)
	js_runtime_set(rt, error, c"name", win_js_string(rt, name))
	js_runtime_set(rt, error, c"message", win_js_string(rt, message))
	js_runtime_throw(rt, error)

html_node* win_dom_tree_find(win_script* script, js_value* value):
	if (win_dom_tree_charge(script.runtime, script.bindings.length) == 0): return 0
	for i in range(script.bindings.length):
		if (script.bindings[i].object == value): return script.bindings[i].node
	return 0

html_node* win_dom_tree_child(win_script* script, html_node* parent, int index):
	html_node* child = parent.first_child
	while (child != 0):
		if (win_dom_tree_charge(script.runtime, 1) == 0): return 0
		if (index == 0): return child
		index = index - 1
		child = child.next_sibling
	return 0

int win_dom_tree_count(win_script* script, html_node* parent):
	int count = 0
	html_node* child = parent.first_child
	while (child != 0):
		if (win_dom_tree_charge(script.runtime, 1) == 0): return 0
		count = count + 1
		child = child.next_sibling
	return count

js_value* win_dom_children_get(void* runtime, void* context, js_value* receiver, js_text* key):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_dom_binding* b = cast(win_dom_binding*, context)
	win_script* script = cast(win_script*, b.context)
	if (receiver != b.child_nodes): return 0
	if (js_runtime_key_is(key, c"length")): return js_runtime_number(rt, cast(float64, win_dom_tree_count(script, b.node)))
	int index = js_runtime_array_index(key)
	if (index < 0): return 0
	html_node* child = win_dom_tree_child(script, b.node, index)
	if (child == 0): return rt.undefined_value
	return win_script_wrap(script, child)

int win_dom_children_has(void* runtime, void* context, js_value* receiver, js_text* key):
	win_dom_binding* b = cast(win_dom_binding*, context)
	if (receiver != b.child_nodes): return 0
	if (js_runtime_key_is(key, c"length")): return 1
	int index = js_runtime_array_index(key)
	if (index < 0): return 0
	return win_dom_tree_child(cast(win_script*, b.context), b.node, index) != 0

int win_dom_children_set(void* runtime, void* context, js_value* receiver, js_text* key, js_value* value):
	win_dom_binding* b = cast(win_dom_binding*, context)
	if (receiver != b.child_nodes): return 0
	return js_runtime_key_is(key, c"length") || js_runtime_array_index(key) >= 0

js_value* win_dom_children_item(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_dom_binding* b = cast(win_dom_binding*, context)
	if (receiver != b.child_nodes || args.length == 0):
		js_runtime_fail(rt, 2, c"NodeList.item requires its receiver and index")
		return rt.undefined_value
	if (args[0].kind != 3):
		js_runtime_fail(rt, 6, c"NodeList.item requires a numeric index")
		return rt.undefined_value
	int index = js_binary_uint(args[0].number, 32)
	return win_script_wrap(cast(win_script*, b.context), win_dom_tree_child(cast(win_script*, b.context), b.node, index))

html_node* win_dom_document_element(win_script* script):
	html_node* node = script.page.html.root.first_child
	while (node != 0):
		if (node.kind == HTML_START): return node
		node = node.next_sibling
	return 0

int win_dom_tree_key(win_dom_binding* b, js_text* key):
	win_script* script = cast(win_script*, b.context)
	if (b.node == script.window_node): return 0
	if (js_runtime_key_is(key, c"nodeType")): return 1
	if (js_runtime_key_is(key, c"nodeName")): return 2
	if (js_runtime_key_is(key, c"parentNode")): return 3
	if (js_runtime_key_is(key, c"firstChild")): return 4
	if (js_runtime_key_is(key, c"lastChild")): return 5
	if (js_runtime_key_is(key, c"nextSibling")): return 6
	if (js_runtime_key_is(key, c"ownerDocument")): return 7
	if (js_runtime_key_is(key, c"childNodes")): return 8
	if (js_runtime_key_is(key, c"nodeValue")): return 9
	if (b.node.kind == HTML_TEXT && js_runtime_key_is(key, c"data")): return 10
	if (b.node.kind == HTML_START):
		if (js_runtime_key_is(key, c"localName")): return 11
		if (js_runtime_key_is(key, c"namespaceURI")): return 12
		if (js_runtime_key_is(key, c"tagName")): return 2
	if (b.node == script.page.html.root):
		if (js_runtime_key_is(key, c"documentElement")): return 13
		if (js_runtime_key_is(key, c"head")): return 14
		if (js_runtime_key_is(key, c"body")): return 15
	return 0

js_value* win_dom_tree_get(win_dom_binding* b, js_text* key):
	win_script* script = cast(win_script*, b.context)
	js_runtime* rt = script.runtime
	int id = win_dom_tree_key(b, key)
	if (id == 0): return 0
	html_node* node = b.node
	if (id == 1):
		int kind = node.kind
		if (kind == HTML_DOCUMENT): kind = 9
		if (kind == HTML_COMMENT): kind = 8
		if (kind == HTML_DOCTYPE): kind = 10
		return js_runtime_number(rt, cast(float64, kind))
	if (id == 2):
		if (node.kind == HTML_TEXT): return win_js_string(rt, c"#text")
		if (node.kind == HTML_DOCUMENT): return win_js_string(rt, c"#document")
		if (node.kind == HTML_FRAGMENT): return win_js_string(rt, c"#document-fragment")
		if (node.kind == HTML_COMMENT): return win_js_string(rt, c"#comment")
		char* name = strclone(node.name)
		if (node.kind == HTML_START):
			for i in range(strlen(name)):
				if (name[i] >= 'a' && name[i] <= 'z'): name[i] = name[i] - 32
		js_value* result = win_js_string(rt, name)
		free(name)
		return result
	if (id == 3): return win_script_wrap(script, node.parent)
	if (id == 4): return win_script_wrap(script, node.first_child)
	if (id == 5): return win_script_wrap(script, node.last_child)
	if (id == 6): return win_script_wrap(script, node.next_sibling)
	if (id == 7):
		if (node == script.page.html.root): return js_runtime_alloc(rt, 1)
		return win_script_wrap(script, script.page.html.root)
	if (id == 8):
		if (b.child_nodes == 0):
			b.child_nodes = js_runtime_alloc(rt, 5)
			js_runtime_root(rt, b.child_nodes)
			js_runtime_set(rt, b.child_nodes, c"item", js_runtime_host_callable(rt, b, win_dom_children_item))
			js_runtime_set_host_hooks(rt, b.child_nodes, b, win_dom_children_get, win_dom_children_set)
			js_runtime_set_host_has(rt, b.child_nodes, win_dom_children_has)
		return b.child_nodes
	if (id == 9 || id == 10):
		if (node.kind == HTML_TEXT || node.kind == HTML_COMMENT): return win_js_string(rt, node.text)
		return js_runtime_alloc(rt, 1)
	if (id == 11): return win_js_string(rt, node.name)
	if (id == 12): return win_js_string(rt, c"http://www.w3.org/1999/xhtml")
	html_node* element = win_dom_document_element(script)
	if (id == 13): return win_script_wrap(script, element)
	if (element != 0):
		html_node* child = element.first_child
		while (child != 0):
			if (win_dom_tree_charge(rt, 1) == 0): return rt.undefined_value
			if (id == 14 && win_tag(child, c"head")): return win_script_wrap(script, child)
			if (id == 15 && (win_tag(child, c"body") || win_tag(child, c"frameset"))): return win_script_wrap(script, child)
			child = child.next_sibling
	return js_runtime_alloc(rt, 1)

char* win_dom_tree_text(js_runtime* rt, js_value* value):
	if (value.kind >= 5):
		js_runtime_fail(rt, 6, c"DOM tree object string coercion is unsupported")
		return 0
	if (value.kind == 4):
		int length = 0
		char* text = js_text_to_utf8(value.text, &length)
		if (text == 0 || strlen(text) != length):
			free(text)
			js_runtime_fail(rt, 6, c"DOM text requires scalar UTF-8 without NUL")
			return 0
		return text
	return win_js_text(value)

int win_dom_tree_set(win_dom_binding* b, js_text* key, js_value* value):
	int id = win_dom_tree_key(b, key)
	if (id == 0): return 0
	if ((id == 9 || id == 10) && b.node.kind == HTML_TEXT):
		win_script* script = cast(win_script*, b.context)
		char* text = win_dom_tree_text(script.runtime, value)
		if (text == 0): return -1
		if (id == 9 && value.kind == 1): text[0] = 0
		win_dom_set_text(script, b.node, text)
		free(text)
		if (script.runtime.completion.status != 0): return -1
	return 1

js_value* win_dom_tree_mutate(win_dom_binding* b, js_value* receiver, list[js_value*] args, int operation):
	win_script* script = cast(win_script*, b.context)
	js_runtime* rt = script.runtime
	if (receiver != b.object || args.length < 1 || (operation == 1 && args.length < 2)):
		js_runtime_fail(rt, 2, c"DOM tree mutation requires its Node receiver and arguments")
		return rt.undefined_value
	html_node* parent = b.node
	html_node* child = win_dom_tree_find(script, args[0])
	if (rt.completion.status != 0): return rt.undefined_value
	if (child == 0):
		js_runtime_fail(rt, 2, c"DOM tree mutation requires a same-document Node")
		return rt.undefined_value
	html_node* reference = 0
	if (operation == 1 && args[1].kind != 1):
		reference = win_dom_tree_find(script, args[1])
		if (rt.completion.status != 0): return rt.undefined_value
		if (reference == 0):
			js_runtime_fail(rt, 2, c"insertBefore reference must be a Node or null")
			return rt.undefined_value
	if (operation == 2):
		if (child.parent != parent):
			win_dom_tree_error(rt, c"NotFoundError", c"Node is not a child of the receiver")
			return rt.undefined_value
	else:
		if ((parent.kind != HTML_START && parent.kind != HTML_FRAGMENT) || (child.kind != HTML_START && child.kind != HTML_TEXT && child.kind != HTML_FRAGMENT)):
			win_dom_hierarchy_error(rt)
			return rt.undefined_value
		html_node* ancestor = parent
		int depth = 0
		while (ancestor != 0):
			if (ancestor == child):
				win_dom_hierarchy_error(rt)
				return rt.undefined_value
			if (win_dom_tree_charge(rt, 1) == 0): return rt.undefined_value
			depth = depth + 1
			ancestor = ancestor.parent
		if (reference != 0 && reference.parent != parent):
			win_dom_tree_error(rt, c"NotFoundError", c"Reference is not a child of the receiver")
			return rt.undefined_value
		if (child.kind == HTML_FRAGMENT):
			html_node* item = child.first_child
			while (item != 0):
				if (win_dom_tree_charge(rt, 1) == 0): return rt.undefined_value
				if (item.kind != HTML_START && item.kind != HTML_TEXT):
					win_dom_hierarchy_error(rt)
					return rt.undefined_value
				win_dom_bounded_height(rt, item, 128 - depth)
				if (rt.completion.status != 0): return rt.undefined_value
				item = item.next_sibling
		else:
			win_dom_bounded_height(rt, child, 128 - depth)
			if (rt.completion.status != 0): return rt.undefined_value
	# Reserve linked-list scans before mutation, so exhaustion leaves both trees intact.
	if (win_dom_tree_charge(rt, 2 * script.page.html.node_count) == 0): return rt.undefined_value
	if (reference == child): reference = child.next_sibling
	if (operation == 2): win_dom_detach(child)
	else:
		html_node* first = child
		html_node* last = child
		if (child.kind == HTML_FRAGMENT):
			first = child.first_child
			last = child.last_child
			child.first_child = 0
			child.last_child = 0
		else: win_dom_detach(child)
		if (first != 0):
			html_node* item = first
			while (item != 0):
				item.parent = parent
				item = item.next_sibling
			last.next_sibling = reference
			if (reference == 0):
				if (parent.last_child != 0): parent.last_child.next_sibling = first
				else: parent.first_child = first
				parent.last_child = last
			else if (parent.first_child == reference): parent.first_child = first
			else:
				html_node* previous = parent.first_child
				while (previous.next_sibling != reference): previous = previous.next_sibling
				previous.next_sibling = first
	script.dirty = 1
	script.styles_dirty = 1
	return args[0]

js_value* win_dom_tree_append(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	return win_dom_tree_mutate(cast(win_dom_binding*, context), receiver, args, 0)

js_value* win_dom_tree_insert(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	return win_dom_tree_mutate(cast(win_dom_binding*, context), receiver, args, 1)

js_value* win_dom_tree_remove(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	return win_dom_tree_mutate(cast(win_dom_binding*, context), receiver, args, 2)

js_value* win_dom_tree_create(win_dom_binding* b, js_value* receiver, list[js_value*] args, int operation):
	win_script* script = cast(win_script*, b.context)
	js_runtime* rt = script.runtime
	int name_index = 0
	if (operation == 1): name_index = 1
	if (receiver != b.object || b.node != script.page.html.root || args.length <= name_index):
		js_runtime_fail(rt, 2, c"Node creation requires the Document receiver and arguments")
		return rt.undefined_value
	if (operation == 1 && (args[0].kind != 4 || js_runtime_key_is(args[0].text, c"http://www.w3.org/1999/xhtml") == 0)):
		js_runtime_fail(rt, 6, c"Only HTML namespace element creation is supported")
		return rt.undefined_value
	if (args.length > name_index + 1 && args[name_index + 1].kind != 0):
		js_runtime_fail(rt, 6, c"Customized built-in elements are unsupported")
		return rt.undefined_value
	char* name = win_dom_tree_text(rt, args[name_index])
	if (name == 0): return rt.undefined_value
	if (operation != 2):
		int valid = html_alpha(name[0])
		for i in range(strlen(name)):
			int c = name[i]
			if (html_alpha(c) == 0 && (c < '0' || c > '9') && c != '-' && c != '_' && c != '.'): valid = 0
			if (operation == 0): name[i] = html_lower(c)
		if (valid == 0):
			free(name)
			win_dom_tree_error(rt, c"InvalidCharacterError", c"Only ASCII unprefixed HTML names are supported")
			return rt.undefined_value
	int kind = HTML_START
	if (operation == 2): kind = HTML_TEXT
	html_node* node = win_dom_create(script, kind, name)
	free(name)
	if (node == 0): return rt.undefined_value
	return win_script_wrap(script, node)

js_value* win_dom_tree_element(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	return win_dom_tree_create(cast(win_dom_binding*, context), receiver, args, 0)

js_value* win_dom_tree_element_ns(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	return win_dom_tree_create(cast(win_dom_binding*, context), receiver, args, 1)

js_value* win_dom_tree_text_node(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	return win_dom_tree_create(cast(win_dom_binding*, context), receiver, args, 2)

js_value* win_dom_tree_fragment(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	win_dom_binding* b = cast(win_dom_binding*, context)
	win_script* script = cast(win_script*, b.context)
	js_runtime* rt = script.runtime
	if (receiver != b.object || b.node != script.page.html.root):
		js_runtime_fail(rt, 2, c"DocumentFragment creation requires the Document receiver")
		return rt.undefined_value
	html_node* node = win_dom_create(script, HTML_FRAGMENT, c"#document-fragment")
	if (node == 0): return rt.undefined_value
	return win_script_wrap(script, node)

# Live HTMLCollection owners are held by the node binding until realm teardown.
struct win_dom_collection:
	win_dom_binding* binding
	char* tag
	js_value* object
	win_dom_collection* next

void win_dom_collections_free(win_dom_binding* binding):
	win_dom_collection* collection = cast(win_dom_collection*, binding.collections)
	while (collection != 0):
		win_dom_collection* next = collection.next
		free(collection.tag)
		free(collection)
		collection = next

# Iterative preorder traversal charges descents, ascents and sibling edges.
# It never walks outside the collection's root, including detached subtrees.
html_node* win_dom_collection_next(win_dom_collection* collection, html_node* node):
	win_script* script = cast(win_script*, collection.binding.context)
	if (win_dom_tree_charge(script.runtime, 1) == 0): return 0
	if (node.first_child != 0): return node.first_child
	html_node* root = collection.binding.node
	while (node != root):
		if (node.next_sibling != 0): return node.next_sibling
		if (win_dom_tree_charge(script.runtime, 1) == 0): return 0
		node = node.parent
	return 0

int win_dom_collection_match(win_dom_collection* collection, html_node* node):
	if (node.kind != HTML_START): return 0
	win_script* script = cast(win_script*, collection.binding.context)
	if (win_dom_tree_charge(script.runtime, strlen(collection.tag) + strlen(node.name) + 1) == 0): return 0
	return strcmp(collection.tag, c"*") == 0 || strcmp(collection.tag, node.name) == 0

# index=-1 counts all matches; name!=0 selects the first id/name match.
html_node* win_dom_collection_scan(win_dom_collection* collection, int index, char* name, int* count):
	win_script* script = cast(win_script*, collection.binding.context)
	*count = 0
	html_node* node = win_dom_collection_next(collection, collection.binding.node)
	while (node != 0 && script.runtime.completion.status == 0):
		if (win_dom_collection_match(collection, node)):
			if (name != 0):
				html_attribute* attr = node.attributes
				while (attr != 0):
					if (win_dom_tree_charge(script.runtime, strlen(attr.name) + strlen(attr.value) + strlen(name) + 1) == 0): return 0
					if (name[0] != 0 && (strcmp(attr.name, c"id") == 0 || strcmp(attr.name, c"name") == 0) && strcmp(attr.value, name) == 0): return node
					attr = attr.next
			else if (*count == index): return node
			*count = *count + 1
		node = win_dom_collection_next(collection, node)
	return 0

int win_dom_collection_builtin(js_runtime* rt, js_value* receiver, js_text* key):
	js_value* object = receiver
	while (object != 0):
		if (win_dom_tree_charge(rt, (key.units.length + 1) * (object.properties.length + 1)) == 0): return 0
		if (js_runtime_property(object, key) != 0): return 1
		object = object.prototype
	return 0

html_node* win_dom_collection_named(win_dom_collection* collection, js_text* key):
	int size = 0
	char* name = js_text_to_utf8(key, &size)
	if (name == 0): return 0
	html_node* result = 0
	if (strlen(name) == size):
		int count = 0
		result = win_dom_collection_scan(collection, -1, name, &count)
	free(name)
	return result

js_value* win_dom_collection_get(void* runtime, void* context, js_value* receiver, js_text* key):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_dom_collection* collection = cast(win_dom_collection*, context)
	if (receiver != collection.object): return 0
	int count = 0
	if (js_runtime_key_is(key, c"length")):
		win_dom_collection_scan(collection, -1, 0, &count)
		if (rt.completion.status != 0): return rt.undefined_value
		return js_runtime_number(rt, cast(float64, count))
	int index = js_runtime_array_index(key)
	html_node* node = 0
	if (index >= 0): node = win_dom_collection_scan(collection, index, 0, &count)
	else:
		if (win_dom_collection_builtin(cast(js_runtime*, runtime), receiver, key)): return 0
		node = win_dom_collection_named(collection, key)
	if (rt.completion.status != 0): return rt.undefined_value
	if (node == 0): return 0
	return win_script_wrap(cast(win_script*, collection.binding.context), node)

int win_dom_collection_has(void* runtime, void* context, js_value* receiver, js_text* key):
	win_dom_collection* collection = cast(win_dom_collection*, context)
	if (receiver != collection.object): return 0
	if (js_runtime_key_is(key, c"length")): return 1
	int index = js_runtime_array_index(key)
	int count = 0
	if (index >= 0): return win_dom_collection_scan(collection, index, 0, &count) != 0
	if (win_dom_collection_builtin(cast(js_runtime*, runtime), receiver, key)): return 1
	return win_dom_collection_named(collection, key) != 0

int win_dom_collection_set(void* runtime, void* context, js_value* receiver, js_text* key, js_value* value):
	win_dom_collection* collection = cast(win_dom_collection*, context)
	if (receiver != collection.object): return 0
	if (js_runtime_key_is(key, c"length") || js_runtime_array_index(key) >= 0): return 1
	if (win_dom_collection_builtin(cast(js_runtime*, runtime), receiver, key)): return 0
	return win_dom_collection_named(collection, key) != 0

js_value* win_dom_collection_item(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_dom_collection* collection = cast(win_dom_collection*, context)
	if (receiver != collection.object || args.length == 0):
		js_runtime_fail(rt, 2, c"HTMLCollection.item requires its receiver and index")
		return rt.undefined_value
	if (args[0].kind != 3):
		js_runtime_fail(rt, 6, c"HTMLCollection.item index coercion is unsupported")
		return rt.undefined_value
	int count = 0
	int index = js_binary_uint(args[0].number, 32)
	html_node* node = win_dom_collection_scan(collection, index, 0, &count)
	if (rt.completion.status != 0): return rt.undefined_value
	return win_script_wrap(cast(win_script*, collection.binding.context), node)

js_value* win_dom_collection_named_item(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_dom_collection* collection = cast(win_dom_collection*, context)
	if (receiver != collection.object || args.length == 0):
		js_runtime_fail(rt, 2, c"HTMLCollection.namedItem requires its receiver and name")
		return rt.undefined_value
	char* name = win_dom_tree_text(rt, args[0])
	if (name == 0): return rt.undefined_value
	int count = 0
	html_node* node = win_dom_collection_scan(collection, -1, name, &count)
	free(name)
	if (rt.completion.status != 0): return rt.undefined_value
	return win_script_wrap(cast(win_script*, collection.binding.context), node)

int win_dom_collection_method(js_runtime* rt, win_dom_collection* collection, char* name, js_host_receiver_function* callback):
	js_value* method = js_runtime_host_callable(rt, collection, callback)
	if (rt.completion.status != 0): return 0
	js_text* key = js_runtime_key(name)
	# Define own properties without invoking attacker-controlled prototype setters.
	int ok = js_runtime_define_data(rt, collection.object, key, method, 1, 0, 1)
	js_text_free(key)
	return ok

js_value* win_dom_get_elements_by_tag(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	win_dom_binding* binding = cast(win_dom_binding*, context)
	win_script* script = cast(win_script*, binding.context)
	js_runtime* rt = script.runtime
	if (receiver != binding.object || args.length == 0 || (binding.node.kind != HTML_START && binding.node != script.page.html.root)):
		js_runtime_fail(rt, 2, c"getElementsByTagName requires Document or Element receiver and name")
		return rt.undefined_value
	char* tag = win_dom_tree_text(rt, args[0])
	if (tag == 0): return rt.undefined_value
	int size = strlen(tag)
	if (size > 65536 || script.dom_bytes > 4194304 - size || win_dom_tree_charge(rt, size + 1) == 0):
		free(tag)
		js_runtime_fail(rt, 5, c"HTMLCollection name limit")
		return rt.undefined_value
	for i in range(size): tag[i] = html_lower(tag[i] & 255)
	win_dom_collection* current = cast(win_dom_collection*, binding.collections)
	int count = 0
	while (current != 0):
		if (win_dom_tree_charge(rt, size + strlen(current.tag) + 1) == 0):
			free(tag)
			return rt.undefined_value
		if (strcmp(current.tag, tag) == 0):
			free(tag)
			return current.object
		count = count + 1
		current = current.next
	if (count >= 256):
		free(tag)
		js_runtime_fail(rt, 5, c"HTMLCollection owner limit")
		return rt.undefined_value
	win_dom_collection* collection = new win_dom_collection()
	collection.binding = binding
	collection.tag = tag
	collection.object = js_runtime_alloc(rt, 5)
	int complete = rt.completion.status == 0
	if (complete): complete = win_dom_collection_method(rt, collection, c"item", win_dom_collection_item)
	if (complete): complete = win_dom_collection_method(rt, collection, c"namedItem", win_dom_collection_named_item)
	if (complete): complete = js_runtime_set_host_hooks(rt, collection.object, collection, win_dom_collection_get, win_dom_collection_set)
	if (complete): complete = js_runtime_set_host_has(rt, collection.object, win_dom_collection_has)
	if (complete): complete = js_runtime_root(rt, collection.object)
	if (complete == 0 || rt.completion.status != 0):
		# No getter/setter/callback ran and nothing exposed the partial object.
		# Its unrooted JS values are reclaimed at the next normal collection.
		if (complete): js_runtime_unroot(rt, collection.object)
		free(collection.tag)
		free(collection)
		js_runtime_fail(rt, 5, c"HTMLCollection construction failed")
		return rt.undefined_value
	# Publish the stable cache only after every fallible construction step.
	collection.next = cast(win_dom_collection*, binding.collections)
	binding.collections = collection
	script.dom_bytes = script.dom_bytes + size
	return collection.object

void win_dom_tree_install(win_dom_binding* b):
	win_script* script = cast(win_script*, b.context)
	js_runtime* rt = script.runtime
	if (b.node == script.window_node): return
	if (b.node.kind == HTML_START || b.node == script.page.html.root): js_runtime_set(rt, b.object, c"getElementsByTagName", js_runtime_host_callable(rt, b, win_dom_get_elements_by_tag))
	js_runtime_set(rt, b.object, c"appendChild", js_runtime_host_callable(rt, b, win_dom_tree_append))
	js_runtime_set(rt, b.object, c"insertBefore", js_runtime_host_callable(rt, b, win_dom_tree_insert))
	js_runtime_set(rt, b.object, c"removeChild", js_runtime_host_callable(rt, b, win_dom_tree_remove))
	if (b.node == script.page.html.root):
		js_runtime_set(rt, b.object, c"createDocumentFragment", js_runtime_host_callable(rt, b, win_dom_tree_fragment))
		js_runtime_set(rt, b.object, c"createElement", js_runtime_host_callable(rt, b, win_dom_tree_element))
		js_runtime_set(rt, b.object, c"createElementNS", js_runtime_host_callable(rt, b, win_dom_tree_element_ns))
		js_runtime_set(rt, b.object, c"createTextNode", js_runtime_host_callable(rt, b, win_dom_tree_text_node))
