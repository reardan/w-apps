# Finite CSS calc arithmetic. Keep percentages and relative units symbolic
# until the property supplies font, viewport and containing-block dimensions.
# Products/divisors require a number; dimensional cancellation is not supported.
struct win_css_math:
	# 0 invalid, 1 number, 2 length, 4 percentage, 6 length-percentage.
	int kind
	float32[11] terms

struct win_css_math_parser:
	css_document* css
	int pos
	int last
	int depth

win_css_math win_css_math_zero():
	win_css_math result
	result.kind = 0
	for i in range(11): result.terms[i] = 0.0
	return result

int win_css_math_finite(win_css_math value):
	for i in range(11):
		if ((float_bits(value.terms[i]) & 0x7f800000) == 0x7f800000): return 0
	return 1

win_css_math win_css_math_scale(win_css_math value, float32 factor):
	for i in range(11): value.terms[i] = value.terms[i] * factor
	if (win_css_math_finite(value) == 0): value.kind = 0
	return value

win_css_math win_css_math_sum(win_css_math_parser* parser);

win_css_math win_css_math_atom(win_css_math_parser* parser):
	win_css_math result = win_css_math_zero()
	css_document* css = parser.css
	parser.pos = css_skip(css, parser.pos, parser.last)
	if (parser.pos >= parser.last || parser.depth >= 64): return result
	int pos = parser.pos
	css_token* token = css.tokens[pos]
	int open = pos
	if (css_kind(token, c"ident") && css_ascii_equal(token.value, c"calc")):
		open = pos + 1
		if (open >= parser.last || token.end != css.tokens[open].start): return result
	if (open < parser.last && css_delim(css.tokens[open], '(')):
		int close = css.tokens[open].match
		if (close < open || close >= parser.last): return result
		win_css_math_parser nested
		nested.css = css
		nested.pos = open + 1
		nested.last = close
		nested.depth = parser.depth + 1
		result = win_css_math_sum(&nested)
		if (css_skip(css, nested.pos, close) != close): result.kind = 0
		parser.pos = close + 1
		return result
	win_css_numeric number = win_css_number(token)
	if (number.unit == 0 || number.unit == 6): return result
	result.kind = 2
	if (number.unit == 1): result.kind = 1
	if (number.unit == 5): result.kind = 4
	result.terms[number.unit] = number.value
	parser.pos = pos + 1
	return result

win_css_math win_css_math_product(win_css_math_parser* parser):
	win_css_math result = win_css_math_atom(parser)
	css_document* css = parser.css
	while (result.kind != 0):
		int pos = css_skip(css, parser.pos, parser.last)
		if (pos >= parser.last): break
		int divide = css_delim(css.tokens[pos], '/')
		if (divide == 0 && css_delim(css.tokens[pos], '*') == 0): break
		parser.pos = pos + 1
		win_css_math right = win_css_math_atom(parser)
		if (right.kind == 0): return right
		if (divide):
			if (right.kind != 1 || right.terms[1] == 0.0): return win_css_math_zero()
			result = win_css_math_scale(result, 1.0 / right.terms[1])
		else if (right.kind == 1): result = win_css_math_scale(result, right.terms[1])
		else if (result.kind == 1): result = win_css_math_scale(right, result.terms[1])
		else: return win_css_math_zero()
	return result

win_css_math win_css_math_sum(win_css_math_parser* parser):
	win_css_math result = win_css_math_product(parser)
	css_document* css = parser.css
	while (result.kind != 0):
		int pos = css_skip(css, parser.pos, parser.last)
		if (pos >= parser.last): break
		int subtract = css_delim(css.tokens[pos], '-')
		if (subtract == 0 && css_delim(css.tokens[pos], '+') == 0): break
		# Binary +/- require whitespace on both sides (comments alone do not).
		int before_space = 0
		int after_space = 0
		for i in range(parser.pos, pos):
			if (css_kind(css.tokens[i], c"space")): before_space = 1
		int after = css_skip(css, pos + 1, parser.last)
		for i in range(pos + 1, after):
			if (css_kind(css.tokens[i], c"space")): after_space = 1
		if (before_space == 0 || after_space == 0): return win_css_math_zero()
		parser.pos = pos + 1
		win_css_math right = win_css_math_product(parser)
		if (right.kind == 0 || (result.kind == 1) != (right.kind == 1)): return win_css_math_zero()
		if (subtract): right = win_css_math_scale(right, -1.0)
		result.kind = result.kind | right.kind
		for i in range(11): result.terms[i] = result.terms[i] + right.terms[i]
		if (win_css_math_finite(result) == 0): return win_css_math_zero()
	return result

int win_css_calc(css_document* css, int first, int last):
	return first + 1 < last && css_kind(css.tokens[first], c"ident") && css_ascii_equal(css.tokens[first].value, c"calc") && css_delim(css.tokens[first + 1], '(') && css.tokens[first].end == css.tokens[first + 1].start

win_css_math win_css_math_parse(css_document* css, int first, int last):
	win_css_math_parser parser
	parser.css = css
	parser.pos = first
	parser.last = last
	parser.depth = 0
	win_css_math result = win_css_math_atom(&parser)
	if (css_skip(css, parser.pos, last) != last): result.kind = 0
	return result

float32 win_css_bound_length(float64 value):
	if (value > 1000000.0): return 1000000.0
	if (value < -1000000.0): return -1000000.0
	return cast(float32, value)

float32 win_css_math_pixels(win_css_math value, float32 size, float32 root_size, float32 width, float32 height):
	float32 smaller = width
	float32 larger = height
	if (height < width):
		smaller = height
		larger = width
	# Wider intermediates allow large finite relative terms to cancel before
	# the engine's used-length bound, without infinity-minus-infinity NaNs.
	float64 result = cast(float64, value.terms[2]) + cast(float64, value.terms[3]) * cast(float64, size) + cast(float64, value.terms[4]) * cast(float64, root_size)
	result = result + (cast(float64, value.terms[7]) * cast(float64, width) + cast(float64, value.terms[8]) * cast(float64, height) + cast(float64, value.terms[9]) * cast(float64, smaller) + cast(float64, value.terms[10]) * cast(float64, larger)) / 100.0
	return win_css_bound_length(result)

int win_css_component_end(css_document* css, int first, int last):
	if (first + 1 < last && css_kind(css.tokens[first], c"ident") && css_delim(css.tokens[first + 1], '(') && css.tokens[first].end == css.tokens[first + 1].start): return css_next_component(css, first + 1, last)
	return first + 1
