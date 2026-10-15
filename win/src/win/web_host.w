# Browser host primitives, independent of script.w. The caller owns viewport
# state and must flush stylesheet/layout mutations before style/geometry reads.
# No navigation, visualViewport event target, or element scrolling is invented.
import win.document
import libs.extras.javascript.runtime

struct win_web_viewport:
	float64 width
	float64 height
	float64 ratio
	float64 scroll_x
	float64 scroll_y

js_value* win_web_string(js_runtime* rt, char* text):
	js_text* units = js_runtime_key(text)
	js_value* result = js_runtime_string(rt, units)
	js_text_free(units)
	return result

# Owned search component of the supplied document address. A '?' in the
# fragment is not a query; a bare '?' has an empty Location.search value.
char* win_web_location_search(char* address):
	int start = 0
	while (address[start] != 0 && address[start] != '?' && address[start] != '#'): start = start + 1
	if (address[start] != '?'): return strclone(c"")
	int end = start + 1
	while (address[end] != 0 && address[end] != '#'): end = end + 1
	if (end == start + 1): return strclone(c"")
	return substring(address, start, end)

# USVString conversion replaces lone surrogates, preserving embedded NUL.
char* win_web_usv_bytes(js_text* text, int* length):
	js_text* scalar = js_text_new()
	int i = 0
	while (i < text.units.length):
		int cp = text.units[i]
		i = i + 1
		if (cp >= 55296 && cp <= 56319 && i < text.units.length):
			int low = text.units[i]
			if (low >= 56320 && low <= 57343):
				scalar.units.push(cp)
				scalar.units.push(low)
				i = i + 1
				continue
		if (cp >= 55296 && cp <= 57343): cp = 65533
		scalar.units.push(cp)
	char* result = js_text_to_utf8(scalar, length)
	js_text_free(scalar)
	return result

# Forgiving UTF-8 decoder with maximal valid-prefix replacement, as required
# by form-urlencoded decoding (strict js_text_from_utf8 is unsuitable here).
js_text* win_web_decode(char* source, int first, int last):
	string_builder* bytes = string_new()
	int i = first
	while (i < last):
		int c = source[i] & 255
		if (c == '+'): c = ' '
		else if (c == '%' && i + 2 < last):
			int high = win_hex(source[i + 1])
			int low = win_hex(source[i + 2])
			if (high >= 0 && low >= 0):
				c = high * 16 + low
				i = i + 2
		string_append_char(bytes, c)
		i = i + 1
	js_text* result = js_text_new()
	i = 0
	while (i < bytes.length):
		int lead = bytes.data[i] & 255
		i = i + 1
		if (lead < 128):
			result.units.push(lead)
			continue
		int need = 0
		int cp = 0
		int lower = 128
		int upper = 191
		if (lead >= 194 && lead <= 223):
			need = 1
			cp = lead & 31
		else if (lead >= 224 && lead <= 239):
			need = 2
			cp = lead & 15
			if (lead == 224): lower = 160
			if (lead == 237): upper = 159
		else if (lead >= 240 && lead <= 244):
			need = 3
			cp = lead & 7
			if (lead == 240): lower = 144
			if (lead == 244): upper = 143
		else:
			result.units.push(65533)
			continue
		while (need > 0 && i < bytes.length):
			int next = bytes.data[i] & 255
			if (next < lower || next > upper): break
			cp = cp * 64 + (next & 63)
			i = i + 1
			need = need - 1
			lower = 128
			upper = 191
		if (need > 0): cp = 65533
		js_text_append_scalar(result, cp)
	string_free(bytes)
	return result

