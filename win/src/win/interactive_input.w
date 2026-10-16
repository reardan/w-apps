# WINT revision 2 raw input. Validate the complete packet before any event.
# All fields are little-endian int32; no native struct layout crosses IPC.
import win.pointer
import structures.string

const int WIN_INPUT_PREFIX = 36
const int WIN_INPUT_RECORD = 20
const int WIN_INPUT_BATCHES = 8

struct win_interactive_input:
	int generation
	int document
	int width
	int height
	int mouse_x
	int mouse_y
	int mods
	win_native_input native

int win_interactive_coordinate(int value):
	return value >= -65536 && value <= 65536

int win_interactive_scalar(int value):
	return value >= 1 && value <= 1114111 && (value < 55296 || value > 57343)

int win_interactive_event_valid(gfx_event* event):
	if (event.mods < 0 || event.mods > 15 || win_interactive_coordinate(event.x) == 0 || win_interactive_coordinate(event.y) == 0): return 0
	int kind = event.kind
	int code = event.code
	if (kind == GFX_EVENT_KEY_DOWN || kind == GFX_EVENT_KEY_UP): return code >= 0 && code <= 65535
	if (kind == GFX_EVENT_CHAR): return win_interactive_scalar(code)
	if (kind == GFX_EVENT_NAV): return code >= GFX_NAV_LEFT && code <= GFX_NAV_DELETE
	if (kind == GFX_EVENT_MOUSE_DOWN || kind == GFX_EVENT_MOUSE_UP): return code >= 1 && code <= 3
	if (kind == GFX_EVENT_SCROLL): return code == -1 || code == 1
	if (kind == GFX_EVENT_SCROLL_PIXELS): return win_interactive_coordinate(code)
	if (kind == GFX_EVENT_POINTER_CANCEL): return code == 0
	if (kind == GFX_EVENT_PREEDIT_BEGIN): return code == 0 && event.x == 0 && event.y >= 0 && event.y <= 1024
	if (kind == GFX_EVENT_PREEDIT_TEXT): return code >= 32 && win_interactive_scalar(code) && event.x == 0
	if (kind == GFX_EVENT_PREEDIT_END): return code == 0 && event.x == 0
	return 0

int win_interactive_input_valid(win_interactive_input* input):
	if (input.generation < 1 || input.generation > 2147483647 || input.document < 1 || input.document > 2147483647): return 0
	if (input.width < 1 || input.width > 4096 || input.height < 1 || input.height > 4096): return 0
	if (input.mods < 0 || input.mods > 15 || win_interactive_coordinate(input.mouse_x) == 0 || win_interactive_coordinate(input.mouse_y) == 0): return 0
	if (input.native.overflow || input.native.count < 0 || input.native.count > 64): return 0
	for i in range(input.native.count):
		if (win_interactive_event_valid(&input.native.events[i]) == 0): return 0
	return 1

string_builder* win_interactive_input_encode(win_interactive_input* input):
	if (win_interactive_input_valid(input) == 0): return 0
	string_builder* result = string_new()
	for i in range(WIN_INPUT_PREFIX + input.native.count * WIN_INPUT_RECORD): string_append_char(result, 0)
	save_int32(result.data, input.generation)
	save_int32(result.data + 4, input.document)
	save_int32(result.data + 8, input.width)
	save_int32(result.data + 12, input.height)
	save_int32(result.data + 16, input.native.count)
	save_int32(result.data + 20, input.mouse_x)
	save_int32(result.data + 24, input.mouse_y)
	save_int32(result.data + 28, input.mods)
	# Offset 32 reserved zero for future flags.
	for i in range(input.native.count):
		gfx_event* event = &input.native.events[i]
		char* data = result.data + WIN_INPUT_PREFIX + i * WIN_INPUT_RECORD
		save_int32(data, event.kind)
		save_int32(data + 4, event.code)
		save_int32(data + 8, event.x)
		save_int32(data + 12, event.y)
		save_int32(data + 16, event.mods)
	return result

win_interactive_input* win_interactive_input_decode(char* data, int length, int generation, int document):
	if (length < WIN_INPUT_PREFIX || load_int32(data + 32) != 0): return 0
	int count = load_int32(data + 16)
	if (count < 0 || count > 64 || length != WIN_INPUT_PREFIX + count * WIN_INPUT_RECORD): return 0
	if (load_int32(data) != generation || load_int32(data + 4) != document): return 0
	win_interactive_input* input = new win_interactive_input()
	input.generation = generation
	input.document = document
	input.width = load_int32(data + 8)
	input.height = load_int32(data + 12)
	input.native.count = count
	input.mouse_x = load_int32(data + 20)
	input.mouse_y = load_int32(data + 24)
	input.mods = load_int32(data + 28)
	for i in range(count):
		char* record = data + WIN_INPUT_PREFIX + i * WIN_INPUT_RECORD
		gfx_event* event = &input.native.events[i]
		event.kind = load_int32(record)
		event.code = load_int32(record + 4)
		event.x = load_int32(record + 8)
		event.y = load_int32(record + 12)
		event.mods = load_int32(record + 16)
	if (win_interactive_input_valid(input)): return input
	free(input)
	return 0
