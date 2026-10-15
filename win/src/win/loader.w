# Linux loader process. Network/file reads never block the UI thread. The
# parent polls a bounded pipe and destroys the old child on stop/navigation.
import win.images
import win.network_state
import lib.process
import lib.poll
import lib.path
import lib.io
import lib.time
import libs.standard.web.content_decode
import libs.extras.compress.codecs

const int WIN_SOURCE_LIMIT = 1048576
const int WIN_ADDRESS_LIMIT = 4096

int win_remote(char* address):
	return starts_with(address, c"http://") || starts_with(address, c"https://")

int win_fragment_index(char* address):
	int n = strlen(address)
	for i in range(n):
		if (address[i] == '#'): return i
	return n

char* win_without_fragment(char* address):
	return substring(address, 0, win_fragment_index(address))

# Inputs from the address bar have an empty base. Links use the current page.
char* win_resolve(char* base, char* reference):
	int n = strlen(reference)
	if (n == 0 || n > WIN_ADDRESS_LIMIT): return 0
	for i in range(n):
		if ((reference[i] & 255) < 32): return 0
	if (win_remote(base) || win_remote(reference)):
		URL* b = 0
		if (win_remote(base)): b = url_parse(base)
		URL* u = 0
		if (win_remote(reference)): u = url_parse(reference)
		else if (b != 0): u = url_resolve(b, reference)
		if (b != 0): url_free(b)
		if (u == 0): return 0
		char* result = url_unparse(u)
		url_free(u)
		return result
	# Deliberately use native paths for explicit local files in this milestone.
	for i in range(n):
		if (reference[i] == ':'): return 0
	char* bare = win_without_fragment(reference)
	char* base_path = win_without_fragment(base)
	char* result = 0
	if (bare[0] == 0 && base_path[0] != 0): result = strclone(base_path)
	else if (bare[0] == '/'): result = path_normalize(bare)
	else:
		char* dir = 0
		if (base_path[0] != 0): dir = path_dirname(base_path)
		else:
			char[4096] cwd
			if (getcwd(&cwd[0], 4096) < 0):
				free(bare)
				free(base_path)
				return 0
			dir = strclone(&cwd[0])
		result = path_join(dir, bare)
		free(dir)
	int fragment = win_fragment_index(reference)
	if (fragment < n):
		string_builder* out = string_new()
		string_append(out, result)
		string_append(out, reference + fragment)
		free(result)
		result = strclone(out.data)
		string_free(out)
	free(bare)
	free(base_path)
	return result

int win_write(char* bytes, int length):
	io_result out
	return io_write_all(1, bytes, length, &out) == IO_OK

int win_worker_error(char* message):
	win_write(c"ERROR\n", 6)
	win_write(message, strlen(message))
	return 1

int win_worker_ok(char* address, char* source, int length):
	if (strlen(address) > WIN_ADDRESS_LIMIT): return win_worker_error(c"Final URL exceeds the address limit.")
	if (win_write(c"OK\n", 3) == 0): return 1
	if (win_write(address, strlen(address)) == 0): return 1
	if (win_write(c"\n", 1) == 0): return 1
	if (win_write(source, length) == 0): return 1
	return 0

int win_mime_is(char* header, char* expected):
	int at = 0
	while (header[at] == 32 || header[at] == 9): at = at + 1
	int size = strlen(expected)
	for i in range(size):
		int c = header[at + i] & 255
		if (c >= 'A' && c <= 'Z'): c = c + 32
		if (c != expected[i]): return 0
	at = at + size
	while (header[at] == 32 || header[at] == 9): at = at + 1
	return header[at] == 0 || header[at] == ';'

int win_resource_redirect(void* context, URL* before, URL* after, int status):
	if (strcmp(before.scheme, c"https") == 0 && strcmp(after.scheme, c"https") != 0): return 0
	return 1

