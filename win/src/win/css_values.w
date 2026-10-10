# Validated numeric values keep their units until computed-value resolution.
import libs.extras.css.css
import lib.format
import lib.fmath

struct win_css_numeric:
	# 0 invalid; 1 unitless number; 2 px; 3 em; 4 rem; 5 percentage; 6 fr.
	int unit
	float32 value

win_css_numeric win_css_number(css_token* token):
	win_css_numeric result
	result.unit = 0
	result.value = 0.0
	if (token.number_length <= 0): return result
	# Parse only the numeric source portion. An escaped unit must never turn
	# into an exponent after CSS escape decoding (for example 1\\65 2px).
	char* number = substring(token.value, 0, token.number_length)
	int consumed = 0
	float32 value = parse_float(number, &consumed)
	free(number)
	if (consumed != token.number_length || (float_bits(value) & 0x7f800000) == 0x7f800000): return result
	result.value = value
	if (css_kind(token, c"number")): result.unit = 1
	else if (css_kind(token, c"percentage")): result.unit = 5
	else if (css_kind(token, c"dimension")):
		char* unit = token.value + token.number_length
		if (css_ascii_equal(unit, c"px")): result.unit = 2
		if (css_ascii_equal(unit, c"em")): result.unit = 3
		if (css_ascii_equal(unit, c"rem")): result.unit = 4
		if (css_ascii_equal(unit, c"fr")): result.unit = 6
	return result

int win_css_is_length(win_css_numeric number):
	return number.unit >= 2 && number.unit <= 4 || number.unit == 1 && number.value == 0.0

float32 win_css_resolve_length(win_css_numeric number, float32 size, float32 root_size):
	if (number.unit == 3): return number.value * cast(float32, size)
	if (number.unit == 4): return number.value * cast(float32, root_size)
	return number.value

# Wide keywords are stored explicitly, never confused with normal identifiers.
int win_css_wide(css_token* token):
	if (css_kind(token, c"ident") == 0): return 0
	if (css_ascii_equal(token.value, c"inherit")): return 1
	if (css_ascii_equal(token.value, c"initial")): return 2
	if (css_ascii_equal(token.value, c"unset")): return 3
	return 0
