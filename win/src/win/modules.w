# Per-document module source cache. Network work is asynchronous; the W module
# resolver only sees completed, validated sources and never performs I/O.
import win.loader
import libs.extras.javascript.modules

struct win_module_source:
	js_module_source source
	char* base
	win_load* load
	int scanned
	int depth

struct win_modules:
	js_modules* engine
	char* executable
	char* address
	char* error
	list[win_module_source*] sources
	int bytes
	int requests
	int stopped

void win_modules_fail(win_modules* context, char* error):
	if (context.error == 0): context.error = strclone(error)

win_module_source* win_modules_find(win_modules* context, char* identifier):
	for i in range(context.sources.length):
		if (strcmp(context.sources[i].source.identifier, identifier) == 0): return context.sources[i]
	return 0

# Bare specifiers require an import map, which this host does not yet expose.
char* win_modules_resolve(win_modules* context, char* specifier, char* referrer):
	if (specifier == 0 || specifier[0] == 0): return 0
	if (win_remote(specifier) == 0 && specifier[0] != '/' && starts_with(specifier, c"./") == 0 && starts_with(specifier, c"../") == 0): return 0
	char* base = referrer
	win_module_source* parent = win_modules_find(context, referrer)
	if (parent != 0): base = parent.base
	char* resolved = win_resolve(base, specifier)
	if (resolved == 0): return 0
	if (win_remote(context.address)):
		URL* from = url_parse(context.address)
		URL* to = url_parse(resolved)
		int allowed = from != 0 && to != 0 && url_same_origin(from, to)
		if (from != 0): url_free(from)
		if (to != 0): url_free(to)
		if (allowed == 0):
			free(resolved)
			return 0
	return resolved

js_module_source* win_modules_resolver(void* data, char* specifier, char* referrer):
	win_modules* context = cast(win_modules*, data)
	# Root identifiers may be synthetic inline document identifiers.
	win_module_source* found = 0
	if (referrer[0] == 0): found = win_modules_find(context, specifier)
	if (found == 0):
		char* address = win_modules_resolve(context, specifier, referrer)
		if (address == 0): return 0
		found = win_modules_find(context, address)
		free(address)
	if (found == 0 || found.scanned == 0 || found.source.source == 0): return 0
	return &found.source

win_modules* win_modules_new(js_runtime* runtime, char* executable, char* address):
	win_modules* context = new win_modules()
	context.sources = new list[win_module_source*]
	context.executable = strclone(executable)
	context.address = strclone(address)
	context.engine = js_modules_new(runtime, win_modules_resolver, context)
	return context

win_module_source* win_modules_request_depth(win_modules* context, char* specifier, char* referrer, int depth):
	if (context.stopped || context.error != 0): return 0
	context.requests = context.requests + 1
	if (context.requests > context.engine.max_requests || depth > context.engine.max_depth):
		win_modules_fail(context, c"Module request or depth limit.")
		return 0
	char* address = win_modules_resolve(context, specifier, referrer)
	if (address == 0):
		win_modules_fail(context, c"Invalid or cross-origin module specifier.")
		return 0
	win_module_source* found = win_modules_find(context, address)
	if (found != 0):
		free(address)
		return found
	if (context.sources.length >= context.engine.max_modules):
		free(address)
		win_modules_fail(context, c"Module source count limit.")
		return 0
	found = new win_module_source()
	found.source.identifier = address
	found.base = strclone(address)
	found.depth = depth
	context.sources.push(found)
	return found

# Returns a borrowed source record; source.identifier is the evaluation key.
win_module_source* win_modules_request(win_modules* context, char* specifier, char* referrer):
	return win_modules_request_depth(context, specifier, referrer, 1)

