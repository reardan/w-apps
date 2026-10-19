# Bounded URL Standard form-urlencoded lists. Native state is realm-owned;
# prototypes and callbacks use the interpreter's ordinary traced values.
import win.web_host

struct win_search_pair:
	js_text* name
	js_text* value

struct win_search_context:
	js_runtime* runtime
	js_value* prototype
	list[void*] states
	int units

struct win_search_state:
	win_search_context* context
	js_value* object
	list[win_search_pair*] pairs
	int units

int win_search_charge(js_runtime* rt, int amount):
	if (rt.completion.status != 0): return 0
	if (amount > rt.remaining):
		js_runtime_fail(rt, 5, c"URLSearchParams execution limit")
		return 0
	rt.remaining = rt.remaining - amount
	rt.completion.steps = rt.completion.steps + amount
	return 1

# Marker only: ordinary properties, including the size accessor, stay on the
# prototype. No caller-controlled property can forge the native brand.
int win_search_brand(void* runtime, void* context, js_value* receiver, js_text* key):
	return 0

win_search_state* win_search_state_of(js_value* value):
	if (value == 0 || value.host_has != cast(int, win_search_brand)): return 0
	win_search_state* state = cast(win_search_state*, value.host_context)
	if (state.object != value): return 0
	return state

js_text* win_search_scalar(js_runtime* rt, js_text* text):
	if (text.units.length > 65536):
		js_runtime_fail(rt, 5, c"URLSearchParams string limit")
		return 0
	if (win_search_charge(rt, 1 + text.units.length) == 0): return 0
	int length = 0
	char* bytes = win_web_usv_bytes(text, &length)
	js_text* result = js_text_from_utf8(bytes, length)
	free(bytes)
	return result

js_text* win_search_text(js_runtime* rt, js_value* value):
	js_text* text = js_runtime_string_text(rt, value)
	if (text == 0): return 0
	js_text* result = win_search_scalar(rt, text)
	js_text_free(text)
	return result

void win_search_pair_free(win_search_pair* pair):
	js_text_free(pair.name)
	js_text_free(pair.value)
	free(pair)

int win_search_capacity(win_search_state* state, int units, int count):
	if (units > 65536 || count > 1024 || state.context.units - state.units + units > 524288):
		js_runtime_fail(state.context.runtime, 5, c"URLSearchParams storage limit")
		return 0
	return 1

void win_search_units(win_search_state* state, int units):
	state.context.units = state.context.units - state.units + units
	state.units = units

void win_search_append(win_search_state* state, js_text* name, js_text* value):
	int units = state.units + name.units.length + value.units.length
	if (win_search_capacity(state, units, state.pairs.length + 1) == 0): return
	if (win_search_charge(state.context.runtime, 1 + name.units.length + value.units.length) == 0): return
	win_search_pair* pair = new win_search_pair()
	pair.name = js_text_clone(name)
	pair.value = js_text_clone(value)
	state.pairs.push(pair)
	win_search_units(state, units)

void win_search_parse(win_search_state* state, js_text* text):
	js_runtime* rt = state.context.runtime
	int length = 0
	char* bytes = win_web_usv_bytes(text, &length)
	int first = 0
	if (length > 0 && bytes[0] == '?'): first = 1
	while (first < length && rt.completion.status == 0):
		int last = first
		while (last < length && bytes[last] != '&'): last = last + 1
		if (win_search_charge(rt, 1 + last - first) == 0): break
		if (last > first):
			int equal = first
			while (equal < last && bytes[equal] != '='): equal = equal + 1
			int start = equal
			if (equal < last): start = start + 1
			js_text* name = win_web_decode(bytes, first, equal)
			js_text* value = win_web_decode(bytes, start, last)
			win_search_append(state, name, value)
			js_text_free(name)
			js_text_free(value)
		first = last + 1
	free(bytes)

void win_search_encode(js_runtime* rt, string_builder* output, js_text* text):
	int length = 0
	char* bytes = win_web_usv_bytes(text, &length)
	char* hex = c"0123456789ABCDEF"
	for i in range(length):
		int c = bytes[i] & 255
		int plain = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '*' || c == '-' || c == '.' || c == '_'
		int cost = 3
		if (plain || c == ' '): cost = 1
		if (output.length + cost > 65536):
			js_runtime_fail(rt, 5, c"URLSearchParams serialization limit")
			break
		if (win_search_charge(rt, cost) == 0): break
		if (plain): string_append_char(output, c)
		else if (c == ' '): string_append_char(output, '+')
		else:
			string_append_char(output, '%')
			string_append_char(output, hex[c / 16])
			string_append_char(output, hex[c % 16])
	free(bytes)

