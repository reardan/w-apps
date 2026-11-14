# Linux loader process. Network/file reads never block the UI thread. The
# parent polls a bounded pipe and destroys the old child on stop/navigation.
import win.broker_wire
import win.images
import win.sandbox
import win.network_state
import lib.process
import lib.net
import lib.poll
import lib.path
import lib.io
import lib.time
import libs.standard.web.content_decode
import libs.extras.compress.codecs

const int WIN_SOURCE_LIMIT = 1048576
# The unchanged mobile UI wasm is 1.7 MiB; only Fetch gets the larger limit.
const int WIN_FETCH_LIMIT = 4194304
const int WIN_ADDRESS_LIMIT = 4096
const int WIN_FETCH_REQUEST_LIMIT = 65536
# COOKIE\n + URL + \n + field + \n, up to 32 across all redirects.
# A separate 1024 bytes covers STATUS/CACHE/WASM-MIME records. Body limits
# are enforced independently after envelope parsing as well as in the child.
const int WIN_LOADER_COOKIE_METADATA_LIMIT = WIN_COOKIE_COUNT * (WIN_ADDRESS_LIMIT + WIN_COOKIE_LIMIT + 9)
const int WIN_LOADER_METADATA_LIMIT = WIN_LOADER_COOKIE_METADATA_LIMIT + 1024

int win_remote(char* address):
	return starts_with(address, c"http://") || starts_with(address, c"https://")

int win_fragment_index(char* address):
	int n = strlen(address)
	for i in range(n):
		if (address[i] == '#'): return i
	return n

char* win_without_fragment(char* address):
	return substring(address, 0, win_fragment_index(address))

# Address-bar text such as "google.com" or "localhost:8080/x" has no scheme.
# Without this it would resolve as a file under the current directory. Existing
# local files, explicit paths and anything else not host-shaped are unchanged.
# The result is always a new allocation.
char* win_address_input(char* text):
	int n = strlen(text)
	if (n == 0 || win_remote(text)): return strclone(text)
	if (text[0] == '/' || text[0] == '.' || text[0] == '~'): return strclone(text)
	if (path_exists(text)): return strclone(text)
	int end = 0
	while (end < n && text[end] != '/' && text[end] != '?' && text[end] != '#'): end += 1
	int host_end = end
	for i in range(end):
		if (text[i] == ':'):
			host_end = i
			break
	if (host_end < end):
		if (host_end + 1 == end): return strclone(text)
		for i in range(host_end + 1, end):
			if (text[i] < '0' || text[i] > '9'): return strclone(text)
	if (host_end == 0): return strclone(text)
	int has_dot = 0
	int numeric = 1
	for i in range(host_end):
		char c = text[i]
		if (c == '.'): has_dot = 1
		else if (c < '0' || c > '9'): numeric = 0
		if (c <= 32 || c == 127 || c == '@'): return strclone(text)
	char* host = substring(text, 0, host_end)
	int local = strcmp(host, c"localhost") == 0
	free(host)
	if (!local && !has_dot): return strclone(text)
	string_builder* out = string_new()
	if (local || numeric): string_append(out, c"http://")
	else: string_append(out, c"https://")
	string_append(out, text)
	char* result = strclone(out.data)
	string_free(out)
	return result

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

