# Linux loader process. Network/file reads never block the UI thread. The
# parent polls a bounded pipe and destroys the old child on stop/navigation.
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

int win_fetch_worker(char* address):
	if (win_remote(address)):
		compress_codecs_register()
		http_client* client = http_client_new()
		http_req* req = http_req_new(c"GET", address)
		req.client = client
		req.total_timeout_ms = 10000
		req.max_redirects = 5
		req.max_stream_bytes = WIN_SOURCE_LIMIT
		http_req_add_header(req, c"Accept", c"text/html")
		http_req_add_header(req, c"Accept-Encoding", c"gzip, deflate")
		http_stream* stream = http_open(req)
		content_decoder* content = http_content_collect(stream, WIN_SOURCE_LIMIT, WIN_SOURCE_LIMIT)
		int code = 1
		if (content.status != content_decode_done):
			if (stream.resp.error != 0): code = win_worker_error(stream.resp.error_message)
			else: code = win_worker_error(c"Unsupported, invalid or oversized content encoding.")
		else if (stream.resp.status < 200 || stream.resp.status >= 300): code = win_worker_error(c"Server returned an unsuccessful HTTP status.")
		else:
			char* mime = http_response_header(stream.resp, c"content-type")
			if (mime != 0 && starts_with(mime, c"text/html") == 0): code = win_worker_error(c"This version opens HTML documents only.")
			else: code = win_worker_ok(stream.resp.final_url, content.output, content.output_length)
		content_decoder_free(content)
		http_stream_close(stream)
		http_req_free(req)
		http_client_free(client)
		return code
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
		if (source.length + count > WIN_SOURCE_LIMIT):
			failed = 1
			break
		string_append_bytes(source, &chunk[0], count)
	close(fd)
	int code = 1
	if (failed): code = win_worker_error(c"Local file read failed or exceeded 1 MiB.")
	else: code = win_worker_ok(address, source.data, source.length)
	string_free(source)
	return code

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

void win_load_free(win_load* load):
	if (load == 0): return
	if (load.child != 0): process_free(load.child)
	string_free(load.output)
	if (load.error != 0): free(load.error)
	if (load.address != 0): free(load.address)
	free(load)

win_load* win_load_start(char* executable, char* address):
	win_load* load = new win_load()
	load.output = string_new()
	load.started = time_monotonic_ms()
	load.eof = 0
	load.finished = 0
	load.error = 0
	load.address = 0
	load.source = 0
	load.length = 0
	spawn_options* opts = spawn_options_new()
	opts.stdin_mode = process_null
	opts.stdout_mode = process_pipe
	opts.new_group = 1
	char*[4] argv
	argv[0] = executable
	argv[1] = c"--fetch"
	argv[2] = address
	argv[3] = 0
	load.child = process_spawn(executable, &argv[0], opts)
	free(opts)
	if (load.child == 0):
		load.error = strclone(c"Cannot start resource loader.")
		load.finished = 1
	return load

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
		if (load.output.length + count > WIN_SOURCE_LIMIT + WIN_ADDRESS_LIMIT + 16):
			win_load_fail(load, c"Document exceeds the loading limit.")
			return 1
		string_append_bytes(load.output, &chunk[0], count)
	if (load.eof == 0): return 0
	int status = process_try_wait(load.child)
	if (status == process_status_running): return 0
	load.finished = 1
	char* data = load.output.data
	if (starts_with(data, c"ERROR\n")): load.error = strclone(data + 6)
	else if (status != 0 || starts_with(data, c"OK\n") == 0): load.error = strclone(c"Resource loader exited unsuccessfully.")
	else:
		int end = 3
		while (end < load.output.length && data[end] != 10): end = end + 1
		if (end >= load.output.length || end - 3 > WIN_ADDRESS_LIMIT): load.error = strclone(c"Invalid loader response.")
		else:
			load.address = substring(data, 3, end)
			load.source = data + end + 1
			load.length = load.output.length - end - 1
	return 1