# String-input URLSearchParams.get primitive: first duplicate wins; missing
# returns JS null, present-but-empty returns ''. '#' is data in this API.
# Constructor coercion and prototype wiring belong to the parent host.
js_value* win_web_search_get(js_runtime* rt, js_text* query, js_text* name):
	if (query.units.length > 65536 || name.units.length > 65536):
		js_runtime_fail(rt, 5, c"URLSearchParams input limit")
		return rt.undefined_value
	int length = 0
	char* bytes = win_web_usv_bytes(query, &length)
	int name_length = 0
	char* name_bytes = win_web_usv_bytes(name, &name_length)
	js_text* wanted = js_text_from_utf8(name_bytes, name_length)
	free(name_bytes)
	js_value* result = js_runtime_alloc(rt, 1)
	int first = 0
	if (length > 0 && bytes[0] == '?'): first = 1
	while (first < length):
		if (rt.remaining <= 0):
			js_runtime_fail(rt, 5, c"URLSearchParams traversal budget")
			break
		rt.remaining = rt.remaining - 1
		int last = first
		while (last < length && bytes[last] != '&'): last = last + 1
		if (last > first):
			int equal = first
			while (equal < last && bytes[equal] != '='): equal = equal + 1
			js_text* key = win_web_decode(bytes, first, equal)
			int match = js_text_equal(key, wanted)
			js_text_free(key)
			if (match):
				int value_start = equal
				if (equal < last): value_start = equal + 1
				js_text* value = win_web_decode(bytes, value_start, last)
				result = js_runtime_string(rt, value)
				js_text_free(value)
				break
		first = last + 1
	js_text_free(wanted)
	free(bytes)
	return result

# Returns 0 for unknown properties. Install via the parent's window hook;
# ratio and CSS viewport sizes must come from the actual browser surface.
js_value* win_web_viewport_get(js_runtime* rt, win_web_viewport* viewport, js_text* key):
	if (js_runtime_key_is(key, c"innerWidth")): return js_runtime_number(rt, viewport.width)
	if (js_runtime_key_is(key, c"innerHeight")): return js_runtime_number(rt, viewport.height)
	if (js_runtime_key_is(key, c"devicePixelRatio")): return js_runtime_number(rt, viewport.ratio)
	if (js_runtime_key_is(key, c"scrollX") || js_runtime_key_is(key, c"pageXOffset")): return js_runtime_number(rt, viewport.scroll_x)
	if (js_runtime_key_is(key, c"scrollY") || js_runtime_key_is(key, c"pageYOffset")): return js_runtime_number(rt, viewport.scroll_y)
	return 0

int win_web_style(js_runtime* rt, win_page* page, html_node* node, win_style* result):
	list[html_node*] ancestors = new list[html_node*]
	while (node != 0 && node != page.html.root):
		if (ancestors.length >= 1024 || rt.remaining <= 0):
			__w_list_free(cast(__w_list*, ancestors))
			js_runtime_fail(rt, 5, c"Computed style traversal budget")
			return 0
		rt.remaining = rt.remaining - 1
		ancestors.push(node)
		node = node.parent
	*result = win_default_style()
	int* previous_budget = win_selector_budget
	win_selector_budget = &rt.remaining
	int i = ancestors.length
	while (i > 0):
		i = i - 1
		*result = win_node_style(page, ancestors[i], *result)
	win_selector_budget = previous_budget
	__w_list_free(cast(__w_list*, ancestors))
	if (rt.remaining <= 0):
		js_runtime_fail(rt, 5, c"Computed style traversal budget")
		return 0
	return 1

js_value* win_web_pixels(js_runtime* rt, float32 value):
	char* number = f64toa(cast(float64, value))
	int length = strlen(number)
	if (length > 2 && number[length - 2] == '.' && number[length - 1] == '0'): number[length - 2] = 0
	string_builder* text = string_from(number)
	string_append(text, c"px")
	js_value* result = win_web_string(rt, text.data)
	string_free(text)
	free(number)
	return result

# Resolved supported lengths, including cascade/inheritance/em units. Unknown
# properties are unhandled, never substituted with inline specified values.
js_value* win_web_computed_get(js_runtime* rt, win_page* page, html_node* node, js_text* key):
	int property = -1
	if (js_runtime_key_is(key, c"paddingLeft") || js_runtime_key_is(key, c"padding-left")): property = 0
	if (js_runtime_key_is(key, c"paddingRight") || js_runtime_key_is(key, c"padding-right")): property = 1
	if (js_runtime_key_is(key, c"paddingTop") || js_runtime_key_is(key, c"padding-top")): property = 2
	if (js_runtime_key_is(key, c"paddingBottom") || js_runtime_key_is(key, c"padding-bottom")): property = 3
	if (js_runtime_key_is(key, c"fontSize") || js_runtime_key_is(key, c"font-size")): property = 4
	if (property < 0): return 0
	win_style style
	if (win_web_style(rt, page, node, &style) == 0): return rt.undefined_value
	float32 value = style.size
	if (property == 0): value = style.padding_left
	if (property == 1): value = style.padding_right
	if (property == 2): value = style.padding_top
	if (property == 3): value = style.padding_bottom
	return win_web_pixels(rt, value)