# Streaming wasm requires an exact MIME value after HTTP whitespace trimming;
# parameters (including an empty semicolon) are forbidden by the Web API.
int win_wasm_mime(char* header):
	if (header == 0): return 0
	char* trimmed = http_trimmed_value(header, 0, strlen(header))
	int valid = win_net_equal(trimmed, c"application/wasm")
	free(trimmed)
	return valid

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
	int removed_body = 0
	int original_timeout = req.total_timeout_ms
	int original_redirects = req.max_redirects
	int deadline = time_monotonic_ms() + original_timeout
	char* address = strclone(req.url)
	http_stream* stream = 0
	int redirects = 0
	int cookie_fields = 0
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
			if (removed_body && (win_net_equal(h.name, c"content-type") || win_net_equal(h.name, c"content-encoding") || win_net_equal(h.name, c"content-language") || win_net_equal(h.name, c"content-location"))): continue
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
		# Match the parent IPC cap across the complete redirect chain. Each
		# original field consumes one slot, including malformed/oversized fields.
		for i in range(http_response_set_cookie_count(stream.resp)):
			if (cookie_fields >= WIN_COOKIE_COUNT): break
			cookie_fields = cookie_fields + 1
			char* set_cookie = http_response_set_cookie(stream.resp, i)
			if (strlen(set_cookie) > WIN_COOKIE_LIMIT || strlen(address) > WIN_ADDRESS_LIMIT): continue
			win_cookie_set(address, set_cookie)
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
		if ((status == 303 && strcmp(req.method, c"HEAD") != 0) || ((status == 301 || status == 302) && strcmp(req.method, c"POST") == 0)):
			req.method = c"GET"
			req.body = 0
			req.body_len = 0
			removed_body = 1
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
		string_append(metadata, c"\nWASM-MIME\n")
		string_append_int(metadata, win_wasm_mime(http_response_header(stream.resp, c"content-type")))
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

int win_fetch_kind_worker_bytes(char* address, char* kind, char* method, char* body, int body_length, char* content_type, char* accept):
	win_cookie_restore(env_get(c"WIN_COOKIE_SNAPSHOT"))
	int limit = WIN_SOURCE_LIMIT
	if (strcmp(kind, c"fetch") == 0): limit = WIN_FETCH_LIMIT
	if (strcmp(kind, c"image") == 0): limit = WIN_IMAGE_INPUT_LIMIT
	if (body_length < 0 || body_length > WIN_FETCH_REQUEST_LIMIT): return win_worker_error(c"Form body exceeds 64 KiB.")
	if (win_remote(address)):
		compress_codecs_register()
		http_client* client = http_client_new()
		http_req* req = http_req_new(method, address)
		req.client = client
		req.total_timeout_ms = 10000
		req.max_redirects = 5
		req.max_stream_bytes = limit
		req.approve_redirect = win_resource_redirect
		req.body = body
		req.body_len = body_length
		if (content_type[0] != 0): http_req_add_header(req, c"Content-Type", content_type)
		if (strcmp(kind, c"fetch") == 0): http_req_add_header(req, c"Accept", accept)
		else if (strcmp(kind, c"document") == 0): http_req_add_header(req, c"Accept", c"text/html")
		else if (strcmp(kind, c"css") == 0): http_req_add_header(req, c"Accept", c"text/css")
		else if (strcmp(kind, c"image") == 0): http_req_add_header(req, c"Accept", c"image/png, image/jpeg, image/gif")
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

int win_fetch_kind_worker(char* address, char* kind, char* method, char* body):
	char* content_type = c""
	if (strcmp(method, c"POST") == 0): content_type = c"application/x-www-form-urlencoded"
	return win_fetch_kind_worker_bytes(address, kind, method, body, strlen(body), content_type, c"*/*")

# Header fields are ASCII request tokens/values. Binary body bytes never pass
# through strlen, argv, or environment variables.
int win_fetch_method(char* method):
	int length = strlen(method)
	if (length == 0 || length > 32): return 0
	if (win_net_equal(method, c"CONNECT") || win_net_equal(method, c"TRACE") || win_net_equal(method, c"TRACK")): return 0
	for i in range(length):
		int c = method[i] & 255
		if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')): continue
		if (c == '!' || c == '#' || c == '$' || c == '%' || c == '&' || c == 39 || c == '*' || c == '+' || c == '-' || c == '.' || c == '^' || c == '_' || c == '`' || c == '|' || c == '~'): continue
		return 0
	return 1

int win_fetch_header_value(char* value, int length):
	if (length > 1024): return 0
	for i in range(length):
		int c = value[i] & 255
		if ((c < 32 && c != 9) || c >= 127): return 0
	return 1

int win_fetch_frame_read(char* buffer, int length, int deadline):
	int offset = 0
	while (offset < length):
		int remaining = deadline - time_monotonic_ms()
		if (remaining <= 0): return 0
		int ready = poll_single(0, poll_in, remaining)
		if (ready == -4): continue
		if (ready <= 0): return 0
		int count = read(0, buffer + offset, length - offset)
		if (count == -4): continue
		if (count <= 0): return 0
		offset = offset + count
	return 1