# W preserves POST on 301/302. Browser form navigations instead switch to
# GET, as on 303; 307/308 replay the original method and encoded body.
# Keep redirect handling here so the foundation's general client is unchanged.
http_stream* win_form_http_open(http_req* req):
	# Redirects are manual for every method: cookie scope is recomputed per hop.
	char* fetch_origin = env_get(c"WIN_FETCH_ORIGIN")
	URL* origin = 0
	if (fetch_origin != 0 && fetch_origin[0] != 0): origin = url_parse(fetch_origin)
	list[http_header*] original_headers = req.headers
	char* initial_cookie = win_cookie_header(req.url)
	int credentialed = initial_cookie[0] != 0
	free(initial_cookie)
	char* original_url = req.url
	char* original_method = req.method
	char* original_body = req.body
	int original_length = req.body_len
	int original_timeout = req.total_timeout_ms
	int original_redirects = req.max_redirects
	int deadline = time_monotonic_ms() + original_timeout
	char* address = strclone(req.url)
	http_stream* stream = 0
	int redirects = 0
	req.max_redirects = 0
	while (1):
		req.url = address
		req.total_timeout_ms = deadline - time_monotonic_ms()
		if (req.total_timeout_ms <= 0):
			stream = http_stream_new()
			http_stream_fail(stream, http_error_timeout)
			break
		URL* target = url_parse(address)
		int same_origin = origin == 0 || url_same_origin(origin, target)
		if (target != 0): url_free(target)
		if (same_origin == 0):
			stream = http_stream_new()
			http_stream_fail(stream, http_error_bad_url)
			break
		req.headers = new list[http_header*]
		for http_header* h in original_headers:
			# Never replay caller credentials; browser cookies are scoped below.
			if (win_net_equal(h.name, c"cookie") || win_net_equal(h.name, c"authorization") || win_net_equal(h.name, c"proxy-authorization")): continue
			http_req_add_header(req, h.name, h.value)
		char* cookie = win_cookie_header(address)
		if (cookie[0] != 0):
			http_req_add_header(req, c"Cookie", cookie)
			credentialed = 1
		free(cookie)
		stream = http_open(req)
		for http_header* h in req.headers:
			free(h.name)
			free(h.value)
			free(h)
		list_free[http_header*](req.headers)
		req.headers = original_headers
		char* set_cookie = http_response_header(stream.resp, c"set-cookie")
		if (set_cookie != 0 && strlen(set_cookie) <= WIN_COOKIE_LIMIT):
			win_cookie_set_many(address, set_cookie)
			if (env_get(c"WIN_COOKIE_SNAPSHOT") != 0):
				win_write(c"COOKIE\n", 7)
				win_write(address, strlen(address))
				win_write(c"\n", 1)
				win_write(set_cookie, strlen(set_cookie))
				win_write(c"\n", 1)
		int status = stream.resp.status
		if (stream.error != 0 || http_status_is_redirect(status) == 0): break
		char* location = http_response_header(stream.resp, c"location")
		if (location == 0): break
		if (redirects >= original_redirects):
			http_stream_fail(stream, http_error_too_many_redirects)
			break
		URL* before = url_parse(address)
		URL* after = http_redirect_target(before, location)
		if (after == 0):
			url_free(before)
			http_stream_fail(stream, http_error_bad_url)
			break
		int allowed = http_validate_url(after) == 0 && win_resource_redirect(0, before, after, status)
		if (origin != 0 && url_same_origin(origin, after) == 0): allowed = 0
		url_free(before)
		if (allowed == 0):
			url_free(after)
			http_stream_fail(stream, http_error_bad_url)
			break
		char* next = url_unparse(after)
		url_free(after)
		if (status == 303 || ((status == 301 || status == 302) && strcmp(req.method, c"POST") == 0)):
			req.method = c"GET"
			req.body = 0
			req.body_len = 0
		http_stream_close(stream)
		free(address)
		address = next
		redirects = redirects + 1
	stream.resp.redirect_count = redirects
	if (origin != 0): url_free(origin)
	if (stream.error == 0 && env_get(c"WIN_COOKIE_SNAPSHOT") != 0):
		string_builder* metadata = string_new()
		string_append(metadata, c"STATUS\n")
		string_append_int(metadata, stream.resp.status)
		string_append(metadata, c"\nCACHE\n")
		int lifetime = 0
		if (strcmp(original_method, c"GET") == 0): lifetime = win_cache_lifetime(stream.resp, credentialed)
		string_append_int(metadata, lifetime)
		string_append(metadata, c"\n")
		win_write(metadata.data, metadata.length)
		string_free(metadata)
	free(address)
	req.url = original_url
	req.method = original_method
	req.body = original_body
	req.body_len = original_length
	req.total_timeout_ms = original_timeout
	req.max_redirects = original_redirects
	return stream