int win_web_descendant(js_runtime* rt, html_node* node, html_node* ancestor):
	while (node != 0):
		if (rt.remaining <= 0):
			js_runtime_fail(rt, 5, c"Geometry traversal budget")
			return 0
		rt.remaining = rt.remaining - 1
		if (node == ancestor): return 1
		node = node.parent
	return 0

# Snapshot bounding border rectangle in viewport CSS coordinates. For inline
# nodes use the union of their actual rendered runs; empty/detached nodes are
# zero rectangles. Transforms are not supported by the current layout engine.
js_value* win_web_rect(js_runtime* rt, win_page* page, html_node* node, win_web_viewport* viewport):
	float64 left = 0.0
	float64 top = 0.0
	float64 right = 0.0
	float64 bottom = 0.0
	int found = 0
	win_box* box = win_page_node_box(page, node)
	if (box != 0):
		left = cast(float64, box.x)
		top = cast(float64, box.y)
		right = left + cast(float64, box.width)
		bottom = top + cast(float64, box.height)
		found = 1
	else:
		for i in range(page.runs.length):
			if (rt.remaining <= 0):
				js_runtime_fail(rt, 5, c"Geometry traversal budget")
				return rt.undefined_value
			rt.remaining = rt.remaining - 1
			win_run* run = page.runs[i]
			if (win_web_descendant(rt, run.node, node)):
				float64 x = cast(float64, run.x)
				float64 y = cast(float64, run.y)
				float64 r = x + cast(float64, run.width)
				float64 b = y + cast(float64, run.height)
				if (found == 0 || x < left): left = x
				if (found == 0 || y < top): top = y
				if (found == 0 || r > right): right = r
				if (found == 0 || b > bottom): bottom = b
				found = 1
	if (found):
		left = left - viewport.scroll_x
		right = right - viewport.scroll_x
		top = top - viewport.scroll_y
		bottom = bottom - viewport.scroll_y
	js_value* rect = js_runtime_alloc(rt, 5)
	js_runtime_set(rt, rect, c"x", js_runtime_number(rt, left))
	js_runtime_set(rt, rect, c"y", js_runtime_number(rt, top))
	js_runtime_set(rt, rect, c"left", js_runtime_number(rt, left))
	js_runtime_set(rt, rect, c"top", js_runtime_number(rt, top))
	js_runtime_set(rt, rect, c"right", js_runtime_number(rt, right))
	js_runtime_set(rt, rect, c"bottom", js_runtime_number(rt, bottom))
	js_runtime_set(rt, rect, c"width", js_runtime_number(rt, right - left))
	js_runtime_set(rt, rect, c"height", js_runtime_number(rt, bottom - top))
	return rect

# Box sizing from actual layout. No synthetic scrollHeight/scrollTop: layout
# has no per-element scrollport. Unknown properties return 0 to the host.
js_value* win_web_dimension(js_runtime* rt, win_page* page, html_node* node, js_text* key):
	int width = js_runtime_key_is(key, c"offsetWidth") || js_runtime_key_is(key, c"clientWidth")
	int height = js_runtime_key_is(key, c"offsetHeight") || js_runtime_key_is(key, c"clientHeight")
	if (width == 0 && height == 0): return 0
	win_box* box = win_page_node_box(page, node)
	float32 value = 0.0
	if (box != 0):
		value = box.height
		if (width): value = box.width
		if (js_runtime_key_is(key, c"clientWidth") || js_runtime_key_is(key, c"clientHeight")):
			win_style style
			if (win_web_style(rt, page, node, &style) == 0): return rt.undefined_value
			value = value - 2.0 * style.border
	else if (js_runtime_key_is(key, c"offsetWidth") || js_runtime_key_is(key, c"offsetHeight")):
		win_web_viewport viewport
		viewport.scroll_x = 0.0
		viewport.scroll_y = 0.0
		js_value* rect = win_web_rect(rt, page, node, &viewport)
		if (rt.completion.status != 0): return rt.undefined_value
		char* dimension = c"height"
		if (width): dimension = c"width"
		value = cast(float32, js_runtime_get(rt, rect, dimension).number)
	if (value < 0.0): value = 0.0
	return js_runtime_number(rt, cast(float64, cast(int, value + 0.5)))