int win_fetch_frame_worker(char* address):
	int deadline = time_monotonic_ms() + 5000
	char[24] header
	if (win_fetch_frame_read(&header[0], 24, deadline) == 0): return win_worker_error(c"Incomplete Fetch request header")
	for i in range(8):
		if (header[i] != c"WFET0001"[i]): return win_worker_error(c"Unsupported Fetch request version")
	int method_length = load_int32(&header[8])
	int type_length = load_int32(&header[12])
	int accept_length = load_int32(&header[16])
	int body_length = load_int32(&header[20])
	if (method_length < 1 || method_length > 32 || type_length < 0 || type_length > 1024 || accept_length < 0 || accept_length > 1024 || body_length < 0 || body_length > WIN_FETCH_REQUEST_LIMIT): return win_worker_error(c"Invalid Fetch request lengths")
	char* method = cast(char*, malloc(method_length + 1))
	char* content_type = cast(char*, malloc(type_length + 1))
	char* accept = cast(char*, malloc(accept_length + 1))
	char* body = cast(char*, malloc(body_length + 1))
	method[method_length] = 0
	content_type[type_length] = 0
	accept[accept_length] = 0
	body[body_length] = 0
	int ok = win_fetch_frame_read(method, method_length, deadline)
	if (ok): ok = win_fetch_frame_read(content_type, type_length, deadline)
	if (ok): ok = win_fetch_frame_read(accept, accept_length, deadline)
	if (ok): ok = win_fetch_frame_read(body, body_length, deadline)
	# One complete frame followed by EOF. A trailing byte is protocol failure.
	char tail
	if (ok):
		int remaining = deadline - time_monotonic_ms()
		if (remaining <= 0 || poll_single(0, poll_in, remaining) <= 0): ok = 0
		else if (read(0, &tail, 1) != 0): ok = 0
	if (strlen(method) != method_length || win_fetch_method(method) == 0): ok = 0
	if (win_fetch_header_value(content_type, type_length) == 0 || win_fetch_header_value(accept, accept_length) == 0): ok = 0
	if ((strcmp(method, c"GET") == 0 || strcmp(method, c"HEAD") == 0) && body_length != 0): ok = 0
	char* origin = env_get(c"WIN_FETCH_ORIGIN")
	URL* from = 0
	if (origin != 0): from = url_parse(origin)
	URL* to = url_parse(address)
	if (from == 0 || to == 0 || url_same_origin(from, to) == 0): ok = 0
	if (from != 0): url_free(from)
	if (to != 0): url_free(to)
	int result = 1
	if (ok): result = win_fetch_kind_worker_bytes(address, c"fetch", method, body, body_length, content_type, accept)
	else: result = win_worker_error(c"Invalid or incomplete Fetch request")
	free(method)
	free(content_type)
	free(accept)
	free(body)
	return result

int win_fetch_worker(char* address):
	return win_fetch_kind_worker(address, c"document", c"GET", c"")

int win_fetch_request_worker(char* address, char* method, char* body):
	return win_fetch_kind_worker(address, c"document", method, body)

int win_resource_worker(char* address, char* kind):
	if (strcmp(kind, c"fetch") == 0): return win_fetch_frame_worker(address)
	return win_fetch_kind_worker(address, kind, c"GET", c"")

struct win_load:
	int broker_id
	string_builder* outgoing
	int sent
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
	int wasm_mime
	int cache_expires
	int cache_allowed
	char* request_address
	char* kind

win_broker_wire* win_broker_client
list[win_load*] win_broker_loads
int win_broker_sequence

void win_broker_forget(win_load* load):
	if (load.broker_id == 0 || win_broker_loads == 0): return
	for i in range(win_broker_loads.length):
		if (win_broker_loads[i] == load):
			win_broker_loads[i] = win_broker_loads[win_broker_loads.length - 1]
			win_broker_loads.pop()
			break
	if (load.finished == 0):
		string_builder* cancel = win_broker_packet(load.broker_id, 2)
		win_broker_queue(win_broker_client, cancel)
		string_free(cancel)
		win_broker_pump(win_broker_client)
	load.broker_id = 0

