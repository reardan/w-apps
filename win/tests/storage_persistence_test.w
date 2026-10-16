import lib.assert
import win.storage
import win.script

void storage_failed_mutation():
	char* html = c"<title>storage</title>"
	win_page* page = win_page_parse(html, strlen(html))
	win_script* script = win_script_new(page)
	win_storage_context* store = win_storage_new()
	win_script_bind_storage(script, store, 0, c"https://example.test/app")
	char* initial = c"localStorage.setItem('key','old');"
	assert1(win_script_eval(script, initial, strlen(initial)))
	store.path = strclone(c"/missing-win-storage-test-directory/state")
	char* fail = c"let failed=0;try{localStorage.setItem('key','new');}catch(e){if(e.name==='QuotaExceededError')failed++;}try{localStorage.removeItem('key');}catch(e){failed++;}try{localStorage.clear();}catch(e){failed++;}if(failed!==3||localStorage.getItem('key')!=='old'||localStorage.length!==1)throw 'rollback';"
	assert1(win_script_eval(script, fail, strlen(fail)))
	assert_equal(0, script.failures)
	win_script_free(script)
	win_page_free(page)
	win_storage_free(store)

int main():
	storage_failed_mutation()
	win_storage_context* store = win_storage_new()
	char* origin = win_storage_origin(c"https://EXAMPLE.test/a")
	assert_strings_equal(c"https://example.test:443", origin)
	win_storage_entry* entry = new win_storage_entry()
	entry.origin = origin
	entry.key = strclone(c"key\nvalue")
	entry.value = strclone(c"Unicode: \xc3\xa9 and newline\n")
	store.entries.push(entry)
	store.bytes = strlen(entry.origin) + strlen(entry.key) + strlen(entry.value)
	string_builder* encoded = win_storage_encode(store)
	win_storage_context* decoded = win_storage_decode(encoded.data, encoded.length)
	assert1(decoded != 0)
	assert_equal(store.bytes, decoded.bytes)
	assert_strings_equal(entry.key, decoded.entries[0].key)
	assert_strings_equal(entry.value, decoded.entries[0].value)
	win_storage_free(decoded)
	for length in range(encoded.length): assert1(win_storage_decode(encoded.data, length) == 0)
	string_append_char(encoded, 'x')
	assert1(win_storage_decode(encoded.data, encoded.length) == 0)
	encoded.length = encoded.length - 1
	encoded.data[0] = 'X'
	assert1(win_storage_decode(encoded.data, encoded.length) == 0)
	encoded.data[0] = 'W'
	store_le32(encoded.data + 8, 1025)
	assert1(win_storage_decode(encoded.data, encoded.length) == 0)
	store_le32(encoded.data + 8, 1)
	store_le32(encoded.data + 12, 2147483647)
	assert1(win_storage_decode(encoded.data, encoded.length) == 0)
	string_free(encoded)
	# Origins with IPv6 hosts must round-trip as parseable serialized origins.
	free(entry.origin)
	entry.origin = win_storage_origin(c"http://[::1]/a")
	store.bytes = strlen(entry.origin) + strlen(entry.key) + strlen(entry.value)
	encoded = win_storage_encode(store)
	decoded = win_storage_decode(encoded.data, encoded.length)
	assert1(decoded != 0)
	win_storage_free(decoded)
	string_free(encoded)
	win_storage_free(store)
	println(c"storage persistence records: OK")
	return 0