int win_fetch_payload(char* address, char* source, int length, char* kind):
	if (strcmp(kind, c"image") != 0): return win_worker_ok(address, source, length)
	wresult[rgba_image*]* decoded = win_image_decode(source, length)
	if (decoded.ok == 0):
		int code = win_worker_error(image_error_string(decoded.code))
		free(decoded)
		return code
	rgba_image* image = decoded.value
	free(decoded)
	char[8] dimensions
	store_be32(&dimensions[0], image.width)
	store_be32(&dimensions[4], image.height)
	int ok = win_worker_ok(address, &dimensions[0], 8)
	if (ok == 0 && win_write(image.pixels, image.length) == 0): ok = 1
	rgba_image_free(image)
	return ok

int win_fetch_kind_worker(char* address, char* kind, char* method, char* body):
	win_cookie_restore(env_get(c"WIN_COOKIE_SNAPSHOT"))
	int limit = WIN_SOURCE_LIMIT
	if (strcmp(kind, c"image") == 0): limit = WIN_IMAGE_INPUT_LIMIT
	if (strlen(body) > 65536): return win_worker_error(c"Form body exceeds 64 KiB.")
	if (win_remote(address)):
		compress_codecs_register()
		http_client* client = http_client_new()
		http_req* req = http_req_new(method, address)
		req.client = client
		req.total_timeout_ms = 10000
		req.max_redirects = 5
		req.max_stream_bytes = limit
		req.approve_redirect = win_resource_redirect
		if (strcmp(method, c"POST") == 0):
			req.body = body
			req.body_len = strlen(body)
			http_req_add_header(req, c"Content-Type", c"application/x-www-form-urlencoded")
		if (strcmp(kind, c"document") == 0): http_req_add_header(req, c"Accept", c"text/html")
		else if (strcmp(kind, c"css") == 0): http_req_add_header(req, c"Accept", c"text/css")
		else if (strcmp(kind, c"image") == 0): http_req_add_header(req, c"Accept", c"image/png, image/jpeg")
		else: http_req_add_header(req, c"Accept", c"text/javascript, application/javascript")
		http_req_add_header(req, c"Accept-Encoding", c"gzip, deflate")
		http_stream* stream = win_form_http_open(req)
		content_decoder* content = http_content_collect(stream, limit, limit)
		int code = 1
		if (content.status != content_decode_done):
			if (stream.resp.error != 0): code = win_worker_error(stream.resp.error_message)
			else: code = win_worker_error(c"Unsupported, invalid or oversized content encoding.")
		else if (strcmp(kind, c"fetch") != 0 && (stream.resp.status < 200 || stream.resp.status >= 300)): code = win_worker_error(c"Server returned an unsuccessful HTTP status.")
		else:
			char* mime = http_response_header(stream.resp, c"content-type")
			if (strcmp(kind, c"document") == 0 && mime != 0 && win_mime_is(mime, c"text/html") == 0): code = win_worker_error(c"This version opens HTML documents only.")
			else if (strcmp(kind, c"css") == 0 && mime != 0 && win_mime_is(mime, c"text/css") == 0): code = win_worker_error(c"Stylesheet response has an unsupported content type.")
			else if (strcmp(kind, c"script") == 0 && mime != 0 && win_mime_is(mime, c"text/javascript") == 0 && win_mime_is(mime, c"application/javascript") == 0 && win_mime_is(mime, c"application/ecmascript") == 0 && win_mime_is(mime, c"text/ecmascript") == 0): code = win_worker_error(c"Script response has an unsupported content type.")
			else: code = win_fetch_payload(stream.resp.final_url, content.output, content.output_length, kind)
		content_decoder_free(content)
		http_stream_close(stream)
		http_req_free(req)
		http_client_free(client)
		return code
	if (strcmp(kind, c"fetch") == 0): return win_worker_error(c"Fetch requires HTTP(S).")
	if (strcmp(method, c"GET") != 0): return win_worker_error(c"Form POST requires an HTTP address.")
	char* filename = win_without_fragment(address)
	int fd = open(filename, 0, 0)
	free(filename)
	if (fd < 0): return win_worker_error(c"Cannot open local file.")
	string_builder* source = string_new()
	char[8192] chunk
	int failed = 0
	while (1):
		int count = read(fd, &chunk[0], 8192)
		if (count == -4): continue
		if (count < 0):
			failed = 1
			break
		if (count == 0): break
		if (source.length + count > limit):
			failed = 1
			break
		string_append_bytes(source, &chunk[0], count)
	close(fd)
	int code = 1
	if (failed): code = win_worker_error(c"Local file read failed or exceeded its resource limit.")
	else: code = win_fetch_payload(address, source.data, source.length, kind)
	string_free(source)
	return code

