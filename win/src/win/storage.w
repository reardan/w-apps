# Explicitly owned origin buckets. Shared local owner lives with the app;
# session owner lives with a tab. Disk persistence is explicitly configured.
import libs.standard.web.urlparse
import libs.extras.javascript.runtime
import lib.fs
import lib.bytes

struct win_storage_entry:
	char* origin
	char* key
	char* value

type win_storage_cancel_fn = fn(void*) -> void

struct win_storage_context:
	list[win_storage_entry*] entries
	int bytes
	char* path
	int lock
	void* pending
	win_storage_cancel_fn* cancel_pending
	int poisoned

struct win_storage_result:
	int kind               # JS primitive kinds: undefined0, null1, number3, string4
	int number
	char* text              # owned when kind4
	int error              # SecurityError1, QuotaExceededError2, UnknownError3
	char* message          # borrowed diagnostic

type win_storage_call_fn = fn(void*, int, int, char*, char*, int) -> win_storage_result*

void win_storage_result_free(win_storage_result* result):
	if (result == 0): return
	free(result.text)
	free(result)

win_storage_context* win_storage_new():
	win_storage_context* store = new win_storage_context()
	store.entries = new list[win_storage_entry*]
	store.lock = -1
	return store

void win_storage_remove(win_storage_context* store, int index):
	win_storage_entry* entry = store.entries[index]
	store.bytes = store.bytes - strlen(entry.origin) - strlen(entry.key) - strlen(entry.value)
	free(entry.origin)
	free(entry.key)
	free(entry.value)
	free(entry)
	for i in range(store.entries.length - index - 1): store.entries[index + i] = store.entries[index + i + 1]
	store.entries.pop()

void win_storage_free(win_storage_context* store):
	if (store == 0): return
	if (store.pending != 0 && store.cancel_pending != 0): store.cancel_pending(store.pending)
	while (store.entries.length > 0): win_storage_remove(store, store.entries.length - 1)
	__w_list_free(cast(__w_list*, store.entries))
	if (store.lock >= 0):
		io_result result
		fs_lock_release(store.lock, &result)
	free(store.path)
	free(store)

char* win_storage_origin(char* address):
	URL* url = url_parse(address)
	if (url == 0): return strclone(c"")
	string_builder* key = string_from(url.scheme)
	string_append(key, c"://")
	string_append(key, url.host)
	string_append_char(key, ':')
	char* port = itoa(url.port)
	string_append(key, port)
	free(port)
	url_free(url)
	char* result = key.data
	free(key)
	return result

# Versioned binary records preserve byte boundaries independently of delimiters.
# All fields still obey the existing bounded UTF-8 storage-string contract.
string_builder* win_storage_encode(win_storage_context* store):
	string_builder* data = string_from(c"WINLS001")
	char[4] word
	store_le32(&word[0], store.entries.length)
	string_append_bytes(data, &word[0], 4)
	for win_storage_entry* entry in store.entries:
		char*[3] fields
		fields[0] = entry.origin
		fields[1] = entry.key
		fields[2] = entry.value
		for i in range(3):
			int length = strlen(fields[i])
			store_le32(&word[0], length)
			string_append_bytes(data, &word[0], 4)
			string_append_bytes(data, fields[i], length)
	return data

# Parse into an independent owner; malformed/oversized data cannot mutate live
# storage or leave partly restored origins. Duplicate origin/key pairs fail.
win_storage_context* win_storage_decode(char* data, int length):
	if (length < 12 || length > 1060876): return 0
	for i in range(8):
		if (data[i] != c"WINLS001"[i]): return 0
	int count = load_le32(data + 8)
	if (count < 0 || count > 1024): return 0
	win_storage_context* store = win_storage_new()
	int pos = 12
	int valid = 1
	for record in range(count):
		char*[3] fields
		for i in range(3): fields[i] = 0
		for i in range(3):
			if (length - pos < 4):
				valid = 0
				break
			int size = load_le32(data + pos)
			pos = pos + 4
			if (size < 0 || size > 65536 || size > length - pos || store.bytes > 1048576 - size):
				valid = 0
				break
			fields[i] = str_copy_range(data, pos, pos + size)
			pos = pos + size
			store.bytes = store.bytes + size
			if (strlen(fields[i]) != size || utf8_validate_bytes(fields[i], size) == 0): valid = 0
		if (valid):
			char* canonical = win_storage_origin(fields[0])
			if (canonical[0] == 0 || strcmp(canonical, fields[0]) != 0): valid = 0
			free(canonical)
			for win_storage_entry* other in store.entries:
				if (strcmp(other.origin, fields[0]) == 0 && strcmp(other.key, fields[1]) == 0): valid = 0
		if (valid == 0):
			for i in range(3): free(fields[i])
			break
		win_storage_entry* entry = new win_storage_entry()
		entry.origin = fields[0]
		entry.key = fields[1]
		entry.value = fields[2]
		store.entries.push(entry)
	if (valid == 0 || pos != length):
		win_storage_free(store)
		return 0
	return store