# Cancellation is transport-neutral: AbortSignal must notify the parent even
# when a completed Promise settlement will defer freeing the win_load object.
void win_load_cancel(win_load* load):
	if (load == 0): return
	win_broker_forget(load)
	if (load.child != 0):
		process_free(load.child)
		load.child = 0
	load.finished = 1

void win_load_free(win_load* load):
	if (load == 0): return
	win_broker_forget(load)
	if (load.child != 0): process_free(load.child)
	string_free(load.output)
	if (load.outgoing != 0): string_free(load.outgoing)
	free(load.request_address)
	free(load.kind)
	if (load.error != 0): free(load.error)
	if (load.address != 0): free(load.address)
	free(load)

int win_broker_kind(char* kind):
	if (strcmp(kind, c"document") == 0): return 1
	if (strcmp(kind, c"css") == 0): return 2
	if (strcmp(kind, c"script") == 0): return 3
	if (strcmp(kind, c"image") == 0): return 4
	if (strcmp(kind, c"fetch") == 0): return 5
	return 0

char* win_broker_kind_name(int kind):
	if (kind == 1): return c"document"
	if (kind == 2): return c"css"
	if (kind == 3): return c"script"
	if (kind == 4): return c"image"
	return c"fetch"

win_load* win_broker_load_start(win_load* load, char* address, char* kind, char* method, char* body, int body_length, char* content_type, char* accept):
	if (win_broker_client.failed || win_broker_sequence >= WIN_BROKER_REQUESTS || win_broker_loads.length >= 16 || strlen(address) > WIN_ADDRESS_LIMIT || win_broker_kind(kind) == 0 || strlen(method) > 32 || strlen(content_type) > 1024 || strlen(accept) > 1024 || body_length < 0 || body_length > WIN_FETCH_REQUEST_LIMIT):
		load.error = strclone(c"Sandbox broker request limit exceeded")
		load.finished = 1
		return load
	win_broker_sequence = win_broker_sequence + 1
	load.broker_id = win_broker_sequence
	win_broker_loads.push(load)
	string_builder* request = win_broker_packet(load.broker_id, 1)
	for i in range(24): string_append_char(request, 0)
	save_int32(request.data + 24, win_broker_kind(kind))
	save_int32(request.data + 28, strlen(address))
	save_int32(request.data + 32, strlen(method))
	save_int32(request.data + 36, strlen(content_type))
	save_int32(request.data + 40, strlen(accept))
	save_int32(request.data + 44, body_length)
	string_append(request, address)
	string_append(request, method)
	string_append(request, content_type)
	string_append(request, accept)
	string_append_bytes(request, body, body_length)
	win_broker_queue(win_broker_client, request)
	string_free(request)
	return load

void win_broker_client_poll():
	if (win_broker_client == 0): return
	win_broker_pump(win_broker_client)
	if (win_broker_complete(win_broker_client)):
		char* data = win_broker_client.input.data
		int length = win_broker_client.input.length
		int id = load_int32(data + 12)
		if (load_int32(data + 16) != 3 || length < 40): win_broker_client.failed = 1
		else:
			int error = load_int32(data + 24)
			int status = load_int32(data + 28)
			int mime = load_int32(data + 32)
			int address_length = load_int32(data + 36)
			if (error < 0 || error > 1 || status < 0 || status > 599 || mime < 0 || mime > 1 || address_length < 0 || address_length > WIN_ADDRESS_LIMIT || address_length > length - 40): win_broker_client.failed = 1
			else:
				for win_load* load in win_broker_loads:
					if (load.broker_id != id): continue
					load.finished = 1
					if (error): load.error = strclone(c"Sandbox broker refused or failed resource request")
					else:
						load.address = str_copy_range(data, 40, 40 + address_length)
						load.status = status
						load.wasm_mime = mime
						string_append_bytes(load.output, data + 40 + address_length, length - 40 - address_length)
						load.source = load.output.data
						load.length = load.output.length
		string_clear(win_broker_client.input)
	if (win_broker_client.failed):
		for win_load* load in win_broker_loads:
			if (load.finished): continue
			load.finished = 1
			load.error = strclone(c"Sandbox broker disconnected or violated protocol")