js_value* win_search_serialize(win_search_state* state):
	js_runtime* rt = state.context.runtime
	string_builder* output = string_new()
	for i in range(state.pairs.length):
		if (win_search_charge(rt, 2) == 0): break
		if (i > 0): string_append_char(output, '&')
		win_search_encode(rt, output, state.pairs[i].name)
		string_append_char(output, '=')
		win_search_encode(rt, output, state.pairs[i].value)
		if (output.length > 65536): js_runtime_fail(rt, 5, c"URLSearchParams serialization limit")
		if (rt.completion.status != 0): break
	js_value* result = rt.undefined_value
	if (rt.completion.status == 0): result = win_web_string(rt, output.data)
	string_free(output)
	return result

int win_search_less(js_runtime* rt, js_text* a, js_text* b):
	int length = a.units.length
	if (b.units.length < length): length = b.units.length
	for i in range(length):
		if (win_search_charge(rt, 1) == 0): return 0
		if (a.units[i] != b.units[i]): return a.units[i] < b.units[i]
	return a.units.length < b.units.length

void win_search_sort(win_search_state* state):
	js_runtime* rt = state.context.runtime
	list[win_search_pair*] sorted = new list[win_search_pair*]
	for i in range(state.pairs.length):
		if (win_search_charge(rt, 1) == 0): break
		win_search_pair* pair = state.pairs[i]
		int position = sorted.length
		sorted.push(pair)
		while (position > 0):
			if (win_search_charge(rt, 1) == 0 || win_search_less(rt, pair.name, sorted[position - 1].name) == 0): break
			sorted[position] = sorted[position - 1]
			position = position - 1
		sorted[position] = pair
	if (rt.completion.status == 0):
		for i in range(sorted.length): state.pairs[i] = sorted[i]
	__w_list_free(cast(__w_list*, sorted))

void win_search_each(win_search_state* state, list[js_value*] args):
	js_runtime* rt = state.context.runtime
	if (args.length == 0 || js_runtime_callable(args[0]) == 0):
		js_runtime_fail(rt, 2, c"URLSearchParams.forEach requires a callback")
		return
	js_value* this_value = rt.undefined_value
	if (args.length > 1): this_value = args[1]
	list[js_value*] values = new list[js_value*]
	values.push(rt.undefined_value)
	values.push(rt.undefined_value)
	values.push(state.object)
	int i = 0
	while (i < state.pairs.length && rt.completion.status == 0):
		win_search_pair* pair = state.pairs[i]
		if (win_search_charge(rt, 1 + pair.name.units.length + pair.value.units.length) == 0): break
		# Copy both strings before calling JS; callbacks can delete this pair.
		values[0] = js_runtime_string(rt, pair.value)
		values[1] = js_runtime_string(rt, pair.name)
		if (rt.completion.status != 0): break
		js_runtime_call_receiver(rt, args[0], this_value, values)
		i = i + 1
	__w_list_free(cast(__w_list*, values))

