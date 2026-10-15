# Explicitly owned in-memory origin buckets. Shared local owner lives with the app;
# session owner lives with a tab. No disk persistence or opaque-origin sharing.
import libs.standard.web.urlparse
import libs.extras.javascript.runtime

struct win_storage_entry:
	char* origin
	char* key
	char* value

struct win_storage_context:
	list[win_storage_entry*] entries
	int bytes

win_storage_context* win_storage_new():
	win_storage_context* store = new win_storage_context()
	store.entries = new list[win_storage_entry*]
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
	while (store.entries.length > 0): win_storage_remove(store, store.entries.length - 1)
	__w_list_free(cast(__w_list*, store.entries))
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