win_load* win_load_start_network_bytes(char* executable, char* address, char* kind, char* method, char* body, int body_length, char* content_type, char* accept, char* origin):
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
	if (strcmp(kind, c"fetch") == 0): load.limit = WIN_FETCH_LIMIT
	load.status = 0
	load.cache_expires = 0
	load.cache_allowed = strcmp(method, c"GET") == 0
	if (strcmp(kind, c"fetch") == 0 && (content_type[0] != 0 || strcmp(accept, c"*/*") != 0)): load.cache_allowed = 0
	load.request_address = win_without_fragment(address)
	load.kind = strclone(kind)
	load.child = 0
	if (win_sandbox_origin != 0):
		URL* allowed_origin = url_parse(win_sandbox_origin)
		URL* target = url_parse(address)
		int allowed = allowed_origin != 0 && target != 0 && url_same_origin(allowed_origin, target)
		if (allowed_origin != 0): url_free(allowed_origin)
		if (target != 0): url_free(target)
		if (allowed == 0):
			load.error = strclone(c"Sandbox broker requires its configured HTTP(S) origin.")
			load.finished = 1
			return load
		origin = win_sandbox_origin
	if (win_broker_client != 0):
		return win_broker_load_start(load, address, kind, method, body, body_length, content_type, accept)
	if (win_sandbox_requested() && win_sandbox_origin == 0 && win_remote(address)):
		load.error = strclone(c"Offline sandbox does not permit network resources.")
		load.finished = 1
		return load
	if (strcmp(method, c"GET") != 0): win_cache_clear()
	if (strcmp(kind, c"fetch") == 0):
		URL* from = url_parse(origin)
		URL* to = url_parse(address)
		int allowed = from != 0 && to != 0 && url_same_origin(from, to) && win_fetch_method(method) && body_length >= 0 && body_length <= WIN_FETCH_REQUEST_LIMIT && win_fetch_header_value(content_type, strlen(content_type)) && win_fetch_header_value(accept, strlen(accept))
		if (from != 0): url_free(from)
		if (to != 0): url_free(to)
		if (allowed == 0):
			load.error = strclone(c"Fetch requires a bounded same-origin HTTP(S) request.")
			load.finished = 1
			return load
	win_cache_entry* cached = 0
	if (load.cache_allowed): cached = win_cache_find(load.request_address, kind)
	if (cached != 0):
		string_append_bytes(load.output, cached.source, cached.length)
		load.source = load.output.data
		load.length = cached.length
		load.address = strclone(address)
		load.status = 200
		load.wasm_mime = cached.wasm_mime
		load.finished = 1
		return load
	if (strcmp(kind, c"image") == 0): load.limit = WIN_IMAGE_RGBA_LIMIT + 8
	spawn_options* opts = spawn_options_new()
	opts.stdin_mode = process_null
	opts.stdout_mode = process_pipe
	if (win_sandbox_requested()): opts.stderr_mode = process_null
	opts.new_group = 1
	char*[12] argv
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
	if (win_sandbox_requested() && win_sandbox_origin == 0):
		argv[9] = c"--sandbox-root"
		argv[10] = win_sandbox_root
		argv[11] = 0
	char* snapshot = win_cookie_snapshot()
	char** cookie_env = env_copy_with(env_current(), c"WIN_COOKIE_SNAPSHOT", snapshot)
	char** worker_env = env_copy_with(cookie_env, c"WIN_FETCH_ORIGIN", origin)
	opts.env = worker_env
	char** sandbox_env = 0
	if (win_sandbox_requested() && win_sandbox_origin == 0):
		sandbox_env = win_sandbox_environment(getpid())
		opts.env = sandbox_env
	if (strcmp(kind, c"fetch") == 0):
		# A socketpair permits nonblocking bounded writes with MSG_NOSIGNAL;
		# it is mapped to worker stdin/stdout without changing signal handlers.
		char[8] pair
		if (syscall7(53, 1, 1 | 524288, 0, cast(int, &pair[0]), 0, 0) >= 0):
			int parent_fd = load_int32(&pair[0])
			int child_fd = load_int32(&pair[4])
			argv[8] = c""
			int pid = fork()
			if (pid == 0):
				setpgid(0, 0)
				close(parent_fd)
				process_redirect(child_fd, 0)
				dup2(0, 1)
				process_close_from(3)
				execve(executable, &argv[0], opts.env)
				exit(127)
			close(child_fd)
			if (pid < 0): close(parent_fd)
			else:
				setpgid(pid, pid)
				load.child = new process()
				load.child.pid = pid
				load.child.stdin_fd = -1
				load.child.stdout_fd = parent_fd
				load.child.stderr_fd = -1
				if (socket_set_nonblocking(parent_fd) < 0):
					process_free(load.child)
					load.child = 0
		if (load.child != 0):
			load.outgoing = string_from(c"WFET0001")
			for i in range(16): string_append_char(load.outgoing, 0)
			save_int32(load.outgoing.data + 8, strlen(method))
			save_int32(load.outgoing.data + 12, strlen(content_type))
			save_int32(load.outgoing.data + 16, strlen(accept))
			save_int32(load.outgoing.data + 20, body_length)
			string_append(load.outgoing, method)
			string_append(load.outgoing, content_type)
			string_append(load.outgoing, accept)
			string_append_bytes(load.outgoing, body, body_length)
	else: load.child = process_spawn(executable, &argv[0], opts)
	for i in range(env_vector_count(worker_env)):
		char* entry = env_entry_at(worker_env, i)
		if (env_match_name(entry, c"WIN_FETCH_ORIGIN") >= 0): free(entry)
	for i in range(env_vector_count(cookie_env)):
		char* entry = env_entry_at(cookie_env, i)
		if (env_match_name(entry, c"WIN_COOKIE_SNAPSHOT") >= 0): free(entry)
	free(cast(void*, worker_env))
	free(cast(void*, cookie_env))
	free(snapshot)
	if (sandbox_env != 0): win_sandbox_environment_free(sandbox_env)
	free(opts)
	if (load.child == 0):
		load.error = strclone(c"Cannot start resource loader.")
		load.finished = 1
	return load

