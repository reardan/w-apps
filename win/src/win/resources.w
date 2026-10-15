# Per-document asynchronous resource queue. Each child performs bounded I/O
# and image decode; at most three children run and cancellation reaps them.
import win.document
import win.loader

const int WIN_RESOURCE_COUNT = 64
const int WIN_RESOURCE_BYTES = 16777216
const int WIN_PAGE_IMAGE_BYTES = 67108864

struct win_resource:
	html_node* node
	char* kind
	char* address
	win_load* load
	char* source
	int length
	char* error
	int finished
	int retired
	int seen
	win_image* image

struct win_resources:
	win_page* page
	char* executable
	char* base
	list[win_resource*] entries
	int bytes
	int image_bytes
	int stopped
	int failed
	int revision
	int changes

win_resource* win_resources_script(win_resources* resources, html_node* node):
	if (resources == 0): return 0
	for i in range(resources.entries.length):
		win_resource* entry = resources.entries[i]
		if (entry.retired == 0 && entry.node == node && strcmp(entry.kind, c"script") == 0): return entry
	return 0

int win_resource_equal_ascii(char* left, char* right):
	int length = strlen(left)
	if (length != strlen(right)): return 0
	for i in range(length):
		int c = left[i] & 255
		if (c >= 'A' && c <= 'Z'): c = c + 32
		if (c != right[i]): return 0
	return 1

int win_resource_rel_stylesheet(char* rel):
	int at = 0
	while (rel[at] != 0):
		while (html_space(rel[at] & 255)): at = at + 1
		int start = at
		while (rel[at] != 0 && html_space(rel[at] & 255) == 0): at = at + 1
		char* token = substring(rel, start, at)
		int matched = win_resource_equal_ascii(token, c"stylesheet")
		free(token)
		if (matched): return 1
	return 0

# Records are never reused: the count and byte budgets cover the document's
# entire lifetime, including mutations and canceled requests.
void win_resources_retire(win_resources* resources, win_resource* entry):
	if (entry.retired): return
	resources.changes = resources.changes + 1
	entry.retired = 1
	entry.finished = 1
	win_load_free(entry.load)
	entry.load = 0
	free(entry.source)
	entry.source = 0
	entry.length = 0
	if (entry.image != 0):
		win_image* image = entry.image
		if (image.texture != 0): ui_image_release(image.texture)
		free(image.pixels)
		image.texture = 0
		image.pixels = 0
		image.width = 0
		image.height = 0
		image.length = 0
		image.failed = 1
	if (strcmp(entry.kind, c"css") == 0):
		for i in range(resources.page.stylesheets.length):
			win_stylesheet* sheet = resources.page.stylesheets[i]
			if (sheet.node == entry.node):
				if (sheet.css != 0): css_document_free(sheet.css)
				sheet.css = 0
	resources.page.width = 0

void win_resources_add(win_resources* resources, html_node* node, char* kind, char* reference):
	if (resources.stopped || reference[0] == 0): return
	char* address = win_resolve(resources.base, reference)
	for i in range(resources.entries.length):
		win_resource* previous = resources.entries[i]
		if (previous.retired || previous.node != node || strcmp(previous.kind, kind) != 0): continue
		int same = previous.address == 0 && address == 0
		if (previous.address != 0 && address != 0): same = strcmp(previous.address, address) == 0
		if (same):
			previous.seen = resources.revision
			free(address)
			return
		win_resources_retire(resources, previous)
	if (resources.entries.length >= WIN_RESOURCE_COUNT):
		free(address)
		return
	win_resource* entry = new win_resource()
	entry.node = node
	entry.kind = kind
	entry.address = address
	entry.seen = resources.revision
	if (entry.address == 0):
		entry.error = strclone(c"Invalid resource address.")
		entry.finished = 1
	else if (starts_with(resources.base, c"https://") && starts_with(entry.address, c"http://")):
		entry.error = strclone(c"Insecure resource on an HTTPS page.")
		entry.finished = 1
	if (strcmp(kind, c"image") == 0):
		entry.image = win_image_find(resources.page.images, node)
		if (entry.image == 0):
			entry.image = new win_image()
			entry.image.node = node
			resources.page.images.push(entry.image)
		entry.image.failed = entry.finished
	resources.entries.push(entry)
	resources.changes = resources.changes + 1
	if (entry.error != 0): resources.failed = resources.failed + 1

void win_resources_discover(win_resources* resources, html_node* node):
	if (node == 0 || win_tag(node, c"template")): return
	if (win_tag(node, c"link") && win_resource_rel_stylesheet(win_attr(node, c"rel")) && html_attribute_find(node.attributes, c"disabled") == 0):
		char* media = win_attr(node, c"media")
		if (strcmp(media, c"print") != 0): win_resources_add(resources, node, c"css", win_attr(node, c"href"))
	else if (win_tag(node, c"script")): win_resources_add(resources, node, c"script", win_attr(node, c"src"))
	else if (win_tag(node, c"img")): win_resources_add(resources, node, c"image", win_attr(node, c"src"))
	html_node* child = node.first_child
	while (child != 0):
		win_resources_discover(resources, child)
		child = child.next_sibling

