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
	float32 maximum
	float32 base_size
	float32 hypothetical
	float32 violation
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

# Content-box flex bases deliberately ignore min/max constraints and the
# zero floor (a small border-box basis can have a negative inner base).
float32 win_flex_length(win_style style, float32 value, int percent, float32 available):
	if (percent): value = available * value / 100.0
	if (style.box_sizing): value = value - win_box_horizontal_extras(style)
	return value

float32 win_flex_clamp(win_layout_item* item, float32 size):
	if (item.maximum >= 0.0 && size > item.maximum): size = item.maximum
	if (size < item.minimum): size = item.minimum
	if (size < 0.0): size = 0.0
	return size

# CSS Flexbox 1 section 9.7: choose grow/shrink using hypothetical sizes;
# distribute from original bases, clamp, then freeze only the violations
# matching the total violation. This keeps later passes proportional to the
# original scaled shrink factors, not the previous pass's intermediate sizes.
void win_flex_sizes(list[win_layout_item*] items, float32 available, float32 gap):
	float32 extras_total = 0.0
	if (items.length > 1): extras_total = gap * cast(float32, items.length - 1)
	float32 hypothetical_total = 0.0
	for i in range(items.length):
		win_layout_item* item = items[i]
		item.base_size = item.intrinsic.max_content
		item.minimum = item.intrinsic.min_content
		item.maximum = -1.0
		if (item.anonymous == 0):
			win_style style = item.style
			extras_total = extras_total + win_box_horizontal_extras(style) + style.margin_left + style.margin_right
			if (style.width >= 0.0):
				float32 preferred = win_flex_length(style, style.width, style.width_percent, available)
				if (item.minimum > preferred): item.minimum = preferred
				if (style.flex_basis == -1.0): item.base_size = preferred
			if (style.flex_basis >= 0.0): item.base_size = win_flex_length(style, style.flex_basis, style.flex_basis_percent, available)
			if (style.max_width >= 0.0):
				item.maximum = win_flex_length(style, style.max_width, style.max_width_percent, available)
				if (item.maximum < 0.0): item.maximum = 0.0
				if (item.minimum > item.maximum): item.minimum = item.maximum
		if (item.minimum < 0.0): item.minimum = 0.0
		item.hypothetical = win_flex_clamp(item, item.base_size)
		hypothetical_total = hypothetical_total + item.hypothetical
	int growing = hypothetical_total + extras_total < available
	float32 initial_free = available - extras_total
	for i in range(items.length):
		win_layout_item* item = items[i]
		float32 factor = item.style.flex_shrink
		if (growing): factor = item.style.flex_grow
		item.frozen = factor == 0.0 || growing && item.base_size > item.hypothetical || growing == 0 && item.base_size < item.hypothetical
		item.main_size = item.base_size
		if (item.frozen): item.main_size = item.hypothetical
		initial_free = initial_free - item.main_size
	for pass in range(items.length + 1):
		float32 remaining = available - extras_total
		float32 factors = 0.0
		float32 weights = 0.0
		float32 factor_max = 0.0
		int unfrozen = 0
		for i in range(items.length):
			win_layout_item* item = items[i]
			if (item.frozen): remaining = remaining - item.main_size
			else:
				unfrozen = unfrozen + 1
				remaining = remaining - item.base_size
				float32 factor = item.style.flex_shrink
				if (growing): factor = item.style.flex_grow
				factors = factors + factor
				if (factor > factor_max): factor_max = factor
		if (unfrozen == 0): break
		# Normalize factors before scaling by bases, preventing finite large
		# factors from overflowing their sums/products during allocation.
		for i in range(items.length):
			win_layout_item* item = items[i]
			if (item.frozen): continue
			float32 weight = item.style.flex_grow
			if (growing == 0): weight = item.style.flex_shrink
			if (factor_max > 0.0): weight = weight / factor_max
			if (growing == 0): weight = weight * item.base_size
			weights = weights + weight
		if (factors < 1.0 && fabs(initial_free * factors) < fabs(remaining)): remaining = initial_free * factors
		float32 total_violation = 0.0
		for i in range(items.length):
			win_layout_item* item = items[i]
			if (item.frozen): continue
			float32 size = item.base_size
			float32 weight = item.style.flex_grow
			if (growing == 0): weight = item.style.flex_shrink
			if (factor_max > 0.0): weight = weight / factor_max
			if (growing == 0): weight = weight * item.base_size
			if (weights > 0.0):
				if (growing): size = size + remaining * (weight / weights)
				else: size = size - fabs(remaining) * (weight / weights)
			item.main_size = win_flex_clamp(item, size)
			item.violation = item.main_size - size
			total_violation = total_violation + item.violation
		for i in range(items.length):
			win_layout_item* item = items[i]
			if (total_violation == 0.0 || total_violation > 0.0 && item.violation > 0.0 || total_violation < 0.0 && item.violation < 0.0): item.frozen = 1