int win_fetch_worker(char* address):
	return win_fetch_kind_worker(address, c"document", c"GET", c"")

int win_fetch_request_worker(char* address, char* method, char* body):
	return win_fetch_kind_worker(address, c"document", method, body)

int win_resource_worker(char* address, char* kind):
	return win_fetch_kind_worker(address, kind, c"GET", c"")

struct win_load:
	process* child
	string_builder* output
	int started
	int eof
	int finished
	char* error
	char* address
	char* source
	int length
	int limit
	int status
	int cache_expires
	char* request_address
	char* kind

void win_load_free(win_load* load):
	if (load == 0): return
	if (load.child != 0): process_free(load.child)
	string_free(load.output)
	free(load.request_address)
	free(load.kind)
	if (load.error != 0): free(load.error)
	if (load.address != 0): free(load.address)
	free(load)

win_load* win_load_start_network(char* executable, char* address, char* kind, char* method, char* body, char* origin):
	win_load* load = new win_load()
	load.output = string_new()
	load.started = time_monotonic_ms()
	load.eof = 0
	load.finished = 0
	load.error = 0
	load.address = 0
	load.source = 0
	load.length = 0
	load.limit = WIN_SOURCE_LIMIT
	load.status = 0
	load.cache_expires = 0
	load.request_address = win_without_fragment(address)
	load.kind = strclone(kind)
	load.child = 0
	if (strcmp(method, c"GET") != 0): win_cache_clear()
	if (strcmp(kind, c"fetch") == 0):
		URL* from = url_parse(origin)
		URL* to = url_parse(address)
		int allowed = from != 0 && to != 0 && url_same_origin(from, to) && strcmp(method, c"GET") == 0
		if (from != 0): url_free(from)
		if (to != 0): url_free(to)
		if (allowed == 0):
			load.error = strclone(c"Fetch requires a same-origin HTTP(S) GET.")
			load.finished = 1
			return load
	win_cache_entry* cached = 0
	if (strcmp(method, c"GET") == 0): cached = win_cache_find(load.request_address, kind)
	if (cached != 0):
		string_append_bytes(load.output, cached.source, cached.length)
		load.source = load.output.data
		load.length = cached.length
		load.address = strclone(address)
		load.status = 200
		load.finished = 1
		return load
	if (strcmp(kind, c"image") == 0): load.limit = WIN_IMAGE_RGBA_LIMIT + 8
	spawn_options* opts = spawn_options_new()
	opts.stdin_mode = process_null
	opts.stdout_mode = process_pipe
	opts.new_group = 1
	char*[10] argv
	argv[0] = executable
	argv[1] = c"--fetch"
	if (strcmp(kind, c"document") != 0): argv[1] = c"--resource"
	argv[2] = address
	argv[3] = c"--kind"
	argv[4] = kind
	argv[5] = c"--method"
	argv[6] = method
	argv[7] = c"--body"
	argv[8] = body
	argv[9] = 0
	char* snapshot = win_cookie_snapshot()
	char** cookie_env = env_copy_with(env_current(), c"WIN_COOKIE_SNAPSHOT", snapshot)
	char** worker_env = env_copy_with(cookie_env, c"WIN_FETCH_ORIGIN", origin)
	opts.env = worker_env
	load.child = process_spawn(executable, &argv[0], opts)
	for i in range(env_vector_count(worker_env)):
		char* entry = env_entry_at(worker_env, i)
		if (env_match_name(entry, c"WIN_FETCH_ORIGIN") >= 0): free(entry)
	for i in range(env_vector_count(cookie_env)):
		char* entry = env_entry_at(cookie_env, i)
		if (env_match_name(entry, c"WIN_COOKIE_SNAPSHOT") >= 0): free(entry)
	free(cast(void*, worker_env))
	free(cast(void*, cookie_env))
	free(snapshot)
	free(opts)
	if (load.child == 0):
		load.error = strclone(c"Cannot start resource loader.")
		load.finished = 1
	return load

win_load* win_load_start_kind(char* executable, char* address, char* kind, char* method, char* body):
	return win_load_start_network(executable, address, kind, method, body, c"")

# No main-worker flag changes: origin and cookie snapshot are exec environment.
win_load* win_load_start_fetch(char* executable, char* address, char* origin, char* method, char* body):
	return win_load_start_network(executable, address, c"fetch", method, body, origin)

