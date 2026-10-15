import lib.assert
import lib.args
import lib.stream
import tests.images.jpeg_fixtures
import win.resources

void resource_test_wait(win_resources* resources):
	int start = time_monotonic_ms()
	while (win_resources_done(resources) == 0):
		win_resources_poll(resources)
		asserts(c"bounded resource completion", time_monotonic_ms() - start < 14000)
		sleep_ms(1)

void test_resource_queue(char* executable, char* fixture):
	char* source = c"<link rel='stylesheet' href='theme.css'><script src='page.js'></script><p class='resource-hidden'>hidden</p><img src='checker.png' width='80' height='80'><img src='missing.png' alt='fallback'>"
	win_page* page = win_page_parse(source, strlen(source))
	win_resources* resources = win_resources_start(executable, page, fixture)
	assert_equal(4, resources.entries.length)
	resource_test_wait(resources)
	assert_equal(1, resources.failed)
	assert_equal(2, page.images.length)
	assert_equal(8, page.images[0].width)
	assert_equal(8, page.images[0].height)
	assert_equal(220, page.images[0].pixels[0] & 255)
	assert_equal(1, page.images[1].failed)
	win_resource* script = resources.entries[1]
	asserts(c"external script retained", script.source != 0 && script.length > 0)
	asserts(c"script lookup", win_resources_script(resources, script.node) == script)
	win_page_layout(page, 600)
	int rendered_image = 0
	for i in range(page.runs.length):
		asserts(c"external stylesheet applied", strcmp(page.runs[i].text, c"hidden") != 0)
		if (page.runs[i].image != 0):
			rendered_image = 1
			asserts(c"HTML dimensions honored", page.runs[i].width == 80.0 && page.runs[i].height == 80.0)
	assert_equal(1, rendered_image)
	ui_renderer renderer
	ui_render_init_headless(&renderer)
	ui_render_begin(&renderer, 100, 100)
	win_image_draw(&renderer, page.images[0], ui_rect_new(0.0, 0.0, 80.0, 80.0))
	assert_equal(1, renderer.commands.length)
	asserts(c"native image command", renderer.commands[0].image == page.images[0].texture)
	asserts(c"pixel ownership transferred", page.images[0].pixels == 0)
	assert_equal(220, page.images[0].texture.pixels[0] & 255)
	win_resources_free(resources)
	win_page_free(page)
	ui_render_destroy(&renderer)
	page = win_page_parse(source, strlen(source))
	resources = win_resources_start(executable, page, fixture)
	win_resources_poll(resources)
	win_resources_stop(resources)
	assert_equal(1, win_resources_done(resources))
	for i in range(resources.entries.length): asserts(c"cancel releases all children", resources.entries[i].load == 0)
	win_resources_free(resources)
	win_page_free(page)
	page = win_page_parse(source, strlen(source))
	resources = win_resources_start(executable, page, fixture)
	resources.bytes = WIN_RESOURCE_BYTES
	resources.image_bytes = WIN_PAGE_IMAGE_BYTES
	resource_test_wait(resources)
	assert_equal(4, resources.failed)
	asserts(c"aggregate limit prevents image allocation", page.images[0].pixels == 0)
	asserts(c"aggregate limit prevents source retention", resources.entries[1].source == 0)
	win_resources_free(resources)
	win_page_free(page)

void test_resource_policy(char* executable):
	char* source = c"<base href='http://insecure.invalid/'><img src='http://insecure.invalid/a.png'><script src='file:///tmp/no.js'></script>"
	win_page* page = win_page_parse(source, strlen(source))
	win_resources* resources = win_resources_start(executable, page, c"https://secure.invalid/index.html")
	assert_strings_equal(c"https://secure.invalid/index.html", resources.base)
	assert_equal(2, resources.failed)
	assert_equal(1, win_resources_done(resources))
	win_resources_free(resources)
	win_page_free(page)
	string_builder* many = string_new()
	for i in range(80): string_append(many, c"<img src='x.png'>")
	page = win_page_parse(many.data, many.length)
	resources = win_resources_start(executable, page, c"/tmp/index.html")
	assert_equal(WIN_RESOURCE_COUNT, resources.entries.length)
	assert_equal(WIN_RESOURCE_COUNT, page.images.length)
	win_resources_stop(resources)
	win_resources_free(resources)
	win_page_free(page)
	string_free(many)