win_module_source* win_modules_add_inline(win_modules* context, char* identifier, char* base, char* source, int length):
	if (context.stopped || context.error != 0): return 0
	if (win_modules_find(context, identifier) != 0):
		win_modules_fail(context, c"Duplicate inline module identifier.")
		return 0
	if (context.sources.length >= context.engine.max_modules || length < 0 || length > context.engine.runtime.max_source_bytes || length > context.engine.max_bytes - context.bytes):
		win_modules_fail(context, c"Module source limit.")
		return 0
	if (source == 0 || utf8_validate_bytes(source, length) == 0):
		win_modules_fail(context, c"Module source is not valid UTF-8.")
		return 0
	win_module_source* entry = new win_module_source()
	entry.source.identifier = strclone(identifier)
	entry.source.source = substring(source, 0, length)
	entry.source.length = length
	entry.base = strclone(base)
	entry.depth = 1
	context.bytes = context.bytes + length
	context.sources.push(entry)
	return entry

void win_modules_scan(win_modules* context, win_module_source* entry):
	pg_parse_result* parsed = js_parse_with_limits(entry.source.source, entry.source.length, entry.source.identifier, 1, context.engine.runtime.parse_limits)
	entry.scanned = 1
	if (parsed.success == 0): win_modules_fail(context, c"Invalid module syntax or parser limit.")
	else:
		for i in range(parsed.root.children.length):
			pg_ast_node* node = parsed.root.children[i]
			if (js_cst_is(node, c"statement")): node = node.children[0]
			if (js_cst_is(node, c"import_statement") == 0): continue
			pg_ast_node* token = js_cst_child(node, c"STRING")
			char* specifier = js_string_decode(token.text, parsed.diagnostics)
			if (specifier == 0): win_modules_fail(context, c"Invalid module specifier.")
			else: win_modules_request_depth(context, specifier, entry.source.identifier, entry.depth + 1)
			free(specifier)
	pg_parse_result_free(parsed)

# Returns 1 when the graph is ready or failed, 0 while I/O remains. Check
# context.error before evaluating. At most three loaders run concurrently.
int win_modules_poll(win_modules* context):
	if (context.stopped || context.error != 0): return 1
	int active = 0
	for i in range(context.sources.length):
		win_module_source* entry = context.sources[i]
		if (entry.scanned): continue
		if (entry.load != 0):
			if (win_load_poll(entry.load) == 0):
				active = active + 1
				continue
			win_load* load = entry.load
			if (load.error != 0): win_modules_fail(context, load.error)
			else if (load.length > context.engine.runtime.max_source_bytes || load.length > context.engine.max_bytes - context.bytes): win_modules_fail(context, c"Module source byte limit.")
			else if (utf8_validate_bytes(load.source, load.length) == 0): win_modules_fail(context, c"Module source is not valid UTF-8.")
			else:
				entry.source.source = substring(load.source, 0, load.length)
				entry.source.length = load.length
				context.bytes = context.bytes + load.length
				# Relative dependencies resolve against the final response URL.
				if (load.address != 0):
					free(entry.base)
					entry.base = strclone(load.address)
			win_load_free(load)
			entry.load = 0
		if (context.error != 0): return 1
		if (entry.source.source != 0): win_modules_scan(context, entry)
		if (context.error != 0): return 1
	int pending = 0
	for i in range(context.sources.length):
		win_module_source* entry = context.sources[i]
		if (entry.scanned): continue
		pending = 1
		if (entry.load == 0 && active < 3):
			entry.load = win_load_start_network(context.executable, entry.source.identifier, c"script", c"GET", c"", context.address)
			active = active + 1
	return pending == 0

js_module* win_modules_evaluate(win_modules* context, char* identifier, int budget):
	if (context.stopped || context.error != 0): return 0
	return js_modules_evaluate(context.engine, identifier, c"", budget)

void win_modules_stop(win_modules* context):
	if (context == 0): return
	context.stopped = 1
	for i in range(context.sources.length):
		win_load_free(context.sources[i].load)
		context.sources[i].load = 0

# Call before destroying the borrowed runtime.
void win_modules_free(win_modules* context):
	if (context == 0): return
	win_modules_stop(context)
	js_modules_free(context.engine)
	for i in range(context.sources.length):
		win_module_source* entry = context.sources[i]
		free(entry.source.identifier)
		free(entry.source.source)
		free(entry.base)
		free(entry)
	__w_list_free(cast(__w_list*, context.sources))
	free(context.executable)
	free(context.address)
	free(context.error)
	free(context)
