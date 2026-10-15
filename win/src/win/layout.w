# Formatting items and intrinsic dimensions are independent of the DOM walk.
import win.style

struct win_intrinsic_size:
	float32 min_content
	float32 max_content

struct win_layout_item:
	html_node* first
	html_node* end
	int anonymous
	win_style style
	win_intrinsic_size intrinsic
	float32 main_size
	float32 minimum
	int frozen

float32 win_box_horizontal_extras(win_style style):
	return style.padding_left + style.padding_right + style.border * 2.0

float32 win_box_vertical_extras(win_style style):
	return style.padding_top + style.padding_bottom + style.border * 2.0

float32 win_box_border_width(win_style style, float32 containing_width):
	float32 extras = win_box_horizontal_extras(style)
	float32 width = containing_width - style.margin_left - style.margin_right
	if (style.width >= 0.0):
		width = style.width
		if (style.width_percent): width = containing_width * width / 100.0
		if (style.box_sizing == 0): width = width + extras
	if (style.max_width >= 0.0):
		float32 maximum = style.max_width
		if (style.max_width_percent): maximum = containing_width * maximum / 100.0
		if (style.box_sizing == 0): maximum = maximum + extras
		if (width > maximum): width = maximum
	if (width < extras): width = extras
	return width

float32 win_box_content_height(win_style style):
	float32 height = style.height
	if (height >= 0.0 && style.box_sizing): height = height - win_box_vertical_extras(style)
	if (height < 0.0): height = 0.0
	return height

int win_style_strike(win_style style):
	int face = UI_FACE_REGULAR
	if (style.bold): face = UI_FACE_BOLD
	int size = cast(int, style.size)
	if (size < 4): size = 4
	if (size > 200): size = 200
	return ui_font_strike(face, size)

win_intrinsic_size win_intrinsic_text(char* text, int length, win_style style):
	win_intrinsic_size result
	result.min_content = 0.0
	result.max_content = 0.0
	int strike = win_style_strike(style)
	int pos = 0
	int words = 0
	while (pos < length):
		while (pos < length && html_space(text[pos])): pos = pos + 1
		int start = pos
		while (pos < length && html_space(text[pos]) == 0): pos = pos + 1
		if (pos == start): break
		char* word = substring(text, start, pos)
		float32 width = cast(float32, ui_text_width_styled(word, strike, style.flags))
		free(word)
		if (width > result.min_content): result.min_content = width
		if (words): result.max_content = result.max_content + cast(float32, ui_text_width_styled(c" ", strike, style.flags))
		result.max_content = result.max_content + width
		words = words + 1
	if (style.pre): result.min_content = result.max_content
	return result

# Initial flex values: grow=0, shrink=1, basis=auto, min-width=auto.
# Resolve weighted shrinking with repeated freezing at content minimums.
# No wrapping, alignment or explicitly declared flex factors in this slice.
void win_flex_sizes(list[win_layout_item*] items, float32 available, float32 gap):
	float32 total = 0.0
	if (items.length > 1): total = gap * cast(float32, items.length - 1)
	for i in range(items.length):
		win_layout_item* item = items[i]
		float32 extras = 0.0
		float32 margins = 0.0
		if (item.anonymous == 0):
			extras = win_box_horizontal_extras(item.style)
			margins = item.style.margin_left + item.style.margin_right
		item.main_size = item.intrinsic.max_content
		item.minimum = item.intrinsic.min_content
		if (item.anonymous == 0 && item.style.width >= 0.0):
			float32 preferred = win_box_border_width(item.style, available) - extras
			item.main_size = preferred
			if (item.minimum > preferred): item.minimum = preferred
		if (item.anonymous == 0 && item.style.max_width >= 0.0):
			win_style max_style = item.style
			max_style.width = item.style.max_width
			max_style.width_percent = item.style.max_width_percent
			float32 maximum = win_box_border_width(max_style, available) - extras
			if (item.main_size > maximum): item.main_size = maximum
			if (item.minimum > maximum): item.minimum = maximum
		item.frozen = 0
		total = total + item.main_size + extras + margins
	float32 deficit = total - available
	if (deficit <= 0.0): return
	for pass in range(items.length + 1):
		float32 weight = 0.0
		for i in range(items.length):
			if (items[i].frozen == 0): weight = weight + items[i].main_size
		if (weight <= 0.0 || deficit <= 0.001): break
		float32 consumed = 0.0
		int froze = 0
		for i in range(items.length):
			win_layout_item* item = items[i]
			if (item.frozen): continue
			float32 reduction = deficit * item.main_size / weight
			if (item.main_size - reduction < item.minimum):
				reduction = item.main_size - item.minimum
				item.frozen = 1
				froze = 1
			item.main_size = item.main_size - reduction
			consumed = consumed + reduction
		deficit = deficit - consumed
		if (froze == 0): break
