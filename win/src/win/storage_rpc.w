# Synchronous child API over the existing connected WINT socket. The parent
# supplies the origin capability; requests cannot name an origin or disk path.
import win.storage_commit

const int WIN_STORAGE_REQUEST = 200
const int WIN_STORAGE_REPLY = 201
const int WIN_STORAGE_WIRE_LIMIT = 131120

struct win_storage_bridge:
	int generation
	int sequence
	int failed

void win_storage_wire_header(string_builder* data, int sequence, int kind):
	string_append(data, c"WINT0001")
	for i in range(16): string_append_char(data, 0)
	store_le32(data.data + 12, sequence)
	store_le32(data.data + 16, kind)
	store_le32(data.data + 20, 1)

win_storage_result* win_storage_bridge_call(void* context, int session, int operation, char* key, char* value, int index):
	win_storage_bridge* bridge = cast(win_storage_bridge*, context)
	win_storage_result* result = new win_storage_result()
	result.error = 3
	result.message = c"Storage parent connection failed"
	if (operation >= 3): key = c""
	if (operation != 1): value = c""
	int key_length = strlen(key)
	int value_length = strlen(value)
	if (bridge.failed || bridge.sequence >= 2147483646): return result
	if (key_length > 65536 || value_length > 65536):
		# Compact oversize marker preserves native get/remove miss semantics and
		# checks origin/owner availability before setItem's quota exception.
		index = -2
		key = c""
		value = c""
		key_length = 0
		value_length = 0
	bridge.sequence = bridge.sequence + 1
	string_builder* data = string_new()
	win_storage_wire_header(data, bridge.sequence, WIN_STORAGE_REQUEST)
	for i in range(24): string_append_char(data, 0)
	store_le32(data.data + 24, bridge.generation)
	store_le32(data.data + 28, session)
	store_le32(data.data + 32, operation)
	store_le32(data.data + 36, index)
	store_le32(data.data + 40, key_length)
	store_le32(data.data + 44, value_length)
	string_append_bytes(data, key, key_length)
	string_append_bytes(data, value, value_length)
	store_le32(data.data + 8, data.length - 24)
	int ok = win_storage_send_exact(0, data.data, data.length)
	string_free(data)
	char[44] header
	if (ok): ok = win_storage_read_exact(0, &header[0], 44)
	if (ok):
		for i in range(8):
			if (header[i] != c"WINT0001"[i]): ok = 0
		int length = load_le32(&header[40])
		int error = load_le32(&header[28])
		int kind = load_le32(&header[32])
		if (load_le32(&header[8]) != 20 + length || load_le32(&header[12]) != bridge.sequence || load_le32(&header[16]) != WIN_STORAGE_REPLY || load_le32(&header[20]) != 1 || load_le32(&header[24]) != bridge.generation || length < 0 || length > 65536 || error < 0 || error > 3 || (kind != 0 && kind != 1 && kind != 3 && kind != 4) || (kind != 4 && length != 0)): ok = 0
		if (ok):
			char* text = cast(char*, malloc(length + 1))
			text[length] = 0
			ok = win_storage_read_exact(0, text, length)
			if (ok && (strlen(text) != length || utf8_validate_bytes(text, length) == 0)): ok = 0
			if (ok):
				result.error = error
				result.kind = kind
				result.number = load_le32(&header[36])
				result.message = c"Parent storage operation failed"
				if (kind == 4): result.text = text
				else: free(text)
			else: free(text)
	if (ok == 0): bridge.failed = 1
	return result

# Validate all lengths/identities before copying strings or mutating any owner.
int win_storage_request_valid(char* data, int length, int generation, int next):
	if (length < 48 || length > WIN_STORAGE_WIRE_LIMIT): return 0
	for i in range(8):
		if (data[i] != c"WINT0001"[i]): return 0
	if (load_le32(data + 8) != length - 24 || load_le32(data + 12) != next || load_le32(data + 16) != WIN_STORAGE_REQUEST || load_le32(data + 20) != 1 || load_le32(data + 24) != generation): return 0
	int session = load_le32(data + 28)
	int operation = load_le32(data + 32)
	int index = load_int32(data + 36)
	int key = load_le32(data + 40)
	int value = load_le32(data + 44)
	if (session < 0 || session > 1 || operation < 0 || operation > 5 || index < -2 || index > 1024 || key < 0 || key > 65536 || value < 0 || value > 65536 || length != 48 + key + value): return 0
	if (index == -2 && (operation > 2 || key != 0 || value != 0)): return 0
	if (utf8_validate_bytes(data + 48, key) == 0 || utf8_validate_bytes(data + 48 + key, value) == 0): return 0
	for i in range(48, length):
		if (data[i] == 0): return 0
	return 1

string_builder* win_storage_reply(int generation, int sequence, win_storage_result* result):
	string_builder* data = string_new()
	win_storage_wire_header(data, sequence, WIN_STORAGE_REPLY)
	for i in range(20): string_append_char(data, 0)
	store_le32(data.data + 24, generation)
	store_le32(data.data + 28, result.error)
	store_le32(data.data + 32, result.kind)
	store_le32(data.data + 36, result.number)
	if (result.kind == 4 && result.text != 0):
		int length = strlen(result.text)
		store_le32(data.data + 40, length)
		string_append_bytes(data, result.text, length)
	store_le32(data.data + 8, data.length - 24)
	return data
