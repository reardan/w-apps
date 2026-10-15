import lib.assert
import lib.args
import win.loader

void network_cookie_assert(char* address, char* expected):
	char* actual = win_cookie_header(address)
	asserts(c"cookie scope/value", strcmp(actual, expected) == 0)
	free(actual)

void network_cookie_tests():
	win_network_state_clear()
	win_cookie_set(c"https://example.test/a/set", c"sid=one")
	network_cookie_assert(c"https://example.test/a/page", c"sid=one")
	network_cookie_assert(c"https://example.test/ab", c"")
	network_cookie_assert(c"https://other.test/a/page", c"")
	network_cookie_assert(c"https://sub.example.test/a/page", c"")
	win_cookie_set(c"https://example.test/", c"bad=1; Domain=other.test; Path=/")
	win_cookie_set(c"https://example.test/", c"bad=2; Domain=test; Path=/")
	network_cookie_assert(c"https://example.test/", c"")
	win_cookie_set(c"https://example.test/a/", c"sid=two; Path=/a; Secure; Max-Age=60")
	network_cookie_assert(c"http://example.test/a/", c"")
	win_cookie_set(c"http://example.test/a/", c"sid=insecure; Path=/a")
	network_cookie_assert(c"https://example.test/a/", c"sid=two")
	char* snapshot = win_cookie_snapshot()
	win_network_state_clear()
	win_cookie_restore(snapshot)
	free(snapshot)
	network_cookie_assert(c"https://example.test/a/", c"sid=two")
	win_cookie_set(c"https://example.test/", c"sid=gone; Path=/a; Max-Age=0")
	network_cookie_assert(c"https://example.test/a/", c"")
	win_cookie_set_many(c"http://example.test/", c"a=1; Path=/, b=2; Path=/")
	network_cookie_assert(c"http://example.test/", c"a=1; b=2")
	win_network_state_clear()
	for i in range(40):
		string_builder* pair = string_new()
		string_append(pair, c"cookie")
		string_append_int(pair, i)
		string_append(pair, c"=bounded")
		win_cookie_set(c"http://example.test/", pair.data)
		string_free(pair)
	int count = 0
	for i in range(WIN_COOKIE_COUNT):
		if (win_cookies[i] != 0): count = count + 1
	assert_equal(32, count)
	win_network_state_clear()

void network_cache_tests():
	http_response* response = http_response_new()
	response.status = 200
	http_store_header(response, c"Cache-Control: public, max-age=60", 33)
	assert_equal(60, win_cache_lifetime(response, 0))
	assert_equal(0, win_cache_lifetime(response, 1))
	response.redirect_count = 1
	assert_equal(0, win_cache_lifetime(response, 0))
	response.redirect_count = 0
	http_store_header(response, c"Age: 20", 7)
	assert_equal(40, win_cache_lifetime(response, 0))
	http_store_header(response, c"Cache-Control: no-store", 23)
	assert_equal(0, win_cache_lifetime(response, 0))
	http_response_free(response)
	response = http_response_new()
	response.status = 200
	http_store_header(response, c"Cache-Control: max-age=60", 25)
	http_store_header(response, c"Date: Wed, 21 Oct 2015 07:28:00 GMT", 35)
	assert_equal(0, win_cache_lifetime(response, 0))
	assert_equal(1445412480, win_net_http_date(c"Wed, 21 Oct 2015 07:28:00 GMT"))
	http_response_free(response)
	win_cache_store(c"http://example.test/", c"document", c"old", 3, time_now() + 60)
	win_cache_store(c"http://example.test/", c"document", c"new", 3, time_now() + 60)
	win_cache_entry* e = win_cache_find(c"http://example.test/", c"document")
	asserts(c"cache replacement", e != 0 && strcmp(e.source, c"new") == 0)
	asserts(c"cache kind partition", win_cache_find(c"http://example.test/", c"script") == 0)
	win_cookie_set(c"http://example.test/", c"sid=private")
	asserts(c"credentialed cache bypass", win_cache_find(c"http://example.test/", c"document") == 0)
	win_network_state_clear()

win_load* network_load(char* executable, char* base, char* path, char* kind):
	char* address = strjoin(base, path)
	win_load* load = 0
	if (strcmp(kind, c"fetch") == 0): load = win_load_start_fetch(executable, address, base, c"GET", c"")
	else: load = win_load_start_kind(executable, address, kind, c"GET", c"")
	free(address)
	while (win_load_poll(load) == 0): sleep_ms(1)
	if (load.error != 0): println(load.error)
	asserts(c"network request success", load.error == 0)
	return load

void network_loopback_tests(char* executable, char* base):
	win_network_state_clear()
	win_load* load = network_load(executable, base, c"/set", c"document")
	win_load_free(load)
	load = network_load(executable, base, c"/scope/echo", c"fetch")
	asserts(c"cookie persists across workers", strcmp(load.source, c"sid=one; second=two") == 0)
	assert_equal(200, load.status)
	win_load_free(load)
	load = network_load(executable, base, c"/other/echo", c"fetch")
	asserts(c"cookie path restricted", load.length == 0)
	win_load_free(load)
	load = network_load(executable, base, c"/redirect", c"fetch")
	asserts(c"redirect cookie applies to next hop", strcmp(load.source, c"hop=ok") == 0)
	win_load_free(load)
	load = network_load(executable, base, c"/foreign-cookie", c"document")
	asserts(c"no credential leakage to foreign host", strcmp(load.source, c"empty") == 0)
	win_load_free(load)
	char* foreign = strjoin(base, c"/foreign-fetch")
	load = win_load_start_fetch(executable, foreign, base, c"GET", c"")
	while (win_load_poll(load) == 0): sleep_ms(1)
	asserts(c"fetch rejects foreign redirect", load.error != 0)
	win_load_free(load)
	free(foreign)
	load = network_load(executable, base, c"/missing", c"fetch")
	assert_equal(404, load.status)
	asserts(c"fetch exposes error body", strcmp(load.source, c"missing") == 0)
	win_load_free(load)
	win_network_state_clear()
	for i in range(2):
		load = network_load(executable, base, c"/cache", c"document")
		asserts(c"cache payload", strcmp(load.source, c"cached") == 0)
		if (i == 1): asserts(c"cache avoids worker", load.child == 0)
		win_load_free(load)
	for i in range(2):
		load = network_load(executable, base, c"/no-store", c"document")
		asserts(c"no-store always loads", load.child != 0)
		win_load_free(load)
	for i in range(2):
		load = network_load(executable, base, c"/cache-redirect", c"document")
		asserts(c"redirect is not cached", load.child != 0)
		asserts(c"final URL retained", ends_with(load.address, c"/cache"))
		win_load_free(load)
	win_network_state_clear()

int main(int argc, int argv):
	args_init(argc, argv)
	char* resource = args_value(c"resource")
	if (resource != 0): return win_resource_worker(resource, args_value(c"kind"))
	char* fetch = args_value(c"fetch")
	if (fetch != 0): return win_fetch_request_worker(fetch, args_value(c"method"), args_value(c"body"))
	char* network = args_value(c"network")
	if (network != 0): network_loopback_tests(args_get(0), network)
	else:
		network_cookie_tests()
		network_cache_tests()
	println(c"network tests passed")
	return 0