win_load* win_load_start(char* executable, char* address):
	return win_load_start_kind(executable, address, c"document", c"GET", c"")

win_load* win_load_start_request(char* executable, char* address, char* method, char* body):
	return win_load_start_kind(executable, address, c"document", method, body)

void win_load_fail(win_load* load, char* error):
	load.error = strclone(error)
	load.finished = 1
	if (load.child != 0):
		process_free(load.child)
		load.child = 0

int win_load_poll(win_load* load):
	if (load.finished): return 1
	if (time_monotonic_ms() - load.started > 12000):
		win_load_fail(load, c"Document loading timed out.")
		return 1
	char[8192] chunk
	# At most 64 KiB per frame; no pipe read occurs without readiness.
	for i in range(8):
		if (load.eof): break
		int ready = poll_single(load.child.stdout_fd, poll_in, 0)
		if (ready == 0): break
		if (ready < 0):
			if (ready == -4): break
			win_load_fail(load, c"Loader pipe failed.")
			return 1
		int count = read(load.child.stdout_fd, &chunk[0], 8192)
		if (count == -4): break
		if (count < 0):
			win_load_fail(load, c"Loader read failed.")
			return 1
		if (count == 0):
			load.eof = 1
			break
		if (load.output.length + count > load.limit + WIN_ADDRESS_LIMIT + 65536):
			win_load_fail(load, c"Document exceeds the loading limit.")
			return 1
		string_append_bytes(load.output, &chunk[0], count)
	if (load.eof == 0): return 0
	int status = process_try_wait(load.child)
	if (status == process_status_running): return 0
	load.finished = 1
	char* data = load.output.data
	int metadata_bytes = 0
	char*[6] cookie_urls
	char*[6] cookie_headers
	int cookie_count = 0
	# Metadata precedes the existing OK/ERROR envelope, including redirect
	# cookies. Only complete, bounded lines are accepted after child exit.
	while (starts_with(data, c"COOKIE\n") || starts_with(data, c"STATUS\n") || starts_with(data, c"CACHE\n")):
		int cookie_record = starts_with(data, c"COOKIE\n")
		int status_record = starts_with(data, c"STATUS\n")
		int start = 6
		if (cookie_record || status_record): start = 7
		int end = start
		while (data[end] != 0 && data[end] != 10): end = end + 1
		if (data[end] != 10): break
		char* value = substring(data, start, end)
		int consumed = end + 1
		if (cookie_record):
			start = consumed
			end = start
			while (data[end] != 0 && data[end] != 10): end = end + 1
			if (data[end] != 10):
				free(value)
				break
			char* header = substring(data, start, end)
			if (cookie_count < 6):
				cookie_urls[cookie_count] = strclone(value)
				cookie_headers[cookie_count] = header
				cookie_count = cookie_count + 1
			else: free(header)
			consumed = end + 1
		else if (status_record): load.status = win_net_decimal(value, 599)
		else:
			int lifetime = win_net_decimal(value, 86400)
			if (lifetime > 0): load.cache_expires = time_now() + lifetime - (time_monotonic_ms() - load.started + 999) / 1000
		free(value)
		data = data + consumed
		metadata_bytes = metadata_bytes + consumed
	if (starts_with(data, c"ERROR\n")): load.error = strclone(data + 6)
	else if (status != 0 || starts_with(data, c"OK\n") == 0): load.error = strclone(c"Resource loader exited unsuccessfully.")
	else:
		int end = 3
		while (end < load.output.length - metadata_bytes && data[end] != 10): end = end + 1
		if (end >= load.output.length - metadata_bytes || end - 3 > WIN_ADDRESS_LIMIT): load.error = strclone(c"Invalid loader response.")
		else:
			load.address = substring(data, 3, end)
			load.source = data + end + 1
			load.length = load.output.length - metadata_bytes - end - 1
	int valid_protocol = (status == 0 && load.error == 0) || (status == 1 && starts_with(data, c"ERROR\n"))
	for i in range(cookie_count):
		if (valid_protocol): win_cookie_set_many(cookie_urls[i], cookie_headers[i])
		free(cookie_urls[i])
		free(cookie_headers[i])
	if (load.error == 0 && load.cache_expires > 0): win_cache_store(load.request_address, load.kind, load.source, load.length, load.cache_expires)
	return 1