win_load* win_load_start_network(char* executable, char* address, char* kind, char* method, char* body, char* origin):
	return win_load_start_network_bytes(executable, address, kind, method, body, strlen(body), c"", c"*/*", origin)

win_load* win_load_start_fetch_bytes(char* executable, char* address, char* origin, char* method, char* body, int length, char* content_type, char* accept):
	return win_load_start_network_bytes(executable, address, c"fetch", method, body, length, content_type, accept, origin)

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
	win_load_cancel(load)
	load.error = strclone(error)

int win_load_poll(win_load* load):
	if (load.broker_id):
		win_broker_client_poll()
		if (load.finished == 0 && time_monotonic_ms() - load.started > 15000):
			win_broker_forget(load)
			load.error = strclone(c"Sandbox broker request timed out")
			load.finished = 1
		return load.finished
	if (load.finished): return 1
	if (time_monotonic_ms() - load.started > 12000):
		win_load_fail(load, c"Document loading timed out.")
		return 1
	if (load.outgoing != 0):
		# At most 64 KiB per frame; peer death cannot raise SIGPIPE.
		for i in range(8):
			int count = load.outgoing.length - load.sent
			if (count > 8192): count = 8192
			int wrote = socket_send(load.child.stdout_fd, load.outgoing.data + load.sent, count, 16384)
			if (wrote == -11 || wrote == -4): break
			if (wrote <= 0):
				win_load_fail(load, c"Fetch request write failed")
				return 1
			load.sent = load.sent + wrote
			if (load.sent == load.outgoing.length):
				io_result closed
				socket_shutdown_checked(load.child.stdout_fd, 1, &closed)
				string_free(load.outgoing)
				load.outgoing = 0
				break
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
		if (count == -4 || count == -11): break
		if (count < 0):
			win_load_fail(load, c"Loader read failed.")
			return 1
		if (count == 0):
			load.eof = 1
			break
		if (load.output.length + count > load.limit + WIN_ADDRESS_LIMIT + 4 + WIN_LOADER_METADATA_LIMIT):
			win_load_fail(load, c"Document exceeds the loading limit.")
			return 1
		string_append_bytes(load.output, &chunk[0], count)
	if (load.eof == 0): return 0
	int status = process_try_wait(load.child)
	if (status == process_status_running): return 0
	load.finished = 1
	char* data = load.output.data
	int metadata_bytes = 0
	int metadata_error = 0
	int cookie_bytes = 0
	int other_metadata_bytes = 0
	# Array sizes mirror WIN_COOKIE_COUNT; imported constants are not array bounds.
	char*[32] cookie_urls
	char*[32] cookie_headers
	int cookie_count = 0
	# Metadata precedes the existing OK/ERROR envelope, including redirect
	# cookies. Only complete, bounded lines are accepted after child exit.
	while (starts_with(data, c"COOKIE\n") || starts_with(data, c"STATUS\n") || starts_with(data, c"CACHE\n") || starts_with(data, c"WASM-MIME\n")):
		int cookie_record = starts_with(data, c"COOKIE\n")
		int status_record = starts_with(data, c"STATUS\n")
		int mime_record = starts_with(data, c"WASM-MIME\n")
		int start = 6
		if (cookie_record || status_record): start = 7
		if (mime_record): start = 10
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
			consumed = end + 1
			cookie_bytes = cookie_bytes + consumed
			if (cookie_count >= WIN_COOKIE_COUNT || strlen(value) > WIN_ADDRESS_LIMIT || strlen(header) > WIN_COOKIE_LIMIT || cookie_bytes > WIN_LOADER_COOKIE_METADATA_LIMIT):
				metadata_error = 1
				free(header)
			else:
				cookie_urls[cookie_count] = strclone(value)
				cookie_headers[cookie_count] = header
				cookie_count = cookie_count + 1
		else if (status_record):
			load.status = win_net_decimal(value, 599)
			if (load.status < 0): metadata_error = 1
		else if (mime_record):
			load.wasm_mime = strcmp(value, c"1") == 0
			if (load.wasm_mime == 0 && strcmp(value, c"0") != 0): metadata_error = 1
		else:
			int lifetime = win_net_decimal(value, 86400)
			if (lifetime < 0): metadata_error = 1
			if (lifetime > 0): load.cache_expires = time_now() + lifetime - (time_monotonic_ms() - load.started + 999) / 1000
		if (cookie_record == 0):
			other_metadata_bytes = other_metadata_bytes + consumed
			if (other_metadata_bytes > 1024): metadata_error = 1
		free(value)
		data = data + consumed
		metadata_bytes = metadata_bytes + consumed
	if (metadata_error): load.error = strclone(c"Invalid loader metadata.")
	else if (starts_with(data, c"ERROR\n")): load.error = strclone(data + 6)
	else if (status != 0 || starts_with(data, c"OK\n") == 0): load.error = strclone(c"Resource loader exited unsuccessfully.")
	else:
		int end = 3
		while (end < load.output.length - metadata_bytes && data[end] != 10): end = end + 1
		if (end >= load.output.length - metadata_bytes || end - 3 > WIN_ADDRESS_LIMIT): load.error = strclone(c"Invalid loader response.")
		else:
			load.address = substring(data, 3, end)
			load.source = data + end + 1
			load.length = load.output.length - metadata_bytes - end - 1
			if (load.length > load.limit):
				load.error = strclone(c"Document exceeds the loading limit.")
				load.source = 0
				load.length = 0
	int valid_protocol = metadata_error == 0 && ((status == 0 && load.error == 0) || (status == 1 && starts_with(data, c"ERROR\n")))
	for i in range(cookie_count):
		if (valid_protocol): win_cookie_set(cookie_urls[i], cookie_headers[i])
		free(cookie_urls[i])
		free(cookie_headers[i])
	if (load.error == 0 && load.cache_allowed && load.cache_expires > 0):
		win_cache_store(load.request_address, load.kind, load.source, load.length, load.cache_expires)
		win_cache_entry* stored = win_cache_find(load.request_address, load.kind)
		if (stored != 0): stored.wasm_mime = load.wasm_mime
	return 1