# Invoke after DOM mutations and before script lookup/polling. Scanning the
# connected tree also detects removals and changes to rel/media/disabled.
int win_resources_refresh(win_resources* resources):
	if (resources == 0 || resources.stopped || resources.page == 0): return 0
	resources.revision = resources.revision + 1
	int before = resources.changes
	win_resources_discover(resources, resources.page.html.root)
	for i in range(resources.entries.length):
		win_resource* entry = resources.entries[i]
		if (entry.retired == 0 && entry.seen != resources.revision):
			win_resources_retire(resources, entry)
	int changed = resources.changes != before
	if (changed):
		win_page_refresh_styles(resources.page)
		resources.page.width = 0
	return changed

char* win_resources_base(html_node* node):
	if (node == 0 || win_tag(node, c"template")): return c""
	if (win_tag(node, c"base") && win_attr(node, c"href")[0] != 0): return win_attr(node, c"href")
	html_node* child = node.first_child
	while (child != 0):
		char* found = win_resources_base(child)
		if (found[0] != 0): return found
		child = child.next_sibling
	return c""

win_resources* win_resources_start(char* executable, win_page* page, char* address):
	win_resources* resources = new win_resources()
	resources.page = page
	resources.executable = strclone(executable)
	resources.base = strclone(address)
	resources.entries = new list[win_resource*]
	char* reference = win_resources_base(page.html.root)
	if (reference[0] != 0):
		char* resolved = win_resolve(address, reference)
		if (resolved != 0):
			# A base element cannot downgrade an HTTPS document.
			if (starts_with(address, c"https://") && starts_with(resolved, c"http://")): free(resolved)
			else:
				free(resources.base)
				resources.base = resolved
	win_resources_refresh(resources)
	return resources

void win_resources_stop(win_resources* resources):
	if (resources == 0): return
	resources.stopped = 1
	for i in range(resources.entries.length):
		win_resource* entry = resources.entries[i]
		if (entry.finished): continue
		win_load_free(entry.load)
		entry.load = 0
		entry.finished = 1
		entry.error = strclone(c"Resource loading stopped.")
		if (entry.image != 0): entry.image.failed = 1

void win_resources_free(win_resources* resources):
	if (resources == 0): return
	for i in range(resources.entries.length):
		win_resource* entry = resources.entries[i]
		win_load_free(entry.load)
		free(entry.address)
		free(entry.source)
		free(entry.error)
		free(entry)
	__w_list_free(cast(__w_list*, resources.entries))
	free(resources.executable)
	free(resources.base)
	free(resources)

int win_resources_done(win_resources* resources):
	if (resources == 0 || resources.stopped): return 1
	for i in range(resources.entries.length):
		if (resources.entries[i].finished == 0): return 0
	return 1

int win_resources_poll(win_resources* resources):
	if (resources == 0 || resources.stopped): return 0
	int active = 0
	int changed = win_resources_refresh(resources)
	for i in range(resources.entries.length):
		win_resource* entry = resources.entries[i]
		if (entry.finished || entry.load == 0): continue
		if (win_load_poll(entry.load) == 0):
			active = active + 1
			continue
		win_load* load = entry.load
		entry.finished = 1
		changed = 1
		if (load.error != 0): entry.error = strclone(load.error)
		else if (entry.image != 0):
			if (resources.image_bytes + load.length > WIN_PAGE_IMAGE_BYTES): entry.error = strclone(c"Page image memory limit exceeded.")
			else if (win_image_receive(entry.image, load.source, load.length) == 0): entry.error = strclone(c"Invalid decoded image.")
			else: resources.image_bytes = resources.image_bytes + entry.image.length
		else if (resources.bytes + load.length > WIN_RESOURCE_BYTES): entry.error = strclone(c"Page text resource limit exceeded.")
		else if (utf8_validate_bytes(load.source, load.length) == 0): entry.error = strclone(c"Resource is not valid UTF-8.")
		else:
			entry.source = substring(load.source, 0, load.length)
			entry.length = load.length
			resources.bytes = resources.bytes + load.length
			if (strcmp(entry.kind, c"css") == 0): win_page_add_stylesheet_for_node(resources.page, entry.node, entry.source, entry.length)
		if (entry.error != 0):
			resources.failed = resources.failed + 1
			if (entry.image != 0): entry.image.failed = 1
		win_load_free(entry.load)
		entry.load = 0
	for i in range(resources.entries.length):
		if (active >= 3): break
		win_resource* entry = resources.entries[i]
		if (entry.finished || entry.load != 0): continue
		entry.load = win_load_start_kind(resources.executable, entry.address, entry.kind, c"GET", c"")
		active = active + 1
	return changed