# Operations: get/getAll/has/append/set/delete/toString/sort/forEach/size.
js_value* win_search_method_body(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_search_state* state = win_search_state_of(receiver)
	if (state == 0):
		js_runtime_fail(rt, 2, c"Illegal URLSearchParams receiver")
		return rt.undefined_value
	int operation = cast(int, context)
	if (operation == 10): return js_runtime_number(rt, cast(float64, state.pairs.length))
	if (operation == 7): return win_search_serialize(state)
	if (operation == 8):
		win_search_sort(state)
		return rt.undefined_value
	if (operation == 9):
		win_search_each(state, args)
		return rt.undefined_value
	int required = 1
	if (operation == 4 || operation == 5): required = 2
	if (args.length < required):
		js_runtime_fail(rt, 2, c"URLSearchParams missing argument")
		return rt.undefined_value
	js_text* name = win_search_text(rt, args[0])
	js_text* value = 0
	int filter = (operation == 3 || operation == 6) && args.length > 1 && args[1].kind != 0
	if (name != 0 && (required == 2 || filter)): value = win_search_text(rt, args[1])
	js_value* result = rt.undefined_value
	if (rt.completion.status == 0 && operation == 4): win_search_append(state, name, value)
	else if (rt.completion.status == 0):
		list[int] matches = new list[int]
		int removed_units = 0
		for i in range(state.pairs.length):
			win_search_pair* pair = state.pairs[i]
			int cost = 1 + pair.name.units.length
			if (filter): cost = cost + pair.value.units.length
			if (win_search_charge(rt, cost) == 0): break
			if (js_text_equal(pair.name, name) && (filter == 0 || js_text_equal(pair.value, value))):
				matches.push(i)
				removed_units = removed_units + pair.name.units.length + pair.value.units.length
		if (rt.completion.status == 0):
			if (operation == 1):
				result = js_runtime_alloc(rt, 1)
				if (matches.length > 0): result = js_runtime_string(rt, state.pairs[matches[0]].value)
			else if (operation == 2):
				result = js_runtime_alloc(rt, 6)
				for i in range(matches.length):
					js_text* text = state.pairs[matches[i]].value
					if (win_search_charge(rt, 1 + text.units.length) == 0): break
					js_runtime_array_append(rt, result, js_runtime_string(rt, text))
			else if (operation == 3): result = js_runtime_boolean(rt, matches.length > 0)
			else if (operation == 5 && matches.length == 0): win_search_append(state, name, value)
			else if (matches.length > 0):
				int units = state.units - removed_units
				if (operation == 5): units = units + name.units.length + value.units.length
				if (win_search_capacity(state, units, state.pairs.length) && win_search_charge(rt, 1 + units)):
					int count = 0
					int match = 0
					for i in range(state.pairs.length):
						win_search_pair* pair = state.pairs[i]
						if (match < matches.length && matches[match] == i):
							match = match + 1
							if (operation == 5 && match == 1):
								js_text_free(pair.value)
								pair.value = js_text_clone(value)
							else:
								win_search_pair_free(pair)
								continue
						state.pairs[count] = pair
						count = count + 1
					while (state.pairs.length > count): state.pairs.pop()
					win_search_units(state, units)
		__w_list_free(cast(__w_list*, matches))
	js_text_free(name)
	js_text_free(value)
	return result

js_value* win_search_method(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	if (js_function_enter(rt) == 0): return rt.undefined_value
	js_value* result = win_search_method_body(runtime, context, receiver, args)
	rt.depth = rt.depth - 1
	return result

void win_search_initialize(win_search_state* state, js_value* initial):
	js_runtime* rt = state.context.runtime
	if (initial.kind == 0): return
	win_search_state* source = win_search_state_of(initial)
	if (source != 0):
		for i in range(source.pairs.length):
			win_search_append(state, source.pairs[i].name, source.pairs[i].value)
			if (rt.completion.status != 0): break
	else if (initial.kind == 6):
		int i = 0
		while (i < initial.array_length):
			if (win_search_charge(rt, 1) == 0): break
			js_value* pair = js_runtime_index_get(rt, initial, i)
			if (rt.completion.status != 0): break
			if (pair.kind != 6):
				js_runtime_fail(rt, 2, c"URLSearchParams requires two-item pairs")
				break
			# Array iterators observe length changes during USVString conversion.
			list[js_text*] items = new list[js_text*]
			int j = 0
			while (j < pair.array_length):
				js_text* item = win_search_text(rt, js_runtime_index_get(rt, pair, j))
				if (item == 0): break
				if (j < 2): items.push(item)
				else: js_text_free(item)
				j = j + 1
			if (rt.completion.status == 0):
				if (j != 2): js_runtime_fail(rt, 2, c"URLSearchParams requires two-item pairs")
				else: win_search_append(state, items[0], items[1])
			js_for_in_keys_free(items)
			i = i + 1
			if (rt.completion.status != 0): break
	else if (js_runtime_object(initial)):
		if (initial.kind != 5 || initial.host_get != 0 || initial.host_set != 0 || initial.host_has != 0 || initial.binary_kind != 0 || initial.regexp != 0 || initial.reactions != 0):
			js_runtime_fail(rt, 6, c"URLSearchParams initializer outside plain record subset")
			return
		list[js_text*] keys = new list[js_text*]
		for i in range(initial.properties.length):
			js_for_in_key(rt, keys, initial.properties[i].key)
			if (rt.completion.status != 0): break
		for i in range(keys.length):
			if (rt.completion.status != 0): break
			js_value* property = js_runtime_property(initial, keys[i])
			if (property == 0 || property.enumerable == 0): continue
			js_text* name = win_search_scalar(rt, keys[i])
			js_text* value = 0
			if (name != 0): value = win_search_text(rt, js_runtime_member_read(rt, initial, keys[i]))
			if (value != 0):
				# Record conversion can collapse distinct surrogate keys to the
				# same USVString. Last value wins without moving the first key.
				int found = -1
				for j in range(state.pairs.length):
					if (win_search_charge(rt, 1 + state.pairs[j].name.units.length) == 0): break
					if (js_text_equal(state.pairs[j].name, name)): found = j
				if (rt.completion.status == 0):
					if (found < 0): win_search_append(state, name, value)
					else:
						win_search_pair* pair = state.pairs[found]
						int units = state.units - pair.value.units.length + value.units.length
						if (win_search_capacity(state, units, state.pairs.length)):
							js_text_free(pair.value)
							pair.value = js_text_clone(value)
							win_search_units(state, units)
			js_text_free(name)
			js_text_free(value)
		js_for_in_keys_free(keys)
	else:
		js_text* text = win_search_text(rt, initial)
		if (text != 0): win_search_parse(state, text)
		js_text_free(text)

void win_search_state_free(win_search_state* state):
	for i in range(state.pairs.length): win_search_pair_free(state.pairs[i])
	__w_list_free(cast(__w_list*, state.pairs))
	win_search_units(state, 0)
	js_runtime_unroot(state.context.runtime, state.object)
	free(state)

js_value* win_search_construct(void* runtime, void* context, js_value* receiver, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, runtime)
	win_search_context* owner = cast(win_search_context*, context)
	if (owner.states.length >= 256):
		js_runtime_fail(rt, 5, c"URLSearchParams realm limit")
		return rt.undefined_value
	win_search_state* state = new win_search_state()
	state.context = owner
	state.pairs = new list[win_search_pair*]
	state.object = js_runtime_alloc(rt, 5)
	js_runtime_root(rt, state.object)
	if (args.length > 0 && rt.completion.status == 0): win_search_initialize(state, args[0])
	# Initializer coercion can reenter the constructor.
	if (owner.states.length >= 256): js_runtime_fail(rt, 5, c"URLSearchParams realm limit")
	if (rt.completion.status != 0):
		win_search_state_free(state)
		return rt.undefined_value
	state.object.prototype = owner.prototype
	state.object.host_context = state
	js_runtime_set_host_has(rt, state.object, win_search_brand)
	owner.states.push(state)
	return state.object

win_search_context* win_search_new(js_runtime* rt, js_value* window):
	win_search_context* context = new win_search_context()
	context.runtime = rt
	context.states = new list[void*]
	context.prototype = js_runtime_alloc(rt, 5)
	js_runtime_root(rt, context.prototype)
	js_value* constructor = js_runtime_host_callable(rt, context, win_search_construct)
	constructor.host_construct = 2
	js_runtime_set(rt, constructor, c"prototype", context.prototype)
	js_runtime_set(rt, context.prototype, c"constructor", constructor)
	js_runtime_set(rt, rt.global, c"URLSearchParams", constructor)
	js_runtime_set(rt, window, c"URLSearchParams", constructor)
	char*[9] names
	names[0] = c"get"
	names[1] = c"getAll"
	names[2] = c"has"
	names[3] = c"append"
	names[4] = c"set"
	names[5] = c"delete"
	names[6] = c"toString"
	names[7] = c"sort"
	names[8] = c"forEach"
	for i in range(9): js_runtime_collection_method(rt, context.prototype, names[i], i + 1, win_search_method)
	js_text* size = js_runtime_key(c"size")
	js_runtime_define_accessor(rt, context.prototype, size, js_runtime_host_callable(rt, cast(void*, 10), win_search_method), 0, 1, 1)
	js_text_free(size)
	return context

void win_search_free(win_search_context* context):
	if (context == 0): return
	for i in range(context.states.length): win_search_state_free(cast(win_search_state*, context.states[i]))
	__w_list_free(cast(__w_list*, context.states))
	js_runtime_unroot(context.runtime, context.prototype)
	free(context)