void test_jpeg_worker(char* executable):
	string_builder* path = string_new()
	string_append(path, c"/tmp/win-jpeg-")
	string_append_int(path, getpid())
	string_append(path, c".jpg")
	wstream* file = stream_open_write(path.data)
	asserts(c"temporary JPEG", file != 0)
	stream_write(file, jpeg_fixture_color(), jpeg_fixture_color_length)
	stream_close(file)
	win_load* load = win_load_start_kind(executable, path.data, c"image", c"GET", c"")
	int start = time_monotonic_ms()
	while (win_load_poll(load) == 0):
		asserts(c"image worker completes", time_monotonic_ms() - start < 14000)
		sleep_ms(1)
	asserts(c"JPEG worker succeeds", load.error == 0)
	win_image image
	assert_equal(1, win_image_receive(&image, load.source, load.length))
	assert_equal(13, image.width)
	assert_equal(9, image.height)
	free(image.pixels)
	win_load_free(load)
	unlink(path.data)
	string_free(path)

void test_slow_resources(char* executable, char* address):
	char* source = c"<img src='slow.png'>"
	win_page* page = win_page_parse(source, strlen(source))
	win_resources* resources = win_resources_start(executable, page, address)
	int frames = 0
	int start = time_monotonic_ms()
	ui_renderer renderer
	ui_render_init_headless(&renderer)
	while (win_resources_done(resources) == 0):
		int before = time_monotonic_ms()
		win_resources_poll(resources)
		ui_render_begin(&renderer, 200, 200)
		ui_render_rect(&renderer, ui_rect_new(0.0, 0.0, 20.0, 20.0), ui_gray(0.5))
		ui_render_end(&renderer)
		asserts(c"resource polling keeps frames responsive", time_monotonic_ms() - before < 250)
		asserts(c"slow resource finishes", time_monotonic_ms() - start < 4000)
		frames = frames + 1
		sleep_ms(5)
	asserts(c"drawing continues during slow image", frames > 10)
	assert_equal(8, page.images[0].width)
	win_resources_free(resources)
	win_page_free(page)
	ui_render_destroy(&renderer)

void resource_test_attr(html_node* node, char* name, char* value):
	html_attribute* attr = html_attribute_find(node.attributes, name)
	if (attr == 0):
		attr = new html_attribute()
		attr.name = strclone(name)
		attr.next = node.attributes
		node.attributes = attr
	else: free(attr.value)
	attr.value = strclone(value)
	attr.value_length = strlen(value)