void win_storage_swap(win_storage_context* left, win_storage_context* right):
	list[win_storage_entry*] entries = left.entries
	int bytes = left.bytes
	left.entries = right.entries
	left.bytes = right.bytes
	right.entries = entries
	right.bytes = bytes

win_storage_context* win_storage_snapshot(win_storage_context* store):
	if (store.path == 0): return 0
	string_builder* data = win_storage_encode(store)
	win_storage_context* copy = win_storage_decode(data.data, data.length)
	string_free(data)
	return copy

# 1: durable; 0: old file unchanged; -1: published, directory barrier failed.
# Preserve the distinction so a caller never rolls memory back after publication.
int win_storage_commit(win_storage_context* store):
	if (store.path == 0): return 1
	string_builder* data = win_storage_encode(store)
	fs_replace_report report
	int status = fs_replace_durable_mode(store.path, data.data, data.length, 384, &report)
	string_free(data)
	if (status == IO_OK): return 1
	if (report.renamed): return -1
	return 0

# The caller supplies an existing profile directory. A lifetime lock excludes
# other Win processes; all tabs in this app share this same owner.
int win_storage_open(win_storage_context* store, char* path):
	if (store.path != 0 || store.entries.length != 0 || path == 0 || path[0] == 0): return 0
	char* lock_path = strjoin(path, c".lock")
	io_result result
	int lock = fs_lock_acquire(lock_path, &result)
	free(lock_path)
	if (lock < 0): return 0
	int fd = fs_open(path, FS_O_RDONLY | FS_O_CLOEXEC, 0, &result)
	win_storage_context* loaded = 0
	if (fd < 0):
		if (result.native_error == 2): loaded = win_storage_new()
	else:
		string_builder* data = string_new()
		char[8192] block
		int valid = 1
		while (1):
			int status = io_read_some(fd, &block[0], 8192, &result)
			if (status == IO_EOF): break
			if (status != IO_OK || result.transferred > 1060876 - data.length):
				valid = 0
				break
			string_append_bytes(data, &block[0], result.transferred)
		if (io_close(fd, &result) != IO_OK): valid = 0
		if (valid): loaded = win_storage_decode(data.data, data.length)
		string_free(data)
	if (loaded == 0):
		fs_lock_release(lock, &result)
		return 0
	win_storage_swap(store, loaded)
	win_storage_free(loaded)
	store.path = strclone(path)
	store.lock = lock
	return 1

# Shared operation semantics for native calls and the parent-owned IPC service.
# A candidate without a path can be mutated before asynchronous publication.
win_storage_result* win_storage_execute(win_storage_context* store, char* origin, int operation, char* key, char* value, int key_index, int durable):
	win_storage_result* result = new win_storage_result()
	if (store == 0 || origin == 0 || origin[0] == 0):
		result.error = 1
		result.message = c"Storage requires an HTTP(S) origin"
		return result
	if (store.poisoned || operation < 0 || operation > 5):
		result.error = 3
		result.message = c"Storage state is unavailable"
		return result
	win_storage_context* previous = 0
	if (durable && operation >= 1 && operation <= 3 && store.path != 0):
		previous = win_storage_snapshot(store)
		if (previous == 0):
			result.error = 3
			result.message = c"Cannot snapshot persistent storage"
			return result
	int found = -1
	int count = 0
	if (operation == 0 || operation == 4): result.kind = 1
	for i in range(store.entries.length):
		win_storage_entry* entry = store.entries[i]
		if (strcmp(entry.origin, origin) != 0): continue
		if (strcmp(entry.key, key) == 0): found = i
		if (operation == 4 && key_index == count):
			result.kind = 4
			result.text = strclone(entry.key)
		count = count + 1
	if (operation == 5):
		result.kind = 3
		result.number = count
	if (operation == 0 && found >= 0):
		result.kind = 4
		result.text = strclone(store.entries[found].value)
	if (operation == 2 && found >= 0): win_storage_remove(store, found)
	if (operation == 3):
		int i = store.entries.length - 1
		while (i >= 0):
			if (strcmp(store.entries[i].origin, origin) == 0): win_storage_remove(store, i)
			i = i - 1
	if (operation == 1):
		int extra = strlen(value)
		if (found >= 0): extra = extra - strlen(store.entries[found].value)
		else: extra = extra + strlen(key) + strlen(origin)
		if (strlen(key) > 65536 || strlen(value) > 65536 || store.bytes + extra > 1048576 || (found < 0 && store.entries.length >= 1024)):
			result.error = 2
			result.message = c"Storage quota exceeded"
		else:
			win_storage_entry* entry = 0
			if (found >= 0):
				entry = store.entries[found]
				free(entry.value)
			else:
				entry = new win_storage_entry()
				entry.origin = strclone(origin)
				entry.key = strclone(key)
				store.entries.push(entry)
			entry.value = strclone(value)
			store.bytes = store.bytes + extra
	if (previous != 0):
		if (result.error == 0):
			int committed = win_storage_commit(store)
			if (committed <= 0):
				if (committed == 0): win_storage_swap(store, previous)
				result.error = 2
				if (committed < 0): result.error = 3
				result.message = c"Persistent storage write failed"
		win_storage_free(previous)
	return result
