# Supported EventHandler IDL names share dispatch with addEventListener.
import win.events

const int WIN_EVENT_HANDLER_COUNT = 30

char* win_event_handler_property(int index):
	if (index == 0): return c"onclick"
	if (index == 1): return c"oninput"
	if (index == 2): return c"onbeforeinput"
	if (index == 3): return c"onchange"
	if (index == 4): return c"onsubmit"
	if (index == 5): return c"onreset"
	if (index == 6): return c"onfocus"
	if (index == 7): return c"onblur"
	if (index == 8): return c"onfocusin"
	if (index == 9): return c"onfocusout"
	if (index == 10): return c"onkeydown"
	if (index == 11): return c"onkeyup"
	if (index == 12): return c"oncompositionstart"
	if (index == 13): return c"oncompositionupdate"
	if (index == 14): return c"oncompositionend"
	if (index == 15): return c"onpointerdown"
	if (index == 16): return c"onpointermove"
	if (index == 17): return c"onpointerup"
	if (index == 18): return c"onpointercancel"
	if (index == 19): return c"ongotpointercapture"
	if (index == 20): return c"onlostpointercapture"
	if (index == 21): return c"onwheel"
	if (index == 22): return c"onload"
	if (index == 23): return c"onerror"
	if (index == 24): return c"onabort"
	if (index == 25): return c"onresize"
	if (index == 26): return c"onpopstate"
	if (index == 27): return c"onvisibilitychange"
	if (index == 28): return c"onselect"
	return c"onselectionchange"

int win_event_handler_index(js_text* key):
	for i in range(WIN_EVENT_HANDLER_COUNT):
		if (js_runtime_key_is(key, win_event_handler_property(i))): return i
	return -1

int win_event_handler_attribute(char* name):
	for i in range(WIN_EVENT_HANDLER_COUNT):
		if (strcmp(name, win_event_handler_property(i)) == 0): return i
	return -1