void test_dynamic_resources(char* executable, char* fixture):
	char* source = c"<link rel='stylesheet' href='theme.css'><img src='checker.png'><script src='page.js'></script><img src=''><script src=''></script>"
	win_page* page = win_page_parse(source, strlen(source))
	win_resources* resources = win_resources_start(executable, page, fixture)
	assert_equal(3, resources.entries.length)
	for i in range(5): assert_equal(0, win_resources_refresh(resources))
	resource_test_wait(resources)
	win_resource* sheet = resources.entries[0]
	win_resource* image = resources.entries[1]
	win_resource* script = resources.entries[2]
	asserts(c"loaded stylesheet", page.stylesheets[0].css != 0)
	int used_bytes = resources.bytes
	int used_image_bytes = resources.image_bytes
	resource_test_attr(sheet.node, c"media", c"print")
	resource_test_attr(image.node, c"src", c"missing.png")
	resource_test_attr(script.node, c"src", c"missing.js")
	assert_equal(1, win_resources_refresh(resources))
	assert_equal(5, resources.entries.length)
	assert_equal(used_bytes, resources.bytes)
	assert_equal(used_image_bytes, resources.image_bytes)
	assert_equal(1, sheet.retired)
	asserts(c"obsolete stylesheet removed", page.stylesheets[0].css == 0)
	assert_equal(1, image.retired)
	assert_equal(1, script.retired)
	asserts(c"obsolete script source released", script.source == 0)
	asserts(c"lookup selects new script", win_resources_script(resources, script.node) == resources.entries[4])
	assert_equal(1, page.images.length)
	asserts(c"stale image pixels removed", page.images[0].pixels == 0 && page.images[0].width == 0)
	resource_test_wait(resources)
	assert_equal(2, resources.failed)
	resource_test_attr(image.node, c"src", c"checker.png")
	resource_test_attr(sheet.node, c"media", c"screen")
	assert_equal(1, win_resources_refresh(resources))
	resource_test_wait(resources)
	assert_equal(8, page.images[0].width)
	asserts(c"stylesheet restored", page.stylesheets[0].css != 0)
	# Previously empty sources become discoverable on mutation.
	html_node* inserted_image = script.node.next_sibling
	html_node* inserted_script = inserted_image.next_sibling
	resource_test_attr(inserted_image, c"src", c"checker.png")
	resource_test_attr(inserted_script, c"src", c"page.js")
	assert_equal(1, win_resources_refresh(resources))
	resource_test_wait(resources)
	assert_equal(2, page.images.length)
	asserts(c"new script downloaded", win_resources_script(resources, inserted_script).source != 0)
	# Disconnect and reconnect the tail, retaining node ownership in the DOM.
	script.node.next_sibling = 0
	assert_equal(1, win_resources_refresh(resources))
	asserts(c"detached script unavailable", win_resources_script(resources, inserted_script) == 0)
	assert_equal(1, page.images[1].failed)
	script.node.next_sibling = inserted_image
	assert_equal(1, win_resources_refresh(resources))
	resource_test_wait(resources)
	assert_equal(2, page.images.length)
	assert_equal(8, page.images[1].width)
	# URL churn cannot replenish the lifetime request budget.
	for i in range(80):
		if (i % 2 == 0): resource_test_attr(image.node, c"src", c"missing.png")
		else: resource_test_attr(image.node, c"src", c"checker.png")
		win_resources_refresh(resources)
	assert_equal(WIN_RESOURCE_COUNT, resources.entries.length)
	win_resources_stop(resources)
	assert_equal(0, win_resources_refresh(resources))
	assert_equal(0, win_resources_poll(resources))
	for i in range(resources.entries.length): asserts(c"all replaced workers reaped", resources.entries[i].load == 0)
	win_resources_free(resources)
	win_page_free(page)

void test_stale_resources(char* executable, char* address):
	char* source = c"<img src='slow.png'><link rel='stylesheet' href='slow.css'><script src='slow.js'></script>"
	win_page* page = win_page_parse(source, strlen(source))
	win_resources* resources = win_resources_start(executable, page, address)
	win_resources_poll(resources)
	sleep_ms(80)
	win_resource* old_image = resources.entries[0]
	win_resource* old_css = resources.entries[1]
	win_resource* old_script = resources.entries[2]
	resource_test_attr(old_image.node, c"src", c"checker.png")
	resource_test_attr(old_css.node, c"href", c"theme.css")
	resource_test_attr(old_script.node, c"src", c"second.js")
	# poll itself must reconcile first, even if the caller omitted refresh.
	win_resources_poll(resources)
	asserts(c"stale workers canceled", old_image.load == 0 && old_css.load == 0 && old_script.load == 0)
	asserts(c"stale records retired", old_image.retired && old_css.retired && old_script.retired)
	resource_test_wait(resources)
	assert_equal(0, resources.failed)
	assert_equal(8, page.images[0].width)
	asserts(c"fresh stylesheet replaces stale response", page.stylesheets[0].css != 0 && strcmp(page.stylesheets[0].css.source, c".hidden { display:none; }") == 0)
	asserts(c"fresh script replaces stale response", starts_with(win_resources_script(resources, old_script.node).source, c"if (document.title"))
	asserts(c"stale script not returned", win_resources_script(resources, old_script.node) != old_script)
	assert_equal(0, win_resources_refresh(resources))
	win_resources_free(resources)
	win_page_free(page)

int main(int argc, int argv):
	args_init(argc, argv)
	if (argc == 4 && strcmp(args_get(1), c"--slow") == 0):
		test_slow_resources(args_get(2), args_get(3))
		test_stale_resources(args_get(2), args_get(3))
		return 0
	assert_equal(3, argc)
	char* dir = path_dirname(args_get(2))
	char* fixture = path_join(dir, c"resources/images.html")
	test_resource_queue(args_get(1), fixture)
	test_dynamic_resources(args_get(1), fixture)
	free(fixture)
	free(dir)
	test_resource_policy(args_get(1))
	test_jpeg_worker(args_get(1))
	println(c"resource tests passed")
	return 0
